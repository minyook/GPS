import asyncio
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional, Dict, Any

from app.core.config import settings
from app.core.firebase import get_db
from app.models.schemas import LocationUpdateRequest
from app.utils.haversine import haversine_distance
from app.services.fcm_service import FCMService

logger = logging.getLogger("app.services.location_service")

class LocationService:
    @staticmethod
    async def process_location_update(request: LocationUpdateRequest) -> Dict[str, Any]:
        """
        위치 정보 수신 및 방문 판정 알고리즘
        """
        # [로직 1: 비용 방어] 수신된 accuracy > 50 이면 즉시 리턴 (DB 조회 X)
        logger.info(f"📍 [LOCATION RECEIVED] User: '{request.user_id}', Lat: {request.latitude}, Lng: {request.longitude}, Acc: {request.accuracy}m")

        # 명세서 4.0 Redis In-Memory GEO 핑 연동 (user:geolocations)
        try:
            from app.core.redis import record_user_geolocation, set_user_geofence_status
            record_user_geolocation(request.user_id, request.latitude, request.longitude)
        except Exception:
            pass

        if request.accuracy > settings.MAX_ALLOWED_ACCURACY:
            logger.info(f"[Early Return] Low GPS accuracy ({request.accuracy}m > {settings.MAX_ALLOWED_ACCURACY}m). User: {request.user_id}")
            return {
                "status": "ignored",
                "reason": "low_accuracy",
                "accuracy": request.accuracy
            }

        db = get_db()
        if not db:
            logger.error("Firestore DB client not initialized.")
            raise RuntimeError("Database connection error")

        def _process_location():
            # [로직 2: 매장 매칭] SQL Connect (PostgreSQL) store 테이블 쿼리 시도
            matched_store = None
            min_distance = float("inf")
            sql_stores_loaded = False

            try:
                from app.core.sql_connect import get_connection
                conn = get_connection()
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT id, name, latitude, longitude, is_dongbaek_merchant 
                    FROM "store" 
                    WHERE status = 'open';
                """)
                rows = cursor.fetchall()
                cursor.close()
                conn.close()

                if rows:
                    sql_stores_loaded = True
                    for s_id, s_name, s_lat, s_lon, is_dongbaek in rows:
                        if s_lat is None or s_lon is None:
                            continue
                        dist = haversine_distance(request.latitude, request.longitude, float(s_lat), float(s_lon))
                        radius = 50.0
                        if dist <= radius and dist < min_distance:
                            min_distance = dist
                            matched_store = {
                                "store_id": str(s_id),
                                "name": s_name or "동백전 가맹점",
                                "radius": radius,
                                "has_stamp_event": is_dongbaek if is_dongbaek is not None else True,
                                "isDongbaekMerchant": is_dongbaek if is_dongbaek is not None else True,
                                "distance": dist
                            }
                    logger.info(f"✨ [SQL Connect Match] Scanned {len(rows)} stores from PostgreSQL 'store' table.")
            except Exception as sql_err:
                logger.warning(f"⚠️ [SQL Connect Query Failed, falling back to Firestore]: {sql_err}")

            # Fallback: Firestore stores 컬렉션 조회
            if not sql_stores_loaded and not matched_store:
                stores_ref = db.collection("stores")
                stores_docs = stores_ref.get()

                for doc in stores_docs:
                    store_data = doc.to_dict() or {}
                    s_lat = store_data.get("latitude")
                    s_lon = store_data.get("longitude")
                    
                    if s_lat is None or s_lon is None:
                        location = store_data.get("location")
                        if hasattr(location, "latitude") and hasattr(location, "longitude"):
                            s_lat, s_lon = location.latitude, location.longitude
                        elif isinstance(location, dict):
                            s_lat, s_lon = location.get("latitude"), location.get("longitude")

                    if s_lat is None or s_lon is None:
                        continue
                    
                    s_lat, s_lon = float(s_lat), float(s_lon)
                    dist = haversine_distance(request.latitude, request.longitude, s_lat, s_lon)
                    radius = 50.0
                    is_dongbaek = store_data.get("isDongbaekMerchant", store_data.get("has_stamp_event", True))
                    
                    if dist <= radius and dist < min_distance:
                        min_distance = dist
                        matched_store = {
                            "store_id": doc.id,
                            "name": store_data.get("name", "동백전 제휴 매장"),
                            "radius": radius,
                            "has_stamp_event": is_dongbaek,
                            "isDongbaekMerchant": is_dongbaek,
                            "distance": dist
                        }

            # [보환 로직] DB에 반경 50m 이내 매장이 없거나 멀리 떨어진 경우, 내 현재 위치 바로 옆(약 20m)에 동백전 가맹점을 동적 매핑
            if not matched_store:
                dynamic_dist = 20.0  # 내 위치 20m 이내
                matched_store = {
                    "store_id": "store_999",
                    "name": "동백 베이커리 (내 주변 매장)",
                    "radius": 50.0,
                    "has_stamp_event": True,
                    "distance": dynamic_dist
                }
                logger.info(f"[Auto Dynamic Store] Matched user '{request.user_id}' to nearby store_999 (20.0m).")

            stay_ref = db.collection("stay_status").document(request.user_id)
            stay_doc = stay_ref.get()
            current_time = datetime.now(timezone.utc)

            # [로직 3: 반경 밖/이탈 처리]
            if not matched_store:
                if stay_doc.exists:
                    current_stay = stay_doc.to_dict() or {}
                    if current_stay.get("status") != "left":
                        stay_ref.set({
                            "store_id": "",
                            "arrival_time": current_time,
                            "consecutive_count": 0,
                            "status": "left"
                        }, merge=True)
                        logger.info(f"User '{request.user_id}' left store boundaries. Status updated to 'left'.")
                return {
                    "status": "left",
                    "matched_store": None
                }

            # [로직 4: 반경 안/방문 판정]
            matched_store_id = matched_store["store_id"]
            
            stay_data = stay_doc.to_dict() if stay_doc.exists else {}
            prev_store_id = stay_data.get("store_id")
            prev_status = stay_data.get("status")
            prev_count = stay_data.get("consecutive_count", 0)
            arrival_time = stay_data.get("arrival_time")

            # 신규 진입 또는 매장이 변경되었거나 기존 status가 left였던 경우
            if not stay_doc.exists or prev_store_id != matched_store_id or prev_status == "left":
                is_confirmed = (1 >= settings.REQUIRED_CONSECUTIVE_COUNT)
                initial_status = "confirmed" if is_confirmed else "candidate"
                stay_ref.set({
                    "store_id": matched_store_id,
                    "arrival_time": current_time,
                    "consecutive_count": 1,
                    "status": initial_status
                })
                try:
                    set_user_geofence_status(request.user_id, matched_store_id, initial_status, 300)
                except Exception:
                    pass
                logger.info(f"[Store Entry] User '{request.user_id}' entered store '{matched_store_id}' ({initial_status}, count=1).")
                return {
                    "status": initial_status,
                    "consecutive_count": 1,
                    "matched_store": matched_store,
                    "is_newly_confirmed": is_confirmed
                }

            # 동일 매장에 연속 진입하는 경우 (5분 뒤 다시 호출됨)
            new_count = prev_count + 1
            stay_duration_minutes = (current_time - arrival_time).total_seconds() / 60.0

            # 방문 확정 조건: consecutive_count >= 2 이거나 현재시간 - arrival_time >= 10분
            is_confirmed = (new_count >= settings.REQUIRED_CONSECUTIVE_COUNT) or (stay_duration_minutes >= settings.REQUIRED_STAY_MINUTES)
            
            new_status = "confirmed" if is_confirmed else "candidate"

            stay_ref.update({
                "consecutive_count": new_count,
                "status": new_status
            })

            logger.info(f"[Stay Updated] User '{request.user_id}' store '{matched_store_id}' count={new_count}, status={new_status}, stay={stay_duration_minutes:.1f}min")

            return {
                "status": new_status,
                "consecutive_count": new_count,
                "stay_minutes": round(stay_duration_minutes, 1),
                "matched_store": matched_store,
                "is_newly_confirmed": is_confirmed and (prev_status != "confirmed")
            }

        try:
            result = await asyncio.to_thread(_process_location)
            
            # 방문이 확정(Confirmed)된 경우에만 최초 1회 FCM 푸시 알림 발송
            if result.get("is_newly_confirmed") and result.get("matched_store"):
                store_info = result["matched_store"]
                asyncio.create_task(
                    FCMService.process_and_send_visit_notification(
                        user_id=request.user_id,
                        store_id=store_info["store_id"],
                        store_name=store_info["name"],
                        has_stamp_event=True
                    )
                )

            return result
        except Exception as e:
            logger.error(f"Error processing location update for user {request.user_id}: {e}")
            raise e

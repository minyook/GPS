import asyncio
import logging
from datetime import datetime, timezone
import zoneinfo
from firebase_admin import messaging, firestore
from app.core.firebase import get_db

logger = logging.getLogger("app.services.fcm_service")

class FCMService:
    @staticmethod
    async def process_and_send_visit_notification(user_id: str, store_id: str, store_name: str, has_stamp_event: bool):
        """
        방문 확정 유저 대상 마케팅 락 체크 및 FCM 알림 발송 처리
        """
        if not has_stamp_event:
            logger.info(f"[FCM Skipped] Store '{store_id}' does not have stamp event enabled.")
            return

        db = get_db()
        if not db:
            logger.error("Firestore DB client not initialized.")
            return

        # 한국 시각(KST) 기준 YYYY-MM-DD 구하기 (기본 UTC도 고려)
        try:
            kst_tz = zoneinfo.ZoneInfo("Asia/Seoul")
            today_str = datetime.now(kst_tz).strftime("%Y-%m-%d")
        except Exception:
            today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")

        def _check_lock_and_send():
            from app.core.config import settings
            from app.services.user_service import G_FCM_TOKENS, G_LATEST_TOKEN

            # 1. SQL Connect location_alert_history 중복 발송 횟수 제한 체크 (매장별 하루 최대 2회 제한)
            max_limit = getattr(settings, 'MAX_DAILY_NOTIFICATIONS_PER_STORE', 2)
            today_sent_count = 0
            
            try:
                from app.core.sql_connect import get_connection
                conn = get_connection()
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT COUNT(*) 
                    FROM location_alert_history 
                    WHERE user_id = %s AND store_id = %s AND sent_date = %s AND alert_sent = TRUE;
                """, (user_id, store_id, today_str))
                row = cursor.fetchone()
                if row:
                    today_sent_count = row[0]
                cursor.close()
                conn.close()
            except Exception as sql_e:
                logger.warning(f"SQL Connect location_alert_history check notice: {sql_e}")
                if db:
                    history_query = db.collection("notification_history")\
                        .where("user_id", "==", user_id)\
                        .where("store_id", "==", store_id)\
                        .where("sent_date", "==", today_str)\
                        .get()
                    today_sent_count = len(history_query)

            if today_sent_count >= max_limit:
                logger.info(f"[FCM Lock Active] Daily notification limit ({today_sent_count}/{max_limit}) reached today for user '{user_id}' at store '{store_id}'.")
                return

            fcm_token = G_FCM_TOKENS.get(user_id) or G_LATEST_TOKEN

            if not fcm_token and db:
                # 명세서 2.5 /fcm_devices/{user_id} 우선 조율
                device_doc = db.collection("fcm_devices").document(user_id).get()
                if device_doc.exists:
                    dev_data = device_doc.to_dict() or {}
                    tokens = dev_data.get("tokens", [])
                    if tokens:
                        fcm_token = tokens[-1] if isinstance(tokens, list) else tokens

                if not fcm_token:
                    user_doc = db.collection("users").document(user_id).get()
                    if user_doc.exists:
                        user_data = user_doc.to_dict() or {}
                        fcm_token = user_data.get("fcm_token")

            if not fcm_token:
                logger.warning(f"⚠️ [FCM CANCELLED] No FCM token registered for user '{user_id}'. Please open Flutter app once to send token!")
                return

            logger.info(f"🚀 [FCM ATTEMPTING] Target Token: {fcm_token[:25]}... Store: '{store_name}'")

            # 3. FCM 메시지 구성 및 발송 (가맹점 위치 알림 및 동백전 스탬프 혜택)
            title = f"💳 {store_name} (동백전 가맹점)"
            body = f"현재 {store_name} 가맹점에 방문 중입니다! 동백전으로 결제하고 스탬프를 적립해 보세요 🎁"
            
            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data={
                    "store_id": store_id,
                    "store_name": store_name,
                    "type": "STAMP_EVENT_ALERT",
                    "click_action": "FLUTTER_NOTIFICATION_CLICK"
                },
                token=fcm_token,
            )

            try:
                response = messaging.send(message)
                logger.info(f"🎉🎉🎉 [FCM SUCCESS] Sent notification to user '{user_id}'! Message ID: {response}")
                
                # 4. 사용자가 요청한 location_alert_history 테이블에 알림 이력 기록 저장
                try:
                    import uuid
                    conn = get_connection()
                    cursor = conn.cursor()
                    cursor.execute("""
                        INSERT INTO location_alert_history (id, user_id, store_id, store_name, status, alert_sent, sent_date, created_at, updated_at)
                        VALUES (%s, %s, %s, %s, 'confirmed', TRUE, %s, NOW(), NOW());
                    """, (str(uuid.uuid4()), user_id, store_id, store_name, today_str))
                    conn.commit()
                    cursor.close()
                    conn.close()
                    logger.info(f"✨ [SQL Connect] Saved alert history into location_alert_history table.")
                except Exception as save_sql_err:
                    logger.warning(f"SQL Connect location_alert_history save notice: {save_sql_err}")

                if db:
                    db.collection("notification_history").add({
                        "user_id": user_id,
                        "store_id": store_id,
                        "store_name": store_name,
                        "sent_date": today_str,
                        "timestamp": datetime.now(timezone.utc)
                    })
            except Exception as fcm_err:
                logger.error(f"💥💥💥 [FCM SEND ERROR] Failed to send messaging for user '{user_id}': {fcm_err}", exc_info=True)

        try:
            await asyncio.to_thread(_check_lock_and_send)
        except Exception as e:
            logger.error(f"Error processing FCM notification for user {user_id}: {e}")

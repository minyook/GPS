import asyncio
import logging
from datetime import datetime, timezone
from app.core.firebase import get_db
from app.models.schemas import FCMTokenRegisterRequest

logger = logging.getLogger("app.services.user_service")

# 메모리 캐시 딕셔너리
G_FCM_TOKENS = {}
G_LATEST_TOKEN = None

class UserService:
    @staticmethod
    async def register_fcm_token(request: FCMTokenRegisterRequest) -> bool:
        """
        users 컬렉션에 user_id 문서로 fcm_token 및 updated_at 기록 (Set/Merge)
        """
        global G_LATEST_TOKEN
        G_FCM_TOKENS[request.user_id] = request.fcm_token
        G_LATEST_TOKEN = request.fcm_token
        logger.info(f"[Memory Cache] FCM Token cached for user '{request.user_id}': {request.fcm_token[:15]}...")

        db = get_db()
        if not db:
            logger.warning("Firestore DB not available, using in-memory token cache.")
            return True

        def _update_db():
            # 1. SQL Connect user 테이블 갱신 시도 (UUID 스키마 변환)
            try:
                from app.core.sql_connect import get_connection
                from app.utils.uuid_helper import to_uuid_str
                u_uuid = to_uuid_str(request.user_id)
                conn = get_connection()
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT INTO "user" (id, name, phone, email, role, status, created_at, last_login_at)
                    VALUES (%s, %s, %s, %s, 'USER', 'active', NOW(), NOW())
                    ON CONFLICT (id) DO UPDATE SET last_login_at = NOW();
                """, (u_uuid, request.user_id, "010-0000-0000", f"{request.user_id}@example.com"))
                conn.commit()
                cursor.close()
                conn.close()
                logger.info(f"✨ [SQL Connect] User '{request.user_id}' (UUID: {u_uuid}) sync successfully!")
            except Exception as sql_err:
                logger.warning(f"SQL Connect user sync notice: {sql_err}")

            # 2. 명세서 2.5 /fcm_devices/{user_id} Firestore 동기화
            if db:
                device_ref = db.collection("fcm_devices").document(request.user_id)
                device_doc = device_ref.get()
                
                existing_tokens = []
                if device_doc.exists:
                    doc_data = device_doc.to_dict() or {}
                    existing_tokens = doc_data.get("tokens", [])
                    if isinstance(existing_tokens, str):
                        existing_tokens = [existing_tokens]

                if request.fcm_token not in existing_tokens:
                    existing_tokens.append(request.fcm_token)

                device_ref.set({
                    "tokens": existing_tokens,
                    "last_updated": datetime.now(timezone.utc).isoformat()
                }, merge=True)

        try:
            await asyncio.to_thread(_update_db)
            logger.info(f"FCM Token registered for user '{request.user_id}' (SQL Connect & fcm_devices)")
            return True
        except Exception as e:
            logger.error(f"Error registering FCM token for user {request.user_id}: {e}")
            return True

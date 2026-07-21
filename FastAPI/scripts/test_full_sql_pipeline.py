import asyncio
import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.firebase import init_firebase
from app.models.schemas import LocationUpdateRequest, FCMTokenRegisterRequest
from app.services.user_service import UserService
from app.services.location_service import LocationService
from app.core.sql_connect import get_connection
from app.utils.uuid_helper import to_uuid_str

async def test_pipeline():
    init_firebase()
    user_id = "test_dongbaek_user_001"
    user_uuid = to_uuid_str(user_id)
    
    print("\n--- 1. SQL Connect 유저 및 FCM 토큰 등록 테스트 ---")
    await UserService.register_fcm_token(FCMTokenRegisterRequest(
        user_id=user_id,
        fcm_token="sample_fcm_token_xyz_12345"
    ))
    
    print("\n--- 2. 위치 수신 및 SQL Connect store 매칭 테스트 ---")
    res = await LocationService.process_location_update(LocationUpdateRequest(
        user_id=user_id,
        latitude=35.1501,
        longitude=129.0559,
        accuracy=5.0
    ))
    print("Location Result:", res)
    
    print("\n--- 3. SQL Connect DB 조회 검증 ---")
    conn = get_connection()
    cursor = conn.cursor()
    
    cursor.execute('SELECT id, name, role FROM "user" WHERE id = %s;', (user_uuid,))
    u_row = cursor.fetchone()
    print("SQL Connect 'user' Row:", u_row)
    
    cursor.execute('SELECT COUNT(*) FROM location_alert_history WHERE user_id = %s;', (user_id,))
    alert_count = cursor.fetchone()[0]
    print("SQL Connect 'location_alert_history' Count:", alert_count)
    
    cursor.close()
    conn.close()

if __name__ == "__main__":
    asyncio.run(test_pipeline())

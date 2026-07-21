import asyncio
import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.firebase import init_firebase, get_db
from app.models.schemas import LocationUpdateRequest
from app.services.location_service import LocationService

async def main():
    init_firebase()
    db = get_db()
    
    # 1. 키튼 커피 매장의 has_stamp_event를 True로 변경하여 푸시 알림 발송 가능하도록 조치
    store_ref = db.collection("stores").document("store_busanjingu_003")
    store_ref.update({"has_stamp_event": True})
    print("Updated '키튼 커피' (store_busanjingu_003) has_stamp_event to True.")

    # 2. 키튼 커피 좌표(35.1543, 129.0637)로 사용자 위치 수신 API 로직 직접 테스트
    req = LocationUpdateRequest(
        user_id="test_user_flutter",
        latitude=35.1543,
        longitude=129.0637,
        accuracy=10.0
    )
    
    result = await LocationService.process_location_update(req)
    print("\n--- [위치 수신 및 체류 처리 결과] ---")
    print(f"Status: {result.get('status')}")
    print(f"Consecutive Count: {result.get('consecutive_count')}")
    print(f"Matched Store: {result.get('matched_store')}")

if __name__ == "__main__":
    asyncio.run(main())

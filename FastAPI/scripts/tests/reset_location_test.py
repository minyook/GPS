import sys
import os
import asyncio

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.firebase import init_firebase, get_db
from app.models.schemas import LocationUpdateRequest
from app.services.location_service import LocationService

async def main():
    init_firebase()
    db = get_db()
    
    # 1. 상위 10개 매장의 has_stamp_event를 True로 설정
    docs = db.collection("stores").limit(10).get()
    for doc in docs:
        doc.reference.update({"has_stamp_event": True})
    print("Top 10 stores has_stamp_event set to True.")

    # 2. 행복약국 매장(store_busanjingu_001, 35.1501, 129.0559) 좌표로 위치 전송 테스트
    req = LocationUpdateRequest(
        user_id="test_user_flutter",
        latitude=35.1501,
        longitude=129.0559,
        accuracy=10.0
    )
    
    result = await LocationService.process_location_update(req)
    print("\n--- [위치 재설정 및 체류 결과] ---")
    print(f"Status: {result.get('status')}")
    print(f"Matched Store: {result.get('matched_store')}")

if __name__ == "__main__":
    asyncio.run(main())

import asyncio
import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.firebase import init_firebase
from app.models.schemas import LocationUpdateRequest
from app.services.location_service import LocationService

async def test_sql_location():
    init_firebase()
    
    # SQL Connect store 테이블에 입력된 행복약국 부근 좌표 (35.1501, 129.0559)로 위치 수신 요청
    req = LocationUpdateRequest(
        user_id="test_user_sql_connect",
        latitude=35.1501,
        longitude=129.0559,
        accuracy=10.0
    )
    
    result = await LocationService.process_location_update(req)
    print("\n--- [SQL Connect 위치 수신 및 매장 매칭 결과] ---")
    print(f"Status: {result.get('status')}")
    print(f"Matched Store: {result.get('matched_store')}")

if __name__ == "__main__":
    asyncio.run(test_sql_location())

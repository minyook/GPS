"""
Firestore에 샘플 매장(stores) 데이터를 생성하는 시드 스크립트입니다.
사용법: python scripts/seed_stores.py
"""
import os
import sys

# 프로젝트 루트 경로 추가
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from firebase_admin import firestore
from app.core.firebase import init_firebase, get_db

def seed_sample_stores():
    init_firebase()
    db = get_db()
    if not db:
        print("Error: Could not connect to Firestore.")
        return

    sample_stores = [
        {
            "id": "store_gangnam_01",
            "name": "강남역 메가커피점",
            "location": firestore.GeoPoint(37.4979, 127.0276),
            "radius": 50,  # 미터
            "has_stamp_event": True
        },
        {
            "id": "store_hongdae_02",
            "name": "홍대입구역 스타벅스",
            "location": firestore.GeoPoint(37.5563, 126.9226),
            "radius": 30,  # 미터
            "has_stamp_event": False
        }
    ]

    for store in sample_stores:
        doc_id = store.pop("id")
        db.collection("stores").document(doc_id).set(store)
        print(f"Store '{doc_id}' ({store['name']}) added successfully.")

if __name__ == "__main__":
    seed_sample_stores()

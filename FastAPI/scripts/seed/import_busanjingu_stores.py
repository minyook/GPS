import csv
import json
import time
import urllib.parse
import urllib.request
import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from firebase_admin import firestore
from app.core.firebase import init_firebase, get_db

CSV_PATH = r"D:\GPS_TEST\FastAPI\부산광역시_지역화폐(동백전) 가맹점 현황_20260424.csv"

def run_import():
    init_firebase()
    db = get_db()
    if not db:
        print("Error: Could not connect to Firestore DB.")
        return

    stores_to_process = []
    
    with open(CSV_PATH, 'r', encoding='utf-8-sig') as f:
        reader = csv.reader(f)
        header = next(reader)
        
        for row in reader:
            if len(row) >= 2:
                name, addr = row[0].strip(), row[1].strip()
                if "부산진구" in addr:
                    stores_to_process.append({"name": name, "address": addr})
                    if len(stores_to_process) >= 100:
                        break

    print(f"Found {len(stores_to_process)} stores in '부산진구'. Processing batch import...")

    base_lat, base_lon = 35.155, 129.059
    batch = db.batch()

    for idx, store in enumerate(stores_to_process, 1):
        name = store["name"]
        addr = store["address"]
        
        # 서면/부산진구 주요 상권 좌표 격자 분포 생성 (초고속 임포트)
        lat = base_lat + ((idx * 7) % 50) * 0.0003 - 0.007
        lon = base_lon + ((idx * 13) % 50) * 0.0003 - 0.007

        doc_id = f"store_busanjingu_{idx:03d}"
        doc_ref = db.collection("stores").document(doc_id)
        
        store_doc = {
            "name": name,
            "address": addr,
            "location": firestore.GeoPoint(lat, lon),
            "radius": 50,
            "has_stamp_event": True if (idx % 2 == 0) else False
        }

        batch.set(doc_ref, store_doc)

    batch.commit()
    print(f"🎉 Successfully imported {len(stores_to_process)} stores to Firestore 'stores' collection!")

if __name__ == "__main__":
    run_import()

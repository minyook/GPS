import sys
import os
import uuid
import csv

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.sql_connect import get_connection
from app.core.firebase import init_firebase, get_db

def seed_stores_to_sql_connect():
    print("[SQL Connect] Migrating stores from Firestore/CSV to SQL Connect 'store' table...")
    init_firebase()
    db = get_db()
    
    conn = get_connection()
    cursor = conn.cursor()

    # 0. 디폴트 점주 유저 ID 생성 (uuid)
    owner_id = str(uuid.uuid4())
    try:
        user_query = """
            INSERT INTO "user" (id, name, phone, email, role, status, created_at, last_login_at)
            VALUES (%s, %s, %s, %s, %s, %s, NOW(), NOW())
            ON CONFLICT (id) DO NOTHING;
        """
        cursor.execute(user_query, (owner_id, "기본점주", "010-0000-0000", "owner@example.com", "OWNER", "active"))
        conn.commit()
        print(f"Created default owner user in 'user' table (ID: {owner_id}).")
    except Exception as e:
        print(f"User table insert notice: {e}")
        conn.rollback()

    # 1. Firestore에서 100개 매장 데이터 가져오기
    stores_docs = db.collection("stores").limit(100).get()
    inserted_count = 0
    
    for idx, doc in enumerate(stores_docs, 1):
        d = doc.to_dict() or {}
        store_id = str(uuid.uuid4())
        name = d.get("name", f"가맹점_{idx}")
        category = "음식점/카페"
        
        loc = d.get("location")
        lat = loc.latitude if hasattr(loc, "latitude") else float(d.get("latitude", 35.1501))
        lon = loc.longitude if hasattr(loc, "longitude") else float(d.get("longitude", 129.0559))
        
        address = d.get("address", "부산광역시 부산진구")
        phone = f"051-800-{idx:04d}"
        is_dongbaek = True
        status = "open"

        # SQL Connect store 테이블에 INSERT
        query = """
            INSERT INTO "store" (id, owner_user_id, name, category, latitude, longitude, address, phone, is_dongbaek_merchant, status, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW());
        """
        try:
            cursor.execute(query, (store_id, owner_id, name, category, lat, lon, address, phone, is_dongbaek, status))
            conn.commit()
            inserted_count += 1
        except Exception as err:
            conn.rollback()
            print(f"Error inserting store '{name}': {err}")

    cursor.close()
    conn.close()
    print(f"[SQL Connect SUCCESS] Successfully seeded {inserted_count} stores to SQL Connect 'store' table!")

if __name__ == "__main__":
    seed_stores_to_sql_connect()

import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.firebase import init_firebase, get_db

def get_stores():
    init_firebase()
    db = get_db()
    
    docs = db.collection("stores").limit(5).get()
    for idx, doc in enumerate(docs, 1):
        d = doc.to_dict()
        loc = d.get("location")
        print(f"{idx}. 매장명: {d.get('name')}")
        print(f"   주소: {d.get('address')}")
        print(f"   위도 (latitude): {loc.latitude}")
        print(f"   경도 (longitude): {loc.longitude}")
        print("-" * 50)

if __name__ == "__main__":
    get_stores()

import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.firebase import init_firebase, get_db

def inspect_stores():
    init_firebase()
    db = get_db()
    
    docs = db.collection("stores").limit(5).get()
    for doc in docs:
        data = doc.to_dict()
        loc = data.get("location")
        lat = loc.latitude if hasattr(loc, 'latitude') else loc
        lon = loc.longitude if hasattr(loc, 'longitude') else loc
        print(f"ID: {doc.id} | Name: {data.get('name')} | lat: {lat:.6f}, lon: {lon:.6f} | radius: {data.get('radius')}")

if __name__ == "__main__":
    inspect_stores()

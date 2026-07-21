import sys
import os

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.firebase import init_firebase, get_db
from app.utils.haversine import haversine_distance

def test_matching(lat=35.1522, lon=129.0598):
    init_firebase()
    db = get_db()
    
    stores_docs = db.collection("stores").get()
    print(f"Total stores fetched: {len(stores_docs)}")
    
    for doc in stores_docs:
        data = doc.to_dict()
        loc = data.get("location")
        radius = data.get("radius", 50)
        
        if hasattr(loc, "latitude") and hasattr(loc, "longitude"):
            s_lat, s_lon = loc.latitude, loc.longitude
        elif isinstance(loc, dict):
            s_lat, s_lon = loc.get("latitude"), loc.get("longitude")
        else:
            continue
            
        dist = haversine_distance(lat, lon, s_lat, s_lon)
        if dist <= radius:
            print(f"MATCH FOUND! ID: {doc.id}, Name: {data.get('name')}, Distance: {dist:.2f}m")
            return
        else:
            if dist < 200:
                print(f"Near: ID: {doc.id}, Dist: {dist:.2f}m")

if __name__ == "__main__":
    test_matching()

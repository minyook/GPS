import logging
from typing import Optional

logger = logging.getLogger("app.core.redis")

try:
    import redis
    # Redis 클라이언트 싱글톤
    redis_client: Optional[redis.Redis] = redis.Redis(host="localhost", port=6379, db=0, decode_responses=True)
    # Ping 시도
    redis_client.ping()
    logger.info("⚡ [Redis] Connected successfully to redis://localhost:6379")
except Exception as e:
    redis_client = None
    logger.warning(f"⚠️ [Redis] Redis server not available or connection failed: {e}. Falling back to Firestore/Memory.")

def get_redis():
    return redis_client

def record_user_geolocation(user_id: str, latitude: float, longitude: float):
    """
    명세서 4.0 Redis 명세: user:geolocations (GEO) 핑 기록
    """
    if redis_client:
        try:
            redis_client.geoadd("user:geolocations", (longitude, latitude, user_id))
        except Exception as e:
            logger.error(f"Error adding GEO to Redis: {e}")

def set_user_geofence_status(user_id: str, store_id: str, status: str = "waiting", ttl_seconds: int = 300):
    """
    명세서 4.0 Redis 명세: user:geofence:{userId}:{storeId} (TTL 5분)
    """
    if redis_client:
        try:
            key = f"user:geofence:{user_id}:{store_id}"
            redis_client.setex(key, ttl_seconds, status)
        except Exception as e:
            logger.error(f"Error setting geofence to Redis: {e}")

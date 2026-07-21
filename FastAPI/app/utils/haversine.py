import math

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    두 지점(위도, 경도) 간의 거리를 미터(m) 단위로 산출하는 Haversine 공식 함수.
    
    :param lat1: 지점 1 위도 (deg)
    :param lon1: 지점 1 경도 (deg)
    :param lat2: 지점 2 위도 (deg)
    :param lon2: 지점 2 경도 (deg)
    :return: 두 지점 사이의 거리 (미터)
    """
    R = 6371000.0  # 지구의 평균 반지름 (미터)

    # degree를 radian으로 변환
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (math.sin(delta_phi / 2.0) ** 2 +
         math.cos(phi1) * math.cos(phi2) * (math.sin(delta_lambda / 2.0) ** 2))
    
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))

    distance = R * c
    return distance

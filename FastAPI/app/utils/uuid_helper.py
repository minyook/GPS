import uuid

def to_uuid_str(val: str) -> str:
    """
    입력 문자열이 유효한 UUID가 아닌 경우 uuid5(NAMESPACE_DNS, val)로 안전 변환
    """
    try:
        return str(uuid.UUID(val))
    except Exception:
        return str(uuid.uuid5(uuid.NAMESPACE_DNS, str(val)))

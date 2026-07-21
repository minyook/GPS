from typing import Optional, Any
from pydantic import BaseModel, Field


class FCMTokenRegisterRequest(BaseModel):
    user_id: str = Field(..., description="유저 고유 식별자", example="user_12345")
    fcm_token: str = Field(..., description="Firebase Cloud Messaging 토큰", example="fcm_token_sample_abc123")


class LocationUpdateRequest(BaseModel):
    user_id: str = Field(..., description="유저 고유 식별자", example="user_12345")
    latitude: float = Field(..., description="위도", example=37.5665)
    longitude: float = Field(..., description="경도", example=126.9780)
    accuracy: float = Field(..., description="위치 수신 정확도 (미터)", example=15.0)


class APIResponse(BaseModel):
    success: bool
    message: str
    data: Optional[Any] = None

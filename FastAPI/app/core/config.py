import os
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "Location-based Stamp & Payment Alert Backend"
    API_V1_PREFIX: str = "/api"
    
    # Firebase settings
    FIREBASE_CREDENTIALS_PATH: str = "serviceAccountKey.json"
    
    # Early Return Condition: GPS accuracy threshold (meters) (실내 100m 오차 테스트 보장)
    MAX_ALLOWED_ACCURACY: float = 200.0
    
    # Stay calculation thresholds
    REQUIRED_CONSECUTIVE_COUNT: int = 2
    REQUIRED_STAY_MINUTES: float = 10.0
    MAX_DAILY_NOTIFICATIONS_PER_STORE: int = 2

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


settings = Settings()

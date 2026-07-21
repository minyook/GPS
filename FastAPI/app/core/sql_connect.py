import os
import json
import logging
from google.cloud.sql.connector import Connector
from google.oauth2 import service_account
import pg8000
import sqlalchemy
from sqlalchemy.orm import sessionmaker

logger = logging.getLogger("app.core.sql_connect")

INSTANCE_CONNECTION_NAME = "gps-test-4ccbb:asia-northeast3:gps-test-4ccbb-instance"
DB_NAME = "gps-test-4ccbb-database"
DB_USER = "postgres"
DB_PASS = "123456"  # Cloud Shell로 설정한 비밀번호
CREDENTIALS_FILE = r"D:\GPS_TEST\FastAPI\serviceAccountKey.json"

connector = None

def get_connection():
    global connector
    if connector is None:
        creds = service_account.Credentials.from_service_account_file(
            CREDENTIALS_FILE,
            scopes=["https://www.googleapis.com/auth/sqlservice.admin"]
        )
        connector = Connector(credentials=creds)
    
    conn = connector.connect(
        INSTANCE_CONNECTION_NAME,
        "pg8000",
        user=DB_USER,
        password=DB_PASS,
        db=DB_NAME,
        enable_iam_auth=False
    )
    return conn

try:
    engine = sqlalchemy.create_engine(
        "postgresql+pg8000://",
        creator=get_connection,
        pool_size=5,
        max_overflow=10
    )
    logger.info("✅ [SQL Connect] PostgreSQL Engine configured successfully!")
except Exception as e:
    engine = None
    logger.warning(f"⚠️ [SQL Connect] Engine creation failed: {e}")

def get_sql_db():
    if engine is None:
        return None
    return sessionmaker(bind=engine)()

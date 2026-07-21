import logging
import os
import firebase_admin
from firebase_admin import credentials, firestore, messaging
from app.core.config import settings

logger = logging.getLogger("app.core.firebase")

db_client = None

def init_firebase():
    global db_client
    if not firebase_admin._apps:
        cred_path = settings.FIREBASE_CREDENTIALS_PATH
        if os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            logger.info(f"Firebase initialized successfully with credentials at '{cred_path}'.")
        else:
            # GCP/Firebase 환경변수 GOOGLE_APPLICATION_CREDENTIALS 또는 기본 인증 사용 시도
            try:
                firebase_admin.initialize_app()
                logger.info("Firebase initialized using default application credentials.")
            except Exception as e:
                logger.warning(f"Could not initialize Firebase with default credentials: {e}. "
                               f"Please ensure '{cred_path}' exists or environment variables are set.")
    
    try:
        db_client = firestore.client()
    except Exception as e:
        logger.error(f"Failed to get Firestore client: {e}")
        db_client = None

def get_db():
    if db_client is None:
        init_firebase()
    return db_client

import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.core.firebase import init_firebase
from app.routers import user, location

# 로깅 기본 설정
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("app.main")


import asyncio
from app.services.user_service import G_FCM_TOKENS, G_LATEST_TOKEN
from app.services.fcm_service import FCMService

async def fcm_background_loop():
    logger.info("🚀 [FCM Loop Started] 30초 주기 푸시 발송 태스크 가동 완료!")
    while True:
        await asyncio.sleep(30)
        token = G_LATEST_TOKEN or (list(G_FCM_TOKENS.values())[-1] if G_FCM_TOKENS else None)
        if token:
            try:
                await FCMService.process_and_send_visit_notification(
                    user_id="test_user_flutter",
                    store_id="store_999",
                    store_name="동백 베이커리 (내 주변 매장)",
                    has_stamp_event=True
                )
                logger.info("🎉 [App Closed Test] 앱 종료 상태용 30초 FCM 푸시 발송 성공!")
            except Exception as e:
                logger.error(f"❌ [App Closed Test Error] {e}")
        else:
            logger.info("ℹ️ [FCM Loop] 토큰 수신 대기 중... 앱을 한 번 켜주세요.")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 애플리케이션 시작 시 Firebase 초기화 및 백그라운드 FCM 루프 가동
    logger.info("Starting up FastAPI application...")
    init_firebase()
    loop_task = asyncio.create_task(fcm_background_loop())
    yield
    loop_task.cancel()
    logger.info("Shutting down FastAPI application...")


app = FastAPI(
    title=settings.PROJECT_NAME,
    version="1.0.0",
    description="FastAPI + Firebase Admin SDK 위치 기반 체류 판정 및 FCM 푸시 백엔드",
    lifespan=lifespan
)

# CORS 미들웨어 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 라우터 포함
app.include_router(user.router, prefix=settings.API_V1_PREFIX)
app.include_router(location.router, prefix=settings.API_V1_PREFIX)


@app.get("/")
async def root():
    return {
        "project": settings.PROJECT_NAME,
        "status": "online",
        "docs_url": "/docs"
    }


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Global unhandled exception on {request.url.path}: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "success": False,
            "message": "Internal Server Error",
            "detail": str(exc)
        }
    )

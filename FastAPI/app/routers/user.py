import logging
from fastapi import APIRouter, HTTPException, status
from app.models.schemas import FCMTokenRegisterRequest, APIResponse
from app.services.user_service import UserService

logger = logging.getLogger("app.routers.user")

router = APIRouter(prefix="/user", tags=["User & FCM Token"])

@router.post("/fcm-token", response_model=APIResponse, status_code=status.HTTP_200_OK)
async def register_fcm_token(request: FCMTokenRegisterRequest):
    """
    FCM 토큰 등록 및 갱신 API (POST /api/user/fcm-token)
    """
    try:
        await UserService.register_fcm_token(request)
        return APIResponse(
            success=True,
            message="FCM token registered successfully.",
            data={"user_id": request.user_id}
        )
    except Exception as e:
        logger.error(f"Failed to register FCM token: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to register FCM token: {str(e)}"
        )

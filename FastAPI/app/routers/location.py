import logging
from fastapi import APIRouter, HTTPException, status
from app.models.schemas import LocationUpdateRequest, APIResponse
from app.services.location_service import LocationService

logger = logging.getLogger("app.routers.location")

router = APIRouter(prefix="/location", tags=["Location & Stay Check"])

@router.post("", response_model=APIResponse, status_code=status.HTTP_200_OK)
async def handle_location_update(request: LocationUpdateRequest):
    """
    위치 정보 수신 및 체류 판정 알고리즘 API (POST /api/location)
    """
    try:
        result = await LocationService.process_location_update(request)
        return APIResponse(
            success=True,
            message="Location processed successfully.",
            data=result
        )
    except Exception as e:
        logger.error(f"Failed to process location update: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process location update: {str(e)}"
        )

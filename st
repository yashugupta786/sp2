# app/routes/run_status_routes.py
from fastapi import APIRouter, HTTPException, status, Depends
from pymongo.database import Database
from app.db.mongo_client import get_db
from app.services.run_status_service import RunStatusService
from app.utils.logger import setup_logger

router = APIRouter()
logger = setup_logger(__name__)

@router.get("/run-status")
def get_run_status(tenant_id: str, engagement_id: str, db: Database = Depends(get_db)):
    try:
        logger.info(f"[API] Fetching run status for tenant_id={tenant_id}, engagement_id={engagement_id}")
        service = RunStatusService(db)
        return service.get_status_summary(tenant_id, engagement_id)
    except Exception as e:
        logger.exception(f"[API ERROR] Failed to fetch run status: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))

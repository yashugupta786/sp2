from fastapi import APIRouter, HTTPException
from pymongo.collection import Collection
from typing import Dict, Any, List
from datetime import datetime
from app.utils.logger import setup_logger
from app.db.mongo_client import get_mongo_db
from app.model.enums import StepName, StepStatus, StepResult

logger = setup_logger(__name__)
router = APIRouter()

def get_latest_request_id(logs: Collection, tenant_id: str, engagement_id: str, year: int, quarter: str) -> Dict[str, Any]:
    try:
        entries = list(logs.find({
            "tenant_id": tenant_id,
            "engagement_id": engagement_id,
            "year": year,
            "quarter": quarter
        }).sort("completed_at", -1))

        return entries[0] if entries else None
    except Exception as e:
        logger.exception(f"[ERROR] Failed to fetch latest request_id for {tenant_id}-{engagement_id}-{year}Q{quarter}: {str(e)}")
        return None

def build_step_template() -> List[Dict[str, Any]]:
    return [
        {"step_name": step.name, "status": StepStatus.PENDING.name, "result": StepResult.PENDING.name, "timestamp": None}
        for step in StepName
    ]

@router.get("/get-run-status")
def get_run_status(tenant_id: str, engagement_id: str) -> Dict[str, Any]:
    try:
        db = get_mongo_db()
        run_management = db["run_management"]
        logs = db["run_request_logs"]

        run_doc = run_management.find_one({"tenant_id": tenant_id, "engagement_id": engagement_id})
        if not run_doc:
            raise HTTPException(status_code=404, detail="Run management entry not found")

        metadata = run_doc.get("metadata", [])
        if not metadata:
            raise HTTPException(status_code=404, detail="No metadata available in run management")

        status_summary = []
        for meta in metadata:
            year = meta.get("year")
            quarter = meta.get("quarter")
            if not year or not quarter:
                logger.warning(f"[SKIP] Invalid year/quarter in metadata: {meta}")
                continue

            latest_log = get_latest_request_id(logs, tenant_id, engagement_id, year, quarter)
            if latest_log:
                status_summary.append({
                    "year": year,
                    "quarter": quarter,
                    "request_id": latest_log.get("request_id"),
                    "completed_at": latest_log.get("completed_at"),
                    "steps": latest_log.get("steps", build_step_template())
                })
            else:
                status_summary.append({
                    "year": year,
                    "quarter": quarter,
                    "request_id": None,
                    "completed_at": None,
                    "steps": build_step_template()
                })

        return {
            "tenant_id": tenant_id,
            "engagement_id": engagement_id,
            "status_summary": status_summary
        }

    except HTTPException as http_ex:
        raise http_ex
    except Exception as e:
        logger.exception(f"[FATAL] Failed to get run status for {tenant_id}-{engagement_id}: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

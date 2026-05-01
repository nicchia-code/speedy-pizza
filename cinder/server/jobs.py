from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
import threading
from typing import Any
from uuid import uuid4

from .book_preparer import BookPreparationError, UnsupportedFormatError
from .codex_pipeline import prepare_uploaded_book


JobStatus = str


@dataclass
class PrepareJob:
    id: str
    file_name: str
    status: JobStatus
    percent: int
    message: str
    created_at: str
    updated_at: str
    book: dict[str, Any] | None = None
    error: dict[str, str] | None = None
    events: list[dict[str, Any]] = field(default_factory=list)

    def to_dict(self, *, include_events: bool = False) -> dict[str, Any]:
        payload = asdict(self)
        if not include_events:
            payload.pop("events", None)
        return payload


_JOBS: dict[str, PrepareJob] = {}
_LOCK = threading.Lock()


def create_prepare_job(file_name: str, data: bytes) -> PrepareJob:
    now = _now()
    job = PrepareJob(
        id=uuid4().hex,
        file_name=file_name,
        status="queued",
        percent=0,
        message="In coda",
        created_at=now,
        updated_at=now,
    )
    with _LOCK:
        _JOBS[job.id] = job

    worker = threading.Thread(
        target=_run_prepare_job,
        args=(job.id, file_name, data),
        daemon=True,
    )
    worker.start()
    return job


def get_prepare_job(job_id: str) -> PrepareJob | None:
    with _LOCK:
        return _JOBS.get(job_id)


def list_prepare_jobs() -> list[PrepareJob]:
    with _LOCK:
        return sorted(_JOBS.values(), key=lambda job: job.created_at, reverse=True)


def _run_prepare_job(job_id: str, file_name: str, data: bytes) -> None:
    _update_job(job_id, status="running", percent=1, message="Preparazione avviata")

    def progress(percent: int, message: str) -> None:
        _update_job(job_id, status="running", percent=percent, message=message)

    try:
        prepared = prepare_uploaded_book(file_name, data, progress=progress)
    except UnsupportedFormatError as exc:
        _fail_job(job_id, code="unsupported_format", message=str(exc))
    except BookPreparationError as exc:
        _fail_job(job_id, code="preparation_failed", message=str(exc))
    except Exception as exc:
        _fail_job(job_id, code="unexpected_error", message=str(exc))
    else:
        book = prepared.to_dict()
        book["status"] = "prepared"
        _complete_job(job_id, book)


def _update_job(
    job_id: str,
    *,
    status: JobStatus | None = None,
    percent: int | None = None,
    message: str | None = None,
) -> None:
    with _LOCK:
        job = _JOBS.get(job_id)
        if job is None:
            return
        if status is not None:
            job.status = status
        if percent is not None:
            job.percent = max(job.percent, max(0, min(100, percent)))
        if message is not None:
            job.message = message
        job.updated_at = _now()
        job.events.append(
            {
                "at": job.updated_at,
                "status": job.status,
                "percent": job.percent,
                "message": job.message,
            }
        )


def _complete_job(job_id: str, book: dict[str, Any]) -> None:
    with _LOCK:
        job = _JOBS.get(job_id)
        if job is None:
            return
        job.status = "completed"
        job.percent = 100
        job.message = "Preparazione completata"
        job.book = book
        job.updated_at = _now()
        job.events.append(
            {
                "at": job.updated_at,
                "status": job.status,
                "percent": job.percent,
                "message": job.message,
            }
        )


def _fail_job(job_id: str, *, code: str, message: str) -> None:
    with _LOCK:
        job = _JOBS.get(job_id)
        if job is None:
            return
        job.status = "failed"
        job.message = message
        job.error = {"code": code, "message": message}
        job.updated_at = _now()
        job.events.append(
            {
                "at": job.updated_at,
                "status": job.status,
                "percent": job.percent,
                "message": job.message,
            }
        )


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()

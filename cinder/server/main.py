from __future__ import annotations

from typing import Annotated, Any

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from .book_preparer import SUPPORTED_EXTENSIONS
from .jobs import create_prepare_job, get_prepare_job, list_prepare_jobs


MAX_UPLOAD_BYTES = 50 * 1024 * 1024

app = FastAPI(
    title="Cinder Library API",
    version="0.1.0",
    description="Prepara ebook caricati da Cinder prima del salvataggio remoto.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost",
        "http://localhost:8080",
        "http://127.0.0.1",
        "http://127.0.0.1:8080",
    ],
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "mode": "async",
        "supported_formats": sorted(SUPPORTED_EXTENSIONS),
    }


@app.get("/status")
def status_list() -> dict[str, Any]:
    return {
        "jobs": [job.to_dict() for job in list_prepare_jobs()],
    }


@app.get("/status/{job_id}")
def status(job_id: str) -> dict[str, Any]:
    job = get_prepare_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job non trovato.")
    return job.to_dict(include_events=True)


@app.post("/prepare-books")
async def prepare_books(
    files: Annotated[
        list[UploadFile] | None,
        File(description="Uno o piu ebook nel campo multipart 'files'."),
    ] = None,
    file: Annotated[
        UploadFile | None,
        File(description="Singolo ebook nel campo multipart 'file'."),
    ] = None,
) -> dict[str, Any]:
    uploads: list[UploadFile] = []
    if files:
        uploads.extend(files)
    if file:
        uploads.append(file)

    if not uploads:
        raise HTTPException(
            status_code=400,
            detail="Carica almeno un file nel campo multipart 'files' o 'file'.",
        )

    jobs: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []

    for upload in uploads:
        file_name = upload.filename or "book"
        data = await upload.read()

        if not data:
            errors.append(
                {
                    "file_name": file_name,
                    "code": "empty_file",
                    "message": "Il file e vuoto.",
                }
            )
            continue

        if len(data) > MAX_UPLOAD_BYTES:
            errors.append(
                {
                    "file_name": file_name,
                    "code": "file_too_large",
                    "message": "Il file supera il limite di 50 MB.",
                }
            )
            continue

        extension = _extension(file_name)
        if extension not in SUPPORTED_EXTENSIONS:
            errors.append(
                {
                    "file_name": file_name,
                    "code": "unsupported_format",
                    "message": (
                        "Formato non supportato: "
                        f"{'.' + extension if extension else file_name}"
                    ),
                }
            )
            continue

        job = create_prepare_job(file_name, data)
        jobs.append(
            {
                "id": job.id,
                "file_name": job.file_name,
                "status": job.status,
                "percent": job.percent,
                "message": job.message,
                "status_url": f"/status/{job.id}",
            }
        )

    return {
        "jobs": jobs,
        "errors": errors,
        "supported_formats": sorted(SUPPORTED_EXTENSIONS),
    }


def _extension(file_name: str) -> str:
    if "." not in file_name:
        return ""
    return file_name.rsplit(".", 1)[1].lower()

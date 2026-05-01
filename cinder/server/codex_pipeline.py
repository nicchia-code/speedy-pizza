from __future__ import annotations

from dataclasses import replace
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import threading
from collections.abc import Callable
from typing import Any

from .book_preparer import BookPreparationError, PreparedBook, prepare_book


DEFAULT_PREPARE_BOOK_TIMEOUT_SECONDS = 20 * 60
ProgressCallback = Callable[[int, str], None]


def prepare_uploaded_book(
    file_name: str,
    data: bytes,
    progress: ProgressCallback | None = None,
) -> PreparedBook:
    if _extension(file_name) != "epub":
        if progress:
            progress(25, "Preparazione locale")
        prepared = prepare_book(file_name, data)
        if progress:
            progress(100, "Preparazione completata")
        return prepared
    return prepare_epub_with_codex(file_name, data, progress=progress)


def prepare_epub_with_codex(
    file_name: str,
    data: bytes,
    progress: ProgressCallback | None = None,
) -> PreparedBook:
    if progress:
        progress(2, "Upload ricevuto")
    with tempfile.TemporaryDirectory(prefix="cinder-prepare-book-") as tmpdir:
        work_dir = Path(tmpdir)
        input_path = work_dir / _safe_input_file_name(file_name)
        output_dir = work_dir / "prepared"
        input_path.write_bytes(data)
        if progress:
            progress(5, "EPUB salvato")

        payload = _run_prepare_book(
            input_path=input_path,
            output_dir=output_dir,
            progress=progress,
        )
        pb_path = _pb_output_path(payload)
        if progress:
            progress(95, "Lettura PB generato")
        pb_bytes = pb_path.read_bytes()
        prepared = prepare_book(pb_path.name, pb_bytes)

        metadata = dict(prepared.metadata)
        metadata["source_file"] = file_name
        metadata["source_upload_sha256"] = sha256(data).hexdigest()
        metadata["prepared_artifact_file_name"] = pb_path.name
        metadata["preparation_engine"] = "prepare-book"
        metadata["prepare_book"] = {
            "used_fallback": bool(payload.get("used_fallback")),
            "chapter_plan_used_fallback": bool(payload.get("chapter_plan_used_fallback")),
            "concept_fallback_count": _coerce_int(payload.get("concept_fallback_count")),
            "chapter_count": _coerce_int(payload.get("count")),
        }

    if progress:
        progress(100, "Preparazione completata")

    return replace(
        prepared,
        id=sha256(data).hexdigest(),
        file_name=file_name,
        byte_size=len(data),
        metadata=metadata,
    )


def _run_prepare_book(
    input_path: Path,
    output_dir: Path,
    progress: ProgressCallback | None = None,
) -> dict[str, Any]:
    cmd = [
        _prepare_book_bin(),
        str(input_path),
        "--output-dir",
        str(output_dir),
        "--format",
        "txt",
        "--json",
    ]

    codex_bin = os.environ.get("CINDER_PREPARE_BOOK_CODEX_BIN")
    if codex_bin:
        cmd.extend(["--codex-bin", codex_bin])

    model = os.environ.get("CINDER_PREPARE_BOOK_MODEL")
    if model:
        cmd.extend(["--model", model])

    reasoning_effort = os.environ.get("CINDER_PREPARE_BOOK_REASONING_EFFORT")
    if reasoning_effort:
        cmd.extend(["--reasoning-effort", reasoning_effort])

    max_preview_chars = os.environ.get("CINDER_PREPARE_BOOK_MAX_PREVIEW_CHARS")
    if max_preview_chars:
        cmd.extend(["--max-preview-chars", max_preview_chars])

    concept_min_words = os.environ.get("CINDER_PREPARE_BOOK_CONCEPT_MIN_WORDS")
    if concept_min_words:
        cmd.extend(["--concept-min-words", concept_min_words])

    timeout = _prepare_book_timeout_seconds()
    try:
        process = subprocess.Popen(
            cmd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError as exc:
        missing = exc.filename or cmd[0]
        raise BookPreparationError(f"prepare-book non trovato: {missing}") from exc

    stdout_chunks: list[str] = []
    stderr_lines: list[str] = []

    def read_stdout() -> None:
        if process.stdout is None:
            return
        for chunk in process.stdout:
            stdout_chunks.append(chunk)

    def read_stderr() -> None:
        if process.stderr is None:
            return
        for raw_line in process.stderr:
            line = raw_line.strip()
            if line:
                stderr_lines.append(line)
            parsed_progress = _parse_prepare_book_progress_line(line)
            if progress and parsed_progress:
                percent, label = parsed_progress
                progress(percent, label)

    stdout_thread = threading.Thread(target=read_stdout, daemon=True)
    stderr_thread = threading.Thread(target=read_stderr, daemon=True)
    stdout_thread.start()
    stderr_thread.start()

    try:
        return_code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        process.kill()
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            pass
        stdout_thread.join(timeout=1)
        stderr_thread.join(timeout=1)
        raise BookPreparationError(
            f"prepare-book ha superato il timeout di {timeout} secondi."
        ) from exc

    stdout_thread.join(timeout=1)
    stderr_thread.join(timeout=1)
    stdout = "".join(stdout_chunks)
    stderr = "\n".join(stderr_lines)

    if return_code != 0:
        message = (stderr or stdout or "prepare-book fallito").strip()
        raise BookPreparationError(_compact_error_message(message))

    try:
        decoded = json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise BookPreparationError("prepare-book non ha restituito JSON valido.") from exc

    if not isinstance(decoded, dict):
        raise BookPreparationError("prepare-book ha restituito un JSON inatteso.")
    return decoded


def _parse_prepare_book_progress_line(line: str) -> tuple[int, str] | None:
    match = re.search(r"\]\s+\d+/\d+\s+(\d+)%\s*(.*)$", line)
    if match is None:
        return None
    percent = max(0, min(100, int(match.group(1))))
    label = " ".join(match.group(2).split()) or "Preparazione in corso"
    return percent, label


def _prepare_book_bin() -> str:
    configured = os.environ.get("CINDER_PREPARE_BOOK_BIN")
    if configured:
        return configured

    cinder_root = Path(__file__).resolve().parents[1]
    sibling_bin = cinder_root.parent / "prepare-book" / ".venv" / "bin" / "prepare-book"
    if sibling_bin.exists():
        return str(sibling_bin)
    return "prepare-book"


def _prepare_book_timeout_seconds() -> int:
    raw_timeout = os.environ.get("CINDER_PREPARE_BOOK_TIMEOUT_SECONDS")
    if not raw_timeout:
        return DEFAULT_PREPARE_BOOK_TIMEOUT_SECONDS
    try:
        timeout = int(raw_timeout)
    except ValueError:
        return DEFAULT_PREPARE_BOOK_TIMEOUT_SECONDS
    return max(1, timeout)


def _pb_output_path(payload: dict[str, Any]) -> Path:
    output = payload.get("all_in_one_output")
    if not isinstance(output, str) or not output.strip():
        raise BookPreparationError("prepare-book non ha indicato il file .pb generato.")

    pb_path = Path(output)
    if not pb_path.exists() or not pb_path.is_file():
        raise BookPreparationError(f"File .pb generato non trovato: {pb_path}")
    return pb_path


def _safe_input_file_name(file_name: str) -> str:
    base_name = file_name.rsplit("/", 1)[-1].rsplit("\\", 1)[-1].strip()
    if not base_name:
        return "book.epub"
    if _extension(base_name) != "epub":
        return f"{base_name}.epub"
    return base_name


def _extension(file_name: str) -> str:
    if "." not in file_name:
        return ""
    return file_name.rsplit(".", 1)[1].lower()


def _coerce_int(value: Any) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return 0
    return 0


def _compact_error_message(message: str, limit: int = 1200) -> str:
    compact = " ".join(message.split())
    if len(compact) <= limit:
        return compact
    return compact[: limit - 3].rstrip() + "..."

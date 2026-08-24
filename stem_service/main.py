from __future__ import annotations

import asyncio
import os
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

APP_ROOT = Path(os.getenv("STEM_WORKDIR", "/tmp/echo_stems"))
MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_BYTES", str(250 * 1024 * 1024)))
DEFAULT_MODEL = os.getenv("DEMUCS_MODEL", "htdemucs")
DEFAULT_BITRATE = os.getenv("DEMUCS_BITRATE", "192")
ALLOWED_EXTENSIONS = {".mp3", ".wav", ".flac", ".m4a", ".ogg", ".opus"}
STEMS = ("vocals", "bass", "drums", "other")

app = FastAPI(
    title="Echo AI Stem Separation",
    version="1.0.0",
    description="Free, open-source four-stem separation powered by Demucs.",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"] ,
)


class StemFile(BaseModel):
    name: str
    url: str
    content_type: str = "audio/mpeg"


class SeparationResponse(BaseModel):
    job_id: str
    model: str
    status: str = Field(pattern="^(completed|failed)$")
    stems: dict[str, StemFile]


def _safe_name(value: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9._-]+", "_", value).strip("._")
    return value or "audio"


def _validate_extension(filename: str | None) -> str:
    extension = Path(filename or "audio.bin").suffix.lower()
    if extension not in ALLOWED_EXTENSIONS:
        allowed = ", ".join(sorted(ALLOWED_EXTENSIONS))
        raise HTTPException(status_code=415, detail=f"Unsupported audio type. Use: {allowed}")
    return extension


async def _save_upload(upload: UploadFile, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    total = 0
    with target.open("wb") as output:
        while chunk := await upload.read(1024 * 1024):
            total += len(chunk)
            if total > MAX_UPLOAD_BYTES:
                target.unlink(missing_ok=True)
                raise HTTPException(status_code=413, detail="Audio file exceeds the upload limit.")
            output.write(chunk)
    await upload.close()


def _run_demucs(input_file: Path, output_root: Path, model: str) -> Path:
    command = [
        sys.executable,
        "-m",
        "demucs",
        "--mp3",
        "--mp3-bitrate",
        DEFAULT_BITRATE,
        "-n",
        model,
        "-o",
        str(output_root),
        str(input_file),
    ]
    completed = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=int(os.getenv("DEMUCS_TIMEOUT_SECONDS", "3600")),
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "Demucs failed.")[-4000:]
        raise RuntimeError(detail)

    track_dir = output_root / model / input_file.stem
    if not track_dir.exists():
        raise RuntimeError("Demucs completed without producing a stem directory.")
    return track_dir


def _find_stem(track_dir: Path, stem: str) -> Path:
    for extension in (".mp3", ".wav", ".flac"):
        candidate = track_dir / f"{stem}{extension}"
        if candidate.exists():
            return candidate
    raise RuntimeError(f"Demucs did not produce the expected {stem} stem.")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "model": DEFAULT_MODEL}


@app.post("/separate", response_model=SeparationResponse)
async def separate_audio(
    request: Request,
    audio: Annotated[UploadFile, File(description="Audio mix to separate")],
) -> SeparationResponse:
    extension = _validate_extension(audio.filename)
    job_id = uuid.uuid4().hex
    job_dir = APP_ROOT / job_id
    input_file = job_dir / f"input{extension}"
    output_dir = job_dir / "output"

    try:
        await _save_upload(audio, input_file)
        track_dir = await asyncio.to_thread(_run_demucs, input_file, output_dir, DEFAULT_MODEL)
        stems: dict[str, StemFile] = {}
        for stem in STEMS:
            file_path = _find_stem(track_dir, stem)
            stems[stem] = StemFile(
                name=stem,
                url=str(request.url_for("download_stem", job_id=job_id, stem_name=stem)),
            )
        return SeparationResponse(job_id=job_id, model=DEFAULT_MODEL, stems=stems)
    except HTTPException:
        shutil.rmtree(job_dir, ignore_errors=True)
        raise
    except subprocess.TimeoutExpired as error:
        shutil.rmtree(job_dir, ignore_errors=True)
        raise HTTPException(status_code=504, detail="Stem separation timed out.") from error
    except Exception as error:
        shutil.rmtree(job_dir, ignore_errors=True)
        raise HTTPException(status_code=500, detail=f"Stem separation failed: {error}") from error


@app.get("/jobs/{job_id}/stems/{stem_name}", name="download_stem")
def download_stem(job_id: str, stem_name: str) -> FileResponse:
    if not re.fullmatch(r"[a-f0-9]{32}", job_id):
        raise HTTPException(status_code=400, detail="Invalid job ID.")
    if stem_name not in STEMS:
        raise HTTPException(status_code=404, detail="Unknown stem.")

    track_dir = APP_ROOT / job_id / "output" / DEFAULT_MODEL
    matches = list(track_dir.glob(f"*/{stem_name}.mp3"))
    if not matches:
        raise HTTPException(status_code=404, detail="Stem is not available.")
    return FileResponse(
        matches[0],
        media_type="audio/mpeg",
        filename=f"{stem_name}.mp3",
        headers={"Cache-Control": "public, max-age=86400"},
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=int(os.getenv("PORT", "7860")))

"""
gdrive_loader.py
================
Optional Google Drive integration for the WIC KPI Dashboard.

When environment variables are configured, this module can automatically
fetch monthly Excel files from a Google Drive folder instead of requiring
manual uploads through the UI.

Environment Variables
---------------------
GDRIVE_FOLDER_ID
    The ID of the Google Drive folder that contains the monthly .xlsx files.
    Example: "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms"

GDRIVE_SERVICE_ACCOUNT_JSON
    Either the path to a service-account JSON key file **or** the raw JSON
    content as a string.  The service account must have at least read access
    to the target folder.

GDRIVE_FILE_PATTERN
    Optional glob / regex pattern to filter files in the folder.
    Defaults to "*.xlsx".

Usage
-----
    from gdrive_loader import list_monthly_files, download_file

    files = list_monthly_files()          # returns list of {id, name} dicts
    for f in files:
        xlsx_bytes = download_file(f["id"])
        # pass xlsx_bytes to load_excel() in app.py

Dependencies (not included in requirements.txt by default)
-----------------------------------------------------------
    pip install google-api-python-client google-auth
"""

from __future__ import annotations

import fnmatch
import io
import json
import os
from typing import Any

# ─────────────────────────────────────────────────────────────
# Configuration (read from environment)
# ─────────────────────────────────────────────────────────────

FOLDER_ID: str | None = os.environ.get("GDRIVE_FOLDER_ID")
SERVICE_ACCOUNT_JSON: str | None = os.environ.get("GDRIVE_SERVICE_ACCOUNT_JSON")
FILE_PATTERN: str = os.environ.get("GDRIVE_FILE_PATTERN", ".xlsx")


# ─────────────────────────────────────────────────────────────
# Internal – build Google Drive API client
# ─────────────────────────────────────────────────────────────

def _build_service() -> Any:
    """
    Build and return an authenticated Google Drive v3 service object.

    Raises
    ------
    EnvironmentError
        If required env vars are not set.
    ImportError
        If google-api-python-client / google-auth are not installed.
    """
    if not SERVICE_ACCOUNT_JSON:
        raise EnvironmentError(
            "GDRIVE_SERVICE_ACCOUNT_JSON is not set. "
            "Set it to the path of your service-account JSON key file "
            "or to the raw JSON string."
        )
    if not FOLDER_ID:
        raise EnvironmentError(
            "GDRIVE_FOLDER_ID is not set. "
            "Set it to the Google Drive folder ID that contains the .xlsx files."
        )

    try:
        from google.oauth2 import service_account  # type: ignore
        from googleapiclient.discovery import build  # type: ignore
    except ImportError as exc:
        raise ImportError(
            "Google API client libraries are not installed. "
            "Run: pip install google-api-python-client google-auth"
        ) from exc

    # Accept either a file path or raw JSON string
    if os.path.isfile(SERVICE_ACCOUNT_JSON):
        credentials = service_account.Credentials.from_service_account_file(
            SERVICE_ACCOUNT_JSON,
            scopes=["https://www.googleapis.com/auth/drive.readonly"],
        )
    else:
        info = json.loads(SERVICE_ACCOUNT_JSON)
        credentials = service_account.Credentials.from_service_account_info(
            info,
            scopes=["https://www.googleapis.com/auth/drive.readonly"],
        )

    return build("drive", "v3", credentials=credentials)


# ─────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────

def is_configured() -> bool:
    """Return True if the Google Drive integration env vars are present."""
    return bool(FOLDER_ID and SERVICE_ACCOUNT_JSON)


def list_monthly_files() -> list[dict[str, str]]:
    """
    List Excel files in the configured Google Drive folder.

    Returns
    -------
    list of dict
        Each dict has ``id`` and ``name`` keys.

    Raises
    ------
    EnvironmentError, ImportError
        See ``_build_service``.
    """
    service = _build_service()
    query = (
        f"'{FOLDER_ID}' in parents "
        f"and mimeType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' "
        f"and trashed=false"
    )
    result = (
        service.files()
        .list(q=query, fields="files(id, name)", orderBy="name")
        .execute()
    )
    files = result.get("files", [])
    if FILE_PATTERN != ".xlsx":
        files = [f for f in files if fnmatch.fnmatch(f["name"], FILE_PATTERN)]
    return files


def download_file(file_id: str) -> bytes:
    """
    Download a file from Google Drive by its ID.

    Parameters
    ----------
    file_id : str
        The Google Drive file ID.

    Returns
    -------
    bytes
        The raw file contents.
    """
    try:
        from googleapiclient.http import MediaIoBaseDownload  # type: ignore
    except ImportError as exc:
        raise ImportError(
            "google-api-python-client is not installed. "
            "Run: pip install google-api-python-client google-auth"
        ) from exc

    service = _build_service()
    request = service.files().get_media(fileId=file_id)
    buf = io.BytesIO()
    downloader = MediaIoBaseDownload(buf, request)
    done = False
    while not done:
        _, done = downloader.next_chunk()
    return buf.getvalue()

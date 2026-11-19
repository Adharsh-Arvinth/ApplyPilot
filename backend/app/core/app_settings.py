"""Tiny JSON key/value helpers on top of the app_settings table."""
import json
from typing import Any
from sqlalchemy.orm import Session
from backend.app.models import AppSetting


def get_setting(db: Session, key: str, default: Any = None) -> Any:
    row = db.get(AppSetting, key)
    if not row or row.value in (None, ""):
        return default
    try:
        return json.loads(row.value)
    except (ValueError, TypeError):
        return default


def set_setting(db: Session, key: str, value: Any) -> None:
    row = db.get(AppSetting, key)
    payload = json.dumps(value, default=str)
    if row:
        row.value = payload
    else:
        db.add(AppSetting(key=key, value=payload))
    db.commit()


def delete_setting(db: Session, key: str) -> None:
    row = db.get(AppSetting, key)
    if row:
        db.delete(row)
        db.commit()

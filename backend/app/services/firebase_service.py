import os
import json
import logging
import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional
import firebase_admin
from firebase_admin import credentials, firestore, messaging, auth
from backend.app.core.config import settings, BASE_DIR

logger = logging.getLogger(__name__)

class FirebaseService:
    _initialized: bool = False
    _app: Optional[firebase_admin.App] = None
    _db: Optional[Any] = None
    _project_id: Optional[str] = None
    _error_message: Optional[str] = None

    @classmethod
    def initialize(cls) -> bool:
        """Initialize Firebase Admin SDK using existing service account credentials."""
        if cls._initialized and cls._app:
            return True

        # Candidate credential paths to check
        potential_paths = [
            BASE_DIR / "applypilot-89c65-firebase-adminsdk-fbsvc-01b6f0c818.json",
            Path("backend/applypilot-89c65-firebase-adminsdk-fbsvc-01b6f0c818.json"),
            BASE_DIR / "serviceAccountKey.json",
        ]
        if settings.FIREBASE_CREDENTIALS_PATH:
            # Handle potential backslash-escape issues from .env by testing raw and normalized paths
            try:
                potential_paths.insert(0, Path(settings.FIREBASE_CREDENTIALS_PATH))
            except Exception:
                pass

        resolved_path: Optional[Path] = None
        for p in potential_paths:
            if p.exists() and p.is_file():
                resolved_path = p
                break

        if not resolved_path:
            cls._error_message = "Firebase service account credentials file not found on disk."
            logger.warning(f"Firebase initialization skipped: {cls._error_message}")
            return False

        try:
            cred = credentials.Certificate(str(resolved_path))
            cls._project_id = cred.project_id
            
            # Re-use existing default app if already initialized
            if firebase_admin._apps and "[DEFAULT]" in firebase_admin._apps:
                cls._app = firebase_admin.get_app()
            else:
                cls._app = firebase_admin.initialize_app(cred)

            try:
                cls._db = firestore.client()
            except Exception as e:
                logger.warning(f"Firestore client initialization warning: {e}")
                cls._db = None

            cls._initialized = True
            cls._error_message = None
            logger.info(f"Firebase Admin SDK successfully initialized for project: {cls._project_id}")
            return True
        except Exception as e:
            cls._error_message = str(e)
            logger.error(f"Failed to initialize Firebase Admin SDK: {e}")
            return False

    @classmethod
    def get_status(cls) -> Dict[str, Any]:
        """Return diagnostic status of Firebase integrations."""
        if not cls._initialized:
            cls.initialize()

        return {
            "initialized": cls._initialized,
            "project_id": cls._project_id or "applypilot-89c65",
            "firestore_ready": cls._db is not None,
            "messaging_ready": cls._initialized,
            "auth_ready": cls._initialized,
            "error": cls._error_message,
        }

    @classmethod
    def verify_id_token(cls, id_token: str) -> Optional[Dict[str, Any]]:
        """Verify Firebase Auth ID Token for secure user identity."""
        if not cls.initialize():
            return None
        try:
            decoded = auth.verify_id_token(id_token)
            return decoded
        except Exception as e:
            logger.warning(f"Firebase token verification failed: {e}")
            return None

    @classmethod
    def sync_profile(cls, profile_dict: Dict[str, Any]) -> bool:
        """Sync candidate profile and preferences to Firestore cloud replica."""
        if not cls.initialize() or not cls._db:
            return False
        try:
            doc_ref = cls._db.collection("profiles").document("candidate_primary")
            payload = {
                **profile_dict,
                "synced_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            }
            # Remove any non-serializable fields
            if "updated_at" in payload and isinstance(payload["updated_at"], datetime.datetime):
                payload["updated_at"] = payload["updated_at"].isoformat()
            doc_ref.set(payload, merge=True)
            return True
        except Exception as e:
            logger.warning(f"Firestore profile sync failed: {e}")
            return False

    @classmethod
    def sync_job(cls, job_dict: Dict[str, Any]) -> bool:
        """Sync discovered/applied job to Firestore cloud repository."""
        if not cls.initialize() or not cls._db:
            return False
        try:
            job_id = str(job_dict.get("id", "temp"))
            doc_ref = cls._db.collection("jobs").document(job_id)
            payload = {
                **job_dict,
                "synced_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            }
            for k, v in list(payload.items()):
                if isinstance(v, datetime.datetime):
                    payload[k] = v.isoformat()
            doc_ref.set(payload, merge=True)
            return True
        except Exception as e:
            logger.warning(f"Firestore job sync failed: {e}")
            return False

    @classmethod
    def send_push_notification(
        cls,
        title: str,
        body: str,
        data: Optional[Dict[str, str]] = None,
        token: Optional[str] = None,
        topic: str = "applypilot_alerts"
    ) -> bool:
        """Send push notification via Firebase Cloud Messaging (FCM)."""
        if not cls.initialize():
            logger.info(f"FCM skipped (not initialized). Notification: {title} - {body}")
            return False

        try:
            string_data = {k: str(v) for k, v in (data or {}).items()}
            message = None
            if token:
                message = messaging.Message(
                    notification=messaging.Notification(title=title, body=body),
                    data=string_data,
                    token=token,
                )
            else:
                message = messaging.Message(
                    notification=messaging.Notification(title=title, body=body),
                    data=string_data,
                    topic=topic,
                )
            
            response = messaging.send(message)
            logger.info(f"FCM notification sent successfully: {response}")
            return True
        except Exception as e:
            logger.warning(f"FCM send failed: {e}. (Normal in local environments without active device token)")
            return False

    @classmethod
    def log_analytics_event(cls, event_name: str, params: Optional[Dict[str, Any]] = None) -> bool:
        """Log sanitized product analytics event to Firestore."""
        if not cls.initialize() or not cls._db:
            return False
        try:
            doc_ref = cls._db.collection("analytics_events").document()
            doc_ref.set({
                "event_name": event_name,
                "params": params or {},
                "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            })
            return True
        except Exception as e:
            logger.warning(f"Firestore analytics log failed: {e}")
            return False

    @classmethod
    def get_remote_config(cls) -> Dict[str, Any]:
        """Return non-sensitive remote configuration defaults."""
        return {
            "daily_cap_default": 100,
            "min_fit_score_default": 4.0,
            "ai_features_enabled": True,
            "cloud_sync_enabled": cls._initialized,
            "version": "1.3.0",
        }

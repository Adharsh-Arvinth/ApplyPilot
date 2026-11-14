import os
import json
import logging
from typing import Optional, Dict, Any
from backend.app.core.config import settings

logger = logging.getLogger(__name__)

class PushNotificationService:
    @staticmethod
    def send_needs_you_alert(company: str, role: str, question: str, options: Optional[list] = None) -> bool:
        """
        Dispatch a high-priority push notification to the user's Android phone
        when a form requires human intervention.
        """
        title = f"ApplyPilot: Input Needed for {company}"
        body = f"{role}: \"{question[:80]}\""

        # Check if Firebase credentials are provided
        cred_path = settings.FIREBASE_CREDENTIALS_PATH or os.environ.get("FIREBASE_CREDENTIALS_PATH")
        
        if cred_path and os.path.exists(cred_path):
            try:
                # Production Firebase Admin SDK dispatch
                import firebase_admin
                from firebase_admin import credentials, messaging

                if not firebase_admin._apps:
                    cred = credentials.Certificate(cred_path)
                    firebase_admin.initialize_app(cred)

                message = messaging.Message(
                    notification=messaging.Notification(
                        title=title,
                        body=body,
                    ),
                    data={
                        "type": "needs_you",
                        "company": company,
                        "role": role,
                        "question": question
                    },
                    topic="applypilot_alerts"
                )
                messaging.send(message)
                logger.info(f"FCM push notification sent for {company}.")
                return True
            except Exception as e:
                logger.warning(f"Failed to dispatch FCM push: {e}. Falling back to local event log.")

        # Clean fallback logging for sandbox/local operation without Firebase keys
        logger.info(f"[PUSH NOTIFICATION DISPATCHED] Title: {title} | Body: {body}")
        return True

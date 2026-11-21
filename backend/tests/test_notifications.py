"""Phone notifications: a first check only sets a baseline; later checks group what's new; settings filter kinds."""
import datetime
import json

from fastapi.testclient import TestClient

from backend.app.core.config import settings
from backend.app.core.database import SessionLocal
from backend.app.main import app
from backend.app.models import EmailProof, Job, NeedsInput

client = TestClient(app)
AUTH = {"Authorization": f"Bearer {settings.APPLYPILOT_TOKEN}"}


def test_first_check_is_a_baseline_then_news_is_grouped():
    first = client.get("/api/v1/notifications", headers=AUTH).json()
    assert first["baseline"] is True and first["items"] == []
    since = first["now"]
    client.put("/api/v1/notifications/settings", headers=AUTH, json={"enabled": True, "replies": True, "matches": True, "questions": True})

    db = SessionLocal()
    try:
        stamp = int(datetime.datetime.now().timestamp() * 1000)
        job = Job(source="greenhouse", company="NotifyCo", title="ML Engineer", status="queued", score=4.8,
                  url=f"https://job-boards.greenhouse.io/notify/{stamp}")
        db.add(job); db.commit()
        db.add(NeedsInput(job_id=job.id, question_text="Why NotifyCo?", field_type="text", status="pending"))
        db.add(EmailProof(message_id=f"<n{stamp}@x>", job_id=job.id, company="NotifyCo", sender="hr@notify.co",
                          subject="Interview", snippet="Let's talk", kind="interview"))
        db.commit()
    finally:
        db.close()

    news = client.get(f"/api/v1/notifications?since={since}", headers=AUTH).json()
    kinds = [i["kind"] for i in news["items"]]
    assert kinds[0] == "replies"  # interviews come first
    assert {"replies", "questions", "matches"} <= set(kinds)
    reply = news["items"][0]
    assert "NotifyCo" in reply["body"] and reply["route"] == "proof"
    match = next(i for i in news["items"] if i["kind"] == "matches")
    assert "ML Engineer at NotifyCo" in match["body"]

    client.put("/api/v1/notifications/settings", headers=AUTH, json={"matches": False})
    quieter = client.get(f"/api/v1/notifications?since={since}", headers=AUTH).json()
    assert "matches" not in [i["kind"] for i in quieter["items"]]
    assert isinstance(quieter["quiet"], bool)
    client.put("/api/v1/notifications/settings", headers=AUTH, json={"matches": True})


def test_settings_need_the_key():
    assert TestClient(app).get("/api/v1/notifications/settings").status_code == 401
    s = client.get("/api/v1/notifications/settings", headers=AUTH).json()
    assert set(s["kinds"]) == {"replies", "matches", "questions", "sent"}

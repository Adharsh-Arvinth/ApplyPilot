from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from backend.app.core.database import get_db
from backend.app.core.security import verify_token
from backend.app.models import AnswerBank
from backend.app.schemas import AnswerBankOut, AnswerBankCreate, AnswerBankUpdate
from backend.app.services.answer_service import AnswerService, normalize_question_key

router = APIRouter(prefix="/answer-bank", tags=["Answer Bank"], dependencies=[Depends(verify_token)])

@router.get("", response_model=List[AnswerBankOut], summary="List & Search Answer Bank")
def list_answers(
    search: Optional[str] = Query(None, description="Search question text or answer"),
    category: Optional[str] = Query(None, description="Filter by category"),
    mode: Optional[str] = Query(None, description="always_use or ask_each_time"),
    is_verified: Optional[bool] = Query(None, description="Filter by verified status"),
    db: Session = Depends(get_db)
):
    query = db.query(AnswerBank)
    if category:
        query = query.filter(AnswerBank.category == category)
    if mode:
        query = query.filter(AnswerBank.mode == mode)
    if is_verified is not None:
        query = query.filter(AnswerBank.is_verified == is_verified)
    if search:
        s = f"%{search.strip().lower()}%"
        query = query.filter(
            (AnswerBank.question_key.like(s)) |
            (AnswerBank.question_text.ilike(s)) |
            (AnswerBank.answer.ilike(s))
        )
    return query.order_by(AnswerBank.usage_count.desc(), AnswerBank.updated_at.desc()).all()

@router.post("", response_model=AnswerBankOut, status_code=status.HTTP_201_CREATED, summary="Create Answer Bank Entry")
def create_answer(entry: AnswerBankCreate, db: Session = Depends(get_db)):
    key = normalize_question_key(entry.question_text)
    existing = db.query(AnswerBank).filter(AnswerBank.question_key == key).first()
    if existing:
        existing.answer = entry.answer
        existing.field_type = entry.field_type
        existing.mode = entry.mode
        existing.category = entry.category
        existing.source = entry.source
        existing.is_verified = entry.is_verified
        existing.supporting_evidence = entry.supporting_evidence
        existing.allow_reuse = entry.allow_reuse
        db.commit()
        db.refresh(existing)
        return existing

    new_answer = AnswerBank(
        question_key=key,
        question_text=entry.question_text,
        field_type=entry.field_type,
        answer=entry.answer,
        mode=entry.mode,
        category=entry.category,
        source=entry.source,
        is_verified=entry.is_verified,
        supporting_evidence=entry.supporting_evidence,
        allow_reuse=entry.allow_reuse
    )
    db.add(new_answer)
    db.commit()
    db.refresh(new_answer)
    return new_answer

@router.get("/{answer_id}", response_model=AnswerBankOut)
def get_answer(answer_id: int, db: Session = Depends(get_db)):
    ans = db.query(AnswerBank).filter(AnswerBank.id == answer_id).first()
    if not ans:
        raise HTTPException(status_code=404, detail="Answer not found.")
    return ans

@router.put("/{answer_id}", response_model=AnswerBankOut)
def update_answer(answer_id: int, update: AnswerBankUpdate, db: Session = Depends(get_db)):
    ans = db.query(AnswerBank).filter(AnswerBank.id == answer_id).first()
    if not ans:
        raise HTTPException(status_code=404, detail="Answer not found.")

    if update.question_text is not None:
        ans.question_text = update.question_text
        ans.question_key = normalize_question_key(update.question_text)
    if update.field_type is not None:
        ans.field_type = update.field_type
    if update.answer is not None:
        ans.answer = update.answer
    if update.mode is not None:
        ans.mode = update.mode
    if update.category is not None:
        ans.category = update.category
    if update.source is not None:
        ans.source = update.source
    if update.is_verified is not None:
        ans.is_verified = update.is_verified
    if update.supporting_evidence is not None:
        ans.supporting_evidence = update.supporting_evidence
    if update.allow_reuse is not None:
        ans.allow_reuse = update.allow_reuse

    db.commit()
    db.refresh(ans)
    return ans

@router.delete("/{answer_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_answer(answer_id: int, db: Session = Depends(get_db)):
    ans = db.query(AnswerBank).filter(AnswerBank.id == answer_id).first()
    if not ans:
        raise HTTPException(status_code=404, detail="Answer not found.")
    db.delete(ans)
    db.commit()
    return None

@router.post("/lookup", summary="Test Resolve a Question Label")
def lookup_answer(label: str = Query(..., description="Field label from an ATS form"), db: Session = Depends(get_db)):
    result = AnswerService.resolve_answer(db, label)
    if not result:
        return {"found": False, "label": label, "answer": None, "mode": None}
    answer, mode = result
    return {"found": True, "label": label, "answer": answer, "mode": mode}

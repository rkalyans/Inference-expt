"""Pydantic API schemas. Database rows are accessed via raw SQL in repo.py to
avoid pulling in a full ORM mapping layer for a thin CRUD service."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Literal, Optional
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field

Category = Literal["top", "bottom", "footwear", "outerwear", "accessory"]


class ItemCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    category: Category
    attributes: Dict[str, Any] = Field(default_factory=dict)
    photo_url: Optional[str] = None


class ItemUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=200)
    category: Optional[Category] = None
    attributes: Optional[Dict[str, Any]] = None
    photo_url: Optional[str] = None


class Item(BaseModel):
    id: UUID
    user_id: UUID
    name: str
    category: Category
    attributes: Dict[str, Any]
    photo_url: Optional[str]
    qdrant_point_id: Optional[str]
    created_at: datetime


class ItemList(BaseModel):
    items: List[Item]
    next_cursor: Optional[str] = None


class UploadUrlResponse(BaseModel):
    upload_url: str
    object_uri: str
    expires_in_seconds: int


class UserCreate(BaseModel):
    email: EmailStr
    preferences: Dict[str, Any] = Field(default_factory=dict)


class User(BaseModel):
    id: UUID
    email: EmailStr
    created_at: datetime
    preferences: Dict[str, Any]

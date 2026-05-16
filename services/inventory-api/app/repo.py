"""Thin async-SQL repository for users + clothing_items.

Uses parameterized SQL to keep the surface small. All queries are scoped by
user_id at the SQL level, so a user cannot see another user's items even if
the application layer forgets to filter.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


# ---------- users ----------

async def get_or_create_user(s: AsyncSession, email: str, preferences: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    row = (await s.execute(
        text("SELECT id, email, created_at, preferences_jsonb FROM users WHERE email = :email"),
        {"email": email},
    )).first()
    if row:
        return _user_row_to_dict(row)
    row = (await s.execute(
        text("""
            INSERT INTO users (email, preferences_jsonb)
            VALUES (:email, CAST(:prefs AS JSONB))
            RETURNING id, email, created_at, preferences_jsonb
        """),
        {"email": email, "prefs": _json(preferences or {})},
    )).first()
    await s.commit()
    return _user_row_to_dict(row)


def _user_row_to_dict(row) -> Dict[str, Any]:
    return {
        "id": row.id,
        "email": row.email,
        "created_at": row.created_at,
        "preferences": row.preferences_jsonb or {},
    }


# ---------- clothing_items ----------

async def list_items(
    s: AsyncSession,
    user_id: UUID,
    category: Optional[str] = None,
    limit: int = 100,
) -> List[Dict[str, Any]]:
    sql = """
        SELECT id, user_id, name, category, attributes_jsonb, photo_url, qdrant_point_id, created_at
        FROM clothing_items
        WHERE user_id = :user_id
        {category_filter}
        ORDER BY created_at DESC
        LIMIT :limit
    """.format(category_filter="AND category = :category" if category else "")

    params: Dict[str, Any] = {"user_id": str(user_id), "limit": limit}
    if category:
        params["category"] = category

    rows = (await s.execute(text(sql), params)).all()
    return [_item_row(r) for r in rows]


async def get_item(s: AsyncSession, user_id: UUID, item_id: UUID) -> Optional[Dict[str, Any]]:
    row = (await s.execute(
        text("""
            SELECT id, user_id, name, category, attributes_jsonb, photo_url, qdrant_point_id, created_at
            FROM clothing_items WHERE user_id = :user_id AND id = :id
        """),
        {"user_id": str(user_id), "id": str(item_id)},
    )).first()
    return _item_row(row) if row else None


async def create_item(
    s: AsyncSession,
    user_id: UUID,
    name: str,
    category: str,
    attributes: Dict[str, Any],
    photo_url: Optional[str],
) -> Dict[str, Any]:
    row = (await s.execute(
        text("""
            INSERT INTO clothing_items (user_id, name, category, attributes_jsonb, photo_url)
            VALUES (:user_id, :name, :category, CAST(:attrs AS JSONB), :photo_url)
            RETURNING id, user_id, name, category, attributes_jsonb, photo_url, qdrant_point_id, created_at
        """),
        {
            "user_id": str(user_id),
            "name": name,
            "category": category,
            "attrs": _json(attributes),
            "photo_url": photo_url,
        },
    )).first()
    await s.commit()
    return _item_row(row)


async def update_item(
    s: AsyncSession,
    user_id: UUID,
    item_id: UUID,
    *,
    name: Optional[str] = None,
    category: Optional[str] = None,
    attributes: Optional[Dict[str, Any]] = None,
    photo_url: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    sets: List[str] = []
    params: Dict[str, Any] = {"user_id": str(user_id), "id": str(item_id)}
    if name is not None:
        sets.append("name = :name")
        params["name"] = name
    if category is not None:
        sets.append("category = :category")
        params["category"] = category
    if attributes is not None:
        sets.append("attributes_jsonb = CAST(:attrs AS JSONB)")
        params["attrs"] = _json(attributes)
    if photo_url is not None:
        sets.append("photo_url = :photo_url")
        params["photo_url"] = photo_url
    if not sets:
        return await get_item(s, user_id, item_id)

    row = (await s.execute(
        text(f"""
            UPDATE clothing_items SET {", ".join(sets)}
            WHERE user_id = :user_id AND id = :id
            RETURNING id, user_id, name, category, attributes_jsonb, photo_url, qdrant_point_id, created_at
        """),
        params,
    )).first()
    await s.commit()
    return _item_row(row) if row else None


async def delete_item(s: AsyncSession, user_id: UUID, item_id: UUID) -> bool:
    res = await s.execute(
        text("DELETE FROM clothing_items WHERE user_id = :user_id AND id = :id"),
        {"user_id": str(user_id), "id": str(item_id)},
    )
    await s.commit()
    return res.rowcount > 0


def _item_row(row) -> Dict[str, Any]:
    return {
        "id": row.id,
        "user_id": row.user_id,
        "name": row.name,
        "category": row.category,
        "attributes": row.attributes_jsonb or {},
        "photo_url": row.photo_url,
        "qdrant_point_id": row.qdrant_point_id,
        "created_at": row.created_at,
    }


def _json(d: Dict[str, Any]) -> str:
    import json
    return json.dumps(d, default=str)

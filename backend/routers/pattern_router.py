"""
routers/pattern_router.py — Quản lý thư viện mẫu dệt
  GET  /api/patterns           — Lấy danh sách tất cả mẫu
  POST /api/search-pattern     — Tìm kiếm mẫu theo prompt (embedding similarity)
  POST /api/patterns/reload    — Reload thư viện (dùng khi cập nhật JSON)
"""

from fastapi import APIRouter, HTTPException
from models.schemas import PromptRenderRequest, PatternSearchResponse
from services.pattern_service import (
    load_pattern_library,
    search_patterns,
    reload_library,
)

router = APIRouter()


@router.get("/patterns")
async def get_all_patterns():
    """
    Trả về toàn bộ mẫu trong thư viện (không bao gồm matrix raw để tiết kiệm bandwidth)
    Flutter dùng để hiển thị grid view lựa chọn mẫu
    """
    patterns = load_pattern_library()
    # Loại bỏ trường nặng (matrix, color_map) trước khi gửi về frontend
    lite = [
        {k: v for k, v in p.items() if k not in ("matrix", "color_map")}
        for p in patterns
    ]
    return {"patterns": lite, "total": len(lite)}


@router.post("/search-pattern")
async def search_pattern_by_prompt(req: PromptRenderRequest):
    """
    Tìm kiếm mẫu bằng ngữ nghĩa — endpoint chính cho chatbox của Flutter
    
    Input: prompt tiếng Việt như "mẫu sọc xanh đỏ truyền thống miền Trung"
    Output: TOP 3–5 mẫu phù hợp nhất kèm điểm similarity
    """
    if not req.prompt.strip():
        raise HTTPException(400, detail="Prompt không được để trống")

    try:
        results = search_patterns(req.prompt, top_k=req.top_k)
    except RuntimeError as e:
        raise HTTPException(503, detail=str(e))

    return PatternSearchResponse(query=req.prompt, results=results)


@router.post("/patterns/reload")
async def reload_patterns():
    """Reload thư viện mẫu và cache embedding — gọi khi cập nhật pattern_library.json"""
    reload_library()
    patterns = load_pattern_library()
    return {"message": f"Đã reload thư viện, tổng {len(patterns)} mẫu"}

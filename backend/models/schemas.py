"""
models/schemas.py — Định nghĩa các schema Pydantic cho request/response
Đảm bảo format dữ liệu nhất quán giữa backend và Flutter frontend
"""

from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any


# ══════════════════════════════════════════════════════════════════════════════
# RESPONSE MODELS — Format chuẩn trả về cho Flutter
# ══════════════════════════════════════════════════════════════════════════════

class ClusterInfo(BaseModel):
    """Thông tin một cụm màu sau khi phân đoạn ảnh"""
    id: int                     # Index của cluster (0–5)
    color: str                  # Màu hex, ví dụ "#ff0000"
    pixel_count: int            # Số pixel thuộc cluster này
    percentage: float           # Tỷ lệ phần trăm diện tích


class RenderResponse(BaseModel):
    """
    Response chuẩn cho tất cả endpoint render (/render-from-image, /render-from-prompt)
    Flutter sẽ parse theo format này
    """
    image_url: str                          # URL ảnh đã render (6 màu)
    matrix: List[List[int]]                 # Ma trận 0/1 để điều khiển lever
    clusters: List[ClusterInfo]             # Danh sách 6 cluster màu
    pattern_name: Optional[str] = None     # Tên mẫu (nếu từ thư viện)
    width: int = 0                          # Chiều rộng ảnh (số cột = số lever)
    height: int = 0                         # Chiều cao ảnh (số hàng)


class PatternItem(BaseModel):
    """Mô tả một mẫu dệt trong thư viện"""
    id: str
    name: str
    description: str
    image_path: str
    tags: List[str] = []


class PatternSearchResponse(BaseModel):
    """Kết quả tìm kiếm mẫu theo prompt (TOP 3–5 mẫu tương tự)"""
    query: str                              # Prompt người dùng nhập
    results: List[Dict[str, Any]]           # Danh sách mẫu + điểm similarity


# ══════════════════════════════════════════════════════════════════════════════
# REQUEST MODELS — Dữ liệu Flutter gửi lên
# ══════════════════════════════════════════════════════════════════════════════

class PromptRenderRequest(BaseModel):
    """Request render từ prompt văn bản"""
    prompt: str = Field(..., min_length=1, description="Mô tả mẫu dệt bằng tiếng Việt/Anh")
    top_k: int = Field(default=3, ge=1, le=5, description="Số mẫu gợi ý trả về")


class ClusterEditRequest(BaseModel):
    """Request thay đổi màu của một cluster cụ thể"""
    image_url: str              # URL ảnh hiện tại (để biết ảnh nào cần chỉnh)
    cluster_id: int             # ID cluster cần đổi màu (0–5)
    new_color: str              # Màu mới dạng hex "#rrggbb"
    matrix: List[List[int]]     # Ma trận hiện tại (để giữ nguyên, chỉ đổi màu ảnh)


class Esp32RowRequest(BaseModel):
    """Dữ liệu một hàng gửi đến ESP32"""
    row_index: int              # Chỉ số hàng đang dệt
    data: List[int]             # 31 giá trị 0/1 tương ứng 31 lever

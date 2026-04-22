"""
routers/cluster_router.py — Chỉnh sửa màu theo cluster
  POST /api/edit-cluster-color — Thay màu một cluster và trả về ảnh mới
"""

from fastapi import APIRouter, HTTPException
import numpy as np

from models.schemas import ClusterEditRequest, RenderResponse
from services.color_service import (
    replace_cluster_color,
    compute_clusters,
    save_image_to_static,
    FIXED_PALETTE,
)
from services.matrix_service import image_to_matrix
from routers.render_router import get_label_map_cache, _label_map_cache
from PIL import Image
import os

router = APIRouter()


@router.post("/edit-cluster-color", response_model=RenderResponse)
async def edit_cluster_color(req: ClusterEditRequest):
    """
    Thay màu một cluster trong ảnh đã render:
    1. Lấy label_map từ cache (đã tính khi render lần đầu)
    2. Thay tất cả pixel thuộc cluster_id bằng màu mới
    3. Render ảnh mới và trả về
    
    Flutter gọi khi user click chọn cluster và chọn màu mới từ palette 6 màu
    """
    # ── Xác định đường dẫn file ────────────────────────────────────────────
    # image_url từ Flutter có thể là path tương đối "/static/renders/..."
    local_path = req.image_url.lstrip("/")
    if not os.path.exists(local_path):
        raise HTTPException(404, detail=f"Không tìm thấy file ảnh: {local_path}")

    # ── Validate cluster_id ────────────────────────────────────────────────
    if req.cluster_id < 0 or req.cluster_id >= len(FIXED_PALETTE):
        raise HTTPException(400, detail=f"cluster_id phải từ 0 đến {len(FIXED_PALETTE)-1}")

    # ── Lấy label_map từ cache ────────────────────────────────────────────
    label_map = get_label_map_cache(req.image_url)
    if label_map is None:
        # Nếu không có cache → tính lại từ ảnh hiện tại
        img = Image.open(local_path).convert("RGB")
        from services.color_service import quantize_to_palette
        _, label_map = quantize_to_palette(img)

    # ── Thay màu cluster ──────────────────────────────────────────────────
    new_img = replace_cluster_color(local_path, label_map, req.cluster_id, req.new_color)

    # ── Lưu ảnh mới ───────────────────────────────────────────────────────
    new_image_url = save_image_to_static(new_img, prefix="edited")

    # ── Cập nhật cache cho ảnh mới ────────────────────────────────────────
    # Tính lại label_map vì màu đã thay đổi
    from services.color_service import quantize_to_palette
    _, new_label_map = quantize_to_palette(new_img)
    _label_map_cache[new_image_url] = new_label_map

    # ── Tính lại matrix từ ảnh mới ────────────────────────────────────────
    matrix, _ = image_to_matrix(new_img)
    clusters = compute_clusters(new_label_map)

    return RenderResponse(
        image_url=new_image_url,
        matrix=req.matrix if req.matrix else matrix,  # Giữ matrix cũ nếu user cung cấp
        clusters=clusters,
    )

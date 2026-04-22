"""
routers/render_router.py — 2 endpoint render chính
  POST /api/render-from-image  — Upload ảnh → xử lý → trả về ảnh 6 màu + matrix
  POST /api/render-from-prompt — Prompt → tìm mẫu phù hợp → render → trả về
"""

import io
import os
from fastapi import APIRouter, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from PIL import Image

from models.schemas import RenderResponse, PromptRenderRequest
from services.color_service import quantize_to_palette, compute_clusters, save_image_to_static
from services.matrix_service import image_to_matrix
from services.pattern_service import search_patterns, get_pattern_by_id, load_pattern_library

router = APIRouter()

# ── Cache label_map theo image_url để cluster editing không cần reprocess ──
# Key: image_url, Value: numpy array label_map
_label_map_cache: dict = {}


@router.post("/render-from-image", response_model=RenderResponse)
async def render_from_image(file: UploadFile = File(...)):
    """
    Nhận ảnh upload từ Flutter → xử lý → trả về:
    - image_url: URL ảnh đã lượng tử hóa về 6 màu
    - matrix: Ma trận 0/1 điều khiển 31 lever
    - clusters: Thông tin 6 cluster màu
    
    Flow: Upload PNG/JPG → Resize → Quantize 6 màu → Matrix → Lưu file → Response
    """
    # ── Kiểm tra định dạng file ────────────────────────────────────────────
    if file.content_type not in ("image/png", "image/jpeg", "image/jpg", "image/webp"):
        raise HTTPException(400, detail="Chỉ chấp nhận file ảnh PNG/JPG/WebP")

    # ── Đọc và mở ảnh ─────────────────────────────────────────────────────
    raw = await file.read()
    try:
        img = Image.open(io.BytesIO(raw))
    except Exception:
        raise HTTPException(400, detail="Không thể đọc file ảnh. Kiểm tra lại định dạng.")

    # ── Xử lý: lượng tử hóa và tạo matrix ────────────────────────────────
    matrix, label_map = image_to_matrix(img)

    # Render lại ảnh với kích thước lớn hơn để hiển thị đẹp
    quantized_img, label_map_full = _render_display_image(img, label_map)

    # ── Lưu ảnh vào static/ ───────────────────────────────────────────────
    image_url = save_image_to_static(quantized_img, prefix="upload")

    # ── Cache label_map để cluster editing tái sử dụng ────────────────────
    _label_map_cache[image_url] = label_map_full

    # ── Tính cluster info ─────────────────────────────────────────────────
    clusters = compute_clusters(label_map)

    return RenderResponse(
        image_url=image_url,
        matrix=matrix,
        clusters=clusters,
        width=31,
        height=len(matrix),
    )


@router.post("/render-from-prompt", response_model=dict)
async def render_from_prompt(req: PromptRenderRequest):
    """
    Nhận prompt văn bản → tìm mẫu phù hợp trong thư viện → trả về TOP K gợi ý
    
    QUAN TRỌNG: Không sinh ảnh mới bằng AI, chỉ tìm mẫu có sẵn!
    
    Flow: Prompt → Embedding → Cosine Similarity → TOP K patterns → Response
    """
    if not req.prompt.strip():
        raise HTTPException(400, detail="Prompt không được để trống")

    # ── Tìm kiếm mẫu phù hợp ─────────────────────────────────────────────
    try:
        results = search_patterns(req.prompt, top_k=req.top_k)
    except RuntimeError as e:
        raise HTTPException(503, detail=str(e))

    if not results:
        return {
            "query": req.prompt,
            "results": [],
            "message": "Không tìm thấy mẫu phù hợp. Thử mô tả khác nhé.",
        }

    return {
        "query": req.prompt,
        "results": results,
        "message": f"Tìm thấy {len(results)} mẫu phù hợp",
    }


@router.post("/render-pattern/{pattern_id}", response_model=RenderResponse)
async def render_pattern_by_id(pattern_id: str):
    """
    Render một mẫu cụ thể từ thư viện theo ID
    Flutter gọi sau khi người dùng chọn một trong TOP K gợi ý
    """
    pattern = get_pattern_by_id(pattern_id)
    if pattern is None:
        raise HTTPException(404, detail=f"Không tìm thấy mẫu ID: {pattern_id}")

    # ── Load ảnh mẫu từ file ──────────────────────────────────────────────
    image_path = pattern.get("image_path", "")
    if not os.path.exists(image_path):
        raise HTTPException(404, detail=f"File ảnh mẫu không tồn tại: {image_path}")

    img = Image.open(image_path)

    # ── Xử lý tương tự render-from-image ─────────────────────────────────
    matrix, label_map = image_to_matrix(img)
    quantized_img, label_map_full = _render_display_image(img, label_map)
    image_url = save_image_to_static(quantized_img, prefix=f"pattern_{pattern_id}")
    _label_map_cache[image_url] = label_map_full
    clusters = compute_clusters(label_map)

    return RenderResponse(
        image_url=image_url,
        matrix=matrix,
        clusters=clusters,
        pattern_name=pattern["name"],
        width=31,
        height=len(matrix),
    )


def _render_display_image(original_img: Image.Image, label_map_31w):
    """
    Tạo ảnh hiển thị kích thước lớn hơn từ label_map 31px
    Upscale để ảnh render đẹp khi hiển thị trên Flutter UI
    """
    from services.color_service import FIXED_PALETTE, quantize_to_palette
    import numpy as np

    # Upscale ảnh gốc để render đẹp (kích thước hiển thị)
    display_w = min(310, original_img.width)  # Tối đa 310px
    display_h = int(original_img.height * (display_w / original_img.width))
    img_display = original_img.resize((display_w, display_h), Image.LANCZOS)

    quantized_full, label_map_full = quantize_to_palette(img_display)
    return quantized_full, label_map_full


def get_label_map_cache(image_url: str):
    """Lấy label_map đã cache cho một image_url (dùng cho cluster editing)"""
    return _label_map_cache.get(image_url)

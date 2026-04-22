"""
services/color_service.py — Dịch vụ xử lý màu sắc
Chức năng:
  1. Lượng tử hóa ảnh về đúng 6 màu cố định (palette)
  2. Phân đoạn cluster và trả về thông tin từng cụm màu
  3. Thay thế màu một cluster (cluster-based color editing)
"""

import numpy as np
from PIL import Image
import io
import os
import uuid
from typing import List, Tuple, Dict
from models.schemas import ClusterInfo

# ── 6 màu cố định của hệ thống ────────────────────────────────────────────
# Format: (R, G, B) — đây là bảng màu duy nhất được phép dùng
FIXED_PALETTE: List[Tuple[int, int, int]] = [
    (220,  38,  38),   # 0 — Đỏ (red)
    ( 37, 99, 235),    # 1 — Xanh dương (blue)
    (124,  58, 237),   # 2 — Tím (purple)
    ( 22, 163,  74),   # 3 — Xanh lá (green)
    (234, 179,   8),   # 4 — Vàng (yellow)
    (255, 255, 255),   # 5 — Trắng (white)
]

# Tên màu để debug / hiển thị
PALETTE_NAMES = ["red", "blue", "purple", "green", "yellow", "white"]


def _rgb_to_hex(rgb: Tuple[int, int, int]) -> str:
    """Chuyển tuple RGB sang chuỗi hex '#rrggbb'"""
    return "#{:02x}{:02x}{:02x}".format(*rgb)


def _closest_palette_index(pixel: np.ndarray) -> int:
    """
    Tìm màu gần nhất trong FIXED_PALETTE cho một pixel
    Dùng khoảng cách Euclidean trong không gian màu RGB
    """
    palette_arr = np.array(FIXED_PALETTE, dtype=np.float32)
    pixel_f = pixel.astype(np.float32)
    # Tính bình phương khoảng cách đến mỗi màu trong palette
    distances = np.sum((palette_arr - pixel_f) ** 2, axis=1)
    return int(np.argmin(distances))  # Trả về index màu gần nhất


def quantize_to_palette(img: Image.Image) -> Tuple[Image.Image, np.ndarray]:
    """
    Lượng tử hóa ảnh: mỗi pixel → màu gần nhất trong FIXED_PALETTE
    
    Returns:
        quantized_img: Ảnh đã được đổi về 6 màu
        label_map: Mảng 2D (H×W) lưu index palette của từng pixel
    """
    # Chuyển sang RGB (loại bỏ alpha nếu có)
    img_rgb = img.convert("RGB")
    arr = np.array(img_rgb, dtype=np.uint8)   # Shape: (H, W, 3)
    H, W = arr.shape[:2]

    # Reshape thành (H*W, 3) để xử lý vectorized
    flat = arr.reshape(-1, 3).astype(np.float32)
    palette_arr = np.array(FIXED_PALETTE, dtype=np.float32)

    # Tính khoảng cách từ mỗi pixel đến 6 màu — shape: (H*W, 6)
    # Dùng broadcasting để tránh vòng lặp Python
    diff = flat[:, np.newaxis, :] - palette_arr[np.newaxis, :, :]   # (N, 6, 3)
    dist_sq = np.sum(diff ** 2, axis=2)   # (N, 6)
    labels = np.argmin(dist_sq, axis=1)   # (N,) — index màu cho mỗi pixel

    # Tái tạo ảnh từ palette
    quantized_flat = palette_arr[labels].astype(np.uint8)   # (N, 3)
    quantized_arr = quantized_flat.reshape(H, W, 3)
    quantized_img = Image.fromarray(quantized_arr, "RGB")

    label_map = labels.reshape(H, W)   # (H, W) — cluster ID từng pixel
    return quantized_img, label_map


def compute_clusters(label_map: np.ndarray) -> List[ClusterInfo]:
    """
    Tính thông tin từng cluster màu sau khi lượng tử hóa
    
    Args:
        label_map: Mảng 2D chứa cluster index của từng pixel
    
    Returns:
        Danh sách ClusterInfo cho 6 màu (kể cả cluster rỗng)
    """
    total_pixels = label_map.size
    clusters = []

    for idx in range(len(FIXED_PALETTE)):
        count = int(np.sum(label_map == idx))
        clusters.append(ClusterInfo(
            id=idx,
            color=_rgb_to_hex(FIXED_PALETTE[idx]),
            pixel_count=count,
            percentage=round(count / total_pixels * 100, 2),
        ))

    return clusters


def save_image_to_static(img: Image.Image, prefix: str = "render") -> str:
    """
    Lưu ảnh vào thư mục static/ và trả về đường dẫn URL tương đối
    
    Args:
        img: PIL Image cần lưu
        prefix: Tiền tố tên file
    
    Returns:
        URL tương đối, ví dụ "/static/renders/render_abc123.png"
    """
    os.makedirs("static/renders", exist_ok=True)
    filename = f"{prefix}_{uuid.uuid4().hex[:8]}.png"
    filepath = f"static/renders/{filename}"
    img.save(filepath, "PNG", optimize=True)
    return f"/static/renders/{filename}"


def replace_cluster_color(
    image_url_local: str,
    label_map: np.ndarray,
    cluster_id: int,
    new_hex_color: str,
) -> Image.Image:
    """
    Thay màu toàn bộ pixel thuộc cluster_id bằng màu mới
    
    Args:
        image_url_local: Đường dẫn file ảnh trên server
        label_map: Mảng 2D cluster labels
        cluster_id: Index cluster cần đổi màu (0–5)
        new_hex_color: Màu mới dạng "#rrggbb"
    
    Returns:
        Ảnh PIL mới đã đổi màu cluster
    """
    # Parse hex color → RGB
    hex_clean = new_hex_color.lstrip("#")
    new_rgb = tuple(int(hex_clean[i:i+2], 16) for i in (0, 2, 4))

    # Load ảnh hiện tại
    img = Image.open(image_url_local).convert("RGB")
    arr = np.array(img, dtype=np.uint8)

    # Tạo mask cho cluster cần đổi màu
    mask = (label_map == cluster_id)   # Shape: (H, W) bool

    # Thay thế tất cả pixel trong cluster
    arr[mask] = new_rgb

    return Image.fromarray(arr, "RGB")

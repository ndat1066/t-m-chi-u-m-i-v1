"""
services/matrix_service.py — Chuyển đổi ảnh → ma trận điều khiển lever
Logic dệt chiếu:
  - Mỗi pixel → 0 hoặc 1
  - 0 = giữ lever (LED tắt)  
  - 1 = kéo lever (LED sáng)
  - Mỗi hàng tối đa 2 màu khác nhau
  - Cùng màu → cùng hành vi (không xung đột toggle)
"""

import numpy as np
from PIL import Image
from typing import List, Tuple
from services.color_service import FIXED_PALETTE, quantize_to_palette

# Số lượng lever (cũng là chiều rộng ma trận)
LEVER_COUNT = 31


def image_to_matrix(img: Image.Image) -> Tuple[List[List[int]], np.ndarray]:
    """
    Chuyển đổi ảnh PIL → ma trận nhị phân 0/1 để điều khiển 31 lever
    
    Thuật toán:
      1. Resize ảnh về chiều rộng = LEVER_COUNT (31 cột)
      2. Lượng tử hóa màu về 6 màu cố định
      3. Xác định màu "nền" (màu phổ biến nhất toàn ảnh)
      4. Mỗi pixel ≠ nền → 1 (kéo lever), == nền → 0 (giữ lever)
      5. Áp dụng quy tắc tối đa 2 màu/hàng
    
    Args:
        img: PIL Image đầu vào (bất kỳ kích thước)
    
    Returns:
        matrix: List[List[int]] kích thước (H × 31)
        label_map: Numpy array cluster labels (để tái sử dụng cho cluster editing)
    """
    # ── Bước 1: Resize về chiều rộng LEVER_COUNT, giữ tỷ lệ ────────────────
    original_w, original_h = img.size
    scale = LEVER_COUNT / original_w
    new_h = max(1, int(original_h * scale))
    img_resized = img.resize((LEVER_COUNT, new_h), Image.LANCZOS)

    # ── Bước 2: Lượng tử hóa màu → 6 màu cố định ──────────────────────────
    quantized_img, label_map = quantize_to_palette(img_resized)
    
    # ── Bước 3: Xác định màu "nền" toàn ảnh ────────────────────────────────
    # Màu xuất hiện nhiều nhất = màu nền → pixel đó sẽ là 0
    unique, counts = np.unique(label_map, return_counts=True)
    bg_label = int(unique[np.argmax(counts)])  # Index palette của màu nền

    # ── Bước 4: Tạo ma trận nhị phân ─────────────────────────────────────
    # Pixel nào ≠ màu nền → lever ON (1), pixel màu nền → lever OFF (0)
    binary_map = (label_map != bg_label).astype(np.int8)  # Shape: (H, W)

    # ── Bước 5: Áp dụng quy tắc tối đa 2 màu/hàng ────────────────────────
    matrix: List[List[int]] = []
    for row_idx in range(new_h):
        row_labels = label_map[row_idx]          # (31,) — label của từng pixel
        row_binary = binary_map[row_idx].tolist()  # [0/1, ...]

        # Đếm số màu khác nhau trong hàng
        unique_in_row = np.unique(row_labels)

        if len(unique_in_row) <= 2:
            # Hàng đã hợp lệ (≤ 2 màu), giữ nguyên
            matrix.append(row_binary)
        else:
            # Hàng có > 2 màu → giữ lại 2 màu phổ biến nhất, còn lại gộp vào màu gần nhất
            row_clean = _enforce_two_color_row(row_labels, row_binary, bg_label)
            matrix.append(row_clean)

    return matrix, label_map


def _enforce_two_color_row(
    row_labels: np.ndarray,
    row_binary: List[int],
    bg_label: int,
) -> List[int]:
    """
    Đảm bảo hàng chỉ có tối đa 2 màu:
    - Giữ lại màu nền (bg_label) và màu chiếm nhiều pixel nhất còn lại
    - Các màu khác → gộp vào màu gần nhất (2 màu được chọn)
    
    Quy tắc: 
    - Cùng màu = cùng hành vi lever
    - Không tạo xung đột toggle trong cùng một hàng dệt
    """
    unique_labels, label_counts = np.unique(row_labels, return_counts=True)

    # Loại màu nền ra, tìm màu foreground phổ biến nhất
    non_bg_mask = unique_labels != bg_label
    if not np.any(non_bg_mask):
        # Hàng toàn màu nền → tất cả 0
        return [0] * len(row_binary)

    non_bg_labels = unique_labels[non_bg_mask]
    non_bg_counts = label_counts[non_bg_mask]
    dominant_fg = non_bg_labels[np.argmax(non_bg_counts)]  # Màu foreground chính

    # 2 màu được giữ lại: bg_label và dominant_fg
    allowed = {bg_label, dominant_fg}

    # Pixel có label không thuộc 2 màu được chọn → gộp vào dominant_fg
    result = []
    for lbl in row_labels:
        if lbl in allowed:
            result.append(0 if lbl == bg_label else 1)
        else:
            # Màu "lạ" → gán vào dominant_fg (=1)
            result.append(1)

    return result


def matrix_to_led_states(matrix: List[List[int]], row_index: int) -> List[bool]:
    """
    Lấy trạng thái LED cho một hàng cụ thể
    
    Args:
        matrix: Ma trận điều khiển đầy đủ
        row_index: Index hàng hiện tại
    
    Returns:
        List 31 bool: True = LED sáng, False = LED tắt
    """
    if row_index >= len(matrix):
        return [False] * LEVER_COUNT
    
    row = matrix[row_index]
    # Đảm bảo luôn đủ 31 phần tử
    padded = row[:LEVER_COUNT] + [0] * max(0, LEVER_COUNT - len(row))
    return [bool(v) for v in padded]


def get_active_levers(row: List[int]) -> List[int]:
    """
    Lấy danh sách index của các lever CẦN KÉO (giá trị = 1) trong một hàng
    
    Returns:
        Danh sách index (0-based), ví dụ [0, 3, 7, 15]
    """
    return [i for i, v in enumerate(row) if v == 1]

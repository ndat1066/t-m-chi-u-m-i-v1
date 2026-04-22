"""
services/pattern_service.py — Tìm kiếm mẫu dệt bằng embedding ngữ nghĩa
Sử dụng sentence-transformers để chuyển prompt → vector,
sau đó tính cosine similarity với description của từng mẫu trong thư viện.
KHÔNG sinh ảnh mới — chỉ tìm mẫu phù hợp nhất.
"""

import json
import os
import numpy as np
from typing import List, Dict, Any, Optional
from functools import lru_cache

# ── Lazy import để tránh tốn RAM khi không dùng ───────────────────────────
_model = None  # SentenceTransformer model (load lần đầu khi cần)

# Đường dẫn file thư viện mẫu dệt
PATTERN_LIBRARY_PATH = "assets/pattern_library.json"

# Cache embedding của tất cả mẫu (tránh tính lại mỗi request)
_pattern_embeddings: Optional[np.ndarray] = None
_pattern_data: Optional[List[Dict]] = None


def _get_model():
    """
    Lazy load model sentence-transformers (chỉ load 1 lần)
    Model nhỏ, đa ngôn ngữ, phù hợp tiếng Việt
    """
    global _model
    if _model is None:
        try:
            from sentence_transformers import SentenceTransformer
            # paraphrase-multilingual-MiniLM-L12-v2: hỗ trợ tiếng Việt, ~120MB
            _model = SentenceTransformer("paraphrase-multilingual-MiniLM-L12-v2")
        except ImportError:
            raise RuntimeError(
                "sentence-transformers chưa được cài. "
                "Chạy: pip install sentence-transformers"
            )
    return _model


def load_pattern_library() -> List[Dict[str, Any]]:
    """
    Load thư viện mẫu từ file JSON
    Format mỗi mẫu: {id, name, description, image_path, tags}
    """
    global _pattern_data
    if _pattern_data is not None:
        return _pattern_data  # Đã cache, không cần đọc lại

    if not os.path.exists(PATTERN_LIBRARY_PATH):
        # Trả về thư viện mẫu mặc định nếu chưa có file
        _pattern_data = _default_pattern_library()
        return _pattern_data

    with open(PATTERN_LIBRARY_PATH, "r", encoding="utf-8") as f:
        raw = json.load(f)

    # Hỗ trợ 2 format: dict {key: {matrix, description, ...}} hoặc list
    if isinstance(raw, dict):
        _pattern_data = [
            {
                "id": key,
                "name": val.get("name", key),
                "description": val.get("description", ""),
                "image_path": val.get("image_path", f"static/patterns/{key}.png"),
                "tags": val.get("tags", []),
                "matrix": val.get("matrix", []),
                "color_map": val.get("color_map", {}),
            }
            for key, val in raw.items()
        ]
    else:
        _pattern_data = raw

    return _pattern_data


def _build_search_text(pattern: Dict) -> str:
    """
    Gộp name + description + tags thành một chuỗi để embed
    Giúp tìm kiếm chính xác hơn khi prompt dùng từ khóa khác nhau
    """
    parts = [
        pattern.get("name", ""),
        pattern.get("description", ""),
        " ".join(pattern.get("tags", [])),
    ]
    return " ".join(p for p in parts if p).strip()


def _get_pattern_embeddings() -> np.ndarray:
    """
    Tính (hoặc lấy cache) embedding vector cho tất cả mẫu trong thư viện
    
    Returns:
        ndarray shape (N, embedding_dim) — N = số mẫu
    """
    global _pattern_embeddings
    if _pattern_embeddings is not None:
        return _pattern_embeddings  # Cache hit

    patterns = load_pattern_library()
    model = _get_model()

    # Tạo danh sách text để embed
    texts = [_build_search_text(p) for p in patterns]

    # Encode batch — model tự xử lý tiếng Việt
    _pattern_embeddings = model.encode(
        texts,
        convert_to_numpy=True,
        normalize_embeddings=True,   # L2-normalize → cosine sim = dot product
        show_progress_bar=False,
    )

    return _pattern_embeddings


def _cosine_similarity_batch(query_vec: np.ndarray, corpus_vecs: np.ndarray) -> np.ndarray:
    """
    Tính cosine similarity giữa 1 query vector và N corpus vectors
    Vì cả 2 đã được L2-normalize, chỉ cần dot product
    
    Returns:
        ndarray shape (N,) — similarity score trong [-1, 1]
    """
    # query_vec: (D,) → (1, D) để broadcast
    return corpus_vecs @ query_vec   # (N, D) @ (D,) = (N,)


def search_patterns(prompt: str, top_k: int = 3) -> List[Dict[str, Any]]:
    """
    Tìm kiếm mẫu dệt phù hợp nhất với prompt người dùng
    
    Thuật toán:
      1. Encode prompt → embedding vector
      2. Tính cosine similarity với tất cả mẫu trong thư viện
      3. Trả về TOP K mẫu có similarity cao nhất
    
    Args:
        prompt: Mô tả mẫu bằng tiếng Việt/Anh, ví dụ "mẫu sọc xanh đỏ truyền thống"
        top_k: Số mẫu gợi ý (1–5)
    
    Returns:
        Danh sách dict, mỗi item: {pattern_info, similarity_score}
    """
    patterns = load_pattern_library()
    if not patterns:
        return []

    model = _get_model()

    # Encode prompt (cũng normalize để dùng dot product)
    query_vec = model.encode(
        prompt,
        convert_to_numpy=True,
        normalize_embeddings=True,
    )

    # Lấy embedding của tất cả mẫu (có cache)
    corpus_vecs = _get_pattern_embeddings()

    # Tính similarity
    scores = _cosine_similarity_batch(query_vec, corpus_vecs)

    # Sắp xếp giảm dần, lấy top_k
    top_indices = np.argsort(scores)[::-1][:top_k]

    results = []
    for idx in top_indices:
        pattern = patterns[idx].copy()
        pattern.pop("matrix", None)       # Không gửi matrix raw (nặng)
        pattern.pop("color_map", None)    # Không gửi color_map raw
        results.append({
            **pattern,
            "similarity": round(float(scores[idx]), 4),
        })

    return results


def get_pattern_by_id(pattern_id: str) -> Optional[Dict[str, Any]]:
    """Lấy thông tin đầy đủ của một mẫu theo ID (bao gồm matrix và color_map)"""
    patterns = load_pattern_library()
    for p in patterns:
        if p["id"] == pattern_id:
            return p
    return None


def reload_library():
    """Reset cache — gọi khi cập nhật file pattern_library.json lúc runtime"""
    global _pattern_data, _pattern_embeddings
    _pattern_data = None
    _pattern_embeddings = None


def _default_pattern_library() -> List[Dict]:
    """
    Thư viện mẫu mặc định khi chưa có file JSON
    Dùng để test và demo
    """
    return [
        {
            "id": "pattern_a",
            "name": "Mẫu Caro Truyền Thống",
            "description": "Họa tiết caro truyền thống đan xen đỏ trắng, mang ý nghĩa may mắn sung túc",
            "image_path": "static/patterns/pattern_a.png",
            "tags": ["caro", "đỏ", "trắng", "truyền thống", "may mắn"],
            "matrix": [],
            "color_map": {},
        },
        {
            "id": "pattern_b",
            "name": "Sọc Ngang Thanh Lịch",
            "description": "Họa tiết sọc ngang xanh tím hiện đại tinh tế phong cách đô thị",
            "image_path": "static/patterns/pattern_b.png",
            "tags": ["sọc", "xanh", "tím", "hiện đại", "ngang"],
            "matrix": [],
            "color_map": {},
        },
        {
            "id": "pattern_c",
            "name": "Sọc Đứng Nam Bộ",
            "description": "Sọc đứng phối màu tím vàng phong cách truyền thống Nam Bộ Việt Nam",
            "image_path": "static/patterns/pattern_c.png",
            "tags": ["sọc đứng", "tím", "vàng", "Nam Bộ", "Việt Nam"],
            "matrix": [],
            "color_map": {},
        },
        {
            "id": "pattern_diamond",
            "name": "Thoi Kim Cương",
            "description": "Hoa văn thoi kim cương xanh lá trắng đối xứng, biểu tượng phồn thịnh",
            "image_path": "static/patterns/pattern_diamond.png",
            "tags": ["thoi", "kim cương", "xanh lá", "trắng", "đối xứng"],
            "matrix": [],
            "color_map": {},
        },
        {
            "id": "pattern_wave",
            "name": "Sóng Biển Miền Trung",
            "description": "Họa tiết sóng biển gợn xanh dương trắng, đặc trưng vùng biển miền Trung",
            "image_path": "static/patterns/pattern_wave.png",
            "tags": ["sóng", "biển", "xanh dương", "trắng", "miền Trung"],
            "matrix": [],
            "color_map": {},
        },
    ]

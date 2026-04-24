"""
main.py — FastAPI Backend chính cho hệ thống dệt chiếu Jacquard thông minh
=============================================================================
LUỒNG HOẠT ĐỘNG:
  1. Flutter upload ảnh → /api/patterns/render
     → convert_json.py xử lý ảnh → matrix màu 6 giá trị (0–5)
     → weaver_render.py render Jacquard 3D thật sự
     → Trả về: image_url + matrix + clusters

  2. Flutter gửi prompt → /api/search-pattern
     → sentence-transformers tìm mẫu giống nhất trong thư viện
     → Trả về: danh sách mẫu gợi ý (KHÔNG sinh ảnh mới)

  3. Flutter chọn mẫu → /api/render-pattern/{key}
     → weaver_render.py render mẫu đó
     → Trả về: image_url + matrix + clusters

  4. Flutter đổi màu cluster → /api/edit-cluster-color
     → Thay màu trong matrix → render lại Jacquard 3D
     → Trả về: image_url + matrix + clusters mới

  5. Flutter gửi đến ESP32 → /api/esp32/send-row
     → Proxy forward đến ESP32
"""

from fastapi import FastAPI, UploadFile, File, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
import os, shutil, uuid, json, numpy as np
import httpx, asyncio
from PIL import Image
import io

# Import từ các module gốc của dự án
from convert_json import convert_hsv_to_matrix, save_library
from weaver_render import SmartWeaver3D

# ── Khởi tạo app ──────────────────────────────────────────────────────────────
app = FastAPI(
    title="Smart Weaving Jacquard API v2",
    description="Backend tích hợp render Jacquard 3D + tìm kiếm mẫu bằng AI",
    version="2.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Thư mục lưu trữ ──────────────────────────────────────────────────────────
UPLOAD_DIR  = "uploads"   # Ảnh tạm khi upload
RENDER_DIR  = "renders"   # Ảnh Jacquard 3D đã render
LIBRARY_FILE = "pattern_library.json"
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(RENDER_DIR, exist_ok=True)

# Phục vụ ảnh render qua URL /renders/...
app.mount("/renders", StaticFiles(directory=RENDER_DIR), name="renders")

# ── Địa chỉ ESP32 ─────────────────────────────────────────────────────────────
ESP32_BASE_URL = os.getenv("ESP32_URL", "http://192.168.1.100")

# ══════════════════════════════════════════════════════════════════════════════
# PYDANTIC SCHEMAS — format dữ liệu chuẩn giữa Flutter và backend
# ══════════════════════════════════════════════════════════════════════════════

class ClusterInfo(BaseModel):
    """Thông tin một nhóm màu trong ảnh (tương ứng 1 trong 6 màu của color_map)"""
    id: int             # 0–5
    color: str          # Hex RGB, ví dụ "#b42832"
    pixel_count: int    # Số pixel có giá trị này trong matrix
    percentage: float   # Tỷ lệ phần trăm trên tổng ảnh

class RenderResponse(BaseModel):
    """Response chuẩn cho MỌI endpoint render — Flutter parse format này"""
    image_url: str              # URL đầy đủ đến file ảnh Jacquard 3D
    matrix: List[List[int]]     # Ma trận màu (giá trị 0–5) kích thước H×W
    clusters: List[ClusterInfo] # 6 cluster màu
    pattern_name: Optional[str] = None
    width: int = 0
    height: int = 0

class PatternItem(BaseModel):
    """Một mẫu trong thư viện"""
    id: str
    name: str
    description: str = ""
    image_path: str = ""
    tags: List[str] = []
    similarity: float = 0.0     # Điểm tương đồng khi tìm kiếm (0–1)

class PromptSearchRequest(BaseModel):
    prompt: str = Field(..., min_length=1)
    top_k: int = Field(default=3, ge=1, le=5)

class ClusterEditRequest(BaseModel):
    """Flutter gửi khi user đổi màu một cluster"""
    pattern_key: str            # Key mẫu trong thư viện (để render lại)
    cluster_id: int             # ID cluster cần đổi (0–5)
    new_color_id: int           # ID màu mới trong COLOR_PALETTE (0–5)

class Esp32RowRequest(BaseModel):
    row_index: int
    data: List[int]             # 31 giá trị 0/1

# ══════════════════════════════════════════════════════════════════════════════
# HÀM TIỆN ÍCH
# ══════════════════════════════════════════════════════════════════════════════

# 6 màu cố định của hệ thống — PHẢI khớp với color_map trong pattern_library.json
COLOR_PALETTE = {
    0: [235, 215, 170],   # Nền (kem/beige)
    1: [180, 40,  50 ],   # Đỏ
    2: [45,  110, 75 ],   # Xanh lá
    3: [35,  75,  145],   # Xanh dương
    4: [215, 155, 35 ],   # Vàng
    5: [125, 95,  65 ],   # Nâu
}

def _rgb_to_hex(rgb: list) -> str:
    """Chuyển list [R, G, B] → chuỗi hex '#rrggbb'"""
    return "#{:02x}{:02x}{:02x}".format(*rgb)

def _compute_clusters(matrix: list) -> List[ClusterInfo]:
    """
    Tính thông tin cluster từ ma trận màu
    Matrix chứa các giá trị int 0–5 ứng với COLOR_PALETTE
    """
    arr = np.array(matrix)
    total = arr.size
    clusters = []
    for idx in range(6):
        count = int(np.sum(arr == idx))
        rgb = COLOR_PALETTE.get(idx, [128, 128, 128])
        clusters.append(ClusterInfo(
            id=idx,
            color=_rgb_to_hex(rgb),
            pixel_count=count,
            percentage=round(count / total * 100, 2) if total > 0 else 0.0,
        ))
    return clusters

def _matrix_to_binary(matrix: list) -> List[List[int]]:
    """
    Chuyển ma trận màu (0–5) → ma trận nhị phân (0/1) để điều khiển lever
    Logic: màu nền (0) = lever OFF (0), màu khác = lever ON (1)
    Chiều rộng ma trận được resize về đúng 31 cột (= 31 lever)
    """
    arr = np.array(matrix)
    # Màu phổ biến nhất = nền
    vals, counts = np.unique(arr, return_counts=True)
    bg_label = int(vals[np.argmax(counts)])

    binary = (arr != bg_label).astype(np.int8)   # (H, W) — 1 = lever bật
    H, W = binary.shape

    LEVER_COUNT = 31
    if W == LEVER_COUNT:
        return binary.tolist()

    # Resize về 31 cột bằng cách lấy mẫu đều
    col_indices = np.linspace(0, W - 1, LEVER_COUNT, dtype=int)
    resized = binary[:, col_indices]   # (H, 31)
    return resized.tolist()

def _load_library() -> dict:
    """Đọc pattern_library.json, trả về {} nếu chưa có"""
    if not os.path.exists(LIBRARY_FILE):
        return {}
    with open(LIBRARY_FILE, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except Exception:
            return {}

def _render_pattern(pattern_key: str, base_url: str) -> RenderResponse:
    """
    Render một mẫu từ thư viện bằng SmartWeaver3D
    Đây là hàm cốt lõi — được gọi bởi nhiều endpoint
    
    Args:
        pattern_key: Key mẫu trong pattern_library.json
        base_url: URL gốc của server (để tạo image_url đầy đủ)
    
    Returns:
        RenderResponse với image_url, matrix, clusters
    """
    # ── Render Jacquard 3D bằng SmartWeaver3D ────────────────────────────
    weaver = SmartWeaver3D(pattern_key, library_file=LIBRARY_FILE)
    rendered_img = weaver.render()

    # ── Lưu ảnh vào thư mục renders/ ─────────────────────────────────────
    output_filename = f"render_{pattern_key}.png"
    output_path = os.path.join(RENDER_DIR, output_filename)
    rendered_img.save(output_path)

    # ── Lấy matrix và tính cluster ───────────────────────────────────────
    matrix_color = weaver.pattern_matrix.tolist()   # Matrix màu gốc (0–5)
    matrix_binary = _matrix_to_binary(matrix_color) # Matrix 0/1 cho lever

    clusters = _compute_clusters(matrix_color)

    # Đảm bảo base_url không có dấu / ở cuối
    base = base_url.rstrip("/")

    return RenderResponse(
        image_url=f"{base}/renders/{output_filename}",
        matrix=matrix_binary,
        clusters=clusters,
        pattern_name=pattern_key,
        width=31,
        height=len(matrix_binary),
    )

# ══════════════════════════════════════════════════════════════════════════════
# ENDPOINTS
# ══════════════════════════════════════════════════════════════════════════════

@app.get("/api/health")
async def health_check():
    """Health check — Flutter ping để kiểm tra server còn sống"""
    return {"status": "ok", "version": "2.0.0"}


# ── 1. RENDER TỪ ẢNH UPLOAD ──────────────────────────────────────────────────
@app.post("/api/patterns/render", response_model=RenderResponse)
async def render_from_image(request: Request, file: UploadFile = File(...)):
    """
    Nhận ảnh từ Flutter → chuyển sang matrix màu → render Jacquard 3D
    
    Luồng:
      Upload PNG/JPG → convert_hsv_to_matrix() → save_library() → SmartWeaver3D.render()
      → Trả về: image_url (Jacquard 3D), matrix (0/1 cho lever), clusters
    """
    # ── Lưu ảnh tạm ──────────────────────────────────────────────────────
    file_id = str(uuid.uuid4())[:8]
    ext = os.path.splitext(file.filename or "upload.jpg")[1] or ".jpg"
    input_path = os.path.join(UPLOAD_DIR, f"{file_id}{ext}")

    with open(input_path, "wb") as buf:
        shutil.copyfileobj(file.file, buf)

    try:
        # ── Chuyển ảnh → ma trận màu (6 giá trị 0–5) ─────────────────────
        matrix_color = convert_hsv_to_matrix(input_path)
        if matrix_color is None:
            raise HTTPException(400, detail="Không thể xử lý ảnh. Thử ảnh khác nhé.")

        # ── Lưu vào thư viện ─────────────────────────────────────────────
        pattern_key = f"pattern_{file_id}"
        save_library(pattern_key, matrix_color, filename=LIBRARY_FILE)

        # ── Render Jacquard 3D ────────────────────────────────────────────
        base_url = str(request.base_url).rstrip("/")
        return _render_pattern(pattern_key, base_url)

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, detail=f"Lỗi render: {str(e)}")
    finally:
        # Xoá ảnh tạm dù thành công hay lỗi
        if os.path.exists(input_path):
            os.remove(input_path)


# ── 2. TÌM KIẾM MẪU BẰNG PROMPT ─────────────────────────────────────────────
@app.post("/api/search-pattern")
async def search_pattern(req: PromptSearchRequest):
    """
    Tìm kiếm mẫu phù hợp nhất với prompt người dùng
    Dùng sentence-transformers (cosine similarity) — KHÔNG sinh ảnh mới
    
    Fallback: Nếu chưa cài sentence-transformers → tìm kiếm theo từ khóa đơn giản
    """
    library = _load_library()
    if not library:
        return {"query": req.prompt, "results": [], "message": "Thư viện trống"}

    # ── Thử dùng sentence-transformers ───────────────────────────────────
    try:
        from sentence_transformers import SentenceTransformer
        import numpy as np

        # Lazy load model — chỉ load lần đầu
        global _st_model, _st_corpus, _st_keys
        if not hasattr(app.state, "st_model"):
            app.state.st_model = SentenceTransformer(
                "paraphrase-multilingual-MiniLM-L12-v2"
            )
            keys = list(library.keys())
            # Lấy description nếu có, không thì dùng key tên
            texts = [library[k].get("description", k) for k in keys]
            app.state.st_keys = keys
            app.state.st_embeddings = app.state.st_model.encode(
                texts, normalize_embeddings=True
            )

        query_vec = app.state.st_model.encode(
            req.prompt, normalize_embeddings=True
        )
        scores = app.state.st_embeddings @ query_vec
        top_idx = np.argsort(scores)[::-1][:req.top_k]

        results = []
        for i in top_idx:
            key = app.state.st_keys[i]
            results.append({
                "id": key,
                "name": library[key].get("name", key),
                "description": library[key].get("description", ""),
                "image_path": f"renders/render_{key}.png",
                "tags": library[key].get("tags", []),
                "similarity": round(float(scores[i]), 4),
            })
        return {"query": req.prompt, "results": results}

    except ImportError:
        # ── Fallback: tìm theo từ khóa đơn giản ─────────────────────────
        prompt_lower = req.prompt.lower()
        results = []
        for key, val in library.items():
            desc = val.get("description", "") + " " + val.get("name", key)
            score = sum(1 for word in prompt_lower.split() if word in desc.lower())
            if score > 0:
                results.append({
                    "id": key,
                    "name": val.get("name", key),
                    "description": val.get("description", ""),
                    "image_path": f"renders/render_{key}.png",
                    "tags": val.get("tags", []),
                    "similarity": min(1.0, score * 0.3),
                })
        # Sắp xếp giảm dần theo score
        results.sort(key=lambda x: x["similarity"], reverse=True)
        return {"query": req.prompt, "results": results[:req.top_k]}


# ── 3. LẤY DANH SÁCH TẤT CẢ MẪU ─────────────────────────────────────────────
@app.get("/api/patterns")
async def get_all_patterns():
    """Trả về danh sách mẫu để Flutter hiển thị grid thư viện"""
    library = _load_library()
    patterns = [
        {
            "id": key,
            "name": val.get("name", key),
            "description": val.get("description", ""),
            "image_path": f"renders/render_{key}.png",
            "tags": val.get("tags", []),
        }
        for key, val in library.items()
    ]
    return {"patterns": patterns, "total": len(patterns)}


# ── 4. RENDER MẪU CỤ THỂ THEO KEY ───────────────────────────────────────────
@app.post("/api/render-pattern/{pattern_key}", response_model=RenderResponse)
async def render_pattern_by_key(pattern_key: str, request: Request):
    """
    Flutter gọi sau khi chọn một mẫu từ gợi ý hoặc thư viện
    Render lại mẫu bằng SmartWeaver3D và trả về
    """
    library = _load_library()
    if pattern_key not in library:
        raise HTTPException(404, detail=f"Không tìm thấy mẫu: {pattern_key}")

    try:
        base_url = str(request.base_url).rstrip("/")
        return _render_pattern(pattern_key, base_url)
    except Exception as e:
        raise HTTPException(500, detail=f"Lỗi render mẫu: {str(e)}")


# ── 5. ĐỔI MÀU CLUSTER VÀ RENDER LẠI ────────────────────────────────────────
@app.post("/api/edit-cluster-color", response_model=RenderResponse)
async def edit_cluster_color(req: ClusterEditRequest, request: Request):
    """
    Đổi màu của cluster_id trong matrix rồi render lại Jacquard 3D
    
    Cách hoạt động:
      1. Load matrix từ thư viện
      2. Thay tất cả pixel == cluster_id bằng new_color_id
      3. Lưu lại vào thư viện (tạo key mới để không ghi đè mẫu gốc)
      4. Render Jacquard 3D với matrix đã chỉnh
    """
    library = _load_library()
    if req.pattern_key not in library:
        raise HTTPException(404, detail=f"Không tìm thấy mẫu: {req.pattern_key}")

    if req.cluster_id < 0 or req.cluster_id > 5:
        raise HTTPException(400, detail="cluster_id phải từ 0 đến 5")
    if req.new_color_id < 0 or req.new_color_id > 5:
        raise HTTPException(400, detail="new_color_id phải từ 0 đến 5")

    # ── Lấy matrix gốc và thay màu ───────────────────────────────────────
    original = library[req.pattern_key]
    arr = np.array(original["matrix"])
    arr[arr == req.cluster_id] = req.new_color_id   # Thay tất cả pixel của cluster

    # ── Tạo key mới cho phiên bản đã chỉnh màu ───────────────────────────
    edit_id = str(uuid.uuid4())[:6]
    new_key = f"{req.pattern_key}_edit_{edit_id}"
    new_entry = {
        "color_map": original["color_map"],
        "matrix": arr.tolist(),
        "name": f"{original.get('name', req.pattern_key)} (chỉnh màu)",
        "description": original.get("description", ""),
        "tags": original.get("tags", []),
    }

    # Lưu vào thư viện
    library[new_key] = new_entry
    with open(LIBRARY_FILE, "w", encoding="utf-8") as f:
        json.dump(library, f)

    try:
        base_url = str(request.base_url).rstrip("/")
        return _render_pattern(new_key, base_url)
    except Exception as e:
        raise HTTPException(500, detail=f"Lỗi render sau khi chỉnh màu: {str(e)}")


# ── 6. GỬI MỘT HÀNG ĐẾN ESP32 ────────────────────────────────────────────────
@app.post("/api/esp32/send-row")
async def send_row_to_esp32(req: Esp32RowRequest):
    """
    Proxy: nhận lệnh từ Flutter → forward đến ESP32
    Format gửi đến ESP32: {"row_index": 0, "data": [0,1,0,...]}  (31 phần tử)
    """
    if len(req.data) != 31:
        raise HTTPException(400, detail=f"data cần đúng 31 phần tử, nhận {len(req.data)}")

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(
                f"{ESP32_BASE_URL}/row",
                json={"row_index": req.row_index, "data": req.data},
            )
            return {"success": resp.status_code == 200, "esp32_status": resp.status_code}
    except httpx.ConnectError:
        raise HTTPException(503, detail="Không kết nối được ESP32. Kiểm tra IP và mạng LAN.")
    except httpx.TimeoutException:
        raise HTTPException(504, detail="ESP32 không phản hồi (timeout 5s)")


# ── 7. PING ESP32 ─────────────────────────────────────────────────────────────
@app.get("/api/esp32/ping")
async def ping_esp32():
    """Kiểm tra kết nối đến ESP32"""
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(f"{ESP32_BASE_URL}/ping")
            return {"connected": resp.status_code == 200, "url": ESP32_BASE_URL}
    except Exception:
        return {"connected": False, "url": ESP32_BASE_URL}


# ── 8. SERVE ẢNH RENDER (endpoint cũ — giữ tương thích) ──────────────────────
@app.get("/renders/{filename}")
async def get_render_file(filename: str):
    """Trả về file ảnh Jacquard 3D (dùng khi StaticFiles không hoạt động)"""
    path = os.path.join(RENDER_DIR, filename)
    if not os.path.exists(path):
        raise HTTPException(404, detail="Không tìm thấy ảnh render")
    return FileResponse(path)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)

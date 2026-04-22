"""
main.py — Điểm khởi chạy của FastAPI backend hệ thống dệt chiếu thông minh
Đăng ký tất cả router và cấu hình CORS cho Flutter app
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os

# Import các router từ module con
from routers import render_router, pattern_router, cluster_router, esp32_router

# ── Khởi tạo ứng dụng FastAPI ──────────────────────────────────────────────
app = FastAPI(
    title="Smart Weaving API",
    description="Backend cho hệ thống dệt chiếu thông minh — xử lý ảnh, tìm mẫu, điều khiển ESP32",
    version="2.0.0",
)

# ── Cấu hình CORS để Flutter app có thể gọi API ───────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],        # Cho phép mọi origin (development)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Phục vụ file tĩnh (ảnh render) ────────────────────────────────────────
os.makedirs("static/renders", exist_ok=True)
os.makedirs("static/patterns", exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")

# ── Đăng ký các router ────────────────────────────────────────────────────
app.include_router(render_router.router,   prefix="/api", tags=["Render"])
app.include_router(pattern_router.router,  prefix="/api", tags=["Patterns"])
app.include_router(cluster_router.router,  prefix="/api", tags=["Clusters"])
app.include_router(esp32_router.router,    prefix="/api", tags=["ESP32"])


@app.get("/api/health")
async def health_check():
    """Kiểm tra trạng thái server — Flutter dùng để ping"""
    return {"status": "ok", "version": "2.0.0"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)

"""
routers/esp32_router.py — Proxy gửi lệnh đến ESP32
  POST /api/esp32/send-row    — Gửi một hàng ma trận đến ESP32
  POST /api/esp32/send-matrix — Gửi toàn bộ ma trận (theo từng hàng)
  GET  /api/esp32/ping        — Kiểm tra kết nối ESP32

Lưu ý: Backend đóng vai trò proxy, nhận lệnh từ Flutter và chuyển tiếp đến ESP32.
Có thể dùng theo 2 cách:
  1. Flutter → API → ESP32 (qua proxy này)
  2. Flutter → ESP32 trực tiếp (nếu cùng mạng LAN)
"""

import httpx
import asyncio
from fastapi import APIRouter, HTTPException
from models.schemas import Esp32RowRequest
from typing import List

router = APIRouter()

# URL mặc định của ESP32 (có thể cấu hình qua env)
import os
ESP32_BASE_URL = os.getenv("ESP32_URL", "http://192.168.1.100")


@router.post("/esp32/send-row")
async def send_row_to_esp32(req: Esp32RowRequest):
    """
    Gửi một hàng dữ liệu (31 giá trị 0/1) đến ESP32
    
    Format gửi đi:
    {
        "row_index": 0,
        "data": [0, 1, 0, 1, ..., 0]  // 31 phần tử
    }
    """
    if len(req.data) != 31:
        raise HTTPException(400, detail=f"data phải có đúng 31 phần tử, nhận được {len(req.data)}")

    payload = {
        "row_index": req.row_index,
        "data": req.data,
    }

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(f"{ESP32_BASE_URL}/row", json=payload)
            return {"success": resp.status_code == 200, "esp32_status": resp.status_code}
    except httpx.ConnectError:
        raise HTTPException(503, detail="Không thể kết nối ESP32. Kiểm tra địa chỉ IP và kết nối mạng.")
    except httpx.TimeoutException:
        raise HTTPException(504, detail="ESP32 không phản hồi (timeout)")


@router.post("/esp32/send-matrix")
async def send_matrix_to_esp32(matrix: List[List[int]], delay_ms: int = 500):
    """
    Gửi toàn bộ ma trận đến ESP32, từng hàng một
    Có delay giữa các hàng để ESP32 kịp xử lý cơ học
    
    Args:
        matrix: Ma trận 2D [[0,1,...], [1,0,...], ...]
        delay_ms: Delay giữa các hàng (ms), mặc định 500ms
    """
    results = []
    for row_idx, row in enumerate(matrix):
        # Đảm bảo đủ 31 phần tử
        padded = row[:31] + [0] * max(0, 31 - len(row))
        
        payload = {"row_index": row_idx, "data": padded}
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.post(f"{ESP32_BASE_URL}/row", json=payload)
                results.append({"row": row_idx, "success": resp.status_code == 200})
        except Exception as e:
            results.append({"row": row_idx, "success": False, "error": str(e)})

        # Delay giữa các hàng
        await asyncio.sleep(delay_ms / 1000)

    success_count = sum(1 for r in results if r["success"])
    return {
        "total_rows": len(matrix),
        "success_count": success_count,
        "results": results,
    }


@router.get("/esp32/ping")
async def ping_esp32():
    """Kiểm tra kết nối đến ESP32"""
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(f"{ESP32_BASE_URL}/ping")
            return {"connected": resp.status_code == 200, "url": ESP32_BASE_URL}
    except Exception:
        return {"connected": False, "url": ESP32_BASE_URL}

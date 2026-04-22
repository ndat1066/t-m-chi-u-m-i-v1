# 🧵 Smart Weaving System — Cấu Trúc Dự Án

## Tổng Quan Kiến Trúc

```
Flutter App  ←→  FastAPI Backend  ←→  ESP32
     ↑                 ↑
  UI/UX          Xử lý ảnh +
  LED Panel      Pattern Search
  Color Edit     (sentence-transformers)
```

## 📁 Backend (FastAPI)

```
weaving_backend/
├── main.py                        # Điểm khởi chạy, đăng ký router, CORS
├── requirements.txt               # Dependencies
├── models/
│   └── schemas.py                 # Pydantic schemas (request/response format)
├── services/
│   ├── color_service.py           # Lượng tử hóa 6 màu, cluster, thay màu
│   ├── matrix_service.py          # Chuyển ảnh → ma trận 0/1 điều khiển lever
│   └── pattern_service.py         # Tìm kiếm mẫu bằng embedding similarity
├── routers/
│   ├── render_router.py           # POST /render-from-image, /render-from-prompt
│   ├── pattern_router.py          # GET /patterns, POST /search-pattern
│   ├── cluster_router.py          # POST /edit-cluster-color
│   └── esp32_router.py            # POST /esp32/send-row, /esp32/send-matrix
├── assets/
│   └── pattern_library.json       # Thư viện mẫu dệt
└── static/
    └── renders/                   # Ảnh render output (được phục vụ qua /static)
```

## 📁 Flutter App

```
weaving_flutter/lib/
├── services/
│   └── weaving_api_service.dart   # Tất cả API calls (HTTP client duy nhất)
├── screens/
│   └── weaving_control_screen.dart # Màn hình điều khiển chính
└── widgets/
    ├── led_panel_widget.dart       # 31 LED hiển thị trạng thái lever
    ├── color_palette_widget.dart   # Bảng 6 màu + cluster editing
    ├── chat_suggest_widget.dart    # Chatbox nhập prompt + kết quả
    └── pattern_grid_widget.dart    # Grid thư viện mẫu
```

---

## 🔌 API Endpoints

| Method | Endpoint | Mô tả |
|--------|----------|-------|
| GET | `/api/health` | Kiểm tra server |
| POST | `/api/render-from-image` | Upload ảnh → render 6 màu + matrix |
| POST | `/api/render-from-prompt` | Prompt → tìm TOP K mẫu phù hợp |
| POST | `/api/render-pattern/{id}` | Render mẫu cụ thể từ thư viện |
| GET | `/api/patterns` | Lấy toàn bộ thư viện mẫu |
| POST | `/api/search-pattern` | Tìm kiếm mẫu bằng prompt |
| POST | `/api/edit-cluster-color` | Thay màu một cluster |
| POST | `/api/esp32/send-row` | Gửi một hàng đến ESP32 |
| POST | `/api/esp32/send-matrix` | Gửi toàn bộ ma trận |
| GET | `/api/esp32/ping` | Ping ESP32 |

---

## 📦 Response Format Chuẩn

```json
{
  "image_url": "/static/renders/render_abc123.png",
  "matrix": [[0,1,0,1,...], [1,0,1,0,...]],
  "clusters": [
    {"id": 0, "color": "#dc2626", "pixel_count": 1234, "percentage": 23.5},
    {"id": 1, "color": "#2563eb", "pixel_count": 987, "percentage": 18.7}
  ],
  "pattern_name": "Mẫu Caro Truyền Thống",
  "width": 31,
  "height": 48
}
```

---

## 🚀 Khởi Chạy Backend

```bash
cd weaving_backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

---

## 🎨 6 Màu Cố Định

| Index | Tên | Hex |
|-------|-----|-----|
| 0 | Đỏ | `#dc2626` |
| 1 | Xanh dương | `#2563eb` |
| 2 | Tím | `#7c3aed` |
| 3 | Xanh lá | `#16a34a` |
| 4 | Vàng | `#eab308` |
| 5 | Trắng | `#ffffff` |

---

## 🧠 Pattern Search (Embedding)

Model sử dụng: `paraphrase-multilingual-MiniLM-L12-v2`
- Hỗ trợ tiếng Việt và tiếng Anh
- ~120MB, inference nhanh (<100ms trên CPU)
- Cosine similarity để tìm TOP K mẫu phù hợp nhất

**KHÔNG sinh ảnh mới** — chỉ tìm mẫu có sẵn trong thư viện

---

## ⚡ Logic Ma Trận Dệt

```
Ảnh gốc → Resize (chiều rộng = 31px) → Quantize 6 màu
→ Xác định màu nền (phổ biến nhất)
→ Pixel ≠ nền → 1 (kéo lever/LED sáng)
→ Pixel = nền → 0 (giữ lever/LED tắt)
→ Quy tắc: tối đa 2 màu/hàng
```

---

## 📡 Giao Thức ESP32

```json
POST /row
{
  "row_index": 0,
  "data": [0, 1, 0, 1, 0, 0, 1, ...]  // 31 giá trị 0/1
}
```

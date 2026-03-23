# EMA CO v1.04 — Tài Liệu Thuật Toán

**File:** `EMA_CO_v1.04.mq5`
**Phiên bản:** 1.04
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

**EMA CO** (EMA Crossover) là EA giao dịch theo xu hướng dựa trên tín hiệu giao cắt giữa hai đường EMA. Phiên bản v1.04 tối ưu hoá tham số và làm sạch code.

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết (v1.04 so với v1.03) |
|-----------|-------------------------------|
| Tối ưu hoá tham số | Tinh chỉnh các giá trị mặc định, làm sạch code. |
| Bỏ EMA 200 filter | Không còn bộ lọc xu hướng dài hạn. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `LotSize` | 0.01 | Lot size cố định mỗi lệnh |
| `ShortPeriod` | 10 | Chu kỳ EMA ngắn |
| `LongPeriod` | 20 | Chu kỳ EMA dài |
| `MagicNumber` | 6 | Magic number |

---

## 4. Chi tiết thuật toán

### 4.1. Điều kiện Vào Lệnh

**BUY:**
```
Short EMA[1] > Long EMA[1]  AND  Short EMA[2] <= Long EMA[2]
→ Mở lệnh BUY
```

### 4.2. Điều kiện Thoát Lệnh

```
Short EMA[1] < Long EMA[1]
→ Đóng vị thế
```

---

## 5. Lưu ý rủi ro & Backtest

> [!WARNING]
> Không có SL cứng. Không có bộ lọc xu hướng. Rủi ro cao khi thị trường sideway hoặc đảo chiều mạnh.

- **Backtest Option:** Bắt buộc dùng **Every Tick based on real ticks**.

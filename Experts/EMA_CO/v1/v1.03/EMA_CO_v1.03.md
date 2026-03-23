# EMA CO v1.03 — Tài Liệu Thuật Toán

**File:** `EMA_CO_v1.03.mq5`
**Phiên bản:** 1.03
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

**EMA CO** (EMA Crossover) là EA giao dịch theo xu hướng dựa trên tín hiệu giao cắt giữa hai đường EMA. Phiên bản v1.03 bỏ SL cố định theo pips, quay lại thoát bằng tín hiệu ngược, nhưng thêm bộ lọc xu hướng dài hạn EMA 200.

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết (v1.03 so với v1.02) |
|-----------|-------------------------------|
| Bộ lọc xu hướng EMA 200 | Chỉ mở lệnh BUY khi giá nằm trên EMA 200. Lọc bớt tín hiệu sai trong thị trường giảm. |
| Bỏ SL pips | Không còn `StopLossPips`. Thoát lệnh bằng tín hiệu giao cắt ngược. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `LotSize` | 0.01 | Lot size cố định mỗi lệnh |
| `ShortPeriod` | 10 | Chu kỳ EMA ngắn |
| `LongPeriod` | 20 | Chu kỳ EMA dài |
| `MagicNumber` | 5 | Magic number |

---

## 4. Chi tiết thuật toán

### 4.1. Điều kiện Vào Lệnh

**BUY:**
```
1. Price > EMA(200)                                    → Xác nhận uptrend dài hạn
2. Short EMA[1] > Long EMA[1] AND Short EMA[2] <= Long EMA[2]  → Golden Cross
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
> Không có SL cứng. Nếu giá giảm nhanh mà không có tín hiệu giao cắt ngược, lệnh sẽ lỗ lớn trước khi được đóng. EMA 200 giúp lọc nhưng không loại bỏ hoàn toàn rủi ro.

- **Backtest Option:** Bắt buộc dùng **Every Tick based on real ticks**.

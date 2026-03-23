# EMA CO v1.05 — Tài Liệu Thuật Toán

**File:** `EMA_CO_v1.05.mq5`
**Phiên bản:** 1.05
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

**EMA CO** (EMA Crossover) là EA giao dịch theo xu hướng dựa trên tín hiệu giao cắt giữa hai đường EMA. Phiên bản v1.05 kết hợp lại bộ lọc EMA 200, ATR-based SL, và tỉ lệ RR để tính TP.

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết (v1.05 so với v1.04) |
|-----------|-------------------------------|
| Bộ lọc EMA 200 | Thêm lại `LongtermPeriod` = 200. Chỉ BUY khi giá trên EMA 200. |
| ATR-based SL | Bổ sung `ATR_Period` và `ATR_Multiplier` để tính SL động theo biến động thị trường. |
| TP theo RR | Bổ sung `RR_Ratio` — TP = SL_distance × RR. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `LotSize` | 0.01 | Lot size cố định mỗi lệnh |
| `ShortPeriod` | 10 | Chu kỳ EMA ngắn |
| `LongPeriod` | 20 | Chu kỳ EMA dài |
| `LongtermPeriod` | 200 | Chu kỳ EMA dài hạn (bộ lọc xu hướng) |
| `MagicNumber` | 7 | Magic number |

### ==== Risk Management ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `ATR_Period` | 14 | Chu kỳ tính ATR |
| `ATR_Multiplier` | 1.5 | Hệ số nhân ATR để tính SL |
| `RR_Ratio` | 2.0 | Tỉ lệ Risk:Reward để tính TP |

---

## 4. Chi tiết thuật toán

### 4.1. Điều kiện Vào Lệnh

**BUY:**
```
1. Price > EMA(200)                                    → Xác nhận uptrend dài hạn
2. Short EMA[1] > Long EMA[1] AND Short EMA[2] <= Long EMA[2]  → Golden Cross
→ Mở lệnh BUY
→ SL = Entry - (ATR × ATR_Multiplier)
→ TP = Entry + (SL_distance × RR_Ratio)
```

### 4.2. Điều kiện Thoát Lệnh

```
1. TP hit
2. SL hit
3. Tín hiệu giao cắt ngược: Short EMA[1] < Long EMA[1]
```

---

## 5. Lưu ý rủi ro & Backtest

> [!WARNING]
> EA chỉ giao dịch chiều BUY. Trong thị trường giảm kéo dài (giá dưới EMA 200) sẽ không có tín hiệu. EMA crossover có độ trễ tự nhiên.

- **Backtest Option:** Bắt buộc dùng **Every Tick based on real ticks**.

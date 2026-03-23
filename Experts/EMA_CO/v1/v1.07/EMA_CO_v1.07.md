# EMA CO v1.07 — Tài Liệu Thuật Toán

**File:** `EMA_CO_v1.07.mq5`
**Phiên bản:** 1.07
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

**EMA CO** (EMA Crossover) là EA giao dịch theo xu hướng dựa trên tín hiệu giao cắt giữa hai đường EMA. Phiên bản v1.07 bỏ bộ lọc EMA 200, chuyển sang dùng EMA 9/21 với ATR-based SL/TP và tỉ lệ RR.

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết (v1.07 so với v1.06) |
|-----------|-------------------------------|
| EMA periods | Chuyển từ 10/20 sang 9/21 — nhạy hơn với biến động ngắn hạn. |
| Bỏ EMA 200 filter | Không còn bộ lọc xu hướng dài hạn. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `LotSize` | 0.01 | Lot size cố định mỗi lệnh |
| `ShortPeriod` | 9 | Chu kỳ EMA ngắn |
| `LongPeriod` | 21 | Chu kỳ EMA dài |
| `MagicNumber` | 9 | Magic number |

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
Short EMA(9)[1] > Long EMA(21)[1]  AND  Short EMA(9)[2] <= Long EMA(21)[2]
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
> Không có bộ lọc xu hướng dài hạn. EMA 9/21 nhạy hơn nhưng cũng tạo nhiều tín hiệu giả hơn trong thị trường sideway.

- **Backtest Option:** Bắt buộc dùng **Every Tick based on real ticks**.

# EMA CO v1.06 — Tài Liệu Thuật Toán

**File:** `EMA_CO_v1.06.mq5`
**Phiên bản:** 1.06
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

**EMA CO** (EMA Crossover) là EA giao dịch theo xu hướng dựa trên tín hiệu giao cắt giữa hai đường EMA. Phiên bản v1.06 giữ nguyên bộ lọc EMA 200 + ATR SL/TP từ v1.05, tập trung cải thiện logic xác nhận tín hiệu vào lệnh.

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết (v1.06 so với v1.05) |
|-----------|-------------------------------|
| Xác nhận đa tín hiệu | Cải thiện logic entry với nhiều điều kiện xác nhận đồng thời thay vì chỉ dựa vào crossover đơn. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `LotSize` | 0.01 | Lot size cố định mỗi lệnh |
| `ShortPeriod` | 10 | Chu kỳ EMA ngắn |
| `LongPeriod` | 20 | Chu kỳ EMA dài |
| `LongtermPeriod` | 200 | Chu kỳ EMA dài hạn (bộ lọc xu hướng) |
| `MagicNumber` | 8 | Magic number |

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
1. Price > EMA(200)                    → Xác nhận uptrend dài hạn
2. Short EMA > Long EMA               → Xu hướng ngắn hạn bullish
3. Crossover xác nhận                  → Golden Cross
→ Mở lệnh BUY
→ SL = Entry - (ATR × ATR_Multiplier)
→ TP = Entry + (SL_distance × RR_Ratio)
```

### 4.2. Điều kiện Thoát Lệnh

```
1. TP hit
2. SL hit
3. Tín hiệu giao cắt ngược
```

---

## 5. Lưu ý rủi ro & Backtest

> [!WARNING]
> EA chỉ giao dịch chiều BUY. Bộ lọc EMA 200 + xác nhận đa tín hiệu giúp tăng winrate nhưng giảm số lượng lệnh.

- **Backtest Option:** Bắt buộc dùng **Every Tick based on real ticks**.

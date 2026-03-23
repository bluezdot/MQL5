# EMA CO v1.01 — Tài Liệu Thuật Toán

**File:** `EMA_CO_v1.01.mq5`
**Phiên bản:** 1.01
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

**EMA CO** (EMA Crossover) là EA giao dịch theo xu hướng dựa trên tín hiệu giao cắt giữa hai đường EMA. Phiên bản v1.01 là bản phát hành đầu tiên thuộc dòng EMA CO. EA sử dụng ATR để tính SL/TP động, kết hợp tỉ lệ RR cố định.

---

## 2. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `LotSize` | 0.01 | Lot size cố định mỗi lệnh |
| `ShortPeriod` | 9 | Chu kỳ EMA ngắn (nhanh) |
| `LongPeriod` | 21 | Chu kỳ EMA dài (chậm) |
| `MagicNumber` | 3 | Magic number |

### ==== Risk Management ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `ATR_Period` | 14 | Chu kỳ tính ATR |
| `ATR_Multiplier` | 1.5 | Hệ số nhân ATR để tính khoảng cách SL |
| `RR_Ratio` | 2.0 | Tỉ lệ Risk:Reward để tính TP từ SL |

---

## 3. Chi tiết thuật toán

### 3.1. Điều kiện Vào Lệnh

**BUY:**
```
Short EMA[1] > Long EMA[1]  AND  Short EMA[2] <= Long EMA[2]
→ EMA ngắn cắt lên trên EMA dài (Golden Cross)
→ Mở lệnh BUY
```

### 3.2. Điều kiện Thoát Lệnh

```
1. TP hit: Entry + (SL_distance × RR_Ratio)
2. SL hit: Entry - (ATR × ATR_Multiplier)
3. Tín hiệu giao cắt ngược: Short EMA[1] < Long EMA[1] → đóng vị thế
```

### 3.3. Tính toán SL/TP

- `SL = Entry - ATR(14) × 1.5`
- `TP = Entry + SL_distance × RR_Ratio`

---

## 4. Lưu ý rủi ro & Backtest

> [!WARNING]
> EA chỉ giao dịch chiều BUY, không có lệnh SELL. Trong thị trường giảm kéo dài sẽ không có tín hiệu vào lệnh. Tín hiệu EMA crossover có độ trễ tự nhiên (lagging indicator).

- **Backtest Option:** Bắt buộc dùng **Every Tick based on real ticks**.

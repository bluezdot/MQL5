# EMA CO v1.02 — Tài Liệu Thuật Toán

**File:** `EMA_CO_v1.02.mq5`
**Phiên bản:** 1.02
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

**EMA CO** (EMA Crossover) là EA giao dịch theo xu hướng dựa trên tín hiệu giao cắt giữa hai đường EMA. Phiên bản v1.02 bổ sung Stop Loss cố định theo pips.

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết (v1.02 so với v1.01) |
|-----------|-------------------------------|
| SL theo Pips | Bổ sung `StopLossPips` — SL cố định theo pips thay vì chỉ thoát bằng tín hiệu ngược. |
| TP theo RR | Bổ sung `RR_Ratio` — TP tính từ SL × tỉ lệ RR. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `LotSize` | 0.01 | Lot size cố định mỗi lệnh |
| `ShortPeriod` | 10 | Chu kỳ EMA ngắn |
| `LongPeriod` | 20 | Chu kỳ EMA dài |
| `MagicNumber` | 4 | Magic number |

### ==== Risk Management ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `StopLossPips` | 400 | Stop Loss cố định tính bằng pips |
| `RR_Ratio` | 2.0 | Tỉ lệ Risk:Reward để tính TP từ SL |

---

## 4. Chi tiết thuật toán

### 4.1. Điều kiện Vào Lệnh

**BUY:**
```
Short EMA[1] > Long EMA[1]  AND  Short EMA[2] <= Long EMA[2]
→ Mở lệnh BUY với SL và TP
```

### 4.2. Điều kiện Thoát Lệnh

```
1. SL hit: Entry - StopLossPips
2. TP hit: Entry + (StopLossPips × RR_Ratio)
3. Tín hiệu giao cắt ngược: Short EMA[1] < Long EMA[1]
```

---

## 5. Lưu ý rủi ro & Backtest

> [!WARNING]
> SL cố định theo pips không thích ứng với biến động thị trường. Trong giai đoạn volatility cao, SL có thể quá gần; trong giai đoạn volatility thấp, SL có thể quá xa.

- **Backtest Option:** Bắt buộc dùng **Every Tick based on real ticks**.

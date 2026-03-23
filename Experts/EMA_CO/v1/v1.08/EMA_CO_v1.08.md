# EMA CO v1.08 — Tài Liệu Thuật Toán

**File:** `EMA_CO_v1.08.mq5`
**Phiên bản:** 1.08
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

**EMA CO** (EMA Crossover) là EA giao dịch theo xu hướng dựa trên tín hiệu giao cắt giữa hai đường EMA. Phiên bản v1.08 là bản hoàn thiện nhất của dòng v1.x, sử dụng EMA 9/21, ATR-based SL, và `TP_Multiplier` thay cho `RR_Ratio`.

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết (v1.08 so với v1.07) |
|-----------|-------------------------------|
| TP logic thay đổi | Dùng `TP_Multiplier` (nhân trực tiếp với ATR) thay vì `RR_Ratio` (nhân với SL distance). |
| Code refactor | Cấu trúc code được làm sạch và tối ưu. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `LotSize` | 0.01 | Lot size cố định mỗi lệnh |
| `ShortPeriod` | 9 | Chu kỳ EMA ngắn |
| `LongPeriod` | 21 | Chu kỳ EMA dài |
| `MagicNumber` | 10 | Magic number |

### ==== Risk Management ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `ATR_Period` | 14 | Chu kỳ tính ATR |
| `ATR_Multiplier` | 1.5 | Hệ số nhân ATR để tính SL |
| `TP_Multiplier` | 1.0 | Hệ số nhân ATR để tính TP |

---

## 4. Chi tiết thuật toán

### 4.1. Điều kiện Vào Lệnh

**BUY:**
```
Short EMA(9)[1] > Long EMA(21)[1]  AND  Short EMA(9)[2] <= Long EMA(21)[2]
→ Mở lệnh BUY
→ SL = Entry - (ATR × ATR_Multiplier)
→ TP = Entry + (ATR × TP_Multiplier)
```

### 4.2. Điều kiện Thoát Lệnh

```
1. TP hit
2. SL hit
3. Tín hiệu giao cắt ngược: Short EMA[1] < Long EMA[1]
```

---

## 5. Ví dụ cấu hình khuyến nghị

| Timeframe | `ShortPeriod` | `LongPeriod` | `ATR_Multiplier` |
|-----------|:-------------:|:------------:|:-----------------:|
| M15 | 9 | 21 | 1.5 |
| H1 | 9 | 21 | 2.0 |
| H4 | 10 | 20 | 2.5 |

---

## 6. Lưu ý rủi ro & Backtest

> [!WARNING]
> Không có bộ lọc xu hướng dài hạn. `TP_Multiplier = 1.0` mặc định cho TP bằng ATR — tỉ lệ RR phụ thuộc vào `ATR_Multiplier / TP_Multiplier`. Với cấu hình mặc định (SL = 1.5 ATR, TP = 1.0 ATR), RR < 1.

- **Backtest Option:** Bắt buộc dùng **Every Tick based on real ticks**.

# MFR DCA v1.00 — Tài Liệu Thuật Toán

**File:** `MFR_DCA_v1.00.mq5`
**Phiên bản:** 1.00
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

**MFR DCA** (Martingale Fibonacci Retracement DCA) kết hợp ba kỹ thuật:
1. **Trend Detection** — Nhận diện xu hướng tăng/giảm dựa trên `N` nến liên tiếp đóng cùng chiều.
2. **Fibonacci Retracement Grid** — Khi giá pullback, xác định anchor/limit của xu hướng, đặt lưới 10 lệnh Limit tại các mức Fibo (0.236 → 4.236).
3. **Martingale Lot Sizing** — Lot mỗi mức tăng theo dãy Fibonacci (×1, ×1, ×2, ×3, ×5, ×8, ×13, ×21, ×34, ×55).

---

## 2. Tham số cấu hình - Input Parameters

| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpBaseLot` | 0.01 | Lot size cơ bản |
| `InpBaseTrendRange` | 100 | Tổng biên độ tối thiểu (points) để xác nhận trend |
| `InpBaseTrendCandles` | 3 | Số nến xu hướng liên tiếp để xác nhận trend |
| `InpMagicNumber` | 13 | Magic number |

---

## 3. Chi tiết thuật toán

### 3.1. Xác định Xu hướng (`ScanForTrend`)

- **Buy:** `N` nến liên tiếp đóng tăng (`close[i] > close[i+1]`)
- **Sell:** `N` nến liên tiếp đóng giảm (`close[i] < close[i+1]`)
- Tổng biên độ ≥ `InpBaseTrendRange × _Point`
- Pullback: nến hiện tại đóng ngược chiều nến trước

### 3.2 Tìm Swing High/Low (`FindSwingHigh`, `FindSwingLow`)

Duyệt tối đa `InpMaxFindSwingCandles` nến để tìm đỉnh/đáy cục bộ.

### 3.3 Lưới Fibonacci DCA (`SetupDCAChain`)

| Index | Fibo Level | Lot Multiplier |
|:-----:|:----------:|:--------------:|
| 0 | 0.236 | ×1 |
| 1 | 0.382 | ×1 |
| 2 | 0.500 | ×2 |
| 3 | 0.618 | ×3 |
| 4 | 0.786 | ×5 |
| 5 | 1.000 | ×8 |
| 6 | 1.618 | ×13 |
| 7 | 2.618 | ×21 |
| 8 | 3.618 | ×34 |
| 9 | 4.236 | ×55 |

**Tổng lot nếu tất cả khớp = 143 × BaseLot**

### 3.4 Take Profit động (`UpdateTP`)

TP được tính lại mỗi tick dựa trên mức Fibo xấu nhất đang khớp:
- Tìm giá entry xấu nhất (thấp nhất với Buy, cao nhất với SELL)
- TP = mức Fibo một bậc trước (gần điểm neo hơn)

### 3.5 Quản lý Chain (`CheckAndManageChain`)

| Trường hợp | Điều kiện | Hành động |
|---|---|---|
| Chưa khớp lệnh, giá phá swing | `!hasPos && price >= swingHigh` (Buy) | Reset |
| TP đã hit, còn limit treo | `hadPositions && !hasPos` | Reset |
| Không còn gì quản lý | `!hasPos && !hasPendingOrders` | Reset |

---

## 4. Mô tả kỹ thuật

---

## 5. Ví dụ cấu hình khuyến nghị

`InpBaseTrendRange = 10000` với XAUUSD M15 hoặc `InpBaseTrendRange = 30000` với XAUUSD M30

---

## 6. Lưu ý rủi ro & Backtest

> [!WARNING]
> **Không Có Stop Loss**. Rủi ro cực cao khi vượt qua tất cả level 

- **Backtest Option:** Bắt buộc cài **Every Tick based on Real Tick**.

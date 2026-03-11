# MFR DCA v2 — Documentation

**File:** `MFR_DCA_v2.mq5`

**Phiên bản:** 2.00

---

## 1. Tổng quan chiến lược (Martingale Fibonacci Retracement DCA)

### Ý tưởng cốt lõi

**MFR DCA** kết hợp ba kỹ thuật:

1. **Trend Detection (Xu hướng)** — Nhận diện xu hướng tăng/giảm dựa trên chuỗi nến liên tiếp đóng cùng chiều và tổng biên độ vượt ngưỡng tối thiểu.
2. **Fibonacci Retracement Grid** — Khi giá pullback về phía ngược chiều xu hướng, bot đặt lưới lệnh Limit tại 10 mức Fibonacci retracement (0.236 → 4.236) tính từ điểm neo **Swing High/Low**.
3. **Martingale Lot Sizing** — Mỗi mức Fibo sâu hơn sẽ có lot size lớn hơn theo dãy Fibonacci (1, 1, 2, 3, 5, 8, 13, 21, 34, 55 × BaseLot), nhằm đạt breakeven và có lãi khi giá phục hồi.

### Luồng tổng quát

```
[Scan Trend] → Nhận diện pullback → [Setup DCA Chain] → Lệnh Limit khớp dần
     ↑                                                          ↓
     |                                                   [Update TP]
     |                                                          ↓
  [Reset Chain] ← ────────────────────────── [CheckAndManageChain]
                         (nếu hit SL / TP xong / giá phá swing)
```

---

## 2. Nguyên lý hoạt động chi tiết

### 2.1 Xác định Xu hướng (`ScanForTrend`)

Bot kiểm tra **mỗi tick** (nếu chain chưa active) để tìm xu hướng:

- **Điều kiện xu hướng TĂNG (Buy):**
  - `N` nến gần nhất (`InpBaseTrendCandles`) đóng **tăng dần** (close[i] > close[i+1]).
  - Tổng biên độ `(high - low)` của `N` nến đó ≥ `InpBaseTrendRange × _Point`.
  - Nến **hiện tại (index 0)** đóng **dưới low** của nến trước (index 1) → pullback bắt đầu.

- **Điều kiện xu hướng GIẢM (Sell):**
  - `N` nến liên tiếp đóng **giảm dần**.
  - Tổng biên độ ≥ ngưỡng.
  - Nến hiện tại đóng **trên high** của nến trước → pullback bắt đầu.

### 2.2 Tìm Swing High / Low (`FindSwingHigh`, `FindSwingLow`)

Sau khi xác nhận pullback, bot tìm điểm neo:

- **Buy Chain** → Swing High là high cao nhất của `N` nến xu hướng + nến hiện tại. Swing Low = đáy cục bộ tìm xuống mảng nến (dừng khi `low[i] < low[i+1]`, tối đa `InpMaxFindSwingCandles` nến).
- **Sell Chain** → Swing Low là low thấp nhất. Swing High = đỉnh cục bộ.

### 2.3 Thiết lập lưới Fibonacci DCA (`SetupDCAChain`)

Từ cặp điểm neo `(f0, f1)`, bot tính 10 mức Fibo:

```
diff = |f0 - f1|

Mức Fibo i:     price = f0 - fiboLevels[i] × diff   (Buy)
                price = f0 + fiboLevels[i] × diff   (Sell)
```

| Index | Fibo Level | Lot Multiplier (× BaseLot) |
|:-----:|:----------:|:--------------------------:|
|   0   |   0.236    |             ×1             |
|   1   |   0.382    |             ×1             |
|   2   |   0.500    |             ×2             |
|   3   |   0.618    |             ×3             |
|   4   |   0.786    |             ×5             |
|   5   |   1.000    |             ×8             |
|   6   |   1.618    |            ×13             |
|   7   |   2.618    |            ×21             |
|   8   |   3.618    |            ×34             |
|   9   |   4.236    |            ×55             |

> **Lưu ý:** Lot multiplier tuân theo dãy Fibonacci (1,1,2,3,5,8,13,21,34,55). Tổng lot nếu tất cả khớp = 143 × BaseLot. Quản lý vốn cẩn thận!

### 2.4 Cập nhật Take Profit động (`UpdateTP`)

TP được tính lại **mỗi tick** dựa trên mức Fibo **xấu nhất** đang có vị thế:

1. Tìm giá entry **xấu nhất** (BUY: thấp nhất; SELL: cao nhất) trong tất cả vị thế đang mở.
2. Tìm **index Fibo** (`deepestIdx`) gần nhất với giá entry đó.
3. TP = mức Fibo **một bậc trước** (`deepestIdx - 1`) — tức là một bước gần điểm neo hơn.
   - Nếu `deepestIdx == 0`: TP = Swing High (Buy) / Swing Low (Sell).
4. Áp dụng TP mới cho **tất cả** vị thế cùng chiều nếu TP thay đổi > `_Point`.

> **Ví dụ (Buy):** Nếu lệnh sâu nhất đang ở Fibo 0.618 (index 3), TP sẽ là mức Fibo 0.382 (index 2). Khi lệnh ở Fibo 1.000 (index 5), TP sẽ trượt về mức 0.786.

### 2.5 Stop Loss theo nến đóng (`CheckStopLoss`)

Chỉ kiểm tra **1 lần/nến** (phát hiện nến mới qua `lastBar`):

- **Buy Chain:** Nếu giá đóng của nến vừa hoàn thành < mức Fibo 4.236 của chain → cắt lỗ toàn bộ vị thế Buy, reset chain.
- **Sell Chain:** Nếu giá đóng > mức Fibo 4.236 của chain → cắt lỗ toàn bộ vị thế Sell, reset chain.

> Mức **Fibo 4.236** là lệnh Limit sâu nhất trong lưới, vì vậy đây là ngưỡng "kịch sàn" của chiến lược.

### 2.6 Quản lý và Reset Chain (`CheckAndManageChain`, `ResetChain`)

Mỗi tick, bot kiểm tra trạng thái chain:

| Trường hợp | Điều kiện | Hành động |
|---|---|---|
| Chưa khớp lệnh nào, giá phá swing | `!hasPos && currentPrice >= swingHigh` (Buy) | Reset chain |
| TP đã chốt toàn bộ, còn lệnh treo | `hadPositions == true && !hasPos` | Hủy limit còn lại, reset |
| Không có vị thế + không có limit treo | `!hasPos && !hasPendingOrders` | Reset chain |

`ResetChain` sẽ:
- Hủy tất cả lệnh Limit đang treo cùng chiều (`CancelAllLimits`)
- Đặt `active = false`, `hadPositions = false`
- Reset `swingHigh` và `swingLow` về 0

---

## 3. Sơ đồ trạng thái Chain

```
         [Không active]
               |
               | ScanForTrend() phát hiện xu hướng + pullback
               ↓
          [Active] ──────── SetupDCAChain() đặt 10 lệnh BuyLimit/SellLimit
               |
               | ← Lệnh Limit khớp dần (vào thị trường)
               | ← UpdateTP() chạy mỗi tick
               | ← CheckStopLoss() chạy mỗi nến
               |
      ┌─────────────────────────────────────┐
      │  CheckAndManageChain()              │
      │  1. Giá phá swing ngược chiều ?     │── → Reset
      │  2. TP đã hit, còn limit treo?      │── → Reset
      │  3. Không còn gì để quản lý?        │── → Reset
      └─────────────────────────────────────┘
               |
               ↓
         [Không active] → ScanForTrend() tiếp tục
```

---

## 4. Input Parameters

| Input | Default | Mô tả |
|---|---|---|
| `InpBaseLot` | 0.01 | Lot size cơ bản (× 1). Lot thực tế từng mức = `InpBaseLot × fiboMult[i]` |
| `InpBaseTrendRange` | 10000 | Tổng biên độ tối thiểu (points) của `N` nến xu hướng. **M15:** dùng 10000; **M30:** dùng 30000 (ghi chú trong code) |
| `InpBaseTrendCandles` | 3 | Số nến xu hướng liên tiếp cần xác nhận |
| `InpMaxFindSwingCandles` | 20 | Số nến tối đa dùng để tìm Swing High/Low |
| `InpMagicNumber` | 123456 | Magic number phân biệt các EA |

### Tham số quan trọng cần chú ý

> **`InpBaseTrendRange`** cần hiệu chỉnh theo timeframe:
> - M15 → `10000`
> - M30 → `30000`
>
> Giá trị này kiểm soát "bộ lọc trend": quá nhỏ sẽ vào lệnh với mọi noise nhỏ, quá lớn sẽ bỏ lỡ nhiều cơ hội.

> **`InpBaseLot`** cần được tính toán kỹ. Vì multiplier tối đa là ×55, tổng exposure nếu đầy đủ 10 lệnh là **143 × BaseLot**. Với account $10,000 và BaseLot = 0.01, rủi ro tối đa ≈ 1.43 lot.

---

## 5. Cấu trúc dữ liệu

### `TrendState` struct

```cpp
struct TrendState {
    bool   active;         // Chain có đang hoạt động không
    double swingHigh;      // Điểm neo cao (anchor)
    double swingLow;       // Điểm neo thấp (anchor)
    int    direction;      // 1 = Buy chain, -1 = Sell chain
    bool   hadPositions;   // Đã từng có vị thế fill trong chain này
};
```

### Biến toàn cục

| Biến | Loại | Mô tả |
|---|---|---|
| `buyChain` | `TrendState` | Trạng thái chain Buy |
| `sellChain` | `TrendState` | Trạng thái chain Sell |
| `fiboLevels[]` | `double[10]` | `{0.236, 0.382, 0.5, 0.618, 0.786, 1.0, 1.618, 2.618, 3.618, 4.236}` |
| `fiboMult[]` | `int[10]` | `{1, 1, 2, 3, 5, 8, 13, 21, 34, 55}` |
| `trade` | `CTrade` | Đối tượng giao dịch MQL5 |

---

## 6. Chi tiết các hàm

### `OnTick()` — Hàm chính (dòng 49)

Thứ tự ưu tiên mỗi tick:

1. `CheckStopLoss()` — Kiểm tra cắt lỗ theo nến đóng **(ưu tiên cao nhất)**
2. `CheckAndManageChain(buyChain)` — Quản lý Buy chain
3. `CheckAndManageChain(sellChain)` — Quản lý Sell chain
4. Nếu `buyChain.active == false` → `ScanForTrend(true)` — Tìm xu hướng Buy mới
5. Nếu `sellChain.active == false` → `ScanForTrend(false)` — Tìm xu hướng Sell mới
6. `UpdateTP(1)` — Cập nhật TP cho Buy
7. `UpdateTP(-1)` — Cập nhật TP cho Sell

---

### `ScanForTrend(bool isBuy)` (dòng 124)

Copy `max(InpBaseTrendCandles+2, InpMaxFindSwingCandles+2)` nến gần nhất. Kiểm tra:
- Điều kiện xu hướng (đủ `N` nến liên tiếp, đủ range)  
- Điều kiện pullback (nến hiện tại đóng ngược chiều nến trước)

Nếu đủ điều kiện → gọi `SetupDCAChain()`.

---

### `FindSwingLow(rates[])` / `FindSwingHigh(rates[])` (dòng 169, 175)

Duyệt từ `i=1` đến `InpMaxFindSwingCandles`, tìm điểm thấp nhất/cao nhất cục bộ:
- `FindSwingLow`: dừng khi `rates[i].low < rates[i+1].low` → trả về `rates[i].low`
- `FindSwingHigh`: dừng khi `rates[i].high > rates[i+1].high` → trả về `rates[i].high`

---

### `SetupDCAChain(int dir, double f0, double f1)` (dòng 184)

Đặt 10 lệnh Limit cùng lúc khi chain được kích hoạt:

```
Buy:  BuyLimit  tại f0 - fiboLevels[i] × diff  (kéo xuống từ Swing High)
Sell: SellLimit tại f0 + fiboLevels[i] × diff  (kéo lên từ Swing Low)
```

Lot mỗi mức = `InpBaseLot × fiboMult[i]`.

---

### `UpdateTP(int dir)` (dòng 208)

Chạy mỗi tick. Tính TP mới dựa trên vị thế "xấu nhất" đang mở (giá vào thấp nhất với Buy, cao nhất với Sell), tra cứu index Fibo tương ứng, sau đó đặt TP = Fibo level một bậc trên (gần điểm neo hơn).

---

### `CheckStopLoss()` (dòng 84)

Chỉ kích hoạt **1 lần/nến** (guard bằng `lastBar`). Dùng giá đóng cửa nến index 1:
- **Buy SL**: `closedClose < swingHigh - 4.236 × diff`
- **Sell SL**: `closedClose > swingLow + 4.236 × diff`

---

### `CheckAndManageChain(TrendState &state)` (dòng 271)

Xử lý 3 điều kiện reset (xem bảng ở mục 2.6). Hàm này chạy mỗi tick, không thực hiện gì nếu chain không `active`.

---

### `ResetChain(TrendState &state)` (dòng 307)

Hủy toàn bộ limit orders cùng chiều, reset struct về trạng thái ban đầu.

---

### Hàm tiện ích

| Hàm | Mô tả |
|---|---|
| `HasPositions(int dir)` | Kiểm tra có vị thế đang mở theo hướng `dir` không |
| `HasPendingLimits(int dir)` | Kiểm tra có lệnh Limit treo theo hướng `dir` không |
| `CancelAllLimits(int dir)` | Hủy toàn bộ lệnh Limit theo hướng `dir` |
| `CloseAllPositions(int dir)` | Đóng toàn bộ vị thế theo hướng `dir` |

---

## 7. Luồng ví dụ thực tế (Buy Chain — M15)

**Giả sử:** BaseLot = 0.01, InpBaseTrendCandles = 3, InpBaseTrendRange = 10000

```
Nến 1 (close 2050), Nến 2 (close 2060), Nến 3 (close 2070)
→ Xu hướng TĂNG, tổng range >= 10000 pts

Nến 4: close THẤP hơn low nến 3 → Pullback được xác nhận

SwingHigh = 2070 (high của nến 1-3 + nến hiện tại)
SwingLow  = 2045 (swing low cục bộ tìm được, ví dụ)

diff = 2070 - 2045 = 25 (pips/giá)

Lưới lệnh BuyLimit:
  Fibo 0.236 → 2070 - 0.236×25 = 2064.1  → 0.01 lot
  Fibo 0.382 → 2070 - 0.382×25 = 2060.45 → 0.01 lot
  Fibo 0.500 → 2070 - 0.500×25 = 2057.5  → 0.02 lot
  Fibo 0.618 → 2070 - 0.618×25 = 2054.55 → 0.03 lot
  ...
  Fibo 4.236 → 2070 - 4.236×25 = 1964.1  → 0.55 lot  (SL trigger)

Khi chỉ có lệnh ở Fibo 0.382 khớp:
  TP = SwingHigh = 2070  (deepestIdx=1, lùi về idx=0 → TP = swingHigh)

Khi thêm lệnh ở Fibo 0.500 khớp:
  TP điều chỉnh → mức Fibo 0.382 = 2060.45  (deepestIdx=2, lùi về idx=1)
```

---

## 8. Lưu ý quan trọng

### Rủi ro Martingale

> [!WARNING]
> Lot size tăng theo dãy Fibonacci. Khi thị trường đi ngược chiều liên tục, exposure có thể rất lớn. **Luôn test kỹ trên demo trước khi dùng thật.**

### Không có SL cứng (Fixed SL)

- SL duy nhất là giá đóng nến vượt mức Fibo 4.236.
- Nếu thị trường có gap hoặc spike mạnh, giá đóng nến có thể sâu hơn nhiều so với Fibo 4.236 trước khi SL kích hoạt.

### Bot chạy song song 2 chain

- `buyChain` và `sellChain` hoàn toàn độc lập.
- Có thể có cả 2 chain cùng active (Buy và Sell cùng lúc) nếu điều kiện xuất hiện.

### Cải tiến so với v1

```
// Improved so với V1
// - Fix Rule đặt TP
// - Fix Rule Reset Chain: Khi có lệnh cắn TP thì phải reset chain
// - Bổ sung Stoploss
// - Fix logic vào lệnh (Kẻ fibonacci)
```

### Về Point Scale (XAUUSD)

| `InpBaseTrendRange` | Timeframe | Tương đương giá |
|---|---|---|
| 10000 points | M15 | $10.00 (với 1pt = 0.001) |
| 30000 points | M30 | $30.00 |

---

## 9. Thông số khuyến nghị khởi đầu

| Timeframe | `InpBaseTrendRange` | `InpBaseTrendCandles` | `InpMaxFindSwingCandles` | `InpBaseLot` |
|:---------:|:-------------------:|:---------------------:|:------------------------:|:------------:|
| M15       | 10000               | 3                     | 20                       | 0.01         |
| M30       | 30000               | 3                     | 20                       | 0.01         |

> Với account nhỏ (dưới $5,000), khuyến nghị `InpBaseLot = 0.01` và giám sát drawdown cẩn thận. Exposure tối đa là **143 × BaseLot = 1.43 lot**.

---

*Tài liệu tạo ngày 2026-03-09 — MFR DCA v2.mq5*

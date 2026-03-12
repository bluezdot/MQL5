# MFR DCA v2.2 — Documentation

**File:** `MFR_DCA_v2.2.mq5`

**Phiên bản:** 2.20

---

## 1. Tổng quan chiến lược

**MFR DCA** (Martingale Fibonacci Retracement DCA) kết hợp ba kỹ thuật:

1. **Trend Detection** — Nhận diện xu hướng tăng/giảm dựa trên `N` nến liên tiếp có **Higher Close + Higher Low** (Buy) hoặc **Lower Close + Lower High** (Sell), kết hợp tổng biên độ vượt ngưỡng tối thiểu.
2. **Fibonacci Retracement Grid** — Khi giá pullback, đặt lưới 10 lệnh Limit tại các mức Fibo (0.236 → 4.236) tính từ điểm neo `anchor`.
3. **Martingale Lot Sizing** — Lot mỗi mức tăng theo dãy Fibonacci (×1, ×1, ×2, ×3, ×5, ×8, ×13, ×21, ×34, ×55), nhằm đạt breakeven khi giá phục hồi.

### Luồng tổng quát

```
[ScanForTrend] → Xác nhận trend + pullback từ nến ĐÃ ĐÓNG
      ↓
[SetupDCAChain] → Đặt lưới lệnh Limit tại 10 mức Fibo
      ↓
[UpdateTP]  ← chạy mỗi tick: TP động theo lệnh sâu nhất đang khớp
[CheckStopLoss] ← chạy mỗi nến đóng: cắt lỗ nếu giá phá Fibo 4.236
      ↓
[CheckAndManageChain] → Reset chain khi không còn gì quản lý
```

---

## 2. Cải tiến so với v2.0

| # | Cải tiến | Chi tiết |
|---|---|---|
| 1 | **Refactor TrendState** | `swingHigh/swingLow` → `anchor/limit` — tránh nhầm lẫn Buy vs Sell |
| 2 | **Pullback từ nến đã đóng** | Trigger từ `rates[1]` (nến đóng) thay vì `rates[0]` (nến live), giảm false signal |
| 3 | **Skip Fibo đã vượt** | `SetupDCAChain` bỏ qua level bị giá vượt qua, giữ lot theo absolute index (Cách A) |
| 4 | **Giữ SL khi modify TP** | `PositionModify(ticket, currentSL, currentTP)` — không xóa SL khi cập nhật TP |
| 5 | **Fix logic reset Sell chain** | Dùng `anchor` (đáy trend) thay vì `swingHigh` sai chiều |
| 6 | **Index đồng nhất** | Trend check, anchor, FindSwing đều start từ `rates[2]` để đúng với map index mới |
| 7 | **Pullback lỏng hơn** | Nến pullback chỉ cần wick chọc qua nến trước, không cần close chọc qua để xác định |

---

## 3. Nguyên lý hoạt động chi tiết

### 3.1 Map Index nến (quan trọng)

```
rates[0]       = nến đang hình thành (live, chưa dùng)
rates[1]       = nến pullback vừa đóng  ← reference chính
rates[2..N+1]  = N nến trend
rates[N+2..]   = các nến cũ để tìm Swing
```

### 3.2 Xác định Trend — `ScanForTrend(int dir)`

**Điều kiện trend TĂNG (dir = 1):**
```
Với mỗi nến trong rates[2..N+1]:
  close[i] > close[i+1]  → Higher Close (momentum)
  low[i]   > low[i+1]    → Higher Low   (cấu trúc)
Tổng biên độ N nến ≥ InpBaseTrendRange × _Point
```

**Điều kiện trend GIẢM (dir = -1):**
```
  close[i] < close[i+1]  → Lower Close
  high[i]  < high[i+1]   → Lower High
Tổng biên độ ≥ InpBaseTrendRange × _Point
```

> **Higher Close + Higher Low** mạnh hơn "close only": xác nhận cả momentum lẫn cấu trúc giá — người mua (Buy) đang vào ở đáy cao hơn qua từng nến.

### 3.3 Xác định Pullback

```
Buy:  rates[1].close < rates[2].low   → nến đóng bên dưới low nến trend cuối
Sell: rates[1].close > rates[2].high  → nến đóng bên trên high nến trend cuối
```

Bot chỉ vào lệnh khi có **nến đóng xác nhận pullback** — không dùng tick live.

### 3.4 Điểm neo Fibonacci — `anchor` và `limit`

| | Buy Chain | Sell Chain |
|---|---|---|
| **`anchor`** | SwingHigh = max(rates[1..N+1].high) | SwingLow = min(rates[1..N+1].low) |
| **`limit`** | SwingLow cục bộ (FindSwingLow) | SwingHigh cục bộ (FindSwingHigh) |
| **Kéo lưới** | `anchor - fibo × diff` (xuống) | `anchor + fibo × diff` (lên) |

> Anchor bao gồm cả `rates[1]` (pullback candle) — nếu pullback tạo đỉnh/đáy mới, nó được include qua `MathMax/Min`.

### 3.5 Lưới Fibo — `SetupDCAChain`

```
diff = |anchor - limit|

Fibo i  │ Level │ Lot (× BaseLot) │ Giá BuyLimit
────────┼───────┼─────────────────┼───────────────────────
  0     │ 0.236 │      ×1         │ anchor - 0.236 × diff
  1     │ 0.382 │      ×1         │ anchor - 0.382 × diff
  2     │ 0.500 │      ×2         │ anchor - 0.500 × diff
  3     │ 0.618 │      ×3         │ anchor - 0.618 × diff
  4     │ 0.786 │      ×5         │ anchor - 0.786 × diff
  5     │ 1.000 │      ×8         │ anchor - 1.000 × diff
  6     │ 1.618 │     ×13         │ anchor - 1.618 × diff
  7     │ 2.618 │     ×21         │ anchor - 2.618 × diff
  8     │ 3.618 │     ×34         │ anchor - 3.618 × diff
  9     │ 4.236 │     ×55         │ anchor - 4.236 × diff ← SL trigger
```

**Skip logic (Cách A):** Level nào có giá ≥ ask (Buy) hoặc ≤ bid (Sell) sẽ bị bỏ qua — giữ nguyên lot multiplier theo absolute index.

### 3.6 Take Profit động — `UpdateTP`

Chạy **mỗi tick**. Tìm vị thế có giá entry **xấu nhất** (thấp nhất với Buy, cao nhất với Sell), tra index Fibo tương ứng, đặt TP = mức Fibo **1 bậc trên** (gần anchor hơn):

```
deepestIdx = index Fibo gần nhất với giá entry xấu nhất

TP (Buy):  anchor - fiboLevels[deepestIdx - 1] × diff
TP (Sell): anchor + fiboLevels[deepestIdx - 1] × diff

Nếu deepestIdx == 0: TP = anchor
```

TP được áp dụng cho **toàn bộ vị thế** cùng chiều. SL được giữ nguyên khi modify.

### 3.7 Stop Loss theo nến đóng — `CheckStopLoss`

Chạy **1 lần/nến** (guard bằng `lastBar`). Dùng `closedClose = iClose(_Period, 1)`:

```
Buy:  SL khi closedClose < anchor - 4.236 × diff  (phá Fibo sâu nhất)
Sell: SL khi closedClose > anchor + 4.236 × diff
```

→ Đóng toàn bộ vị thế cùng chiều và reset chain.

### 3.8 Reset Chain — `CheckAndManageChain`

| Trường hợp | Điều kiện | Hành động |
|---|---|---|
| Giá phá anchor | `price >= anchor` (Buy) hoặc `price <= anchor` (Sell) | Reset |
| TP đã hit, chain kết thúc | `hadPositions == true && !hasPos` | Reset |
| Không còn gì quản lý | `!hasPos && !hasPendingOrders` | Reset |

`ResetChain`: hủy toàn bộ lệnh Limit còn treo, đặt `active = false`, `anchor = limit = 0`.

---

## 4. Sơ đồ trạng thái Chain

```
         [Không active]
               │
               │ ScanForTrend(): trend + pullback confirmed (nến đóng)
               ↓
     [Active] ─────────── SetupDCAChain(): đặt ≤10 lệnh Limit
               │
               ├─ UpdateTP()        mỗi tick  → TP động
               ├─ CheckStopLoss()   mỗi nến   → SL nếu phá Fibo 4.236
               │
       CheckAndManageChain():
       ├─ Giá phá anchor → Reset
       ├─ TP xong        → Reset
       └─ Hết lệnh       → Reset
               │
         [Không active]
```

---

## 5. Input Parameters

| Input | Default | M15 | M30 | Mô tả |
|---|---|---|---|---|
| `InpBaseLot` | 0.01 | 0.01 | 0.01 | Lot cơ bản. Tổng tối đa = 143 × BaseLot |
| `InpBaseTrendRange` | 10000 | 10000 | 30000 | Tổng biên độ tối thiểu của N nến trend (points) |
| `InpBaseTrendCandles` | 3 | 3 | 3 | Số nến trend liên tiếp cần xác nhận |
| `InpMaxFindSwingCandles` | 20 | 15–20 | 20–25 | Số nến tối đa để tìm Swing Low/High |
| `InpMagicNumber` | 123456 | — | — | Phân biệt EA với các EA khác |

### Hướng dẫn chọn `InpMaxFindSwingCandles`

```
Rule ngón tay cái: ≈ 2 × số giờ swing điển hình của symbol/TF
XAUUSD M30: swing 4–6 giờ → 8–12 candle → thêm buffer → chọn 15–20
```

> ⚠️ Đảm bảo `InpMaxFindSwingCandles > InpBaseTrendCandles + 3`

---

## 6. Cấu trúc dữ liệu

### `TrendState` struct

```cpp
struct TrendState {
    bool   active;       // Chain đang hoạt động không
    double anchor;       // Neo GỐC: Buy = SwingHigh, Sell = SwingLow
    double limit;        // Neo giới hạn: Buy = SwingLow, Sell = SwingHigh
    int    direction;    // 1 = Buy, -1 = Sell
    bool   hadPositions; // Đã từng có vị thế fill trong chain này
};
```

**Công thức thống nhất — đối xứng hoàn toàn Buy/Sell:**
```
diff       = MathAbs(anchor - limit)
Fibo price = anchor ± fiboLevels[i] × diff   (Buy: −, Sell: +)
SL level   = anchor ± fiboLevels[9] × diff
TP         = anchor ± fiboLevels[deepestIdx−1] × diff
Reset khi  = price ≥ anchor (Buy) hoặc price ≤ anchor (Sell)
```

### Arrays toàn cục

| Biến | Giá trị |
|---|---|
| `fiboLevels[10]` | `{0.236, 0.382, 0.5, 0.618, 0.786, 1.0, 1.618, 2.618, 3.618, 4.236}` |
| `fiboMult[10]` | `{1, 1, 2, 3, 5, 8, 13, 21, 34, 55}` |

---

## 7. Chi tiết các hàm

| Hàm | Trigger | Mô tả |
|---|---|---|
| `OnTick()` | Mỗi tick | Điều phối: SL → ManageChain → ScanTrend → UpdateTP |
| `CheckStopLoss()` | 1 lần/nến | Cắt lỗ khi nến đóng phá Fibo 4.236 |
| `ScanForTrend(dir)` | Mỗi tick (nếu chain inactive) | Tìm trend + pullback, trigger SetupDCAChain |
| `FindSwingLow/High(rates)` | Khi có pullback | Tìm đáy/đỉnh cục bộ từ `rates[2]` trở đi |
| `SetupDCAChain(dir, anchor, limit)` | Khi pullback xác nhận | Đặt ≤10 lệnh Limit, skip level đã vượt |
| `UpdateTP(dir)` | Mỗi tick | Tính TP động theo entry xấu nhất, giữ SL |
| `CheckAndManageChain(state)` | Mỗi tick | Kiểm tra 3 điều kiện reset chain |
| `ResetChain(state)` | Khi cần reset | Hủy limit treo, reset toàn bộ TrendState |

---

## 8. Ví dụ thực tế (Buy Chain — XAUUSD M30)

**Giả sử:** `InpBaseLot = 0.01`, `InpBaseTrendCandles = 3`, `InpBaseTrendRange = 30000`

```
rates[4]: high=2045, low=2038, close=2044  ┐
rates[3]: high=2055, low=2046, close=2054  │ 3 nến trend (Higher Close + Higher Low ✅)
rates[2]: high=2068, low=2056, close=2065  ┘

rates[1]: high=2070 (new high!), low=2049, close=2051
  → close=2051 < low of rates[2]=2056 → Pullback xác nhận ✅

anchor    = max(rates[1..4].high) = max(2070, 2068, 2055, 2045) = 2070
SwingLow  = FindSwingLow(rates) bắt đầu từ rates[2]:
            rates[2].low=2056 > rates[3].low=2046 → i++
            rates[3].low=2046 > rates[4].low=2038 → i++
            rates[4].low=2038 < rates[5].low=... (giả sử tăng) → return 2038
limit = 2038

diff = 2070 - 2038 = 32

Lưới BuyLimit:
  Fibo 0.236 → 2070 - 0.236×32 = 2062.45 → 0.01 lot
  Fibo 0.382 → 2070 - 0.382×32 = 2057.78 → 0.01 lot
  Fibo 0.500 → 2070 - 0.500×32 = 2054.00 → 0.02 lot
  Fibo 0.618 → 2070 - 0.618×32 = 2050.22 → 0.03 lot
  ...
  Fibo 4.236 → 2070 - 4.236×32 = 1934.45 → 0.55 lot  ← SL trigger
```

---

## 9. Lưu ý quan trọng

> [!WARNING]
> Martingale: Lot tối đa = **143 × BaseLot**. Với BaseLot = 0.01 → 1.43 lot. Tính toán kỹ margin trước khi tăng BaseLot.

> [!CAUTION]
> SL duy nhất là nến đóng phá Fibo 4.236. Gap thị trường qua đêm có thể bypass SL — không có hard equity protection.

### Re-entry sau Reset

Bot re-entry ngay tick tiếp theo nếu điều kiện vẫn đủ. Không có cooldown — trong sideway có thể tạo nhiều chain trong ngày.

### Bot chạy 2 chain độc lập

`buyChain` và `sellChain` hoàn toàn độc lập. Cả 2 chain có thể active cùng lúc nếu thị trường có cả 2 chiều đủ điều kiện.

---

## 10. Thông số khuyến nghị

| Timeframe | `InpBaseTrendRange` | `InpBaseTrendCandles` | `InpMaxFindSwingCandles` | `InpBaseLot` |
|:---------:|:-------------------:|:---------------------:|:------------------------:|:------------:|
| M15       | 10000               | 3                     | 15–20                    | 0.01         |
| M30       | 30000               | 3                     | 20–25                    | 0.01         |

---

*Tài liệu tạo ngày 2026-03-10 — MFR DCA v2.2.mq5*

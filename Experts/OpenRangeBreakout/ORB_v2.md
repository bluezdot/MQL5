# GOLD ORB v2 — Documentation

**File:** `ORB_v2.mq5`

**Phiên bản:** 2.00

**Timeframe khuyến nghị:** H1 (1 giờ) — hỗ trợ multi-timeframe

**Symbol:** XAUUSD (GOLD)

**Ngôn ngữ:** MQL5

---

## 1. Điểm khác biệt so với v1

| # | Tính năng | v1 | v2 |
|---|-----------|----|----|
| 1 | **Stop Loss** | Fixed points (`InpSLPoints`) | Tại boundary của range (`range.low` / `range.high`) |
| 2 | **Take Profit** | Fixed points (`InpTPPoints`) | Chọn mode: **RR-based** hoặc **Fixed points** |
| 3 | **Lot size** | Tính theo `slPoints` (điểm) | Tính theo `slDistance` (khoảng cách giá thực tế) |
| 4 | **TP Mode** | Không có | `TP_BY_RR` hoặc `TP_BY_POINTS` qua `InpTPMode` |
| 5 | **Bar selection** | `InpMarketOpenHour` (giờ) | `InpOpenBar` (bar index từ đầu ngày — multi-TF) |

---

## 2. Tổng quan chiến lược

### Ý tưởng cốt lõi
Open Range Breakout (ORB) xác định vùng high/low sau khi thị trường mở cửa. Sau khi range được xác nhận, bot chờ giá phá vỡ để vào lệnh. **v2 cải tiến risk management** bằng cách đặt SL tại boundary của range, đảm bảo SL luôn có ý nghĩa kỹ thuật.

### Nguyên lý hoạt động

1. **Xác định nến mở cửa (Initial Range Candle)**
   - Nến khởi đầu là nến có **bar index** bằng `InpOpenBar` tính từ đầu ngày server.
   - Index được tính: `barIndex = (barOpenTime - midnight) / PeriodSeconds` — hoạt động đúng trên mọi timeframe.
   - Khi nến này đóng cửa, high/low trở thành **Initial Range**.

   > **Tham chiếu `InpOpenBar` theo timeframe:**
   > | Timeframe | `InpOpenBar` | Giờ tương ứng |
   > |-----------|-------------|---------------|
   > | H1        | 1           | 01:00         |
   > | H1        | 4           | 04:00         |
   > | M30       | 2           | 01:00         |
   > | M15       | 4           | 01:00         |
   > | M5        | 12          | 01:00         |
   > **Formula:** `InpOpenBar = target_hour × 3600 / PeriodSeconds`

2. **Giai đoạn FORMING — Thu thập Composition**
   - Nến **vượt ra ngoài** range: cập nhật mở rộng range, không tính vào composition.
   - Nến **nằm trong** range: `composition++`.
   - Khi `composition >= InpMinComposition` → range **FINAL**.
   - Đặc biệt: `InpMinComposition = 0` → range finalize ngay sau bar đầu tiên tiếp theo (bỏ qua giai đoạn composition).

3. **Giai đoạn FINAL — Chờ Breakout + Vào lệnh**
   - Kiểm tra từng tick:
     - `ask >= range.high` → Mở lệnh **BUY**, SL = `range.low`
     - `bid <= range.low`  → Mở lệnh **SELL**, SL = `range.high`
   - TP tính theo `InpTPMode` (xem mục 4).
   - Mỗi hướng chỉ vào lệnh 1 lần/ngày.

4. **Reset hàng ngày**
   - Midnight (server time) → reset toàn bộ state về **IDLE**.

---

## 3. Sơ đồ State Machine

```
           [IDLE]
              |
              | → Nến tại index InpOpenBar đóng cửa
              ↓
          [FORMING]
              |
              | → composition >= InpMinComposition
              ↓
           [FINAL]  ←──── tick check: breakout?
              |
              | → buyDone == true && sellDone == true
              ↓
          [TRADED]
              |
              | → Midnight (new day)
              ↓
           [IDLE]  (reset)
```

---

## 4. Input Parameters

### ==== General Settings ====
| Input | Default | Mô tả |
|---|---|---|
| `InpMagicNumber` | 111222 | Magic number để phân biệt EA với các EA khác |
| `InpOpenBar` | 0 | Bar index tính từ đầu ngày (0 = nến đầu tiên). Xem bảng tham chiếu ở mục 2 |
| `InpMinComposition` | 3 | Số nến tối thiểu nằm trong range để xác nhận FINAL. `0` = finalize sau đúng 1 bar tiếp theo |

### ==== TP Settings ====
| Input | Default | Mô tả |
|---|---|---|
| `InpTPMode` | `TP_BY_RR` | Chế độ Take Profit: `TP_BY_RR` hoặc `TP_BY_POINTS` |
| `InpRR` | 1.0 | **[TP_BY_RR]** Risk:Reward ratio. `TP = entry + slDistance × RR` |
| `InpTPPoints` | 12000 | **[TP_BY_POINTS]** TP cố định tính bằng points. `1pt = $0.001` với XAUUSD thông thường |

#### Công thức TP theo mode

| Mode | BUY TP | SELL TP |
|------|--------|---------|
| `TP_BY_RR` | `ask + (ask − range.low) × InpRR` | `bid − (range.high − bid) × InpRR` |
| `TP_BY_POINTS` | `ask + InpTPPoints × _Point` | `bid − InpTPPoints × _Point` |

### ==== Trailing Stop ====
| Input | Default | Mô tả |
|---|---|---|
| `InpUseTrail` | false | Bật/tắt Trailing Stop |
| `InpTrailPoints` | 1500 | Khoảng cách trailing stop từ giá hiện tại |
| `InpTrailStep` | 100 | Bước tối thiểu để SL được dịch chuyển |

### ==== Risk Management ====
| Input | Default | Mô tả |
|---|---|---|
| `InpFixedLot` | 0.1 | Lot cố định — dùng khi `InpRiskPerTradePercent = 0` |
| `InpRiskPerTradePercent` | 1 | % balance rủi ro mỗi lệnh. EA tự tính lot từ SL distance. `0` = dùng `InpFixedLot` |

### ==== Day Filter ====
| Input | Default | Mô tả |
|---|---|---|
| `InpMonday` ... `InpFriday` | true | Bật/tắt giao dịch theo từng thứ trong tuần |

---

## 5. Cấu trúc dữ liệu

### `ORB_STATE_ENUM`
```cpp
enum ORB_STATE_ENUM {
   ORB_IDLE,     // Chờ nến mở cửa
   ORB_FORMING,  // Nến đầu đã đóng, đang thu thập composition
   ORB_FINAL,    // Range xác nhận, đang chờ breakout
   ORB_TRADED    // Cả 2 lệnh đã vào, chờ ngày mới
};
```

### `TP_MODE_ENUM`
```cpp
enum TP_MODE_ENUM {
   TP_BY_RR,      // TP = SL distance × RR ratio
   TP_BY_POINTS   // TP = fixed points from entry
};
```

### `ORB_RANGE` struct
```cpp
struct ORB_RANGE {
   datetime initCandleTime;  // Thời điểm mở của nến khởi đầu range
   datetime dayMidnight;     // Mốc nửa đêm — dùng để detect ngày mới
   double   high;            // Range high (ngưỡng kháng cự)
   double   low;             // Range low (ngưỡng hỗ trợ)
   int      composition;     // Số nến đã "composed" trong range
   bool     buyDone;         // True khi lệnh BUY đã vào trong ngày
   bool     sellDone;        // True khi lệnh SELL đã vào trong ngày
};
```

---

## 6. Chi tiết các hàm

### `OnTick()` (dòng 102)
Được gọi mỗi tick. Thứ tự thực hiện:
1. Cập nhật `g_lastTick` qua `SymbolInfoTick()`
2. Nếu `InpUseTrail = true` → gọi `ManageTrailingStop()`
3. So sánh `iTime(_Period, 0)` với `g_lastBarTime` để phát hiện **nến mới**
   - Nếu có nến mới → gọi `OnNewBar()`
4. Nếu `g_state == ORB_FINAL` → gọi `CheckBreakout()` (kiểm tra breakout từng tick)
5. Gọi `ShowComment()` để hiển thị TF, bar index, state lên chart

---

### `RunStateMachine()` (dòng 155)
Chạy mỗi bar mới. Đọc bar vừa **đóng** (index 1):

**Khi `ORB_IDLE`:**
- Tính `barIndexOfDay = (closedBarTime - midnight) / PeriodSeconds(_Period)`
- Nếu `barIndexOfDay == InpOpenBar` → thiết lập high/low ban đầu → `ORB_FORMING`

**Khi `ORB_FORMING`:**
- `closedHigh > range.high` → mở rộng range lên, không tính composition
- `closedLow < range.low` → mở rộng range xuống, không tính composition
- Không mở rộng → `composition++`
- `composition >= InpMinComposition` → `ORB_FINAL`

---

### `CheckBreakout()` (dòng 215)
Gọi mỗi tick khi `g_state == ORB_FINAL`:

```
BUY:  ask >= range.high  AND  buyDone == false
  → SL = range.low
  → slDist = ask - range.low
  → TP theo InpTPMode

SELL: bid <= range.low   AND  sellDone == false
  → SL = range.high
  → slDist = range.high - bid
  → TP theo InpTPMode
```

**Ưu điểm SL tại range boundary:**
- SL có ý nghĩa kỹ thuật: nếu giá quay về trong range → tín hiệu breakout thất bại
- SL tự điều chỉnh theo kích thước range mỗi ngày

---

### `CalcLotSize(double slDistance)` (dòng 279)
Tính lot size từ **khoảng cách giá** SL (khác với v1 dùng slPoints):

```
Nếu InpRiskPerTradePercent > 0:
   riskAmount = balance × RiskPercent / 100
   slCost     = slDistance / tickSize × tickValue   ← giá trị $ của SL cho 1 lot
   lots       = riskAmount / slCost

Nếu InpRiskPerTradePercent = 0:
   lots = InpFixedLot

Sau đó chuẩn hóa theo min/max/step của broker.
```

> **Lưu ý v2 vs v1:** v1 dùng `slPoints × pointValue`, v2 dùng `slDistance / tickSize × tickValue`. Cả hai cho kết quả tương đương nhưng v2 chính xác hơn vì không phụ thuộc vào `_Point`.

---

### `ManageTrailingStop()` (dòng 304)
Gọi mỗi tick, chỉ di chuyển SL khi:
- **BUY**: `bid - trail > openPrice` (đang lãi) VÀ `newSL >= curSL + step`
- **SELL**: `ask + trail < openPrice` (đang lãi) VÀ `newSL <= curSL - step`

---

### `CheckDayReset()` (dòng 135)
So sánh `barTime - (barTime % 86400)` với `g_range.dayMidnight`. Nếu khác → sang ngày mới:
- Reset toàn bộ `g_range`
- `g_state = ORB_IDLE`
- Xóa và vẽ lại chart objects

---

### `IsTradingDay()` (dòng 339)
Lọc ngày giao dịch qua `dt.day_of_week` (1=Thứ 2, 5=Thứ 6).

---

### `DrawObjects()` (dòng 353)
Vẽ 3 đối tượng lên chart:
- **`orb_start`** (OBJ_VLINE, màu xanh dương): thời điểm bắt đầu range
- **`orb_high`** (OBJ_HLINE, màu xanh lá, nét đứt): ngưỡng kháng cự = SL của SELL
- **`orb_low`** (OBJ_HLINE, màu đỏ cam, nét đứt): ngưỡng hỗ trợ = SL của BUY

---

## 7. Ví dụ giao dịch thực tế

Với **H1**, `InpOpenBar = 1`, `InpMinComposition = 3`, `InpTPMode = TP_BY_RR`, `InpRR = 2.0`:

```
01:00 bar đóng: High=2910, Low=2900
  → FORMING. range.high=2910, range.low=2900

02:00 trong range → composition=1
03:00 trong range → composition=2
04:00 trong range → composition=3 ≥ 3 → ORB_FINAL

Tick: ask=2910.5 (≥ range.high 2910) → BUY triggered
  SL    = range.low = 2900
  slDist = 2910.5 - 2900 = 10.5
  TP    = 2910.5 + 10.5 × 2.0 = 2931.5
  RR    = 1:2

Tick: bid=2899.5 (≤ range.low 2900) → SELL triggered
  SL    = range.high = 2910
  slDist = 2910 - 2899.5 = 10.5
  TP    = 2899.5 - 10.5 × 2.0 = 2878.5
  RR    = 1:2
```

---

## 8. Lưu ý quan trọng

### Về Point Scale (XAUUSD)
- `1 point = 0.001` (broker thông thường, 3 chữ số thập phân)
- Code dùng `_Point` và `tickSize/tickValue` động → tự thích nghi mọi broker

| Input | Points | Giá trị giá |
|---|---|---|
| TP (points mode) | 12000 | $12.00 |
| Trail | 1500 | $1.50 |
| Trail Step | 100 | $0.10 |

### Giới hạn của v2
- SL **không thể tắt** (luôn đặt tại range boundary) — đây là design có chủ đích để bảo vệ tài khoản.
- Nếu range quá rộng → `slDist` lớn → lot size nhỏ hơn (nếu dùng % risk). Đây là hành vi đúng.
- Mỗi hướng (buy/sell) chỉ vào **1 lệnh/ngày**.
- Breakout kiểm tra tại **giá bid/ask hiện tại** → có thể gặp false breakout khi spread cao.

### So sánh nhanh v1 vs v2

| Tiêu chí | v1 | v2 |
|---|---|---|
| SL | Fixed points từ entry | Range boundary (kỹ thuật hơn) |
| TP | Fixed points | RR-based hoặc Fixed points |
| Lot size | Từ SL points | Từ SL price distance (chính xác hơn) |
| Consistency | RR thay đổi mỗi ngày | RR **nhất quán** mỗi ngày (TP_BY_RR) |

---

*Tài liệu tạo ngày 2026-03-05 — GOLD ORB v2.mq5*

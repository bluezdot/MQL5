# GOLD ORB v1 — Documentation

**File:** `ORB_v1.mq5`

**Timeframe khuyến nghị:** H1 (1 giờ) — hỗ trợ multi-timeframe

**Symbol:** XAUUSD (GOLD)

**Ngôn ngữ:** MQL5

**Phiên bản:** 1.00

---

## 1. Tổng quan chiến lược (Open Range Breakout)

### Ý tưởng cốt lõi
Open Range Breakout (ORB) là chiến lược dựa trên việc xác định vùng giá (high/low) hình thành ngay sau khi thị trường mở cửa. Sau khi vùng này được xác nhận, bot chờ giá phá vỡ (breakout) để vào lệnh theo hướng phá vỡ.

### Nguyên lý hoạt động
1. **Xác định nến mở cửa (Initial Range Candle)**
   - Thị trường XAUUSD mở cửa lúc ~1:02 server time.
   - Nến khởi đầu là nến có **thứ tự** (index) bằng `InpOpenBar` tính từ đầu ngày (0 = nến đầu tiên trong ngày).
   - Index được tính theo công thức: `barIndex = (barOpenTime - midnight) / PeriodSeconds`.
   - Khi nến này đóng cửa, high/low của nó trở thành **Initial Range** (kháng cự/hỗ trợ ban đầu).

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
   - Các nến tiếp theo được đánh giá:
     - Nến **vượt ra ngoài** range (high > range.high hoặc low < range.low): cập nhật mở rộng range, **không** tính vào composition.
     - Nến **nằm trong** range (hoàn toàn bên trong high/low): tính vào `composition`.
   - Khi `composition >= InpMinComposition` (mặc định 3): range được xác nhận là **FINAL**.

3. **Giai đoạn FINAL — Chờ Breakout**
   - Kiểm tra từng tick:
     - `ask >= range.high` → Mở lệnh **BUY** (breakout lên trên)
     - `bid <= range.low`  → Mở lệnh **SELL** (breakdown xuống dưới)
   - Mỗi hướng chỉ vào lệnh 1 lần/ngày (`buyDone` / `sellDone`).
   - Khi cả hai đã vào lệnh → chuyển sang trạng thái **TRADED**.

4. **Reset hàng ngày**
   - Lúc nửa đêm (midnight) — phát hiện qua sự thay đổi ngày của bar mới — toàn bộ trạng thái range được reset về **IDLE**.

---

## 2. Sơ đồ State Machine

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

## 3. Input Parameters

### ==== General Settings ====
| Input | Default | Mô tả |
|---|---|---|
| `InpMagicNumber` | 111222 | Magic number để phân biệt EA với các EA khác trên cùng account |
| `InpOpenBar` | 0 | **Bar index** tính từ đầu ngày (0 = nến đầu tiên). Xác định nến khởi đầu range. Hoạt động đúng trên mọi timeframe. Xem bảng tham chiếu ở mục 1. |
| `InpMinComposition` | 3 | Số nến tối thiểu phải nằm trong range để range được xác nhận final |

### ==== Trade Settings ====
| Input | Default | Giá trị thực (1pt = 0.001) | Mô tả |
|---|---|---|---|
| `InpSLPoints` | 4000 | $4.00 | Stop Loss tính bằng points. `0` = tắt SL |
| `InpTPPoints` | 12000 | $12.00 | Take Profit tính bằng points. `0` = tắt TP |

### ==== Trailing Stoploss ====
| Input | Default | Giá trị thực (1pt = 0.001) | Mô tả |
|---|---|---|---|
| `InpUseTrail` | false | — | Bật/tắt Trailing Stop |
| `InpTrailPoints` | 1500 | $1.50 | Khoảng cách trailing stop tính từ giá hiện tại |
| `InpTrailStep` | 100 | $0.10 | Bước tối thiểu để SL được dịch chuyển |

### ==== Risk Management ====
| Input | Default | Mô tả |
|---|---|---|
| `InpFixedLot` | 0.1 | Lot size cố định — dùng khi `InpRiskPerTradePercent = 0` |
| `InpRiskPerTradePercent` | 1 | % balance rủi ro mỗi lệnh. EA tự tính lot. `0` = dùng `InpFixedLot` |

### ==== Day Filter ====
| Input | Default | Mô tả |
|---|---|---|
| `InpMonday` ... `InpFriday` | true | Bật/tắt giao dịch theo từng thứ trong tuần |

---

## 4. Cấu trúc dữ liệu

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

### `ORB_STATE_ENUM`
```cpp
enum ORB_STATE_ENUM {
   ORB_IDLE,     // Chờ nến mở cửa (chưa có gì)
   ORB_FORMING,  // Nến đầu đã đóng, đang thu thập composition
   ORB_FINAL,    // Range xác nhận, đang chờ breakout
   ORB_TRADED    // Cả 2 lệnh đã vào, chờ ngày mới
};
```

---

## 5. Chi tiết các hàm

### `OnTick()` — Hàm chính (dòng 94)
Được gọi mỗi tick. Thực hiện theo thứ tự:
1. Cập nhật `g_lastTick` qua `SymbolInfoTick()`
2. Nếu `InpUseTrail = true` → gọi `ManageTrailingStop()`
3. So sánh `iTime(_Period, 0)` với `g_lastBarTime` để phát hiện **nến mới**
   - Nếu có nến mới → gọi `OnNewBar()`
4. Nếu `g_state == ORB_FINAL` → gọi `CheckBreakout()` (kiểm tra breakout từng tick)
5. Gọi `ShowComment()` để cập nhật thông tin trên chart (hiển thị TF và bar index đang dùng)

---

### `OnNewBar()` → `RunStateMachine()` (dòng 118, 147)
Chạy một lần mỗi nến mới. Đọc dữ liệu nến vừa **đóng** (index 1):

**Khi `ORB_IDLE`:**
- Tính `barIndexOfDay = (closedBarTime - midnight) / PeriodSeconds(_Period)`
- Nếu `barIndexOfDay == InpOpenBar` → thiết lập high/low ban đầu → chuyển sang `ORB_FORMING`

**Khi `ORB_FORMING`:**
- `closedHigh > range.high` → cập nhật `range.high` (range mở rộng lên)
- `closedLow < range.low`  → cập nhật `range.low` (range mở rộng xuống)
- Không mở rộng → `composition++`
- `composition >= InpMinComposition` → chuyển sang `ORB_FINAL`

---

### `CheckBreakout()` (dòng 207)
Gọi mỗi tick khi `g_state == ORB_FINAL`:

```
BUY:  ask >= range.high  AND  buyDone == false
SELL: bid <= range.low   AND  sellDone == false
```

- Tính SL/TP theo số points từ giá entry.
- Tính lot qua `CalcLotSize()`.
- Gọi `g_trade.Buy()` / `g_trade.Sell()`.
- Nếu thành công → đặt `buyDone = true` / `sellDone = true`.
- Nếu cả hai `true` → `g_state = ORB_TRADED`.

---

### `CalcLotSize(slPoints)` (dòng 252)
Tính lot size tự động theo rủi ro:

```
Nếu InpRiskPerTradePercent > 0:
   riskAmount  = balance × RiskPercent / 100
   pointValue  = tickValue × _Point / tickSize
   slCost      = slPoints × pointValue          ← giá trị SL theo tiền tệ cho 1 lot
   lots        = riskAmount / slCost

Nếu InpRiskPerTradePercent = 0:
   lots = InpFixedLot

Sau đó chuẩn hóa theo min/max/step của broker.
```

---

### `ManageTrailingStop()` (dòng 277)
Gọi mỗi tick, chỉ di chuyển SL khi:
- **BUY**: giá bid - trail > open price (đang lãi) VÀ `newSL >= curSL + step` (tiến thêm ít nhất 1 bước)
- **SELL**: giá ask + trail < open price (đang lãi) VÀ `newSL <= curSL - step`

---

### `CheckDayReset()` (dòng 127)
`g_range.dayMidnight` lưu timestamp `00:00:00` của ngày hiện tại. Mỗi bar mới, hàm tính lại midnight từ `barTime % 86400` và so sánh — nếu khác → sang ngày mới, reset toàn bộ state.
So sánh `barTime - (barTime % 86400)` để phát hiện ngày mới. Nếu ngày thay đổi:
- Reset toàn bộ `g_range` về giá trị mặc định
- Đặt lại `g_state = ORB_IDLE`
- Xóa và vẽ lại chart objects

---

### `IsTradingDay()` (dòng 312)
Lọc thứ trong tuần qua `dt.day_of_week` (1=Thứ 2, 5=Thứ 6).
Trả về `false` nếu ngày hiện tại bị tắt trong input.

---

### `DrawObjects()` (dòng 326)
Vẽ 3 đối tượng lên chart:
- **`orb_start`** (OBJ_VLINE, màu xanh dương): đánh dấu thời điểm bắt đầu range
- **`orb_high`** (OBJ_HLINE, màu xanh lá, nét đứt): ngưỡng kháng cự
- **`orb_low`** (OBJ_HLINE, màu đỏ cam, nét đứt): ngưỡng hỗ trợ

---

## 6. Luồng hoạt động tổng thể theo thời gian

Ví dụ với **H1**, `InpOpenBar = 1` (bar index 1 = 01:00), `InpMinComposition = 3`:

```
00:00            01:00            02:00            03:00      04:00      05:00
  |                |                |                |          |          |
  | ← Midnight → reset IDLE        |                |          |          |
                   |                |                |          |          |
             barIndex=1 (01:00) barIndex=2 (02:00)  |          |          |
             = InpOpenBar       Nến đóng → FORMING  |          |          |
                                range.high = bar[1].H          |          |
                                range.low  = bar[1].L          |          |
                                             barIndex=3         barIndex=5
                                             trong range?       trong range?
                                             composition=1      composition=3
                                                                → ORB_FINAL!
                                                         Break above high? → BUY
                                                         Break below low?  → SELL
```

---

## 7. Lưu ý quan trọng

### Về Point Scale (XAUUSD)
- Broker điển hình: `1 point = 0.001` (3 chữ số thập phân)
- Code dùng `_Point` động → tự thích nghi mọi broker
- Tham chiếu quy đổi (với 1 pt = 0.001):

| Input | Points | Giá trị giá |
|---|---|---|
| SL | 4000 | $4.00 |
| TP | 12000 | $12.00 |
| Trail | 1500 | $1.50 |
| Trail Step | 100 | $0.10 |

### Giới hạn của v1
- Mỗi hướng (buy/sell) chỉ vào **1 lệnh/ngày**.
- Không có filter theo giờ kết thúc (không có `close_time`).
- Không có equity monitoring (được chuyển sang `ORB_v2.mq5`).
- Breakout được kiểm tra tại **giá bid/ask hiện tại**, không phải giá đóng nến — nên có thể gặp false breakout trong điều kiện spread cao.

---

*Tài liệu tạo ngày 2026-03-04 — GOLD ORB v1.mq5*
*Tài liệu tạo ngày 2026-03-04 — Cập nhật 2026-03-05 — GOLD ORB v1.mq5*

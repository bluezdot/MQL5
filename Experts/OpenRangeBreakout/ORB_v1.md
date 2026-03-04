# GOLD ORB v1 — Documentation
**File:** `ORB_v1.mq5`
**Timeframe khuyến nghị:** H1 (1 giờ)
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
   - Nến H1 đầu tiên mở lúc `InpMarketOpenHour:00` (mặc định 1:00) là nến khởi đầu.
   - Khi nến này đóng cửa, high/low của nó trở thành **Initial Range** (kháng cự/hỗ trợ ban đầu).

2. **Giai đoạn FORMING — Thu thập Composition**
   - Các nến H1 tiếp theo được đánh giá:
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
              | → Nến tại InpMarketOpenHour đóng cửa
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
| `InpMarketOpenHour` | 1 | Giờ mở cửa thị trường (server time). Nến H1 mở lúc giờ này là nến khởi đầu range |
| `InpMinComposition` | 3 | Số nến tối thiểu phải nằm trong range để range được xác nhận final |

### ==== Trade Settings ====
| Input | Default | Giá trị thực (1pt = 0.001) | Mô tả |
|---|---|---|---|
| `InpSLPoints` | 4000 | $4.00 | Stop Loss tính bằng points. `0` = tắt SL |
| `InpTPPoints` | 12000 | $12.00 | Take Profit tính bằng points. `0` = tắt TP |
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
3. So sánh `iTime(H1, 0)` với `g_lastBarTime` để phát hiện **nến H1 mới**
   - Nếu có nến mới → gọi `OnNewBar()`
4. Nếu `g_state == ORB_FINAL` → gọi `CheckBreakout()` (kiểm tra breakout từng tick)
5. Gọi `ShowComment()` để cập nhật thông tin trên chart

---

### `OnNewBar()` → `RunStateMachine()` (dòng 118, 147)
Chạy một lần mỗi nến H1 mới. Đọc dữ liệu nến vừa **đóng** (index 1):

**Khi `ORB_IDLE`:**
- Nếu `closedBar.hour == InpMarketOpenHour` → thiết lập high/low ban đầu → chuyển sang `ORB_FORMING`

**Khi `ORB_FORMING`:**
- `closedHigh > range.high` → cập nhật `range.high` (range mở rộng lên)
- `closedLow < range.low`  → cập nhật `range.low` (range mở rộng xuống)
- Không mở rộng → `composition++`
- `composition >= InpMinComposition` → chuyển sang `ORB_FINAL`

---

### `CheckBreakout()` (dòng 203)
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

### `CalcLotSize(slPoints)` (dòng 251)
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

### `ManageTrailingStop()` (dòng 276)
Gọi mỗi tick, chỉ di chuyển SL khi:
- **BUY**: giá bid - trail > open price (đang lãi) VÀ `newSL >= curSL + step` (tiến thêm ít nhất 1 bước)
- **SELL**: giá ask + trail < open price (đang lãi) VÀ `newSL <= curSL - step`

---

### `CheckDayReset()` (dòng 127)
So sánh `barTime % 86400` để phát hiện ngày mới. Nếu ngày thay đổi:
- Reset toàn bộ `g_range` về giá trị mặc định
- Đặt lại `g_state = ORB_IDLE`
- Xóa và vẽ lại chart objects

---

### `IsTradingDay()` (dòng 311)
Lọc thứ trong tuần qua `dt.day_of_week` (1=Thứ 2, 5=Thứ 6).
Trả về `false` nếu ngày hiện tại bị tắt trong input.

---

### `DrawObjects()` (dòng 325)
Vẽ 3 đối tượng lên chart:
- **`orb_start`** (OBJ_VLINE, màu xanh dương): đánh dấu thời điểm bắt đầu range
- **`orb_high`** (OBJ_HLINE, màu xanh lá, nét đứt): ngưỡng kháng cự
- **`orb_low`** (OBJ_HLINE, màu đỏ cam, nét đứt): ngưỡng hỗ trợ

---

## 6. Luồng hoạt động tổng thể theo thời gian

```
00:00            01:00            02:00            03:00      04:00      05:00
  |                |                |                |          |          |
  | ← Midnight → reset IDLE        |                |          |          |
                   |                |                |          |          |
             Nến mở lúc 1:00  Nến đóng lúc 2:00    |          |          |
                              → FORMING             |          |          |
                              range.high = H1[1].H  |          |          |
                              range.low  = H1[1].L  |          |          |
                                           Nến 3:00               Nến 5:00
                                           nằm trong range?      nằm trong range?
                                           composition = 1        composition = 3
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

## 8. Phân biệt ORB_v1 vs ORB_v2

| | ORB_v1 | ORB_v2 |
|---|---|---|
| **Equity Monitoring** | ❌ Không có | ✅ Có (commented, dễ bật lại) |
| **Mục đích** | Clean, production-ready | Development / testing với monitor |
| **Code clarity** | ⭐⭐⭐⭐⭐ Rõ ràng nhất | ⭐⭐⭐⭐ Có comment block lớn |

---

*Tài liệu tạo ngày 2026-03-04 — GOLD ORB v1.mq5*

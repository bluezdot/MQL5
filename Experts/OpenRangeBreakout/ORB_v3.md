# GOLD ORB v3 — Documentation

**File:** `ORB_v3.mq5`  **Phiên bản:** 2.00  
**Timeframe:** H1 (khuyến nghị) — hỗ trợ multi-timeframe  
**Symbol:** XAUUSD (GOLD)  **Ngôn ngữ:** MQL5

---

## 1. Điểm khác biệt so với v2

| # | Tính năng | v2 | v3 |
|---|-----------|----|----|
| 1 | **Session timezone** | UTC midnight cố định | `InpSessionStartHour` — configurable UTC hour |
| 2 | **Bar selection** | `InpOpenBar` từ UTC midnight | `InpOpenBar` từ `InpSessionStartHour` — timezone-safe |
| 3 | **Single-bar range** | `InpMinComposition=0` vào FORMING rồi mới FINAL | `InpMinComposition=0` → FINAL ngay lập tức (range lock đúng 1 nến) |
| 4 | **Close before session end** | Không có | `InpCloseAtSessionEnd` + `InpCloseBeforeMinutes` |
| 5 | **Debug info** | Không có | Chart comment hiển thị Tick Time, broker UTC offset, Bar Index, Session start |

---

## 2. Tổng quan chiến lược

ORB xác định vùng high/low từ một nến mở cửa đã định, sau đó chờ giá phá vỡ vùng đó để vào lệnh theo hướng breakout.

### Nguyên lý hoạt động

1. **Session Day Reset** — Mỗi ngày bắt đầu tại `InpSessionStartHour` UTC (không phải UTC midnight), toàn bộ state được reset về IDLE.

2. **Xác định Initial Range Candle** — Bar có index `InpOpenBar` tính từ session start → high/low của bar đó là Initial Range.
   - `barIndexOfDay = (barTime - sessionStart) / PeriodSeconds`
   - `sessionStart` được tính theo: `GetSessionStart(barTime)` — timezone-safe với bất kỳ UTC offset nào.

3. **FORMING — Thu thập Composition**
   - Bar vượt ra ngoài range → mở rộng range (high/low), không tính composition.
   - Bar nằm trong range → `composition++`.
   - `composition >= InpMinComposition` → **FINAL**.
   - **Đặc biệt:** `InpMinComposition = 0` → bỏ qua hoàn toàn FORMING, nhảy thẳng IDLE → FINAL. Range cố định đúng 1 nến.

4. **FINAL — Breakout detection (per-tick)**
   ```
   BUY:  ask >= range.high → SL = range.low,  TP theo InpTPMode
   SELL: bid <= range.low  → SL = range.high, TP theo InpTPMode
   ```

5. **Close trước session end** — Nếu `InpCloseAtSessionEnd = true`, đóng toàn bộ lệnh `InpCloseBeforeMinutes` phút trước khi session kết thúc.

6. **Reset** — Session start mới → reset state + `g_sessionCloseDone = false`.

---

## 3. Sơ đồ State Machine

```
           [IDLE]
              |
              | → Bar InpOpenBar đóng
              |   InpMinComposition=0 → FINAL (skip FORMING)
              |   InpMinComposition>0 → FORMING
              ↓
          [FORMING]
              |
              | → composition >= InpMinComposition
              ↓
           [FINAL]  ←──── CheckBreakout() mỗi tick
              |
              | → buyDone && sellDone
              ↓
          [TRADED]
              |
              | → Session start mới (InpSessionStartHour UTC)
              ↓
           [IDLE]  (reset)
```

---

## 4. Input Parameters

### ==== General Settings ====
| Input | Default | Mô tả |
|---|---|---|
| `InpMagicNumber` | 111222 | Magic number phân biệt EA |
| `InpOpenBar` | 1 | Bar index từ **session start** (0 = bar đầu tiên của session). Xem bảng tham chiếu bên dưới |
| `InpSessionStartHour` | 22 | Giờ UTC bắt đầu session mỗi ngày. Đặt **trước** market open để tránh reset xung đột |
| `InpMinComposition` | 3 | Số bar tối thiểu trong range để xác nhận FINAL. `0` = single-bar mode (FINAL ngay lập tức) |

#### Tham chiếu `InpOpenBar` theo timeframe (với `InpSessionStartHour = 22`)

| Market open (UTC) | H1 `InpOpenBar` | M30 `InpOpenBar` | M15 `InpOpenBar` |
|---|---|---|---|
| 23:00 | 1 | 2 | 4 |
| 00:00 | 2 | 4 | 8 |
| 01:00 | 3 | 6 | 12 |

> **Formula:** `InpOpenBar = (marketOpenUTC - InpSessionStartHour) * 3600 / PeriodSeconds`

### ==== TP Settings ====
| Input | Default | Mô tả |
|---|---|---|
| `InpTPMode` | `TP_BY_RR` | Chế độ TP: `TP_BY_RR` hoặc `TP_BY_POINTS` |
| `InpRR` | 1.0 | **[TP_BY_RR]** Risk:Reward ratio. `TP = entry + slDistance × RR` |
| `InpTPPoints` | 12000 | **[TP_BY_POINTS]** TP cố định tính bằng points |

#### Công thức TP
| Mode | BUY TP | SELL TP |
|---|---|---|
| `TP_BY_RR` | `ask + (ask − range.low) × RR` | `bid − (range.high − bid) × RR` |
| `TP_BY_POINTS` | `ask + InpTPPoints × _Point` | `bid − InpTPPoints × _Point` |

### ==== Trailing Stop ====
| Input | Default | Mô tả |
|---|---|---|
| `InpUseTrail` | false | Bật/tắt Trailing Stop |
| `InpTrailPoints` | 1500 | Khoảng cách trailing từ giá hiện tại |
| `InpTrailStep` | 100 | Bước tối thiểu để SL dịch chuyển |
| `InpCloseAtSessionEnd` | false | Bật tính năng đóng lệnh trước session end |
| `InpCloseBeforeMinutes` | 60 | **[khi bật]** Đóng lệnh trước bao nhiêu phút tính từ session end |

### ==== Risk Management ====
| Input | Default | Mô tả |
|---|---|---|
| `InpFixedLot` | 0.1 | Lot cố định (dùng khi `InpRiskPerTradePercent = 0`) |
| `InpRiskPerTradePercent` | 1 | % balance rủi ro/lệnh. EA tự tính lot từ SL distance. `0` = Fixed Lot |

### ==== Day Filter ====
`InpMonday` ... `InpFriday` — bật/tắt giao dịch theo thứ trong tuần (default: tất cả `true`).

---

## 5. Cấu trúc dữ liệu

### Enumerations
```cpp
enum ORB_STATE_ENUM { ORB_IDLE, ORB_FORMING, ORB_FINAL, ORB_TRADED };
enum TP_MODE_ENUM   { TP_BY_RR, TP_BY_POINTS };
```

### `ORB_RANGE` struct
| Field | Kiểu | Mô tả |
|---|---|---|
| `initCandleTime` | datetime | Thời điểm mở của nến khởi đầu range |
| `dayMidnight` | datetime | **Session start** của ngày hiện tại (UTC) |
| `high` | double | Range high = SL của SELL |
| `low` | double | Range low = SL của BUY |
| `composition` | int | Số bar đã nằm trong range |
| `buyDone` | bool | BUY đã vào trong session này |
| `sellDone` | bool | SELL đã vào trong session này |

### Global variables
| Variable | Mô tả |
|---|---|
| `g_state` | State machine hiện tại |
| `g_sessionCloseDone` | Đã đóng lệnh trước session end chưa (reset mỗi session) |

---

## 6. Chi tiết các hàm

### `GetSessionStart(barTime)` (dòng 144)
```mql5
datetime GetSessionStart(datetime barTime) {
   datetime offset       = InpSessionStartHour * 3600;
   datetime adjustedTime = barTime - offset;
   datetime sessionDay   = adjustedTime - (adjustedTime % 86400);
   return sessionDay + offset;
}
```
Trả về timestamp UTC của session start cho ngày chứa `barTime`. Hoạt động đúng với bất kỳ UTC offset nào.

---

### `CheckSessionEndClose()` (dòng 172)
Gọi mỗi tick khi `InpCloseAtSessionEnd = true`:
```
sessionEnd = g_range.dayMidnight + 86400
closeTime  = sessionEnd - InpCloseBeforeMinutes × 60
Nếu tick.time >= closeTime AND chưa close hôm nay:
  → CloseAllPositions()
  → g_sessionCloseDone = true
```

---

### `CheckDayReset()` (dòng 190)
Phát hiện session mới bằng cách so sánh `GetSessionStart(barTime)` với `g_range.dayMidnight`. Nếu khác:
- Reset `g_sessionCloseDone = false`
- Reset toàn bộ `g_range`
- `g_state = ORB_IDLE`

---

### `RunStateMachine()` (dòng 211)

**IDLE:** Nếu `barIndexOfDay == InpOpenBar`:
- Lock range = `[bar.low, bar.high]`
- `InpMinComposition == 0` → `ORB_FINAL` (single-bar mode)
- `InpMinComposition > 0` → `ORB_FORMING`

**FORMING:** Mỗi bar:
- Extend range nếu bar vượt ra ngoài → không reset composition
- `composition++` nếu bar nằm trong range
- `composition >= InpMinComposition` → `ORB_FINAL`

---

### `CheckBreakout()` (dòng 279)
Per-tick khi `state == ORB_FINAL`. SL luôn tại range boundary:

| Lệnh | Trigger | SL | TP |
|---|---|---|---|
| BUY | `ask >= range.high` | `range.low` | `ask + slDist × RR` hoặc fixed points |
| SELL | `bid <= range.low` | `range.high` | `bid - slDist × RR` hoặc fixed points |

---

### `CalcLotSize(slDistance)` (dòng 343)
Tính lot theo % risk và khoảng cách giá SL thực tế:
```
slCost = slDistance / tickSize × tickValue   // USD risk của 1 lot
lots   = riskAmount / slCost
```

---

### `ManageTrailingStop()` (dòng 368)
Trail SL chỉ khi đang lãi và SL cải thiện ít nhất `InpTrailStep`:
- BUY: `newSL = bid - trail` (chỉ tăng)
- SELL: `newSL = ask + trail` (chỉ giảm)

---

## 7. Ví dụ cấu hình thực tế

### Broker UTC+0, market mở 23:00 UTC, H1
```
InpSessionStartHour = 22    ← session reset lúc 22:00 UTC (trước open 1h)
InpOpenBar          = 1     ← bar 23:00 UTC = index 1 từ 22:00
InpMinComposition   = 0     ← single-bar: range = đúng nến 23:00
InpTPMode           = TP_BY_RR
InpRR               = 2.0
InpCloseAtSessionEnd    = true
InpCloseBeforeMinutes   = 60   ← đóng lệnh lúc 21:00 UTC
```

**Timeline ngày giao dịch:**
```
22:00 UTC → Session reset (IDLE)
23:00 UTC → Bar 23:00 đóng → range FINAL (InpMinComposition=0)
23:00+    → CheckBreakout per-tick
21:00 UTC → CloseAllPositions (1h trước session end 22:00)
22:00 UTC → Session reset lại
```

---

## 8. Chart Comment (debug)

```
=== GOLD ORB v2 ===
Tick Time  : 2026.01.06 23:15:00 (broker UTC+2)
Bar Index  : 1 (target: 1)
TF / OpenBar: PERIOD_H1 / bar #1
State      : FINAL — Watching for breakout
Range High : 2910.500
Range Low  : 2900.200
Composition: 0/0
Buy Done   : No
Sell Done  : No
Balance    : 10000.00
Equity     : 10000.00
```

---

## 9. Lưu ý quan trọng

- **SL không thể tắt** — luôn đặt tại range boundary (thiết kế có chủ đích).
- **Mỗi hướng 1 lệnh/session** — `buyDone`/`sellDone` reset khi session mới.
- **Backtest:** Dùng **"Every Tick"** hoặc **"Every Tick Based on Real Ticks"** — "Open Prices Only" sẽ không detect breakout intrabar.
- `InpSessionStartHour` phải **nhỏ hơn** giờ market open UTC để tránh conflict reset.

---

*Tài liệu tạo ngày 2026-03-06 — GOLD ORB v3.mq5*

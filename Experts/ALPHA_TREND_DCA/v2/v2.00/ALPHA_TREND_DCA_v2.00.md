# ALPHA TREND DCA v2.00 — Tài Liệu Thuật Toán

**File:** `ALPHA_TREND_DCA_v2.00.mq5`  
**Phiên bản:** 2.00  
**Ngôn ngữ:** MQL5  
**Ngày cập nhật:** 2026-03-17  

---

## 1. Tổng quan chiến lược

**ALPHA TREND DCA v2.00** là bản nâng cấp lớn từ v1.00, với ba thay đổi cốt lõi: **(1)** bộ tính toán AlphaTrend được tích hợp hoàn toàn vào EA (không cần indicator bên ngoài), **(2)** bổ sung module phát hiện và vẽ vùng Support/Resistance tự động từ n nến lookback trên timeframe tuỳ chọn, và **(3)** thêm info panel trực quan trên chart hiển thị trạng thái S/R, AT, và basket theo thời gian thực.

Logic giao dịch DCA Fibonacci giữ nguyên cơ bản như v1.00 (xác nhận tín hiệu, dynamic grid, basket TP, reversal close), nhưng tín hiệu AT được tính nội bộ dựa trên thuật toán so sánh AT[i] vs AT[i-2] với bộ lọc xen kẽ BUY/SELL. Phiên bản này bỏ tính năng scale lot theo balance, thay vào đó lot được tính trực tiếp từ `InpBaseLot × Fib(i)`.

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết |
|-----------|----------|
| **AT Engine tích hợp** | Tự tính AlphaTrend nội bộ qua MFI/RSI — không còn phụ thuộc `Custom\AlphaTrend.ex5` |
| **S/R Detection** | Tự động tìm Resistance (highest high) và Support (lowest low) trong `InpSR_Lookback` nến trên `InpSR_TF` với cache tăng tốc |
| **Chart Drawing** | Vẽ S/R lines, nhãn giá, tín hiệu AT BUY/SELL và info panel lên chart trực tiếp |
| **OnTimer 60s** | Cập nhật và vẽ lại S/R + AT mỗi 60 giây thay vì không có timer (v1.00) |
| **Signal timeframe** | Tín hiệu dùng `PERIOD_CURRENT` — không còn tham số `InpSignalTF` riêng |
| **Bỏ Balance Scaling** | Loại bỏ `InpScaleLot` và `InpBaseBalance` — lot cố định theo `InpBaseLot × Fib(i)` |
| **SL lookback TF** | SL dùng `PERIOD_CURRENT` thay vì `InpSignalTF` như v1.00 |
| **InpMaxDCA mặc định** | Tăng từ 5 lên 9 cấp |
| **InpGrid mặc định** | Tăng từ 10 lên 100 points |
| **InpTpMin mặc định** | Tăng từ 1.0 lên 1.05 |

---

## 3. Tham số cấu hình - Input Parameters

### ==== S/R Settings ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpSR_Lookback` | 100 | Số nến nhìn lại để tìm S/R |
| `InpSR_TF` | PERIOD_M5 | Khung thời gian để tính S/R |
| `InpResistColor` | clrRed | Màu đường Resistance |
| `InpSupportColor` | clrDodgerBlue | Màu đường Support |
| `InpSR_AvgColor` | clrGold | Màu đường trung bình S/R |
| `InpSR_LineWidth` | 2 | Độ dày đường S/R |
| `InpSR_LineStyle` | STYLE_SOLID | Kiểu đường S/R |

### ==== Position Sizing ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpBaseLot` | 0.01 | Lot cơ sở (Fibonacci cấp 0) |
| `InpMaxDCA` | 9 | Số cấp DCA tối đa (bao gồm lệnh khởi tạo) |

### ==== DCA Grid ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpGrid` | 100 | Khoảng cách lưới tối thiểu (points) — sàn bảo vệ |

### ==== Take Profit ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpTpMax` | 1.5 | Hệ số TP tối đa (tại cấp DCA đầu tiên) |
| `InpTpMin` | 1.05 | Hệ số TP tối thiểu (tại cấp DCA cuối) |

### ==== Stop Loss ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpSLCandle` | 12 | Số nến nhìn lại để xác định SL tự nhiên (trên `PERIOD_CURRENT`) |
| `InpSLPoint` | 10 | Buffer thêm ngoài điểm cực trị nến (points) |
| `InpSLFlex` | 50 | Vùng linh hoạt SL (points) |

### ==== Signal Confirmation ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpConfirmBars` | 2 | Số nến tín hiệu phải duy trì liên tiếp trước khi vào lệnh |

### ==== Risk Control ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpCloseOnRev` | true | Đóng toàn bộ basket ngay khi có tín hiệu đảo chiều |
| `InpUseSL` | true | Bật/tắt Stop Loss cứng trên tất cả lệnh |

### ==== AlphaTrend Settings ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpATCoeff` | 1.0 | Hệ số nhân ATR cho dải AlphaTrend |
| `InpATPeriod` | 14 | Chu kỳ tính AlphaTrend (SMA of TrueRange + oscillator) |
| `InpATNoVol` | false | Dùng RSI thay vì MFI làm oscillator |
| `InpAT_DrawBars` | 300 | Số nến tính AT (phục vụ cả drawing và tín hiệu) |

### ==== EA Settings ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpMagic` | 2 | Magic number định danh lệnh |
| `InpPrintLog` | true | Bật/tắt in log chi tiết |

---

## 4. Chi tiết thuật toán

### Điều kiện kích hoạt

- Logic mở lệnh kích hoạt tại **đầu mỗi nến mới** trên `PERIOD_CURRENT` (phát hiện qua `iTime`).
- AT được tính lại (`CalcAlphaTrend()`) trên mỗi nến mới.
- Theo dõi Basket TP và SL hit chạy trên **mỗi Tick** (intra-bar monitoring).
- `OnTimer` (60 giây): cập nhật S/R (incremental hoặc full recalc), vẽ lại chart, cập nhật info panel.

### Thuật toán AlphaTrend nội bộ (CalcAlphaTrend)

EA tự tính AT từ raw OHLC mà không cần indicator bên ngoài:

```
Oscillator = MFI(period) nếu !InpATNoVol, hoặc RSI(period) nếu InpATNoVol
ATR_i      = SMA(TrueRange, InpATPeriod)
upTrend    = low[i]  - ATR_i × InpATCoeff    // mức hỗ trợ AT
downTrend  = high[i] + ATR_i × InpATCoeff    // mức kháng cự AT

bullish = (Oscillator >= 50)
AT[i]   = max(upTrend,   AT[i-1])  nếu bullish
AT[i]   = min(downTrend, AT[i-1])  nếu bearish
```

**Màu sắc AT:** So sánh AT[i] vs AT[i-2] (không phải AT[i-1]):
- `AT[i] > AT[i-2]` → xanh (bullish)
- `AT[i] < AT[i-2]` → đỏ (bearish)

**Tín hiệu crossover (với bộ lọc xen kẽ BUY/SELL):**
```
BUY signal:  AT[i] > AT[i-2] && AT[i-1] <= AT[i-3]
SELL signal: AT[i] < AT[i-2] && AT[i-1] >= AT[i-3]
Bộ lọc: BUY chỉ hợp lệ khi khoảng cách từ SELL cuối > BUY cuối (và ngược lại)
```

### Thuật toán S/R (FullRecalcSR / IncrementalUpdateSR)

```
Full Recalc:
  Quét InpSR_Lookback nến trên InpSR_TF
  g_resistance = max(high[1..n])  → thời gian tương ứng g_resistTime
  g_support    = min(low[1..n])   → thời gian tương ứng g_supportTime
  g_srAverage  = (resistance + support) / 2

Incremental Update (mỗi 60s):
  Nếu g_resistTime < g_windowOldest → FullRecalc (peak hết hạn)
  Nếu g_supportTime < g_windowOldest → FullRecalc (valley hết hạn)
  Ngược lại: chỉ kiểm tra nến mới nhất có tạo high/low mới không
```

### Flowchart OnTick

```
[Mỗi Tick]
  ├─ isNewBar? KHÔNG
  │    ├─ !g_inTrade → return
  │    ├─ SL hit? (CountPos == 0) → ResetBasket → EnterBasket (cùng chiều)
  │    └─ CheckBasketTP hit? → ResetBasket → EnterBasket (cùng chiều)
  │
  └─ isNewBar? CÓ
       ├─ CalcAlphaTrend()   // tính lại AT nội bộ
       ├─ Basket trống đột ngột → ResetBasket → EnterBasket (cùng chiều)
       ├─ Đọc buySignal / sellSignal từ g_atValues[] (crossover trên nến g_lastBar)
       ├─ [RISK] Tín hiệu đảo chiều khi đang có basket?
       │    InpCloseOnRev=true → ResetBasket → EnterBasket (chiều mới)
       │    InpCloseOnRev=false → log cảnh báo, giữ nguyên
       ├─ Cập nhật g_pendingDir / g_pendingCount
       └─ !g_inTrade && pendingCount >= InpConfirmBars
            → EnterBasket(isBuy)
```

### EnterBasket — Mở chuỗi DCA

**Bước 1: Tính SL**
```
sl = lowest low(InpSLCandle nến trên PERIOD_CURRENT) - (InpSLPoint + InpSLFlex) × Point   [BUY]
sl = highest high(InpSLCandle nến trên PERIOD_CURRENT) + (InpSLPoint + InpSLFlex) × Point  [SELL]
```

**Bước 2: Tính khoảng cách lưới tự động**
```
extreme       = min low của InpSLCandle nến gần nhất (BUY) / max high (SELL) trên PERIOD_CURRENT
range         = |entry - extreme|
g_dynamicGrid = max(range / InpMaxDCA,  InpGrid × Point)
```

**Bước 3: Mở lệnh**
```
Cấp 0: Market BUY/SELL, lot = InpBaseLot × Fib(0)
Cấp i: BuyLimit/SellLimit tại (entry ∓ dynamicGrid × i), lot = InpBaseLot × Fib(i)
  với i = 1 .. InpMaxDCA-1
```

> **Lưu ý:** v2.00 không có balance scaling — lot luôn là `InpBaseLot × Fib(i)` bất kể số dư.

### CheckBasketTP — Chốt lời Basket

```
n        = số lệnh đang mở
tpRatio  = InpTpMax - (InpTpMax - InpTpMin) × (n-1) / (InpMaxDCA-1)
           [min = InpTpMin = 1.05]
tpDist   = tpRatio × g_dynamicGrid
tpPrice  = avgEntry + tpDist (BUY) | avgEntry - tpDist (SELL)
TP hit   → ResetBasket → EnterBasket (cùng chiều, chu kỳ mới)
```

### Dãy Fibonacci (lot tại mỗi cấp DCA — với InpBaseLot=0.01)

| Cấp (0-indexed) | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| Fib(n) | 1 | 1 | 2 | 3 | 5 | 8 | 13 | 21 | 34 |
| Lot (0.01 base) | 0.01 | 0.01 | 0.02 | 0.03 | 0.05 | 0.08 | 0.13 | 0.21 | 0.34 |

---

## 5. Mô tả kỹ thuật

### Biến trạng thái toàn cục — Nhóm AT

| Biến | Kiểu | Mục đích |
|------|------|---------|
| `g_oscHandle` | int | Handle MFI hoặc RSI dùng làm oscillator trong tính AT |
| `g_atValues[]` | double[] | Mảng giá trị AT (oldest→newest), size = `InpAT_DrawBars` |
| `g_atATR[]` | double[] | Mảng SMA(TrueRange) tương ứng |
| `g_atColor[]` | double[] | Màu mỗi nến: 0=bullish, 1=bearish |
| `g_atTimes[]` | datetime[] | Thời gian mở mỗi nến trong mảng AT |
| `g_atCurrent` | double | Giá trị AT tại nến cuối đã đóng |
| `g_atDirection` | int | Hướng AT hiện tại: +1=bullish, -1=bearish |
| `g_atSignal` | int | Tín hiệu mới nhất: +1=BUY, -1=SELL, 0=không có |
| `g_atLastBuyIdx` | int | Index trong `g_atValues[]` của tín hiệu BUY cuối cùng |
| `g_atLastSellIdx` | int | Index trong `g_atValues[]` của tín hiệu SELL cuối cùng |

### Biến trạng thái toàn cục — Nhóm S/R

| Biến | Kiểu | Mục đích |
|------|------|---------|
| `g_resistance` | double | Mức kháng cự hiện tại (max high n nến) |
| `g_support` | double | Mức hỗ trợ hiện tại (min low n nến) |
| `g_srAverage` | double | Trung bình S/R = (resistance + support) / 2 |
| `g_resistTime` | datetime | Thời gian nến tạo ra resistance |
| `g_supportTime` | datetime | Thời gian nến tạo ra support |
| `g_windowOldest` | datetime | Thời gian nến cũ nhất trong cửa sổ lookback — dùng để kiểm tra cache hết hạn |

### Biến trạng thái toàn cục — Nhóm DCA

| Biến | Kiểu | Mục đích |
|------|------|---------|
| `g_pendingDir` | int | Hướng tín hiệu đang chờ xác nhận (+1/-1/0) |
| `g_pendingCount` | int | Số nến tín hiệu duy trì liên tiếp |
| `g_inTrade` | bool | Trạng thái basket đang mở |
| `g_tradeDir` | int | Chiều basket hiện tại: +1=BUY, -1=SELL |
| `g_dynamicGrid` | double | Khoảng cách lưới tính theo SL range (price units) |

### Object prefixes trên chart

| Prefix | Loại đối tượng |
|--------|---------------|
| `AlphaBot_SR_` | Đường S/R và nhãn giá |
| `AlphaBot_AT_Line_` | Đường AT (segment) |
| `AlphaBot_AT_Buy_` / `AlphaBot_AT_Sell_` | Nhãn tín hiệu BUY/SELL |
| `AlphaBot_AT_DirLabel` | Nhãn hướng lớn góc phải trên |

### OnTimer — luồng xử lý (mỗi 60 giây)

1. `IncrementalUpdateSR()` — cập nhật S/R mini hoặc full recalc nếu cache hết hạn
2. `CalcAlphaTrend()` — tính lại toàn bộ AT array
3. `DrawSROnChart()` — vẽ 3 đường ngang + nhãn giá R/S/Avg
4. `DrawAlphaTrendOnChart()` — vẽ nhãn tín hiệu BUY/SELL mới nhất
5. `DrawInfoPanel()` — cập nhật info panel góc trái trên (S/R info + AT status + basket PnL)

---

## 6. Ví dụ cấu hình khuyến nghị

### XAUUSD — M15 (Tài khoản $10,000)

| Input | Giá trị | Lý do |
|-------|---------|-------|
| `InpBaseLot` | 0.01 | Tổng exposure 9 cấp = 88× base — cần lot nhỏ |
| `InpMaxDCA` | 7 | Giảm từ 9 xuống 7 để an toàn hơn — tổng Fib = 1+1+2+3+5+8+13=33× |
| `InpGrid` | 100 | 100 pts = 10 pips — phù hợp biến động M15 XAUUSD |
| `InpSLCandle` | 10 | 10 nến M15 = nhìn lại 2.5 giờ |
| `InpConfirmBars` | 2 | Xác nhận 2 nến giảm tín hiệu giả |
| `InpCloseOnRev` | true | Đảo chiều nhanh theo AT |
| `InpSR_Lookback` | 100 | 100 nến M5 = ~8 giờ lịch sử S/R |
| `InpSR_TF` | PERIOD_M5 | S/R trên M5 — độ phân giải cao hơn |
| `InpATPeriod` | 14 | Chuẩn — phù hợp M15 |
| `InpATCoeff` | 1.0 | Hệ số mặc định |

---

## 7. Lưu ý rủi ro & Backtest

> [!WARNING]
> **Rủi ro Fibonacci DCA mở rộng:** Tổng lot của 9 cấp DCA = 1+1+2+3+5+8+13+21+34 = **88× lot cơ sở**. Với `InpBaseLot=0.01`, exposure tối đa là 0.88 lot. Trên XAUUSD với giá $3000, mỗi 0.01 lot ≈ $3/pip — tổng đòn bẩy rất lớn khi đầy đủ các cấp.

> [!WARNING]
> **Auto re-enter sau khi chạm SL:** Khi toàn bộ basket đóng do SL, EA **ngay lập tức mở basket mới cùng chiều**. Trong xu hướng mạnh ngược chiều, có thể thua lỗ nhiều chu kỳ liên tiếp.

> [!CAUTION]
> **S/R không phải tín hiệu giao dịch:** Các đường S/R được vẽ chỉ để tham khảo — EA không dùng S/R để quyết định vào/ra lệnh. Chỉ AlphaTrend crossover mới điều khiển logic giao dịch.

- **Backtest Mode:** Bắt buộc dùng **`Every Tick`** — EA dùng pending limit orders và intra-bar TP/SL monitoring, cần tick-by-tick để mô phỏng chính xác.
- **Visual objects:** Các đường S/R và AT chỉ hiển thị trong live trading, không xuất hiện trong Strategy Tester (MT5 Tester không hỗ trợ `ObjectCreate` đầy đủ).

---

*Tài liệu cập nhật: 2026-03-17 — ALPHA_TREND_DCA v2.00*

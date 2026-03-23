# ALPHA TREND DCA v1.00 — Tài Liệu Thuật Toán

**File:** `ALPHA_TREND_DCA_v1.00.mq5`  
**Phiên bản:** 1.00  
**Ngôn ngữ:** MQL5  
**Ngày cập nhật:** 2026-03-17  

---

## 1. Tổng quan chiến lược

**ALPHA TREND DCA** là EA kết hợp tín hiệu trend từ indicator **AlphaTrend** (indicator bên ngoài) với cơ chế DCA Fibonacci. EA chỉ vào lệnh khi tín hiệu crossover AlphaTrend được xác nhận liên tục trong `InpConfirmBars` nến, sau đó mở toàn bộ chuỗi DCA gồm 1 lệnh thị trường + các pending limit phân bố đều theo `dynamicGrid`. Lot tăng dần theo dãy Fibonacci (1, 1, 2, 3, 5, 8...) và được nhân hệ số scale theo số dư tài khoản.

Basket được chốt lời khi giá chạm đến mức TP tính từ giá trung bình có trọng số. Tỉ lệ khoảng cách TP giảm dần khi nhiều lệnh DCA mở ra. Khi xuất hiện tín hiệu đảo chiều, EA có thể lập tức đóng toàn bộ basket và mở basket mới theo chiều ngược lại.

---

## 2. Tham số cấu hình - Input Parameters

### ==== Position Sizing ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpBaseLot` | 0.01 | Lot cơ sở tại mức `InpBaseBalance` |
| `InpMaxDCA` | 5 | Số cấp DCA tối đa (bao gồm lệnh khởi tạo) |

### ==== Lot Scaling ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpScaleLot` | true | Bật scale lot theo số dư tài khoản |
| `InpBaseBalance` | 100000 | Số dư tham chiếu để tính hệ số nhân lot (USD) |

### ==== DCA Grid ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpGrid` | 10 | Khoảng cách lưới tối thiểu (points) — sàn bảo vệ khi `dynamicGrid` quá nhỏ |

### ==== Take Profit ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpTpMax` | 1.5 | Hệ số TP tối đa (tại cấp DCA đầu tiên) |
| `InpTpMin` | 1.0 | Hệ số TP tối thiểu (tại cấp DCA cuối) |

### ==== Stop Loss ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpSLCandle` | 12 | Số nến nhìn lại để xác định SL tự nhiên (trên `InpSignalTF`) |
| `InpSLPoint` | 10 | Buffer thêm ngoài điểm cực trị nến (points) |
| `InpSLFlex` | 50 | Vùng linh hoạt SL — giá vượt SL tối đa bao nhiêu points mới tính là chạm (points) |

### ==== Signal Confirmation ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpConfirmBars` | 2 | Số nến tín hiệu phải duy trì liên tiếp trước khi vào lệnh |

### ==== Risk Control ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpCloseOnRev` | true | Đóng toàn bộ basket ngay khi xuất hiện tín hiệu đảo chiều |
| `InpUseSL` | true | Bật/tắt Stop Loss cứng trên tất cả lệnh |

### ==== AlphaTrend Settings ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpATCoeff` | 1.0 | Hệ số nhân ATR cho dải AlphaTrend |
| `InpATPeriod` | 14 | Chu kỳ tính AlphaTrend |
| `InpATNoVol` | false | Dùng RSI thay vì MFI làm oscillator |
| `InpSignalTF` | PERIOD_H1 | Khung thời gian tín hiệu (indicator + phát hiện nến mới) |

### ==== EA Settings ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpMagic` | 1 | Magic number định danh lệnh |
| `InpPrintLog` | true | Bật/tắt in log chi tiết |

---

## 3. Chi tiết thuật toán

### Điều kiện kích hoạt

- Logic mở lệnh kích hoạt tại **đầu mỗi nến mới** trên `InpSignalTF` (phát hiện qua so sánh `iTime`).
- Theo dõi Basket TP và SL hit chạy trên **mỗi Tick** (intra-bar monitoring).
- Không có `OnTimer` — không có drawing hay timer.

### AlphaTrend Signal (bộ tín hiệu bên ngoài)

EA đọc indicator `Custom\AlphaTrend` qua handle `g_atHandle`:
- **Buffer[2]** — giá trị BUY signal (khác `EMPTY_VALUE` và > 0 là có tín hiệu mua)
- **Buffer[3]** — giá trị SELL signal (khác `EMPTY_VALUE` và > 0 là có tín hiệu bán)
- Tín hiệu lấy từ **nến vừa đóng** (`index = 1`)

### Cơ chế xác nhận tín hiệu (`g_pendingDir`, `g_pendingCount`)

```
Mỗi nến mới:
  buySignal  → g_pendingDir = +1, đếm số nến duy trì
  sellSignal → g_pendingDir = -1, đếm số nến duy trì
  Không có signal → vẫn tiếp tục đếm (hướng cũ giữ nguyên)

Vào lệnh khi:
  !g_inTrade && g_pendingCount >= InpConfirmBars
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
       ├─ Basket trống đột ngột → ResetBasket → EnterBasket (cùng chiều)
       ├─ Đọc buySignal / sellSignal từ g_atHandle buffer[2],[3]
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
sl = lowest low(InpSLCandle nến trên InpSignalTF) - (InpSLPoint + InpSLFlex) × Point   [BUY]
sl = highest high(InpSLCandle nến trên InpSignalTF) + (InpSLPoint + InpSLFlex) × Point  [SELL]
```

**Bước 2: Tính khoảng cách lưới tự động**
```
extreme       = min low của InpSLCandle nến gần nhất (BUY) hoặc max high (SELL)
range         = |entry - extreme|
g_dynamicGrid = max(range / InpMaxDCA,  InpGrid × Point)
```

**Bước 3: Mở lệnh**
```
Cấp 0: Market BUY/SELL, lot = ScaledBaseLot × Fib(0)
Cấp i: BuyLimit/SellLimit tại (entry ∓ dynamicGrid × i), lot = ScaledBaseLot × Fib(i)
  với i = 1 .. InpMaxDCA-1
```

**Hệ số scale lot theo số dư:**
```
ScaledBaseLot = InpBaseLot × (AccountBalance / InpBaseBalance)   [nếu InpScaleLot=true]
ScaledBaseLot = InpBaseLot                                       [nếu InpScaleLot=false]
```

### CheckBasketTP — Chốt lời Basket

```
n        = số lệnh đang mở
tpRatio  = InpTpMax - (InpTpMax - InpTpMin) × (n-1) / (InpMaxDCA-1)
           [min = InpTpMin]
tpDist   = tpRatio × g_dynamicGrid
tpPrice  = avgEntry + tpDist (BUY) | avgEntry - tpDist (SELL)
TP hit   → ResetBasket → EnterBasket (cùng chiều, lặp lại chu kỳ)
```

Khi càng nhiều lệnh DCA mở ra (`n` tăng), `tpRatio` giảm dần → khoảng cách TP đến giá trung bình ngắn lại.

### Dãy Fibonacci (lot tại mỗi cấp DCA)

| Cấp (0-indexed) | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| Fib(n) | 1 | 1 | 2 | 3 | 5 | 8 | 13 | 21 | 34 |

---

## 4. Mô tả kỹ thuật

### Biến trạng thái toàn cục

| Biến | Kiểu | Mục đích |
|------|------|---------|
| `g_atHandle` | int | Handle indicator AlphaTrend bên ngoài |
| `g_lastBarTime` | datetime | Thời gian nến cuối đã xử lý — phát hiện nến mới |
| `g_pendingDir` | int | Hướng tín hiệu đang chờ: +1=BUY, -1=SELL, 0=chưa có |
| `g_pendingCount` | int | Số nến tín hiệu đã duy trì liên tiếp |
| `g_inTrade` | bool | Trạng thái basket đang mở |
| `g_tradeDir` | int | Chiều basket hiện tại: +1=BUY, -1=SELL |
| `g_dynamicGrid` | double | Khoảng cách lưới tự động tính theo SL range (price units) |

### Vòng đời OnTick — thứ tự xử lý

1. Phát hiện nến mới bằng `iTime(_Symbol, InpSignalTF, 0)` vs `g_lastBarTime`
2. **Intra-bar path** (không phải nến mới): chỉ kiểm tra SL hit và Basket TP
3. **New-bar path**: xử lý tín hiệu AlphaTrend, cập nhật confirmation counter, vào lệnh nếu đủ điều kiện
4. `ResetBasket()` = đóng tất cả positions + xóa pending orders + reset state

### Yêu cầu indicator bên ngoài

> [!CAUTION]
> EA v1.00 phụ thuộc vào indicator `Custom\AlphaTrend` phải được cài đặt trong thư mục `MQL5\Indicators\Custom\`. Nếu thiếu file indicator, `OnInit()` sẽ trả về `INIT_FAILED` và EA không khởi động.

---

## 5. Ví dụ cấu hình khuyến nghị

### XAUUSD — H1 (Tài khoản $10,000)

| Input | Giá trị | Lý do |
|-------|---------|-------|
| `InpBaseLot` | 0.01 | Lot nhỏ để buffer qua tối đa 5 cấp DCA |
| `InpMaxDCA` | 5 | 5 cấp đủ cho biên độ thông thường XAUUSD H1 |
| `InpGrid` | 15 | Sàn 15 pts phòng trường hợp range quá hẹp |
| `InpTpMax` | 1.5 | TP xa khi ít lệnh — chờ giá quay đủ xa |
| `InpTpMin` | 1.0 | TP sát hơn khi nhiều lệnh DCA — thu hồi sớm |
| `InpSLCandle` | 12 | 12 nến H1 = SL nhìn lại ~12 giờ |
| `InpConfirmBars` | 2 | Xác nhận 2 nến — giảm tín hiệu giả |
| `InpCloseOnRev` | true | Đảo chiều nhanh theo trend mới |
| `InpSignalTF` | PERIOD_H1 | Tín hiệu H1 — ít nhiễu |
| `InpBaseBalance` | 10000 | Bằng số dư thực tế để ScaleLot = 1× |

---

## 6. Lưu ý rủi ro & Backtest

> [!WARNING]
> **Rủi ro Fibonacci DCA:** Tổng lot của 5 cấp DCA = 1+1+2+3+5 = 12× lot cơ sở. Khi toàn bộ 5 lệnh mở, exposure thực có thể lên 12× `InpBaseLot × ScaleRatio`. Cần tính toán margin kỹ.

> [!WARNING]
> **Auto re-enter sau khi chạm SL:** Khi toàn bộ basket bị đóng do SL hit, EA **lập tức mở basket mới cùng chiều** từ giá hiện tại. Trong điều kiện trending mạnh ngược chiều, điều này có thể dẫn đến nhiều chu kỳ thua lỗ liên tiếp.

> [!CAUTION]
> **Indicator phụ thuộc bên ngoài:** Khác v2.00, phiên bản này không tự tính AlphaTrend. File indicator `Custom\AlphaTrend.ex5` phải tồn tại trong máy client mới chạy được.

- **Backtest Mode:** Bắt buộc dùng **`Every Tick`** — EA dùng pending limit orders và intra-bar TP monitoring, cần tick-by-tick để mô phỏng chính xác.

---

*Tài liệu cập nhật: 2026-03-17 — ALPHA_TREND_DCA v1.00*

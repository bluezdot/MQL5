# [Viprasol] Multi-Timeframe Trend Signal Engine — EA v1.00

> **File:** `bots/Trend/v1.mq5`  
> **Nguồn gốc:** Dịch từ Pine Script indicator `[Viprasol] Multi-Timeframe Trend Signal Engine` sang MQL5  
> **Phong cách:** Trend-following, bar-close confirmation, anti-repaint

---

## Mục lục

1. [Tổng quan chiến lược](#1-tổng-quan-chiến-lược)
2. [Luồng tín hiệu](#2-luồng-tín-hiệu)
3. [Các chỉ báo thành phần](#3-các-chỉ-báo-thành-phần)
4. [Signal Mode: All vs Filtered](#4-signal-mode-all-vs-filtered)
5. [Bộ lọc bổ sung](#5-bộ-lọc-bổ-sung)
6. [Quản lý vốn & rủi ro](#6-quản-lý-vốn--rủi-ro)
7. [Tham số đầu vào](#7-tham-số-đầu-vào)
8. [Sơ đồ quyết định vào lệnh](#8-sơ-đồ-quyết-định-vào-lệnh)
9. [Hướng dẫn cài đặt gợi ý](#9-hướng-dẫn-cài-đặt-gợi-ý)
10. [Lưu ý & cảnh báo](#10-lưu-ý--cảnh-báo)

---

## 1. Tổng quan chiến lược

EA này là hệ thống giao dịch xu hướng đa khung thời gian (**Multi-Timeframe Trend-Following**). Tín hiệu gốc được tạo ra bởi **SuperTrend crossover**, sau đó được lọc qua nhiều lớp bộ lọc độc lập để chỉ giữ lại những tín hiệu chất lượng cao, đồng thuận với xu hướng dài hạn.

**Triết lý cốt lõi:**
- Chỉ vào lệnh **theo chiều trend**, không đi ngược thị trường
- Tất cả tín hiệu đều dựa trên **nến đã đóng** (bar-close confirmed) — tránh repaint
- Dừng lỗ được đặt dựa trên **ATR động** — thích ứng với biến động thực tế
- Hỗ trợ **nhiều mức chốt lời** (TP1/TP2/TP3) với cơ chế bảo vệ lợi nhuận

---

## 2. Luồng tín hiệu

```
[Giá đóng cửa nến N-1]
        │
        ▼
┌─────────────────────────────┐
│   SuperTrend Crossover      │  ← Tín hiệu thô (raw signal)
│   close crosses ST line     │
└────────────┬────────────────┘
             │ rawBuy / rawSell
             ▼
┌─────────────────────────────┐
│   SMA(13) Momentum Filter   │  ← close >= SMA13 (buy) / close <= SMA13 (sell)
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│   Signal Mode (EMA 200)     │  ← All Signals / Filtered Signals
│   aboveMainEma flag         │
└────────────┬────────────────┘
             │ tradeBuy / tradeSell
             ▼
┌─────────────────────────────┐
│   [Tùy chọn] Ribbon Filter  │  ← EMA20 vs EMA55 crossover
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│   [Tùy chọn] Chaos Filter   │  ← Chaos Trend Line direction
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│   [Tùy chọn] MTF ADX Filter │  ← ≥ N/6 timeframes đồng thuận
└────────────┬────────────────┘
             │ Tín hiệu cuối cùng
             ▼
        Vào lệnh BUY / SELL
```

---

## 3. Các chỉ báo thành phần

### 3.1 SuperTrend — Tín hiệu gốc

SuperTrend là chỉ báo theo dõi xu hướng dựa trên **ATR (Average True Range)**. Nó vẽ một đường hỗ trợ/kháng cự động và thay đổi màu khi giá vượt qua nó.

**Công thức (dịch từ Pine):**

```
src        = Open (của nến hiện tại)
upperBand  = src + Sensitivity × ATR(AtrFactor)
lowerBand  = src − Sensitivity × ATR(AtrFactor)

# Trailing band logic:
lowerBand  = max(lowerBand, prevLowerBand)  nếu close[prev] >= prevLowerBand
upperBand  = min(upperBand, prevUpperBand)  nếu close[prev] <= prevUpperBand

# Hướng trend:
Nếu đang ở upperBand (bearish):
   → close > upperBand  → chuyển sang lowerBand (bull), trendDir = -1
Nếu đang ở lowerBand (bullish):
   → close < lowerBand  → chuyển sang upperBand (bear), trendDir = +1
```

**Tín hiệu:**
- **BUY raw**: `close[1]` vượt lên trên ST line (crossover) **AND** `close >= SMA(13)`
- **SELL raw**: `close[1]` vượt xuống dưới ST line (crossunder) **AND** `close <= SMA(13)`

**Tham số điều chỉnh:**
| Input | Ý nghĩa | Tăng → | Giảm → |
|---|---|---|---|
| `InpSensitivity` (2.5) | ATR multiplier cho bands | Ít tín hiệu hơn, band rộng | Nhiều tín hiệu, nhạy hơn |
| `InpAtrFactor` (11) | Chu kỳ ATR | Band smoothed hơn | Band nhảy hơn |

---

### 3.2 Main EMA(200) — Bộ lọc xu hướng chính

Đường EMA 200 phân chia thị trường thành hai chế độ:

```
close > EMA(200)  →  aboveEma = TRUE   (vùng Bull)
close < EMA(200)  →  aboveEma = FALSE  (vùng Bear)
```

Cờ `aboveEma` được sử dụng bởi **Signal Mode** để phân loại tín hiệu.

---

### 3.3 SMA(13) — Momentum Filter

Đường SMA 13 kỳ dùng để loại bỏ tín hiệu yếu:
- BUY chỉ hợp lệ nếu `close >= SMA(13)` — giá đang có đà tăng
- SELL chỉ hợp lệ nếu `close <= SMA(13)` — giá đang có đà giảm

---

### 3.4 EMA Ribbon (EMA 20/55) — Bộ lọc tùy chọn

Ribbon gồm 5 đường EMA (20, 25, 35, 45, 55). Tín hiệu đơn giản hóa trong EA:

```
ribbonBullish = true   khi EMA(20) cross UP   EMA(55)
ribbonBullish = false  khi EMA(20) cross DOWN EMA(55)
```

Khi bật (`InpUseRibbon = true`):
- **BUY** chỉ được phép khi `ribbonBullish = true`
- **SELL** chỉ được phép khi `ribbonBullish = false`

---

### 3.5 Chaos Trend Line — Bộ lọc tùy chọn

Chaos Trend là một chỉ báo phát hiện đảo chiều xu hướng dựa trên **pivot highs/lows** và **ATR(100)**. Nó định nghĩa hai trạng thái:

```
chaosTrend = 0  → Xu hướng TĂNg (bullish)
chaosTrend = 1  → Xu hướng GIẢM (bearish)
```

**Cơ chế chuyển trạng thái:**
- Từ Bull sang Bear: `chaosHighMA < maxLow` **AND** `close < prevLow`
- Từ Bear sang Bull: `chaosLowMA > minHigh` **AND** `close > prevHigh`

Khi bật (`InpUseChaos = true`):
- **BUY** chỉ hợp lệ khi `chaosTrend == 0` (bullish)
- **SELL** chỉ hợp lệ khi `chaosTrend == 1` (bearish)

---

### 3.6 ADX Multi-Timeframe Confluence — Bộ lọc tùy chọn

Đo sức mạnh xu hướng (ADX Wilder, period=14) trên **6 khung thời gian**:

| Khung | Label |
|---|---|
| M5  | 5 phút |
| M15 | 15 phút |
| H1  | 1 giờ |
| H4  | 4 giờ |
| H12 | 12 giờ |
| D1  | Daily |

**Phân loại tín hiệu mỗi khung:**
```
ADX > medianADX × 1.2  → Bull (+1)
ADX < medianADX × 0.8  → Bear (-1)
Còn lại               → Neutral (0)
```

**BullScore**: tổng số khung đang Bull (0–6)  
**BearScore**: tổng số khung đang Bear (0–6)

Khi bật (`InpUseMtfFilter = true`, `InpMtfMinScore = 4`):
- **BUY** chỉ vào khi `bullScore >= 4`
- **SELL** chỉ vào khi `bearScore >= 4`

---

### 3.7 RSI(14) — Take Profit tùy chọn

RSI 14 kỳ dùng để phát hiện vùng **overbought/oversold** làm tín hiệu đóng lệnh:

| Tín hiệu | Điều kiện |
|---|---|
| Bull TP1 | RSI crossover 70 (mặc định) |
| Bull TP2 | RSI crossover 85 |
| Bear TP1 | RSI crossunder 30 |
| Bear TP2 | RSI crossunder 15 |

---

## 4. Signal Mode: All vs Filtered

Đây là tham số quan trọng nhất, quyết định **triết lý vào lệnh**:

### Mode: All Signals (mặc định)
Giao dịch **ngược với EMA 200** — tức là bắt đầu xu hướng mới từ vùng đối lập:

```
BUY  = rawBuy  AND close DƯỚI EMA(200)   ← giá đang pull back xuống, bắt đầu bật
SELL = rawSell AND close TRÊN EMA(200)   ← giá đang pull back lên, bắt đầu quay đầu
```

> Phù hợp với **mean reversion** kết hợp trend: mua khi giá về vùng dưới EMA, bán khi lên quá EMA.

### Mode: Filtered Signals
Giao dịch **theo EMA 200** — chỉ vào lệnh khi EMA xác nhận:

```
BUY  = rawBuy  AND close TRÊN EMA(200)   ← giá đã kéo lên rõ ràng
SELL = rawSell AND close DƯỚI EMA(200)   ← giá đã kéo xuống rõ ràng
```

> Phù hợp với **pure trend-following**: ít tín hiệu hơn nhưng chất lượng cao hơn.

---

## 5. Bộ lọc bổ sung

| Bộ lọc | Input | Mặc định | Khuyến nghị |
|---|---|---|---|
| Main EMA 200 | `InpUseMainEma` | `true` | Luôn bật |
| Ribbon EMA | `InpUseRibbon` | `true` | Bật cho timeframe ngắn |
| Chaos Trend | `InpUseChaos` | `false` | Thử nghiệm trước |
| MTF ADX | `InpUseMtfFilter` | `false` | Bật cho H1+ |
| RSI TP | `InpUseRsiTp` | `false` | Dùng thay TP cố định |

---

## 6. Quản lý vốn & rủi ro

### 6.1 Dừng lỗ (Stop Loss)

**ATR-based (mặc định, khuyến nghị):**
```
SL_distance = ATR(14) × InpAtrSlMult (mặc định 2.2)
BUY  SL = Ask − SL_distance
SELL SL = Bid + SL_distance
```

**Fixed points (tùy chọn):**
```
BUY  SL = Ask − InpFixedSL × Point
SELL SL = Bid + InpFixedSL × Point
```

---

### 6.2 Chốt lời nhiều mức (TP Cascade)

Rủi ro = khoảng cách từ entry đến SL

```
TP1 = entry ± Risk × InpTpMult1  (mặc định: 1× Risk = Risk:Reward 1:1)
TP2 = entry ± Risk × InpTpMult2  (mặc định: 2× Risk = R:R 1:2)
TP3 = entry ± Risk × InpTpMult3  (mặc định: 3× Risk = R:R 1:3)
```

**Cơ chế cascade mặc định (TP1 + TP2):**

```
Giá chạm TP1  →  SL dịch về Break-Even (entry + 1 point)
Giá chạm TP2  →  Đóng toàn bộ lệnh
```

**Khi bật TP3:**
```
Giá chạm TP1  →  SL về Break-Even
Giá chạm TP2  →  SL dịch lên TP1 (lock profit)
Giá chạm TP3  →  Đóng toàn bộ lệnh
```

---

### 6.3 Đóng lệnh ngược chiều

Khi tín hiệu đảo chiều xuất hiện:
- Nếu `InpCloseOnOpposite = true` (mặc định): **đóng lệnh cũ** trước khi mở lệnh mới
- Nếu `false`: chỉ mở lệnh mới, giữ lệnh cũ (không khuyến nghị)

---

## 7. Tham số đầu vào

### Main Settings

| Tham số | Mặc định | Phạm vi | Mô tả |
|---|---|---|---|
| `InpSensitivity` | 2.5 | 0.5 – 5.0 | ATR multiplier của SuperTrend. Thấp = nhiều tín hiệu |
| `InpSignalMode` | All Signals | — | Chế độ lọc EMA 200 |
| `InpAtrFactor` | 11 | 5 – 20 | ATR period cho SuperTrend bands |

### Trend Filters

| Tham số | Mặc định | Mô tả |
|---|---|---|
| `InpUseMainEma` | true | Dùng EMA 200 làm bộ lọc |
| `InpMainEmaPeriod` | 200 | Chu kỳ EMA chính |
| `InpUseRibbon` | true | Bộ lọc EMA Ribbon (20 vs 55) |
| `InpUseChaos` | false | Bộ lọc Chaos Trend Line |
| `InpUseMtfFilter` | false | Bộ lọc ADX đa khung thời gian |
| `InpMtfMinScore` | 4 | Số khung tối thiểu đồng thuận (1–6) |

### Trade Execution

| Tham số | Mặc định | Mô tả |
|---|---|---|
| `InpLotSize` | 0.1 | Khối lượng lệnh |
| `InpMagicNumber` | 202601 | ID phân biệt EA |
| `InpValidate` | Closed Candle | Chờ nến đóng (chống repaint) |
| `InpSlippage` | 10 | Slippage tối đa (points) |
| `InpReverseTrade` | false | Đảo chiều tín hiệu (dùng để test) |
| `InpCloseOnOpposite` | true | Đóng lệnh cũ khi có tín hiệu ngược |

### Risk Management

| Tham số | Mặc định | Mô tả |
|---|---|---|
| `InpUseFixedSL` | false | Dùng SL cố định (points) |
| `InpFixedSL` | 500 | Khoảng cách SL cố định (points) |
| `InpAtrSlMult` | 2.2 | Hệ số ATR(14) cho SL động |
| `InpUseFixedTP` | false | Dùng TP cố định (points) |
| `InpFixedTP` | 1000 | Khoảng cách TP cố định (points) |
| `InpTpMult1` | 1.0 | Hệ số TP1 (1× risk) |
| `InpUseTP2` | true | Kích hoạt TP2 |
| `InpTpMult2` | 2.0 | Hệ số TP2 (2× risk) |
| `InpUseTP3` | false | Kích hoạt TP3 |
| `InpTpMult3` | 3.0 | Hệ số TP3 (3× risk) |
| `InpMoveBeAtTp1` | true | Dịch SL về BE khi chạm TP1 |

### RSI TP Signals

| Tham số | Mặc định | Mô tả |
|---|---|---|
| `InpUseRsiTp` | false | Đóng lệnh khi RSI reaching level |
| `InpRsiTp1Bull` | 70.0 | RSI crossover → TP1 (Bull) |
| `InpRsiTp2Bull` | 85.0 | RSI crossover → TP2 (Bull) |

---

## 8. Sơ đồ quyết định vào lệnh

```
SuperTrend crossover?
    ├── KHÔNG → Không làm gì
    └── CÓ → close >= SMA(13)?
                ├── KHÔNG → Bỏ qua
                └── CÓ → Signal Mode?
                           ├── All Signals
                           │       ├── BUY raw  AND close < EMA200 → tradeBuy
                           │       └── SELL raw AND close > EMA200 → tradeSell
                           └── Filtered Signals
                                   ├── BUY raw  AND close > EMA200 → tradeBuy
                                   └── SELL raw AND close < EMA200 → tradeSell
                                           │
                                           ▼
                              InpUseRibbon? → Ribbon bullish/bearish khớp?
                                           │
                                           ▼
                              InpUseChaos? → Chaos direction khớp?
                                           │
                                           ▼
                              InpUseMtfFilter? → bullScore/bearScore đủ?
                                           │
                                           ▼
                              Tín hiệu hợp lệ → Đóng lệnh ngược (nếu có) → Mở lệnh mới
```

---

## 9. Hướng dẫn cài đặt gợi ý

### Cài đặt bảo thủ (ít tín hiệu, chất lượng cao)
```
InpSensitivity    = 3.5
InpSignalMode     = Filtered Signals
InpAtrFactor      = 14
InpUseRibbon      = true
InpUseMtfFilter   = true
InpMtfMinScore    = 4
InpAtrSlMult      = 2.5
InpTpMult1        = 1.5
InpUseTP2         = true
InpTpMult2        = 3.0
```

### Cài đặt cân bằng (mặc định)
```
InpSensitivity    = 2.5
InpSignalMode     = All Signals
InpAtrFactor      = 11
InpUseRibbon      = true
InpUseMtfFilter   = false
InpAtrSlMult      = 2.2
InpTpMult1        = 1.0
InpUseTP2         = true
InpTpMult2        = 2.0
```

### Cài đặt tích cực (nhiều tín hiệu)
```
InpSensitivity    = 1.5
InpSignalMode     = All Signals
InpAtrFactor      = 8
InpUseRibbon      = false
InpUseMtfFilter   = false
InpAtrSlMult      = 1.8
InpTpMult1        = 1.0
InpUseTP2         = false
InpMoveBeAtTp1    = true
```

### Timeframe phù hợp

| Khung thời gian | Signal Mode | Kết hợp |
|---|---|---|
| M15, M30 | All Signals | Ribbon + Chaos |
| H1, H4 | Filtered Signals | MTF ADX (score ≥ 4) |
| H4, D1 | Filtered Signals | MTF ADX (score ≥ 5) |

---

## 10. Lưu ý & cảnh báo

> [!WARNING]
> **Đây là công cụ hỗ trợ giao dịch, không phải hệ thống tự động hoàn hảo.** Luôn backtest trên dữ liệu lịch sử trước khi dùng live.

> [!IMPORTANT]
> **Anti-repaint**: Tất cả tín hiệu được tính toán trên `bar[1]` (nến đã hoàn toàn đóng). Mặc định `VALIDATE_CLOSED` đảm bảo không xảy ra repaint. Chỉ dùng `VALIDATE_LIVE` cho mục đích thử nghiệm.

> [!NOTE]
> **SuperTrend dùng `Open` làm midpoint** (không phải `Close`) — giữ nguyên logic gốc của Pine Script. Điều này khiến bands rộng hơn một chút so với SuperTrend thông thường.

> [!CAUTION]
> **MTF ADX Filter** gọi `iADXWilder` trên 6 khung thời gian mỗi bar — có thể làm chậm EA nếu dữ liệu chưa được cache. Bắt đầu thử nghiệm với filter này tắt.

> [!TIP]
> **RSI TP** nên dùng thay thế cho Fixed TP trên các thị trường có biến động cao (crypto, xauusd). Với Forex major, ATR-based TP thường ổn định hơn.

---

*Tài liệu này mô tả EA dựa trên mã nguồn `v1.mq5`. Mọi thay đổi tham số đều cần backtest lại.*

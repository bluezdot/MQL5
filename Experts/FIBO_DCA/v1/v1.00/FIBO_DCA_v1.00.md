# FIBO DCA v1.00 — Tài Liệu Thuật Toán

**File:** `FIBO_DCA_v1.00.mq5`  
**Phiên bản:** 1.00  
**Ngôn ngữ:** MQL5  
**Ngày cập nhật:** 2026-03-17  

---

## 1. Tổng quan chiến lược

**FIBO DCA** (Fibonacci Dollar-Cost Averaging) là EA giao dịch lưới theo chiến lược DCA, trong đó mỗi lệnh DCA tiếp theo được đặt theo bước giá tăng dần (Progressive Grid). Kích thước lot tăng theo dãy số Fibonacci (1, 1, 2, 3, 5, 8...) nhằm kéo giá trung bình nhanh hơn so với DCA cố định. EA hỗ trợ giao dịch hai chiều (Buy/Sell) hoặc một chiều, kết hợp lọc phạm vi giá từ nến ngày D1 hôm trước để tránh vào lệnh ngoài vùng an toàn.

Chiến lược hoạt động hai giai đoạn: **Giai đoạn DCA thường** (tăng lot theo Fibonacci) và **Giai đoạn Bảo vệ** (khi số lệnh vượt ngưỡng, chuyển sang hệ số nhân lot cố định). Thoát lệnh toàn bộ theo Basket TP (% lợi nhuận trên balance) và bảo vệ tài khoản qua Drawdown Protection tự động đóng toàn bộ khi vượt ngưỡng rút vốn định sẵn.

---

## 2. Tham số cấu hình - Input Parameters

### ==== Trading Settings ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpMagic` | 11 | Magic number định danh lệnh của EA |
| `InpDirection` | DIRECTION_BUY | Chiều giao dịch: `DIRECTION_BUY` / `DIRECTION_SELL` / `DIRECTION_BOTH` |
| `InpLots` | 0.01 | Khối lượng lệnh khởi tạo (lot cơ sở) |
| `InpStepPoints` | 200 | Khoảng cách lưới cơ bản (points) |
| `InpStepMultiplier` | 1.1 | Hệ số nhân khoảng cách lưới mỗi cấp DCA |
| `InpTakeProfitPercent` | 0.12 | Mục tiêu lợi nhuận tính theo % balance |
| `InpMaxOrders` | 27 | Số lệnh tối đa mỗi chiều |
| `InpSlippage` | 3 | Trượt giá cho phép (points) |
| `InpRangeMargin` | 600 | Biên mở rộng thêm từ D1 High/Low (points) |

### ==== Drawdown Protection ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpEnableDrawdownProtection` | true | Bật/tắt tính năng bảo vệ drawdown |
| `InpInitBalance` | 200000 | Số dư tham chiếu để tính `g_ScaleRatio` |
| `InpMaxDrawdownPercent` | 30 | Ngưỡng drawdown tối đa (%) — được nhân với `ScaleRatio` |

### ==== Basket Protection & Recovery ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpProtectionThreshold` | 6 | Số lệnh mở tối thiểu để kích hoạt giai đoạn bảo vệ |
| `InpProtectionStepPoints` | 200 | Khoảng cách lưới trong giai đoạn bảo vệ (points) |
| `InpProtectionStepMultiplier` | 1.1 | Hệ số nhân lưới trong giai đoạn bảo vệ |
| `InpProtectionLotMultiplier` | 1.5 | Hệ số nhân lot trong giai đoạn bảo vệ |
| `InpProtectionTakeProfitPercent` | 10.0 | Mục tiêu TP giai đoạn bảo vệ (% balance) |

### ==== Statistics & Export ====

| Input | Mặc Định | Mô tả |
|-------|----------|-------|
| `InpExportPath` | "" | Đường dẫn tuyệt đối để xuất CSV (chỉ trong Tester). Để trống để tắt |

---

## 3. Chi tiết thuật toán

### Điều kiện kích hoạt

- Lệnh được xử lý trên **mỗi Tick** (`OnTick()`).
- Vùng giá D1 được làm mới tự động mỗi **1 giờ** thông qua `OnTimer()`.

### Flowchart

```
[OnInit]
  → CalculateTradingRange()    // Tính g_MinPrice, g_MaxPrice từ D1±margin
  → g_InitialBalance = balance // Khởi tạo theo dõi drawdown

[OnTimer — mỗi 1 giờ]
  → CalculateTradingRange()    // Làm mới vùng D1

[OnTick]
  → m_symbol.RefreshRates()
  → g_ScaleRatio = floor(balance / InpInitBalance)
  │
  ├─ [CheckDrawdownProtection]
  │    Nếu (InitBalance - Equity) / InitBalance × 100
  │         ≥ InpMaxDrawdownPercent × ScaleRatio
  │    → Đóng toàn bộ lệnh, DỪNG xử lý (return)
  │
  ├─ Phân tích vị thế hiện tại
  │    buy_positions, buy_last_price, buy_profit_money
  │    sell_positions, sell_last_price, sell_profit_money
  │
  ├─ [ProcessBuyLogic]  (nếu direction = BUY hoặc BOTH)
  │    Giá Ask trong [g_MinPrice, g_MaxPrice]?
  │    ├─ buy_positions == 0
  │    │    → Hủy pending BUY_LIMIT cũ
  │    │    → Mở Market BUY: lot = InpLots × ScaleRatio
  │    └─ buy_positions < InpMaxOrders && chưa có pending BUY_LIMIT
  │         ├─ Giai đoạn 1 (pos < Threshold):
  │         │    step = InpStepPoints × Point × InpStepMultiplier^(pos-1)
  │         │    lot  = InpLots × Fib(pos) × ScaleRatio
  │         └─ Giai đoạn 2 (pos ≥ Threshold):
  │              step = InpProtectionStepPoints × Point × InpProtectionStepMultiplier^(pos-threshold)
  │              lot  = base_lot × InpProtectionLotMultiplier^(pos-threshold+1)
  │         → Đặt BUY_LIMIT tại (buy_last_price - step)
  │
  ├─ [ProcessSellLogic] (logic đối xứng, chiều ngược lại)
  │
  └─ [CheckBasketTakeProfit]
       buy_profit_money  ≥ balance × (InpTakeProfitPercent / 100)  → Đóng tất cả BUY
       sell_profit_money ≥ balance × (InpTakeProfitPercent / 100)  → Đóng tất cả SELL
       (Giai đoạn 2 dùng InpProtectionTakeProfitPercent)
```

### Công thức tính bước lưới và lot

**Giai đoạn 1 — Normal DCA** (`pos < InpProtectionThreshold`)

```
step     = InpStepPoints × Point × InpStepMultiplier^(pos - 1)
BuyLimit = buy_last_price  - step
lot      = InpLots × Fib(pos) × ScaleRatio
```

**Giai đoạn 2 — Protection DCA** (`pos ≥ InpProtectionThreshold`)

```
step      = InpProtectionStepPoints × Point × InpProtectionStepMultiplier^(pos - threshold)
BuyLimit  = buy_last_price - step
base_lot  = InpLots × Fib(threshold) × ScaleRatio
lot       = base_lot × InpProtectionLotMultiplier^(pos - threshold + 1)
```

> [!WARNING]
> **Không có Stop Loss cứng per lệnh.** EA chỉ bảo vệ tổng tài khoản qua Drawdown Protection (đóng toàn bộ khi vượt ngưỡng) và chốt lời qua Basket TP. Không có cơ chế thoát lỗ cho từng vị thế riêng lẻ.

### Dãy Fibonacci dùng cho tỉ lệ lot

| Thứ tự lệnh (0-based) | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| Fib(n) | 1 | 1 | 2 | 3 | 5 | 8 | 13 | 21 | 34 | 55 |

### Ví dụ chuỗi lệnh BUY (`InpLots=0.01`, `InpStepPoints=200`, `InpStepMultiplier=1.1`)

| Lệnh | Fib(n) | Lot | Bước lưới | Tích lũy |
|------|--------|-----|-----------|----------|
| 1 (Initial) | 1 | 0.01 | — | — |
| 2 (DCA #1) | 1 | 0.01 | 200 pts | 200 pts |
| 3 (DCA #2) | 2 | 0.02 | 220 pts | 420 pts |
| 4 (DCA #3) | 3 | 0.03 | 242 pts | 662 pts |
| 5 (DCA #4) | 5 | 0.05 | 266 pts | 928 pts |
| 6 (DCA #5) | 8 | 0.08 | 293 pts | 1221 pts |
| 7+ (Bảo vệ) | — | ×1.5 mỗi cấp | `InpProtectionStepPoints` | — |

---

## 4. Mô tả kỹ thuật

### Enum và biến toàn cục quan trọng

```cpp
enum ENUM_TRADE_DIRECTION {
    DIRECTION_BUY,   // Chỉ Buy
    DIRECTION_SELL,  // Chỉ Sell
    DIRECTION_BOTH   // Cả hai chiều
};
```

| Biến | Kiểu | Mục đích |
|------|------|---------|
| `g_MinPrice` / `g_MaxPrice` | double | Biên vùng giao dịch tính từ D1 High/Low ± margin |
| `g_InitialBalance` / `g_PeakBalance` | double | Theo dõi balance gốc để tính drawdown |
| `g_ScaleRatio` | int | Hệ số nhân lot tự động — tính lại mỗi Tick |
| `g_EquityFileHandle` | int | File handle ghi equity curve trong Tester |
| `g_SessionFolder` | string | Tên thư mục phiên xuất dữ liệu (`Symbol_Magic_Timestamp`) |

### Vòng đời OnTick() — thứ tự xử lý

1. `m_symbol.RefreshRates()` — Làm mới dữ liệu giá
2. Tính `g_ScaleRatio = floor(balance / InpInitBalance)`
3. `CheckDrawdownProtection()` — Kiểm tra drawdown, dừng nếu vượt ngưỡng
4. Loop `PositionsTotal()` — Phân loại và tổng hợp thông số BUY/SELL
5. `ProcessBuyLogic()` / `ProcessSellLogic()` — Mở lệnh khởi tạo hoặc đặt pending DCA
6. `CheckBasketTakeProfit()` — Đóng toàn bộ khi đạt mục tiêu lợi nhuận
7. `LogEquityStatus()` — Ghi snapshot equity (chỉ trong Tester khi có `InpExportPath`)

### Scale Ratio — cơ chế tự động điều chỉnh

```
g_ScaleRatio = floor(CurrentBalance / InpInitBalance)
```

Khi balance tăng 2× so với tham chiếu, `ScaleRatio = 2` → lot nhân đôi, đồng thời ngưỡng drawdown tính theo giá trị tuyệt đối cũng nhân đôi. Đây là cơ chế tự động tăng quy mô theo vốn nhưng cũng khuếch đại rủi ro tương ứng.

### Xuất dữ liệu (chỉ trong Strategy Tester)

Khi `InpExportPath` được đặt, `OnDeinit()` sẽ xuất các file vào `{InpExportPath}\{SessionFolder}\`:

| File | Nội dung |
|------|----------|
| `trades.csv` | Lịch sử lệnh với profit / commission / swap |
| `price-h1.csv` | Dữ liệu OHLCV H1 toàn bộ kỳ backtest |
| `balance.csv` | Snapshot balance và equity theo giờ |
| `input.set` | Toàn bộ tham số input để tái hiện backtest |

---

## 5. Ví dụ cấu hình khuyến nghị

### XAUUSD — M15 (Tài khoản $2,000 – $5,000)

| Input | Giá trị | Lý do |
|-------|---------|-------|
| `InpDirection` | DIRECTION_BUY | Vàng có thiên hướng tăng dài hạn, ưu tiên mua |
| `InpLots` | 0.01 | Lot nhỏ để chịu đủ nhiều lệnh DCA liên tiếp |
| `InpStepPoints` | 200 | ~20 pips, phù hợp biến động intraday XAUUSD |
| `InpStepMultiplier` | 1.1 | Khoảng cách tăng dần nhẹ, tránh đặt lệnh quá thưa |
| `InpTakeProfitPercent` | 0.12 | Mục tiêu 0.12% balance mỗi chu kỳ giao dịch |
| `InpMaxOrders` | 15 | Giới hạn an toàn để kiểm soát margin sử dụng |
| `InpInitBalance` | 2000 | Bằng số dư thực tế ban đầu để ScaleRatio = 1 |
| `InpMaxDrawdownPercent` | 30 | Cắt lỗ toàn bộ khi rút vốn vượt 30% |
| `InpProtectionThreshold` | 6 | Kích hoạt giai đoạn bảo vệ từ lệnh thứ 6 |

---

## 6. Lưu ý rủi ro & Backtest

> [!WARNING]
> **Rủi ro Martingale Fibonacci:** Lot tăng theo dãy Fibonacci — lệnh thứ 10 có lot = 55× lot khởi tạo. Tổng exposure nếu tất cả 10 lệnh đều mở có thể lên tới 143× lot ban đầu. Cần tính toán margin kỹ lưỡng trước khi chạy live.

> [!WARNING]
> **Không có Stop Loss cứng:** Trong điều kiện thị trường trending mạnh hoặc xảy ra gap giá lớn, tài khoản có thể bị cháy trước khi Drawdown Protection kịp kích hoạt. Cần giám sát thường xuyên, đặc biệt trong các phiên có tin tức lớn.

> [!CAUTION]
> **Scale Ratio tăng tự động:** Khi balance vượt nhiều lần `InpInitBalance`, `g_ScaleRatio` tăng và kéo theo kích thước lot của toàn bộ chuỗi DCA tăng theo. Cần xem xét đặt lại `InpInitBalance` hoặc giảm `InpLots` khi tài khoản tăng trưởng đáng kể.

- **Backtest Mode:** Bắt buộc dùng **`Every Tick`** để kết quả mô phỏng chính xác nhất. Lệnh DCA sử dụng pending `BUY_LIMIT` / `SELL_LIMIT` nên cần từng tick để xác định đúng thời điểm khớp lệnh.

---

*Tài liệu cập nhật: 2026-03-17 — FIBO_DCA v1.00*

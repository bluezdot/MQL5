# GRID DCA v1.00 — Tài Liệu Thuật Toán

> **File:** `GRID_DCA_v1.00.mq5`  
> **Phát hành:** 2026-03-11  
> **Tác giả:** Tran Hoang Nam

---

## 1. Tổng Quan

Grid DCA v1.00 là phiên bản đầu tiên của Expert Advisor giao dịch theo chiến lược **Grid kết hợp DCA (Dollar Cost Averaging)**. EA đồng thời quản lý một **Buy chain** và một **Sell chain**, mỗi chain có thể chứa tối đa 20 lệnh trải qua 4 zone với volume tăng dần theo ma trận Fibonacci.

---

## 2. Tham Số Cấu Hình

### 2.1 Cấu Hình Cơ Bản

| Parameter | Mặc Định | Kiểu | Mô Tả |
|---|---|---|---|
| `MagicNumber` | `1` | int | Số định danh duy nhất cho EA. Mỗi order trong chain được gán một magic number riêng biệt tính từ giá trị này |
| `MaxOrdersPerSide` | `20` | int | Số lượng lệnh tối đa cho mỗi chain (buy hoặc sell) |
| `BaseLot` | `0.01` | double | Khối lượng cơ bản; volume thực tế của từng lệnh = `BaseLot × ZoneVolume[zone][level]` |
| `ChainStopLoss` | `60000` | double | Ngưỡng thua lỗ tổng (currency). Nếu tổng PnL của cả 2 chain ≤ `-ChainStopLoss` thì đóng tất cả và **dừng vĩnh viễn** |
| `BuyOnly` | `false` | bool | Nếu `true`: chỉ mở Buy chain |
| `SellOnly` | `false` | bool | Nếu `true`: chỉ mở Sell chain |
| `TimeToOpenNewChain` | `15` | int | Số giây chờ sau khi đóng chain trước mới được mở chain mới (giây) |

### 2.2 Grid Step — Khoảng Cách Trong Zone (Points)

| Parameter | Mặc Định | Mô Tả |
|---|---|---|
| `Zone1_GridStep` | `10000` | Khoảng cách giữa các lệnh trong Zone 1 |
| `Zone2_GridStep` | `10000` | Khoảng cách giữa các lệnh trong Zone 2 |
| `Zone3_GridStep` | `10000` | Khoảng cách giữa các lệnh trong Zone 3 |
| `Zone4_GridStep` | `15000` | Khoảng cách giữa các lệnh trong Zone 4 |

### 2.3 Zone Transition Distance — Khoảng Cách Chuyển Zone (Points)

| Parameter | Mặc Định | Mô Tả |
|---|---|---|
| `Zone1_To_Zone2_Distance` | `30000` | Khoảng cách từ lệnh cuối Zone 1 (index 4) đến lệnh đầu Zone 2 (index 5) |
| `Zone2_To_Zone3_Distance` | `45000` | Khoảng cách từ lệnh cuối Zone 2 (index 9) đến lệnh đầu Zone 3 (index 10) |
| `Zone3_To_Zone4_Distance` | `35000` | Khoảng cách từ lệnh cuối Zone 3 (index 14) đến lệnh đầu Zone 4 (index 15) |

### 2.4 Take Profit

| Parameter | Mặc Định | Mô Tả |
|---|---|---|
| `TP_PerLot` | `500` | Mục tiêu lợi nhuận trên mỗi lot của chain (currency). TP target = `TP_PerLot × totalVolume` |

---

## 3. Ma Trận Volume

Volume của mỗi lệnh = `BaseLot × ZoneVolume[zone][level]`

| Zone | Level 0 | Level 1 | Level 2 | Level 3 | Level 4 |
|---|---|---|---|---|---|
| **Zone 1** (index 0–4) | ×1 | ×1 | ×2 | ×3 | ×5 |
| **Zone 2** (index 5–9) | ×1 | ×6 | ×7 | ×13 | ×20 |
| **Zone 3** (index 10–14) | ×1 | ×21 | ×22 | ×43 | ×65 |
| **Zone 4** (index 15–19) | ×1 | ×66 | ×67 | ×133 | ×200 |

**Ví dụ với `BaseLot = 0.01`:**

| Order Index | Zone | Level | Volume |
|---|---|---|---|
| 0 | 1 | 0 | 0.01 lot |
| 5 | 2 | 0 | 0.01 lot |
| 6 | 2 | 1 | 0.06 lot |
| 9 | 2 | 4 | 0.20 lot |
| 19 | 4 | 4 | 2.00 lot |

---

## 4. Hệ Thống Magic Number

Mỗi lệnh được gán một **magic number riêng biệt** để định danh:

```
Buy  chain: MagicNumber × 100 + orderIndex        (range: baseMagic + 0  … + 19)
Sell chain: MagicNumber × 100 + 50 + orderIndex   (range: baseMagic + 50 … + 69)
```

**Ví dụ với `MagicNumber = 1`:**

| Chain | Order Index | Magic Number |
|---|---|---|
| BUY | 0 | 100 |
| BUY | 5 | 105 |
| BUY | 19 | 119 |
| SELL | 0 | 150 |
| SELL | 19 | 169 |

Tất cả hàm lọc lệnh đều scan `POSITION_MAGIC` trong range `[minMagic, maxMagic]` của từng chain.

---

## 5. Thuật Toán Chi Tiết

### 5.1 Luồng Chính — `OnTick()`

```
OnTick()
│
├─ [Guard] BotStopped = true? → return
│
├─ SECTION 1: Chain StopLoss
│   totalPnL = buyProfit + sellProfit
│   if totalPnL ≤ -ChainStopLoss:
│       Đóng tất cả lệnh
│       BotStopped = true (dừng vĩnh viễn)
│       return
│
├─ SECTION 2: Take Profit
│   Buy TP:  if buyProfit  ≥ TP_PerLot × buyVolume  → CloseChainBySide(BUY)
│   Sell TP: if sellProfit ≥ TP_PerLot × sellVolume → CloseChainBySide(SELL)
│
├─ SECTION 3: Quản lý Buy Chain
│   CanOpenNewChain(BUY)?  → PlaceOrder(BUY, 0, ask)  → BuyChainEntryPrice = ask
│   BuyChainEntryPrice > 0?
│       lastIndex = GetLastOrderIndex(BUY)
│       nextGridPrice = lastOrderPrice - requiredDistance
│       ask ≤ nextGridPrice → PlaceOrder(BUY, lastIndex+1, ask)
│
└─ SECTION 4: Quản lý Sell Chain
    CanOpenNewChain(SELL)? → PlaceOrder(SELL, 0, bid) → SellChainEntryPrice = bid
    SellChainEntryPrice > 0?
        lastIndex = GetLastOrderIndex(SELL)
        nextGridPrice = lastOrderPrice + requiredDistance
        bid ≥ nextGridPrice → PlaceOrder(SELL, lastIndex+1, bid)
```

### 5.2 Điều Kiện Mở Chain Mới — `CanOpenNewChain()`

| Điều Kiện | Fails khi |
|---|---|
| Bot chưa bị dừng | `BotStopped = true` |
| Lọc BuyOnly/SellOnly | Vi phạm config |
| Chain chưa tồn tại | `BuyChainEntryPrice ≠ 0` (hoặc Sell) |
| Hết thời gian chờ | `TimeCurrent() - lastCloseTime < TimeToOpenNewChain` |

### 5.3 Tính Khoảng Cách Đặt Lệnh Tiếp Theo

```
lastLevel = orderIndex % 5

if lastLevel == 4:                    ← lệnh cuối zone
    requiredDistance = ZoneN_To_ZoneN+1_Distance
else:
    requiredDistance = ZoneN_GridStep  ← cùng zone

requiredPriceDistance = requiredDistance × SYMBOL_POINT

Buy:  nextGridPrice = lastOrderPrice - requiredPriceDistance
Sell: nextGridPrice = lastOrderPrice + requiredPriceDistance
```

### 5.4 Take Profit

```
TP Target = TP_PerLot × totalVolume (của chain)

Buy TP:  totalProfit ≥ TP Target → CloseChainBySide(BUY)
Sell TP: totalProfit ≥ TP Target → CloseChainBySide(SELL)
```

### 5.5 Chain StopLoss — Dừng Vĩnh Viễn

```
totalPnL = buyProfit + sellProfit

if totalPnL ≤ -ChainStopLoss:
    Đóng tất cả lệnh (BUY + SELL)
    BotStopped = true     ← EA ngừng hoạt động trong phiên hiện tại
                           ← Không có cơ chế tự khởi động lại
```

> ⚠️ Trong v1.00, `BotStopped` là **biến runtime** — nếu restart EA thì bot sẽ hoạt động trở lại.

---

## 6. Sơ Đồ Trạng Thái Chain

```
[Chờ]
  │  CanOpenNewChain() = true
  ▼
[Order 0 mở — Chain Active]
  │  Giá di chuyển đúng hướng
  ▼
[DCA thêm lệnh theo grid]
  │
  ├─ Profit ≥ TP Target → CloseChainBySide() → [Chờ TimeToOpenNewChain]
  │
  └─ TotalPnL ≤ -ChainStopLoss → CloseAll() → [BotStopped — dừng vĩnh viễn]
```

---

## 7. Hàm Quan Trọng

| Hàm | Mô Tả |
|---|---|
| `GetMagicNumber(side, index)` | Tính magic number cho từng lệnh trong chain |
| `GetChainStats(side)` | Lấy tổng volume, profit, số lệnh của chain — dùng magic range để lọc |
| `CloseChainBySide(side)` | Đóng toàn bộ lệnh của chain, reset `EntryPrice`, ghi `LastCloseTime` |
| `GetLastOrderIndex(side)` | Tìm `orderIndex` cao nhất đang mở trong chain |
| `GetLastOrderPrice(side, index)` | Lấy giá mở của lệnh tại index cụ thể qua exact magic match |
| `PlaceOrder(side, index, price)` | Đặt lệnh với magic riêng biệt, volume theo `ZoneVolume` |

---

## 8. Giới Hạn Của v1.00

- **Magic number phân tán:** Mỗi lệnh có magic riêng (40 magic numbers cho 2 chain × 20 lệnh), gây khó khăn khi phân tích từ công cụ bên ngoài
- **Dừng vĩnh viễn khi StopLoss:** Không có cơ chế tự restart theo thời gian
- **Không có session filter:** Bot chạy 24/7, không phân biệt giờ mở/đóng cửa thị trường
- **Không có EOD handling:** Bot có thể cầm lệnh qua đêm hoặc qua weekend

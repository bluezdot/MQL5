# GRID DCA v1.1 — Tài Liệu Thuật Toán

> **File:** `GRID_DCA_v1.1.mq5`  
> **Phát hành:** 2026-03-13  
> **Tác giả:** Tran Hoang Nam  
> **Nâng cấp từ:** v1.00

---

## 1. Tổng Quan

v1.1 giữ nguyên toàn bộ thuật toán grid DCA của v1.00 và bổ sung 3 tính năng lớn:

1. **Single Magic + Comment Encoding** — Tất cả lệnh dùng chung một magic number duy nhất; thông tin chain và slot được mã hóa vào comment lệnh. Giải quyết vấn đề phân tích lệnh từ công cụ bên ngoài (Grafana, v.v.) khi chạy nhiều EA trên cùng tài khoản.
2. **ChainStopLoss Restart** — Thay vì dừng vĩnh viễn, bot có thể tự khởi động lại sau một khoảng delay có thể cấu hình.
3. **EOD (End-of-Day) Handler** — Tự động xử lý lệnh trước khi thị trường đóng cửa, tránh cầm lệnh qua đêm.

---

## 2. So Sánh Với v1.00

### 2.1 Tham Số Cấu Hình

| Parameter | v1.00 | v1.1 | Ghi Chú |
|---|---|---|---|
| `MagicNumber` | `1` | `1` | Không đổi, nhưng vai trò thay đổi hoàn toàn (xem mục 4) |
| `CommentPrefix` | *(không có)* | `"GRID_DCA_v1.1"` | **MỚI** — prefix để build comment lệnh |
| `MaxOrdersPerSide` | `20` | `20` | Không đổi |
| `BaseLot` | `0.01` | `0.01` | Không đổi |
| `ChainStopLoss` | `60000` | `55000` | Thay đổi default |
| `ChainStopLossRestartDelay` | *(không có — dừng vĩnh viễn)* | `3600` | **MỚI** — giây chờ trước khi resume (0 = dừng vĩnh viễn) |
| `BuyOnly` | `false` | `false` | Không đổi |
| `SellOnly` | `false` | `false` | Không đổi |
| `TimeToOpenNewChain` | `15` | `15` | Không đổi |
| `Zone1_GridStep` | `10000` | `5000` | Thay đổi default |
| `Zone2_GridStep` | `10000` | `10000` | Không đổi |
| `Zone3_GridStep` | `10000` | `10000` | Không đổi |
| `Zone4_GridStep` | `15000` | `15000` | Không đổi |
| `Zone1_To_Zone2_Distance` | `30000` | `25000` | Thay đổi default |
| `Zone2_To_Zone3_Distance` | `45000` | `35000` | Thay đổi default |
| `Zone3_To_Zone4_Distance` | `35000` | `30000` | Thay đổi default |
| `TP_PerLot` | `500` | `500` | Không đổi |
| `EODWindowMinutes` | *(không có)* | `120` | **MỚI** — phút trước đóng cửa để kích hoạt EOD mode (0 = tắt) |
| `EODZoneThreshold` | *(không có)* | `8` | **MỚI** — chain dưới ngưỡng lệnh này sẽ bị đóng ngay trong EOD |
| `DelayAfterMarketOpen` | *(không có)* | `600` | **MỚI** — giây chờ sau khi market mở trước khi trade trở lại |

### 2.2 Global Variables

| Variable | v1.00 | v1.1 | Ghi Chú |
|---|---|---|---|
| `BuyChainEntryPrice` | ✅ | ✅ | Không đổi |
| `SellChainEntryPrice` | ✅ | ✅ | Không đổi |
| `LastBuyCloseTime` | ✅ | ✅ | Không đổi |
| `LastSellCloseTime` | ✅ | ✅ | Không đổi |
| `BotStopped` | ✅ | ❌ Xóa | Thay bằng `ChainStopLossTriggeredTime` |
| `ChainStopLossTriggeredTime` | ❌ | ✅ | **MỚI** — timestamp thay vì bool, hỗ trợ delay restart |
| `EODWindowActive` | ❌ | ✅ | **MỚI** — đang trong cửa sổ EOD |
| `WaitingForMarketOpen` | ❌ | ✅ | **MỚI** — đang chờ market mở phiên kế tiếp |
| `MarketOpenTime` | ❌ | ✅ | **MỚI** — timestamp lúc market được phát hiện mở |

### 2.3 Hàm

| Hàm | v1.00 | v1.1 | Ghi Chú |
|---|---|---|---|
| `GetMagicNumber(side, index)` | ✅ | ❌ Xóa | Thay bằng comment encoding |
| `GetOrderComment(side, index)` | ❌ | ✅ | **MỚI** — build comment `{prefix}_B_05` |
| `ParseOrderComment(comment, &side, &index)` | ❌ | ✅ | **MỚI** — parse comment để lấy side và index |
| `IsMarketOpen()` | ❌ | ✅ | **MỚI** — kiểm tra phiên giao dịch đang mở |
| `GetSessionCloseTime()` | ❌ | ✅ | **MỚI** — lấy giờ đóng cửa phiên hiện tại |
| `HandleEODChains()` | ❌ | ✅ | **MỚI** — xử lý chain trong EOD window |
| `GetChainStats(side)` | ✅ | ✅ | Cập nhật: lọc bằng comment thay vì magic range |
| `GetOrderCount(side)` | ✅ | ✅ | Cập nhật: lọc bằng comment thay vì magic range |
| `CloseChainBySide(side)` | ✅ | ✅ | Cập nhật: lọc bằng comment thay vì magic range |
| `GetLastOrderIndex(side)` | ✅ | ✅ | Cập nhật: parse index từ comment thay vì tính từ magic |
| `GetLastOrderPrice(side, index)` | ✅ | ✅ | Cập nhật: match bằng comment thay vì exact magic |
| `PlaceOrder(side, index, price)` | ✅ | ✅ | Cập nhật: dùng single magic + comment |
| `CanOpenNewChain(side)` | ✅ | ✅ | Cập nhật: thêm EOD guard |

---

## 3. Tham Số Cấu Hình Đầy Đủ

### 3.1 Cấu Hình Cơ Bản

| Parameter | Mặc Định | Kiểu | Mô Tả |
|---|---|---|---|
| `MagicNumber` | `1` | int | Số định danh duy nhất cho **toàn bộ EA**. Tất cả lệnh đều dùng chung giá trị này |
| `CommentPrefix` | `"GRID_DCA_v1.1"` | string | Prefix để build comment lệnh. Phải unique giữa các EA trên cùng tài khoản |
| `MaxOrdersPerSide` | `20` | int | Số lệnh tối đa mỗi chain |
| `BaseLot` | `0.01` | double | Khối lượng cơ bản |
| `ChainStopLoss` | `55000` | double | Ngưỡng thua lỗ tổng (currency) |
| `ChainStopLossRestartDelay` | `3600` | int | Giây chờ sau khi StopLoss trước khi trade trở lại. `0` = dừng vĩnh viễn |
| `BuyOnly` | `false` | bool | Chỉ mở Buy chain |
| `SellOnly` | `false` | bool | Chỉ mở Sell chain |
| `TimeToOpenNewChain` | `15` | int | Giây chờ sau khi đóng chain trước |

### 3.2 Grid Steps & Zone Transitions

| Parameter | Mặc Định | Mô Tả |
|---|---|---|
| `Zone1_GridStep` | `5000` | Khoảng cách giữa các lệnh trong Zone 1 (points) |
| `Zone2_GridStep` | `10000` | Khoảng cách giữa các lệnh trong Zone 2 (points) |
| `Zone3_GridStep` | `10000` | Khoảng cách giữa các lệnh trong Zone 3 (points) |
| `Zone4_GridStep` | `15000` | Khoảng cách giữa các lệnh trong Zone 4 (points) |
| `Zone1_To_Zone2_Distance` | `25000` | Khoảng cách chuyển zone 1→2 (points) |
| `Zone2_To_Zone3_Distance` | `35000` | Khoảng cách chuyển zone 2→3 (points) |
| `Zone3_To_Zone4_Distance` | `30000` | Khoảng cách chuyển zone 3→4 (points) |
| `TP_PerLot` | `500` | Mục tiêu lợi nhuận trên mỗi lot (currency) |

### 3.3 EOD Settings

| Parameter | Mặc Định | Mô Tả |
|---|---|---|
| `EODWindowMinutes` | `120` | Số phút trước khi thị trường đóng cửa để kích hoạt EOD mode. `0` = tắt tính năng |
| `EODZoneThreshold` | `8` | Chain có **ít hơn** ngưỡng này sẽ bị đóng ngay; từ ngưỡng trở lên sẽ chờ TP tự đóng |
| `DelayAfterMarketOpen` | `600` | Giây chờ sau khi phát hiện market mở trước khi trade trở lại. `0` = vào lệnh ngay |

---

## 4. Hệ Thống Comment Encoding (Thay Thế Magic Number)

### 4.1 Format Comment

```
{CommentPrefix}_{Side}_{Index:02d}

Ví dụ (CommentPrefix = "GRID_DCA_v1.1"):
  GRID_DCA_v1.1_B_00   ← Buy chain, slot 0
  GRID_DCA_v1.1_B_05   ← Buy chain, slot 5
  GRID_DCA_v1.1_S_00   ← Sell chain, slot 0
  GRID_DCA_v1.1_S_19   ← Sell chain, slot 19
```

### 4.2 Nhận Diện Lệnh

Tất cả hàm scan lệnh đều lọc theo **2 điều kiện đồng thời**:

```
POSITION_MAGIC == MagicNumber        ← định danh EA
ParseOrderComment(comment) == side   ← định danh chain + slot
```

### 4.3 Lợi Ích Khi Dùng Nhiều EA

| Tình huống | v1.00 | v1.1 |
|---|---|---|
| Lọc "tất cả lệnh của EA này" | Không được (40 magic khác nhau) | Được: `WHERE magic = 12345` |
| Lọc "lệnh Buy chain của EA này" | Không được | Được: `WHERE comment LIKE 'GRID_DCA_v1.1_B_%'` |
| 2 EA trên cùng tài khoản | Dễ trùng magic range | Không trùng nếu `MagicNumber` và `CommentPrefix` khác nhau |

---

## 5. Thuật Toán Chi Tiết

### 5.1 Luồng Chính — `OnTick()`

```
OnTick()
│
├─ [Guard] ChainStopLossTriggeredTime > 0?
│   ├─ RestartDelay = 0 → return (dừng vĩnh viễn)
│   ├─ Elapsed < RestartDelay → return (đang cooldown)
│   └─ Elapsed ≥ RestartDelay → ChainStopLossTriggeredTime = 0, resume
│
├─ SECTION 0: EOD / Market Session Check
│   WaitingForMarketOpen = true?
│       IsMarketOpen() = false → return
│       IsMarketOpen() = true, MarketOpenTime = 0? → ghi MarketOpenTime
│       Elapsed < DelayAfterMarketOpen → return
│       Elapsed ≥ DelayAfterMarketOpen → reset tất cả EOD flags, resume
│
├─ SECTION 1: Chain StopLoss
│   totalPnL = buyProfit + sellProfit
│   totalPnL ≤ -ChainStopLoss:
│       Đóng tất cả lệnh
│       ChainStopLossTriggeredTime = TimeCurrent()
│       return
│
├─ SECTION 2: Take Profit
│   Buy TP:  buyProfit  ≥ TP_PerLot × buyVolume  → CloseChainBySide(BUY)
│   Sell TP: sellProfit ≥ TP_PerLot × sellVolume → CloseChainBySide(SELL)
│
├─ SECTION 2.5: EOD Window Handling
│   EODWindowActive = false AND EODWindowMinutes > 0?
│       GetSessionCloseTime() → timeToClose = closeTime - TimeCurrent()
│       0 < timeToClose ≤ EODWindowMinutes×60 → EODWindowActive = true
│   EODWindowActive = true → HandleEODChains()
│
├─ SECTION 3: Quản lý Buy Chain
│   CanOpenNewChain(BUY)? → PlaceOrder(BUY, 0, ask) → BuyChainEntryPrice = ask
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

### 5.2 EOD Window Handler — `HandleEODChains()`

```
HandleEODChains():

  BUY chain tồn tại AND orderCount < EODZoneThreshold?
      → Force close BUY chain ngay lập tức

  SELL chain tồn tại AND orderCount < EODZoneThreshold?
      → Force close SELL chain ngay lập tức

  Cả 2 chain đã đóng (EntryPrice = 0) AND WaitingForMarketOpen = false?
      → WaitingForMarketOpen = true
      (Chain ≥ EODZoneThreshold vẫn chạy bình thường, chờ TP Section 2 đóng)
      (WaitingForMarketOpen sẽ được set = true sau khi chain đó đóng ở lần gọi tiếp theo)
```

### 5.3 Market Reopen Delay — `Section 0`

```
WaitingForMarketOpen = true:
    IsMarketOpen() = false:
        MarketOpenTime = 0
        return (chờ)
    IsMarketOpen() = true:
        MarketOpenTime == 0? → ghi MarketOpenTime = TimeCurrent()
        TimeCurrent() - MarketOpenTime < DelayAfterMarketOpen → return (chờ delay)
        DelayAfterMarketOpen đã hết:
            EODWindowActive = false
            WaitingForMarketOpen = false
            MarketOpenTime = 0
            Resume trading
```

### 5.4 ChainStopLoss Restart (Khác v1.00)

| | v1.00 | v1.1 |
|---|---|---|
| Cơ chế | `BotStopped = true` (bool) | `ChainStopLossTriggeredTime = TimeCurrent()` |
| Restart | Không — dừng vĩnh viễn trong phiên | Tự động sau `ChainStopLossRestartDelay` giây |
| Tắt tính năng restart | Không có option | `ChainStopLossRestartDelay = 0` |

### 5.5 `CanOpenNewChain()` — Guards Thêm Mới

```
v1.00:
  BotStopped → false
  BuyOnly/SellOnly → false
  Chain đã tồn tại → false
  TimeToOpenNewChain chưa hết → false

v1.1 (thêm ở đầu):
  EODWindowActive = true → false   ← KHÔNG mở chain mới trong EOD window
  WaitingForMarketOpen = true → false   ← KHÔNG mở chain mới khi chờ market
  ... (các guard cũ giữ nguyên)
```

> **Lưu ý:** DCA thêm lệnh vào chain đang tồn tại **vẫn hoạt động** trong EOD window vì logic đó nằm ngoài `CanOpenNewChain()`.

---

## 6. Sơ Đồ Trạng Thái EOD

```
[Trading bình thường]
        │
        │ timeToClose ≤ EODWindowMinutes × 60
        ▼
[EODWindowActive = true]
        │
        ├──── Chain < EODZoneThreshold lệnh ──→ Force Close ngay
        │
        └──── Chain ≥ EODZoneThreshold lệnh ──→ Chờ TP (Section 2 vẫn chạy)
                                                       │
                          Cả 2 chain đã đóng ◄─────────┘
                                    │
                                    ▼
                      [WaitingForMarketOpen = true]
                                    │
                          IsMarketOpen() = true
                                    │
                          Ghi MarketOpenTime
                                    │
                          Đợi DelayAfterMarketOpen giây
                                    │
                                    ▼
                         [Reset EOD flags — Trading bình thường]
```

---

## 7. Hàm Quan Trọng

| Hàm | Mô Tả |
|---|---|
| `GetOrderComment(side, index)` | Build comment: `"{prefix}_B_05"`. Dùng `CommentPrefix` động |
| `ParseOrderComment(comment, &side, &index)` | Parse comment, trả về `true` nếu hợp lệ. Tính `prefixLen` động |
| `IsMarketOpen()` | Dùng `SymbolInfoSessionTrade()` kiểm tra phiên hôm nay còn active không |
| `GetSessionCloseTime()` | Trả về timestamp tuyệt đối của giờ đóng cửa phiên hiện tại (0 nếu không tìm thấy) |
| `HandleEODChains()` | Force close chain nhỏ; set `WaitingForMarketOpen` khi tất cả chain đã đóng |
| `GetChainStats(side)` | Lọc bằng `magic == MagicNumber` + `ParseOrderComment()` thay vì magic range |
| `CloseChainBySide(side)` | Lọc bằng comment, đóng toàn bộ lệnh của chain |
| `GetLastOrderIndex(side)` | Parse `orderIndex` từ comment thay vì tính `posMagic - minMagic` |
| `GetLastOrderPrice(side, index)` | Match bằng `comment == targetComment` thay vì exact magic |
| `PlaceOrder(side, index, price)` | Dùng `MagicNumber` duy nhất; comment = `GetOrderComment()` |

---

## 8. Ma Trận Volume (Không Đổi Từ v1.00)

Volume của mỗi lệnh = `BaseLot × ZoneVolume[zone][level]`

| Zone | Level 0 | Level 1 | Level 2 | Level 3 | Level 4 |
|---|---|---|---|---|---|
| **Zone 1** (index 0–4) | ×1 | ×1 | ×2 | ×3 | ×5 |
| **Zone 2** (index 5–9) | ×1 | ×6 | ×7 | ×13 | ×20 |
| **Zone 3** (index 10–14) | ×1 | ×21 | ×22 | ×43 | ×65 |
| **Zone 4** (index 15–19) | ×1 | ×66 | ×67 | ×133 | ×200 |

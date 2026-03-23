# GOLD ORB v1.00 — Tài Liệu Thuật Toán

**File:** `ORB_v1.00.mq5`
**Phiên bản:** 1.00
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

Open Range Breakout (ORB) xác định vùng high/low (Range) được tạo ra từ nến mở cửa thị trường (Initial Range Candle), sau đó chờ giá phá vỡ vùng đó để vào lệnh theo hướng breakout.
Đây là phiên bản nền tảng sơ khởi nhất với mức cắt lỗ (SL) và chốt lời (TP) được fix cứng cố định bằng điểm (points) đếm từ vị trí vào lệnh. 

---

## 2. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpMagicNumber` | 16 | Magic number |
| `InpSessionStartHour` | 21 | Giờ bắt đầu tính là session mới của ngày |
| `InpMarketOpenHour` | 22 | Giờ mở cửa thị trường thực tế (UTC). Cột mốc chuẩn nến để lấy range |
| `InpMinComposition` | 3 | Số nến tổi thiểu phải nằm gọn trong cấu trúc range trước khi Confirm để trade |

### ==== TP/SL Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpSLPoints` | 4000 | Stop Loss tính bằng điểm (points) từ Entry. `0` = tắt |
| `InpTPPoints` | 12000 | Take Profit tính bằng điểm từ Entry. `0` = tắt |

### ==== Trailing Stop ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpUseTrail` | false | Bật/tắt trailing dời SL bám theo giá |
| `InpTrailPoints` | 1500 | Khoảng cách điểm bắt đầu kích hoạt dời lệnh |
| `InpTrailStep` | 100 | Bước trôi dời tối thiểu trên mỗi nhịp |

### ==== Risk Management ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpFixedLot` | 0.1 | Lot đánh cố định (sử dụng khi % rủi ro bằng không) |
| `InpRiskPerTradePercent` | 1 | % số dư để chịu rủi ro tự động chia Lot dựa trên `InpSLPoints` |

### ==== Day Filter ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpMonday` đến `InpFriday` | true | Bật/tắt hoạt động theo ngày trong tuần |

---

## 3. Chi tiết thuật toán

### 3.1. Sơ đồ vòng đời quản trị luồng (State Machine)
Thuật toán quản lý trạng thái tự động qua 4 vòng đời sau mỗi ngày.
```text
           [IDLE]
              |
              | → Bar chứa `InpMarketOpenHour` UTC hoàn thành việc đóng
              |   `InpMinComposition`=0 → Nhảy sang FINAL
              |   `InpMinComposition`>0 → Đi qua FORMING để theo dõi composition
              ↓
          [FORMING]
              |
              | → `composition >= InpMinComposition`
              ↓
           [FINAL]  ←──── CheckBreakout() chạy mỗi tick liên tục
              |
              | → buyDone && sellDone
              ↓
          [TRADED]
              |
              | → Trải qua mốc Session start mới (`InpSessionStartHour` UTC) làm mới chu kỳ
              ↓
           [IDLE]  (Cài đặt lại toàn bộ State về không)
```

### 3.2. Điều kiện Vào/Ra Lệnh
- **Xác định Range:** Trục `targetBarIdx` tính từ độ lệch giờ mở cửa và giờ thay session để thu thập chính xác cây nến. Cây nến ban đầu xác lập bộ khung `high` và `low` của chiến lược.
- **Forming:** Các cây nến con tiếp theo nằm trọn trong range đó sẽ được +1 điểm (composition factor). Nếu nến vượt ra ngoài phạm vi biên range, nó tự động mở rộng vạch range hiện hành và không tính đếm điểm nữa. Phải đủ mức `InpMinComposition` mới đổi sang trạng thái FINAL.
- **Trigger:** Tiến hành check thông tin Tick-by-tick tại FINAL loop.
  - Vượt `range.high` -> BUY.
  - Vượt `range.low` -> SELL.

### 3.3. Tính toán SL/TP
Ở version đầu tiên, hệ thống chặn rủi ro không nương theo kỹ thuật range mà theo hệ điểm fix cứng Points (VD: 4000 points = 40 giá vàng XAUUSD) cộng hoặc trừ rập khuôn vào giá vào cửa (Entry Price Bid/Ask).

---

## 4. Mô tả kỹ thuật

Các biến trạng thái quản trị State: `ORB_IDLE`, `ORB_FORMING`, `ORB_FINAL`, `ORB_TRADED`.  
Cấu trúc `ORB_RANGE` Struct chứa:  
- `initCandleTime`, `sessionStart`, `high`, `low`, `composition`, `buyDone`, `sellDone`.
Hệ vòng lặp `OnTick()` nối tiếp qua các step:
1. `GetSessionStart` tìm ra mốc thời gian UTC đầu ngày tự động với bất kì thông số UTC offset nào từ Broker mà không bị sai lệch.
2. `RunStateMachine()` vận hành bộ chia State nếu phát hiện Event cây nến kết thúc (đóng nến Index=1).
3. `CheckBreakout()` để kiểm tra giá vượt ra ngoài range, khi đó bắt đầu Buy/Sell.

---

## 5. Ví dụ cấu hình khuyến nghị

**Ví dụ Giao dịch Vàng khung M15 (UTC+3 Broker time):**
- Điểm Session bắt đầu là 21:00 UTC (Tương đương 00:00 midnight máy chủ). Canh giờ market Open lúc 22:00 UTC.
- `InpMinComposition` = 3 cung cấp 3 x 15m = 45 phút đầu gom thanh khoản giá làm cữ đo lường.
- Stoploss tĩnh được chốt `InpSLPoints = 5000` (~50 pip vàng mộc bảo vệ margin). 

---

## 6. Lưu ý rủi ro & Backtest

> [!WARNING]
> Thuật toán thực hiện Buy/Sell ngay khoảnh khắc giá vừa phá range, rủi ro của phiên bản này là **Fake Breakout** - Thị trường có thể quét râu ảo hai chiều. Ngoài ra SL dựa trên fix points phụ thuộc may rủi khá nhiều vào những giai đoạn có biên độ co dãn (Volatility) không lường trước.

- **Backtest Option:** Bắt buộc **Every Tick based on real ticks** chạy full tick giá lịch sử, tuyệt đối không dùng Open Prices.

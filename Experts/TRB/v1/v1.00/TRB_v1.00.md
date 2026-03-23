# Time Range Breakout (TRB) v1.00 — Tài Liệu Thuật Toán

**File:** `TRB_v1.00.mq5`
**Phiên bản:** 1.00
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

TRB xác định vùng high/low của giá trong một khoảng thời gian cố định tự định nghĩa, sau đó chờ giá Breakout khỏi vùng đó để vào lệnh.
Khác với ORB (dùng nến mở cửa thị trường làm range), TRB cho phép tự do lựa chọn bất kỳ khung giờ nào trong ngày (ví dụ: phiên Á, phiên London, v.v.). Breakout chỉ được xác nhận khi nến thực sự đóng cửa (bar close) nằm ngoài vùng range.

---

## 2. Tham số cấu hình - Input Parameters

### ==== General Inputs ====
| Input Variable | Mặc Định | Mô tả |
|---|---|---|
| `InpLotSize` | 0.01 | Khối lượng vào lệnh cố định |
| `InpMagicNumber` | 20 | Magic number để phân biệt EA này trên cùng account |

### ==== SL / TP Inputs ====
| Input Variable | Mặc Định | Mô tả |
|---|---|---|
| `InpSLPct` | 100 | Stop Loss tính theo % của chiều rộng range (0 = tắt) |
| `InpTPPct` | 100 | Take Profit tính theo % của chiều rộng range (0 = tắt) |

### ==== Time Range Inputs ====
| Input Variable | Mặc Định | Mô tả |
|---|---|---|
| `InpRangeStartHour` | 22 | Giờ bắt đầu tính range (UTC, 0-23) |
| `InpRangeStartMinute` | 0 | Phút bắt đầu tính range (0-59) |
| `InpRangeEndHour` | 9 | Giờ kết thúc tính range (UTC), hỗ trợ vắt qua rạng sáng ngày tiếp theo |
| `InpRangeEndMinute` | 0 | Phút kết thúc tính range (0-59) |
| `InpRangeCloseHour` | 20 | Giờ đóng tất cả các lệnh (UTC). Đặt là -1 để tắt tính năng đóng lệnh theo giờ |
| `InpRangeCloseMinute` | 0 | Phút đóng lệnh |
| `InpBreakoutMode` | `BREAKOUT_MODE_HIGH_LOW` | Chế độ giao dịch breakout |

**Tham số tuỳ chọn cho InpBreakoutMode:**
- `BREAKOUT_MODE_HIGH_LOW`: Vào cả hai chiều (phá high thì BUY, phá low thì SELL)
- `BREAKOUT_MODE_HIGH`: Chỉ BUY khi phá high
- `BREAKOUT_MODE_LOW`: Chỉ SELL khi phá low
- `BREAKOUT_MODE_ONE_TRADE_PER_RANGE`: Chỉ vào 1 lệnh đầu tiên hợp lệ trong range (BUY hoặc SELL), khóa chiều còn lại

### ==== Day Filter Inputs ====
| Input Variable | Mặc Định | Mô tả |
|---|---|---|
| `InpMonday` đến `InpFriday` | true | Bật/tắt giao dịch ở các ngày tương ứng trong tuần |

---

## 3. Chi tiết thuật toán

### 3.1. Sơ đồ vòng đời của một Range

```text
[InpRangeStartHour:Min]           [InpRangeEndHour:Min]              [InpRangeCloseHour:Min]
      │                              │                                  │
      ▼                              ▼                                  ▼
  ┌───────────── FORMING ───────────┐───────── BREAKOUT ZONE ──────────┐─── CLOSE ───
  │  Ghi nhận high/low tick-by-tick │  CheckBreakouts() khi đóng nến   │ Đóng lệnh
  └─────────────────────────────────┘──────────────────────────────────┘
```

### 3.2. Điều kiện Vào/Ra Lệnh
- **Chuẩn bị (Forming):** Từ lúc `start_time` đến `end_time`, high/low của range liên tục được cập nhật tick-by-tick từ giá `ask` (đối với high) và `bid` (đối với low). Nếu EA khởi động giữa chừng khoảng thời gian này, dữ liệu lịch sử bar (`CopyRates`) sẽ được dùng để tái tạo lại range.
- **Vào lệnh (Entry):** Kể từ sau `end_time`, kiểm tra mức giá đóng nến của nến mới kết thúc (Bar Close - `closePrice`):
  - Kích hoạt **BUY** nếu `closePrice > range.high`. Không FOMO nhồi lệnh (kiểm tra break high flag).
  - Kích hoạt **SELL** nếu `closePrice < range.low`.
- **Ra lệnh (Close):** Tại thời điểm `range.close_time`, nếu `InpRangeCloseHour >= 0` thì toàn bộ vị thế EA đang kiểm soát sẽ bị đóng khẩn cấp toàn bộ. Range sẽ reset sau khi qua điểm close_time.

### 3.3. Tính toán SL/TP
Công thức xác định độ rộng range: `range_width = range.high - range.low`.

- **Đối với lệnh BUY:**
  - `SL = bid - (range_width * InpSLPct%)`
  - `TP = bid + (range_width * InpTPPct%)`
- **Đối với lệnh SELL:**
  - `SL = ask + (range_width * InpSLPct%)`
  - `TP = ask - (range_width * InpTPPct%)`

---

## 4. Mô tả kỹ thuật

Dữ liệu trạng thái Range được lưu theo struct `RANGE_STRUCT`:
- `start_time`, `end_time`, `close_time` (datetime)
- `high`, `low` (double)
- Các cờ flag entry: `f_entry`, `f_high_breakout`, `f_low_breakout` (bool)

Luồng xử lý hàm `OnTick()` chạy mỗi tick:
1. Thu thập dữ liệu `lastTick` và cập nhật các mức đỉnh/đáy (`Ask` cho high, `Bid` cho low) nếu trong khung giờ Forming.
2. Kiểm tra đóng lệnh khi đến giờ `close_time`. Tính lại chu kỳ Range (`CalculateRange`) nếu qua chu kỳ khác.
3. Xác định nến vừa đóng bằng việc so sánh `iTime()` hiện tại với `g_lastBar`. Lấy `iClose()` đưa vào `CheckBreakouts()` để entry theo đúng điều kiện không dính chông râu nến ảo.
Trực quan: EA vẽ các khung giờ bằng line màu sắc và chấm dot line để dự phóng vùng kháng định trên chart bằng `DrawObjects()`.

---

## 5. Ví dụ cấu hình khuyến nghị

**Ví dụ Giao Dịch Phiên London (1 giờ đầu) bằng UTC:**
- `InpRangeStartHour` = 7, `InpRangeStartMinute` = 0
- `InpRangeEndHour` = 8, `InpRangeEndMinute` = 0
- `InpRangeCloseHour` = 17, `InpRangeCloseMinute` = 0
- `InpBreakoutMode` = `BREAKOUT_MODE_ONE_TRADE_PER_RANGE`
*(Logic: Thống kê và lưu lại vùng range cho phiên từ 07:00 đến 08:00 (giờ Server UTC). Chỉ cho phép đánh duy nhất 1 lệnh phá vỡ thành công vùng này sau 08:00, và dọn dẹp lệnh đóng ở 17:00)*

---

## 6. Lưu ý rủi ro & Backtest

> [!WARNING]
> Breakout là một chiến lược bẫy giá nhạy cảm, có thể phải dính SL liên tục vào ngày có những cây nến pinbar quét 2 đầu, hoặc khi tick spike nhanh nhưng nến vẫn đóng ngoài (nhờ bản mới update closePrice nên rủi ro này đã được hạn chế).

- **Backtest Option:** Bắt buộc dùng chế độ `Every Tick` hoặc `Every tick based on real ticks` để đảm bảo EA tính toán biên độ đỉnh/đáy tick-by-tick một cách chân thực nhất trong vùng tạo range.

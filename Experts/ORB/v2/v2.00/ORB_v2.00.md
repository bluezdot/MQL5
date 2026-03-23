# GOLD ORB v2.00 — Tài Liệu Thuật Toán

**File:** `ORB_v2.00.mq5`
**Phiên bản:** 2.00
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

Trong phiên bản 2.00 làm lại hoàn toàn cơ chế ra lệnh của dòng bot Open Range Breakout (ORB). Bỏ đi Stop Loss được fixed cứng điểm số như v1 vốn mang nhiều yếu tố đỏ đen, v2 sử dụng Price Action dùng kích thước Range để làm quản trị RR. EA sẽ bắt lấy đỉnh và đáy của range làm mốc chặn lỗ (SL) để tôn trọng tuyệt đối kháng cự và hỗ trợ. Đồng thời nó được tích hợp tính năng dọn rác vị thế khi kề cận hết chu kỳ ngày.

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết v2.00 nâng cấp so với v1.00  |
|-----------|-------------------------------------|
| SL | Cắt lỗ kỹ thuật dựa trên biên đối diện của Range (`range.low` khi Buy / `range.high` khi Sell) |
| TP | Tùy chọn qua biến Enum: Hoặc theo tỷ trọng Risk:Reward `TP_BY_RR` hoặc theo Point |
| Lot size | Lot tính dựa theo % risk. Đoạn giá nào Range to -> lot bé, Range bé -> lot to |
| Time Clean up | Cho phép sạch lệnh vào cuối session (`InpCloseAtSessionEnd`). Chống treo tài khoản qua đêm tốn phí, gap nến ngày mới và không còn trong xu hướng. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpMagicNumber` | 17 | Magic number |
| `InpSessionStartHour` | 21 | Giờ chuyển giao ngày mới session (đầu vào UTC time) |
| `InpMarketOpenHour` | 22 | Giờ market bắt đầu mở cửa |
| `InpMinComposition` | 0 | Số nến để xác định Range. Mặc định `0` sẽ lấy nến đầu tiên xác định Range luôn. |

### ==== TP Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpTPMode` | `TP_BY_RR` | Mode TP theo RR hoặc Point |
| `InpRR` | 1.5 | Tỉ lệ RR so với SL. Active khi `InpTPMode == TP_BY_RR` |
| `InpTPPoints` | 12000 | TP theo Point. Active khi `InpTPMode == TP_BY_POINTS` |

### ==== Trailing Stop ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpUseTrail` | false | Bật/tắt chế độ Trailing SL |
| `InpTrailPoints` | 1500 | Số point để bắt đầu Trailing SL |
| `InpTrailStep` | 100 | Số point để di dời SL mỗi lần kích hoạt |

### ==== Risk Management ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpFixedLot` | 0.1 | Base lot |
| `InpRiskPerTradePercent` | 2 | % rủi ro chấp nhận mỗi lệnh để tính ra lot size |
| `InpCloseAtSessionEnd` | true | Bật/tắt chế độ dọn lệnh khi hết phiên |
| `InpCloseBeforeMinutes` | 60 | Số phút trước khi hết phiên để bắt đầu dọn lệnh |

### ==== Day Filter ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpMonday` đến `InpFriday` | true | Bật/tắt hoạt động theo ngày trong tuần |

---

## 4. Chi tiết thuật toán

Thực thi dựa vào State Machine [IDLE] -> [FORMING] -> [FINAL] -> [TRADED], điểm khác biệt cốt lõi ở Trigger Check-Breakout và Lot Equation System.

### 4.1. Điều kiện Vào/Ra Lệnh 

Đợi `state == ORB_FINAL`:
- Khi Ask chạm kháng cự trên (`range.high`) -> BUY, SL tại `range.low`.
- Khi Bid chạm hỗ trợ dưới (`range.low`) -> SELL, SL tại `range.high`.

### 4.2. Tính toán Money Management
Công thức:
`slCost = slDistance / tickSize * tickValue`
`lots = riskAmount / slCost`

---

## 5. Mô tả kỹ thuật

---

## 6. Ví dụ cấu hình khuyến nghị

`InpMinComposition` = 0. Xác định Range dựa vào nến đầu tiên. Dùng đối diện Range làm giá SL.
hoặc
`InpMinComposition` = 3. Xác định Range dựa vào 3 nến đầu tiên. Dùng đối diện Range làm giá SL.

---

## 7. Lưu ý rủi ro & Backtest

> [!WARNING]
> Rủi ro dính lỗ liên tục nếu không có biến động mạnh, thị trường sideway không rõ xu hướng sau khi mở cửa

- **Backtest Option:** Bắt buộc duy nhất **Every Tick based on real ticks**.

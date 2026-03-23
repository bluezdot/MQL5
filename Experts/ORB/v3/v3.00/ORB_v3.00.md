# GOLD ORB v3.00 — Tài Liệu Thuật Toán

**File:** `ORB_v3.00.mq5`
**Phiên bản:** 3.00
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

GOLD ORB v3.00 kế thừa toàn bộ cơ chế thuật toán từ v2.01 (Breakout Buffer chống false break, Auto Break-Even bảo vệ vốn). Điểm khác biệt duy nhất nằm ở **giá trị mặc định** được tinh chỉnh hướng tới phong cách phòng thủ, phù hợp triển khai Production Live cho các quỹ Prop Firm — ưu tiên winrate cao và bảo toàn vốn thay vì RR lớn.

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết v3.00 so với v2.01 |
|-----------|-------------------------------|
| Default `InpMinComposition` | Tăng từ `0` (single-bar) lên `3`. Bắt buộc range phải được xác nhận qua ít nhất 3 nến sideway, tăng độ tin cậy của vùng tích lũy. |
| Default `InpRR` | Giảm từ `1.5` xuống `1.0`. Chốt lời sớm hơn, tăng winrate, phù hợp chiến lược bảo toàn vốn. |
| Default `InpCloseAtSessionEnd` | Luôn bật (`true`). Đóng toàn bộ vị thế trước khi hết phiên để tránh gap qua đêm. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpMagicNumber` | 18 | Magic number |
| `InpSessionStartHour` | 21 | Giờ bắt đầu session mới (UTC) |
| `InpMarketOpenHour` | 22 | Giờ mở cửa thị trường (UTC), dùng để xác định nến target lấy Range |
| `InpMinComposition` | 3 | Số nến tối thiểu nằm gọn trong Range để xác nhận vùng tích lũy. Mặc định `3` thay vì `0` của v2.x |

### ==== Entry Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpBreakoutBuffer` | 150 | Buffer points chống false break (kế thừa từ v2.01) |

### ==== TP Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpTPMode` | `TP_BY_RR` | Mode chốt lời: theo RR hoặc Point |
| `InpRR` | 1.0 | Tỉ lệ RR. Active khi `InpTPMode == TP_BY_RR`. Mặc định `1.0` thay vì `1.5` của v2.x |
| `InpTPPoints` | 12000 | TP theo Point. Active khi `InpTPMode == TP_BY_POINTS` |

### ==== BE & Trailing Stop ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpUseAutoBE` | false | Bật/tắt chế độ dời SL về hòa vốn |
| `InpAutoBETrigger` | 250 | Số Point lợi nhuận cần đạt để kích hoạt dời SL về hòa vốn |
| `InpAutoBEOffset` | 20 | Số Point độn thêm để bù phí giao dịch khi dời SL về hòa vốn |
| `InpUseTrail` | false | Bật/tắt Trailing SL |
| `InpTrailPoints` | 1500 | Số point để bắt đầu Trailing SL |
| `InpTrailStep` | 100 | Số point di dời SL mỗi lần kích hoạt |

### ==== Risk Management ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpFixedLot` | 0.1 | Base lot |
| `InpRiskPerTradePercent` | 2 | % rủi ro chấp nhận mỗi lệnh để tính ra lot size |
| `InpCloseAtSessionEnd` | true | Bật/tắt dọn lệnh khi hết phiên (mặc định luôn bật) |
| `InpCloseBeforeMinutes` | 60 | Số phút trước khi hết phiên để bắt đầu dọn lệnh |

### ==== Day Filter ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpMonday` đến `InpFriday` | true | Bật/tắt hoạt động theo ngày trong tuần |

---

## 4. Chi tiết thuật toán

Cơ chế thuật toán giống hoàn toàn v2.01 — State Machine [IDLE] -> [FORMING] -> [FINAL] -> [TRADED].

### 4.1. Điều kiện Vào Lệnh

Quá trình Forming (khác biệt chính so với v2.x do default `InpMinComposition = 3`):
- Nến nằm gọn trong Range (High/Low không vượt biên) → `composition++`.
- Nến vượt ra ngoài Range → Range được mở rộng, `composition` không tăng.
- Khi `composition >= InpMinComposition` (= 3) → chuyển sang `ORB_FINAL`, sẵn sàng đợi breakout.

Trigger breakout (kế thừa v2.01):
- `buyTriggerPrice  = range.high + InpBreakoutBuffer * _Point`
- `sellTriggerPrice = range.low  - InpBreakoutBuffer * _Point`
- Ask vượt `buyTriggerPrice` → BUY, SL tại `range.low`.
- Bid vượt `sellTriggerPrice` → SELL, SL tại `range.high`.

### 4.2. Dọn lệnh cuối phiên
`InpCloseAtSessionEnd` mặc định bật. EA đóng tất cả vị thế vào `sessionEnd - InpCloseBeforeMinutes` (mặc định 60 phút trước phiên kế tiếp) để tránh phí swap và gap qua đêm.

### 4.3. Break-Even
Kế thừa v2.01: khi PnL đạt ngưỡng `InpAutoBETrigger`, EA dời SL về `OpenPrice + InpAutoBEOffset`.

---

## 5. Mô tả kỹ thuật

State Machine sử dụng `Enum ORB_STATE_ENUM { ORB_IDLE, ORB_FORMING, ORB_FINAL, ORB_TRADED }`. Hàm `RunStateMachine()` chạy khi đóng nến (index-based), đảm bảo hoạt động đúng trên mọi timeframe. Module `CheckSessionEndClose()` hoạt động song song với State Machine trong `OnTick`, khoá giao dịch khi đạt mốc dọn phiên.

---

## 6. Ví dụ cấu hình khuyến nghị

**XAUUSD — Phiên Mỹ (M15):**
- `InpSessionStartHour` = 17, `InpMarketOpenHour` = 18 (13h EST = 18h UTC).
- `InpMinComposition` = 3. Range được xác nhận sau 3 nến M15 (tương đương ~45 phút tích lũy từ 18:00 đến ~18:45).
- `InpRR` = 1.0. Chốt lời 1R để tối ưu winrate.
- `InpBreakoutBuffer` = 150. Chống false breakout.

---

## 7. Lưu ý rủi ro & Backtest

> [!WARNING]
> Với `InpMinComposition = 3`, EA yêu cầu range phải ổn định qua ít nhất 3 nến. Nếu thị trường biến động mạnh ngay từ nến đầu tiên (range liên tục bị mở rộng), EA có thể bị kẹt ở trạng thái FORMING và bỏ lỡ cơ hội giao dịch (missed trade). Đây là đánh đổi có chủ đích: ưu tiên tránh false breakout hơn là bắt mọi cơ hội.

- **Backtest Option:** Bắt buộc duy nhất **Every Tick based on real ticks**.

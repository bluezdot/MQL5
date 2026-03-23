# Support & Resistance Breakout (SRB) v1.00 — Tài Liệu Thuật Toán

**File:** `SRB_v1.00.mq5`
**Phiên bản:** 1.00
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

SRB là chiến lược giao dịch đột phá (breakout) hoàn toàn tự động dựa trên **vùng hỗ trợ/kháng cự động**. Các vùng hỗ trợ và kháng cự (S/R) được xác định tự động bằng chỉ báo **Fractals** tích hợp sẵn của Bill Williams, qua đó loại bỏ việc người dùng phải kẻ/vẽ tay kháng cự hỗ trợ, đồng thời theo đuôi sát xu hướng hành động giá.

---

## 2. Tham số cấu hình - Input Parameters

### ==== General Inputs ====
| Input Variable | Mặc Định | Kiểu | Mô tả |
|---|---|---|---|
| `InpMagicNumber` | 19 | int | Magic number để phân biệt bot mở lệnh trên tài khoản |
| `InpFractalPeriod` | 5 | int | Chu kỳ để tìm kiếm pattern Fractal (nhóm số lượng nến) |
| `InpLotSize` | 0.1 | double | Khối lượng vào lệnh cố định |
| `InpRR` | 1.5 | double | Tỷ lệ Risk:Reward (Reward/Risk ratio). Nhấn mạnh SL được tính logic theo sóng. TP = SL x RR |

---

## 3. Chi tiết thuật toán

### 3.1. Nhận diện vùng Hỗ trợ/Kháng cự bằng Fractal
Sử dụng hàm iFractals để đọc Pattern 5 nến (chuỗi nến đỉnh điểm):
- **Kháng cự (Resistance):** Vẽ qua đỉnh nến giữa (Fractal High) cao hơn so với đỉnh nến ở trước và sau nó.
- **Hỗ trợ (Support):** Vẽ qua đáy nến giữa (Fractal Low) thấp hơn so với đáy nến ở trước và sau.
> Fractal là chỉ báo đi sau (lagging indicator) nên cần 2 nến hoàn thành sau đó để xác nhận chính xác. Điều này khiến thuật toán bỏ qua 2 index cuối gần nhất để lấy mức cản.

### 3.2. Điều kiện Vào/Ra Lệnh
Chỉ hoạt động khi có **nến mới mở**, thuật toán sẽ đọc giá đóng cửa của nến kề nó (`closePrice` nến index 1):
- **BUY:** Nếu giá `closePrice > resistance` (Breakout kháng cự).
- **SELL:** Nếu giá `closePrice < support` (Breakout hỗ trợ).
*(EA sẽ check nếu đang có 1 vị thế mở bởi lệnh từ `InpMagicNumber` thì không nhồi lệnh thêm, để bảo toàn tài khoản).*

### 3.3. Tính toán SL/TP
Nguyên lý cắt lỗ tuân thủ chặt đứt cấu trúc cản:
- **Lệnh BUY:** 
  - `SL = support` (chặn lỗ nằm dưới đáy Fractal Low gần nhất)
  - `TP = closePrice + (closePrice - SL) * InpRR` (TP thả nổi theo SL nhân với Risk:Reward)
- **Lệnh SELL:**
  - `SL = resistance` (chặn lỗ nằm mép trên đỉnh Fractal High gần nhất)
  - `TP = closePrice - (SL - closePrice) * InpRR`

---

## 4. Mô tả kỹ thuật

- `handleFractals`: Được khởi tạo trong hàm `OnInit` chuyên gọi ra instance `iFractals`.
- Các biến `upper[]` (Kháng cự) và `lower[]` (Hỗ trợ) chứa giá trị các mức được copy thông qua hàm `CopyBuffer`.
- Giá trị đỉnh đáy sẽ được thiết lập vòng lặp chạy từ index=2 cho đến tối đa 50 nến quá khứ (vì index 0 và 1 chưa thoả điều kiện check xác nhận sóng xong). Quá trình kết thúc break khi tìm thấy 2 điểm S/R đầu tiên (Mới nhất).
- Lệnh được thực thi ra thị trường thông qua đối tượng class `CTrade`. Toàn bộ hành động dò `OnTick` được rào chắn bởi cờ `last_bar` nhằm bảo đảm giảm số chu kỳ tính toán (chỉ chạy khi nhịp đóng nến hoàn thiện một bar nến).

---

## 5. Ví dụ cấu hình khuyến nghị

**Ví dụ Giao dịch trên khung H1 (XAUUSD):**
- `InpRR` = 2.0 (Do TP dài nên 1 lệnh thắng có thể bù lỗ cho 2 lệnh thua).
- `InpFractalPeriod` = 5. Lọc những điểm breakout mạnh và có kiểm chứng cao, để các S/R được confirm không bị nhiễu do tick nhỏ của H1. Khung thời gian càng nhỏ thì càng nên nâng Period lên.

---

## 6. Lưu ý rủi ro & Backtest

> [!WARNING]
> Tín hiệu Fractal bị trễ vì cần chờ xác nhận từ 2 nến kế tiếp hoàn thành. Không có lớp lọc thời gian (Day/Time filter) nên bot có thể xả lệnh vào ban đêm và lệnh có lot thủ công (fixed lot) không co giãn phần trăm thep equity.

- **Backtest Option:** Dùng `Every Tick` hoặc chế độ `Open Prices Only` đều hợp lệ, do điều kiện vào dựa theo kết quả `closePrice` của một nến đã thành hình hoàn chỉnh nằm phía sau. Việc không tính giá tick làm tăng tốc độ test lên đáng kể.

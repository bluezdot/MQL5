# MFR DCA v2.01 — Tài Liệu Thuật Toán

**File:** `MFR_DCA_v2.01.mq5`
**Phiên bản:** 2.01
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

**MFR DCA** (Martingale Fibonacci Retracement DCA) kết hợp ba kỹ thuật:
1. **Trend Detection** — Nhận diện xu hướng tăng/giảm dựa trên chuỗi nến liên tiếp đóng tăng dần (Higher Close + Higher Low) hoặc giảm dần.
2. **Fibonacci Retracement Grid** — Khi giá pullback, đặt lưới 10 lệnh Limit tại các mức Fibo (0.236 → 4.236).
3. **Martingale Lot Sizing** — Lot mỗi mức tăng theo dãy Fibonacci (×1, ×1, ×2, ×3, ×5, ×8, ×13, ×21, ×34, ×55).

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết (v2.01 so với v2.00) |
|-----------|-------------------------------|
| **Refactor TrendState** | Struct `TrendState` đổi tên biến `swingHigh`/`swingLow` thành `anchor`/`limit` để phân biệt rõ điểm neo xu hướng và điểm giới hạn hồi, tránh nhầm lẫn chiều Buy/Sell. |
| **Xác nhận nến đóng Pullback** | Tín hiệu Pullback được xác nhận từ nến đã đóng (`rates[1]`) thay vì nến live `rates[0]`. Tránh vào lệnh sai do râu nến giật (false signal). |
| **Skip Fibo đã vượt** | Hàm `SetupDCAChain` bỏ qua các mức Fibo mà giá thị trường đã vượt qua khi đặt lưới, nhưng vẫn giữ đúng hệ số lot Fibonacci tại mỗi index tầng. |
| **Fix Bug modify TP** | Khi cập nhật Take Profit bằng `PositionModify`, giá trị Stop Loss hiện có không bị ghi đè hoặc xoá mất. |
| **Fix bug Sell chain** | Dùng `anchor` (đáy trend) thay vì `swingHigh` sai chiều. |
| **Index đồng nhất** | Trend check, anchor, FindSwing đều start từ `rates[2]` để đúng với map index mới. |
| **Pullback lỏng hơn** | Nến pullback chỉ cần wick chọc qua nến trước, không cần close chọc qua để xác định. |
| **Tối ưu hiệu suất** | `ScanForTrend` chạy 1 lần/nến thay vì mỗi tick. `CheckStopLoss` sử dụng `IsNewBar()` chung. |
| **Kiểm tra Ask/Bid chuẩn xác** | `CheckAndManageChain` sử dụng `askPrice` cho lệnh Buy và `bidPrice` cho lệnh Sell khi kiểm tra phá `anchor`. |
| **Bảo vệ xung đột đa EA** | Bổ sung kiểm tra `_Symbol` cùng với `MagicNumber` khi quản lý lệnh, ngăn ngừa xung đột lệnh giữa các EA chạy trên nhiều pair khác nhau. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input Variable | Mặc Định | Mô tả |
|---|---|---|
| `InpBaseLot` | 0.01 | Lot size cơ bản. |
| `InpLotMultiplier` | 1.0 | Hệ số nhân lot tổng thể. |
| `InpBaseTrendRange` | 10000 | Biên độ tối thiểu (points) mà chuỗi nến phải đạt để xác nhận xu hướng. |
| `InpBaseTrendCandles` | 3 | Số nến liên tiếp đóng cùng chiều tối thiểu để xác nhận xu hướng. |
| `InpMaxFindSwingCandles` | 20 | Số nến tối đa quét ngược lịch sử để tìm mốc Swing High/Low. |
| `InpMagicNumber` | 15 | Magic number. |

---

## 4. Chi tiết thuật toán

### 4.1. Bản đồ Index nến

Sự thay đổi quan trọng của v2.01 so với v2.00 trong cách sử dụng index nến:

| Index | Ý nghĩa | Vai trò trong v2.01 |
|:-----:|----------|---------------------|
| `rates[0]` | Nến live đang chạy | **Không** dùng để xác nhận tín hiệu — tránh false signal do râu nến giật. |
| `rates[1]` | Nến vừa đóng xong | Dùng để xác nhận Pullback (giá hồi ngược xu hướng). |
| `rates[2..N+1]` | N nến lịch sử | Tạo base trend — xác nhận xu hướng tăng/giảm. |

### 4.2. Điều kiện Vào/Ra Lệnh

**Xác định xu hướng (`ScanForTrend`):**
- **Buy:** `N` nến liên tiếp có Higher Close, tổng biên độ ≥ `InpBaseTrendRange × _Point`.
- Kèm điều kiện: nến `rates[1]` (vừa đóng) phải đóng thấp hơn nến trước — xác nhận Pullback.
- Xác định `anchor` (mốc Fibo) và `limit` (điểm hồi).
- Ngược lại với Sell.

**Đặt lưới DCA (`SetupDCAChain`):**
- Tính Diff = |Anchor − Limit|.
- Đặt 10 lệnh Limit tại các mức Fibo: 0.236, 0.382, 0.500, 0.618, 0.786, 1.000, 1.618, 2.618, 3.618, 4.236.
- Lot size tại mỗi mức theo chuỗi Fibonacci: [1, 1, 2, 3, 5, 8, 13, 21, 34, 55] × `InpBaseLot` × `InpLotMultiplier`.
- **Tính năng mới:** Nếu giá hiện tại đã vượt qua một mức Fibo, lệnh Limit ở mức đó sẽ bị bỏ qua (không đặt), nhưng hệ số lot Fibonacci của index đó vẫn được giữ nguyên.

**Cập nhật Take Profit (`UpdateTP`):**
- Mỗi tick, xác định vị thế có entry xấu nhất (mức Fibo sâu nhất đang khớp lệnh).
- Đặt TP cho toàn bộ chuỗi tại mức Fibo cao hơn 1 bậc (gần anchor hơn).
- **Cải tiến:** Khi gọi `PositionModify` để cập nhật TP, giá trị SL hiện tại được truyền lại để không bị xoá.

### 4.3. Cơ chế Stop Loss

Hàm `CheckStopLoss()` hoạt động theo chu kỳ đóng nến (chỉ kiểm tra khi có nến mới đóng):
- Kiểm tra giá đóng của nến vừa hoàn thành có phá vỡ mức Fibo cuối cùng (4.236) hay không.
- Nếu phá vỡ: xoá toàn bộ lệnh Limit đang chờ và đóng tất cả vị thế đang mở để cắt lỗ.
- **Ưu điểm so với v2.00:** Sử dụng giá đóng nến thay vì tick giá, tránh bị kích hoạt SL giả do râu nến giật.

---

## 5. Mô tả kỹ thuật

Struct `TrendState` lưu trữ trạng thái xu hướng với các trường: `active`, `anchor`, `limit`, `direction` (1 = Buy / -1 = Sell), `hadPositions`.

Luồng xử lý `OnTick()` theo thứ tự:
1. `CheckStopLoss()` — Kiểm tra điều kiện cắt lỗ (chỉ khi có nến mới đóng).
2. Quản lý Buy Chain và Sell Chain **song song, độc lập**. Nếu một chiều không active, gọi `ScanForTrend()` để dò tín hiệu mới.
3. `CheckAndManageChain()` — Kiểm tra 3 điều kiện reset Chain:
   - Giá vượt qua mốc Anchor mà chưa có lệnh nào khớp → Reset.
   - TP đã hit, các vị thế đã đóng, còn lệnh Limit treo → Xoá và reset.
   - Không còn vị thế lẫn lệnh Limit → Reset.

---

## 6. Ví dụ cấu hình khuyến nghị

**XAUUSD — Khung M30:**
- `InpBaseTrendCandles` = 3
- `InpBaseTrendRange` = 30000 (biên độ dao động lớn hơn phù hợp với khung M30).
- `InpMaxFindSwingCandles` = 20–25 (quét khoảng 10–12 giờ lịch sử trên M30 để tìm Swing High/Low chính xác).
- `InpBaseLot` = 0.01 (giữ lot thấp nhất để phòng hộ vốn — tổng lot tối đa = 1.43 lot).
- `InpLotMultiplier` = 1.0 (Phù hợp với 5000$ -> 10000$)

---

## 7. Lưu ý rủi ro & Backtest

> [!WARNING]
> Chiến lược Martingale + lưới Fibo tích luỹ lot rất lớn khi giá đi sâu. Tại mức Fibo 4.236 (tầng thứ 10), tổng lot tích luỹ ≈ 143 × `InpBaseLot`. Tài khoản có vốn mỏng (< 3000$) có rủi ro Margin Call rất cao. Ngoài ra, gap giá qua đêm/cuối tuần có thể khiến giá nhảy vượt mốc 4.236 mà không kịp kích hoạt SL nến, gây thiệt hại nghiêm trọng.

- **Backtest Option:** Bắt buộc dùng chế độ **Every Tick based on Real Ticks** để có kết quả giả lập chính xác.

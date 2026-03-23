# MFR DCA v2.00 — Tài Liệu Thuật Toán

**File:** `MFR_DCA_v2.00.mq5`
**Phiên bản:** 2.00
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

**MFR DCA** (Martingale Fibonacci Retracement DCA) kết hợp ba kỹ thuật:

1. **Trend Detection** — Nhận diện xu hướng tăng/giảm dựa trên `N` nến liên tiếp đóng cùng chiều.
2. **Fibonacci Retracement Grid** — Khi giá pullback, đặt lưới 10 lệnh Limit tại các mức Fibo (0.236 → 4.236).
3. **Martingale Lot Sizing** — Lot mỗi mức tăng theo dãy Fibonacci (×1, ×1, ×2, ×3, ×5, ×8, ×13, ×21, ×34, ×55).

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết (v2.00 so với v1.00) |
|-----------|-------------------------------|
| SL | v1.00 không có Stop Loss, gây rủi ro cháy tài khoản. v2.00 thêm cơ chế cắt lỗ tự động: khi giá phá vỡ mức Fibo cuối cùng (4.236), EA sẽ đóng toàn bộ vị thế và xoá lệnh Limit còn lại để bảo vệ vốn. |
| TP & Reset Chain tự động | Sửa lỗi EA bị treo khi lưới lệnh chạm TP. Sau khi TP được kích hoạt, EA tự động reset Chain và sẵn sàng cho chu kỳ giao dịch mới thay vì dừng hoạt động. |
| Logic lưới Fibo chuẩn hóa | Cải thiện logic đo và đặt lưới Fibonacci Retracement, đảm bảo các mức Limit được tính chính xác hơn dựa trên Swing High/Low. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input | Mặc Định | Mô tả |
|---|---|---|
| `InpBaseLot` | 0.01 | Lot size cơ bản. Tổng lot khi toàn bộ 10 lệnh Limit khớp = 143 × `InpBaseLot`. |
| `InpBaseTrendRange` | 10000 | Biên độ tối thiểu (points) mà chuỗi nến phải đạt để xác nhận xu hướng. |
| `InpBaseTrendCandles` | 3 | Số nến liên tiếp đóng cùng chiều tối thiểu để xác nhận xu hướng. |
| `InpMaxFindSwingCandles` | 20 | Số nến tối đa quét ngược lịch sử để tìm mốc Swing High/Low. |
| `InpMagicNumber` | 14 | Magic number để phân biệt lệnh của EA này với các EA khác chạy trên cùng tài khoản. |

---

## 4. Chi tiết thuật toán

### 4.1. Điều kiện Vào/Ra Lệnh

**Xác định xu hướng (`ScanForTrend`):**
- **Buy:** `InpBaseTrendCandles` nến liên tiếp có Close tăng dần, tổng biên độ ≥ `InpBaseTrendRange × _Point`.
- **Sell:** ngược lại — nến liên tiếp có Close giảm dần.
- Kèm điều kiện Pullback: nến live `rates[0]` đang đóng ngược chiều xu hướng (giá hồi lại).

**Đặt lưới DCA (`SetupDCAChain`):**
- Xác định Swing High và Swing Low từ dữ liệu lịch sử.
- Tính Diff = Swing High − Swing Low.
- Đặt 10 lệnh Limit tại các mức Fibo: 0.236, 0.382, 0.500, 0.618, 0.786, 1.000, 1.618, 2.618, 3.618, 4.236.
- Lot size tại mỗi mức theo chuỗi Fibonacci: [1, 1, 2, 3, 5, 8, 13, 21, 34, 55] × `InpBaseLot`.

**Cập nhật Take Profit (`UpdateTP`):**
- Mỗi tick, xác định vị thế có entry xấu nhất (mức Fibo sâu nhất đang khớp lệnh).
- Đặt TP cho toàn bộ chuỗi lệnh tại mức Fibo cao hơn 1 bậc (gần anchor hơn) so với vị thế xấu nhất. Mục tiêu: khi giá hồi về, cả chuỗi đều có lãi trung bình.

### 4.2. Cơ chế Stop Loss

Hàm `CheckStopLoss()` hoạt động theo chu kỳ đóng nến (`lastBar`):
- Khi nến đóng xong, kiểm tra giá đóng có phá vỡ mức Fibo cuối cùng (mức 4.236 — mức Limit thứ 10) hay không.
- Nếu giá phá vỡ tầng 4.236: EA xoá toàn bộ lệnh Limit đang chờ và đóng tất cả vị thế đang mở để cắt lỗ, bảo vệ tài khoản khỏi Margin Call.

---

## 5. Mô tả kỹ thuật

Struct `TrendState` lưu trữ trạng thái xu hướng với các trường: `active`, `swingHigh`, `swingLow`, `direction`, `hadPositions`.

Hàm `CheckAndManageChain()` kiểm tra 3 điều kiện để reset Chain:
1. Giá vượt qua mốc Swing (anchor) mà chưa có lệnh nào khớp → Reset để tránh lưới treo vô nghĩa.
2. TP đã được kích hoạt, các vị thế đã đóng nhưng vẫn còn lệnh Limit treo → Xoá lệnh Limit dư và reset.
3. Không còn vị thế mở lẫn lệnh Limit chờ → Reset để EA sẵn sàng dò tín hiệu mới.

---

## 6. Ví dụ cấu hình khuyến nghị

**XAUUSD — Khung M15:**
- `InpBaseTrendRange` = 10000 (tương đương 1000 pip MT5, phù hợp biên độ dao động trung bình của vàng trên M15).
- `InpMaxFindSwingCandles` = 20 (quét khoảng ~5 giờ lịch sử trên M15 để tìm Swing High/Low).
- `InpBaseLot` = 0.01 (giữ lot thấp nhất để phòng hộ — tổng lot tối đa khi 10 lệnh khớp = 1.43 lot).

---

## 7. Lưu ý rủi ro & Backtest

> [!WARNING]
> Chiến lược Martingale + lưới Fibo tích luỹ lot rất lớn khi giá đi sâu. Ở mức Fibo cuối (4.236), tổng lot gom = 143 × `InpBaseLot`. Nếu xác định Swing sai hoặc trend đảo chiều mạnh, tài khoản có rủi ro Margin Call rất cao. **Không khuyến khích sử dụng với tài khoản dưới 2000$**. Ngoài ra, nến live `rates[0]` có thể tạo tín hiệu Pullback giả (râu nến giật) dẫn đến vào lệnh sai.

- **Backtest Option:** Bắt buộc dùng chế độ **Every Tick based on real ticks** để có kết quả giả lập chính xác.

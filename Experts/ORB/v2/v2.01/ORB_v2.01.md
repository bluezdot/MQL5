# GOLD ORB v2.01 — Tài Liệu Thuật Toán

**File:** `ORB_v2.01.mq5`
**Phiên bản:** 2.01
**Ngôn ngữ:** MQL5
**Ngày cập nhật:** 2026-03-19

---

## 1. Tổng quan chiến lược

ORB v2.01 là phiên bản bản nâng cấp của v2.00, fix lỗi false break out điển hình. Ngoài ra bổ sung option Break-even Auto.

---

## 2. Cải tiến của phiên bản

| Tính năng | Chi tiết v2.01 so với v2.00  |
|-----------|-------------------------------------|
| Breakout Buffer | Bổ sung cơ chế cộng `InpBreakoutBuffer` để chống false break. |
| Auto Break-Even | Bổ sung cơ chế dời SL về hòa vốn khi giá đạt lợi nhuận `InpAutoBETrigger`. |

---

## 3. Tham số cấu hình - Input Parameters

### ==== General Settings ====
| Input Variable | Mặc Định | Mô tả |
|---|---|---|
| `InpMagicNumber` | 17 | Magic number |
| `InpSessionStartHour` / `InpMarketOpenHour` | 21/22 | Giờ khởi tạo Session và Market Open |
| `InpMinComposition` | 0 | Số nến cần thiết để xác định Range |

### ==== Entry Settings (Cải tiến Nòng Cốt) ====
| Input Variable | Mặc Định | Mô tả |
|---|---|---|
| `InpBreakoutBuffer` | 150 | Buffer points chống false break |

### ==== TP Settings ====
| Input Variable | Mặc Định | Mô tả |
|---|---|---|
| `InpTPMode` | `TP_BY_RR` | Mode chốt lời |
| `InpRR` / `InpTPPoints`| 1.0 / 12000 | - | Các thông số biến tùy biến làm mốc chốt lời |

### ==== BE & Trailing Stop (Lá Chắn Mới) ====
| Input Variable | Mặc Định | Mô tả |
|---|---|---|
| `InpUseAutoBE` | false | Bật/tắt chế độ dời SL về hòa vốn |
| `InpAutoBETrigger` | 250 | Số Point cần đạt được để dời SL về hòa vốn |
| `InpAutoBEOffset` | 20 | Số Point độn thêm để bù phí giao dịch, đảm bảo dời SL về hòa vốn |
| Các thông số Trailing | ... | | Các thông số Trailing Stop được giữ nguyên từ phiên bản v2.00 |

---

## 4. Chi tiết thuật toán

### 4.1. Điều kiện Vào/Ra Lệnh bằng Vách Ngăn
Bổ sung `Breakout Buffer`, mở rộng Range để chống false break.
`buyTriggerPrice  = g_range.high + InpBreakoutBuffer * _Point;`
`sellTriggerPrice = g_range.low  - InpBreakoutBuffer * _Point;`

### 4.2. Break-Even
Khi lệnh Open thả nổi PnL đạt ngưỡng `InpAutoBETrigger`, EA sẽ dời SL về hòa vốn `OpenPrice + InpAutoBEOffset`.

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
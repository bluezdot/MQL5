# MFR DCA v2.3 — Documentation

**File:** `MFR_DCA_v2.3.mq5`

**Phiên bản:** 2.30

---

## 2. Cải tiến so với v2.2

| # | Cải tiến | Chi tiết |
|---|---|---|
| 1 | **TP dựa trên Avg Entry** | Thay vì tìm Fibo index sâu nhất, v2.3 tính **lot-weighted average entry** rồi đặt TP tại `avgEntry + (anchor − avgEntry) × InpTpRetracementPct` |
| 2 | **`InpTpRetracementPct` input** | Điều chỉnh tỉ lệ TP retracement mà không cần recompile (thay thế `#define TP_RETRACEMENT_PCT`) |

---

*Tài liệu tạo ngày 2026-03-11 — MFR DCA v2.3.mq5*

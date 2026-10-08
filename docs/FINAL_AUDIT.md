# Audit Akhir (§41) — EVE IDR Risk Protector v1.00

Audit dilakukan dari atas ke bawah terhadap seluruh kode di `MQL5/`.

Status:
- **OK** = terpenuhi dan ada bukti kode/test.
- **OK\*** = terpenuhi dengan catatan.
- **RISIKO** = keterbatasan yang tersisa.

> **Catatan utama:** kode **belum pernah di-compile**. Lingkungan pengembangan tidak punya MetaEditor, dan `download.mql5.com` diblokir. Sudah dilakukan tiga hal:
> - review sintaks manual;
> - cek keseimbangan kurung/blok otomatis;
> - menghindari konstruksi MQL5 yang meragukan (mis. elemen array struct tidak pernah di-pass by reference; tidak ada `MathMin`/`MathMax` ke `int`).
>
> Proyek baru boleh dianggap **diterima** setelah compile 0 error dan unit test 0 failed di MT5 user (PANDUAN §3–4).

| # | Item audit §41 | Status | Bukti / lokasi |
|---|---|---|---|
| 1 | Kebingungan IDR/USD | OK | Tidak ada kurs hard-coded. Semua input `long` IDR. Mata uang ≠ IDR → `SAFE_DISABLED` (`RiskProtectorApp::Init`). Grep "USD" hanya menemukan komentar. |
| 2 | Kesalahan hitung floating profit | OK | `CEvePositionScanner::SumFloating` = Σ `POSITION_PROFIT`, dinormalisasi ke `ACCOUNT_CURRENCY_DIGITS` (B-04); T2, T8. |
| 3 | Target profit dari winners saja | OK | `CEveFloatingMonitor::Evaluate` memakai total **net**; T6 (+700k −300k → tidak trigger). |
| 4 | Swap/komisi ikut terhitung | OK | `POSITION_SWAP` hanya dibaca untuk log; komisi tidak dibaca sama sekali; T7. |
| 5 | Kegagalan partial close | OK | `ProcessClose`: deteksi volume turun → kirim sisa; `DONE_PARTIAL` = sukses-terverifikasi-parsial; pecahan `VOLUME_MAX`. |
| 6 | Perintah close ganda | OK | Satu op per (tiket, jenis). Tidak kirim ulang selama `awaitingVerify` sampai `VerificationTimeoutMs`. `request.position` selalu terisi. |
| 7 | Race condition | OK\* | Handler MQL5 single-thread + penjaga `m_inCycle`. Posisi baru saat closing ikut ditutup (§25.D). Posisi yang sedang ditutup dikeluarkan dari rencana SL. Engine SL dijeda di luar `ARMED`. |
| 8 | Pemulihan restart | OK | `CEvePersistence` (GV per login+server + `GlobalVariablesFlush`). Restore `LOCKED` / `CLOSING_ALL` (`RestoreAndArm`). Ganti input tidak membuka lock (G-08). |
| 9 | Risiko SL melebihi budget IDR | OK\* | Gerbang kepatuhan Σ ≤ B; `Σ Budget_g ≤ B − fixed` (floor); verifikasi ulang setelah normalisasi; guard never-widen di executor; T11–T14. Catatan R2, R4. |
| 10 | Level harga broker tidak valid | OK | `IsLegalSL` (stops + freeze + buffer, relatif ke Bid/Ask, B-02); cek ulang legalitas tepat sebelum kirim. |
| 11 | Arah SL BUY/SELL salah | OK | `IsMoreProtective`, `IsLegalSL`, solver bercabang BUY/SELL; T11, T17. |
| 12 | Normalisasi volume | OK\* | EA tidak menghitung volume baru. Close memakai volume live posisi (≤ `VOLUME_MAX`). Catatan R3. |
| 13 | Normalisasi tick-size | OK | Solver bekerja pada indeks `k × SYMBOL_TRADE_TICK_SIZE` lalu `NormalizeDouble(digits)`. |
| 14 | Perbedaan hedging/netting | OK\* | `ACCOUNT_MARGIN_MODE` dideteksi dan di-log. Close via `request.position`, volume ≤ volume live; 10036 → verifikasi hilang. Belum diuji di akun netting. |
| 15 | Logika pembuka trade tidak sengaja | OK | Grep: satu-satunya `TRADE_ACTION_DEAL` di production ada di `ProcessClose` (closing deal, arah berlawanan, dengan `position`). Harness pembuka posisi terpisah dan menolak jalan di luar tester. |
| 16 | Fail-open diam-diam | OK | `SAFE_DISABLED` / CONFIG ERROR / AutoTrading OFF / timer gagal tampil sebagai banner + log CRITICAL + push. Retry close tidak pernah berhenti selama posisi ada (K-02). Gagal hitung → UNPROTECTED (terlihat). |
| 17 | Risiko SL dari harga sekarang, bukan harga open | OK | `LossAt(..., POSITION_PRICE_OPEN, X)`. Harga sekarang hanya untuk legalitas dan headroom. |
| 18 | Pending order membuat eksposur saat LOCKED | OK | Hapus sejak awal close-all (jika lock berlaku) dan terus selama LOCKED; posisi baru ditutup sesuai policy. |
| 19 | Monitoring hanya `OnTick()` | OK | Timer `EventSetMillisecondTimer` (fallback 1 s + banner) + `OnTradeTransaction`. |
| 20 | SL melebar saat rebalance | OK | `ShouldMoveSL` hanya mengetatkan (preserve ON). SL pengunci profit tidak pernah dilebarkan. Executor menolak pelebaran sebagai lapis kedua; T16, T17. |
| 21 | SL mustahil diterima diam-diam | OK | `UNSATISFIABLE` → `CRITICAL_SL_BUDGET_UNSATISFIABLE` + fail-safe; T15. |
| 22 | SL agregat diperlakukan sebagai target | OK | Tidak ada aksi saat patuh. Budget tidak "dihabiskan" dengan melebarkan SL (kecuali preserve OFF, opt-in eksplisit). |

## Risiko yang tersisa (diketahui)

| ID | Risiko | Dampak / mitigasi |
|---|---|---|
| R1 | Compile dan unit test sudah lulus di MT5 user; harness tester dan checklist demo belum | Wajib harness + checklist demo sebelum live. |
| R2 | Posisi tanpa SL yang terblokir (market tutup) tidak masuk perhitungan budget saat itu | Ditampilkan UNPROTECTED. Saat market buka, rencana diulang dan posisi lain hanya diketatkan. |
| R3 | Posisi netting > `VOLUME_MAX` dengan sisa pecahan < `VOLUME_MIN` | Close sisa bisa ditolak berulang (retry persisten + CRITICAL). Sangat jarang. |
| R4 | Drift kurs USD/IDR hanya dikoreksi selama EA berjalan | Margin 1% + koreksi otomatis saat online. |
| R5 | Gap/slippage melebihi `EmergencyCloseMaxDeviationPoints` (Instant execution) | Requote → retry terus dengan harga baru. Hasil realisasi bisa melewati limit (sesuai §26). |
| R6 | SL untuk posisi baru dipasang di siklus timer berikutnya (≤ 250 ms) | Proteksi global tetap aktif di setiap event. |
| R7 | Lonjakan spread (rollover) bisa memicu close-all | Sesuai spek (trigger langsung). Filter tidak ditambahkan agar close darurat tidak tertunda. |
| R8 | `OrderSend` sinkron: close-all N posisi butuh N × latensi dalam satu siklus | Semua close dikirim di siklus yang sama tanpa jeda tambahan. |
| R9 | EA lain yang memodifikasi SL bisa "berebut" dengan engine | Backoff per tiket; fail-safe setelah `SLModifyFailuresBeforeFailSafe` penolakan. |

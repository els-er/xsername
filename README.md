# EVE IDR Risk Protector (MT5) — v1.00

EA **pengendali risiko** untuk MetaTrader 5 (akun Exness Pro dengan mata uang **IDR**).

> EA ini **tidak pernah membuka posisi**. Tidak ada sinyal, martingale, grid, maupun averaging. Tugasnya hanya menjaga risiko.

## Fitur

| Fitur | Ringkasan |
|---|---|
| **A. Global Floating Loss** | Jika total floating P/L **semua posisi di akun** ≤ −`MaxGlobalFloatingLossIDR`, **semua posisi ditutup**. |
| **B. Global Floating Profit** | Jika total floating P/L **net** ≥ `GlobalFloatingProfitTargetIDR`, **semua posisi ditutup**. ON/OFF terpisah. |
| **C. Lock** | Opsional. Setelah close-all, EA masuk `LOCKED`: posisi baru langsung ditutup dan pending order dihapus, sampai Anda menekan **RESET PROTECTION** (dua klik). Default **OFF**, jadi Anda bisa langsung entry lagi. |
| **D. Aggregate IDR SL** | Memasang SL server-side di setiap posisi. Total kerugian teoretis jika semua SL kena tidak melebihi `MaxAggregateSLRiskIDR`. Budget mengikuti berapa pun jumlah entry dan berapa pun lot-nya: satu harga SL bersama per simbol+arah. |

Dasar perhitungan:
- Hanya `POSITION_PROFIT`. Swap dan komisi **tidak** dihitung.
- Semua nominal dalam **Rupiah**.
- Cakupan: **semua posisi di akun** (semua simbol, semua magic number, manual maupun EA lain).

> **Penting:** nominal limit adalah **ambang pemicu**, bukan jaminan hasil realisasi. Pergerakan harga, spread, slippage, latensi, dan gap bisa membuat hasil akhir berbeda dari angka yang diset.

## Isi repository

```text
MQL5/Experts/EVE_IDR_RiskProtector.mq5           EA production
MQL5/Experts/EVE_RiskProtector_TestHarness.mq5   khusus Strategy Tester (membuka posisi uji)
MQL5/Scripts/EVE_Risk_UnitTests.mq5              unit test (tanpa trading)
MQL5/Include/EVE_Risk/*.mqh                      modul (lihat docs/DESIGN.md)
docs/PANDUAN.md                                  panduan compile, instalasi, uji, VPS
docs/DESIGN.md                                   arsitektur, algoritma, state machine
docs/TEST_PLAN.md                                rencana uji + checklist demo + status bukti
docs/SPEC_AUDIT.md                               audit spek + keputusan user
docs/FINAL_AUDIT.md                              audit akhir (§41)
docs/EA_IDR_RISK_PROTECTION_SPEC.md              spesifikasi asli
tests/solver_mirror_check.py                     cek silang angka unit test (Python)
CHANGELOG.md
```

## Mulai cepat

1. Salin folder `MQL5` ke Data Folder MT5 (*File → Open Data Folder*).
2. Compile `EVE_IDR_RiskProtector.mq5` di MetaEditor (F7).
3. Jalankan script `EVE_Risk_UnitTests` dan pastikan hasilnya **0 failed**.
4. Pasang EA di **satu** chart (simbol apa saja) pada akun **demo IDR**. Aktifkan *Allow Algo Trading* dan tombol **Algo Trading**.
5. Isi nominal Rupiah di tab Inputs.

Langkah lengkap ada di [`docs/PANDUAN.md`](docs/PANDUAN.md).

## Parameter input

Semua nominal dalam **IDR (Rupiah)**, berupa bilangan bulat.

| Input | Default | Keterangan |
|---|---|---|
| `ProtectionScope` | ALL ACCOUNT POSITIONS | Satu-satunya mode di v1.00. |
| `EnableGlobalFloatingLossProtection` | true | Aktifkan close-all saat total floating rugi mencapai limit. |
| `MaxGlobalFloatingLossIDR` | 500000 | **MAX GLOBAL FLOATING LOSS (IDR)**. Pemicu: total ≤ −nilai ini. |
| `LockAfterGlobalTrigger` | **false** | Lock setelah trigger loss. Default OFF (keputusan user), jadi bisa langsung entry lagi. |
| `RequireManualReset` | true | Wajib true jika lock loss ON. |
| `EnableGlobalFloatingProfitAutoClose` | false | Aktifkan close-all saat target profit tercapai. |
| `GlobalFloatingProfitTargetIDR` | 500000 | **GLOBAL FLOATING PROFIT TARGET (IDR)**. Pemicu: total net ≥ nilai ini. |
| `LockAfterGlobalProfitTrigger` | false | Lock setelah trigger profit. |
| `RequireManualResetAfterProfit` | false | Wajib true jika lock profit ON. |
| `LockedNewPositionPolicy` | CLOSE IMMEDIATELY | Saat LOCKED: posisi baru langsung ditutup, atau alert saja. |
| `CancelPendingOrdersWhenLocked` | true | Saat LOCKED: hapus semua pending order (juga sejak awal close-all jika lock berlaku). |
| `EnableAggregateIDRSL` | true | Engine SL agregat ON/OFF. |
| `MaxAggregateSLRiskIDR` | 500000 | **MAX AGGREGATE SL RISK (IDR)**: total rugi teoretis jika semua SL kena. Batas atas, bukan target. |
| `AutoApplySLToNewPositions` | true | false = mode advisory: hanya memberi peringatan, tidak memasang SL, tidak close. |
| `RebalanceExistingPositionsOnNewEntry` | true | Entry baru membuat SL basket dihitung ulang (hanya diketatkan). |
| `SLAllocationMethod` | BASKET | BASKET = satu harga SL bersama per simbol+arah dari total semua entry. PROPORTIONAL = jatah tetap per posisi menurut lot (spek asli). |
| `PreserveMoreProtectiveExistingSL` | true | SL yang lebih ketat tidak pernah dilebarkan. SL yang mengunci profit tidak pernah dilebarkan dalam kondisi apa pun. |
| `FailSafeWhenCompliantSLImpossible` | CLOSE POSITION | Jika SL legal broker tidak bisa memenuhi budget: tutup posisi, atau biarkan terbuka dengan status UNPROTECTED + alert. |
| `SLBudgetSafetyMarginPct` | 1.0 | SL dipasang di 99% budget supaya tidak terus dimodifikasi saat kurs USD/IDR bergerak. Aksi ulang baru terjadi jika risiko > 100%. |
| `SLExtraBufferTicks` | 1 | Jarak tambahan dari stop level broker. |
| `SLModifyFailuresBeforeFailSafe` | 5 | Jumlah penolakan modifikasi SL berturut-turut sebelum fail-safe. |
| `CloseRetryCount` | 5 | Retry cepat saat close gagal. Setelah itu retry **persisten** selama posisi masih ada. |
| `CloseRetryDelayMs` | 250 | Jeda retry cepat. |
| `VerificationTimeoutMs` | 5000 | Batas tunggu verifikasi sebelum close/modifikasi dikirim ulang. |
| `PersistentRetryIntervalMs` | 1000 | Jeda retry persisten. |
| `EmergencyCloseMaxDeviationPoints` | 1000 | Slippage maksimum untuk close darurat (Instant execution). Diabaikan pada Market execution. |
| `ReconciliationIntervalMs` | 250 | Interval timer rekonsiliasi seluruh akun. |
| `EnablePushNotifications` | true | Push ke HP (MetaQuotes ID harus diisi di MT5). |
| `EnableAlerts` | true | Popup alert untuk kejadian kritis. |
| `EnableFileLog` | true | Log harian di `MQL5\Files\EVE_RiskProtector_<login>_<tanggal>.log`. |
| `ShowDashboard`, `DashboardX`, `DashboardY` | true, 10, 25 | Panel di chart. |

## Keterbatasan penting

1. **Ambang ≠ hasil.** Rugi atau profit realisasi bisa melewati angka yang diset (gap, slippage, spread, latensi, close berurutan).
2. **Proteksi global hanya hidup selama MT5 dan EA berjalan dan terkoneksi.** Jika VPS mati, yang tersisa hanya SL server-side dari Feature D.
3. **Bukan batas rugi harian.** Rugi yang sudah realized tidak dihitung. Dengan lock OFF, Anda bisa entry lagi setelah close-all (keputusan user).
4. **Spread melebar saat rollover** bisa memicu close-all lebih awal pada posisi SELL, karena posisi SELL dinilai di harga Ask.
5. **SL basket konservatif.** Profit sebuah entry tidak dipakai untuk melebarkan SL entry lain, jadi SL bisa sedikit lebih ketat dari titik "net = −budget".
6. **SL mengikuti kurs.** Kerugian dalam IDR di level SL ikut kurs USD/IDR. EA mengetatkan SL bila risiko naik di atas budget, tapi hanya selama EA berjalan.
7. **Posisi EA lain ikut dikelola.** Engine SL juga memasang SL dan bisa menutup posisi milik EA lain (keputusan user). EA lain yang memodifikasi SL bisa "berebut" dengan engine ini.
8. **Satu instance per akun per terminal.** Instance kedua otomatis `STANDBY`. Dua terminal berbeda pada akun yang sama tidak bisa dicegah.
9. **Tidak cocok untuk MetaQuotes Virtual Hosting.** Tombol reset tidak berfungsi di sana. Gunakan Windows VPS biasa (RDP).
10. **Belum di-compile di lingkungan pengembangan.** Lihat `docs/FINAL_AUDIT.md` dan `docs/PANDUAN.md`.

## Versi

v1.00 — lihat [`CHANGELOG.md`](CHANGELOG.md).

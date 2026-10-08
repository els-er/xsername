# EVE IDR Risk Protector (MT5) — v1.10

EA **pengendali risiko** untuk MetaTrader 5 (akun Exness Pro dengan mata uang **IDR**).

> EA ini **tidak pernah membuka posisi**. Tidak ada sinyal, martingale, grid, maupun averaging. Tugasnya hanya menjaga risiko.

## Fitur

| # | Fitur | Ringkasan |
|---|---|---|
| 1 | **Max total loss** | Jika total floating P/L **semua posisi di akun** ≤ −limit, **semua posisi ditutup**. |
| 2 | **Profit target** | Jika total floating P/L **net** ≥ target, **semua posisi ditutup**. ON/OFF terpisah. |
| 3 | **Auto stop loss** | SL server-side di setiap posisi. Total rugi teoretis jika semua SL kena tidak melebihi batas Rupiah. Satu harga SL bersama per keranjang (simbol + arah), sehingga mengikuti berapa pun entry dan lot-nya. |
| 4 | **Trailing stop** *(baru v1.10)* | Per keranjang, dalam Rupiah. Mulai jalan saat profit keranjang mencapai nilai awal, lalu mengunci "profit tertinggi − jarak". SL hanya bergerak maju. |
| 5 | **Basket TP** *(baru v1.10)* | TP server-side di harga saat profit keranjang = target Rupiah. Satu harga TP untuk semua entry keranjang. |
| 6 | **Lock** | Opsional. Setelah close-all, EA terkunci sampai Anda menekan **RESET PROTECTION** dua kali. Default **OFF**, jadi Anda bisa langsung entry lagi. |

Dasar perhitungan:
- Hanya `POSITION_PROFIT`. Swap dan komisi **tidak** dihitung.
- Semua nominal dalam **Rupiah**.
- Cakupan: **semua posisi di akun** (semua simbol, semua magic number, manual maupun EA lain).

Peningkatan lain di v1.10:
- **Label input bahasa Inggris sederhana** dengan saklar ON/OFF. Pengaturan teknis dikumpulkan di grup *Advanced* paling bawah.
- **Panel baru:**
  - digambar ulang dan menyesuaikan skala layar (DPI), angka rata kanan sehingga tidak bertumpuk;
  - bar progres, badge status, tombol minimize;
  - posisi pojok bisa dipilih.
- **Perintah dikirim paralel** (async). Close-all dan perubahan SL/TP untuk banyak posisi berangkat bersamaan.
- **SL/TP posisi baru dipasang langsung** saat posisi muncul, tidak menunggu siklus timer.

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

1. Salin folder `MQL5` ke Data Folder MT5 (*File → Open Data Folder*), timpa file lama.
2. Compile `EVE_IDR_RiskProtector.mq5` di MetaEditor (F7).
3. Jalankan script `EVE_Risk_UnitTests` dan pastikan hasilnya **0 failed**.
4. Pasang EA di **satu** chart pada akun **demo IDR**. Aktifkan *Allow Algo Trading* dan tombol **Algo Trading**.

Langkah lengkap ada di [`docs/PANDUAN.md`](docs/PANDUAN.md).

## Parameter input

Label di bawah persis seperti yang tampil di tab Inputs MT5. Semua nominal dalam **IDR**, bilangan bulat.

### 1. MAX TOTAL LOSS — closes ALL positions

| Label | Default | Keterangan |
|---|---|---|
| Close all when total loss reaches the limit | ON | Close-all saat total floating rugi mencapai limit. |
| Max total loss (IDR) | 500000 | Pemicu: total floating ≤ −nilai ini. |
| Lock EA after max loss (needs manual reset) | OFF | ON = setelah close-all, EA terkunci sampai di-reset. |

### 2. PROFIT TARGET — closes ALL positions

| Label | Default | Keterangan |
|---|---|---|
| Close all when total profit reaches the target | OFF | Close-all saat total floating **net** ≥ target. |
| Profit target (IDR) | 500000 | Target profit total akun. |
| Lock EA after profit target (needs manual reset) | OFF | Sama seperti lock di atas. |

### 3. AUTO STOP LOSS — SL on every position

| Label | Default | Keterangan |
|---|---|---|
| Put an SL on every position | ON | Engine SL ON/OFF. |
| Max total loss if all SLs are hit (IDR) | 500000 | Batas atas total rugi teoretis di level SL. |
| SL mode | Basket | *Basket* = satu harga SL untuk semua entry (simbol + arah). *Per position* = jatah per posisi sesuai lot. |
| If an SL cannot be placed within the limit | Close the position | Atau *Leave it open (warning only)*. |

### 4. TRAILING STOP — per basket

| Label | Default | Keterangan |
|---|---|---|
| Trailing stop | OFF | ON/OFF. |
| Start when basket profit reaches (IDR) | 100000 | Trailing mulai saat profit keranjang ≥ nilai ini. |
| Keep this much below the highest profit (IDR) | 50000 | Profit yang dikunci = profit saat ini − jarak. SL hanya maju. |
| Move SL only when locked profit grows by (IDR) | 10000 | Langkah minimal agar SL tidak dimodifikasi terlalu sering. |

### 5. TAKE PROFIT — per basket

| Label | Default | Keterangan |
|---|---|---|
| Take profit | OFF | ON/OFF. |
| Close the basket at this profit (IDR) | 300000 | TP server-side di harga saat profit keranjang = nilai ini. |

### 6. WHEN THE EA IS LOCKED

| Label | Default | Keterangan |
|---|---|---|
| New position while locked | Close it immediately | Atau *Leave it open (warning only)*. |
| Delete pending orders while locked | ON | Hapus pending order selama terkunci. |

### 7. PANEL AND ALERTS

| Label | Default | Keterangan |
|---|---|---|
| Show panel | ON | Panel di chart (tombol reset tetap muncul saat terkunci walau panel OFF). |
| Panel position | Top left | Top left / Top right / Bottom left / Bottom right. |
| Panel distance from side / top-bottom (px) | 10 / 30 | Jarak panel dari tepi chart. |
| Alerts to phone (set MetaQuotes ID in MT5) | ON | Push notification MT5. |
| Popup alerts for important events | ON | Popup alert. |

### 8. ADVANCED — keep the default if unsure

| Label | Default | Keterangan |
|---|---|---|
| Recalculate basket SL on a new entry | ON | Entry baru → SL keranjang dihitung ulang (hanya diketatkan). |
| Never move an SL further away | ON | SL tidak pernah dijauhkan. Wajib ON saat trailing aktif. |
| Put SL on new positions (OFF = warning only) | ON | OFF = SL otomatis hanya memberi peringatan. |
| SL safety margin for USD/IDR moves (%) | 1.0 | SL dipasang di 99% batas agar tidak sering diubah saat kurs bergerak. |
| Extra SL distance from the broker limit (ticks) | 1 | Jarak tambahan dari stop level broker. |
| Close a position after this many SL errors | 5 | Penolakan SL berturut-turut sebelum fail-safe. |
| Fast close retries / Fast retry delay (ms) | 5 / 250 | Retry cepat saat close gagal. Setelah itu retry lanjutan terus selama posisi masih ada. |
| Wait for broker confirmation (ms) | 5000 | Batas tunggu sebelum perintah dikirim ulang. |
| Retry delay after the fast retries (ms) | 1000 | Jeda retry lanjutan. |
| Max slippage for emergency close (points) | 1000 | Untuk Instant execution. Diabaikan pada Market execution. |
| Account check interval (ms) | 250 | Timer pengecekan seluruh akun. |
| Send orders in parallel (faster) | ON | Semua perintah dalam satu siklus dikirim bersamaan (async). |
| Save a daily log file | ON | `MQL5\Files\EVE_RiskProtector_<login>_<tanggal>.log`. |

## Keterbatasan penting

1. **Ambang ≠ hasil.** Rugi atau profit realisasi bisa melewati angka yang diset (gap, slippage, spread, latensi).
2. **Proteksi global hanya hidup selama MT5 dan EA berjalan.** Jika VPS mati, yang tersisa hanya SL/TP server-side.
3. **Bukan batas rugi harian.** Rugi yang sudah realized tidak dihitung (keputusan user).
4. **Spread melebar saat rollover** bisa memicu close-all lebih awal pada posisi SELL.
5. **SL keranjang konservatif.** Profit sebuah entry tidak dipakai untuk melonggarkan SL entry lain.
6. **TP dan trailing mengatur semua posisi akun**, termasuk posisi EA lain. TP manual akan disamakan dengan TP keranjang selama fitur TP ON.
7. **SL/TP mengikuti kurs.** Nilai Rupiah di level SL/TP ikut kurs USD/IDR. EA mengoreksinya hanya selama berjalan.
8. **Satu instance per akun per terminal.** Instance kedua otomatis `STANDBY`.
9. **Tidak cocok untuk MetaQuotes Virtual Hosting.** Gunakan Windows VPS biasa (RDP).
10. **Delay jaringan.** Di WiFi rumah, jarak ke server broker menambah delay. Untuk eksekusi tercepat gunakan VPS dekat server broker.

## Versi

v1.10 — lihat [`CHANGELOG.md`](CHANGELOG.md).

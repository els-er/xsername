# Rencana Uji & Bukti — EVE IDR Risk Protector v1.10

Ada empat lapisan uji:

| Lapisan | Alat | Siapa yang menjalankan |
|---|---|---|
| A. Unit test logika | `MQL5/Scripts/EVE_Risk_UnitTests.mq5` | User (MT5) |
| B. Integrasi di tester | `MQL5/Experts/EVE_RiskProtector_TestHarness.mq5` | User (Strategy Tester) |
| C. Cek silang angka | `tests/solver_mirror_check.py` | Claude (sudah dijalankan, lihat E) |
| D. Uji manual akun demo IDR | Checklist di bawah | User |

Spek §31: tidak ada look-ahead. Harness hanya bereaksi pada tick/timer yang sedang berjalan, dan hasil tester tidak dianggap bukti eksekusi broker yang sebenarnya.

---

## A. Unit test (deterministik)

Jalankan script `EVE_Risk_UnitTests`. Target: `0 failed`. Hasil: `MQL5\Files\EVE_Risk_UnitTests_Result.txt`.

| ID | Skenario (§32) | Ekspektasi |
|---|---|---|
| T1 | Limit Rp500.000; floating −499.999 / −500.000 / −500.001; proteksi OFF | none / LOSS / LOSS / none |
| T2 | −100k, −150k, −250k | LOSS (close all) |
| T3 | +100k | tidak ada trigger loss |
| T4 | Profit OFF, +500k | none |
| T5 | Target 500k: +499.999 / +500.000 / +500.001 | none / PROFIT / PROFIT |
| T6 | +700k −200k +50k = +550k; +700k −300k = +400k | PROFIT; none (net, bukan winners saja) |
| T7 | profit −450k, swap −70k | none (swap tidak dihitung) |
| T8 | −166.666,67 ×2 −166.666,66 = −500.000,00; varian −499.999,99 | LOSS; none |
| T9 | Format Rupiah | `Rp0`, `Rp500.000`, `Rp1.000.000`, `Rp10.500.000`, `-Rp500.000`, `+Rp100.000` |
| T10 | Transisi state legal/ilegal | sesuai DESIGN §4 |
| T11 | BUY 0,10 @2000 / SELL 0,10 @2000, budget 500k | SL 1996,88 / 2003,12; 1 tick lebih jauh > budget |
| T12 | Basket 0,1/0,2/0,3 | satu SL (1998,30), Σ loss ≤ budget |
| T13 | **Contoh user:** 0,02 lot −Rp200.000 + 0,05 lot | SL bersama 1997,47, total Rp499.360, tanpa close paksa |
| T14 | Budget grup proporsional / basket | 83.333 + 166.666 + 250.000 ≤ 500.000; 400.000 + 100.000 |
| T15 | Stop level 500 pt, 1 lot; floating sudah melewati budget | UNSATISFIABLE, SL legal terdekat dilaporkan |
| T16 | SL mengunci profit (BUY/SELL) | loss = 0, tidak pernah dilebarkan (B-01) |
| T17 | Preserve / tighten / widen / idempoten | sesuai §9.2 |
| T18 | Jalur lock lewat state machine | ARMED → … → LOCKED → reset → ARMED |
| T25 | Klasifikasi retcode | DONE sukses, REQUOTE retry, MARKET_CLOSED slow, INVALID_FILL rotasi filling |
| K-03/K-04 | Validasi config | input invalid hanya mematikan fiturnya sendiri; lock tanpa reset ditolak |
| T26 | TP keranjang BUY / SELL 0,10 lot, target 300k | TP 2001,88 / 1998,12 (tick pertama yang mencapai target); legalitas TP |
| T27 | TP keranjang contoh user (0,02 + 0,05) | satu TP 2004,61, profit keranjang Rp300.320 |
| T28 | Aturan refresh TP (toleransi 1%) | TP kosong dipasang; TP dalam toleransi tidak diubah; TP jauh diperbarui |
| T29 | Trailing BUY: profit 320k, jarak 50k, langkah 10k | SL 2001,69 (kunci Rp270.400); +30.400 → geser; +6.400 → tidak; tidak pernah mundur; SL legal terdekat 2001,99 |
| T30 | Trailing SELL (cermin) | SL 1998,31; SL legal terdekat 1998,01; tidak pernah mundur |
| Config v1.10 | Trailing/TP invalid; trailing + never-widen OFF | hanya fitur itu yang mati; never-widen dipaksa ON |

---

## B. Test harness (Strategy Tester)

Mode: *Every tick based on real ticks*, XAUUSD, minimal 1 bulan data.

Invariant yang dicek setiap event:
- **INV1/INV2:** selama `ARMED`, floating tidak pernah ≤ −limit atau ≥ target setelah siklus proteksi berjalan.
- **INV3:** jika semua posisi punya SL dan tidak ada operasi in-flight, `Σ loss di SL ≤ budget`.
- **INV4:** saat `LOCKED` (policy close), posisi baru hilang dalam ≤ 60 detik waktu tester.
- **INV5 (v1.10):** SL sebuah posisi tidak pernah bergerak menjauh dari pasar dan tidak pernah dihapus (never-widen + trailing).

| Skenario | Yang diuji | Lulus jika |
|---|---|---|
| 1 Basket multi-entry | SL basket mengikuti entry 0,02 → 0,05 → SELL; trigger loss | `invariant FAILURES 0`, ada trigger, posisi selalu bersih setelah close-all |
| 2 Lock ON | trigger → LOCKED → entry saat LOCKED ditutup → reset → ARMED | FAILURES 0, `locks ≥ 1`, `manual resets ≥ 1` |
| 3 Profit target | close-all di target net, lock OFF, entry ulang | FAILURES 0, ada trigger |
| 4 Lock OFF | close-all lalu entry ulang langsung | FAILURES 0 |
| 5 Trailing + TP | trailing keranjang dan TP keranjang aktif bersama | FAILURES 0 (termasuk INV5) |

---

## C. Cek silang angka (Python)

`python3 tests/solver_mirror_check.py` menjalankan replika algoritma solver, formatter, dan penjumlahan dengan aritmetika yang sama. Tujuannya memastikan angka harapan di unit test memang benar. Output tersimpan di `tests/solver_mirror_check.out.txt`.

---

## D. Checklist manual di akun DEMO IDR

Gunakan nominal kecil, mis.:
- `MaxGlobalFloatingLossIDR = 50000`
- `MaxAggregateSLRiskIDR = 50000`
- `GlobalFloatingProfitTargetIDR = 50000`

Isi kolom "Hasil" saat menguji.

| # | Langkah | Ekspektasi | Hasil |
|---|---|---|---|
| D1 | Pasang EA di chart EURUSD (bukan XAUUSD) | Dashboard IDR, ARMED, scope ALL | |
| D2 | Buka BUY XAUUSD 0,01 manual | log `NEW POSITION detected`, SL terpasang ≤ 1 detik, `SL Status COMPLIANT` | |
| D3 | Tambah BUY XAUUSD 0,02 | SL kedua posisi pindah ke **satu harga yang sama**, `SL Risk @ Stops` ≤ budget | |
| D4 | Ubah manual SL satu posisi menjadi lebih ketat | EA tidak melebarkannya | |
| D5 | Hapus manual SL satu posisi | EA memasang SL lagi | |
| D6 | Biarkan floating menyentuh −Rp50.000 | `CRITICAL GLOBAL FLOATING LOSS ...`, semua posisi tertutup, `CLOSE-ALL VERIFIED`, kembali ARMED (lock OFF) | |
| D7 | Langsung entry lagi | diizinkan (lock OFF, keputusan user) | |
| D8 | Set `LockAfterGlobalTrigger = true`, ulangi D6 | state LOCKED; entry baru langsung ditutup; pending order dihapus | |
| D9 | Klik RESET PROTECTION sekali, lalu sekali lagi | klik 1: "click again"; klik 2: ARMED, log `MANUAL RESET COMPLETE` | |
| D10 | Saat LOCKED, restart MT5 | setelah start: tetap LOCKED (log `RESTORED LOCKED`) | |
| D11 | Profit auto-close ON target Rp50.000, posisi untung + rugi | close-all saat **net** ≥ target | |
| D12 | Matikan tombol Algo Trading saat ada posisi | banner `PROTECTION CANNOT EXECUTE`; nyalakan lagi → normal | |
| D13 | Pasang EA di chart kedua | chart kedua `STANDBY` | |
| D14 | Posisi dari EA lain (magic ≠ 0) | ikut dihitung dan dikelola | |
| D15 | Buka 1 lot dengan budget sangat kecil (mis. Rp5.000) | `CRITICAL_SL_BUDGET_UNSATISFIABLE` → posisi ditutup (fail-safe) | |
| D16 | Ganti input saat LOCKED (mis. lock jadi OFF) | tetap LOCKED sampai reset | |
| D17 | Pasang di akun non-IDR (mis. USD demo) | `SAFE_DISABLED`, tidak ada aksi | |
| D18 | Close ditolak (uji saat market tutup, mis. akhir pekan, dengan limit yang sudah terlewati) | `CLOSE_FAILED`, retry tiap 5 detik, sukses saat market buka | |
| D19 | Trailing ON (start 20.000, jarak 10.000, langkah 2.000), BUY 0,01 sampai profit > 20.000 | SL pindah ke harga yang mengunci ± profit − 10.000; hanya maju | |
| D20 | Saat trailing jalan, harga berbalik | SL tidak mundur; kena SL dengan profit terkunci | |
| D21 | TP ON (20.000), 2 entry BUY lot berbeda | kedua posisi punya TP yang sama; profit keranjang di TP ≈ 20.000 | |
| D22 | Tambah entry ketiga saat TP aktif | TP semua posisi dihitung ulang (satu harga) | |
| D23 | Ubah TP manual saat TP ON | EA menyamakan lagi ke TP keranjang | |
| D24 | Panel: ganti `Panel position` ke Top right, klik [-] lalu [+] | panel pindah pojok, mengecil/membesar, teks tidak bertumpuk (cek juga skala Windows 125%/150%) | |
| D25 | `Send orders in parallel` ON vs OFF, close-all 5 posisi | keduanya menutup semua; ON terasa lebih cepat; log `SENT_ASYNC` lalu `VERIFIED CLOSED` | |

---

## E. Status bukti

| Item | Status |
|---|---|
| Cek silang Python (C) | **Dijalankan oleh Claude**. Semua angka cocok dengan ekspektasi unit test (lihat `tests/solver_mirror_check.out.txt`). |
| Compile MQL5 v1.00 | **Lulus** — dilaporkan user: 0 error. |
| Unit test MQL5 v1.00 (A) | **Lulus** — dilaporkan user: 0 failed. |
| Uji pakai v1.00 di MT5 | Dilaporkan user: jalan; masukan → v1.10 (bahasa, trailing/TP, panel). |
| Cek silang Python v1.10 (TP/trailing) | **Dijalankan oleh Claude**, angka T26–T30 cocok (`tests/solver_mirror_check.out.txt`). |
| Compile MQL5 v1.10 | **Belum** — menunggu compile oleh user. |
| Unit test MQL5 v1.10 | **Belum** — menunggu user. |
| Harness tester (B) | **Belum dijalankan.** Menunggu user. |
| Checklist demo (D) | **Belum dijalankan.** Menunggu user. |

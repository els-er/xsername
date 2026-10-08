# Desain — EVE IDR Risk Protector v1.10

Dokumen ini memenuhi §41 spek: arsitektur, pemetaan requirement, struktur modul, state machine, algoritma SL agregat, algoritma loss/profit global, algoritma close/retry/verifikasi, dan matriks uji.

Dasar keputusan:
- `docs/EA_IDR_RISK_PROTECTION_SPEC.md` (spek)
- `docs/SPEC_AUDIT.md` (temuan B-/K-/G-/L- dan jawaban user Q1–Q4)

---

## 1. Arsitektur

```text
                         MT5 EVENTS
   OnTick (cepat)   OnTradeTransaction (perubahan)   OnTimer 250ms (rekonsiliasi wajib)
          \                     |                          /
           +------------> CEveRiskProtectorApp::Cycle() <-+          OnChartEvent -> tombol RESET (2 klik)
                                   |
        +--------------------------+------------------------------------------+
        |                          |                                          |
 CEvePositionScanner        CEveFloatingMonitor                      CEveAggregateSLManager
 (SEMUA posisi akun,        total = Σ POSITION_PROFIT                (SL basket server-side,
  PositionsTotal loop)      loss: total <= -MaxLoss                    hanya saat ARMED,
        |                   profit: total >= Target                   hanya di siklus timer)
        |                          |                                          |
        |                          v                                          v
        |                  CEveStateMachine  ---------------------->  CEvePriceRiskCalculator
        |      ARMED -> PROTECTION_TRIGGERED -> CLOSING_ALL            (OrderCalcProfit, solver
        |      -> ALL_POSITIONS_CLOSED -> LOCKED | ARMED                biner per tick-size)
        |                          |                                          |
        +--------------------------+------------------+-----------------------+
                                                      v
                                            CEveTradeExecutor
                         (registry in-flight per tiket, close/modify/delete,
                          retry burst -> retry persisten, verifikasi, filling fallback,
                          penjaga never-widen, penjaga netting)
                                                      |
                     CEvePersistence (GlobalVariables + Flush, per login+server)
                     CEveInstanceGuard (mutex + heartbeat, 1 instance per akun)
                     CEveLogger / CEveNotifier (journal + file + push MT5)
                     CEveRiskDashboard (panel chart, format Rupiah)
```

Prinsip utama:
- Satu fungsi `Cycle()` dipakai oleh ketiga event. Ada penjaga re-entrancy.
- Trigger global dievaluasi di **setiap** event.
- Engine SL hanya berjalan di siklus timer (`full = true`), jadi tidak dijalankan berulang-ulang di setiap tick.
- Tidak ada `Sleep()` dan tidak ada `MessageBox()`. Semua retry dijadwalkan (non-blocking), sehingga timer tetap hidup.
- Tidak ada jalur kode yang membuka posisi (§15). Satu-satunya `TRADE_ACTION_DEAL` di production EA adalah *closing deal* dengan `request.position` terisi.

---

## 2. Struktur file

```text
MQL5/
  Experts/
    EVE_IDR_RiskProtector.mq5            EA production (input + event forwarding saja)
    EVE_RiskProtector_TestHarness.mq5    KHUSUS Strategy Tester: membuka posisi bernaskah + cek invariant
  Scripts/
    EVE_Risk_UnitTests.mq5               unit test logika murni (tanpa trading)
  Include/EVE_Risk/
    Defines.mqh                 enum, konstanta, SEveConfig, helper nama
    IDRFormatter.mqh            format Rupiah: Rp1.000.000 / -Rp500.000
    Logger.mqh                  CEveLogger (INFO/WARNING/ERROR/CRITICAL, file) + CEveNotifier (push, rate-limit)
    AccountValidator.mqh        validasi mata uang IDR, izin trading, mode margin
    ConfigurationValidator.mqh  validasi per fitur, clamp aman, checksum
    PositionScanner.mqh         scan seluruh akun, deteksi posisi baru/hilang, Σ POSITION_PROFIT
    FloatingMonitor.mqh         evaluasi trigger loss/profit (fungsi murni)
    PriceRiskCalculator.mqh     model profit (OrderCalcProfit, bisa di-mock), solver SL basket
    TradeExecutor.mqh           eksekusi + retry + verifikasi
    StateMachine.mqh            state + tabel transisi legal
    Persistence.mqh             CEvePersistence + CEveInstanceGuard
    AggregateSLManager.mqh      engine SL agregat
    TrailTPManager.mqh          trailing stop + take profit per keranjang (v1.10)
    RiskDashboard.mqh           panel chart (CCanvas, DPI-aware) + tombol reset 2 langkah
    RiskProtectorApp.mqh        orkestrator (dipakai EA production dan test harness)
```

---

## 3. Pemetaan requirement → kode

| Requirement (spek) | Implementasi |
|---|---|
| §2.1–2 Semua nominal dalam IDR, bebas diisi | Input `long` (integer Rupiah), label "(IDR)" — `EVE_IDR_RiskProtector.mq5` |
| §3, §15A, §27 Cakupan = semua posisi akun | `CEvePositionScanner::Scan()` loop `PositionsTotal()` tanpa filter simbol/magic; `ProtectionScope` hanya `ALL_ACCOUNT_POSITIONS` |
| §4 Validasi mata uang, SAFE_DISABLED | `CEveAccountValidator::IsCurrencyIDR()`; `App::Init()` → `SAFE_DISABLED`, EA tetap di chart |
| §5.0 OnTick + OnTimer + OnTradeTransaction | `App::OnTickEvent/OnTimerEvent/OnTradeTransactionEvent` → `Cycle()`; timer `EventSetMillisecondTimer(ReconciliationIntervalMs)` |
| §5.2 Hanya `POSITION_PROFIT`, threshold crossing | `CEvePositionScanner::SumFloating()` (swap dibaca hanya untuk log); `CEveFloatingMonitor::Evaluate()` memakai `<=` / `>=` |
| §5A Profit auto-close account-wide net | `Evaluate()` memakai total net yang sama; close-all mencakup semua posisi |
| §5A.6 Trigger tidak saling membatalkan | Trigger hanya dievaluasi saat `ARMED`; alasan disimpan di `CEveStateMachine::Reason()` |
| §6 Close-all + verifikasi + retry | `App::HandleClosing()` + `CEveTradeExecutor::ProcessClose()` |
| §7 Lock ON/OFF, kebijakan posisi baru, pending order | `App::LockAppliesFor()` (flag per alasan, K-01), `HandleLocked()`, `CancelPendingOrders()` |
| §8–§11 SL agregat IDR | `CEveAggregateSLManager::Reconcile()` + `CEvePriceRiskCalculator::SolveGroupSL()` |
| §11.1 Unsatisfiable → fail-safe | `ApplyFailSafe()`: log `CRITICAL_SL_BUDGET_UNSATISFIABLE`, close atau tandai UNPROTECTED |
| §11.2 Gagal modifikasi → retry terbatas | Penghitung gagal per tiket di executor; fail-safe setelah `SLModifyFailuresBeforeFailSafe` |
| §12–13 Deteksi posisi baru, rekonsiliasi idempoten | Signature scan + gerbang kepatuhan (tidak ada aksi jika patuh) |
| §16 State machine eksplisit | `CEveStateMachine::IsAllowed()` |
| §17 Persistensi | `CEvePersistence` (GV per login+server + `GlobalVariablesFlush`) |
| §18 Reset manual | Tombol dua klik `RESET PROTECTION` → `App::ManualReset()` |
| §19 Validasi konfigurasi | `CEveConfigurationValidator::Validate()` (per fitur, K-04) |
| §20–21 Dashboard + format Rupiah | `CEveRiskDashboard`, `EveFormatIDR()` |
| §23–24 Eksekusi andal + log | Executor memeriksa setiap retcode; logger 4 level + file harian |
| §25 Edge case A–J | Lihat matriks uji (§9) |
| §37 Fail safe | Validasi per fitur; proteksi global tidak bergantung pada engine SL |

Temuan audit yang diterapkan: B-01..B-05, K-01..K-05, G-02..G-09, G-12..G-21 (lihat §8 di bawah dan `SPEC_AUDIT.md`).

---

## 4. State machine

```text
INIT -> VALIDATING
VALIDATING -> SAFE_DISABLED          (mata uang bukan IDR)
VALIDATING -> STANDBY                (instance lain sudah aktif untuk akun ini)
VALIDATING -> ARMED                  (normal)
VALIDATING -> LOCKED                 (restore: lock tersimpan)
VALIDATING -> CLOSING_ALL            (restore: close-all belum selesai saat restart)
ARMED -> PROTECTION_TRIGGERED        (alasan: GLOBAL_FLOATING_LOSS | GLOBAL_FLOATING_PROFIT_TARGET)
PROTECTION_TRIGGERED -> CLOSING_ALL
CLOSING_ALL <-> CLOSE_FAILED         (CLOSE_FAILED = burst habis / terblokir; tetap retry)
CLOSING_ALL | CLOSE_FAILED -> ALL_POSITIONS_CLOSED   (0 posisi, tidak ada close in-flight, stabil >= 1 interval)
ALL_POSITIONS_CLOSED -> LOCKED       (jika lock untuk alasan ini ON)
ALL_POSITIONS_CLOSED -> ARMED        (jika lock OFF)
LOCKED -> ARMED                      (HANYA lewat reset manual)
STANDBY -> VALIDATING                (instance utama hilang → ambil alih)
(state apa pun selain SAFE_DISABLED) -> STANDBY   (kepemilikan diambil instance lain)
```

Nilai yang disimpan (durable):
- `ARMED`
- `CLOSING_ALL` (+ alasan, waktu trigger)
- `LOCKED` (+ alasan, waktu trigger)

`LOCKED` tidak pernah dihapus oleh restart, ganti input, atau lepas/pasang EA. Yang bisa menghapusnya hanya tombol reset (G-08).

---

## 5. Algoritma SL agregat (Feature D)

Notasi:
- `B` = `MaxAggregateSLRiskIDR`
- `m` = `SLBudgetSafetyMarginPct / 100`
- `Bt = B × (1 − m)` (target penempatan)

**Loss teoretis** satu posisi di harga `X`:

```text
Loss_i(X) = max(0, −OrderCalcProfit(type_i, symbol_i, volume_i, POSITION_PRICE_OPEN_i, X))
```

- Bertanda dan di-clamp (B-01). SL yang mengunci profit bernilai 0 dan tidak pernah mengimbangi posisi lain (B-03).
- Swap dan komisi tidak ikut dihitung.

**Langkah 1 — gerbang kepatuhan (idempoten).**
- Total teoretis `T = Σ Loss_i(SL_i)` untuk posisi yang punya SL.
- Patuh jika semua posisi punya SL **dan** `T ≤ B`.
- Jika patuh, tidak ada aksi (tidak ada modifikasi berulang).
- Replan hanya jika:
  - ada posisi tanpa SL, atau
  - `T > B` (mis. user melebarkan SL, atau kurs USD/IDR bergeser), atau
  - (`PreserveMoreProtectiveExistingSL = false` dan himpunan posisi berubah).
- Histeresis: SL ditempatkan pada `Bt`, aksi ulang baru terjadi setelah melewati `B` (G-12).

**Langkah 2 — klasifikasi.**
- Posisi yang sedang ditutup (ada op CLOSE) dikeluarkan.
- `Rebalance = true`: semua posisi *adjustable*.
- `Rebalance = false`: posisi yang sudah punya SL menjadi *fixed*; hanya posisi tanpa SL yang adjustable. Jika tidak ada posisi tanpa SL (pelanggaran karena drift/pelebaran), semua menjadi adjustable.
- `FixedLoss = Σ Loss_i(SL_i)` untuk posisi fixed.

**Langkah 3 — grup.**
- `BASKET_COMMON_PRICE` (default, jawaban Q1): satu grup per (simbol, arah).
- `PROPORTIONAL_TO_VOLUME`: satu grup per posisi.

**Langkah 4 — budget grup.**
- `A = Btot − FixedLoss`
- `Consumed_g = GroupLoss_g(harga keluar saat ini)` (BUY → Bid, SELL → Ask)
- `w_g = volume_g / Σ volume_adjustable`

| Mode | Budget grup |
|---|---|
| BASKET | `H = A − Σ Consumed_g`; `Budget_g = floor(Consumed_g + max(0, H) × w_g)` |
| PROPORTIONAL | `Budget_g = floor(max(0, A) × w_g)` (spek harfiah) |

`Σ Budget_g ≤ A`, jadi total tidak melebihi `Btot`. Dihitung untuk `Btot = Bt`. Jika satu grup tidak layak pada `Bt`, grup itu dicoba lagi dengan bagian dari `Btot = B`. Campuran keduanya tetap `≤ B` karena `H(Bt) ≤ H(B)`.

**Langkah 5 — solver SL bersama per grup** (`SolveGroupSL`):

```text
GroupLoss_g(P) = Σ_i Loss_i(EffStop_i(P))
EffStop_i(P)   = SL_i  jika (Preserve, atau SL_i mengunci profit) dan SL_i lebih protektif dari P
                 P     selain itu
```

- Karena `Loss_i` di-clamp per posisi, entry yang **untung** di harga `P` dihitung 0, sehingga profitnya tidak dipakai untuk melebarkan SL entry lain (B-03). Akibatnya, jika sebagian entry basket berada di zona profit pada level SL, SL bersama bisa sedikit lebih ketat daripada titik "net total = −budget". Ini selalu ke arah risiko lebih kecil. Contoh di unit test T12: SL 1998,30, bukan 1998,15. Close-all global (Feature A) tetap memakai total **net** persis seperti permintaan user.
- `GroupLoss_g(P)` monoton. Pencarian biner dilakukan pada indeks tick `k` (`P = k × SYMBOL_TRADE_TICK_SIZE`, lalu `NormalizeDouble(digits)`).
- Jarak minimum: `d = max(STOPS_LEVEL, FREEZE_LEVEL) × point + SLExtraBufferTicks × tickSize`.
- **BUY:**
  - `kHigh = floor((Bid − d) / tick)` adalah SL legal terdekat.
  - Jika `GroupLoss(kHigh) > Budget_g` → **UNSATISFIABLE**.
  - Selain itu cari `k` terkecil (SL terjauh) dengan `GroupLoss ≤ Budget_g`.
- **SELL:** cerminannya: `kLow = ceil((Ask + d) / tick)`, lalu cari `k` terbesar.
- Pembulatan selalu ke arah risiko lebih kecil (§22). Hasil diverifikasi ulang dengan `OrderCalcProfit` setelah normalisasi.

**Langkah 6 — terapkan.** Untuk tiap posisi di grup, SL diubah ke `P*` jika:
- posisi belum punya SL, atau
- `P*` lebih protektif dari SL sekarang (mengetatkan), atau
- `Preserve = false` dan SL sekarang **tidak** mengunci profit (melebarkan, masih dalam budget).

Setiap modifikasi selalu mengirim `POSITION_TP` terkini (B-05). Executor menolak pelebaran saat `Preserve = true` sebagai pertahanan lapis kedua.

**Langkah 7 — kegagalan.**
- `UNSATISFIABLE`:
  - log `CRITICAL_SL_BUDGET_UNSATISFIABLE` (simbol, tiket, volume, budget, SL legal terdekat, loss teoretisnya);
  - fail-safe `CLOSE_POSITION` menutup semua posisi grup, sedangkan `LEAVE_UNPROTECTED` menandai UNPROTECTED dan mengirim alert.
- Gagal hitung (`OrderCalcProfit` false): UNPROTECTED + ERROR, **tanpa** fail-safe close (G-13).
- Market tutup (retcode slow): tiket diblokir 5 detik lalu dicoba lagi, tanpa menambah hitungan gagal.
- Modifikasi gagal `N` kali berturut-turut: fail-safe.

**Contoh dari user (Q1).** Budget Rp500.000, model XAUUSD Rp1.600.000 per $1 per lot.

- P1 BUY 0,02 @2006,25, floating −Rp200.000 (Bid 2000,00).
- P2 BUY 0,05 @2000,20.
- `GroupLoss(P) = 32.000 × (2006,25 − P) + 80.000 × (2000,20 − P) ≤ 500.000` memberi `P ≥ 1997,4643`, dinormalisasi menjadi `P* = 1997,47`.
- Loss di `P*` = Rp280.960 + Rp218.400 = Rp499.360 ≤ budget.
- Kedua SL dipasang di 1997,47. Tidak ada posisi yang ditutup paksa. Saat harga menyentuh 1997,47, total floating ≈ −Rp500.000; SL server dan close-all global terjadi bersamaan.
- Kasus ini ada di unit test `TestSolverUserExample`, dengan `m = 0` agar angkanya persis.

---

## 6. Algoritma loss/profit global (Feature A/B)

```text
Scan(): total = NormalizeDouble( Σ POSITION_PROFIT (semua posisi akun), ACCOUNT_CURRENCY_DIGITS )
Evaluate (hanya jika state == ARMED):
  if LossActive   and total <= −MaxGlobalFloatingLossIDR + ε  -> GLOBAL_FLOATING_LOSS
  elif ProfitActive and total >=  GlobalFloatingProfitTargetIDR − ε -> GLOBAL_FLOATING_PROFIT_TARGET
ε = 1e-7 (lebih kecil dari unit Rupiah terkecil; total sudah dinormalisasi, B-04)
```

Detail:
- `FloatingLoss = max(0, −total)`, `FloatingProfit = max(0, total)`.
- Fitur hanya aktif jika ON dan nilainya > 0 (validator).
- Evaluasi berjalan di OnTick, OnTimer, dan OnTradeTransaction.

---

## 7. Algoritma close / retry / verifikasi

**Trigger:**
1. Log CRITICAL dengan snapshot semua posisi.
2. `PROTECTION_TRIGGERED`, simpan state.
3. Batalkan op modifikasi SL.
4. Kirim notifikasi.
5. Jika lock berlaku untuk alasan ini dan `CancelPendingOrdersWhenLocked`, hapus pending sekarang (G-06).
6. `CLOSING_ALL`, simpan state.
7. Langsung masuk `HandleClosing()` di siklus yang sama.

**HandleClosing (setiap siklus):**
- Setiap posisi yang terlihat (termasuk posisi **baru** yang muncul saat closing, §25.D) mendapat op CLOSE jika belum punya.
- Jika ada op yang sudah habis burst-nya atau terblokir, state menjadi `CLOSE_FAILED`; jika pulih, kembali ke `CLOSING_ALL`.
- Selesai jika 0 posisi, tidak ada op CLOSE aktif, dan kondisi ini stabil ≥ `max(ReconciliationIntervalMs, 100)` ms.

**ProcessClose (per op, non-blocking):**
1. Jika posisi sudah tidak ada (`PositionSelectByTicket` false): **VERIFIED CLOSED**, op selesai.
2. Jika sedang menunggu verifikasi:
   - Jika volume posisi sudah turun dari volume saat kirim: lanjut kirim sisanya (partial fill / pecahan `VOLUME_MAX`).
   - Jika belum lewat `VerificationTimeoutMs`: tunggu, **jangan kirim ulang** (anti-duplikat, G-15).
   - Jika sudah lewat timeout: WARNING, hitung sebagai satu percobaan, kirim ulang.
3. Jika belum waktunya (`now < nextAttempt`): tunggu.
4. Baca ulang posisi secara live dan siapkan close deal:
   - `volume = min(volume_sekarang, SYMBOL_VOLUME_MAX)`, tidak pernah melebihi volume posisi;
   - `request.position = tiket` (aman untuk netting);
   - harga Bid/Ask terkini, `deviation = EmergencyCloseMaxDeviationPoints`;
   - filling: Instant/Request → FOK; Market → FOK/IOC sesuai flag, lalu RETURN; dirotasi saat retcode 10030.
5. Klasifikasi retcode:
   - `DONE` / `DONE_PARTIAL` / `PLACED` → tunggu verifikasi.
   - `POSITION_CLOSED` → cek ulang posisi.
   - `MARKET_CLOSED`, `TRADE_DISABLED`, AutoTrading off (10026/10027), gagal lokal tanpa izin trading → **slow**: coba lagi tiap 5 detik, tidak pernah menyerah.
   - Lainnya → **burst**: `CloseRetryCount` kali tiap `CloseRetryDelayMs`. Setelah itu **persisten** tiap `PersistentRetryIntervalMs` selama posisi masih ada (K-02).
6. Log:
   - setiap kirim/hasil di fase burst;
   - fase persisten tiap 10 percobaan atau saat retcode berubah (anti-spam).

`ProcessModify` dan `ProcessDelete` memakai pola yang sama: baca ulang → validasi → kirim → verifikasi (SL terbaca = target ± ½ tick, atau order hilang).

---

## 8. Keputusan desain tambahan (dari audit)

| Kode | Keputusan |
|---|---|
| K-01 | Lock dipilih per alasan: LOSS → `LockAfterGlobalTrigger`, PROFIT → `LockAfterGlobalProfitTrigger`. |
| K-03 | Lock ON + `RequireManualReset = false` dilaporkan CONFIG ERROR, lalu diperlakukan aman (reset manual tetap wajib). |
| K-04 | Input invalid hanya mematikan fitur terkait (atau di-clamp ke default aman untuk parameter teknis). EA tidak pernah mengembalikan `INIT_FAILED`. |
| G-07 | Tombol reset dua klik dalam 10 detik. Tidak ada `MessageBox`. Reset ditolak jika masih ada op close aktif. |
| G-09 | Mutex GV per akun + heartbeat (dianggap basi setelah 10 detik). Instance kedua menjadi `STANDBY`. Nonaktif di tester. |
| G-16 | Izin trading (terminal, EA, akun, expert, koneksi) dicek setiap siklus. Jika mati, banner CRITICAL + log + push sekali. |
| G-17 | Push MT5: antrean dengan jarak ≥ 6,5 detik (batas platform 10/menit), maksimum 10 pesan antre. |
| G-18 | Close-all memproses posisi dalam urutan scan. Semua close dikirim dalam satu siklus, jadi urutan berdampak minimal. |
| G-21 | Engine SL dijeda di semua state selain `ARMED` (statistik tetap dihitung untuk dashboard). |
| Q4 | Default `LockAfterGlobalTrigger = false`. |

---

## 9. Matriks uji

**Kolom "Jenis":**
- **U** = unit test (`EVE_Risk_UnitTests.mq5`, deterministik)
- **H** = test harness di Strategy Tester (cek invariant)
- **D** = manual di akun demo IDR (checklist di `docs/TEST_PLAN.md`)

| # | Skenario (§32) | Ekspektasi | Jenis |
|---|---|---|---|
| T1 | Limit 500k: −499.999 / −500.000 / −500.001 | none / LOSS / LOSS | U |
| T2 | P1 −100k, P2 −150k, P3 −250k | total −500k → LOSS | U |
| T3 | Total +100k | tidak ada trigger loss | U |
| T4 | Profit OFF, +500k | tidak ada trigger | U |
| T5 | Profit ON 500k: +499.999 / +500.000 / +500.001 | none / PROFIT / PROFIT | U |
| T6 | +700k, −200k, +50k (net +550k) | PROFIT (net, bukan winners saja) | U |
| T7 | Swap/komisi ≠ 0 | hanya `POSITION_PROFIT` dijumlah | U (fungsi penjumlah) + D |
| T8 | Penjumlahan berdesimal (−166.666,67 ×2 −166.666,66) | LOSS tepat di −500.000 | U |
| T9 | Format IDR | Rp0, Rp500.000, Rp1.000.000, Rp10.500.000, −Rp500.000 | U |
| T10 | Transisi state legal/ilegal | sesuai §4 | U |
| T11 | SL 1 posisi BUY/SELL | loss di SL ≤ budget, 1 tick lebih jauh > budget | U |
| T12 | 3 posisi 0,1/0,2/0,3 (basket) | satu harga SL, Σ loss ≤ budget | U + H |
| T13 | Contoh user 0,02 (−200k) + 0,05 | SL bersama 1997,47, tidak ada close paksa | U |
| T14 | Proporsional: budget 83.333/166.666/250.000 | Σ ≤ 500.000 | U |
| T15 | Stop level membuat budget mustahil | UNSATISFIABLE, tidak dipasang | U + D |
| T16 | SL mengunci profit (B-01) | loss = 0, tidak pernah dipindah ke zona rugi | U |
| T17 | Preserve: SL lebih ketat dipertahankan | keputusan "keep" | U |
| T18 | Lock ON: trigger → close → LOCKED → posisi baru ditutup → reset → ARMED | sesuai | H + D |
| T19 | Lock OFF: trigger → close → ARMED → bisa entry lagi | sesuai | H + D |
| T20 | Posisi baru muncul saat CLOSING | ikut ditutup | H + D |
| T21 | Restart terminal saat LOCKED / CLOSING | state dipulihkan | D |
| T22 | Akun non-IDR | SAFE_DISABLED, tidak ada aksi | D (+ H dengan deposit USD tanpa override) |
| T23 | Close ditolak (market tutup / AutoTrading OFF) | CLOSE_FAILED, retry terus, sukses setelah pulih | D |
| T24 | EA dipasang di 2 chart | chart kedua STANDBY | D |
| T25 | Klasifikasi retcode | sesuai tabel §7 | U |


---

## 10. Tambahan v1.10

### 10.1 Input bahasa Inggris sederhana

Permintaan user: bahasa sederhana, tetap Inggris. Perubahan:
- Saklar `bool` diganti enum **ON/OFF**.
- Input yang tidak punya pilihan nyata dihapus dari tab Inputs: `RequireManualReset*` (lock selalu butuh reset manual) dan `ProtectionScope` (hanya satu nilai). Nilainya tetap dikirim ke engine.
- Pengaturan teknis dikumpulkan di grup **8. ADVANCED** paling bawah.
- Label tetap menyebut satuan **(IDR)** (§36).

| Nama di spek | Label v1.10 |
|---|---|
| `EnableGlobalFloatingLossProtection` / `MaxGlobalFloatingLossIDR` | Close all when total loss reaches the limit / Max total loss (IDR) |
| `LockAfterGlobalTrigger` | Lock EA after max loss (needs manual reset) |
| `EnableGlobalFloatingProfitAutoClose` / `GlobalFloatingProfitTargetIDR` | Close all when total profit reaches the target / Profit target (IDR) |
| `EnableAggregateIDRSL` / `MaxAggregateSLRiskIDR` | Put an SL on every position / Max total loss if all SLs are hit (IDR) |
| `SLAllocationMethod` / `FailSafeWhenCompliantSLImpossible` | SL mode / If an SL cannot be placed within the limit |
| `RebalanceExistingPositionsOnNewEntry` | Recalculate basket SL on a new entry |
| `PreserveMoreProtectiveExistingSL` | Never move an SL further away |
| `AutoApplySLToNewPositions` | Put SL on new positions (OFF = warning only) |
| `CloseRetryCount` / `CloseRetryDelayMs` / `VerificationTimeoutMs` | Fast close retries / Fast retry delay (ms) / Wait for broker confirmation (ms) |
| `CancelPendingOrdersWhenLocked` | Delete pending orders while locked |

Dashboard, banner, dan notifikasi juga memakai bahasa Inggris sederhana. Log teknis tetap rinci.

### 10.2 Take profit per keranjang

Keranjang = posisi dengan simbol + arah yang sama.

```text
G(P) = Σ OrderCalcProfit(type, sym, vol_i, open_i, P)     (signed: semua posisi tutup bersamaan di P)
P_tp = BUY : harga TERKECIL dengan G(P) >= target
       SELL: harga TERBESAR dengan G(P) >= target
```

Langkah:
1. Pencarian biner pada indeks tick, sama seperti solver SL (`SolvePriceForProfit`).
2. Hasilnya dicek legal: BUY `TP ≥ Bid + jarak`, SELL `TP ≤ Ask − jarak`. Jika tidak legal, dilewati dulu.
3. TP diubah hanya jika posisi belum punya TP, atau profit keranjang di TP sekarang menyimpang > 1% dari target (histeresis, tidak berubah tiap kali kurs bergerak).
4. Jika `G(harga sekarang) ≥ target`, keranjang langsung ditutup (purpose `TAKE_PROFIT`). Ini menangani TP yang belum bisa dipasang.

### 10.3 Trailing stop per keranjang

```text
aktif jika G(exit) >= start
lock   = G(exit) - distance
P_ts   = harga dengan G(P_ts) = lock (sisi terdekat ke pasar, solver yang sama)
jika P_ts melewati batas legal broker -> pakai SL legal terdekat (ClosestLegalSL)
pindah SL posisi i ke P_ts hanya jika:
   SL_i kosong, atau
   P_ts lebih protektif dari SL_i DAN G(P_ts) - G(SL_i) >= step
```

Sifatnya:
- Stateless (tidak perlu menyimpan puncak; aman setelah restart).
- SL hanya maju. `Never move an SL further away` dipaksa ON (validator) agar engine SL tidak melonggarkan SL trailing.
- Bersama engine SL: keduanya hanya mengetatkan, dan permintaan digabung (SL paling protektif yang menang). Kepatuhan budget tetap terjaga.

### 10.4 Satu perintah SL+TP, digabung per siklus

- `RequestStops(ticket, sl, tp, purpose)`: `EVE_KEEP` = jangan ubah.
- Permintaan dalam siklus yang sama untuk posisi yang sama digabung: SL paling protektif menang, TP terakhir menang.
- Ditolak jika sedang in-flight (re-plan setelah verifikasi) atau jika posisi sedang ditutup.
- Verifikasi memeriksa SL dan TP yang diminta. Bagian yang tidak legal/akan melebar dibuang, sisanya tetap dikirim.
- Penghitung gagal:
  - *hard* (SL yang dibutuhkan engine SL) dihitung ke fail-safe;
  - *soft* (trailing/TP) hanya backoff hingga 30 detik dan **tidak** menunda engine SL.

### 10.5 Pengiriman paralel (async)

- `Send Orders In Parallel = ON` → `OrderSendAsync`. Semua close/modifikasi dalam satu siklus berangkat bersamaan.
- `request_id` disimpan. Balasan broker datang lewat `OnTradeTransaction` (`TRADE_TRANSACTION_REQUEST`) → `OnRequestResult`:
  - ditolak → retry dijadwalkan segera (close/delete) atau dicatat gagal (modifikasi);
  - diterima → tetap menunggu verifikasi dari state posisi.
- Jika balasan hilang, timeout verifikasi tetap menangani. Anti-duplikat sama seperti mode sinkron.

### 10.6 Kapan engine SL/trailing/TP berjalan

- Setiap siklus timer (250 ms).
- Setiap event trade (posisi baru langsung dapat SL/TP).
- Saat tick, paling sering tiap 200 ms.
- Aksi hanya saat `ARMED`. Statistik panel diperbarui di semua state.

### 10.7 Panel (CCanvas)

- Satu `OBJ_BITMAP_LABEL` digambar dengan CCanvas.
- Font dalam persepuluhan poin (diskalakan Windows). Semua jarak × `TERMINAL_SCREEN_DPI / 96`.
- Lebar dihitung dari teks yang diukur (`TextWidth`): label kiri, angka rata kanan, panel melebar sampai maks ±470 px × skala. Teks yang lebih panjang dipotong dengan `...`, banner dibungkus kata per kata.
- Badge status, bar progres (rugi, profit, risiko SL), tombol minimize, tombol RESET yang digambar (klik dideteksi dari koordinat `CHARTEVENT_OBJECT_CLICK`).
- Posisi dihitung dari pojok pilihan dan ukuran chart, diperbarui saat `CHARTEVENT_CHART_CHANGE`.

# Audit Spesifikasi — EVE IDR Risk Protection EA

**Dokumen yang diaudit:** `docs/EA_IDR_RISK_PROTECTION_SPEC.md`
**Tahap:** pra-implementasi (§34 "Before coding" dan §41)
**Status:** menunggu keputusan user untuk Q1–Q4 (bagian 7)

---

## 1. Ringkasan

Intinya spek ini sudah benar dan arsitekturnya sehat:

- monitoring berlapis `OnTick` + `OnTimer` + `OnTradeTransaction`,
- trigger hanya dari `POSITION_PROFIT` dengan threshold crossing,
- state machine yang eksplisit,
- lock yang persisten,
- SL dihitung lewat `OrderCalcProfit()`, bukan rumus pip.

Spek ini bisa diimplementasikan. Tapi kalau dikerjakan **apa adanya**, ada masalah:

| Kategori | Jumlah | Contoh |
|---|---|---|
| Bug rumus/logika di spek | 5 | `abs()` di rumus SL bisa membuat SL yang sedang mengunci profit malah **dilebarkan ke zona rugi** (B-01) |
| Kontradiksi antar-bagian | 9 | Flag lock mana yang berlaku untuk profit trigger (K-01), retry terbatas vs "terus tutup sampai habis" (K-02) |
| Perilaku yang tidak didefinisikan | 21 | Rebalance saat entry baru bisa menutup paksa posisi lama yang sedang rugi (G-01), deviasi/slippage untuk close darurat (G-04) |
| Keterbatasan yang harus dipahami user | 6 | Proteksi floating ≠ batas rugi harian (L-01), proteksi global mati jika terminal/VPS mati (L-02) |
| Kendala lingkungan | 1 | Container ini tidak bisa compile MQL5 (bagian 6) |

Skala keparahan: **KRITIS** = perilaku tidak aman jika diikuti apa adanya · **TINGGI** = harus diputuskan sebelum coding · **SEDANG** = perlu definisi, ada usulan default · **RENDAH** = kosmetik/minor.

---

## 2. Bug rumus / logika di spek

### B-01 [KRITIS] `abs()` pada rumus loss SL (§10)

Spek menulis:

```text
abs(OrderCalcProfit(ORDER_TYPE_BUY, symbol, volume, referencePrice, SLPrice)) <= AllocatedRiskIDR
```

- **Masalah:** SL BUY yang sudah dipindah di atas harga open (breakeven/trailing, mengunci profit) menghasilkan `OrderCalcProfit` **positif**. Dengan `abs()`, profit yang terkunci dihitung sebagai "risiko". Jika profit terkunci > alokasi, engine menganggap SL itu "insufficient" lalu mencari "furthest legal SL dengan abs ≤ alokasi". Hasilnya SL di **bawah** harga open (zona rugi). SL dilebarkan besar-besaran, kebalikan langsung dari §9.2/§9.3.
- **Resolusi:** pakai loss bertanda:
  `Loss_i = max(0, −OrderCalcProfit(type, sym, vol, POSITION_PRICE_OPEN, SL))`.
  SL yang mengunci profit punya `Loss_i = 0` dan tidak pernah disentuh.

### B-02 [TINGGI] Syarat sisi SL relatif ke harga open (§10)

- **Masalah:** spek menulis "BUY: `SLPrice < Current/Reference Price`", dan reference = `POSITION_PRICE_OPEN`. Itu salah untuk SL yang sudah melewati breakeven.
- **Resolusi:** validitas SL selalu relatif ke harga pasar, tidak ke harga open:
  - BUY: `SL ≤ Bid − jarak_min` dan `SL > 0`
  - SELL: `SL ≥ Ask + jarak_min`

  Harga open hanya dipakai untuk **menghitung loss teoretis**.

### B-03 [TINGGI] SL di zona profit bolehkah "membebaskan" budget posisi lain? (spek diam)

- **Masalah:** dengan loss bertanda, SL yang mengunci +Rp200.000 bisa dianggap risiko −Rp200.000. Artinya posisi lain boleh rugi lebih besar.
- **Resolusi (konservatif):** risiko per posisi = `max(0, Loss_i)`. Profit terkunci **tidak** mengimbangi risiko posisi lain. Ini selalu ≤ budget dan tidak pernah memperlebar SL siapa pun.

### B-04 [SEDANG] Perbandingan threshold dengan `double` (§5.2, §32)

- **Masalah:** test case "Floating = −Rp500.000 → trigger" bisa gagal karena jumlah `POSITION_PROFIT` berdesimal bisa menghasilkan `−499999.99999999994`.
- **Resolusi:**
  - Total dinormalisasi ke `ACCOUNT_CURRENCY_DIGITS` sebelum dibandingkan.
  - Input IDR bertipe integer (`long`), jadi user tidak bisa mengetik desimal yang ambigu.

### B-05 [TINGGI] Modifikasi SL bisa menghapus TP (spek diam)

- **Masalah:** `TRADE_ACTION_SLTP` mengirim SL **dan** TP sekaligus. Mengirim `tp = 0` akan **menghapus TP** yang dipasang user atau EA lain.
- **Resolusi:** setiap modifikasi SL selalu menyertakan `POSITION_TP` terkini, dibaca ulang tepat sebelum dikirim.

---

## 3. Kontradiksi antar-bagian

### K-01 [TINGGI] Flag lock untuk profit trigger

- **Masalah:**
  - §6 langkah 8 berlaku untuk "loss **atau** profit" tapi memakai `LockAfterGlobalTrigger`.
  - §5A.4 dan §5A.5 memakai `LockAfterGlobalProfitTrigger`.
  - §16 juga hanya menyebut `LockAfterGlobalTrigger`.
- **Resolusi:** flag dipilih berdasarkan alasan trigger:
  - `GLOBAL_FLOATING_LOSS` → `LockAfterGlobalTrigger`
  - `GLOBAL_FLOATING_PROFIT_TARGET` → `LockAfterGlobalProfitTrigger`

### K-02 [TINGGI] Retry terbatas vs "terus tutup sampai habis"

- **Masalah:**
  - §5.1/§6 menetapkan `CloseRetryCount=5` × `250 ms` (≈1,25 detik), lalu "retry policy exhausted".
  - §25.H meminta "continue closing until no in-scope positions remain".
  - Jika diikuti harfiah, setelah 5 gagal (badai requote, atau market satu simbol sedang tutup) EA **berhenti mencoba sementara posisi masih terbuka**. Ini fail-open.
- **Resolusi: retry dua tingkat.**
  1. **Burst:** `CloseRetryCount` kali dengan jeda `CloseRetryDelayMs`.
  2. **Persisten:** setelah burst habis, coba lagi di setiap siklus timer (dengan backoff) **selama masih ada posisi**. State tetap `CLOSING`/`CLOSE_FAILED`, dashboard CRITICAL.
  3. Tidak pernah pindah ke `LOCKED`/`ARMED` selama masih ada posisi.

### K-03 [SEDANG] `RequireManualReset` dan `RequireManualResetAfterProfit` tidak punya pilihan nyata

- **Masalah:** keduanya "wajib true jika Lock=true" dan tidak bermakna jika Lock=false.
- **Resolusi:** input tetap ada (sesuai spek). Validator menolak kombinasi `Lock=true` + `RequireManualReset=false`.
- **Catatan:** kalau sebenarnya Anda menginginkan opsi auto-unlock (mis. buka kunci otomatis di hari berikutnya), itu fitur terpisah. Tidak saya buat tanpa permintaan.

### K-04 [SEDANG] Konfigurasi invalid → SAFE_DISABLED vs §37

- **Masalah:**
  - §19 meminta setting invalid ditolak.
  - §37 meminta kegagalan engine SL **tidak pernah** mematikan proteksi floating loss global.
  - Jika `MaxAggregateSLRiskIDR = 0` membuat seluruh EA SAFE_DISABLED, proteksi global ikut mati.
  - Lebih buruk lagi, `OnInit` yang mengembalikan `INIT_PARAMETERS_INCORRECT` **mencabut EA dari chart**.
- **Resolusi:**
  - Validasi per fitur: input invalid hanya mematikan fitur itu, dengan banner CRITICAL.
  - `SAFE_DISABLED` total hanya untuk mata uang ≠ IDR, atau saat semua fitur invalid.
  - EA tetap menempel di chart dengan pesan error besar, tidak mengembalikan INIT_FAILED.

### K-05 [SEDANG] Edge `ARMED → LOCKED` langsung di §16 tanpa pemicu

- **Resolusi:** edge itu ditafsirkan sebagai pemulihan dari state persisten saat startup (`VALIDATING → LOCKED`). Tidak ada jalur lain.

### K-06 [RENDAH] Penomoran ganda di §2

Butir 8–11 muncul dua kali. Kosmetik saja.

### K-07 [RENDAH] Posisi tanda minus

§20 menulis `Rp -xxx.xxx`, sedangkan §21 menulis `-Rp500.000`. Saya pakai format §21.

### K-08 [RENDAH] Daftar default §35 tidak lengkap

Tiga input tidak tercantum: `FailSafeWhenCompliantSLImpossible`, `CancelPendingOrdersWhenLocked`, dan kebijakan posisi baru saat LOCKED. Default-nya saya ambil dari §8.2 dan §7.

### K-09 [RENDAH] Nama state berbeda antara dashboard (§20) dan state machine (§16)

Label dashboard akan dipetakan dari state internal secara eksplisit.

---

## 4. Perilaku yang belum didefinisikan (gap)

### G-01 [TINGGI] Rebalance saat entry baru bisa menutup paksa posisi lama yang sedang rugi → **perlu keputusan (Q1)**

Contoh dengan budget Rp500.000:

1. P1 BUY 0,10 lot dibuka. SL dipasang di −Rp500.000 (seluruh budget).
2. Harga turun. P1 floating −Rp300.000.
3. User membuka P2 0,10 lot. Alokasi proporsional menjadi Rp250.000 + Rp250.000.
4. SL P1 harus berada di −Rp250.000 dari harga open, padahal pasar sudah di −Rp300.000. SL tidak bisa dipasang (sudah di atas Bid).
5. Akibatnya `SL_UNSATISFIABLE`, lalu fail-safe `CLOSE_POSITION` **menutup P1 di sekitar −Rp300.000**.

Ini konsisten dengan prinsip batas keras: P1 −300k ditambah potensi P2 250k = 550k > 500k. Tapi user mungkin tidak menduga bahwa **menambah posisi bisa memotong posisi lama**.

Dua kebijakan yang sama-sama menjaga Σrisiko ≤ budget:

- **(A) Spek harfiah:** alokasi proporsional murni. Posisi lama yang tidak muat ditutup.
- **(C) Lantai kelayakan (rekomendasi saya):**
  - Posisi lama mendapat minimal risiko yang masih bisa diwakili SL legal.
  - Sisa budget dibagi ke posisi lain.
  - Jika total tetap melebihi budget, posisi **terbaru** yang ditutup.
  - Ini sejalan dengan §37 "do not increase exposure": entry baru yang membuat budget jebol ditolak, posisi lama tidak dicairkan paksa.
  - Catatan jujur: pada (C), posisi lama yang rugi besar bisa mendapat SL sangat dekat pasar, sehingga peluang kena SL juga tinggi.

### G-02 [TINGGI] Perilaku `RebalanceExistingPositionsOnNewEntry = false` tidak didefinisikan

- **Usulan:**
  - SL lama tidak disentuh.
  - Posisi baru mendapat `budget − Σ risiko posisi lama`.
  - Jika sisa itu tidak cukup, fail-safe berlaku pada posisi baru.
- **Konsekuensi:** posisi pertama yang memakan seluruh budget membuat entry berikutnya selalu ditolak, kecuali user mengetatkan SL sendiri. Ini akan didokumentasikan di panel input.

### G-03 [SEDANG] `AutoApplySLToNewPositions = false` saat engine SL ON tidak didefinisikan

- **Usulan:** engine berjalan dalam mode *advisory*:
  - menghitung, menampilkan status patuh/tidak, dan memberi alert;
  - **tidak** pernah mengirim modifikasi atau fail-safe close.

### G-04 [TINGGI] Tidak ada input deviasi/slippage untuk close darurat

- **Masalah:**
  - Mode eksekusi per simbol dideteksi saat runtime (`SYMBOL_TRADE_EXEMODE`).
  - Pada Instant/Request execution, close dengan deviasi kecil kena requote (`10004`) tepat saat pasar bergerak cepat, yaitu saat proteksi paling dibutuhkan.
- **Usulan:**
  - Input baru `EmergencyCloseMaxDeviationPoints` dengan default longgar. Diabaikan otomatis pada Market execution.
  - Filling mode dideteksi dari `SYMBOL_FILLING_MODE`.

### G-05 [SEDANG] Arti `VerificationTimeoutMs` tidak didefinisikan

- **Usulan:** setelah retcode DONE, jika posisi masih terlihat setelah `VerificationTimeoutMs`, status dianggap "belum terverifikasi". Lalu volume dibaca ulang dan close dikirim ulang dengan penjaga duplikat (lihat G-15).

### G-06 [SEDANG] Celah waktu pending order

- **Masalah:**
  - §7 hanya menghapus pending order **setelah** masuk LOCKED. Pending bisa ter-fill selama `CLOSING`.
  - Spek juga tidak mengatur pending baru yang muncul selama LOCKED (dari EA lain).
- **Usulan:**
  - Jika lock akan berlaku untuk alasan trigger ini, hapus pending **sejak awal** close-all.
  - Selama LOCKED, terus hapus pending baru.
  - Jika lock OFF, pending tidak disentuh dan ini ditampilkan di dashboard.

### G-07 [SEDANG] Konfirmasi reset lewat `MessageBox()` memblokir EA

- **Masalah:** §18 meminta konfirmasi. `MessageBox()` bersifat modal: selama dialog terbuka, `OnTimer` tidak jalan dan **proteksi global berhenti**.
- **Usulan:** tombol dua langkah. Klik `RESET PROTECTION` mengubah tombol menjadi `KLIK LAGI UNTUK KONFIRMASI (10s)`. Tidak ada yang memblokir.

### G-08 [SEDANG] Mengganti input bisa jadi "jalan pintas" keluar dari LOCKED

- **Masalah:** mengubah input memicu `OnDeinit`/`OnInit`. User bisa menyetel `LockAfterGlobalTrigger=false` untuk lolos dari lock.
- **Usulan:**
  - LOCKED yang tersimpan **hanya** bisa dihapus oleh tombol reset. Ganti input, lepas/pasang EA, atau restart tidak menghapusnya.
  - Checksum konfigurasi hanya untuk log, tidak pernah memicu auto-unlock.
  - Kunci state disimpan per `login + server` supaya ganti akun di terminal yang sama tidak tercampur.
  - `GlobalVariablesFlush()` dipanggil setiap kali state berubah. Tanpa itu, crash atau VPS mati listrik bisa menghilangkan state yang belum tersimpan ke disk.

### G-09 [SEDANG] Tidak ada penjaga satu instance

- **Masalah:** EA yang dipasang di dua chart (atau dua terminal pada akun yang sama, mis. VPS + PC rumah) akan mengirim close/modify ganda dan saling berebut SL.
- **Usulan:**
  - Mutex berbasis Global Variable dengan heartbeat per akun. Instance kedua masuk `STANDBY` (hanya tampilan).
  - Dua terminal berbeda tidak bisa dicegah dari dalam EA; ini didokumentasikan.

### G-10 [SEDANG] Cakupan engine SL ke posisi EA lain → **perlu konfirmasi (Q2)**

§3 jelas untuk proteksi global (semua posisi). Untuk engine SL, cakupan account-wide berarti EA ini akan:

- memasang/mengetatkan SL pada posisi EA lain, dan bisa saling-modif dengan EA yang punya trailing sendiri;
- **menutup paksa** posisi EA grid/martingale yang sengaja tanpa SL, jika SL-nya tidak bisa memenuhi budget.

Apa pun pilihannya, akan ada pembatas laju modifikasi per tiket.

### G-11 [SEDANG] Alokasi "proporsional volume" tidak sebanding antar-simbol

Satu lot XAUUSD, EURUSD, dan indeks punya nilai yang sangat berbeda. Untuk basket satu simbol (contoh-contoh di spek memakai XAUUSD) ini tidak masalah.

- **Usulan:** default tetap `PROPORTIONAL_TO_VOLUME` sesuai spek. Peringatan tampil di dashboard bila basket berisi lebih dari satu simbol. Metode berbasis nilai nosional bisa jadi opsi versi berikut.

### G-12 [SEDANG] Risiko SL dalam IDR bergeser mengikuti kurs

- **Masalah:**
  - Harga SL XAUUSD tetap dalam USD. Nilai rugi dalam IDR mengikuti kurs USD/IDR saat itu (konversi internal `OrderCalcProfit`).
  - Jika rupiah melemah, loss teoretis di SL yang sama naik melewati budget.
  - Catatan: §13 "price movement" sebenarnya tidak relevan karena referensinya harga open; yang relevan adalah pergeseran kurs dan jarak legal.
- **Usulan:**
  - Input `SLBudgetSafetyMarginPct` (default 1%).
  - SL dipasang pada `budget × (1 − margin)`, dan baru diketatkan ulang jika risiko > budget.
  - Histeresis ini mencegah modifikasi berulang setiap kali kurs bergerak, sambil tetap menjaga budget sebagai batas keras.

### G-13 [SEDANG] Market tutup atau trading dinonaktifkan

- **Masalah:** modifikasi SL dan fail-safe close keduanya gagal (`10018`).
- **Usulan:**
  - Jangan spam request.
  - Tandai `UNPROTECTED (market closed)` dan ulangi ketika sesi buka.
  - Gagal hitung (`OrderCalcProfit` mengembalikan `false`) tidak memicu fail-safe close. Statusnya UNPROTECTED + CRITICAL + retry, karena belum terbukti *unsatisfiable*.

### G-14 [RENDAH] `SYMBOL_TRADE_STOPS_LEVEL = 0` tidak menjamin SL diterima

- **Usulan:**
  - Tambah buffer minimal 1 tick (bisa dikonfigurasi).
  - SL yang sedang berada di dalam freeze level ditandai "frozen, coba lagi", bukan *unsatisfiable*.

### G-15 [SEDANG] Risiko close ganda, terutama di akun netting

- **Masalah:**
  - Setelah `OrderSend` mengembalikan DONE, posisi bisa masih terlihat sesaat.
  - Di hedging, close ganda biasanya ditolak dengan aman.
  - Di **netting**, deal lawan dengan volume basi berisiko **membalik posisi** (membuka eksposur baru).
- **Usulan:**
  - Mode akun dideteksi lewat `ACCOUNT_MARGIN_MODE`.
  - Selalu isi `request.position`.
  - Volume dibaca ulang tepat sebelum kirim, dan tidak pernah melebihi volume posisi.
  - Registry *in-flight* per tiket dipakai bersama oleh close-all dan fail-safe.
  - Close dipecah jika volume melebihi `SYMBOL_VOLUME_MAX`.

### G-16 [SEDANG] AutoTrading mati tidak dideteksi

- **Masalah:** jika tombol Algo Trading mati, timer tetap jalan dan trigger tetap menyala, tapi semua order gagal (`10027`/`10026`).
- **Usulan:**
  - Cek `TERMINAL_TRADE_ALLOWED`, `MQL_TRADE_ALLOWED`, `ACCOUNT_TRADE_ALLOWED`, dan `ACCOUNT_TRADE_EXPERT`.
  - Jika ada yang mati, dashboard menampilkan CRITICAL "PROTEKSI TIDAK BISA EKSEKUSI".

### G-17 [RENDAH] Notifikasi

EA di VPS jarang dilihat, jadi alert di chart saja kurang berguna.

- **Usulan:** input `EnablePushNotifications = true` memakai push standar MT5 (`SendNotification`) untuk trigger, lock, CRITICAL, dan reset. Jika MetaQuotes ID belum diisi, gagalnya tidak berdampak apa-apa.

### G-18 [RENDAH] Urutan close dalam close-all tidak ditentukan

- **Usulan:** tutup dari |P/L| terbesar dulu. Deterministik, menghentikan rugi terbesar (trigger loss) atau mengamankan profit terbesar (trigger profit) lebih dulu.
- `TRADE_ACTION_CLOSE_BY` untuk pasangan hedge menjadi opsi versi berikut.

### G-19 [RENDAH] Tipe data input IDR

Semua input IDR bertipe `long`: bilangan bulat, aman sampai sekitar 9,2 × 10¹⁸. Formatter menangani nilai negatif dan nilai sangat besar.

### G-20 [SEDANG] Testabilitas vs "EA tidak boleh membuka order"

- **Masalah:** Strategy Tester hanya menjalankan satu EA, tidak bisa mensimulasikan trade manual atau EA lain, dan EA proteksi tidak boleh membuka posisi.
- **Usulan:**
  - Production EA **tidak punya jalur kode pembuka posisi sama sekali**, dan ini diaudit dengan grep.
  - Pengujian dipisah:
    1. Script unit-test untuk logika murni (formatter, evaluasi threshold, alokator, solver SL).
    2. EA *test harness* terpisah (tidak dirilis) yang meng-include modul yang sama dan membuka posisi bernaskah **hanya di tester**.
    3. Checklist manual di akun demo IDR untuk skenario multi-EA, restart, dan penolakan broker.

### G-21 [SEDANG] Engine SL berjalan bersamaan dengan close-all

- **Masalah:** spek diam. Jika engine SL memodifikasi atau fail-safe-close posisi yang sedang ditutup oleh close-all, terjadi aksi ganda.
- **Usulan:** engine SL **dijeda** selama `PROTECTION_TRIGGERED` / `CLOSING` / `LOCKED`. Proteksi global tetap jalan di semua state kecuali `SAFE_DISABLED`.

---

## 5. Keterbatasan yang harus dipahami user (sesuai spek, bukan bug)

### L-01 Proteksi floating bukan batas rugi harian

Rugi yang sudah realized (kena SL, fail-safe close, close-all sebelumnya) **tidak dihitung**.

Dengan lock OFF, rugi kumulatif tidak terbatas: −500k, close, entry lagi, −500k lagi, dan seterusnya. Dengan lock ON, reset manual mengembalikan budget penuh Rp500.000. Batas harian atau equity adalah fitur berbeda (**Q4**).

### L-02 Proteksi global hanya hidup selama terminal dan EA hidup serta terkoneksi

Jika VPS mati atau putus koneksi, satu-satunya pelindung adalah SL sisi server dari engine SL. Ini alasan kuat membiarkan engine SL tetap ON.

### L-03 Lonjakan spread saat rollover

Spread XAUUSD biasanya melebar di sekitar rollover harian. Posisi SELL dinilai di Ask, jadi floating loss melonjak. Trigger global bisa menyala **karena spread**, lalu close terjadi di spread terlebar.

Spek meminta trigger langsung, dan itu saya ikuti. Filter atau penundaan konfirmasi akan **menunda close darurat**, jadi tidak saya tambahkan tanpa permintaan.

### L-04 Threshold ≠ hasil realized

Sudah dibahas di §26 dan akan tampil jelas di panel input serta README.

### L-05 Kombinasi rebalance + fail-safe bisa menutup posisi

Lihat G-01. Perilaku ini akan dijelaskan di panel input.

### L-06 VPS bawaan MetaQuotes (Virtual Hosting) tidak cocok

Di hosting MetaQuotes, salinan EA berjalan tanpa UI. Tombol reset di terminal lokal tidak menjangkau instance di hosting, dan Global Variable-nya terpisah. Spek menyebut **Windows VPS (RDP)**, dan di sana semuanya berfungsi normal.

---

## 6. Kendala lingkungan pengerjaan

- Container cloud ini **tidak punya MetaEditor**.
- `download.mql5.com` **diblokir oleh kebijakan jaringan** environment (HTTP 403).
- Wine 9.0 tersedia via apt.

Deliverable §38 "compiles without errors" dan "test evidence" memerlukan salah satu dari:

1. **Menambahkan `download.mql5.com` ke Allowed domains** di pengaturan Network access environment (menu environment di title bar sesi → Edit). Setelah itu saya bisa mencoba compile headless via Wine (`metaeditor64.exe /compile ... /log`). Ini sering berhasil, tapi belum terjamin sampai dicoba.
2. **Anda yang compile** di MetaEditor (PC atau VPS), lalu kirim log error ke saya.

Run Strategy Tester dan uji di akun demo **tidak bisa** dijalankan dari sini dalam kondisi apa pun. Bukti uji akan berasal dari script unit-test, harness tester, dan checklist demo yang Anda jalankan.

---

## 7. Keputusan yang dibutuhkan dari user

**Q1. Saat budget SL tidak cukup karena ada entry baru, siapa yang dikorbankan?** (G-01)
- (A) Spek harfiah: posisi lama yang rugi dan tidak muat ditutup.
- (C) **Rekomendasi:** posisi lama dipertahankan semampunya; entry **baru** yang membuat budget jebol ditutup.

**Q2. Apakah engine SL juga berlaku untuk posisi dari EA lain?** (G-10)
Termasuk memasang SL dan menutup paksa jika tidak bisa memenuhi budget.
- Ya, semua posisi (spek harfiah).
- Hanya posisi manual (`magic = 0`). Proteksi floating global tetap mencakup semua posisi.

**Q3. Jalur compile?** (bagian 6)
- Anda tambahkan `download.mql5.com` ke allowlist dan saya coba compile via Wine.
- Anda compile sendiri di MetaEditor dan kirim log error.

**Q4. Konfirmasi: cukup proteksi floating saja (sesuai spek), tanpa batas rugi harian/realized?** (L-01)
- Ya, floating saja untuk versi 1.
- Tambahkan batas harian (realized + floating) sebagai fitur opsional.

---

## 8. Resolusi default yang akan diterapkan (kecuali ada keberatan)

| Kode | Resolusi |
|---|---|
| B-01, B-02, B-03 | Loss bertanda `max(0, −OrderCalcProfit(...))` dari `POSITION_PRICE_OPEN`. Validitas SL relatif ke Bid/Ask. Profit terkunci tidak mengimbangi risiko posisi lain. |
| B-04 | Total P/L dinormalisasi ke `ACCOUNT_CURRENCY_DIGITS`. Input IDR bertipe `long`. |
| B-05 | TP selalu dipertahankan saat modifikasi SL. |
| K-01 | Flag lock dipilih per alasan trigger. |
| K-02 | Retry burst, lalu retry persisten tanpa batas selama posisi masih ada. |
| K-03 | Kombinasi `RequireManualReset` yang invalid ditolak validator. |
| K-04 | Validasi per fitur. EA tidak pernah mencabut diri dari chart. |
| G-02, G-03 | Semantik "sisa budget" dan mode advisory. |
| G-04 | Input `EmergencyCloseMaxDeviationPoints` baru. Filling dideteksi otomatis. |
| G-06 | Pending dihapus sejak awal close-all (jika lock berlaku) dan terus dihapus selama LOCKED. |
| G-07 | Tombol reset dua langkah, non-blocking. |
| G-08 | Lock hanya dihapus oleh tombol reset. State disimpan per akun, dengan `GlobalVariablesFlush()`. |
| G-09 | Mutex satu instance per akun di satu terminal. |
| G-12 | `SLBudgetSafetyMarginPct = 1%` + histeresis. |
| G-13, G-14 | Penanganan market tutup, freeze level, dan gagal hitung tanpa fail-safe close. |
| G-15 | Registry in-flight, penjaga netting, pemecahan volume maksimal. |
| G-16 | Deteksi AutoTrading mati dengan status CRITICAL. |
| G-17 | Push notification MT5 ON. |
| G-18 | Urutan close: \|P/L\| terbesar dulu. |
| G-20 | Production EA tanpa jalur buka posisi. Test harness terpisah. |
| G-21 | Engine SL dijeda selama close-all/LOCKED. |

---

## 9. Langkah berikutnya (setelah Q1–Q4 dijawab)

Sesuai §41, sebelum menulis kode saya akan menyiapkan:

1. diagram arsitektur;
2. pemetaan requirement → modul (acceptance criteria per butir);
3. struktur file/modul;
4. state machine final (dengan resolusi K-01/K-05);
5. algoritma SL agregat persis (dengan B-01..B-03, G-01, G-12);
6. algoritma loss/profit global;
7. algoritma close/retry/verifikasi (K-02, G-05, G-15);
8. matriks uji.

Setelah itu implementasi dikerjakan modul demi modul, compile dan uji per komponen yang kritis keselamatannya, lalu audit akhir sesuai daftar di §41.

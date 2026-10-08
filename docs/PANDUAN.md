# Panduan Kerja — EVE IDR Risk Protector

Panduan ini menjawab permintaan Q3: langkah-langkah untuk compile, menguji, memasang, dan menjalankan EA ini, serta cara mengirim hasil atau error ke saya (Claude) agar bisa diperbaiki.

Alur kerja kita:

```text
Claude menulis kode  ->  Anda compile di MetaEditor  ->  ada error?  ->  kirim log ke Claude -> diperbaiki
                                       |
                                       v (0 error)
                   unit test (script) -> Strategy Tester (harness) -> akun DEMO IDR -> akun LIVE
```

> Container cloud tempat saya bekerja **tidak punya MetaEditor**, dan `download.mql5.com` diblokir oleh kebijakan jaringannya. Karena itu langkah **compile dan uji di MT5 dilakukan di komputer/VPS Anda**. Opsi agar saya bisa mencoba compile sendiri ada di bagian 10.

---

## 1. Yang dibutuhkan

- MetaTrader 5 dari Exness (desktop Windows, atau Windows VPS).
- Akun **DEMO** Exness dengan mata uang **IDR**, untuk pengujian. Setelah semua lolos, baru akun live.
- File dari repository ini (folder `MQL5`).

Cek mata uang akun: di MT5, *Toolbox → Trade*. Satuan saldo harus **IDR**. Kalau bukan IDR, EA akan masuk `SAFE_DISABLED` dan tidak melakukan apa-apa (ini disengaja).

---

## 2. Menyalin file ke MT5

1. Di MT5, buka **File → Open Data Folder**.
2. Masuk ke folder `MQL5` di dalam data folder itu.
3. Salin isi folder `MQL5` dari repository ke sana, **gabungkan** (merge):

   ```text
   repo/MQL5/Experts/EVE_IDR_RiskProtector.mq5          ->  <DataFolder>/MQL5/Experts/
   repo/MQL5/Experts/EVE_RiskProtector_TestHarness.mq5  ->  <DataFolder>/MQL5/Experts/
   repo/MQL5/Scripts/EVE_Risk_UnitTests.mq5             ->  <DataFolder>/MQL5/Scripts/
   repo/MQL5/Include/EVE_Risk/  (seluruh folder)        ->  <DataFolder>/MQL5/Include/EVE_Risk/
   ```

4. Di MT5, klik kanan **Navigator → Refresh**.

---

## 3. Compile di MetaEditor

1. Tekan **F4** di MT5 untuk membuka MetaEditor.
2. Di panel Navigator MetaEditor, buka lalu compile (**F7**) file-file ini satu per satu:
   - `Experts/EVE_IDR_RiskProtector.mq5`
   - `Scripts/EVE_Risk_UnitTests.mq5`
   - `Experts/EVE_RiskProtector_TestHarness.mq5`
3. Lihat tab **Errors** di bawah. Target: **0 errors**. Warnings sebaiknya juga dikirim ke saya.

### Jika ada error — kirim ke saya

- Di tab **Errors**, blok semua baris (Ctrl+A), klik kanan → **Copy**, lalu tempel ke chat.
- Atau kirim screenshot tab Errors. Teks lebih baik karena saya bisa membaca nomor baris dengan tepat.
- Sertakan juga nomor **build** MT5 Anda (*Help → About*).

Alternatif lewat command line (opsional), yang menghasilkan file log:

```bat
"C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:"<DataFolder>\MQL5\Experts\EVE_IDR_RiskProtector.mq5" /log
```

File `.log` muncul di sebelah file `.mq5`. Kirim isinya ke saya.

---

## 4. Menjalankan unit test (wajib sebelum demo)

1. Di MT5, buka chart apa saja.
2. Navigator → **Scripts** → seret `EVE_Risk_UnitTests` ke chart.
3. Hasil tampil di **Toolbox → Experts** dan di file `<DataFolder>\MQL5\Files\EVE_Risk_UnitTests_Result.txt`.
4. Baris terakhir harus `=== RESULT: N passed, 0 failed ===`.
5. Jika ada `FAIL`, kirim file hasil itu ke saya.

Script ini **tidak trading**. Ia menguji logika:
- format Rupiah;
- trigger loss/profit (−499.999 / −500.000 / −500.001, dan seterusnya);
- state machine;
- solver SL, termasuk contoh Anda: 0,02 lot rugi Rp200.000 + entry 0,05 lot menghasilkan SL basket 1997,47 dengan total Rp499.360;
- klasifikasi retcode;
- validasi konfigurasi.

---

## 5. Uji di Strategy Tester (test harness)

`EVE_RiskProtector_TestHarness` **hanya** berjalan di Strategy Tester. Ia memakai mesin proteksi yang sama, membuka posisi uji sesuai skenario, lalu mengecek invariant di setiap tick/timer.

1. *View → Strategy Tester*. Expert: `EVE_RiskProtector_TestHarness`. Simbol: XAUUSD. Mode: **Every tick based on real ticks**. Visual mode boleh ON.
2. **Deposit:** jika tester mengizinkan mata uang **IDR**, pilih IDR dan isi nominal dalam Rupiah. Jika tidak, pakai USD dengan `AllowNonIDRDepositForTest = true`, lalu isi `LossLimit`, `ProfitTarget`, dan `SLBudget` **dalam USD** (mis. 30).
3. Jalankan skenario 1–4 (input `Scenario`):
   - 1: basket multi-entry (0,02 + 0,05 + SELL);
   - 2: lock ON + entry saat LOCKED + reset;
   - 3: target profit;
   - 4: lock OFF + entry ulang.
4. Hasil ada di tab **Journal** (`HARNESS SUMMARY ... invariant FAILURES 0`) dan file `MQL5\Files\EVE_Risk_Harness_Result_S<n>.txt` milik agent tester (biasanya di `Tester\Agent-...\MQL5\Files`).
5. Kirim file hasil, atau potongan Journal, ke saya.

Keterbatasan tester: tidak bisa mensimulasikan trade manual, EA lain, restart terminal, maupun penolakan broker. Semua itu diuji di akun demo (bagian 6).

---

## 6. Uji di akun DEMO IDR

Ikuti checklist lengkap di `docs/TEST_PLAN.md` (bagian D). Ringkasnya:

1. Pasang EA di **satu** chart. Simbol apa saja; EA tetap menjaga **semua** posisi akun.
2. Saat memasang:
   - Tab **Common**: centang **Allow Algo Trading**.
   - Tab **Inputs**: isi nominal Rupiah. Untuk uji, pakai nilai kecil, mis. loss Rp50.000.
   - Tombol **Algo Trading** di toolbar harus hijau.
3. Cek dashboard: `Account Currency: IDR`, `State: ARMED`, `AutoTrading: OK`.
4. Buka posisi manual kecil (0,01) → SL otomatis terpasang dalam ≤ 1 detik.
5. Tambah entry dengan lot berbeda → SL semua posisi di simbol+arah yang sama berubah ke **satu harga bersama**.
6. Biarkan floating menyentuh limit kecil → semua posisi ditutup, log `CRITICAL ... GLOBAL FLOATING LOSS PROTECTION TRIGGERED`.
7. Cek file log: `MQL5\Files\EVE_RiskProtector_<login>_<tanggal>.log`.

---

## 7. Membaca dashboard

| Baris | Arti |
|---|---|
| Floating P/L | Total `POSITION_PROFIT` semua posisi akun (tanpa swap/komisi). |
| Loss Remaining | Jarak ke limit loss. Hijau → oranye (< 50%) → merah (< 20%). |
| SL Risk @ Stops | Total rugi teoretis jika semua SL kena, plus jumlah posisi terlindungi/tidak. |
| SL Status | `COMPLIANT` = semua posisi punya SL dan total ≤ budget. `ADJUSTING` = sedang memasang/mengetatkan SL. `UNPROTECTED` / `FAIL-SAFE CLOSE` = SL tidak mungkin dipasang. |
| State | `ARMED` normal, `CLOSING` sedang close-all, `CLOSING (FAILED-RETRYING)` close ditolak tapi terus dicoba, `LOCKED` menunggu reset, `STANDBY` instance kedua, `ERROR (SAFE_DISABLED)` mata uang bukan IDR. |
| Banner merah/oranye | Kondisi kritis yang perlu perhatian. |
| RESET PROTECTION | Muncul hanya saat LOCKED. Klik sekali, lalu klik lagi dalam 10 detik untuk konfirmasi. |

---

## 8. Deployment di Windows VPS (akun live)

1. Pasang MT5 Exness di VPS dan login akun **IDR**.
2. Salin file (bagian 2), compile (bagian 3), jalankan unit test (bagian 4).
3. *Tools → Options → Expert Advisors*: centang **Allow algorithmic trading**.
4. *Tools → Options → Notifications*: isi **MetaQuotes ID** dari aplikasi MT5 di HP agar push notification masuk.
5. Pasang EA di **satu** chart saja, lalu nyalakan tombol **Algo Trading**.
6. Biarkan MT5 tetap terbuka. Jangan logout dari sesi RDP dengan "Sign out"; cukup tutup jendela RDP (disconnect).
7. Agar MT5 otomatis jalan setelah VPS restart: buat shortcut `terminal64.exe` di folder `shell:startup`. MT5 akan membuka kembali chart dan EA terakhir. Setelah restart, EA memulihkan state (`LOCKED` atau close-all yang belum selesai) dari Global Variables.
8. Jangan gunakan **MetaQuotes Virtual Hosting** (migrasi EA bawaan MT5) untuk EA ini, karena tombol reset tidak berfungsi di sana.
9. Jangan jalankan EA ini di dua terminal untuk akun yang sama (mis. VPS dan PC rumah) secara bersamaan.

---

## 9. Troubleshooting

| Gejala | Penyebab & solusi |
|---|---|
| `ERROR (SAFE_DISABLED)` | Mata uang akun bukan IDR. Gunakan akun IDR. |
| Banner `PROTECTION CANNOT EXECUTE: AutoTrading ...` | Tombol Algo Trading mati atau *Allow Algo Trading* tidak dicentang. Nyalakan; EA otomatis melanjutkan. |
| `STANDBY` | EA terpasang di lebih dari satu chart. Hapus dari chart lain; instance ini mengambil alih otomatis. |
| `CLOSING (FAILED-RETRYING)` | Broker menolak close (market tutup, koneksi). EA terus mencoba. Cek log untuk retcode. |
| `CONFIG ERROR: ...` | Ada input tidak valid. Fitur terkait dimatikan atau memakai default aman. Perbaiki input. |
| Push tidak masuk | MetaQuotes ID belum diisi (bagian 8.4). |
| Posisi baru langsung ditutup | EA sedang `LOCKED` (lock ON) atau SL tidak bisa dipasang sesuai budget (fail-safe). Cek baris `Last Event` dan log. |

---

## 10. (Opsional) Agar saya bisa compile sendiri

Di pengaturan environment sesi Claude Code (menu environment di judul sesi → **Edit** → **Network access**), tambahkan `download.mql5.com` ke **Allowed domains**. Panduan resminya: https://code.claude.com/docs/en/cloud-environments#network-access.

Setelah itu saya bisa mencoba memasang MetaEditor lewat Wine dan compile headless. Ini sering berhasil, tapi belum terjamin sampai dicoba. Uji di MT5 (unit test, tester, demo) tetap dilakukan di sisi Anda.

---

## 11. Informasi yang perlu dikirim jika ada masalah

1. Isi tab **Errors** (saat compile) atau file `EVE_Risk_UnitTests_Result.txt`.
2. File log `EVE_RiskProtector_<login>_<tanggal>.log` (bagian yang relevan).
3. Screenshot dashboard.
4. Nilai input yang dipakai (tab Inputs → **Save** menghasilkan file `.set`, kirim file itu).
5. Build MT5 dan jenis akun (demo/live, hedging/netting; tertulis di log baris `ENV`).

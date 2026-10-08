# Panduan Kerja — EVE IDR Risk Protector v1.10

Panduan ini berisi langkah compile, uji, pemasangan, dan pemakaian EA, serta cara mengirim hasil atau error ke saya (Claude) agar bisa diperbaiki.

Alur kerja kita:

```text
Claude menulis kode  ->  Anda compile di MetaEditor  ->  ada error?  ->  kirim log ke Claude -> diperbaiki
                                       |
                                       v (0 error)
                   unit test (script) -> Strategy Tester (harness) -> akun DEMO IDR -> akun LIVE
```

> Container cloud tempat saya bekerja tidak punya MetaEditor, jadi **compile dan uji di MT5 dilakukan di komputer/VPS Anda**. Opsi agar saya bisa mencoba compile sendiri ada di bagian 12.

---

## 1. Yang dibutuhkan

- MetaTrader 5 dari Exness (Windows desktop atau Windows VPS).
- Akun **DEMO** Exness dengan mata uang **IDR** untuk pengujian.
- File dari paket ini (folder `MQL5`).

Mata uang akun harus **IDR**. Kalau bukan, EA masuk status `DISABLED` dan tidak melakukan apa-apa (disengaja).

---

## 2. Menyalin file ke MT5 (juga untuk update versi)

1. Di MT5, buka **File → Open Data Folder**, lalu masuk ke folder `MQL5`.
2. Salin isi folder `MQL5` dari paket ke sana dan **timpa** file lama:

   ```text
   paket/MQL5/Experts/*.mq5             ->  <DataFolder>/MQL5/Experts/
   paket/MQL5/Scripts/*.mq5             ->  <DataFolder>/MQL5/Scripts/
   paket/MQL5/Include/EVE_Risk/ (semua) ->  <DataFolder>/MQL5/Include/EVE_Risk/
   ```

   v1.10 menambah file baru `Include/EVE_Risk/TrailTPManager.mqh`. Pastikan file itu ikut tersalin.
3. Klik kanan **Navigator → Refresh**.

> Saat update dari v1.00: nama input berubah (label sekarang bahasa Inggris sederhana). File `.set` lama tidak terbaca otomatis, jadi isi ulang nilai Anda sekali, lalu **Save** sebagai `.set` baru.

---

## 3. Compile di MetaEditor

1. Tekan **F4** di MT5 untuk membuka MetaEditor.
2. Compile (**F7**) file-file ini:
   - `Experts/EVE_IDR_RiskProtector.mq5`
   - `Scripts/EVE_Risk_UnitTests.mq5`
   - `Experts/EVE_RiskProtector_TestHarness.mq5`
3. Target di tab **Errors**: **0 errors**.

Kalau ada error: di tab **Errors** tekan Ctrl+A, klik kanan → **Copy**, lalu tempel ke chat. Sertakan juga nomor build MT5 (*Help → About*).

---

## 4. Menjalankan unit test

1. Seret script `EVE_Risk_UnitTests` (Navigator → Scripts) ke chart mana pun.
2. Hasil tampil di **Toolbox → Experts** dan di file `MQL5\Files\EVE_Risk_UnitTests_Result.txt`.
3. Baris terakhir harus `=== RESULT: N passed, 0 failed ===`. Jika ada `FAIL`, kirim file hasil ke saya.

v1.10 menambah tes TP keranjang dan trailing stop (T26–T30).

---

## 5. Memasang EA

1. **Tools → Options → Expert Advisors:** centang **Allow algorithmic trading**.
2. Buka **satu** chart saja (simbol apa pun). EA tetap menjaga **semua** posisi akun.
3. Seret `EVE_IDR_RiskProtector` ke chart.
4. Tab **Common:** centang **Allow Algo Trading**.
5. Tab **Inputs:** isi nilai (lihat bagian 6). Untuk uji di demo, pakai nominal kecil.
6. Tombol **Algo Trading** di toolbar harus hijau.
7. Panel muncul dan badge di kanan atas panel berbunyi **ARMED** (hijau).

---

## 6. Pengaturan (tab Inputs)

Label persis seperti di MT5. Semua nominal dalam **Rupiah (IDR)**.

| Grup | Yang perlu diisi |
|---|---|
| **1. MAX TOTAL LOSS** | `Max total loss (IDR)`, mis. 500000. Semua posisi ditutup saat total floating rugi mencapai angka ini. |
| **2. PROFIT TARGET** | Nyalakan `Close all when total profit reaches the target`, isi `Profit target (IDR)`. |
| **3. AUTO STOP LOSS** | `Max total loss if all SLs are hit (IDR)`: total rugi jika semua SL kena. |
| **4. TRAILING STOP** | Nyalakan, isi kapan mulai, jarak, dan langkah (lihat bagian 7). |
| **5. TAKE PROFIT** | Nyalakan, isi `Close the basket at this profit (IDR)` (lihat bagian 8). |
| **6. WHEN THE EA IS LOCKED** | Hanya berlaku jika lock dinyalakan di grup 1/2. |
| **7. PANEL AND ALERTS** | Posisi panel dan notifikasi. |
| **8. ADVANCED** | Biarkan default jika ragu. |

Istilah **keranjang (basket)** = semua posisi dengan **simbol dan arah yang sama**, mis. semua BUY XAUUSD.

---

## 7. Cara kerja trailing stop

Contoh pengaturan: mulai Rp100.000, jarak Rp50.000, langkah Rp10.000. Keranjang BUY XAUUSD:

| Profit keranjang | Yang dilakukan EA |
|---|---|
| Rp60.000 | Belum apa-apa (belum mencapai Rp100.000). |
| Rp100.000 | Trailing mulai. SL semua posisi keranjang dipindah ke harga yang mengunci **Rp50.000** (100.000 − 50.000). |
| Rp130.000 | SL maju ke harga yang mengunci **Rp80.000** (naik ≥ Rp10.000). |
| Rp135.000 | Tidak digeser (kenaikan kunci baru Rp5.000, kurang dari langkah). |
| Turun ke Rp90.000 | SL **tidak mundur**. Kalau harga terus turun, SL kena dan profit terkunci ± Rp80.000. |

Catatan:
- Semua entry dalam keranjang memakai **satu harga SL yang sama**.
- SL hanya pernah bergerak ke arah yang lebih aman. Opsi *Never move an SL further away* otomatis dipaksa ON saat trailing aktif.
- Jika jarak terlalu dekat untuk aturan broker, SL ditaruh di posisi terdekat yang diizinkan broker.

---

## 8. Cara kerja basket TP

Contoh: TP Rp300.000, keranjang BUY XAUUSD berisi 0,02 lot @2006,25 dan 0,05 lot @2000,20.

- EA menghitung satu harga TP di mana **total** profit keranjang = Rp300.000, yaitu **2004,61** (profit Rp300.320).
- TP itu dipasang di **kedua** posisi (di server broker, tetap jalan walau VPS mati).
- Kalau Anda menambah entry, TP dihitung ulang untuk seluruh keranjang.
- Kalau profit keranjang sudah ≥ target tapi TP belum terpasang (mis. terlalu dekat harga), EA langsung menutup keranjang itu.
- Selama TP ON, TP yang Anda ubah manual akan disamakan lagi oleh EA. Matikan TP jika ingin mengatur TP sendiri.

Bedanya dengan **Profit target** (grup 2): profit target melihat total **semua posisi di akun** lalu menutup semuanya. Basket TP bekerja **per keranjang** dan dipasang di server.

---

## 9. Membaca panel

```text
EVE RISK PROTECTOR v1.10              [ARMED] [-]
ACCOUNT ──────────────────────────────────────────
Currency                                     IDR
Balance                              Rp1.600.582
Equity                               Rp1.600.582
Floating                                     Rp0   (besar, hijau/merah)
Positions                     0 open | 0 pending
PROTECTION ───────────────────────────────────────
Max total loss                  Rp0 / Rp500.000
▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░   (bar pemakaian)
Profit target                   Rp0 / Rp300.000
Auto SL (loss if hit)           Rp0 / Rp800.000
SL status                           NO POSITIONS
Trailing stop                                OFF
Basket TP                                    OFF
SYSTEM ───────────────────────────────────────────
Auto Trading                        OK (HEDGING)
Lock after close           Loss OFF | Profit OFF
Last event          15:30:23 All closed - armed
```

- Tombol **[-]** di kanan atas memperkecil panel menjadi judul saja. **[+]** membukanya lagi.
- Pindahkan panel lewat input `Panel position` (Top left / Top right / Bottom left / Bottom right) dan jaraknya.
- Panel menyesuaikan skala tampilan Windows (125%, 150%, dst.), dan angka selalu rata kanan sehingga tidak bertumpuk.
- Badge status: **ARMED** (normal), **CLOSING ALL**, **CLOSE FAILED** (terus dicoba), **LOCKED**, **STANDBY**, **DISABLED**.
- Kotak berwarna di bawah muncul jika ada hal penting (mis. Algo Trading mati, pengaturan salah).
- Saat **LOCKED**, muncul tombol **RESET PROTECTION**. Klik sekali, lalu klik lagi dalam 10 detik.

---

## 10. Soal delay

Delay dari menekan tombol sampai broker mengeksekusi sebagian besar berasal dari **jaringan** (WiFi rumah → server broker). Yang sudah dilakukan EA di v1.10:

- **Send orders in parallel = ON:** semua perintah close/SL/TP dalam satu siklus dikirim bersamaan. Close-all 5 posisi tidak lagi menunggu satu per satu.
- SL/TP untuk posisi baru dipasang **langsung** saat posisi muncul (sebelumnya menunggu timer).
- Pengecekan seluruh akun tetap jalan tiap 250 ms walau chart tidak ada tick.

Untuk delay paling kecil, jalankan MT5 di **Windows VPS dekat server broker** (bagian 11).

---

## 11. Deployment di Windows VPS (akun live)

1. Pasang MT5 Exness di VPS, login akun **IDR**.
2. Salin file (bagian 2), compile (bagian 3), jalankan unit test (bagian 4).
3. **Tools → Options → Expert Advisors:** centang **Allow algorithmic trading**.
4. **Tools → Options → Notifications:** isi **MetaQuotes ID** agar push masuk ke HP.
5. Pasang EA di **satu** chart, nyalakan **Algo Trading**.
6. Tutup jendela RDP dengan *disconnect* (jangan *Sign out*).
7. Agar MT5 otomatis jalan setelah VPS restart: buat shortcut `terminal64.exe` di folder `shell:startup`.
8. Jangan gunakan **MetaQuotes Virtual Hosting**, dan jangan jalankan EA ini di dua terminal untuk akun yang sama.

---

## 12. Troubleshooting

| Gejala | Penyebab & solusi |
|---|---|
| Badge `DISABLED` | Mata uang akun bukan IDR. |
| Kotak `CANNOT TRADE: Algo Trading button is OFF` | Nyalakan tombol Algo Trading. EA otomatis melanjutkan. |
| Badge `STANDBY` | EA terpasang di lebih dari satu chart. Hapus dari chart lain. |
| Badge `CLOSE FAILED` | Broker menolak close (market tutup, koneksi). EA terus mencoba. Cek log. |
| Kotak `SETTINGS ERROR: ...` | Ada input tidak valid. Fitur terkait dimatikan atau memakai nilai aman. |
| Posisi baru langsung ditutup | EA `LOCKED`, SL tidak bisa dipasang sesuai batas (fail-safe), atau profit keranjang sudah ≥ TP. Cek `Last event` dan log. |
| TP yang saya ubah kembali sendiri | Fitur Take profit ON. Matikan jika ingin TP manual. |
| Push tidak masuk | MetaQuotes ID belum diisi. |

Agar saya bisa mencoba compile sendiri: tambahkan `download.mql5.com` ke **Allowed domains** di pengaturan environment sesi Claude Code (menu environment → **Edit** → **Network access**). Panduan resmi: https://code.claude.com/docs/en/cloud-environments#network-access.

---

## 13. Informasi yang perlu dikirim jika ada masalah

1. Isi tab **Errors** (saat compile) atau file `EVE_Risk_UnitTests_Result.txt`.
2. File log `MQL5\Files\EVE_RiskProtector_<login>_<tanggal>.log` (bagian yang relevan).
3. Screenshot panel.
4. File `.set` input yang dipakai (tab Inputs → **Save**).

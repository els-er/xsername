# Changelog

## v1.12 — 2026-10-08

Panel lebih kecil, berdasarkan masukan user (panel v1.11 menutupi hampir seluruh tinggi chart). Logika proteksi tidak berubah.

- **Panel ringkas:**
  - Huruf lebih kecil: label/angka 9 → 6 pt, judul 10 → 6,5 pt, angka Floating 14 → 8,5 pt.
  - Jarak antarbaris, header, badge, tombol, dan bar progres dirapatkan.
  - Baris *Currency* digabung ke judul bagian (`ACCOUNT (IDR)`); baris merah muncul hanya jika mata uang bukan IDR.
  - Catatan dua baris di bawah panel dihapus (isinya ada di PANDUAN).
  - Teks dipersingkat: `ON - starts at Rp…`, `Basket TP Rp…`.
  - Hasil simulasi tata letak di skala Windows 150%: 450×705 px → kira-kira 290×375 px (tinggi ±53%, lebar ±64%).
- **Input baru `Panel size (%)`** (grup 7, default 100, rentang 50–200): mengalikan ukuran huruf dan jarak. Nilai di luar rentang → error di panel dan memakai 100.
- **Tombol minimize** menerima klik sedikit di sekitarnya (tombolnya kini lebih kecil).
- **Unit test:** validasi `Panel size (%)` (70 diterima, 10 ditolak → 100).

## v1.11 — 2026-10-08

Perbaikan compile v1.10. Tidak ada perubahan perilaku.

- **Compile:** v1.10 gagal di ketiga program (33 error, 25 warning). Semuanya berasal dari satu sebab:
  - Fungsi bantu warna di `RiskDashboard.mqh` bernama `ARGB`, sama dengan macro `ARGB(a,r,g,b)` milik `Canvas.mqh` bawaan MT5.
  - Setiap pemanggilannya dibaca sebagai macro, sehingga class panel rusak dan error berantai ke `RiskProtectorApp.mqh`.
  - Fungsi diganti nama menjadi `ToArgb`. Tidak ada nama lain di kode EA yang sama dengan macro atau class dari library standar yang dipakai panel.
- **Versi:** 1.11 (EA, harness, panel).

## v1.10 — 2026-10-08

Berdasarkan masukan user setelah uji v1.00 di MT5. Compile gagal di MT5 user; diperbaiki di v1.11.

- **Input:**
  - Semua label input diganti bahasa Inggris sederhana dengan saklar ON/OFF.
  - Grup bernomor 1–8; pengaturan teknis ada di grup **8. ADVANCED**.
  - Input yang tidak punya pilihan nyata dihapus (`RequireManualReset*`, `ProtectionScope`); perilakunya tetap sama.
- **Trailing stop (baru):** per keranjang (simbol + arah), dalam Rupiah. Mulai pada profit tertentu, mengunci "profit − jarak", hanya maju, bergeser minimal per langkah.
- **Basket TP (baru):** satu harga TP untuk semua entry keranjang pada profit Rupiah tertentu. Keranjang ditutup bila target sudah tercapai tapi TP belum terpasang.
- **Eksekusi:**
  - SL dan TP diubah dalam satu perintah; permintaan dalam satu siklus digabung.
  - Mode kirim paralel (`OrderSendAsync`) dengan pelacakan `request_id` lewat `OnTradeTransaction`.
  - Kegagalan trailing/TP tidak menunda engine SL.
- **Latensi:** SL/trailing/TP dijalankan langsung saat ada event trade dan saat tick (maks tiap 200 ms), tidak hanya di timer.
- **Panel:** digambar ulang dengan CCanvas.
  - Menyesuaikan skala DPI Windows; teks diukur sehingga tidak bertumpuk.
  - Bagian ACCOUNT / PROTECTION / SYSTEM, bar progres, badge status.
  - Tombol minimize, pilihan pojok, tombol RESET yang digambar.
- **Bahasa:** dashboard, banner, notifikasi, dan pesan validasi memakai bahasa Inggris sederhana.
- **Pengujian:**
  - Unit test T26–T30 (TP/trailing) dan validasi config baru.
  - Harness skenario 5 + invariant INV5 (SL tidak pernah menjauh).
  - Cek silang Python diperluas.

## v1.00 — 2026-10-08

Rilis pertama (belum di-compile di lingkungan pengembangan; lihat `docs/FINAL_AUDIT.md`).

- **Feature A:** global floating loss protection untuk semua posisi akun. Hanya `POSITION_PROFIT`, threshold crossing, close-all dengan verifikasi.
- **Feature B:** global floating profit auto-close (total net), ON/OFF terpisah.
- **Feature C:** lock mode dengan flag per alasan trigger.
  - Kebijakan posisi baru saat LOCKED.
  - Penghapusan pending order.
  - Reset manual dua klik.
  - Lock persisten setelah restart.
- **Feature D:** aggregate IDR SL engine.
  - Alokasi `BASKET_COMMON_PRICE` (default, keputusan user Q1) atau `PROPORTIONAL_TO_VOLUME`.
  - Loss dihitung bertanda dan di-clamp dari harga open.
  - Hanya mengetatkan; SL yang mengunci profit tidak pernah dilebarkan.
  - Fail-safe close.
  - Histeresis margin terhadap kurs.
- **Eksekusi:**
  - Registry per tiket (anti-duplikat).
  - Retry cepat, lalu retry persisten.
  - Verifikasi setiap operasi.
  - Rotasi filling mode.
  - Pecahan `VOLUME_MAX` dan aman untuk netting.
  - TP selalu dipertahankan.
- **Monitoring:** OnTick + OnTimer (250 ms) + OnTradeTransaction.
- **Infrastruktur:**
  - Persistensi Global Variables (per login + server, flush).
  - Penjaga satu instance.
  - Dashboard Rupiah.
  - Log harian.
  - Push notification.
- **Default:** `LockAfterGlobalTrigger = false` (keputusan user Q4; spek asli `true`).
- **Pengujian:** unit test script, test harness Strategy Tester, cek silang Python.

# Changelog

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

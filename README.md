# SANTRI DEPROK

Aplikasi keuangan Haul KH. Ahmad Baehaqi Sholihin. Project ini terpisah dari project lama.

## Jalankan lokal
npm install
npm run dev

Buka http://localhost:3000.

## Status
- Dashboard adalah pratinjau UI dengan data contoh lokal.
- Draft migrasi: supabase/migrations/20261009_santri_deprok_finance.sql
- Rencana uji: docs/keuangan/TAHAP-2-DATABASE.md
- Pemeriksaan statis: scripts/audit-finance-static.ps1
- Belum terhubung ke Supabase, belum menerapkan migrasi, belum diuji terhadap PostgreSQL, dan belum dideploy.

## Prinsip
- Akun tabungan sapi dan kas umum terpisah untuk tiap periode tahunan.
- Saldo awal Rp0; transaksi pending tidak masuk saldo.
- Setoran sapi mensyaratkan opt-in eksplisit dan peserta aktif.
- Transaksi terkonfirmasi tidak dihapus/diubah; koreksi memakai counter-entry dan audit.
- Pencatat tidak boleh menyetujui transaksinya sendiri.
- Role: admin, bendahara_sapi, bendahara_kas, pemeriksa, jamaah.
- Tidak menggunakan Firebase, OTP, atau Twilio.

Jangan menjalankan draft migrasi di database produksi. Review dan uji di database staging terpisah wajib dilakukan.

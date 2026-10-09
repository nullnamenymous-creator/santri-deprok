# SANTRI DEPROK — Tahap 2: Fondasi database dan hardening

Status: DRAFT STATIS. Migrasi belum diterapkan ke database mana pun.

## Domain model
- sd_haul_periods: periode tahunan dengan status OPEN/CLOSED.
- sd_fund_accounts: tepat satu akun SAPI dan satu KAS_UMUM per periode; saldo awal wajib nol.
- sd_members: profil jamaah; nomor telepon tidak tersedia lewat SELECT langsung.
- sd_user_roles: role global atau role yang dibatasi pada akun.
- sd_sapi_participants: opt-in eksplisit per jamaah/periode.
- sd_financial_transactions: buku besar; pending tidak masuk saldo.
- sd_transaction_reversals: permintaan koreksi dan keputusan pihak lain.
- sd_audit_log: audit append-only.

## RPC terkontrol
- sd_admin_create_period: admin membuat periode dan kedua akun Rp0 secara atomik.
- sd_admin_create_member: admin membuat profil jamaah; dapat mengaitkan Auth user.
- sd_admin_set_user_role: admin menetapkan/mencabut role, memvalidasi tipe akun, dan mencegah pencabutan admin terakhir.
- sd_admin_close_period: mengunci akun, menolak penutupan jika masih ada transaksi atau reversal pending, lalu menutup periode.
- sd_set_sapi_opt_in: bendahara sapi/admin mencatat opt-in/opt-out dengan audit.
- sd_confirm_transaction dan sd_reject_transaction: keputusan terpisah dari pencatatan, tidak boleh dilakukan pencatat sendiri.
- sd_request_reversal dan sd_review_reversal: reversal perlu pemohon dan penilai berbeda; transaksi sumber tidak diubah.

## Keamanan yang dirancang
1. RLS aktif di seluruh tabel dan akses role operasional dibatasi pada akun.
2. Klien tidak diberi UPDATE/DELETE langsung pada buku besar.
3. Composite foreign key memastikan akun dan periode pada transaksi/peserta cocok.
4. Akun dikunci selama konfirmasi/reversal untuk serialisasi pemeriksaan saldo.
5. Trigger INSERT mengunci akun dan membaca periode dengan row lock agar INSERT tidak berlomba dengan penutupan periode.
6. Perubahan role admin diserialisasi memakai transaction-scoped advisory lock agar dua pencabutan bersamaan tidak menghapus admin terakhir.
7. Transaksi terkonfirmasi immutable; koreksi memakai counter-entry yang terhubung ke sumber.
8. Counter-entry hanya dapat dibuat oleh alur reversal yang sah; koreksi berantai ditolak.
9. Audit log tidak bisa diubah/dihapus melalui jalur SQL biasa; detail audit masih perlu review lebih lanjut agar cukup untuk audit operasional.
10. Fungsi SECURITY DEFINER memakai search_path kosong; akses EXECUTE dicabut dari PUBLIC lalu diberikan secara eksplisit.
11. Profil jamaah dibuat melalui RPC admin, bukan INSERT bebas oleh klien.
12. Tidak ada kredensial, token, atau nilai rahasia di file migrasi.

## Bootstrap admin pertama
Tidak ada RPC yang dapat membuat admin pertama dari pengguna non-admin. Ini disengaja agar pengguna biasa tidak dapat menaikkan role sendiri.
1. Setelah staging terpisah disetujui dan dibuat, buat satu pengguna Auth melalui dashboard operator.
2. Salin UUID pengguna tersebut dari daftar Auth.
3. Review file BOOTSTRAP-ADMIN-MANUAL.sql.example; ganti placeholder UUID dengan UUID pengguna Auth yang benar.
4. Jalankan hanya pada database staging yang benar, oleh operator berwenang, dan catat persetujuannya.
5. Login sebagai admin tersebut, lalu gunakan RPC untuk membuat periode, profil jamaah, dan role berikutnya.
6. Jangan pernah mengeksekusi file contoh di produksi atau menyimpan service-role key di aplikasi browser.

## Batasan sebelum staging
- Belum ada parser atau eksekusi PostgreSQL sungguhan. Pemeriksaan saat ini hanya statis.
- SQL adalah draft satu-kali migrasi, bukan skrip untuk dijalankan berulang manual.
- RLS, privileges, semua RPC, dan race condition harus diuji dengan akun berbeda pada database staging kosong.
- Penutupan periode dan review reversal harus diuji untuk locking/deadlock dan concurrency.
- Model akses jamaah, kebutuhan akses nomor telepon, storage receipt, serta retensi audit perlu review final.
- Tidak ada Supabase project yang dihubungkan/diubah, tidak ada branch dibuat, dan tidak ada deployment.

## Skenario pengujian staging
1. Admin pertama hanya bisa dibuat lewat prosedur operator; pengguna non-admin gagal memanggil semua RPC admin.
2. Buat periode: akun SAPI dan KAS_UMUM dibuat bersamaan dengan saldo Rp0; tahun duplikat ditolak.
3. Pending tidak mengubah saldo; transaksi baru tidak bisa langsung berstatus CONFIRMED.
4. Dua OUT paralel melebihi saldo: saldo tidak boleh negatif.
5. Pencatat tidak bisa menyetujui atau menolak transaksi sendiri.
6. Opt-in/opt-out, anggota nonaktif, akun salah, dan periode tertutup diuji.
7. Role akun A tidak dapat membaca/menulis akun B atau mengakses akun bertipe salah.
8. Profil jamaah dan nomor telepon tidak bocor ke jamaah lain.
9. Reversal diri sendiri/pencatat sumber gagal; dua permintaan aktif untuk sumber yang sama tidak bisa dibuat.
10. Reversal menghasilkan satu counter-entry; sumber immutable; reversal berantai ditolak.
11. Periode tidak dapat ditutup jika ada transaksi/reversal pending.
12. Audit log merekam pembuatan periode, akun, jamaah, role, transaksi, opt-in, penolakan, dan reversal.
13. Uji double-submit, idempotency, rollback, deadlock, dan timeout.

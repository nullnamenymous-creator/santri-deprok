-- SANTRI DEPROK: finance foundation (DRAFT; not applied)
-- Requires Supabase Auth and PostgreSQL. Review and test in isolated staging before use.
begin;
create extension if not exists pgcrypto;

create table if not exists public.sd_haul_periods (
 id uuid primary key default gen_random_uuid(), year integer not null unique check(year between 2000 and 2200),
 name text not null, starts_on date not null, ends_on date not null,
 status text not null default 'OPEN' check(status in ('OPEN','CLOSED')),
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 closed_by uuid references auth.users(id), closed_at timestamptz,
 check(starts_on<=ends_on),
 check((status='OPEN' and closed_at is null) or (status='CLOSED' and closed_at is not null))
);
create table if not exists public.sd_members (
 id uuid primary key default gen_random_uuid(), auth_user_id uuid unique references auth.users(id),
 full_name text not null check(length(trim(full_name)) between 2 and 160), phone text,
 is_active boolean not null default true, created_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists public.sd_user_roles (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check(role in ('admin','bendahara_sapi','bendahara_kas','pemeriksa','jamaah')),
 account_id uuid, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 check((role in ('admin','jamaah') and account_id is null) or (role in ('bendahara_sapi','bendahara_kas','pemeriksa') and account_id is not null))
);
create unique index if not exists sd_user_roles_unique_global on public.sd_user_roles(user_id,role) where account_id is null;
create unique index if not exists sd_user_roles_unique_scoped on public.sd_user_roles(user_id,role,account_id) where account_id is not null;
create table if not exists public.sd_fund_accounts (
 id uuid primary key default gen_random_uuid(), period_id uuid not null references public.sd_haul_periods(id),
 account_type text not null check(account_type in ('SAPI','KAS_UMUM')), display_name text not null,
 opening_balance numeric(18,2) not null default 0 check(opening_balance=0), is_active boolean not null default true,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(period_id,account_type), unique(id,account_type), unique(id,period_id)
);
alter table public.sd_user_roles add constraint sd_user_roles_account_fk foreign key(account_id) references public.sd_fund_accounts(id);
create table if not exists public.sd_sapi_participants (
 id uuid primary key default gen_random_uuid(), period_id uuid not null references public.sd_haul_periods(id),
 account_id uuid not null references public.sd_fund_accounts(id), member_id uuid not null references public.sd_members(id),
 opt_in boolean not null default false, opt_in_at timestamptz, opt_in_recorded_by uuid references auth.users(id),
 opt_out_at timestamptz, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 unique(period_id,member_id),
 foreign key(account_id,period_id) references public.sd_fund_accounts(id,period_id),
 check((opt_in=false and opt_in_at is null and opt_in_recorded_by is null) or (opt_in=true and opt_in_at is not null and opt_in_recorded_by is not null))
);
create table if not exists public.sd_financial_transactions (
 id uuid primary key default gen_random_uuid(), account_id uuid not null references public.sd_fund_accounts(id),
 period_id uuid not null references public.sd_haul_periods(id), participant_id uuid references public.sd_sapi_participants(id),
 member_id uuid references public.sd_members(id), transaction_type text not null check(transaction_type in ('SETORAN_SAPI','KAS_MASUK','KAS_KELUAR','KOREKSI')),
 direction text not null check(direction in ('IN','OUT')), amount numeric(18,2) not null check(amount>0),
 note text not null check(length(trim(note)) between 3 and 500), receipt_path text,
 status text not null default 'PENDING' check(status in ('PENDING','CONFIRMED','REJECTED')),
 recorded_by uuid not null references auth.users(id), recorded_at timestamptz not null default now(),
 verified_by uuid references auth.users(id), verified_at timestamptz,
 idempotency_key uuid not null default gen_random_uuid(), reversal_of uuid references public.sd_financial_transactions(id),
 unique(idempotency_key),
 foreign key(account_id,period_id) references public.sd_fund_accounts(id,period_id),
 check((status='CONFIRMED' and verified_by is not null and verified_at is not null and verified_by<>recorded_by)
    or (status<>'CONFIRMED' and verified_by is null and verified_at is null)),
 check((transaction_type='SETORAN_SAPI' and direction='IN' and participant_id is not null and member_id is not null)
    or (transaction_type='KAS_MASUK' and direction='IN' and participant_id is null)
    or (transaction_type='KAS_KELUAR' and direction='OUT' and participant_id is null)
    or (transaction_type='KOREKSI' and participant_id is null))
);
create unique index if not exists sd_transactions_single_reversal on public.sd_financial_transactions(reversal_of) where reversal_of is not null;
create table if not exists public.sd_transaction_reversals (
 id uuid primary key default gen_random_uuid(), transaction_id uuid not null references public.sd_financial_transactions(id),
 requested_by uuid not null references auth.users(id), request_note text not null check(length(trim(request_note))>=5),
 status text not null default 'PENDING' check(status in ('PENDING','APPROVED','REJECTED')),
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz, review_note text,
 counter_transaction_id uuid references public.sd_financial_transactions(id), created_at timestamptz not null default now(),
 check((status='PENDING' and reviewed_by is null and reviewed_at is null and counter_transaction_id is null)
    or (status='APPROVED' and reviewed_by is not null and reviewed_at is not null and counter_transaction_id is not null and reviewed_by<>requested_by)
    or (status='REJECTED' and reviewed_by is not null and reviewed_at is not null and counter_transaction_id is null and reviewed_by<>requested_by and length(trim(coalesce(review_note,'')))>=5))
);
create unique index if not exists sd_reversal_one_active_request
 on public.sd_transaction_reversals(transaction_id) where status in ('PENDING','APPROVED');
create table if not exists public.sd_audit_log (
 id bigint generated always as identity primary key, actor_user_id uuid references auth.users(id),
 action text not null, entity_table text not null, entity_id text, details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create index if not exists sd_transactions_account_status_idx on public.sd_financial_transactions(account_id,status,recorded_at desc);
create index if not exists sd_audit_entity_idx on public.sd_audit_log(entity_table,entity_id,created_at desc);

create or replace function public.sd_has_role(p_roles text[],p_account_id uuid default null)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(select 1 from public.sd_user_roles r where r.user_id=auth.uid() and
   (r.role='admin' or (r.role=any(p_roles) and
     ((p_account_id is not null and r.account_id=p_account_id) or
      (p_account_id is null and r.account_id is null and r.role=any(p_roles))))))
$$;
create or replace function public.sd_is_own_member(p_member_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.sd_members m where m.id=p_member_id and m.auth_user_id=auth.uid()) $$;
create or replace function public.sd_account_type(p_account_id uuid)
returns text language sql stable security definer set search_path=''
as $$ select a.account_type from public.sd_fund_accounts a where a.id=p_account_id $$;

create or replace function public.sd_audit_row()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_id text; v_payload jsonb;
begin
 if TG_OP='DELETE' then v_id:=to_jsonb(OLD)->>'id'; v_payload:=jsonb_build_object('operation','DELETE');
 else v_id:=to_jsonb(NEW)->>'id'; v_payload:=jsonb_build_object('operation',TG_OP); end if;
 insert into public.sd_audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(auth.uid(),'ROW_'||TG_OP,TG_TABLE_NAME,v_id,v_payload);
 if TG_OP='DELETE' then return OLD; else return NEW; end if;
end; $$;

create or replace function public.sd_guard_transaction_mutation()
returns trigger language plpgsql set search_path=''
as $$
begin
 if TG_OP='DELETE' then raise exception 'Transaksi tidak boleh dihapus; gunakan prosedur koreksi.'; end if;
 if OLD.status='CONFIRMED' then raise exception 'Transaksi terkonfirmasi bersifat immutable.'; end if;
 if (to_jsonb(NEW)-'status'-'verified_by'-'verified_at') is distinct from (to_jsonb(OLD)-'status'-'verified_by'-'verified_at') then
  raise exception 'Transaksi yang sudah dibuat tidak boleh diubah; buat transaksi baru.';
 end if;
 if OLD.status<>NEW.status and not (OLD.status='PENDING' and NEW.status in ('CONFIRMED','REJECTED')) then raise exception 'Perubahan status tidak valid.'; end if;
 return NEW;
end; $$;

create or replace function public.sd_confirm_transaction(p_transaction_id uuid)
returns public.sd_financial_transactions language plpgsql security definer set search_path=''
as $$
declare v_tx public.sd_financial_transactions%rowtype; v_account public.sd_fund_accounts%rowtype;
 v_period public.sd_haul_periods%rowtype; v_balance numeric(18,2);
begin
 if auth.uid() is null then raise exception 'Autentikasi diperlukan.'; end if;
 select * into v_tx from public.sd_financial_transactions where id=p_transaction_id for update;
 if not found then raise exception 'Transaksi tidak ditemukan.'; end if;
 if v_tx.status<>'PENDING' then raise exception 'Transaksi bukan pending.'; end if;
 if v_tx.recorded_by=auth.uid() then raise exception 'Pencatat tidak boleh menyetujui transaksi sendiri.'; end if;
 select * into v_account from public.sd_fund_accounts where id=v_tx.account_id for update;
 select * into v_period from public.sd_haul_periods where id=v_tx.period_id for share;
 if not v_account.is_active or v_period.status<>'OPEN' or v_account.period_id<>v_tx.period_id then raise exception 'Akun atau periode tidak aktif/tidak cocok.'; end if;
 if v_account.account_type='SAPI' then
  if not public.sd_has_role(array['admin','pemeriksa'],v_account.id) and not public.sd_has_role(array['bendahara_sapi'],v_account.id) then raise exception 'Tidak berwenang memverifikasi akun sapi.'; end if;
 else
  if not public.sd_has_role(array['admin','pemeriksa','bendahara_kas'],v_account.id) then raise exception 'Tidak berwenang memverifikasi akun kas.'; end if;
 end if;
 if v_tx.transaction_type='SETORAN_SAPI' then
  if v_account.account_type<>'SAPI' or v_tx.direction<>'IN' then raise exception 'Setoran sapi harus masuk ke akun sapi.'; end if;
  if not exists(select 1 from public.sd_sapi_participants p join public.sd_members m on m.id=p.member_id
   where p.id=v_tx.participant_id and p.member_id=v_tx.member_id and p.account_id=v_tx.account_id and p.period_id=v_tx.period_id
    and p.opt_in and p.opt_out_at is null and m.is_active) then raise exception 'Peserta belum opt-in atau tidak cocok dengan akun/periode.'; end if;
 elsif v_account.account_type='KAS_UMUM' and v_tx.transaction_type not in ('KAS_MASUK','KAS_KELUAR','KOREKSI') then raise exception 'Jenis transaksi tidak cocok dengan akun kas.';
 elsif v_account.account_type='SAPI' and v_tx.transaction_type not in ('SETORAN_SAPI','KOREKSI') then raise exception 'Jenis transaksi tidak cocok dengan akun sapi.';
 end if;
 if v_account.account_type='KAS_UMUM' and (v_tx.participant_id is not null or v_tx.member_id is not null) then raise exception 'Transaksi kas tidak boleh terkait peserta/anggota.'; end if;
 if v_tx.direction='OUT' then
  select v_account.opening_balance+coalesce(sum(case when t.direction='IN' then t.amount else -t.amount end),0) into v_balance
  from public.sd_financial_transactions t where t.account_id=v_account.id and t.status='CONFIRMED';
  if v_balance<v_tx.amount then raise exception 'Saldo tidak mencukupi.'; end if;
 end if;
 update public.sd_financial_transactions set status='CONFIRMED',verified_by=auth.uid(),verified_at=now()
 where id=p_transaction_id returning * into v_tx;
 insert into public.sd_audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(auth.uid(),'TRANSACTION_CONFIRMED','sd_financial_transactions',v_tx.id::text,jsonb_build_object('account_id',v_tx.account_id,'amount',v_tx.amount,'direction',v_tx.direction));
 return v_tx;
end; $$;

create or replace function public.sd_request_reversal(p_transaction_id uuid,p_note text)
returns public.sd_transaction_reversals language plpgsql security definer set search_path=''
as $$
declare v_tx public.sd_financial_transactions%rowtype; v_account public.sd_fund_accounts%rowtype; v_result public.sd_transaction_reversals%rowtype;
begin
 if auth.uid() is null then raise exception 'Autentikasi diperlukan.'; end if;
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'Alasan koreksi minimal 5 karakter.'; end if;
 select * into v_tx from public.sd_financial_transactions where id=p_transaction_id for share;
 if not found or v_tx.status<>'CONFIRMED' then raise exception 'Hanya transaksi terkonfirmasi yang dapat dimintakan koreksi.'; end if;
 if v_tx.transaction_type='KOREKSI' or v_tx.reversal_of is not null then raise exception 'Transaksi koreksi tidak dapat dikoreksi berantai; ajukan penyesuaian khusus kepada admin.'; end if;
 select * into v_account from public.sd_fund_accounts where id=v_tx.account_id;
 if not public.sd_has_role(array['admin','pemeriksa'],v_account.id)
  and not public.sd_has_role(array['bendahara_sapi','bendahara_kas'],v_account.id)
  and not public.sd_is_own_member(v_tx.member_id) then raise exception 'Tidak berwenang meminta koreksi.'; end if;
 if exists(select 1 from public.sd_transaction_reversals r where r.transaction_id=p_transaction_id and r.status in ('PENDING','APPROVED')) then raise exception 'Permintaan koreksi aktif/sudah disetujui telah ada.'; end if;
 insert into public.sd_transaction_reversals(transaction_id,requested_by,request_note) values(p_transaction_id,auth.uid(),trim(p_note)) returning * into v_result;
 insert into public.sd_audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(auth.uid(),'REVERSAL_REQUESTED','sd_transaction_reversals',v_result.id::text,jsonb_build_object('transaction_id',p_transaction_id));
 return v_result;
end; $$;

create or replace function public.sd_review_reversal(p_reversal_id uuid,p_approve boolean,p_note text default null)
returns public.sd_transaction_reversals language plpgsql security definer set search_path=''
as $$
declare v_rev public.sd_transaction_reversals%rowtype; v_tx public.sd_financial_transactions%rowtype;
 v_account public.sd_fund_accounts%rowtype; v_period public.sd_haul_periods%rowtype;
 v_counter public.sd_financial_transactions%rowtype; v_balance numeric(18,2);
begin
 if auth.uid() is null then raise exception 'Autentikasi diperlukan.'; end if;
 if p_approve is null then raise exception 'Keputusan koreksi wajib ditentukan.'; end if;
 select * into v_rev from public.sd_transaction_reversals where id=p_reversal_id for update;
 if not found or v_rev.status<>'PENDING' then raise exception 'Permintaan koreksi tidak pending.'; end if;
 if v_rev.requested_by=auth.uid() then raise exception 'Pemohon tidak boleh menilai permintaannya sendiri.'; end if;
 select * into v_tx from public.sd_financial_transactions where id=v_rev.transaction_id for update;
 select * into v_account from public.sd_fund_accounts where id=v_tx.account_id for update;
 select * into v_period from public.sd_haul_periods where id=v_tx.period_id for share;
 if v_tx.status<>'CONFIRMED' then raise exception 'Transaksi sumber bukan terkonfirmasi.'; end if;
 if v_tx.recorded_by=auth.uid() then raise exception 'Pencatat transaksi sumber tidak boleh menilai koreksinya.'; end if;
 if not public.sd_has_role(array['admin','pemeriksa'],v_account.id) then raise exception 'Hanya admin atau pemeriksa lingkup akun yang boleh menilai koreksi.'; end if;
 if p_approve then
  if v_period.status<>'OPEN' then raise exception 'Periode tertutup; koreksi memerlukan prosedur khusus yang diaudit.'; end if;
  if v_tx.direction='IN' then
   select v_account.opening_balance+coalesce(sum(case when t.direction='IN' then t.amount else -t.amount end),0) into v_balance
   from public.sd_financial_transactions t where t.account_id=v_account.id and t.status='CONFIRMED';
   if v_balance<v_tx.amount then raise exception 'Saldo berjalan tidak cukup untuk membalik transaksi masuk.'; end if;
  end if;
  insert into public.sd_financial_transactions(account_id,period_id,transaction_type,direction,amount,note,status,recorded_by,recorded_at,verified_by,verified_at,reversal_of)
  values(v_tx.account_id,v_tx.period_id,'KOREKSI',case when v_tx.direction='IN' then 'OUT' else 'IN' end,v_tx.amount,
   'Koreksi transaksi '||v_tx.id::text||': '||left(trim(coalesce(p_note,v_rev.request_note)),400),'CONFIRMED',v_rev.requested_by,now(),auth.uid(),now(),v_tx.id)
  returning * into v_counter;
  update public.sd_transaction_reversals set status='APPROVED',reviewed_by=auth.uid(),reviewed_at=now(),
   review_note=nullif(trim(coalesce(p_note,'')),''),counter_transaction_id=v_counter.id where id=p_reversal_id returning * into v_rev;
 else
  if length(trim(coalesce(p_note,'')))<5 then raise exception 'Alasan penolakan minimal 5 karakter.'; end if;
  update public.sd_transaction_reversals set status='REJECTED',reviewed_by=auth.uid(),reviewed_at=now(),review_note=trim(p_note)
  where id=p_reversal_id returning * into v_rev;
 end if;
 insert into public.sd_audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(auth.uid(),case when p_approve then 'REVERSAL_APPROVED' else 'REVERSAL_REJECTED' end,'sd_transaction_reversals',v_rev.id::text,
 jsonb_build_object('transaction_id',v_tx.id,'counter_transaction_id',v_rev.counter_transaction_id,'review_note',v_rev.review_note));
 return v_rev;
end; $$;

create or replace function public.sd_admin_create_period(
 p_year integer, p_name text, p_starts_on date, p_ends_on date
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_period_id uuid;
begin
 if auth.uid() is null or not public.sd_has_role(array['admin'],null) then raise exception 'Hanya admin yang dapat membuat periode.'; end if;
 if p_year<2000 or p_year>2200 or length(trim(coalesce(p_name,'')))<3 or p_starts_on>p_ends_on then
  raise exception 'Data periode tidak valid.';
 end if;
 insert into public.sd_haul_periods(year,name,starts_on,ends_on,created_by)
 values(p_year,trim(p_name),p_starts_on,p_ends_on,auth.uid()) returning id into v_period_id;
 insert into public.sd_fund_accounts(period_id,account_type,display_name,opening_balance,created_by)
 values
  (v_period_id,'SAPI','Tabungan Sapi Haul '||p_year,0,auth.uid()),
  (v_period_id,'KAS_UMUM','Kas Umum Haul '||p_year,0,auth.uid());
 insert into public.sd_audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(auth.uid(),'PERIOD_CREATED','sd_haul_periods',v_period_id::text,jsonb_build_object('year',p_year));
 return v_period_id;
end; $$;

create or replace function public.sd_admin_create_member(
 p_full_name text, p_phone text default null, p_auth_user_id uuid default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_member_id uuid;
begin
 if auth.uid() is null or not public.sd_has_role(array['admin'],null) then raise exception 'Hanya admin yang dapat membuat profil jamaah.'; end if;
 if length(trim(coalesce(p_full_name,'')))<2 or length(trim(p_full_name))>160 then raise exception 'Nama jamaah tidak valid.'; end if;
 if p_auth_user_id is not null and not exists(select 1 from auth.users u where u.id=p_auth_user_id) then
  raise exception 'Pengguna Auth tidak ditemukan.';
 end if;
 insert into public.sd_members(auth_user_id,full_name,phone,is_active,created_by)
 values(p_auth_user_id,trim(p_full_name),nullif(trim(coalesce(p_phone,'')),''),true,auth.uid())
 returning id into v_member_id;
 if p_auth_user_id is not null then
  insert into public.sd_user_roles(user_id,role,account_id,created_by)
  values(p_auth_user_id,'jamaah',null,auth.uid())
  on conflict(user_id,role) where account_id is null do nothing;
 end if;
 insert into public.sd_audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(auth.uid(),'MEMBER_CREATED','sd_members',v_member_id::text,jsonb_build_object('auth_user_id',p_auth_user_id));
 return v_member_id;
end; $$;

create or replace function public.sd_admin_set_user_role(
 p_user_id uuid, p_role text, p_account_id uuid default null, p_enabled boolean default true
) returns void
language plpgsql security definer set search_path=''
as $$
declare v_type text;
begin
 if auth.uid() is null or not public.sd_has_role(array['admin'],null) then raise exception 'Hanya admin yang dapat mengatur role.'; end if;
 if not exists(select 1 from auth.users u where u.id=p_user_id) then raise exception 'Pengguna Auth tidak ditemukan.'; end if;
 if coalesce(p_role,'') not in ('admin','bendahara_sapi','bendahara_kas','pemeriksa','jamaah') then raise exception 'Role tidak valid.'; end if;
 if p_enabled is null then raise exception 'Status role wajib ditentukan.'; end if;
 if p_role in ('admin','jamaah') and p_account_id is not null then raise exception 'Role ini harus bersifat global.'; end if;
 if p_role in ('bendahara_sapi','bendahara_kas','pemeriksa') and p_account_id is null then raise exception 'Role ini wajib dibatasi ke akun.'; end if;
 if p_account_id is not null then
  select account_type into v_type from public.sd_fund_accounts where id=p_account_id and is_active;
  if v_type is null then raise exception 'Akun tidak ditemukan atau tidak aktif.'; end if;
  if p_role='bendahara_sapi' and v_type<>'SAPI' then raise exception 'Bendahara sapi hanya boleh pada akun SAPI.'; end if;
  if p_role='bendahara_kas' and v_type<>'KAS_UMUM' then raise exception 'Bendahara kas hanya boleh pada akun KAS_UMUM.'; end if;
 end if;
 if p_role='admin' and not p_enabled
   and exists(select 1 from public.sd_user_roles target where target.user_id=p_user_id and target.role='admin' and target.account_id is null)
   and (select count(*) from public.sd_user_roles r where r.role='admin' and r.account_id is null)<=1 then
  raise exception 'Admin terakhir tidak boleh dicabut; tetapkan admin pengganti terlebih dahulu.';
 end if;
 if p_enabled then
  if p_account_id is null then
   insert into public.sd_user_roles(user_id,role,account_id,created_by)
   values(p_user_id,p_role,null,auth.uid())
   on conflict(user_id,role) where account_id is null do nothing;
  else
   insert into public.sd_user_roles(user_id,role,account_id,created_by)
   values(p_user_id,p_role,p_account_id,auth.uid())
   on conflict(user_id,role,account_id) where account_id is not null do nothing;
  end if;
 else
  delete from public.sd_user_roles r
  where r.user_id=p_user_id and r.role=p_role and r.account_id is not distinct from p_account_id;
 end if;
 insert into public.sd_audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(auth.uid(),case when p_enabled then 'ROLE_GRANTED' else 'ROLE_REVOKED' end,'sd_user_roles',p_user_id::text,
 jsonb_build_object('role',p_role,'account_id',p_account_id));
end; $$;

create or replace function public.sd_admin_close_period(p_period_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare v_period public.sd_haul_periods%rowtype;
begin
 if auth.uid() is null or not public.sd_has_role(array['admin'],null) then raise exception 'Hanya admin yang dapat menutup periode.'; end if;
 perform 1 from public.sd_fund_accounts where period_id=p_period_id order by id for update;
 select * into v_period from public.sd_haul_periods where id=p_period_id for update;
 if not found or v_period.status<>'OPEN' then raise exception 'Periode tidak ditemukan atau sudah tertutup.'; end if;
 if exists(select 1 from public.sd_financial_transactions t where t.period_id=p_period_id and t.status='PENDING') then
  raise exception 'Selesaikan atau tolak semua transaksi pending sebelum periode ditutup.';
 end if;
 if exists(select 1 from public.sd_transaction_reversals r join public.sd_financial_transactions t on t.id=r.transaction_id
  where t.period_id=p_period_id and r.status='PENDING') then raise exception 'Selesaikan semua permintaan koreksi sebelum periode ditutup.'; end if;
 update public.sd_haul_periods set status='CLOSED',closed_by=auth.uid(),closed_at=now() where id=p_period_id;
 update public.sd_fund_accounts set is_active=false where period_id=p_period_id;
 insert into public.sd_audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(auth.uid(),'PERIOD_CLOSED','sd_haul_periods',p_period_id::text,jsonb_build_object('year',v_period.year));
end; $$;

create or replace function public.sd_set_sapi_opt_in(p_participant_id uuid,p_opt_in boolean)
returns public.sd_sapi_participants language plpgsql security definer set search_path=''
as $$
declare v_participant public.sd_sapi_participants%rowtype; v_account public.sd_fund_accounts%rowtype; v_period public.sd_haul_periods%rowtype;
begin
 if auth.uid() is null then raise exception 'Autentikasi diperlukan.'; end if;
 if p_opt_in is null then raise exception 'Status opt-in wajib ditentukan.'; end if;
 select * into v_participant from public.sd_sapi_participants where id=p_participant_id for update;
 if not found then raise exception 'Peserta tidak ditemukan.'; end if;
 select * into v_account from public.sd_fund_accounts where id=v_participant.account_id for update;
 select * into v_period from public.sd_haul_periods where id=v_participant.period_id for share;
 if not public.sd_has_role(array['admin','bendahara_sapi'],v_account.id) then raise exception 'Tidak berwenang mengubah opt-in.'; end if;
 if v_period.status<>'OPEN' or not v_account.is_active then raise exception 'Periode atau akun tidak aktif.'; end if;
 if p_opt_in then
  update public.sd_sapi_participants set opt_in=true,opt_in_at=now(),opt_in_recorded_by=auth.uid(),opt_out_at=null
  where id=p_participant_id returning * into v_participant;
 else
  update public.sd_sapi_participants set opt_in=false,opt_in_at=null,opt_in_recorded_by=null,opt_out_at=now()
  where id=p_participant_id returning * into v_participant;
 end if;
 insert into public.sd_audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(auth.uid(),case when p_opt_in then 'SAPI_OPT_IN' else 'SAPI_OPT_OUT' end,'sd_sapi_participants',p_participant_id::text,
 jsonb_build_object('member_id',v_participant.member_id,'period_id',v_participant.period_id));
 return v_participant;
end; $$;

create or replace function public.sd_reject_transaction(p_transaction_id uuid,p_reason text)
returns public.sd_financial_transactions language plpgsql security definer set search_path=''
as $$
declare v_tx public.sd_financial_transactions%rowtype; v_account public.sd_fund_accounts%rowtype; v_period public.sd_haul_periods%rowtype;
begin
 if auth.uid() is null then raise exception 'Autentikasi diperlukan.'; end if;
 if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Alasan penolakan minimal 5 karakter.'; end if;
 select * into v_tx from public.sd_financial_transactions where id=p_transaction_id for update;
 if not found or v_tx.status<>'PENDING' then raise exception 'Transaksi tidak ditemukan atau bukan pending.'; end if;
 if v_tx.recorded_by=auth.uid() then raise exception 'Pencatat tidak boleh menolak transaksinya sendiri.'; end if;
 select * into v_account from public.sd_fund_accounts where id=v_tx.account_id for update;
 select * into v_period from public.sd_haul_periods where id=v_tx.period_id for share;
 if v_period.status<>'OPEN' or not v_account.is_active then raise exception 'Periode atau akun tidak aktif.'; end if;
 if v_account.account_type='SAPI' then
  if not public.sd_has_role(array['admin','pemeriksa','bendahara_sapi'],v_account.id) then raise exception 'Tidak berwenang menolak transaksi sapi.'; end if;
 else
  if not public.sd_has_role(array['admin','pemeriksa','bendahara_kas'],v_account.id) then raise exception 'Tidak berwenang menolak transaksi kas.'; end if;
 end if;
 update public.sd_financial_transactions set status='REJECTED' where id=p_transaction_id returning * into v_tx;
 insert into public.sd_audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(auth.uid(),'TRANSACTION_REJECTED','sd_financial_transactions',v_tx.id::text,
 jsonb_build_object('reason',trim(p_reason),'account_id',v_tx.account_id));
 return v_tx;
end; $$;

create or replace function public.sd_guard_transaction_insert()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_account public.sd_fund_accounts%rowtype; v_period public.sd_haul_periods%rowtype;
begin
 if auth.uid() is null then raise exception 'Autentikasi diperlukan.'; end if;
 if NEW.status='PENDING' then
  if NEW.recorded_by is distinct from auth.uid() or NEW.verified_by is not null or NEW.verified_at is not null then
   raise exception 'Transaksi baru wajib pending dan pencatat harus pengguna aktif.';
  end if;
 elsif NEW.status='CONFIRMED' and NEW.transaction_type='KOREKSI' and NEW.reversal_of is not null
   and NEW.verified_by=auth.uid() and NEW.verified_at is not null and NEW.recorded_by<>auth.uid()
   and exists(select 1 from public.sd_transaction_reversals r
      join public.sd_financial_transactions src on src.id=r.transaction_id
      where r.transaction_id=NEW.reversal_of and r.status='PENDING' and r.requested_by=NEW.recorded_by
       and src.status='CONFIRMED' and src.transaction_type<>'KOREKSI'
       and src.account_id=NEW.account_id and src.period_id=NEW.period_id and src.amount=NEW.amount
       and NEW.direction<>src.direction and NEW.verified_by=auth.uid()) then
  null; -- Approved reversal RPC may atomically insert a confirmed counter-entry.
 else
  raise exception 'Transaksi baru tidak boleh langsung terkonfirmasi.';
 end if;
 select * into v_account from public.sd_fund_accounts where id=NEW.account_id;
 if v_account.id is null then raise exception 'Akun tidak ditemukan.'; end if;
 select * into v_period from public.sd_haul_periods where id=NEW.period_id;
 if v_period.id is null or v_account.period_id<>NEW.period_id or not v_account.is_active or v_period.status<>'OPEN' then
  raise exception 'Akun/periode tidak cocok atau tidak aktif.';
 end if;
 if NEW.transaction_type='KOREKSI' then
  if NEW.status<>'CONFIRMED' or NEW.reversal_of is null or NEW.participant_id is not null or NEW.member_id is not null then
   raise exception 'Koreksi hanya boleh menjadi counter-entry reversal yang sah.';
  end if;
 elsif v_account.account_type='SAPI' then
  if NEW.transaction_type<>'SETORAN_SAPI' or NEW.direction<>'IN' or NEW.participant_id is null or NEW.member_id is null then
   raise exception 'Akun sapi hanya menerima setoran peserta.';
  end if;
 elsif NEW.transaction_type not in ('KAS_MASUK','KAS_KELUAR') or NEW.participant_id is not null or NEW.member_id is not null then
  raise exception 'Transaksi kas harus masuk/keluar tanpa peserta atau anggota.';
 end if;
 return NEW;
end; $$;

create or replace function public.sd_audit_log_immutable()
returns trigger language plpgsql set search_path=''
as $$ begin raise exception 'Audit log bersifat append-only.'; end; $$;

create or replace function public.sd_guard_participant()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_account public.sd_fund_accounts%rowtype; v_period public.sd_haul_periods%rowtype; v_member public.sd_members%rowtype;
begin
 select * into v_account from public.sd_fund_accounts where id=NEW.account_id;
 select * into v_period from public.sd_haul_periods where id=NEW.period_id;
 select * into v_member from public.sd_members where id=NEW.member_id;
 if v_account.account_type<>'SAPI' or v_account.period_id<>NEW.period_id then raise exception 'Peserta harus terikat ke akun sapi pada periode sama.'; end if;
 if v_period.status<>'OPEN' or not v_account.is_active then raise exception 'Periode atau akun tidak aktif.'; end if;
 if not v_member.is_active then raise exception 'Jamaah tidak aktif.'; end if;
 if not public.sd_has_role(array['admin','bendahara_sapi'],v_account.id) then raise exception 'Tidak berwenang mengelola peserta sapi.'; end if;
 if TG_OP='INSERT' and NEW.created_by is distinct from auth.uid() then raise exception 'Petugas pencatat peserta tidak valid.'; end if;
 if NEW.opt_in then
  if NEW.opt_in_recorded_by is distinct from auth.uid() then raise exception 'Petugas opt-in harus sama dengan pengguna masuk.'; end if;
  if NEW.opt_in_at is null then NEW.opt_in_at:=now(); end if;
  NEW.opt_out_at:=null;
 else
  NEW.opt_in_at:=null; NEW.opt_in_recorded_by:=null;
  if TG_OP='UPDATE' and OLD.opt_in and NEW.opt_out_at is null then NEW.opt_out_at:=now(); end if;
 end if;
 return NEW;
end; $$;

drop trigger if exists sd_participant_guard on public.sd_sapi_participants;
create trigger sd_participant_guard before insert or update on public.sd_sapi_participants for each row execute function public.sd_guard_participant();
drop trigger if exists sd_transaction_insert_guard on public.sd_financial_transactions;
create trigger sd_transaction_insert_guard before insert on public.sd_financial_transactions for each row execute function public.sd_guard_transaction_insert();
drop trigger if exists sd_audit_periods on public.sd_haul_periods;
create trigger sd_audit_periods after insert or update or delete on public.sd_haul_periods for each row execute function public.sd_audit_row();
drop trigger if exists sd_audit_log_guard on public.sd_audit_log;
create trigger sd_audit_log_guard before update or delete on public.sd_audit_log for each row execute function public.sd_audit_log_immutable();
drop trigger if exists sd_transaction_guard on public.sd_financial_transactions;
create trigger sd_transaction_guard before update or delete on public.sd_financial_transactions for each row execute function public.sd_guard_transaction_mutation();
drop trigger if exists sd_audit_members on public.sd_members;
create trigger sd_audit_members after insert or update or delete on public.sd_members for each row execute function public.sd_audit_row();
drop trigger if exists sd_audit_accounts on public.sd_fund_accounts;
create trigger sd_audit_accounts after insert or update or delete on public.sd_fund_accounts for each row execute function public.sd_audit_row();
drop trigger if exists sd_audit_participants on public.sd_sapi_participants;
create trigger sd_audit_participants after insert or update or delete on public.sd_sapi_participants for each row execute function public.sd_audit_row();
drop trigger if exists sd_audit_transactions on public.sd_financial_transactions;
create trigger sd_audit_transactions after insert on public.sd_financial_transactions for each row execute function public.sd_audit_row();
drop trigger if exists sd_audit_roles on public.sd_user_roles;
create trigger sd_audit_roles after insert or update or delete on public.sd_user_roles for each row execute function public.sd_audit_row();

alter table public.sd_haul_periods enable row level security;
alter table public.sd_members enable row level security;
alter table public.sd_user_roles enable row level security;
alter table public.sd_fund_accounts enable row level security;
alter table public.sd_sapi_participants enable row level security;
alter table public.sd_financial_transactions enable row level security;
alter table public.sd_transaction_reversals enable row level security;
alter table public.sd_audit_log enable row level security;

create policy sd_periods_read on public.sd_haul_periods for select to authenticated using(
 public.sd_has_role(array['admin'],null) or exists(select 1 from public.sd_fund_accounts a where a.period_id=sd_haul_periods.id and public.sd_has_role(array['pemeriksa','bendahara_sapi','bendahara_kas'],a.id)));
create policy sd_members_read on public.sd_members for select to authenticated using(
 public.sd_has_role(array['admin'],null) or public.sd_is_own_member(id) or exists(select 1 from public.sd_sapi_participants p where p.member_id=sd_members.id and public.sd_has_role(array['pemeriksa','bendahara_sapi'],p.account_id)));
create policy sd_roles_read on public.sd_user_roles for select to authenticated using(user_id=auth.uid() or public.sd_has_role(array['admin'],null) or public.sd_has_role(array['pemeriksa'],account_id));
create policy sd_accounts_read on public.sd_fund_accounts for select to authenticated using(public.sd_has_role(array['admin','pemeriksa'],id) or public.sd_has_role(array['bendahara_sapi','bendahara_kas'],id));
create policy sd_participants_read on public.sd_sapi_participants for select to authenticated using(public.sd_has_role(array['admin','pemeriksa','bendahara_sapi'],account_id) or public.sd_is_own_member(member_id));
create policy sd_participants_insert on public.sd_sapi_participants for insert to authenticated with check(public.sd_has_role(array['admin','bendahara_sapi'],account_id));
create policy sd_transactions_read on public.sd_financial_transactions for select to authenticated using(public.sd_has_role(array['admin','pemeriksa','bendahara_sapi','bendahara_kas'],account_id) or public.sd_is_own_member(member_id));
create policy sd_transactions_insert on public.sd_financial_transactions for insert to authenticated with check(
 recorded_by=auth.uid() and status='PENDING' and verified_by is null and verified_at is null and
 ((public.sd_account_type(account_id)='SAPI' and transaction_type='SETORAN_SAPI' and direction='IN'
  and public.sd_has_role(array['admin','bendahara_sapi'],account_id)
  and exists(select 1 from public.sd_sapi_participants p where p.id=sd_financial_transactions.participant_id and p.member_id=sd_financial_transactions.member_id
   and p.account_id=sd_financial_transactions.account_id and p.period_id=sd_financial_transactions.period_id and p.opt_in and p.opt_out_at is null))
  or (public.sd_account_type(account_id)='KAS_UMUM' and transaction_type in ('KAS_MASUK','KAS_KELUAR')
   and participant_id is null and member_id is null and public.sd_has_role(array['admin','bendahara_kas'],account_id))));
create policy sd_reversals_read on public.sd_transaction_reversals for select to authenticated using(requested_by=auth.uid() or exists(
 select 1 from public.sd_financial_transactions t where t.id=transaction_id and public.sd_has_role(array['admin','pemeriksa'],t.account_id)));
create policy sd_audit_read on public.sd_audit_log for select to authenticated using(public.sd_has_role(array['admin'],null) or
 (entity_table='sd_financial_transactions' and exists(select 1 from public.sd_financial_transactions t where t.id::text=entity_id and public.sd_has_role(array['pemeriksa'],t.account_id))));

revoke all on public.sd_haul_periods,public.sd_members,public.sd_user_roles,public.sd_fund_accounts,public.sd_sapi_participants,public.sd_financial_transactions,public.sd_transaction_reversals,public.sd_audit_log from public,anon,authenticated;
grant select on public.sd_haul_periods,public.sd_user_roles,public.sd_fund_accounts,public.sd_sapi_participants,public.sd_financial_transactions,public.sd_transaction_reversals,public.sd_audit_log to authenticated;
grant select(id,auth_user_id,full_name,is_active,created_at) on public.sd_members to authenticated;
grant insert(period_id,account_id,member_id,opt_in,opt_in_at,opt_in_recorded_by,opt_out_at,created_by) on public.sd_sapi_participants to authenticated;
grant insert(account_id,period_id,participant_id,member_id,transaction_type,direction,amount,note,receipt_path,status,recorded_by,idempotency_key) on public.sd_financial_transactions to authenticated;

revoke all on function public.sd_has_role(text[],uuid) from public,anon,authenticated;
revoke all on function public.sd_is_own_member(uuid) from public,anon,authenticated;
revoke all on function public.sd_account_type(uuid) from public,anon,authenticated;
revoke all on function public.sd_audit_row() from public,anon,authenticated;
revoke all on function public.sd_guard_transaction_mutation() from public,anon,authenticated;
revoke all on function public.sd_guard_participant() from public,anon,authenticated;
revoke all on function public.sd_guard_transaction_insert() from public,anon,authenticated;
revoke all on function public.sd_audit_log_immutable() from public,anon,authenticated;
revoke all on function public.sd_confirm_transaction(uuid) from public,anon,authenticated;
revoke all on function public.sd_request_reversal(uuid,text) from public,anon,authenticated;
revoke all on function public.sd_review_reversal(uuid,boolean,text) from public,anon,authenticated;
revoke all on function public.sd_admin_create_member(text,text,uuid) from public,anon,authenticated;
revoke all on function public.sd_admin_create_period(integer,text,date,date) from public,anon,authenticated;
revoke all on function public.sd_admin_set_user_role(uuid,text,uuid,boolean) from public,anon,authenticated;
revoke all on function public.sd_admin_close_period(uuid) from public,anon,authenticated;
revoke all on function public.sd_set_sapi_opt_in(uuid,boolean) from public,anon,authenticated;
revoke all on function public.sd_reject_transaction(uuid,text) from public,anon,authenticated;

grant execute on function public.sd_has_role(text[],uuid) to authenticated;
grant execute on function public.sd_is_own_member(uuid) to authenticated;
grant execute on function public.sd_account_type(uuid) to authenticated;
grant execute on function public.sd_confirm_transaction(uuid) to authenticated;
grant execute on function public.sd_request_reversal(uuid,text) to authenticated;
grant execute on function public.sd_review_reversal(uuid,boolean,text) to authenticated;
grant execute on function public.sd_admin_create_member(text,text,uuid) to authenticated;
grant execute on function public.sd_admin_create_period(integer,text,date,date) to authenticated;
grant execute on function public.sd_admin_set_user_role(uuid,text,uuid,boolean) to authenticated;
grant execute on function public.sd_admin_close_period(uuid) to authenticated;
grant execute on function public.sd_set_sapi_opt_in(uuid,boolean) to authenticated;
grant execute on function public.sd_reject_transaction(uuid,text) to authenticated;
commit;

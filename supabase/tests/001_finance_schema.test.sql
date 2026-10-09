-- SANTRI DEPROK database contract tests (pgTAP)
-- Run only AFTER the migration is approved and applied to an isolated staging project.
-- These tests inspect schema/privileges; they do not create financial data.
begin;
select plan(18);

select ok((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sd_haul_periods'), 'RLS enabled: periods');
select ok((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sd_members'), 'RLS enabled: members');
select ok((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sd_user_roles'), 'RLS enabled: roles');
select ok((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sd_fund_accounts'), 'RLS enabled: fund accounts');
select ok((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sd_sapi_participants'), 'RLS enabled: cattle participants');
select ok((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sd_financial_transactions'), 'RLS enabled: transactions');
select ok((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sd_transaction_reversals'), 'RLS enabled: reversals');
select ok((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='sd_audit_log'), 'RLS enabled: audit log');

select ok(not has_column_privilege('authenticated','public.sd_members','phone','SELECT'), 'authenticated cannot directly select member phone');
select ok(not has_column_privilege('authenticated','public.sd_members','full_name','INSERT'), 'authenticated cannot directly insert member profiles');
select ok(not has_table_privilege('authenticated','public.sd_financial_transactions','UPDATE'), 'authenticated cannot directly update ledger transactions');
select ok(not has_table_privilege('authenticated','public.sd_financial_transactions','DELETE'), 'authenticated cannot directly delete ledger transactions');

select ok(not has_function_privilege('anon','public.sd_confirm_transaction(uuid)','EXECUTE'), 'anon cannot confirm transactions');
select ok(has_function_privilege('authenticated','public.sd_confirm_transaction(uuid)','EXECUTE'), 'authenticated can call controlled confirmation RPC');
select ok(not has_function_privilege('anon','public.sd_admin_create_period(integer,text,date,date)','EXECUTE'), 'anon cannot create periods');
select ok(has_function_privilege('authenticated','public.sd_admin_create_period(integer,text,date,date)','EXECUTE'), 'authenticated can invoke admin period RPC, which must enforce admin role internally');

select ok(exists(select 1 from pg_constraint where conrelid='public.sd_fund_accounts'::regclass and contype='c' and pg_get_constraintdef(oid) like '%opening_balance%'), 'fund account opening balance check exists');
select is((select count(*)::integer from pg_policies where schemaname='public' and tablename in ('sd_haul_periods','sd_members','sd_user_roles','sd_fund_accounts','sd_sapi_participants','sd_financial_transactions','sd_transaction_reversals','sd_audit_log')), 10, 'expected minimum number of RLS policies exists');

select * from finish();
rollback;

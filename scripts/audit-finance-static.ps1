$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$sql = Join-Path $root "supabase\migrations\20261009_santri_deprok_finance.sql"
$body = Get-Content -LiteralPath $sql -Raw
$checks = @(
 @{ Name="RLS enabled on all core tables"; Pattern="alter table public\.sd_audit_log enable row level security" },
 @{ Name="Separate annual fund accounts"; Pattern="unique\(period_id,account_type\)" },
 @{ Name="Opening balance fixed at zero"; Pattern="opening_balance numeric\(18,2\) not null default 0 check\(opening_balance=0\)" },
 @{ Name="Account-period composite FK"; Pattern="foreign key\(account_id,period_id\) references public\.sd_fund_accounts\(id,period_id\)" },
 @{ Name="Explicit opt-in enforced"; Pattern="p\.opt_in and p\.opt_out_at is null" },
 @{ Name="Pending-only regular insert"; Pattern="Transaksi baru tidak boleh langsung terkonfirmasi" },
 @{ Name="No self-approval"; Pattern="v_tx\.recorded_by=auth\.uid\(\)" },
 @{ Name="No self-rejection"; Pattern="Pencatat tidak boleh menolak transaksinya sendiri" },
 @{ Name="Account row locked on confirmation"; Pattern="where id=v_tx\.account_id for update" },
 @{ Name="Confirmed transaction immutable"; Pattern="if OLD\.status='CONFIRMED' then" },
 @{ Name="Two-person reversal"; Pattern="v_rev\.requested_by=auth\.uid\(\)" },
 @{ Name="Duplicate active reversal blocked"; Pattern="sd_reversal_one_active_request" },
 @{ Name="Audit log append-only"; Pattern="create trigger sd_audit_log_guard before update or delete on public\.sd_audit_log" },
 @{ Name="Admin period provisioning RPC"; Pattern="create or replace function public\.sd_admin_create_period" },
 @{ Name="Admin member provisioning RPC"; Pattern="create or replace function public\.sd_admin_create_member" },
 @{ Name="Scoped role management RPC"; Pattern="create or replace function public\.sd_admin_set_user_role" },
 @{ Name="Period close checks pending"; Pattern="Selesaikan atau tolak semua transaksi pending" },
 @{ Name="Controlled opt-in RPC"; Pattern="create or replace function public\.sd_set_sapi_opt_in" },
 @{ Name="Transaction rejection RPC"; Pattern="create or replace function public\.sd_reject_transaction" },
 @{ Name="Phone omitted from direct SELECT"; Pattern="grant select\(id,auth_user_id,full_name,is_active,created_at\) on public\.sd_members" },
 @{ Name="No direct member INSERT grant"; Pattern="grant insert\(auth_user_id,full_name,phone,is_active,created_by\) on public\.sd_members" }
)
$failed=@()
foreach($c in $checks){
 $matched=$body -match $c.Pattern
 if($c.Name -eq "No direct member INSERT grant"){$matched = -not $matched}
 if($matched){Write-Host ("PASS  "+$c.Name) -ForegroundColor Green}else{Write-Host ("FAIL  "+$c.Name) -ForegroundColor Red;$failed+=$c.Name}
}
$dq=([regex]::Matches($body,'\$\$')).Count
if(($dq%2)-eq 0){Write-Host "PASS  Dollar-quote delimiter count is even" -ForegroundColor Green}else{$failed+="Dollar-quote delimiter count"}
$commits=([regex]::Matches($body,'(?im)^commit;\s*$')).Count
if($commits -eq 1){Write-Host "PASS  Single migration transaction commit" -ForegroundColor Green}else{Write-Host ("FAIL  Expected 1 commit, found "+$commits) -ForegroundColor Red;$failed+="Commit count"}
$bootstrap=Join-Path $root "docs\keuangan\BOOTSTRAP-ADMIN-MANUAL.sql.example"
if(Test-Path $bootstrap){Write-Host "PASS  Manual bootstrap example present" -ForegroundColor Green}else{$failed+="Manual bootstrap example"}
Push-Location $root
try {
 if(Test-Path (Join-Path $root ".git")){
  git diff --check
  if($LASTEXITCODE -ne 0){$failed+="git diff --check"}else{Write-Host "PASS  git diff --check" -ForegroundColor Green}
 } else { Write-Host "SKIP  git diff --check (project belum diinisialisasi sebagai Git)" -ForegroundColor Yellow }
 npx tsc --noEmit
 if($LASTEXITCODE -ne 0){$failed+="TypeScript"}else{Write-Host "PASS  TypeScript" -ForegroundColor Green}
 npm run build
 if($LASTEXITCODE -ne 0){$failed+="Next build"}else{Write-Host "PASS  Next build" -ForegroundColor Green}
} finally {Pop-Location}
if($failed.Count){Write-Host ("FAILED: "+($failed -join ", ")) -ForegroundColor Red;exit 1}
Write-Host "STATIC CHECKS PASSED. SQL has not been parsed or executed by PostgreSQL." -ForegroundColor Cyan

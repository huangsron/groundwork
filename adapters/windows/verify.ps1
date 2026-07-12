<#
.SYNOPSIS
  Reusable, role-separated build + launch verifier for .NET / MSBuild projects.
  Reference Phase-6 harness for the /groundwork:verify skill.

  Run by an INDEPENDENT verifier (not the agent that edited the code), on a CLEAN checkout.
  Without -Independent the best possible verdict is LOCAL_CHECK, never PASS.
  Same source + same harness => same verdict.

  ASCII-only: Windows PowerShell 5.1 reads .ps1 as ANSI; non-ASCII comments corrupt parsing.

.PARAMETER Project          .csproj (built Platform "AnyCPU").
.PARAMETER Solution         optional .sln (built Platform "Any CPU").
.PARAMETER Exe              produced exe for the GUI gate; omit to skip launch (e.g. success level "compiles").
.PARAMETER Configuration    Debug | Release (default Debug).
.PARAMETER NoRestore        skip the NuGet /restore pass (offline env; legacy packages.config projects restore separately anyway).
.PARAMETER LaunchSeconds    startup timeout before window check (default 20; raise for apps that block on DB/network).
.PARAMETER MinStableSeconds re-check window still present after this many more seconds (default 2).
.PARAMETER ExpectedWindowTitle  optional regex a top-level window title must match.
.PARAMETER ExpectedCommit   optional commit SHA; verdict downgrades if HEAD != this.
.PARAMETER PlanId           optional approved-plan id/hash, recorded in the manifest (handoff binding).
.PARAMETER Independent      assert role separation (verifier != executor, clean checkout). Required for a PASS verdict.
.PARAMETER IndependenceLevel contract enum recorded when -Independent: subagent | process-separated | CI (default subagent).
.PARAMETER DismissStartupDialogs  opt-in: send ENTER to ONE expected startup #32770 dialog, then check for the app's REAL window. For legacy apps that show an expected/benign warning (e.g. DB-unavailable in an offline test env) before their UI. Recorded as a limitation; pair with -ExpectedWindowTitle so PASS lands on the real window, not the dialog.
.PARAMETER RecordsDir       output dir (default <project>\_groundwork\runs\run-<utc>-<rand>).

.NOTES
  Exit codes: 0 = PASS or LOCAL_CHECK; 1 = FAIL / INCONCLUSIVE / BLOCKED / ERROR.
  Read manifest.json (verdict field) for the distinction.
  BLOCKED = environment missing (e.g. MSBuild not found), NOT a product or harness failure.
#>
param(
  [Parameter(Mandatory=$true)][string]$Project,
  [string]$Solution = "",
  [string]$Exe = "",
  [string]$Configuration = "Debug",
  [switch]$NoRestore,
  [int]$LaunchSeconds = 20,
  [int]$MinStableSeconds = 2,
  [string]$ExpectedWindowTitle = "",
  [string]$ExpectedCommit = "",
  [string]$PlanId = "",
  [switch]$Independent,
  [ValidateSet("subagent","process-separated","CI")][string]$IndependenceLevel = "subagent",
  [switch]$DismissStartupDialogs,
  [string]$RecordsDir = ""
)
$ErrorActionPreference = "Stop"
$Summary = [System.Collections.Generic.List[string]]::new()
$limitations = [System.Collections.Generic.List[string]]::new()   # List => empty serializes as [] not null
function Section($t) { Write-Host "`n==== $t ====" -ForegroundColor Cyan }
function Add-Sum($s) { $Summary.Add($s); Write-Host $s }

function Find-MSBuild {
  $pf86 = ${env:ProgramFiles(x86)}   # absent on 32-bit/ARM64 Windows; guard before Join-Path
  if ($pf86) {
    $vswhere = Join-Path $pf86 "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
      try {
        $p = & $vswhere -latest -prerelease -products * -find "MSBuild\**\Bin\MSBuild.exe" 2>$null | Select-Object -First 1
        if ($p -and (Test-Path $p)) { return $p }
      } catch {}   # vswhere stderr is terminating under EAP=Stop in PS 5.1; fall through to PATH
    }
  }
  $g = Get-Command MSBuild.exe -ErrorAction SilentlyContinue
  if ($g) { return $g.Source }
  throw "BLOCKED: MSBuild not found (vswhere + PATH both failed) -- missing toolchain, not a product failure."
}

function Write-Utf8NoBom([string]$path, [string]$text) {
  [IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# run records live under the project: _groundwork/runs/run-<utc>-<rand>/ (retained, policy-cleanable)
$RunsRoot = Join-Path (Split-Path $Project -Parent) "_groundwork\runs"
New-Item -ItemType Directory -Force -Path $RunsRoot | Out-Null
if ([string]::IsNullOrEmpty($RecordsDir)) {
  $runId = "run-" + (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ") + "-" + ([guid]::NewGuid().ToString("N").Substring(0,6))
  $RecordsDir = Join-Path $RunsRoot $runId
}
New-Item -ItemType Directory -Force -Path $RecordsDir | Out-Null
$LogsDir = Join-Path $RecordsDir "logs"
New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null

$harnessHash = try { (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash } catch { "" }

# minimal iteration metrics: cross-run state file (at runs root) auto-computes error_delta
$stateFile = Join-Path $RunsRoot "iteration-state.json"
$prevErrors = $null; $iteration = 1
if (Test-Path $stateFile) {
  try { $s = Get-Content $stateFile -Raw | ConvertFrom-Json; $prevErrors = $s.last_errors; $iteration = [int]$s.iteration + 1 } catch {}
}

$manifest = [ordered]@{
  verdict="ERROR"; independence=$(if($Independent){$IndependenceLevel}else{"none"})   # contract enum: subagent|process-separated|CI|none
  plan_id=$PlanId; build_ok=$false; launch=""; window_titles=@(); window_classes=@(); crash_detected=$false
  tree_clean=$null; raw_dirty=$null; source_commit=""; expected_commit=$ExpectedCommit; commit_match=$null
  harness_hash=$harnessHash; msbuild=""; msbuild_version=""
  configuration=$Configuration; project=$Project; solution=$Solution; exe=$Exe
  artifact_fresh=$null; iteration=$iteration; errors_remaining=$null; error_delta=$null
  records_dir=$RecordsDir; limitations=$limitations
}
try {
  $MSBuild = Find-MSBuild
  $manifest.msbuild = $MSBuild
  try { $manifest.msbuild_version = (& $MSBuild -version -nologo 2>$null | Select-Object -Last 1) } catch {}

  Section "Preflight"
  Add-Sum ("MSBuild : {0}  ({1})" -f $MSBuild, $manifest.msbuild_version)
  Add-Sum ("Project : {0}" -f $Project)
  if ($Solution) { Add-Sum ("Solution: {0}" -f $Solution) }
  Add-Sum ("PlanId  : {0}" -f $PlanId)
  Add-Sum ("Harness : {0}" -f $harnessHash)
  Add-Sum ("Independent: {0}" -f $manifest.independence)

  try {
    Push-Location (Split-Path $Project -Parent)
    $manifest.source_commit = (git rev-parse HEAD 2>$null)
    # cleanliness is judged from the REPO TOPLEVEL (edits anywhere in the repo can affect the build),
    # EXCLUDING the verifier's own outputs (the run records/reports it writes)
    $repoTop = (git rev-parse --show-toplevel 2>$null)
    $stRaw = (git -C $repoTop status --porcelain 2>$null)
    $manifest.raw_dirty = -not [string]::IsNullOrWhiteSpace($stRaw)
    $stAdj = (git -C $repoTop status --porcelain -- . ':(exclude)_groundwork/**' 2>$null)
    $manifest.tree_clean = [string]::IsNullOrWhiteSpace($stAdj)
    Pop-Location
  } catch {
    try { Pop-Location } catch {}
    # git absent / not a repo: cleanliness UNKNOWN (tree_clean stays $null) -> never treated as clean
    $limitations.Add("git unavailable or not a repository: source commit and tree cleanliness UNKNOWN.")
  }
  if ($ExpectedCommit) { $manifest.commit_match = ($manifest.source_commit -eq $ExpectedCommit) }
  Add-Sum ("Commit  : {0}  tree_clean(adj)={1}  raw_dirty={2}  commit_match={3}" -f $manifest.source_commit, $manifest.tree_clean, $manifest.raw_dirty, $manifest.commit_match)

  function Invoke-Build($target, $logName, $label, $platform) {
    Section ("MSBuild " + $label)
    $log = Join-Path $LogsDir $logName
    # /restore: SDK-style projects fail with NETSDK1004 without it; a no-op for legacy packages.config
    $restore = if ($NoRestore) { "" } else { "/restore " }
    $argStr = ('"{0}" {3}/t:Rebuild /p:Configuration="{1}" /p:Platform="{2}" /nologo /v:normal /nodeReuse:false /p:UseSharedCompilation=false' -f $target, $Configuration, $platform, $restore)
    $p = Start-Process -FilePath $MSBuild -ArgumentList $argStr -NoNewWindow -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log + ".stderr")
    $code = $p.ExitCode
    $errs = if (Test-Path $log) { (Select-String -Path $log -Pattern ": error " -SimpleMatch -ErrorAction SilentlyContinue | Measure-Object).Count } else { -1 }
    Add-Sum ("[{0}] exit={1} errorLines={2}  log={3}" -f $label, $code, $errs, (Split-Path $log -Leaf))
    if ($code -ne 0) { return 1 } else { return $errs }
  }

  Add-Type -ErrorAction SilentlyContinue -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class GwWin {
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  delegate bool EnumProc(IntPtr h, IntPtr p);
  // one "class|title" per visible top-level window owned by the process
  public static List<string> WindowsForPid(uint target) {
    var res = new List<string>();
    EnumWindows((h,p) => { uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid==target && IsWindowVisible(h)) {
        var t=new StringBuilder(256); GetWindowText(h,t,256);
        var c=new StringBuilder(128); GetClassName(h,c,128);
        res.Add(c.ToString()+"|"+t.ToString()); }
      return true; }, IntPtr.Zero);
    return res;
  }
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static IntPtr FirstDialogForPid(uint target) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h,p) => { uint pid; GetWindowThreadProcessId(h, out pid);
      var c=new StringBuilder(128); GetClassName(h,c,128);
      if (pid==target && IsWindowVisible(h) && c.ToString()=="#32770") { found=h; return false; }
      return true; }, IntPtr.Zero);
    return found;
  }
}
'@
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

  # kill ONLY instances running from the target exe path (never same-named apps elsewhere -- those
  # may be the user's real work); lingering instances would lock the build output (MSB3027)
  $appName = if ($Exe) { [System.IO.Path]::GetFileNameWithoutExtension($Exe) } else { "" }
  $exeFull = if ($Exe) { [System.IO.Path]::GetFullPath($Exe) } else { "" }
  function Stop-TargetInstances {
    if (-not $appName) { return }
    Get-Process -Name $appName -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -eq $exeFull } |
      Stop-Process -Force -ErrorAction SilentlyContinue
  }
  Stop-TargetInstances
  if ($Exe -and (Test-Path $Exe)) { Remove-Item $Exe -Force -ErrorAction SilentlyContinue }

  $buildStart = Get-Date
  $csprojLog = ((Split-Path $Project -Leaf) -replace '\.csproj$','') + "-csproj.log"
  $csErrs  = Invoke-Build $Project $csprojLog "csproj" "AnyCPU"
  $slnErrs = 0
  if ($Solution) { $slnErrs = Invoke-Build $Solution "sln.log" "sln" "Any CPU" }
  $buildOK = ($csErrs -eq 0 -and $slnErrs -eq 0)
  $manifest.build_ok = $buildOK
  Add-Sum ("BUILD: {0}" -f ($(if ($buildOK) {"PASS (0 errors)"} else {"FAIL"})))

  # minimal metrics: errors_remaining = DISTINCT ": error " lines across build logs (the same error
  # repeats in MSBuild's end-of-build summary and again in the solution log -- dedupe, don't sum)
  $errLines = @()
  foreach ($lg in (Get-ChildItem $LogsDir -Filter "*.log" -ErrorAction SilentlyContinue)) {
    $errLines += @(Select-String -Path $lg.FullName -Pattern ": error " -SimpleMatch -ErrorAction SilentlyContinue | ForEach-Object { $_.Line.Trim() })
  }
  $errorsRemaining = @($errLines | Sort-Object -Unique).Count
  $manifest.errors_remaining = $errorsRemaining
  if ($null -ne $prevErrors) { $manifest.error_delta = $errorsRemaining - [int]$prevErrors }
  try { Write-Utf8NoBom $stateFile ((@{ last_errors=$errorsRemaining; iteration=$iteration } | ConvertTo-Json)) } catch {}
  Add-Sum ("METRICS: iteration={0} errors_remaining={1} error_delta={2}" -f $iteration, $errorsRemaining, $manifest.error_delta)

  $launch = "SKIPPED"; $titles = @(); $entries = @(); $crash = $false; $fresh = $null
  if ($buildOK -and $Exe) {
    Section "Launch verify"
    if (-not (Test-Path $Exe)) { throw "exe not produced: $Exe" }
    $fresh = ((Get-Item $Exe).LastWriteTime -ge $buildStart); $manifest.artifact_fresh = $fresh
    # baseline WER set: only NEW WerFault processes count as a crash of our app
    $werBefore = @(Get-Process -Name "WerFault","WerFault64" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $p = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe -Parent) -PassThru
    Start-Sleep -Seconds $LaunchSeconds
    $p.Refresh()
    $werNew = @(Get-Process -Name "WerFault","WerFault64" -ErrorAction SilentlyContinue | Where-Object { $_.Id -notin $werBefore })
    if ($p.HasExited) {
      $crash = ($p.ExitCode -ne 0) -or ($werNew.Count -gt 0)
      $launch = "FAIL (exited early, code=$($p.ExitCode))"
    } else {
      if ($DismissStartupDialogs) {
        $dlg = [GwWin]::FirstDialogForPid([uint32]$p.Id)
        if ($dlg -ne [IntPtr]::Zero) {
          [GwWin]::SetForegroundWindow($dlg) | Out-Null; Start-Sleep -Milliseconds 400
          try { [System.Windows.Forms.SendKeys]::SendWait("{ENTER}") } catch {}
          Start-Sleep -Seconds 3; $p.Refresh()
          $limitations.Add("Dismissed an EXPECTED startup dialog (-DismissStartupDialogs) before checking for the app's real window.")
        }
      }
      $entries = @()
      try { $entries = @([GwWin]::WindowsForPid([uint32]$p.Id) | ForEach-Object {
              $i = $_.IndexOf('|'); [pscustomobject]@{ class = $_.Substring(0,$i); title = $_.Substring($i+1) } }) } catch { $entries = @() }
      $titles = @($entries | ForEach-Object { $_.title })
      $nonDialog = @($entries | Where-Object { $_.class -ne '#32770' })   # #32770 = Win32 dialog / MessageBox
      Start-Sleep -Seconds $MinStableSeconds; $p.Refresh()
      $stable = -not $p.HasExited
      # re-poll WER after the stability window: a crash surfacing during dialog-dismiss/stability is otherwise missed
      $werNew += @(Get-Process -Name "WerFault","WerFault64" -ErrorAction SilentlyContinue | Where-Object { $_.Id -notin $werBefore -and $_.Id -notin $werNew.Id })
      # array-count test, not string truthiness: an EMPTY window title that matches must still count
      $titleHit = @($titles | Where-Object { $_ -match $ExpectedWindowTitle })
      if ($werNew.Count -gt 0) { $crash = $true; $launch = "FAIL (WER/crash dialog detected)" }
      elseif (-not $stable) { $launch = "FAIL (window appeared then process died)" }
      elseif ($ExpectedWindowTitle -ne "" -and $titleHit.Count -gt 0) { $launch = "PASS (expected window matched)" }
      elseif ($ExpectedWindowTitle -ne "") { $launch = "FAIL (no window matched /$ExpectedWindowTitle/)" }
      elseif ($nonDialog.Count -gt 0) { $launch = "PASS (credible app window present)"; $limitations.Add("Window present != end-to-end functional.") }
      elseif ($entries.Count -gt 0) { $launch = "INCONCLUSIVE (only dialog/MessageBox window(s) -- could be the real UI or an error popup; pass -ExpectedWindowTitle to confirm)" }
      else { $launch = "WEAK (alive but no visible top-level window within ${LaunchSeconds}s)" }
      try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
      Stop-TargetInstances
    }
    $manifest.launch = $launch; $manifest.window_titles = $titles; $manifest.window_classes = @($entries | ForEach-Object { $_.class }); $manifest.crash_detected = $crash
    $shownTitles = ($titles | Where-Object { $_ }) -join ' | '
    Add-Sum ("LAUNCH: {0}  fresh={1}  windowCount={2}  titles=[{3}]" -f $launch, $fresh, $titles.Count, $shownTitles)
  }

  # verdict -- gates include artifact freshness (a stale exe must never PASS, per contract)
  $gatesOk = $buildOK -and (($launch -like "PASS*") -or (-not $Exe)) -and (-not $crash) -and ($fresh -ne $false)
  if (-not $gatesOk) {
    if ($fresh -eq $false) { $limitations.Add("Artifact is STALE (not rebuilt this run): launched binary may be an old build.") }
    $verdict = $(if (($launch -like "WEAK*" -or $launch -like "INCONCLUSIVE*") -and $fresh -ne $false) {"INCONCLUSIVE"} else {"FAIL"})
  } elseif (-not $Independent) {
    $verdict = "LOCAL_CHECK"; $limitations.Add("No role separation asserted (-Independent not set): not an independent PASS.")
  } elseif ($manifest.tree_clean -ne $true) {
    # $false = dirty; $null = UNKNOWN (git absent/failed) -- unknown cleanliness is NOT clean
    $verdict = "LOCAL_CHECK"
    $limitations.Add($(if ($manifest.tree_clean -eq $false) {"Working tree dirty: not a clean-checkout PASS."} else {"Tree cleanliness UNKNOWN (no git evidence): not a clean-checkout PASS."}))
  } elseif ($ExpectedCommit -and ($manifest.commit_match -ne $true)) {
    $verdict = "LOCAL_CHECK"; $limitations.Add("HEAD does not match ExpectedCommit: not verifying the approved commit.")
  } else {
    $verdict = "PASS"
  }
  $manifest.verdict = $verdict
} catch {
  # missing environment (e.g. toolchain) is BLOCKED, not ERROR -- never disguise env gaps as failures
  if ($_.Exception.Message -like "BLOCKED:*") {
    $manifest.verdict = "BLOCKED"; $limitations.Add($_.Exception.Message)
    Add-Sum ("BLOCKED: " + $_.Exception.Message)
  } else {
    $manifest.verdict = "ERROR"; $limitations.Add("harness error: " + $_.Exception.Message)
    Add-Sum ("HARNESS ERROR: " + $_.Exception.Message)
  }
} finally {
  $mPath = Join-Path $RecordsDir "manifest.json"
  Write-Utf8NoBom $mPath ($manifest | ConvertTo-Json -Depth 6)      # BOM-less: strict JSON parsers reject a BOM
  Write-Utf8NoBom (Join-Path $RecordsDir "summary.txt") ($Summary -join "`r`n")
  # auto-collect (platform-free, local ledger). Best-effort: never affects the verdict.
  try { & "$PSScriptRoot\collect.ps1" -Manifest $mPath | Out-Null } catch {}
  Section "Summary"
  Write-Host ("VERDICT: {0}" -f $manifest.verdict)
  Write-Host ("Evidence: {0}" -f $RecordsDir)
}
if ($manifest.verdict -eq "PASS" -or $manifest.verdict -eq "LOCAL_CHECK") { exit 0 } else { exit 1 }

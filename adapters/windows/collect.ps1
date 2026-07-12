<#
.SYNOPSIS
  Platform-independent feedback COLLECTOR. Reads a verify-build manifest, builds a REDACTED,
  minimal record (category + stable signature), and APPENDS it to a local JSONL ledger.
  Always local, no network, no platform. Publishing is a separate, optional step (feedback.ps1).

  Redaction happens HERE (collection time) so the ledger is safe even if a sink later reads it.
  Outputs the record as a single JSON line on stdout (so callers can reuse it).

  ASCII-only.

.PARAMETER Manifest      path to manifest.json from verify.ps1
.PARAMETER SkillName     default "groundwork/verify"
.PARAMETER SkillVersion  default: read from the plugin's .claude-plugin/plugin.json (fallback "0.0.0")
.PARAMETER Category      failure category; inferred from manifest if omitted (contract.md taxonomy)
.PARAMETER FalseVerdict  retro-correction: a human confirmed the recorded verdict was wrong.
                         Re-run collect with -FalseVerdict 1 to append a correction record
                         (same run_id) -- this is the ONLY way false_verdict becomes non-zero.
.PARAMETER NoAppend      compute + emit the record but do NOT write the ledger (used by feedback.ps1)
.PARAMETER LedgerPath    override ledger path (default <project>\_groundwork\feedback\ledger.jsonl)
#>
param(
  [Parameter(Mandatory=$true)][string]$Manifest,
  [string]$SkillName = "groundwork/verify",
  [string]$SkillVersion = "",
  [string]$Category = "",
  [int]$FalseVerdict = 0,
  [switch]$NoAppend,
  [string]$LedgerPath = ""
)
$ErrorActionPreference = "Stop"

if (-not $SkillVersion) {
  # default from plugin.json so the signature's version component tracks releases automatically
  try { $SkillVersion = (Get-Content (Join-Path $PSScriptRoot "..\..\.claude-plugin\plugin.json") -Raw | ConvertFrom-Json).version } catch {}
  if (-not $SkillVersion) { $SkillVersion = "0.0.0" }
}

function Redact([string]$s) {
  if ($null -eq $s) { return "" }
  # allow spaces inside path segments ("C:\Users\John Smith\...") -- stopping at whitespace leaks the tail
  $s = [regex]::Replace($s, '[A-Za-z]:\\[^<>:"|?*\r\n]+', '<path>')
  $s = [regex]::Replace($s, '/(home|Users)/[^<>:"|?*\r\n]+', '<path>')
  $s = [regex]::Replace($s, '\b\d{1,3}(\.\d{1,3}){3}\b', '<ip>')
  $s = [regex]::Replace($s, '(?i)(password|secret|token|api[_-]?key|bearer)\s*[:=]\s*\S+', '$1=<redacted>')
  return $s
}

$m = Get-Content $Manifest -Raw | ConvertFrom-Json
$projDir = if ($m.project) { Split-Path $m.project -Parent } else { Split-Path $Manifest -Parent }

# project_id: prefer git remote (owner/repo), else dir name
$projectId = ""
try {
  Push-Location $projDir
  $top = git rev-parse --show-toplevel 2>$null
  $remote = git remote get-url origin 2>$null
  Pop-Location
  if ($remote) { $projectId = ($remote -replace '^.*[:/]([^/]+/[^/]+?)(\.git)?$','$1') }
  elseif ($top) { $projectId = Split-Path $top -Leaf }
} catch { try { Pop-Location } catch {} }
if (-not $projectId) { $projectId = Split-Path $projDir -Leaf }

# category inference (order matters; taxonomy defined in skills/verify/references/contract.md)
# -FalseVerdict (a human-confirmed correction) is the ONLY source of false_verdict
$false_verdict = $FalseVerdict
if ([string]::IsNullOrWhiteSpace($Category)) {
  if ($false_verdict -gt 0)                { $Category = "false_verdict" }
  elseif ($m.verdict -eq "BLOCKED")        { $Category = "env_blocked" }      # environment missing, not a product failure
  elseif ($m.verdict -eq "ERROR")          { $Category = "harness_error" }    # the harness itself failed, not the build
  elseif ($m.crash_detected)               { $Category = "startup_crash" }
  elseif ($m.build_ok -ne $true)           { $Category = "build_failure" }
  elseif ($m.launch -like "FAIL*")         { $Category = "launch_failure" }
  elseif ($m.launch -like "WEAK*" -or $m.launch -like "INCONCLUSIVE*") { $Category = "launch_inconclusive" }
  elseif ($m.verdict -eq "PASS" -or $m.verdict -eq "LOCAL_CHECK") { $Category = "ok" }
  else { $Category = "unknown" }
}

# error skeleton (redacted, normalized) for a stable signature
# logs live under <records_dir>\logs\ -- search recursively or every build failure hashes identically
$errPattern = ""
if ($m.records_dir -and (Test-Path -LiteralPath $m.records_dir)) {
  foreach ($lg in (Get-ChildItem -LiteralPath $m.records_dir -Recurse -Filter "*.log" -ErrorAction SilentlyContinue)) {
    # compiler-error shape only (same regex as verify.ps1): plain ': error ' also matches
    # warning text like "#warning: 'TODO: error handling'" and would hijack the signature
    $hit = Select-String -LiteralPath $lg.FullName -Pattern ':\s+(fatal\s+)?error(\s+[A-Za-z]+\d+)?\s*:' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { $errPattern = $hit.Line.Trim(); break }
  }
}
if (-not $errPattern) { $errPattern = "$($m.launch)" }
$errNorm = [regex]::Replace((Redact $errPattern), '\(\d+,\d+\)', '(<lc>)')
$errNorm = [regex]::Replace($errNorm, '[^\s]+\(<lc>\)', '<file>(<lc>)')   # relative source paths vary per error site, not per problem
$errNorm = [regex]::Replace($errNorm, "'[^']*'", "'<v>'")
$errNorm = [regex]::Replace($errNorm, '/[^/]*/', '/<re>/')                # harness title-regex embedded in launch strings
$errNorm = [regex]::Replace($errNorm, '(?<![A-Za-z0-9])\d+', '<n>')       # timeouts/exit codes vary per run; keep CSnnnn-style codes

$sigInput = "$Category|$SkillName|$SkillVersion|$errNorm"
$sha = [System.Security.Cryptography.SHA256]::Create()
$sig = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sigInput))) -replace '-','').Substring(0,12).ToLower()

$record = [ordered]@{
  schema_version   = 1
  timestamp        = (Get-Date).ToString("o")
  project_id       = $projectId
  run_id           = (Split-Path $m.records_dir -Leaf)
  skill_name       = $SkillName
  skill_version    = $SkillVersion
  verdict          = $m.verdict
  iteration        = $m.iteration
  errors_remaining = $m.errors_remaining
  error_delta      = $m.error_delta
  crash_detected   = $m.crash_detected
  false_verdict    = $false_verdict
  category         = $Category
  signature        = $sig
  error_pattern    = $errNorm
  harness_hash     = $m.harness_hash
}

if (-not $NoAppend) {
  if (-not $LedgerPath) { $LedgerPath = Join-Path $projDir "_groundwork\feedback\ledger.jsonl" }
  $ld = Split-Path $LedgerPath -Parent
  if (-not (Test-Path $ld)) { New-Item -ItemType Directory -Force -Path $ld | Out-Null }
  # BOM-less UTF-8 append: PS 5.1 Add-Content -Encoding utf8 writes a BOM on file creation,
  # which strict per-line JSONL parsers reject on record 1
  $line = ($record | ConvertTo-Json -Depth 5 -Compress) + [Environment]::NewLine
  [IO.File]::AppendAllText($LedgerPath, $line, (New-Object System.Text.UTF8Encoding($false)))
}

$record | ConvertTo-Json -Depth 5 -Compress
exit 0

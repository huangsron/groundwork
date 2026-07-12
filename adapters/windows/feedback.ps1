<#
.SYNOPSIS
  GitHub-issue publish helper for groundwork feedback. The user runs this AFTER a verify run
  and DECIDES whether to open an issue. It does NOT file anything by itself.

  Auto-collection is separate (collect.ps1, run every verify). This script only helps PUBLISH:
  it reuses collect.ps1 to build a REDACTED record, then offers two ways to open an issue --
  (A) a ready-to-paste `gh` command, or (B) a prefilled GitHub "new issue" URL for the browser --
  plus a dedup search. Either way you end with an issue URL.

  ASCII-only.

.PARAMETER Manifest          path to manifest.json from verify.ps1
.PARAMETER Repo              GitHub "owner/name"; default read from plugin-root feedback.config.json
.PARAMETER SkillVersion      default: read from the plugin's .claude-plugin/plugin.json
.PARAMETER ExpectedVsActual  one-line description
.PARAMETER LabelPrefix       default read from feedback.config.json (fallback "skill:")
.PARAMETER FalseVerdict      pass 1 when publishing a human-confirmed false verdict (forwarded to collect.ps1;
                             without it a PASS-that-was-wrong run never triggers publishing)
#>
param(
  [Parameter(Mandatory=$true)][string]$Manifest,
  [string]$Repo = "",
  [string]$SkillVersion = "",
  [string]$ExpectedVsActual = "",
  [string]$LabelPrefix = "",
  [int]$FalseVerdict = 0
)
$ErrorActionPreference = "Stop"

# defaults come from plugin-root feedback.config.json (repo, label prefix, mode, cooldown)
$cfg = $null
try { $cfg = Get-Content (Join-Path $PSScriptRoot "..\..\feedback.config.json") -Raw | ConvertFrom-Json } catch {}
if (-not $Repo -and $cfg -and $cfg.feedback_repo)               { $Repo = $cfg.feedback_repo }
if (-not $LabelPrefix) { $LabelPrefix = $(if ($cfg -and $cfg.feedback_label_prefix) { $cfg.feedback_label_prefix } else { "skill:" }) }
$mode = $(if ($cfg -and $cfg.feedback_mode) { $cfg.feedback_mode } else { "draft" })
$cooldownDays = 0
if ($cfg -and $cfg.feedback_cooldown_days) { try { $cooldownDays = [int]$cfg.feedback_cooldown_days } catch {} }

if ($mode -eq "off") { Write-Host "feedback_mode=off (feedback.config.json): publishing disabled."; exit 0 }
if (-not $Repo -or $Repo -eq "<owner/repo>") {
  Write-Host "No target repo: set feedback_repo in feedback.config.json or pass -Repo owner/name." -ForegroundColor Yellow
  exit 1
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

# reuse the collector to build the redacted record (do NOT append again; verify already collected)
$colArgs = @{ Manifest = $Manifest; NoAppend = $true }
if ($SkillVersion) { $colArgs.SkillVersion = $SkillVersion }
if ($FalseVerdict -gt 0) { $colArgs.FalseVerdict = $FalseVerdict }
$rec = & "$PSScriptRoot\collect.ps1" @colArgs | ConvertFrom-Json

# ERROR (harness itself failed) is improvement data too; BLOCKED is an env gap the user fixes locally
$triggered = ($rec.verdict -in @("FAIL","INCONCLUSIVE","ERROR")) -or ($rec.crash_detected -eq $true) -or ([int]$rec.false_verdict -gt 0)
if (-not $triggered) {
  Write-Host "No feedback trigger (verdict=$($rec.verdict), crash=$($rec.crash_detected), false_verdict=$($rec.false_verdict)). Nothing to publish."
  exit 0
}

# cooldown: same signature already ledgered within N days -> suggest commenting, not a new issue
if ($cooldownDays -gt 0) {
  try {
    # derive the ledger the same way collect.ps1 does (from the manifest's project dir) --
    # a custom -RecordsDir would break a records-dir-relative guess
    $mRaw = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
    $pDir = if ($mRaw.project_root) { $mRaw.project_root }
            elseif ($mRaw.project)  { Split-Path $mRaw.project -Parent }
            else                    { Split-Path $Manifest -Parent }
    $ledger = Join-Path $pDir "_groundwork\feedback\ledger.jsonl"
    if (Test-Path -LiteralPath $ledger) {
      $cut = (Get-Date).AddDays(-$cooldownDays)
      $dup = Get-Content -LiteralPath $ledger | ForEach-Object { $_ | ConvertFrom-Json } |
             Where-Object { $_.signature -eq $rec.signature -and [datetime]$_.timestamp -gt $cut } |
             Select-Object -First 2
      if (@($dup).Count -gt 1) {   # >1: this run's own record plus an earlier one
        Write-Host ("COOLDOWN: sig {0} already recorded within {1} days -- prefer commenting on the existing issue (see dedup search below)." -f $rec.signature, $cooldownDays) -ForegroundColor Yellow
      }
    }
  } catch {}
}

$dir   = Split-Path $Manifest -Parent
$sig   = $rec.signature
$cat   = $rec.category
$title = "[groundwork] $cat (sig:$sig)"
$eva   = Redact $ExpectedVsActual

$snapshot = [ordered]@{
  verdict=$rec.verdict; errors_remaining=$rec.errors_remaining; error_delta=$rec.error_delta
  iteration=$rec.iteration; crash_detected=$rec.crash_detected; false_verdict=$rec.false_verdict
  harness_hash=$rec.harness_hash
}
$bodyFull = @"
**sig:** $sig
**skill:** $($rec.skill_name) @ $($rec.skill_version)
**category:** $cat
**expected vs actual:** $eva

**error pattern (redacted):**
``````
$($rec.error_pattern)
``````

**manifest snapshot:**
``````json
$($snapshot | ConvertTo-Json -Depth 4)
``````
_Filed by groundwork feedback (redacted: no paths/code/secrets)._
"@

$bodyMd = Join-Path $dir "feedback_body.md"
$bodyFull | Out-File $bodyMd -Encoding utf8
($rec | ConvertTo-Json -Depth 5) | Out-File (Join-Path $dir "feedback_draft.json") -Encoding utf8

# short body for the prefilled URL (URLs have length limits; full body lives in --body-file)
$bodyShort = "sig: $sig`ncategory: $cat`nexpected vs actual: $eva`nerror: $($rec.error_pattern)`nverdict: $($rec.verdict)  errors_remaining: $($rec.errors_remaining)  delta: $($rec.error_delta)"
$encTitle = [uri]::EscapeDataString($title)
$encBody  = [uri]::EscapeDataString($bodyShort)
$encLabel = [uri]::EscapeDataString("$LabelPrefix$($rec.skill_name),category:$cat")
$newUrl   = "https://github.com/$Repo/issues/new?title=$encTitle&body=$encBody&labels=$encLabel"

Write-Host ""
Write-Host "Feedback draft ready (you decide whether to open an issue):" -ForegroundColor Cyan
Write-Host "  body : $bodyMd"
Write-Host ""
Write-Host "0) DEDUP first - is it already reported?" -ForegroundColor Yellow
Write-Host "   gh issue list --repo $Repo --state open --search `"sig:$sig in:title`""
Write-Host ""
Write-Host "A) Open via gh CLI (prints the new issue URL on success):" -ForegroundColor Yellow
Write-Host "   gh issue create --repo $Repo --title `"$title`" --body-file `"$bodyMd`" --label `"$LabelPrefix$($rec.skill_name)`" --label `"category:$cat`""
Write-Host ""
Write-Host "B) Or open in the browser with a PREFILLED issue (no gh needed):" -ForegroundColor Yellow
Write-Host "   $newUrl"
Write-Host ""
Write-Host "If dedup found an open issue N, comment instead:" -ForegroundColor DarkGray
Write-Host "   gh issue comment N --repo $Repo --body-file `"$bodyMd`""
Write-Host ""
Write-Host "(Nothing is filed automatically. After creating, keep the issue URL.)" -ForegroundColor DarkGray
exit 0

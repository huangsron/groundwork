# groundwork

接手陌生或遺留專案的工具集：**理解系統 → 先盤依賴並計畫（核准後才動手）→ 獨立且可重複地驗證**。修復編譯只是其中一項。

驗證的「規格」是**語言/OS 無關的契約**（`skills/verify/references/contract.md`）；「怎麼跑」由 per-platform **adapter** 實作。無對應 adapter 時，照契約用該環境的工具執行。

## Skills

| Skill | 調用 | 何時用 |
|---|---|---|
| architect | `/groundwork:architect` | 需要先理解既有系統、依賴與架構時 |
| plan | `/groundwork:plan` | 需要產生並由你核准修正計畫時（不改碼） |
| verify | `/groundwork:verify` | 需要獨立、可重複地驗證並追蹤剩餘錯誤時 |
| feedback | `/groundwork:feedback` | 需要把失敗整理成回饋時（僅在本地整理，**不會自動送出 GitHub issue**） |

## Quickstart

```bash
claude --plugin-dir "E:/work/ai/groundwork"   # 啟用（改完用 /reload-plugins）
```
依序使用：`/groundwork:architect`（理解）→ `/groundwork:plan`（計畫、待你核准）→ `/groundwork:verify`（執行＋驗證）；`/groundwork:feedback` 按需使用。

## Workflow & artifacts

各 skill 讀前一個的產物、寫自己的，全部放在 `<專案>/_groundwork/`：
```
architect → _map.md, _claims.json
plan      → 讀 _map.md → _plan.md, _manifest.json（含核准記錄）
verify    → 讀 _manifest.json → feedback/ledger.jsonl, _report.md
```
靠**穩定的產物格式**整合，**沒有 orchestrator**——四個 skill 不會自動串接，使用者決策點（核准、是否 feedback）保持顯式。

## Windows adapter（參考實作）

```powershell
powershell -ExecutionPolicy Bypass -File adapters\windows\verify.ps1 `
  -Project <csproj> [-Solution <sln>] [-Exe <exe>] [-PlanId <id>] [-Independent]
```
- 非獨立 / 工作樹髒 / commit 不符 → verdict = **`LOCAL_CHECK`**（「尚未獨立確認」的狀態，**不是 PASS**）。
- 可重複性僅限**同環境**；independence 為程序性而非密碼學級。
- 其餘參數見 `verify.ps1` 註解；完整判準見 `contract.md`。

## Verification metrics

每次 verify 自動寫進 manifest：`iteration`、`errors_remaining`（建置錯誤行數）、`error_delta`（對上一輪）。`error_delta` 連續為 0 = 卡關，應停下回計畫，而非繼續試錯。

## Design

通用性來自**契約與實作分離**：`contract.md` 定義 verdict/manifest/ledger schema、smoke-gate、redaction、signature 與誠實限制（皆語言/OS 無關）；`adapters/<platform>/` 是各平台的實作（`windows` 為 .NET/Windows 參考 adapter，平台=目錄、工具=檔名）。

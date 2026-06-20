# groundwork — toolset for taking on unfamiliar / legacy projects（開發工作區）

Claude Code **plugin**（name=`groundwork`）。一個**工具集**：安全地接手陌生或遺留專案——理解系統、先盤依賴、計畫在核准閘後才執行、獨立且可重複地驗證。**修復編譯只是其中一項，不是全部。**

> 這裡是 plugin 的**開發/source-of-truth**位置（不在 `~/.claude/skills` 內，不會被自動載入）。要啟用照下方「安裝/啟用」。

## 設計原則：契約 vs 實作（這讓它通用）

**驗證的「規格」是語言/OS 無關的契約**（`skills/verify/references/contract.md`）：verdict 判準、manifest/ledger schema、redaction 規則、dedup signature、各型別 smoke-gate。
**「怎麼跑」由 adapter 實作**：`adapters/dotnet-win/*.ps1` 是 **.NET/Windows 的參考 adapter**（PowerShell 是該生態系的原生工具）——它是**一個 adapter，不是通用機制**。其他生態系用各自的 adapter；無對應 adapter 時，agent 直接照契約用該環境的工具執行。

---

## 工具集（4 個 skill，各自單一職責）

| Skill | 調用 | 職責 |
|---|---|---|
| architect | `/groundwork:architect` | 以系統架構師視角**理解專案**，產出共享系統簡報 |
| plan | `/groundwork:plan` | 盤點問題＋設計修正計畫，**不改碼**，止於核准 |
| verify | `/groundwork:verify` | 執行已核准計畫＋獨立可重複驗證（自動 collect 紀錄） |
| feedback | `/groundwork:feedback` | 把失敗轉成回饋，**使用者決定**是否開 issue |

## 整合（靠檔案契約，不用 orchestrator）

各工具讀前一個的產物、寫自己的，全部放在 `<專案>/_groundwork/`。工具之間用**穩定的產物格式**整合，不靠 runtime 耦合；工具間的使用者決策點（核准計畫、是否 feedback）保持透明。

```
architect → _map.md, _claims.json
plan      → 讀 _map.md → _plan.md, _manifest.json（含核准記錄）
verify    → 讀 _manifest.json → feedback/ledger.jsonl, _report.md
feedback  → 讀 ledger.jsonl → GitHub issue / _feedback.md
```
（不做 `/groundwork:run` orchestrator——使用者決策點不該被埋進自動流程；要一鍵時做薄 shell 捷徑即可。）

---

## 目錄結構

```
groundwork/                          ← plugin root
  .claude-plugin/plugin.json         ← manifest（name=groundwork）
  feedback.config.json               ← feedback 設定（repo/label/mode/cooldown）
  skills/
    architect/ SKILL.md                                   ← 理解系統
    plan/      SKILL.md + references/
    verify/    SKILL.md + references/{contract.md, verification-harness.md}
    feedback/  SKILL.md                                   ← 決定是否回報
  adapters/
    dotnet-win/  {verify.ps1, collect.ps1, feedback.ps1}  ← 平台=目錄, 工具=檔名（.NET/Windows 參考實作）
  design/plan-flow.md                ← plan 重整流程草案（改稿中，未套進 SKILL.md）
  README.md
```

---

## 安裝 / 啟用

開發迭代（免重啟，改完 `/reload-plugins`）：
```bash
claude --plugin-dir "E:/work/ai/groundwork"
```
之後即可 `/groundwork:plan`、`/groundwork:verify`。分享：push 到 git，`claude plugin install groundwork@github:<org>/<repo>`。

---

## dotnet-win adapter 用法（實作 contract 的參考腳本）

```powershell
powershell -ExecutionPolicy Bypass -File adapters\dotnet-win\verify.ps1 `
  -Project <csproj> [-Solution <sln>] [-Exe <exe>] `
  [-Configuration Debug|Release] [-LaunchSeconds 20] [-ExpectedWindowTitle <regex>] `
  [-ExpectedCommit <sha>] [-PlanId <id>] [-Independent]
```
- 非獨立 / 工作樹髒 / commit 不符 → verdict = **`LOCAL_CHECK`**。`LOCAL_CHECK` **不是 PASS**，是「尚未獨立確認」的**獨立狀態**，不可當通過計算。
- 證據：`<project>\_verify\<timestamp>\manifest.json`（`verdict` 為準）。
- 可重複性僅限**同環境**（不同 SDK/registry/字型/locale 可能改變結果）；independence 為**程序性**而非密碼學級，報告需標 level。

---

## 量化 metrics（最小起點）

adapter 每次自動寫進 manifest：`iteration`、`errors_remaining`、`error_delta`（用 `<project>\_verify\iteration-state.json` 自動算）——不靠 agent 自評。先只看這兩數字、跑數次真實任務再決定是否擴充。

---

## feedback（兩層：自動收集 + 使用者決定發布）

**1) 自動收集（Collector，平台獨立、本地）**：adapter 每次跑完呼叫 `collect.ps1`，把**清洗後**最小紀錄 append 到本地 `<project>\.groundwork\feedback\ledger.jsonl`。無網路、不影響 verdict（best-effort）。redaction 為 **best-effort（規則不完整），對外分享前仍需人工複查**。
**2) 使用者決定發布（選用，目前 GitHub adapter）**：判 `FAIL/INCONCLUSIVE/crash/false_verdict` 時，由**使用者決定**是否開 issue：`feedback.ps1` 印出去重搜尋＋**兩種開法**（(A) `gh issue create` 指令，回網址；(B) 預填 new-issue 網址，免 gh）。**零自動送出**。發布是可換的 sink（GitHub 只是一個 adapter）。

---

## 現況
- 兩 skill 以 TDD-for-skills 建立、壓力情境合規、多輪 Codex 審查、必修項已補。
- dotnet-win adapter 對真實專案實測通過；硬化項（WER 誤判、harness hash、limitations JSON、最小 metrics、feedback redaction）已修並驗證。
- **語言無關 contract** 已抽出（`skills/verify/references/contract.md`）。
- **改稿中**：`design/plan-flow.md`（具體 S0–S7、通用 S1、架構師簡報）尚未套進 `plan/SKILL.md`。

## 待辦
- [ ] 把 design 流程套進 `plan/SKILL.md`；新增 plan 端 ecosystem adapters（dispatch）
- [ ] 升級 S2 為「系統架構師簡報」（修正 2，尚未做）
- [ ] 跑數次真實任務看 metrics／feedback；視需要 git init 本工作區

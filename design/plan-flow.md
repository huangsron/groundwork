# /groundwork:plan — 重整後具體流程（草案 v2）

> **狀態：SUPERSEDED（歷史草稿，勿照此實作）** — 本文的 `_buildfix/` 目錄與 S0–S7 編號檔
> （含 `07_approval.md`）已被現行設計取代：產物一律在 `_groundwork/`（`_plan.md` ＋
> `_manifest.json` 核准記錄），流程見 `skills/plan/SKILL.md`。僅留作設計脈絡。
> 原則不變：全程**唯讀、不改任何產品碼**，止於交付可核准的計畫。
> v2 自我精修：S2 補「怎麼抓」配方＋白話總結；每步加「完成判準」；釐清回退歸屬；S3 交叉引用既有 `dependency-probes.md` 不重複。

---

## 如何使用（一句話）
依序跑 S0→S7，**每步寫一個編號檔到 `<被修專案根>/_buildfix/`**；過關卡才進下一步；S7 交付後停下等使用者核准，核准了才換 `/groundwork:verify` 執行。

| 步 | 動作 | 產出檔 | 完成判準（gate） |
|---|---|---|---|
| S0 契約 | 定範圍/成功層級/可改禁改/搜尋根 | `00_contract.md` | 成功層級已擇一、允許路徑明確 |
| S1 系統掃描（先） | 偵測 ecosystem/OS → 派發對應 adapter 探測 → 呈現選項 | `01_env_scan.md` | 每個命中 ecosystem 都有工具鏈矩陣＋缺口選項 |
| S2 專案 MAP（後） | 白話總結＋專案表格＋結構依賴圖 | `02_project_map.md` | 陌生人讀完能說出「這是什麼、幾個可執行件、進入點、跑起來要什麼」 |
| S3 依賴閉包＋搜尋 | 每條依賴可用性驗證＋缺的搜尋紀錄 | `03_dependency_matrix.md` | `INVENTORY_COMPLETE`（見下） |
| S4 重現基準失敗 | 實跑 build、原始 log、error→根因 | `04_build_log.txt` ＋ `04_error_map.md` | 失敗已重現、每個 error 有根因假設 |
| S5 計畫草擬 | 每阻礙處置（含給 verify 的回退規格） | `05_plan.md` | 每阻礙都有處置＋驗證關卡 |
| S6 獨立審查 | reviewer≠規劃者（單人→自審清單） | `06_review.md` | 漏依賴/過早 stub 已被挑過 |
| S7 交付核准 | plan 記錄（機器可讀） | `07_approval.md` | 已交付、等待使用者核准 |

---

## S0 契約 → `00_contract.md`
- 範圍（哪個 sln/csproj、哪些路徑可碰）；**.sln 是「有哪些專案」的真相來源**
- 成功層級**擇一**：只編譯 / 可打包 / 可啟動 / 核心流程可用
- 允許變更路徑 ＆ 禁止清單；搜尋根（含是否預設允許全機搜尋）

## S1 系統掃描（先做）→ `01_env_scan.md`

> 通用原則：**不綁死任何 OS/語言**。三段＝偵測 → 派發 adapter 探測 → 呈現選項。掃描只**提供資訊與選項，不替使用者決定、不自動執行任何選項**。

### S1a 偵測（純輸出，不決策）
- OS/平台、可用 shell。
- 用 marker 檔認 ecosystem（可同時多個）：
  `.NET(*.sln/*.csproj/*.vbproj/*.fsproj)`、`Node(package.json)`、`Java(pom.xml/build.gradle)`、`Python(pyproject.toml/requirements.txt)`、`Rust(Cargo.toml)`、`C/C++(CMakeLists.txt/Makefile/*.vcxproj)`、`Go(go.mod)`…
- 輸出：偵測到的 ecosystem(s) ＋ OS。**不在此決定要跑什麼**。

### S1-dispatch（微小路由）
- 讀 `adapters/dispatch.yaml`（marker → adapter 路徑），偵測命中才載入該 adapter（漸進揭露）。新增 ecosystem 只需加一目錄＋一行，不動主流程。

### S1b 探測（跑命中的 adapter；mono-repo 就跑多個）
- **adapter ＝ 一份文件（markdown/YAML）**，描述「跑哪些指令、如何解讀輸出、如何填矩陣」——**不是程式碼**，不需執行引擎。
- 每個 adapter 輸出正規化 `ToolchainMatrix`：
  ```
  ecosystem
  tools: [{ name, required_version, detected_version, status: ok|missing|mismatch }]
  gaps:  [{ tool, gap_type: missing|version_mismatch|ambiguous,
            options: [{ label, action_hint }],   # 純文字選項，非可執行指令
            decision_required: true|false }]      # true → 流程在 S5 前先請使用者確認
  raw_evidence: 原始指令輸出（給人驗證）
  ```
- **generic fallback**（無對應 adapter）：只收集 lock/build script/CI config 線索、標 `status: unknown`、請人研判——**不猜測**。
- 預載 adapter（先做有明確 build 問題的）：`dotnet`、`node`、`java`、`python`；其餘按需再加。

### S1c 呈現選項（資訊，不決策）
- 每個 gap 列**選項**，例：「.NET 3.5 未裝 → (1)裝 3.5 targeting pack (2)retarget 已裝的 4.8 (3)中止」。
- 多 ecosystem **分組呈現、不強行合併衝突**，讓人看清楚。
- 越界判定：S1 產生 options＝OK；S1 **替使用者選 / 自動執行某選項＝越界**（選擇是 S5 的事）。

> `dotnet-on-windows` adapter（範例內容，供參考——原本寫死在 S1 的指令搬來這）：
> ```powershell
> [System.Environment]::OSVersion.VersionString; $PSVersionTable.PSVersion
> & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe
> dotnet --list-sdks; dotnet --list-runtimes
> Get-ChildItem "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP" -Recurse | Get-ItemProperty -Name Version,Release -EA SilentlyContinue | Where-Object { $_.PSChildName -match "^(?!S)\p{L}" } | Select-Object PSChildName,Version,Release
> Get-ChildItem "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework" -Directory | Select-Object Name
> where.exe nuget.exe 2>$null
> ```
> 解讀：把每行結果填入 `tools[]`；TargetFramework 未安裝 → 一條 `gaps[]`，`options` 列「裝 targeting pack / retarget 已裝版本 / 中止」，`decision_required:true`。

## S2 專案 MAP（後做）→ `02_project_map.md`
**先白話、後表格、再圖**——這樣才真的 30 秒看懂。

**(a) 白話總結（3–5 句，置頂）**：這是什麼系統、給誰用、幾個可執行部件、技術棧、跑起來需要什麼外部資源（DB/FTP/網路）。可由視窗文字、SQL、README 推論並標〔推測〕。

**(b) 方案摘要**：方案名/路徑、專案數與類型分布、各專案目標框架、建置組合。

**(c) 專案表（每 .csproj 一列）**：
`名稱/路徑 | 語言 | OutputType | TargetFramework | 進入點 | 模組職責 | 依賴專案 | 重要外部組件 | Native/COM | DB provider | 設定檔 | Designer/RESX | 備註`

**怎麼抓（可照做的配方）**：
- 專案清單：parse `.sln` 的 `Project(...) = "Name", "path", "{guid}"`
- 每 csproj：讀 `<OutputType>`、`<TargetFrameworkVersion>`/`<TargetFramework>`、`<RootNamespace>`、`<Reference Include>`+`<HintPath>`、`<ProjectReference>`、`<PackageReference>`/`packages.config`、`<PreBuildEvent>`/`<PostBuildEvent>`
- 進入點：grep `static\s+.*\bMain\s*\(` ／ `Application\.Run\(` ／ `class\s+Startup` ／ `Global\.asax`（格式記成 `[WinExe] Program.cs→FrmMain`）
- DB provider：grep `System.Data.SqlClient|Sybase.Data.AseClient|Oracle\.|System.Data.OleDb|Npgsql|MySql\.`
- Native/COM：grep `DllImport|ComImport|<COMReference|Interop\.`
- 設定/binding：讀 `app.config`/`web.config` 找 `<bindingRedirect`

**.NET 老專案必抓但常漏**：`bindingRedirect`（build 不報、執行爆）、`packages.config` vs `PackageReference`（混用 S3 會找錯）、Pre/Post-build event（xcopy/regasm/tlbexp）、`.shproj`、`Directory.Build.props`。

**(d) 結構依賴圖**（mermaid，無法渲染則文字）：專案→專案、→組件/套件、→native/COM、→DB/外部。
（此處只畫「結構」供看懂；「真實檔在哪、能不能 build」留給 S3。）

## S3 依賴閉包＋搜尋 → `03_dependency_matrix.md`
依 skill 既有 `references/dependency-probes.md` 的 6 層 probe 與搜尋順序執行（不在此重複）。重點：
- 每條依賴**可用性驗證**；缺的依序搜 `repo→git history→舊build產物→快取/GAC→(旗標)全機→原廠`，找到真檔才比對 SHA/版本/契約/架構/授權。
- **`INVENTORY_COMPLETE`**：每條已分類、每個缺的有搜尋紀錄、基準失敗已重現、無未解必要依賴（有→BLOCKED）。
- 處置優先序：`真實原始碼/原binary > 官方套件 > 相容版本 > 重建 > adapter > stub(最後手段，需特別求核准)`。
- 若需「全機搜尋」→ 在此列**旗標**，S5 寫入計畫、S7 一併核准（避免線性流程悖論）。

## S4 重現基準失敗 → `04_build_log.txt` ＋ `04_error_map.md`
實跑 build，**原始 log 不裁剪**（給 verify/工具機直接 grep）；另出 `error code → 根因假設` 對映（給人讀）。

## S5 計畫草擬 → `05_plan.md`
每阻礙：根因＋證據、要改哪些檔、預測結果、驗證關卡、依賴處置（照優先序）。
**回退**＝這裡只「規劃」未來由 `/groundwork:verify` 執行的修改之回退方式（plan 本身不改碼）；唯讀盤點步驟不需回退。
若 S3 標了全機搜尋旗標，在此寫明供核准。

## S6 獨立審查 → `06_review.md`
reviewer ≠ 規劃者：挑漏依賴、過早 stub、有無更忠於原系統的還原、風險。
**單人情境** fallback：改用 10 條固定自審清單，並於 `07_approval.md` 記「已自審、無第二人」。

## S7 交付核准 → `07_approval.md`
機器可讀記錄：plan id/hash、scope、成功層級、允許路徑、將用 harness（hash）。
→ 核准後換 `/groundwork:verify`；verify 讀此檔、把 plan id 傳給 `verify.ps1 -PlanId`。

---

## 修訂紀錄
**v2**：加「如何使用」＋每步 gate；S2 改「白話→表格→圖」＋可照做 grep/parse 配方；釐清回退歸屬；S3 交叉引用 `dependency-probes.md`；全機搜尋旗標化。
**v3（本次，通用化 S1）**：S1 從 Windows/.NET 寫死改為**語言/OS 無關三段**（偵測→派發 adapter→呈現選項）；adapter 為**文件非程式**、放 `adapters/<eco>/`＋`dispatch.yaml`；加 `ToolchainMatrix` schema、`generic` fallback、mono-repo 分組、`decision_required` 旗標；**掃描只給選項不決策**（選擇留 S5）。原 PowerShell 指令搬進 `dotnet-on-windows` adapter 範例。

## 待辦（核准後才做，目前不動 skill）
- [ ] 寫進 `/groundwork:plan/SKILL.md`（Phases→S0–S7＋產出檔＋gate）
- [ ] 建 `adapters/`：`dispatch.yaml` ＋ `dotnet/ node/ java/ python/ generic/`（每個一份文件描述指令與解讀），漸進揭露
- [ ] 補 `references/project-map-template.md`
- [ ] 交接：plan `07_approval.md` → verify `-PlanId`

# /groundwork:architect — 多 agent 掃描管線（設計，已核准 2026-07-09）

> 原則不變：全程**唯讀、不改任何產品碼**。輸出仍是 `<project>/_groundwork/` 下的
> `_map.md`、`_map-detail.md`、`_claims.json`。

## 目標

把現行 Team 段（兩句話的「workers 平行 + 單一 synthesizer」）落實為可執行的四階段管線：
**多視角平行掃描 → 交叉比對 → 對抗驗證 → 報告**。報告與地圖只在對抗驗證完成後才產出。

## 角色與 model

| 角色 | 執行者 | Model | 職責 | 禁區 |
|------|--------|-------|------|------|
| 調度員 | 主對話 | （主對話） | 問使用者、派工、收結果 | 不掃檔案、不下結論 |
| 掃描員 ×5 | subagent | **Haiku** | 各帶一個 lens 全目錄掃描，回傳 claims | 不做綜合結論 |
| synthesizer | subagent | **繼承主對話 model** | 交叉比對＋最終寫報告 | 不掃檔案（只讀 claims 與 verdicts） |
| 對抗驗證員 | subagent | **Sonnet** | 帶「推翻它」任務查證據，回 verdict | 不寫報告 |

三權分立：**掃描者不做結論、綜合者不掃檔案、驗證者不寫報告**。

## 四階段流程

### Phase 0 — 開場詢問（調度員）
AskUserQuestion 一題：
1. ⭐ 全套多 agent 管線
2. 現行單人掃描（一次綜合 pass，跳過 Phase 1–3 的團隊機制）

### Phase 1 — 平行掃描
- 一次派出 5 個 Haiku subagent（同一訊息並行），每個 prompt 只寫：
  「你是視角 X 的掃描員，先讀 `references/lens-X.md` 照做；掃描根目錄 `<path>`；
  最終回覆只回 claims JSON。」
- claims 條目：`{ text, kind: fact|inference|unknown, evidence: "file:line 或指令輸出", confidence, lens }`
- 掃描員掛掉或回空 → 該視角列入 `_map.md` 的「Not analyzed / unknowns」，**不補猜**。

### Phase 2 — 交叉比對（synthesizer 第一回合）
- 收齊全部 claims 轉交 synthesizer subagent。
- 合併同義主張，為每條標 `corroboration`：
  - `agreed` — 多視角一致
  - `conflicted` — 視角間矛盾（列出兩造與各自證據）
  - `single` — 僅一視角提出
- 產出：合併後 claims 清單＋矛盾清單＋HIGH 風險清單，回給調度員。**此階段不寫報告。**

### Phase 3 — 對抗驗證
- 調度員先問使用者範圍（此時能具體報出「N 條矛盾、M 條 HIGH」）：
  1. ⭐ 只驗 HIGH＋conflicted
  2. 全部 claims 都驗
  3. 關鍵全驗＋其餘隨機抽 10 條（選項文字中顯示實際條數）
- 每條待驗主張派一個 Sonnet subagent，prompt：「先讀 `references/adversarial-verify.md`；
  你的任務是**推翻**這條主張：〈claim＋證據〉。回 verdict JSON。」
- verdict：`confirmed | refuted | unverifiable`＋反證或確認證據。

### Phase 4 — 報告（synthesizer 第二回合）
- 用 SendMessage 叫回**同一個** synthesizer（保留其比對脈絡），附上全部 verdicts。
- 整合規則：
  - `refuted` → 從地圖移除或降級為 unknown；`_map.md` 可信度標記註明「經對抗驗證推翻 N 條」
  - `unverifiable` → 保留但標 unknown/低信心
- 寫出 `_map.md`（決策視圖）、`_map-detail.md`（六節完整簡報）、`_claims.json`。

## `_claims.json` schema（單一檔案原則不變，加三欄）

```json
{ "text": "...", "kind": "fact|inference|unknown", "evidence": "...", "confidence": 0.9,
  "lens": "structure|dependencies|dataflow|runtime|risk",
  "corroboration": "agreed|conflicted|single",
  "verdict": "confirmed|refuted|unverifiable"   // 僅被驗過的條目有此欄
}
```

## 五個視角（references/ 每檔含：找什麼、證據格式、輸出 schema、常見陷阱）

| 檔案 | 看什麼 |
|------|--------|
| `lens-structure.md` | 元件邊界、責任、依賴方向 |
| `lens-dependencies.md` | 建置鏈、外部套件、toolchain 缺口 |
| `lens-dataflow.md` | 主要流程、狀態擁有者、資料儲存 |
| `lens-runtime.md` | 設定來源、外部整合、部署拓撲 |
| `lens-risk.md` | 啟動崩潰探測（launch-crash probe 全文移入）、單點故障、技術債 |

另加 `references/adversarial-verify.md`：驗證員攻擊手冊（找反證、重讀原始檔、
檢查引用的 file:line 是否真的存在且支持主張）。

## 檔案異動

- `skills/architect/SKILL.md`：Team 段改寫為本管線＋角色/model 表；
  launch-crash probe 細節移至 `lens-risk.md`，SKILL.md 留一行指引。
- 新增 `skills/architect/references/`：上述 6 檔。

## Addendum（2026-07-09，實作審查後補充；均已寫入 SKILL.md）

- Phase 2/4：synthesizer 掛掉或回空 → 以相同輸入重派一次；再失敗 → 中止並向使用者回報部分結果。
- Phase 3：驗證員掛掉或回空 → 該條 claim 無 verdict、視同 unverifiable（`_claims.json` 不寫 `verdict` 欄位）。
- 單人模式：所有 claim 的 `corroboration` 一律 `single`、皆無 `verdict`。
- verdict JSON 增加 `claim` 欄位（回帶原 claim 全文），Phase 4 才能把 verdict 對回 claim。
- HIGH 定義：帶 `HIGH launch-crash risk:` 前綴的 claim，加上 synthesizer 判斷會阻斷啟動或造成資料損失者。

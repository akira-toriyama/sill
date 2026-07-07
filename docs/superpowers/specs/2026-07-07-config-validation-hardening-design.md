# config validation hardening（#52 scope A）— design

- **date**: 2026-07-07
- **status**: draft（brainstorming 経由・owner レビュー待ち）
- **出自**: `akira-toriyama/projects` t-0046（config/schema family consolidation epic）の #52 を split した scope A。epic は 2026-07-07 に close 済み。
- **tasks**: A1=t-van5（ready）/ A2=t-wnvm / A3=t-5qxd ／ 非対象 B=t-vzjh（decode 単一ソース・deferred）
- **対象 repo**: sill（ConfigSchema engine）+ facet / wand / perch（consumer）

---

## 1. 背景 — 前提が動いていた

t-0046 body は #52 を「**descriptor を emit だけでなく validation の単一ソースに**」と定義していた。しかし 2026-07-07 の 5モジュール監査（sill/facet/wand/perch/chord を file:line で実測）で、その前提は**既に満たされている**ことが判明した:

- **emit + validation は family-wide で既に単一ソース済み**。facet/wand/perch は 3つとも `configSpec`（`ConfigSchema.Spec<Root>`）1本から `jsonSchema()`（emit）も `validate()`（検証）も導出している。sill 側は `foldedRoot()`→`SchemaEmit`（emit）と `makeDescriptor().validate()`（検証）が同じ `sections` を消費する（sill `ConfigSchema.swift:240-251, 347-349`）。#138-S3 で emit の単一ソースが出荷され、t-0029 で validate も配線済み。

つまり epic が想定した「emit と validation の二重」は解消済み。**実際に残っている二重管理は次の 2 つ**である:

1. **decode が descriptor と別物**。typed model は今も**別の手書き parser**で組まれ、emit/validate を駆動する descriptor とは独立した機構。sill の `Spec.decode`（`ConfigSchema.swift:169-179`）は各 field の app 供給 `apply` closure を dispatch するだけで、`.table` section しか処理せず `.arrayOfTables`/`.dynamicTable` は skip する。`apply` の coercion は宣言 `kind` に束縛されないため、`kind == .integer` なのに `value.asString` を読む apply が green でコンパイルできる（engine-level の drift の種）。
2. **validate が load 時に走らない**。facet/perch は daemon load 経路で validate せず lenient（clamp/drop）。schema 違反はユーザが手動で `config --validate` を叩いた時だけ見える。

この 2 つが「**editor は green（＋ `--validate` clean）なのに load は黙って別の事をする**」という実害クラスの根。scope A は **(2) を塞ぎ、(1) の実害を無害化**する（(1) の根治＝decode 単一ソース化は scope B へ分離）。

### 監査の要点（app 別・file:line）

- **facet**: `configSpec`（`FacetConfig+Spec.swift:107`）→ emit/validate 単一ソース。load（`FacetConfig+Decode.swift:387`）は validate を呼ばず、`exclude`/`rule`/`desktop.section`/`desktop.tab` は 4 本の手書き decoder。`--validate` のみ検証（`FacetConfig+Validate.swift:26`）。典型 drift: lens に `match` 無し → editor-green ＆ --validate-clean なのに load で silently drop。
- **wand**: family 最先行。`configSpec.validate()`（`Config.swift:135`）を `--validate` で load 前に実行（`Main.swift:698`）。uniform scalar は descriptor-driven decode（`apply` closure＝実 decode）で既に単一ソース。arrays-of-tables と cross-field（chomp-size gated on theme 等）は手書き。
- **perch**: `configSpec` の Root が throwaway flat `Staged`（`PerchConfig+Spec.swift:112, 51-100`）で、shipped nested `PerchConfig` は手書き assemble（`Config.swift:587-606`）。load は lenient・validate は `--validate` のみ（`Main.swift:324`）。`.dynamicTable`（`overlay.themes.<name>` / `behavior.<bundle-id>` / `search.synonyms`）が **permissive object** ＝ 内部キー typo が schema/validate 両方を素通り（最大の silent gap）。
- **chord**: `Spec<Root>` を採用せず `SchemaDescriptor` DATA family を使用。key inventory は descriptor 単一ソース済み。leaf-DSL（keybind grammar）+ cross-row semantics は意図的に手書き。scope A の対象外（B/天井側）。

---

## 2. scope と non-goals

### in scope（A）

- **A1** validate を load 経路へ（warn・reject しない）
- **A2** perch の permissive dynamicTable に typed inner-key shape
- **A3** hand-mirror な enum/literal/default を 1 ソース化

### out of scope

- **B（deferred, t-vzjh）** descriptor-driven DECODE。手書き parser を消す本命だが sill ConfigSchema の大改造（arrayOfTables/dynamicValue decode + value-tree か macro/property-wrapper bridge + cross-field/条件フック）を要する。pure-Swift は reflection 無しゆえ descriptor→任意 struct の直マップ不可。un-defer trigger 付きで icebox。
- **恒久的に手書き残（#52 の天井・A でも B でも移せない）**:
  - **leaf-DSL grammar** — chord keybind（`mod + mod - key`）、facet `match` WHERE-clause、wand action/template grammar、perch `HotkeyCombo`/theme resolution。descriptor には opaque `.string`。
  - **cross-field / 条件ルール** — lens requires match、workspace forbids match/apply、chomp-size gated on theme 等。field-at-a-time の descriptor では表現不能。
  - **app-bespoke semantics** — alias 解決、cross-row uniqueness、reserved names。symbol-table を要し Draft-07 でも structural validator でも表現不能（chord は `x-*-constraints` の hover でのみ discoverability を担保）。

---

## 3. A1 — validate on the LOAD path（warn, not reject）

### 目的
load 経路で schema 違反を surface し、editor/validate/load が黙って乖離しないようにする。

### 設計
- 各アプリの load 経路で `configSpec.validate(root)` を実行し、返った `[ValidationError]` を **warning として log/stderr に出す**。
- **daemon 安全則は不変**: load は従来どおり lenient（clamp/drop）で continue する。**reject しない**。「弾く」のではなく「見せる」。これは perch の clamp-don-t-reject 則（`Config.swift:4-7`）と整合。
- validate は nested tree（`Toml.parse`）を要する一方 decode は flat map（`Toml.parseFlat`）を読む app がある。既に `--validate` 経路が nested parse をしているので、その parse を load 側でも再利用 or 併走させる（二重 parse コストは起動 1 回のみで許容）。

### app 別
- **facet**: `FacetConfig.load`（`FacetConfig+Decode.swift:387`）に validate-then-warn を追加。既存の `FacetConfig.validate`（`+Validate.swift:26`）を再利用。
- **perch**: `PerchConfig.load/parse`（`Config.swift:541,576`）に同様追加。clamp 則維持。
- **wand**: `--validate` は既に load 前 validate 済（`Main.swift:698`）。daemon の `runServer`（`Main.swift:254`）load 経路でも同じ warn を出すか判断・実装（他 2 app と挙動を揃える方向を推奨）。

### error handling
- parse 不能（TOML syntax error）: 従来の load 失敗挙動を踏襲（A1 は変えない）。
- schema 違反: warning surface のみ。exit code は変えない（daemon は起動継続）。

### testing
- 各 app: 既知の違反を含む config を load し、warning が **load 経路**で出ることを assert（`--validate` だけでなく）。clamp/drop 挙動は不変であることも確認。

---

## 4. A2 — perch typed dynamicTable inner-key shape

### 目的
perch の `.dynamicTable`（open map）内部キーの typo を emit/validate が検査できるようにする（最大の silent gap を閉じる）。

### 現状
`overlay.themes.<name>`（`Spec.swift:208`）/ `behavior.<bundle-id>`（`Spec.swift:331`）/ `search.synonyms`（`Spec.swift:388`）が permissive object（`additionalProperties:true`）。実際の内部キー期待（`pill-bg`/`accent`/`text`/... や `roles`/`min-size`/`appear-effect`/...）は手書き decode（`Config.swift:825,740,879`）にのみ存在。typo（`pillbg` vs `pill-bg`）は schema/validate を素通りし load は黙って default。

### 設計
- sill には既に `DynamicValue = keyPattern + boxed value ObjectShape`（`SchemaDescriptor.swift:134-145`）があり、facet が dynamic-ordinal desktop で typed 化済み（t-kz0m）。
- perch の 3 つの permissive open map を、**inner `ObjectShape` を持つ `DynamicValue`** へ置換する。key は任意文字列（palette 名 / bundle-id）なので `keyPattern` は許容的に（例 `.*` または bundle-id パターン）、value shape に内部キーの `SchemaField` 群を宣言。
- これで emit（patternProperties + inner properties）も validate（keyPattern + 再帰）も内部キーを検査できる（sill `Validator.swift:168-200` step 7 が既に対応）。

### sill engine の確認事項
facet の dynamicValue は ordinal-keyed（`^0*[1-9][0-9]*$`）。perch は **open-string-key + typed inner shape**。engine の `DynamicValue`/Validator step 7 がこの組合せを既にカバーするか要確認。カバー済みなら perch-only の変更。隙間があれば sill を最小拡張（その場合 A2 の repos に sill が乗る）。

### testing
- perch: typo った内部キーを含む dynamicTable を `--validate`（＋A1 後は load）で flag することを assert。正しいキーは通ること。emit の drift ガード（`ConfigSchemaDriftTests`）は committed schema 再生成で自動。

---

## 5. A3 — kill hand-mirrored enums / literals / defaults

### 目的
宣言と手書きに二重化している enum domain / bound / default を 1 ソースへ寄せ、片側だけ変えた時の drift を消す。

### 対象（app 別）
- **facet**: `exclude.action` の enum が descriptor 側 literal（`Spec.swift:255`）と decode の `ExclusionAction`（`ExclusionRules.swift:21`）で二重。desktop の type/apply 語彙も literal。→ descriptor の domain を `ExclusionAction.allCases.map(\.rawValue)` 由来化（`raise-on-open`/`rail.edge` が既に採る良パターン `Spec.swift:120,142` の横展開）。
- **wand**: `[failsafe]` の `5..300` / default `30` / `esc` が descriptor（`Config+Spec.swift:160-166`）と runtime clamp（`Config.swift:432-438`）に literal 重複。→ 共有定数へ hoist し双方が cite。
- **perch**: default が 3 重管理（Staged seed `Spec.swift:52-97` / spec `def:` / `PerchConfig.default` `Config.swift:509-535`）。→ 1 ソース化（少なくとも「shown default = resolved default」を保証する形に）。

### 注意（変えない意図的 asymmetry）
- schema range を**advisory に緩く**取り runtime で clamp する箇所（wand `clampMs` min:0、perch の clamp band）は **意図的**。A3 は「重複 literal の 1 本化」であって「strict 化」ではない。clamp-don-t-reject 則は不変。

### testing
- 各 app: enum/default が 1 ソースから導出されることを test（例: descriptor の action domain == `ExclusionAction.allCases`）。既存 `ConfigSchemaDriftTests` と併せて回帰ガード。

---

## 6. 実装順・成功基準

### 順序
1. **A1**（最優先・最小変更・実害 drift をほぼ全消し）→ 単独 PR（facet/perch/wand、または app 別 PR）。
2. **A2**（perch の silent gap）。
3. **A3**（機械的 DRY・per-app）。

各スライスは独立に PR→close 可能（epic ぶら下がり回避が split の目的）。

### 成功基準
- **A1**: facet/perch/wand とも、schema 違反を含む config を通常 load した時に warning が出る（手動 `--validate` 不要）。load は従来どおり継続（reject しない）。test 追加。
- **A2**: perch の 3 dynamicTable で内部キー typo が validate に flag される。正当な dynamic 名は誤検知しない。
- **A3**: 対象の enum/default が 1 ソース由来。片側だけ変えると test が落ちる（drift ガード）。

### 非目標の明示
- typed model の decode 単一ソース化（B）は本 scope で**やらない**。
- leaf-DSL / cross-field / app-bespoke semantics は手書きのまま（天井）。

---

## 7. 未決事項（owner 確認したい点）

1. **A1 の PR 粒度**: facet/perch/wand を 1 PR（family sweep）か、app 別 3 PR か。→ lean = app 別（各 repo で独立 close・[[sweep-include-tests]] に沿って Tests も各 repo で）。
2. **wand daemon load の warn**: 他 2 app と揃えて daemon load でも warn を出すか（現状は `--validate` のみ load 前検証）。→ lean = 揃える。
3. **A2 の sill engine 拡張要否**: open-string-key + typed inner shape を engine が既にカバーするかの確認結果次第。

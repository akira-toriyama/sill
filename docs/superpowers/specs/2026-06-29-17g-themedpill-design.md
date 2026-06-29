# #17g — ThemedPill（表示/indicator pill）SwiftUI-native 設計

> ROADMAP **#17g**（furrow **t-kjcr**）の主部品。**perch 適用の最初の実ゲート**（ThemedPill 一つで perch の hint-pill UI ほぼ全域が解放）。
> 設計承認: **route=SwiftUI-native（feature-superset）／scope=表示・indicator 専用**＝ユーザー確定 2026-06-29。公開 API 面も同日承認。本書は spec-review 用の正本。
> 根拠調査（2026-06-29・code-level, 並列リーダー5本）: sill `ThemedChip`/`ThemedChipView`/`ThemedBackdropView`/`ThemedBorder`、perch `HintPainter`/`Theme`/`Config`、prism `Gallery`/`ChipShowcase`/`KitCatalog` の現行コード読込。

## 1. 目的・位置づけ

perch の `HintPainter`（796行・universal hint-pill draw）は、1つの描画器で **button/chip/tag/badge/list-row/search-indicator/error-state** を兼ねている。これを sill の単一ウィジェット **`ThemedPill`** に吸収し、prism 全テーマで live 確認できるようにする。perch は静止アプリのため、prism mock で de-risk 後そのまま実適用まで運べる（実適用＝裏方配線は Phase B の別作業）。

**住み分け（確定）**:
- **`ThemedChip`**（既存・AppKit）= **操作する** token（tap/delete/select/focus）。現状維持。
- **`ThemedPill`**（新規・**純 SwiftUI**）= **表示/indicator** surface。5 shape・two-color typed-prefix label・idle/matched/miss の結果状態・frost・drop shadow・corner badge・app 駆動 motion passthrough。

**床（AppKit 使用可ポリシー準拠）**: pill は IME も非activating窓殻も要らない＝**純 SwiftUI で実装し AppKit 面を増やさない**。`ThemedChip` は別途 SwiftUI 化（本書スコープ外）。neon/hue-cycle border のみ #17k（任意 path stroke）完成後に合成で後付け。

**版**: 機能追加＝次 minor（`v1.33.0` の次）。`#17e`(#86) の tag 状況を merge 時に確認してから採番（並行作業ハザード）。

## 2. 既存コードの状態（実装者の足場）

### 2.1 合成する既存 SwiftUI 部品 — 再実装しない
- **`ThemedBackdropView<S: Shape>`**（`Sources/ThemeKitUI/ThemedBackdropView.swift:42`）: surface 塗り＋optional border。`public init(palette:in:fill:bordered:)`（:50）、`enum BackdropFill { auto, solid, scrim(opacity:), clear }`（:26-37）。**任意 `Shape` を mask** し `backgroundAlpha` を尊重（:63,:72,:79）。pill の **surface（capsule/rounded-rect/circle/tag/underline）はこれに shape を渡して合成**。
- **frost** = SwiftUI `.ultraThinMaterial`（ポリシー: blur/vibrancy は Material）。専用 BlurBackdrop ファイルは無く、Material を直接適用するのが現行作法（`ThemedBackdropView.swift` 内で Material 参照あり）。
- **themed shadow** = `palette.shadow(level)`（`PaletteKit.swift:398`）＋ `Elevation` enum（`Palette.swift:1002-1014`）。
- **配色** = `ResolvedPalette` の canonical role のみ（`PaletteKit.swift:38-78`）。role 名は発明しない。`palette.uiFont(role)`・`palette.onPrimary()`・`bestContrast(on:)` 等のヘルパあり。

### 2.2 perch consumer の要求（`HintPainter.swift`）— ThemedPill が満たすべき機能
- **5 shape preset**（`shapeFor` :626-686）: `.pill`(radius10) / `.square`(radius1) / `.circle`(単字 oval、多字は pill fallback) / `.underline`(body 無し＋下に 2pt accent bar、L/R inset4pt :657-667) / `.tag`(rounded rect＋左へ 6pt 突出・8pt 高の三角を1パス :668-684)。
- **two-color typed-prefix label**（:354-377・**署名機能**）: `keys.uppercased()` を prefix(入力済み＝accent 色、miss 時 error 色)＋suffix(残り＝text 色) に分割、1つの中央寄せ文字列として描画。
- **tri-state**（:282-351）: idle-unmatched=accent hairline@0.55 / idle-matched=accent glow(blur7)＋accent 実線2pt（**fill は変えない**）/ miss=missColor 塗り(frost-aware alpha)＋missColor border 2pt＋prefix も赤。
- **drop shadow**（:271-280）: 全 pill 下に黒@0.35・blur8・offset(0,-2)＝浮遊カード感。
- **frost vs solid**（:204-207）: blur ON=低 alpha 透過 / blur OFF=alpha+0.45 で不透明寄せ。pill surface 色＝`spec.background` hex＋`backgroundAlpha`（標準 role でない translucent surface）。
- **corner badge**（`drawModifierBadge` :564-594）: 右上に修飾キー glyph（⌃⌥⇧⌘）or glyph+verb、10pt semibold、accent@0.95、inset 3pt/1pt。
- **motion**（:224-256）: per-pill scale/dx/dy/alpha（appear/match/unmatch/all-pill offset/ghost）。**perch app 側 essential**＝ThemedPill は transform/opacity を**素通すだけ**。
- **非interactive**（:109 `hitTest -> nil`）: overlay の純 indicator。focus も editing も無い。

### 2.3 perch token → sill role bridge（既に殆ど出来ている）
perch は**独自 palette を持たず** sill `PaletteKit.resolve(spec)` の薄い bridge（`HintPainter.swift:713-757`、`Theme.swift:34` で `import Palette`）。canonical role を **4つだけ** clean に使う:

| perch | sill role | 備考 |
|---|---|---|
| pill-bg / `spec.background` | `background` | translucent surface のベース |
| text | `foreground` | label suffix 色 |
| accent | `primary` | prefix/matched/border |
| miss | `error` | miss 状態 |
| pill-bg-alpha | `backgroundAlpha` | 透過（surfaceAlpha slot） |
| `system`(固定黒・非flip) | `backgroundMode` | concrete bg から自動導出 |

→ **ResolvedPalette 駆動の ThemedPill は perch の色要求の strict superset**。sill role でないのは2つだけ:
1. **frosted alpha policy**（`perchPillAlpha` `Theme.swift:48`、0.85 light / 0.30 dark）: slot は `backgroundAlpha` だが **value policy は app 側**。→ ThemedPill は `surfaceAlpha: Double?` の口を持ち、値は consumer が渡す（sill は値を持たない）。
2. **`[overlay].accent` override**（`HintPainter.swift:739-744`）: sill に per-app accent override は無い（設計 #5）。→ ThemedPill は `accent: Color?`（既定 `palette.primary`）の口を持つ。

> perch は muted/secondary/tertiary/border/hover/selection を**使わない**（`Config.swift:849-853`）。ThemedPill がこれら role を使う箇所は ResolvedPalette の既定にフォールバックする＝perch custom palette には影響しない。

## 3. 公開 API

```swift
// Sources/ThemeKitUI/ThemedPillView.swift — 純 SwiftUI・表示/indicator 専用
public struct ThemedPillView: View {
    public enum Shape: Sendable { case pill, square, circle, underline, tag }
    public enum State: Sendable { case idle, matched, miss }   // miss == error 結果

    public init(
        palette: ResolvedPalette,
        label: String,
        shape: Shape = .pill,
        state: State = .idle,
        typedCount: Int = 0,          // 先頭 N 文字を accent 色で（two-color prefix）
        badge: String? = nil,         // 任意・右上 corner badge
        accent: Color? = nil,         // palette.primary を上書き（[overlay].accent 用）
        surfaceAlpha: Double? = nil,  // 塗りの透過（perch frost slot）
        frosted: Bool = false,        // 塗りの背後に .ultraThinMaterial
        elevated: Bool = true,        // themed drop shadow
        transform: CGAffineTransform = .identity,  // app 駆動 motion passthrough
        opacity: Double = 1
    )
    public var body: some View { … }
}

// ergonomic（任意）: extension View { func themedPill(…) -> some View }
```

- **`typedCount` は `state` と直交**: 入力進捗の色分け（prefix）と idle/matched/miss は別軸（perch 同様）。
- v1 に **border-effect 引数は無い**（neon/hue-cycle は #17k 後に後付け）。
- **leading icon は v1 に入れない**（perch hint pill は icon を持たない＝YAGNI。後続 consumer が要れば追加）。

## 4. 部品別の設計（描画の中身）

### 4.1 Shape → SwiftUI Shape
- `.pill` = `Capsule()`
- `.square` = `RoundedRectangle(cornerRadius: 1, style: .continuous)`
- `.circle` = `Circle()`（単字のみ。`label.count > 1` は `.pill` に fallback＝perch 同挙動）
- `.underline` = **surface/border を描かない**。label 下に 2pt の accent bar（L/R inset 4pt）。
- `.tag` = カスタム `Shape`（`struct TagShape: Shape`）: rounded rect（radius10）＋左向き三角（rect.minX から外へ 6pt、高さ 8pt）を1パスに連結。fill/stroke 両方がこの形に乗る。

surface は `ThemedBackdropView(palette:, in: <resolved shape>, fill:)`。tag/underline 等の custom Shape も `ThemedBackdropView<S: Shape>` の generic にそのまま渡せる。

### 4.2 two-color typed-prefix label
- `prefix = String(label.prefix(typedCount))`、`suffix = String(label.dropFirst(typedCount))`。
- `Text(prefix).foregroundColor(prefixColor) + Text(suffix).foregroundColor(Color(nsColor: palette.foreground))`。
- `prefixColor = state == .miss ? Color(nsColor: palette.error) : (accent ?? Color(nsColor: palette.primary))`。
- 中央寄せ。font = `palette.uiFont(.body)` ベースに weight semibold（perch 相当）。
- **純粋分割関数**を切る（test 対象）: `splitLabel(_ label: String, typedCount: Int) -> (prefix: String, suffix: String)`（clamp 込み）。

### 4.3 tri-state（idle / matched / miss）
| state | fill | border | 追加 |
|---|---|---|---|
| `.idle` | `background@surfaceAlpha` | accent@0.55, 1pt hairline | — |
| `.matched` | **不変**（idle と同じ） | accent 実線 2pt | native `.shadow(color: accent.opacity(0.5), radius: 7)` glow |
| `.miss` | error wash@alpha | error 2pt | prefix も error 色 |

- border は `ThemedBackdropView(bordered:)` ではなく **`.overlay(shape.stroke(...))`** で state 別に出す（色/太さを state で切替えるため）。
- matched の glow は **stroke overlay に付ける native `.shadow`**（`.overlay(shape.stroke(accent, lineWidth: 2).shadow(color: accent.opacity(0.5), radius: 7))`）。AppKit `NSShadow` 不要。これは pill 全体の elevation `.shadow`（4.5）とは別レイヤ＝2 つの shadow が共存して良い。
- `.underline` は border overlay を**出さない**（surface 無し＝accent bar のみ）。

### 4.4 fill / frost
- 基本 fill = `ThemedBackdropView` の `.scrim(opacity: surfaceAlpha ?? 1)`（background role の透過塗り）。`surfaceAlpha == nil` は不透明。
- `frosted == true`: 塗りの**背後**に `.ultraThinMaterial` を `clipShape(shape)` で敷く（Material blur）。perch の「blur ON=低alpha / OFF=+0.45」は consumer が `surfaceAlpha`/`frosted` を渡して再現。

### 4.5 shadow / badge / motion
- **shadow**: `elevated == true` で `.shadow`（`palette.shadow(.dp2)` 相当の色/blur/offset）。`compositingGroup()` 後に適用し、shape 全体へ。SwiftUI の `.shadow` は描画形に沿う＝AppKit の masksToBounds glow 消失 gotcha は**無い**。
- **badge**: `badge != nil` で `.overlay(alignment: .topTrailing) { Text(badge).font(...semibold).foregroundColor(accent).padding(...) }`。
- **motion passthrough**: body 末尾に `.transformEffect(transform).opacity(opacity)`。prism は既定（identity / 1）。

## 5. body 構造（合成図）

```
ZStack {
  if frosted {                       // frost 床
    Color.clear.background(.ultraThinMaterial).clipShape(shape)
  }
  if shape != .underline {           // tinted 塗り（underline は描かない）
    ThemedBackdropView(palette: palette, in: shape, fill: .scrim(opacity: surfaceAlpha ?? 1))
  }
  label2color                        // two-color Text（中央）
  if shape == .underline { accentBar }   // body 無しモードの 2pt bar
}
.overlay(borderStroke(for: state))   // idle/matched/miss の stroke（matched は別途 .shadow glow）
.overlay(alignment: .topTrailing) { badgeView }
.compositingGroup()
.shadow(themedShadow, if: elevated)  // drop shadow
.transformEffect(transform)
.opacity(opacity)
```

## 6. prism showcase（必須）

- **`Sources/prism/PillShowcase.swift`** に `struct MockThemedPill: View { let p: ResolvedPalette; … }`。
  - **名前衝突回避**: 既存 `MockPill` は perch app specimen（`Specimens.swift:303`）＝別物。`MockThemedPill` を使う。
  - grid: **5 shape × {idle, matched, miss}**、**frost/solid**、**badge 有無**、**typed-prefix（typedCount 0→full）** の段。`ChipShowcase.swift:15-134` の構成を踏襲。
- **登録**: `Gallery.swift:334` の `widgetFamily(p:)` `.action` case（:344-349）に `WidgetSection(kitComponent("ThemedPill"), p: p) { MockThemedPill(p: p) }` を追加。
- **catalog**: `KitCatalog.swift:53-505` に `KitComponent(name:"ThemedPill", module:"ThemeKitUI", kind:…, family:.action, …)` を追加（copy-ref 用、`ThemedChip` エントリ :175-197 を雛形に）。
- 全テーマ live＋animatable テーマは `ThemeCard`（`Gallery.swift:241-309`）が per-frame 再配色。

## 7. test

CLT-only 母艦では `swift test`（XCTest）は走らない＝CI 専用。純ロジックのみ XCTest:
- `splitLabel(_:typedCount:)` の prefix/suffix 分割（境界: 0 / 全長 / 超過 clamp / 空文字）。
- shape → SwiftUI Shape のマッピング（特に `.circle` の単字/多字 fallback 判定 `isCircleEligible(label:)`）。
- state → prefixColor / border 選択の純関数。
- `surfaceAlpha`/`accent` の既定解決。
描画そのものは **prism live 撮影で証明**（prism recipe）。

## 8. deferred（v1 外・明記）

- **neon/cyber/vapor/rainbow/hue-cycle border** → **#17k（t-01ys）**。現 `ThemedBorder` は roundedRect しか stroke しない（`ThemedBorder.swift:138-139`）＝tag/underline/capsule path 非対応。#17k が「任意 path stroke」を入れた後、ThemedPill に effect-border 引数を**合成で**後付け。
- **DisplayLink→Combine clock util** / **cascade・radial menu placement** = t-kjcr の**別 small part**（#17k halo / facet 用）＝別 spec。本書スコープ外。
- **particles / ghost / appear-match motion** = perch app 側 essential（t-yc68 線引き）。ThemedPill は transform/opacity を素通すのみ。

## 9. 実装手順（低リスク→高リスク・TDD）

1. **純ロジック＋test 先行**: `splitLabel` / `isCircleEligible` / state→色 セレクタを純関数で切り、XCTest を先に書く（RED→GREEN）。
2. **`TagShape: Shape`** を実装（geometry 単体で確認可能）。
3. **`ThemedPillView`** body を合成で組む（`ThemedBackdropView` surface＋two-color label＋state border＋frost/shadow/badge/motion）。
4. `swift build`（ローカル gate）。
5. **prism showcase**（`PillShowcase.swift`＋`Gallery` 登録＋`KitCatalog` エントリ）。
6. `.build/debug/prism` を起動し **全テーマ live 撮影**（prism recipe・preview override で静的化）。5 shape・tri-state・two-color・frost・badge を目視確認。
7. PR（worktree `feat-17g-themedpill` → origin/main）。CI green で squash-merge＋次 minor tag（版は merge 時に #17e tag 状況を確認）。PR 本文に `SetStatus-task` footer（t-kjcr）。

## 10. 検証・リスク

- **CLT 盲点**: `swift test` はローカル不可＝描画バグは prism 目視＋CI のみ。→ ロジックは純関数化して XCTest、見た目は prism 撮影で必ず確認。
- **`ThemedBackdropView` の Material 経路**: frost を `.ultraThinMaterial` 直書きにするか、`ThemedBackdropView` が Material fill を既に持つなら再利用するか、実装時に同ファイルを確認して DRY に寄せる（要なら 1 行の合成）。
- **tag/underline の generic Shape 受け渡し**: `ThemedBackdropView<S: Shape>` に custom Shape を渡せること、`.underline` の body 非描画分岐が崩れないことを build＋prism で確認。
- **並行作業ハザード**: origin/main は #17e（#86）まで進行中。本作業は worktree 隔離済。版採番は merge 直前に再確認（sibling が tag を取っていないか）。

## 11. 完了の定義（end-state）

- `Sources/ThemeKitUI/ThemedPillView.swift`（純 SwiftUI・`NSViewRepresentable` ゼロ・AppKit draw 呼び出しゼロ）が存在し `swift build` green。
- 5 shape・two-color typed-prefix label・idle/matched/miss・frost・drop shadow・corner badge・transform/opacity passthrough を備える。
- prism `.action` タブに `MockThemedPill` が全テーマ live 表示され、目視確認済。
- 純ロジック XCTest green（CI）。
- AppKit 床 = 据え置き（IME 編集コア＋窓殻のみ。ThemedPill は床を増やさない）。

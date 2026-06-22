# #14a — DRY 集約（トークン非依存）実装プラン

> 状態: **設計/監査済・実装未着手**（plan/execution 分割の handoff・2026-06-22）。
> #14 のうち**トークン非依存の安全な前半**だけを 1 PR に。本丸 `ThemedControl: NSView` 基底（hover/press/focus/focus-ring/`preview*`/`fx*` の状態機械を 1 基底へ）は **#14b 以降に別途設計**（grill/brainstorm 必須）。
> 前提: #13 完了済（origin/main `b761c35` 以降・`v1.19.0`）＝`Space`/`Radius`/`Elevation` トークン + `ResolvedPalette.shadow(_:)` + 9 widget の layerTxn は既に `Duration.enter` 配線済。
> ブランチ `feat-dry-14a`（origin/main から）。次セッションは `git fetch` → 本プラン → 実装 → `swift build` → prism before/after → 敵対的レビュー → PR → CI 緑 → squash-merge + `v1.20.0`。
> 監査根拠 = 6-agent workflow（2026-06-22・各クラスタ exact 行付き）。**未達成は各クラスタ行で明示。**

## 検証方針（house ルール・全クラスタ共通）
- `swift build` = ローカル唯一ゲート（CLT）。`swift test` は **CI のみ**＝[[sweep-include-tests]]：**Tests/ も grep**してから private 削除（消す helper を反射参照するテストが無いか）。
- **値保存が本質**（DRY は挙動を変えない）。確定的 before/after は **prism ライブ撮影**（agent は画面収録不可＝**maintainer 確認ゲート**）。ROADMAP の #14 撮影ゲート＝Button/FAB/Checkbox/Chip **＋ ToolBar・ComboBox/Menu**（共有ヘルパ経由の hover/snap 回帰を捕捉）。
- 各 widget の DEBUG probe（`shadowOpacity`/`_badgeFill` 等）で CI XCTest 値照合。各 PR で敵対的レビュー（多視点）。
- **置く場所の鉄則**: NSColor/CGPath/CALayer に触れる物は **PaletteKit か ThemeKit**。`Palette` は CoreGraphics-free を維持（純粋トークンのみ）。

## 着手順（安全・高レバレッジ順）
1. C2 bestContrast public化（最安全・1行+6削除）
2. C3 themeBackingScale 抽出（init-time も値同一）
3. C1 layerTxn 共有 free func（Border/fadeOut/Grow は据置）
4. C6 Elevation struct 統合（Button/Group/FAB-pressed は完全一致・**FAB-rest は要判断**・ToolBar は formula 据置）
5. C5 ControlRole + `color(for:)`（最も込み入る・per-widget アダプタ・neutral 意味）
6. C4 CornerPath 抽出（**単一消費者=任意/低優先**・将来 ThemedControl の seam 用）

新規ファイル: `Sources/ThemeKit/Shared.swift`（free `layerTxn` + `NSView.themeBackingScale`）、必要なら `Sources/ThemeKit/CornerPath.swift`。PaletteKit 追加: `bestContrast` public・`ControlRole`+`color(for:)`(+任意 `onColor(for:)`)。

---

## C2 — `bestContrast` を public 化（contrast-ink 6コピー廃止）★最優先・最安全
- **現状**: `PaletteKit.swift:139-150` に `@MainActor func bestContrast(on:) -> NSColor`（**internal**・`onPrimary`/`onSecondary` が既に使用）。同一 math を 6 widget が private 再実装:
  - `ThemedButton.swift:296-302` `ink(on:)`（呼: 308, 334）
  - `ThemedButtonGroup.swift:217-223` `contrastInk(on:)`（呼: 228・`.withAlphaComponent(0.25)` は呼側）
  - `ThemedCheckbox.swift:194-200` `ink(on:)`（呼: 210＝primary/muted）
  - `ThemedChip.swift:269-275` `ink(on:)`（呼: 315 error, 342 overlay）
  - `ThemedFAB.swift:248-254` `ink(on:)`（呼: 276 overlay）
  - `ThemedTooltip.swift:311-317` `ink(on:)`（呼: 323 foreground）※doc-comment が「bestContrast が internal だから」と明記＝公開で存在理由消滅
- **全コピー byte-identical**（local var `l` vs `L` のみ＝出力不変）。
- **やること**: `bestContrast` を `ResolvedPalette` の `public` メソッドに昇格（`onPrimary` 等の隣・body 不変）→ 6 private 削除 → 各呼出を `palette.bestContrast(on: X)` に。ButtonGroup の `.withAlphaComponent(0.25)` は呼側に残す。`Palette` には**降ろさない**（NSColor 使用）。
- **据置**: FAB `roleInk`・Chip `onPrimary/onSecondary` 直呼・ToolBar `barInk` は**既に共有 accessor**＝重複でない。
- **リスク**: 極低（byte-identical）。証跡: build + PaletteKitTests に代表色で .black/.white 照合 + prism（contained Button/secondary FAB/error Chip/Tooltip を light+neon で同一確認）。

## C3 — `NSView.themeBackingScale` 抽出
- **Family A（byte-identical `private var backingScale { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }`）**: Button:520, ButtonGroup:107, Checkbox:177, Chip:473, FAB:370, Divider:187, ToolBar:186。inline 同形: Skeleton:316, TextField:523, Border:157。
- **Family B（init-time・screen-only `NSScreen.main?.backingScaleFactor ?? 2`）**: Border:101, Divider:113, Skeleton:117, TextField:220 → **init 時は window==nil なので themeBackingScale が screen に短絡＝値同一**。
- **やること**: `Sources/ThemeKit/Shared.swift` に `@MainActor extension NSView { var themeBackingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 } }`。11 サイト採用（Family A は `private var backingScale { themeBackingScale }` の 1 行 alias 残しで呼出 ~25 箇所を無改変にしてもよい）。
- **据置（controller・別意図）**: Tooltip:476（`_anchor?` 経由・self.window 無し）、ComboBox:592-597 / Menu:416（**host window を意図的に読む**＝panel が order-in 前で scale stale・fallback 無し）。
- **リスク**: 極低（A は no-op・B は init で値同一）。⚠ `Tests/` を `backingScale` で grep してから削除。

## C1 — `layerTxn` 共有 free func
- **9 widget の private `layerTxn(animated:)` が意味的 byte-identical**（single/multi-line timing の差のみ・全て `Duration.enter` 配線済）: Button:594, TextField:367, FAB:440, Checkbox:345, Chip:539, Divider:276, ToolBar:523, ButtonGroup:374, Skeleton:323。
- **inline snap-only**（`begin/setDisableActions(true)/commit`）: ComboBox:265, Menu:264, List:639 → `layerTxn(animated:false){}` に。
- **canonical**: `Sources/ThemeKit/Shared.swift` に
  ```swift
  @MainActor func layerTxn(animated: Bool, duration: TimeInterval = ThemedTransition.Duration.enter, _ body: () -> Void) {
      CATransaction.begin()
      if animated { CATransaction.setAnimationDuration(duration); CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut)) }
      else { CATransaction.setDisableActions(true) }
      body(); CATransaction.commit()
  }
  ```
  internal free func（QuartzCore 使用＝ThemeKit 限定）。9 private 削除→呼出は無修飾のまま free func に解決。`duration` param は **PopupFade.transact**（combo 0.12/tooltip 0.16）を畳むためだけ＝`PopupFade.transact` を `layerTxn(animated:animated, duration:duration, body)` の 1 行委譲に。
- **据置（挙動非等価）**: `ThemedBorder.swift:297` の layerTxn は **snap-only `setDisableActions(!animated)`**（animated 枝に duration/timing 無し）＝canonical の animated 枝と非等価。**animated:true で呼ばれていない事を確認できるまで据置**（折り込むと stroke が 0.16s で animate 開始＝挙動変化）。`PopupPanel.fadeOut`（completion block + 遅延 orderOut＝child-window stale バグ対策）据置。`ThemedMenu` Grow（CABasicAnimation transform）・Skeleton makePulse/makeWave（layer 付き keyframe ループ）は別物＝据置。
- **リスク**: 低。9 個は textual no-op。証跡: build + prism で Button/Checkbox/Chip/FAB の hover/press/focus（`animated:animated` 経路）と ComboBox/Menu/List/TextField の theme-switch snap を before/after 比較（差分 NIL のはず）。PopupFade combo/tooltip が 0.12/0.16 のままを確認。

## C6 — inline Elevation struct を `palette.shadow(.dpN)` に統合
- `ThemedButton.swift:354-365`: 4 状態が #13 ladder と**完全一致**（pressed→`.dp8` / focused→`.dp6` / hovered→`.dp4` / rest→`.dp2` / disabled・non-contained→`.flat`）。struct 削除→`palette.shadow(...)`。呼側は `e.opacity/.radius/.offsetY` でラベル一致＝無改変。
- `ThemedButtonGroup.swift:232-250`: inline literal 0.20/3/-1 ＝**完全 dp2**。`let e = palette.shadow(.dp2)` で 3 prop 代入に。
- `ThemedFAB.swift:282-290`: pressed (0.34/12/-7)＝**完全 dp12**。rest (0.30/8/-3)＝**off-ladder**（radius8/dy3 は dp8 一致だが opacity 0.30≠dp8 の 0.28）。**【要判断①】** (a) `.dp8` に snap（rest 影が ~7% 薄く・#13 doc が既に「#14a で snap」と明記＝**推奨**）／(b) dp ladder に 0.30 rung 追加／(c) FAB-rest だけ literal 据置で pressed のみ DRY。
- `ThemedToolBar.swift:318-322`: **連続 formula（elevation 0..24・opacity 定数 0.24・radius/offset 線形）＝ladder の case でない**＝**formula 据置**。任意 DRY: 同じ tuple 型なので `palette.shadow(continuousDp: Int)` overload を PaletteKit に足して formula をそこへ移すのは additive（必須でない）。
- **符号**: `shadow(_:)` は既に dy を負化（`-t.dy`）＝採用側は結果をそのまま使い**再負化しない**（現 struct は手書き負値で内部整合・1:1 swap）。
- **リスク**: Button/Group/FAB-pressed/ToolBar = ~0。唯一の視覚変化は FAB-rest snap（判断①）。証跡: probe（shadowOpacity/Radius/OffsetY）を CI XCTest で旧値照合（FAB-rest のみ期待値変更を明記）+ prism FAB rest/pressed・Button 全状態・Group を before/after。

## C5 — `ControlRole` + `ResolvedPalette.color(for:)`（最も込み入る）
- **byte-identical roleColor（primary/secondary/error）**: Button:285, ButtonGroup:208（共に `ThemedButton.Role`）。
- **subset**: FAB:228（`FAB.Role={primary,secondary}`）。**superset**: Chip:257（`Chip.Role` に `.neutral→foreground`）。
- **別 enum・非 role arm あり（role arm のみ委譲・残し）**: ToolBar:278 `surfaceFill`（`Surface={surface,primary,secondary,transparent}`・**NSColor? 返し**・`.surface`/`.transparent` 据置）、List:1334 `resolvedTint`（`ListTint={none,primary,secondary,error,custom}`・`.none→clear`/`.custom(hex)` 据置）、List:1558 `badgeColors`（`BadgeRole`・**(fill,ink) wash tuple**・base 色のみ role 由来）。**degenerate**: Checkbox:202（role 1 case＝`palette.primary` 直・任意）。
- **canonical（PaletteKit）**:
  ```swift
  public enum ControlRole { case neutral, primary, secondary, error }
  @MainActor public extension ResolvedPalette {
      func color(for role: ControlRole) -> NSColor { switch role { case .neutral: return foreground; case .primary: return primary; case .secondary: return secondary; case .error: return error } }
  }
  ```
  任意で `onColor(for:)`（contrast-ink ミラー＝C2 と連動: primary→onPrimary()/secondary→onSecondary()/error→bestContrast(on:error)/neutral→foreground）も同居させ FAB `roleInk`/Chip `inkColor`/ToolBar `barInk` を畳む。
- **各 widget は自分の public enum を維持**（FAB に .error 無し等は意図的 API＝**広げない**）→ 呼側で ControlRole にマップ（薄い adapter）。**role arm のみ** `color(for:)` 委譲・非 role arm（surface/transparent/none/custom/wash）は据置。
- **【要判断②】** `color(for: .neutral)` = **foreground**（Chip 一致＝推奨）。Badge の neutral は **muted のまま**（wash tuple 側で明示・shared を通さない）。
- **リスク**: 純 role switch は低（byte-identical）。集中点: neutral 意味・subset enum・非 role arm の取りこぼし（exhaustive switch が構造破綻は捕捉、誤 default は捕捉せず＝arm 逐語維持）。証跡: prism Chip/FAB/ButtonGroup/ToolBar/List-badge を全テーマ before/after + List DEBUG 色 probe（`_badgeFill` 等）を CI で照合。**公開 enum 不変＝facet/wand/perch 無影響**を確認。

## C4 — `CornerPath` 抽出（単一消費者・任意/低優先）
- **真の selective-corner builder は ThemedButton のみ**: `closedCornerPath`+`borderPath`（`ThemedButton.swift:464-516`・rect/radius/corners/edges 全 param＝既に de-facto free・呼: 532/544/548）。
- 他は全て **plain all-corners** CGPath/NSBezierPath（FAB/Chip/Checkbox/TextField/Border/ToolBar/ButtonGroup-shadow/List/Scroller）＝**重複でない**（しかも List/Scroller は NSBezierPath で API 系統が別）。
- **rule-of-three 未達**（消費者 1）。justification = テスト可能化 + 将来 ThemedControl 基底の seam。**#14a に含めるかは任意**（含めるなら ThemedButton の pair を `enum CornerPath { static closed(...); static bordered(...) }` に `Sources/ThemeKit/CornerPath.swift`（CG のみ・非 @MainActor）へ移し `BorderEdges`(ThemedButton:52-59) も同居・呼 3 箇所だけ retarget。**plain all-corners は触らない**）。
- **リスク**: 低（純コード移動・byte-identical 契約）。証跡: prism で standalone Button（all-corners）と ButtonGroup（selective corner + open seam edge＝唯一 corners≠.all/edges≠.all が発火）を before/after。

---

## 実装開始時に maintainer へ確認する判断（2つ）
1. **FAB-rest elevation 0.30→dp8(0.28) に snap**（推奨・~7% 薄い rest 影・#13 doc 既に予告）か、FAB-rest を literal 据置か。
2. **`color(for: .neutral)` = foreground**（推奨・Chip 一致）でよいか。Badge neutral は muted のまま。

（C4 を #14a に含めるか/別出しか、も軽く確認可。）

## ROADMAP 反映
着手で `#14` を「**着手中: PR #N**」、merge で `完了`（PR #N + `v1.20.0`）。本丸 `ThemedControl` 基底は **#14b（別 PR・要設計）**として明示し、暗黙にしない。

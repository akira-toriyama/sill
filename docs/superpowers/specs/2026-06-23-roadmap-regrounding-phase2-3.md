# #16.5 — sill ロードマップ再接地（Phase 2/3 再枠組み）

> 状態: **調査完了・整理プラン確定／ROADMAP.md の実改訂は次セッションで本書を読んで実行**（ユーザー指示 2026-06-23）。
> このセッションの役割 = 調査結論 + 実行プランの引き継ぎ（git 管理）。次セッション = #16.5 本体（ROADMAP.md の Phase 2/3 書き換え）。
> 進捗 SSOT は `docs/ROADMAP.md`。本書は #16.5 の根拠・実行手順。

## 0. 経緯

- #16（ThemeKitUI = prism の14橋を公開 SwiftUI モジュールに昇格）完了＝PR #70 + `v1.23.0`・2026-06-23。
- #17（native SwiftUI 部品 B）着手前に、ユーザー指示で **「各アプリの実コード + 現 sill を見て #17/Phase3 の枠組み自体を判断（ROADMAP 整理OK・破壊的変更OK・高品質）」**。
- 7-agent 調査 workflow（facet/wand/perch/glance/halo の各リーダー + sill 状態リーダー + plan リーダー〔529 で失敗・影響なし〕）を実施。本書はその結論。

## 1. 調査結論（実証済み）

### 1.1 決定的事実: どのアプリも sill の「ウィジェット部分」を使っていない

各アプリが実際に import している sill モジュール（`grep -rE "^import …" <app>/Sources` 実測）:

| アプリ | LOC | 消費 sill モジュール | ThemeKit / ThemeKitUI |
|---|---|---|---|
| facet | ~27.8k | Palette・PaletteKit・Effects・ConfigSchema（+ Toml） | **未使用** |
| wand | ~14.6k | Palette・Effects・ConfigSchema・CLIKit（+ Toml） | **未使用** |
| perch | ~11.7k | Palette・PaletteKit・Effects・ConfigSchema・CLIKit | **未使用** |
| glance | ~1.4k | Palette・PaletteKit | **未使用** |
| halo | ~1.2k | Effects・ConfigSchema（+ Palette via Effects） | **未使用** |

→ **5アプリすべて、`ThemeKit`（AppKit ウィジェットキット）と `ThemeKitUI`（その SwiftUI 橋）を一切 import していない。** 使っているのは色/効果/設定/CLI の**純粋・AppKit-resolver エンジン部分だけ**。`ThemeKit` / `ThemeKitUI` の唯一の消費者は **prism（ベンチ）**。

### 1.2 各アプリは 100% 非アクティブ overlay/daemon ＝ SwiftUI 化の "content 窓" が無い

| アプリ | 窓モデル | UI 実体 | SwiftUI-on-sill 適合性 |
|---|---|---|---|
| facet | 非アクティブ NSPanel ×3（tree/grid/rail）・LSUIElement | 全て NSView+CG 手描き。global CGEventTap(real-window DnD)・NSTextField(IME 検索)・ScreenCaptureKit サムネ・click-through pet 窓 | **不可**（多大リライトで CGEventTap/IME/per-pixel/ScreenCaptureKit/click-through を失う） |
| wand | 非アクティブ overlay(gesture trail) + non-activating launcher panel | 全て NSView+CG（trail/particle/pet/launcher）。テキスト入力ゼロ。**自前 `NSColorParse`**（PaletteKit 不使用） | **不可**（"shell が app そのもの"・移す content が無い） |
| perch | 非アクティブ daemon・CGEventTap キー入力 | hint pill 等を NSBezierPath 手描き。テキスト入力フィールド無し（query は String 組み立て） | **不可**（SwiftUI は activation 必須＝非アクティブ性を壊す）。#4/#5 で色/border は既に sill 収束済 |
| glance | 非アクティブ NSPanel（becomesKeyOnlyIfNeeded） | read-only NSTextView + MarkdownRenderer(TextKit/NSTextTable) | 実質不可（SwiftUI に NSTextTable 相当の markdown レンダラが無い・別物の「MarkdownKit」が要る） |
| halo | 非アクティブ click-through NSWindow・LSUIElement | RingView（draw 47行）+ SkyLight C コールバック | 不要（pure Effects の理想消費者・"shell が app そのもの"） |

→ 設計 spec が掲げた **「AppKit の殻 + 中身 SwiftUI-on-sill（NSHostingView）」のハイブリッドは applicant がゼロ**。全アプリが「殻＝app 全体」で、移すべき "content" が存在しない（spec §2 が既に "ThemeKit 利用ゼロ/脱AppKit 不成立" を認識・本調査はそれをさらに裏付けた）。

### 1.3 sill の実価値は「純粋共有エンジン」。ウィジェット路線は prism 限定

- 全アプリが実利用 = `Palette`/`PaletteKit`/`Effects`/`ConfigSchema`/`CLIKit`/`Motion`（pure + AppKit-resolver）。**ここが sill の本当の価値で、既にほぼ全アプリに行き渡っている。**
- `ThemeKit`(ウィジェット) / `ThemeKitUI`(SwiftUI 橋) / prism の widget showcase = **デザインベンチ/前方投資**であって、現状アプリ消費はゼロ。
- 既に多くのアプリは pure モジュールに収束済（perch=#4/#5 で border/color 収束・halo=ネイティブで Effects のみ・facet/glance もクリーンに pure 利用）。**残る収束対象は小さい**（主に wand の `NSColorParse`→`PaletteKit`）。

## 2. 含意（ロードマップへの影響）

1. **#17（native SwiftUI 部品 B）は実アプリの消費者がいない**＝prism のためだけに作る前方投資。クリティカルパス `#13→#15→#17` の前提（アプリが SwiftUI 部品を欲しがる）は実コードに反する。
2. **Phase 3（#18-21＝各アプリ SwiftUI-on-sill 化）は前提が崩壊**。どのアプリも移植不可/不要。
3. **sill のコア使命はほぼ達成済**（pure 共有エンジンを全アプリが採用）。残るのは小さな収束 + 任意のデザインベンチ拡充。
4. #16（今回完了）も実アプリ消費はゼロだが、クリーンなモジュール抽出として無害・低コストで完了済（巻き戻し不要）。

## 3. #16.5 でやること（次セッションの実作業）

`docs/ROADMAP.md` の Phase 2/3 + クリティカルパス記述を、実態に合わせて整理する：

1. **#17 を再定義 + 格下げ**: 「native SwiftUI 部品（B）」は**クリティカルパスから外す**。位置づけを「**prism デザインシステム拡充 / 将来 SwiftUI オプション（実アプリ非依存・前方投資）**」と明記。やる/凍結は §4 Q1 の判断後に確定。
2. **Phase 3（#18-21）を再定義**: 「各アプリを SwiftUI-on-sill 化」→ **「各アプリの自前重複（色/効果/設定/CLI）を共有 pure モジュールへ収束」**（#4/#5 perch 型の展開）。各 app repo の follow-up。**ただし残対象は小さい**ことを明記（下記）。
   - **具体的収束対象（実証ベース）**: wand の `NSColorParse`(CastThemePalette/TomeThemePalette)→`PaletteKit.resolve`（旧 #20 の中身）。他アプリは概ね収束済＝opportunistic cleanup のみ。
   - facet/glance/halo/perch は「現状維持＝既に pure モジュールをクリーン消費」と記録（移植 task を消す）。
3. **クリティカルパス/依存の記述を更新**: `#13→#15→#17` 中心の図を廃し、「sill = pure 共有エンジン（達成済）+ デザインベンチ（prism/ThemeKit/ThemeKitUI）+ 小さな per-app 収束」という実態の構造に。
4. **#16 の「将来項目」**（ThemedContainer 基底・CornerPath・palette→Color・#17）を「prism/デザインベンチ文脈の任意項目」に整理（アプリ駆動でないと明記）。
5. **本書へのリンク**を ROADMAP に残す（根拠の所在）。

## 4. Open questions（次セッションで決める＝ユーザー判断）

1. **#17 をどうするか**: (a) 凍結（やらない・実アプリ需要ゼロ）／(b) prism 用デザインシステムとして低優先で継続（Tommy が craft/playground 価値を見出すなら。cf. [[animation-is-a-differentiator]] [[theme-aesthetics]]）。
2. **Phase 3 収束を実際にやるか**: アプリは今でも動作＝必須でない。やるなら [[sill-first-consistency]] の統一感目的。最優先は wand 色収束。優先順と「やる/やらない」。
3. **ThemeKit/ThemeKitUI/prism の位置づけ**: デザインベンチとして育てるか・最小維持か・将来の新アプリ（widget ベース UI を持つもの）に備えた前方投資と割り切るか。
4. **glance の「MarkdownKit」**: SwiftUI/TextKit2 markdown を sill 化する将来項目として残すか（今は不要）。

## 5. 根拠・参照

- 本調査 = 7-agent workflow（2026-06-23・本セッション）。各アプリ verdict は §1。
- 既存設計 spec: [`2026-06-22-sill-generalization-and-swiftui-design.md`](2026-06-22-sill-generalization-and-swiftui-design.md)（§2 で "ThemeKit 利用ゼロ/脱AppKit 不成立" を既に認識・本書はそれを実コードで深掘りし、ハイブリッド案にも applicant が無いことを確認）。
- 現 sill 状態（#13 トークン/#14 DRY+ThemedControl/#15 ListCore/#16 ThemeKitUI）= ROADMAP.md「次の大型テーマ」節。

## 6. 引き継ぎ（未達成を暗黙にしない）

- **未達**: ROADMAP.md の実改訂（Phase 2/3 書き換え）= **次セッションで本書 §3 に沿って実行**。
- 現状: #16 完了（v1.23.0）・main = origin/main 同期・在flight 作業なし・worktree なし（#16 用は撤去済）。
- 次セッション開始手順: `git fetch` → `docs/ROADMAP.md`（origin/main 版）→ 本書 → §3 を ROADMAP に反映（§4 の Q は着手前にユーザーへ確認）。破壊的整理OK・品質重視・1セッションに収めなくてよい。

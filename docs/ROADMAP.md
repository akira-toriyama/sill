# sill やることリスト

- 現行 **v1.5.0**。**番号が小さいほど先**にやる（小さいほど優先度高め）。
- すべて sill 本体の作業（追加は additive・default-off）。
- このファイルが残作業・進捗の**唯一の記録**（git 管理）。

## sill に部品を足す — facet / wand のツリー・ランチャー用（1〜2）

1. **ワークスペースまるごとの並べ替え DnD** — ⚠ **重要・復帰確定**。facet の「ワークスペース1個を掴んで順番を入れ替える」操作。
   いまの sill は **1 行のドラッグ**（窓をワークスペースへ落とす／ヘッダ単体の入替）まで対応済み（v1.3.0）。
   未対応なのは **ヘッダ＋配下の窓を“ひとかたまり”で動かす**並べ替え（複数行が一緒に動く・かたまりのドラッグ画像・
   セクション単位の並べ替え）。facet の昔（filter pivot より前）にあった機能なので、まず **tmp に新規 clone** して
   当時の挙動を発掘 → 設計 → 実装。重いので **別セッション・計画と実行を分ける**。（**/Volumes 配下の facet は触らない**）
2. 横ツールバー `ThemedToolBar` を新規 — wand のランチャー（新規ウィジェット。MUI から設計、別セッションで計画先行）

## sill に部品を足す — perch 用（3〜7）

3. `ThemedChip` を新規 — perch のヒント pill・facet のタグ・キー記号（⌘⇧）
4. perch の自前エフェクトを sill の既存 Effects に寄せる — 追加コードほぼ無し（perch の最初）
5. perch の自前の色計算を sill の PaletteKit に寄せる
6. アニメ用の計算 `ThemedTransition` を新規 — perch・facet・wand 共通
7. 紙吹雪 / 花火を Effects に足す

## sill のその他（8〜11）

8. **文字を MUI 規約に照合して調整** — 原典 grounding で精密比較（急がない）。
   読みづらい確定 = ThemedList の 2 行目（11pt regular muted）と TextField 補助文 → 12pt か medium。
   要再確認 = badge 9pt・shortcut 10pt（MUI 11px 下限未満）。全体は概ね基準内（13pt は macOS 慣習で適正）。
9. **wand のエフェクト一式を sill に移植** — 大きいので別途じっくり（gesture / trail / line-pet）
10. prism のタブを app 別に分割（facet / wand / perch / glance）— いつでも
11. prism のエフェクト切り替えトグルの配置直し — いつでも

## 完了

- **v1.5.0** ThemedList の横スクロール＋キーボードカーソル（.outline で選択と見分け）＋ゼブラ縞（旧 #4/#5/#6）
- **v1.4.0** ThemedList の階層インデント＋折りたたみ（旧 #2）
- **v1.3.0** ThemedList ドラッグ層（行の drop-onto／並べ替え＋キーボード lift）（旧 #1）
- **v1.2.0** スクロールバーの themed 化 + アイコン上下逆の修正 + prism の文字拡大
- **v1.1.0** メニューのサブメニュー（1 段）

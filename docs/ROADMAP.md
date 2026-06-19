# sill やることリスト

- 現行 **v1.6.0**。**番号が小さいほど先**にやる（小さいほど優先度高め）。
- すべて sill 本体の作業（追加は additive・default-off）。
- このファイルが残作業・進捗の**唯一の記録**（git 管理）。

## sill に部品を足す — facet / wand のツリー・ランチャー用（1）

1. 横ツールバー `ThemedToolBar` を新規 — wand のランチャー（新規ウィジェット。MUI から設計、別セッションで計画先行）

## sill に部品を足す — perch 用（2〜6）

2. `ThemedChip` を新規 — perch のヒント pill・facet のタグ・キー記号（⌘⇧）
3. perch の自前エフェクトを sill の既存 Effects に寄せる — 追加コードほぼ無し（perch の最初）
4. perch の自前の色計算を sill の PaletteKit に寄せる
5. アニメ用の計算 `ThemedTransition` を新規 — perch・facet・wand 共通
6. 紙吹雪 / 花火を Effects に足す

## sill のその他（7〜10）

7. **文字を MUI 規約に照合して調整** — 原典 grounding で精密比較（急がない）。
   読みづらい確定 = ThemedList の 2 行目（11pt regular muted）と TextField 補助文 → 12pt か medium。
   要再確認 = badge 9pt・shortcut 10pt（MUI 11px 下限未満）。全体は概ね基準内（13pt は macOS 慣習で適正）。
8. **wand のエフェクト一式を sill に移植** — 大きいので別途じっくり（gesture / trail / line-pet）
9. prism のタブを app 別に分割（facet / wand / perch / glance）— いつでも
10. prism のエフェクト切り替えトグルの配置直し — いつでも

## 完了

- **v1.6.0** ThemedList のチャンク並べ替え — ヘッダ＋配下の行を1かたまりで並べ替え（複数行 dim・節境界フル幅 insertion bar・header grip・chunk ghost）＋キーボード DnD を節境界 aim に共通化（KeyboardDragController）（旧 #1）
- **v1.5.0** ThemedList の横スクロール＋キーボードカーソル（.outline で選択と見分け）＋ゼブラ縞（旧 #4/#5/#6）
- **v1.4.0** ThemedList の階層インデント＋折りたたみ（旧 #2）
- **v1.3.0** ThemedList ドラッグ層（行の drop-onto／並べ替え＋キーボード lift）（旧 #1）
- **v1.2.0** スクロールバーの themed 化 + アイコン上下逆の修正 + prism の文字拡大
- **v1.1.0** メニューのサブメニュー（1 段）

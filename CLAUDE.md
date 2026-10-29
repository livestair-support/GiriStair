# Claude Code・Codex 共通ルール

必ず [AGENTS.md](AGENTS.md)、[docs/DESIGN.md](docs/DESIGN.md)、[docs/UI_PARITY_AUDIT.md](docs/UI_PARITY_AUDIT.md) を読んでから作業してください。

- UIの基準はLiveStairのiPhone実装と、GiriStair 0.2.1で実撮影した共通UIです。新しいページ・詳細・編集・シート・設定行でも、この基準を継承してください。
- LiveStairリポジトリは参照専用です。参照できない場合は推測で再設計せず、その旨を報告してください。
- 共通Stair部品と役割別StairTypographyを使います。文字を一律に太く／小さくしたり、個別のMaterial部品で代用しないでください。
- UIFontを名前から再生成しないでください。UIFontをCTFontへ直接bridgeし、Flutterには端末から取得したfamily名と役割別weightを渡します。PostScript名をfamily欄に使わないでください。
- iPhoneのタブ・選択メニュー・時刻は現在のUIKit bridgeを維持します。スクリーンショットを取得した場合は、画像と実フォント診断の両方を確認してください。
- 詳細・編集・設定のサブページは `StairNavigationBar` / `StairBackButton` を使い、戻る「＜」を統一します。カレンダーはLiveStairの一覧／月間表示切替、年月移動、前月・翌月の操作を基準にします。保存中の無効化・未保存確認・戻るジェスチャーを壊さないでください。
- 生大喜利とネット大喜利を同格に扱い、通常の継続サイト、各周期、競技大会のステージ、お題回、自分の結果、大会全体の上位成績を混同しないでください。
- 作業は別ブランチとPRにまとめ、mainを勝手にマージしないでください。保存互換性と実際に実行した検証範囲を明記してください。

進行中の要件と判断は [docs/WORKFLOW_REVISION.md](docs/WORKFLOW_REVISION.md) に記録します。

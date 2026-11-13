# 要件と検証状況

この表は仕様書のスコープを保持するための開発記録です。「実装済み」と「実機で確認済み」を区別し、未確認を完成扱いにしません。

## 機能

| ID | 要件 | 現在の証拠 | 残作業 |
|---|---|---|---|
| F-01 MUST | 単純リマップ・修飾/メディア | SwiftUI 編集、C++ 入力列テスト、同一出力の参照カウント。実機の q→w が TextEdit へ W と入力されることをユーザーと画面で確認 | メディア/JIS/修飾キーの組合せ、長時間試験 |
| F-02 MUST | 複合・alone/held/after | C++ の閾値、割込み、キー列、修飾キー抑止/復元テスト | 実機でリピート・JIS・アプリの組合せ |
| F-03 MUST | 2〜4 キー同時押し | 2〜4 キーの一致/解放、期限切れ/早い解放テスト | 複数候補の優先順、実機 |
| F-04 MUST | hold/toggle レイヤー | 編集 UI、hold/toggle、レイヤー終了後のキー解放、Space 単押しテスト | 複数レイヤーの競合・実機 |
| F-05 MUST | アプリ/デバイス/入力ソース/配列/変数条件 | 条件コンパイラ、Agent の状態通知、アプリ/変数のテスト | 入力ソース・配列・デバイス/シリアルと unless も入力列テスト済み。実機の組合せ試験が必要 |
| F-06 MUST | デバイス別、除外、内蔵無効化 | シリアル別設定と上書きテスト、IOHID 列挙、接続/切断ハンドラ、UI | 外付け接続時の内蔵無効化と接続復帰を実機検証 |
| F-07 MUST | プロファイル、ショートカット、自動切替 | 作成/複製/名前変更/削除 UI、Carbon ショートカット登録、Agent のアプリ/デバイス選択 | サービス登録後の切替確認、競合ショートカット通知改善 |
| F-08 MUST | デバイス別 Fn/メディア | F1/F キーモードのコアテスト、デバイス UI | F1〜F12 と Fn を複数機種で確認 |
| F-09 SHOULD | マウス・スクロール | 未実装 | ポインティングの捕捉・出力・UI |
| F-10 SHOULD | ユーザーアクション | root はアクション ID のみキュー化。Agent で shell/open_app/input_source/notify を実行 | 実機、スリープアクション |
| F-11 SHOULD | Sticky 修飾キー | 次のキー 1 回の適用・解放のコアテスト | 複数修飾キー・実機 |
| F-12 SHOULD | Karabiner インポート | 単純/複合/デバイス変換、警告一覧、非対応 action フラグの拒否テスト | 実際の複雑な設定一式の互換性確認 |
| F-13 MUST | EventViewer | 署名確認 XPC、入力/出力・時刻・デバイス/usage/修飾キー/ルールの UI。修正版で物理 a の押下・解放を両列に表示することを実機確認 | 不要な HID sentinel/rollover 表示の除外、セキュア欄の実機確認 |
| F-14 MAY | URL/JSON 共有 | 設定/プロファイル JSON 入出力 | rekey:// と .rekeyrules |
| F-15 MAY | マクロ録画 | 未実装 | v2 候補 |

## UI・設定・安全性

| 要件 | 現在の状態 | 追加の確認/作業 |
|---|---|---|
| Swift 6 / SwiftUI、macOS 27、arm64、LSUIElement | リリース app を生成、ネイティブ画面と追加/削除を Computer Use で確認 | 更新版の全画面操作と VoiceOver |
| メニュー、設定、EventViewer | 実装、XPC 接続状態に基づく表示 | サービス稼働中の表示確認 |
| 保存 300 ms、無効 JSON の配布防止 | 設定ストア/フォーム/JSON エディタ、C++ 検証の共有 | 排他トランザクション・3方向統合・競合時の下書き保持を20テストで検証。実機で切替との同時編集を確認 |
| 0600、原子的置換、所有者確認、20 バックアップ、symlink | Swift テストで確認。Core も所有者・モード・ファイルサイズを確認 | fsync / F_FULLFSYNC とディレクトリ同期を実装。停電・iCloud の実機試験は未実施 |
| schema_version | v1 を許可、新しい版は拒否 | 旧版が発生した時点でマイグレーション実装 |
| XPC の署名条件 | root 所有の UI/Agent に対する designated requirement を固定 | インストール後に許可/拒否を実機確認。出荷 Team ID を確定 |
| Core 内の出力キュー（旧 root-only ソケット・共有メモリは廃止） | プロセス内の有界キュー（4096 件）、世代番号でリセット後の再送を防止 | 再起動・キュー溢れの障害注入 |
| イベントを扱う root 1 プロセス（rekey-core）とユーザー Agent | ソースとバイナリを実装 | 評価用出力は既存 Karabiner 仮想 HID サービスにも依存。出荷には独自 dext/IOUserClient 経路が必要 |
| セキュアな入力・ログ | 既定でキーのファイルログなし、secure 状態不明/Agent heartbeat 断で Viewer を抑止 | フォーカス切替の実機検証、os_log とローテーションログ |
| UI 終了時の無効化 | XPC lifecycle と 5 秒の UI lease。ユーザーの一時停止設定と分離 | 正常終了/強制終了/再起動を実機確認 |
| 緊急停止・全キー解放 | 物理修飾キーの長押し、変換出力の一括解放テスト | 占有中の実機障害注入 |
| 日本語/英語 | 日本語/英語リソースと切り替え UI を追加 | 英語の全画面表示・動的文言・エラー文の確認 |
| 初回セットアップ自動進行 | 説明画面と権限タブ、状態の周期更新、登録操作 | Agent 権限の個別状態、全ステップの自動遷移、既存設定の自動提案 |

## 非機能・配布の未達ゲート

- 物理キーから dext 出力まで p99 1 ms / 3 ms、Karabiner 比較は未測定。オフライン `rekey-bench` は別の指標として出力。
- イベントの変換処理は割当ゼロをテスト。リアルタイム専用スレッド化は未実装で、Core の制御処理とイベント処理は同じ run loop。
- 評価用クライアントの `async_post_report` 以降の待ち/割当を除去する独自 IOUserClient 実装は未提供。
- アイドル CPU 0.1%、連続入力 CPU 2%、3 プロセス計 60 MB、24 時間稼働は未測定。
- ログイン後 2 秒、ログイン画面、クラッシュ後 1 秒復帰、スリープ/Bluetooth 復帰 50 回の試験は未実施。SMAppService plist には KeepAlive と 1 秒の throttle を指定しているが、これだけでは復帰時間の証明にならない。
- 実在する Team ID / bundle ID、Developer ID Application / Installer、DriverKit entitlement、独自 dext の署名と承認が必要。現在の Mac では有効な codesigning identity が 0 件。
- 開発用未公証 pkg を管理者認証でインストール済み。アンインストール UI はサービスとログイン登録を解除し app/設定をゴミ箱へ移動する。出荷用の署名・公証・更新時停止・アンインストールのエンドツーエンド検証は未完了。
- Sparkle 2 と試験用署名 appcast は実装・検証中。実配布 URL、署名鍵、更新安全性と公証は未完了。詳細は [配布準備](sparkle-distribution-ja.md)。Homebrew Cask は未実装。
- SIP を変更していない。署名/TCC/DriverKit の承認を迂回する実装はない。
- マイナー OS のベータ試験、macOS 26 用別ブランチ、サポート運用は未着手。

## 検証コマンド

```sh
swift test
scripts/test-core.sh
scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 build/ReKey.app
build/rekey-core --validate "$HOME/Library/Application Support/ReKey/rekey.json"
build/rekey-bench --events 10000
```

Swift テストは設定・所有権・バックアップ・symlink・非対応ルールを扱います。C++ テストは実機 I/O を使わず入力列を再生し、200 ルール/10,000 イベントの処理と割当数を確認します。出力キューは 100,000 件の並行出力の順序を検証します（旧 rekey-vhid の共有リングは Core への統合で廃止）。これらだけで未達ゲートを満たしたとは判断しません。

## 2026-10-21 の実行記録

- Swift の24テスト（モデル・永続化20、XPC コールバック1、フォーカス秘匿判定3）が成功。
- C++ の入力列・ランダム列（20,000 イベント）と、200 ルール/10,000 イベントの割当検査が成功。AddressSanitizer / UndefinedBehaviorSanitizer でも成功。
- 共有リングの 100,000 件の並行送受信が成功。
- リリース app と `build/ReKey-0.1.0-current.pkg` を生成。pkg を展開し、全 14 ファイルの SHA-256 が app と一致すること、root daemon plist が正確に 2 個であること、入れ子の app のコード署名が検証できることを確認。
- pkg 自体は未署名・未公証。`pkgbuild` が非 root のビルド時に `write: Permission denied` を 4 件出すが終了コードは 0。ペイロードの完全性は上記のとおり確認したものの、出荷前にこの診断の原因確認が必要。
- 最初に開いた旧開発 pkg は `build/ReKey-0.1.0.pkg`。認証待ちの元ファイルを置換しないため、更新版を `ReKey-0.1.0-current.pkg` として生成した。実機試験には更新版を使うこと。
- 管理者認証はツールから操作できない OS 認証画面で待機。その後 Mac がロックされ、更新版の UI 操作検証も本人によるロック解除待ちになった。管理者インストールやサービス稼働を確認した記録はまだない。

## 実機セットアップの追加記録

- 管理者インストール、root 所有・署名、root の Core/VHID とユーザー Agent の起動、UI からの XPC 接続を確認。
- サービス不在時の XPC エラー通知で起きる Swift 6 の actor 検査による起動クラッシュを修正し、回帰テストした。
- 初回の SMAppService 登録で承認待ちになっても、残りのサービスを登録し、承認画面へ案内する。
- macOS の POSIX 共有メモリは65,792バイトから81,920バイトに切り上げられる。旧 Core のサイズ検査が接続を拒否していたため、ページ単位で作成・検査するよう修正。実際の shm_open/mmap による別マッピング間の送受信・所有者拒否を回帰テストし、修正版 UI の「仮想 HID 接続済み（評価用）」を確認した。
- ユーザーが Karabiner-Elements を削除。残った特権バックグラウンド項目をオフにし、Core-Service プロセスの終了を確認した。解除専用の一時 pkg はインストールしていない。
- 単独 VirtualHID パッケージ8.6.0の公式署名・公証を検査してインストールし、署名検証済み Manager の activate が成功。Karabiner-Elements 本体は復元していない。
- root Core の IOHIDDeviceOpen も TCC に拒否されることを確認。仕様書の「Agent だけが入力監視を要求する」という前提は実機と異なる。Core の権限状態を報告し、未許可時は取得しない。その他の取得失敗の再試行は1秒間隔とした。
- ad-hoc 署名更新後、SMAppService は enabled でも launchd が EX_CONFIG / needs LWCR update になる例があった。バックグラウンド項目のオフ→オンで更新後サービスの起動を確認。OS 保護は変更していない。
- Core の入力監視を付与して再起動後、キーボード取得と UI の「リマップ有効」「入力サービス 稼働中」を確認。実機 q→w の TextEdit 入力をユーザーと CUA で確認した。検証の一時ルールは削除し、設定ファイルが空の simple 配列に戻ったことを確認。検証文書は build/ReKey-input-check.rtf に保存した。
- 初回の EventViewer では Caps Lock の押下・解放と左 Control への変換が表示されたが、通常の q 入力では表示されなかった。Agent が任意属性の AXSubrole がない場合まで秘匿していたため、属性なしと AX 読み取り失敗を分けて修正し、3テストを追加した。パスワード欄、Secure Event Input、不明/読み取り不能なフォーカスは引き続き非表示。修正版の実機再検証は必要。
- AXSubrole が任意であることは [Apple の属性仕様](https://developer.apple.com/documentation/applicationservices/kaxsubroleattribute)、取得結果の違いは [AXUIElementCopyAttributeValue](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue) に基づく。
- 通常稼働時の Core CPU の短い観測は1.2〜1.6%で、アイドル0.1%目標には未達。専用スレッド・タイマーの改善が必要。回復性能の実機試験も未完了。
- フォーカス修正版を build 17 としてインストール。インストール後の全14ファイルがビルドと一致し、コード署名の厳密検証が成功。Agent の署名更新に対する launchd の拒否は、通常のバックグラウンド項目オフ→オンで解消した。
- 現行アプリを明示して入力監視を追加し直し、Agent も現行パスでアクセシビリティへ追加し直した。単なるスイッチの再操作だけでは古い署名条件が更新されない場合があった。
- 修正版 EventViewer で物理 a の押下・解放と入力/出力両列の表示を確認。検証後に表示を消去して閉じた。入力イベントをファイルに保存していない。

## 設定競合の修正

UI と Agent は同じロックで保存し、Agent の切替は最新設定へのトランザクションとして実行する。UI の変更は読み込み時のスナップショットを基準に統合し、同じ項目の競合はファイルを変更せず通知する。未保存の下書きを周期的な再読込で破棄しない。変更のない保存はファイルやバックアップを更新しない。明示的な再読込・緊急停止からの再開には XPC の再読込操作を使用する。Swift の20テストで競合・並行更新・バックアップの内容を確認済み。

## 最小権限への整理

- 入力監視は rekey-core、アクセシビリティは ReKeyAgent のみへ集約。UI の直接要求と Agent の入力監視要求を削除。
- Agent のアクセシビリティ状態を Core 経由で UI に報告し、500 ms の期限を過ぎると未許可扱い。EventViewer のセキュア入力抑止は維持。
- 更新後、UI/Agent の入力監視と UI のアクセシビリティを無効にした実機で、デバイス一覧・自動切替・リマップ・EventViewer を検証する必要がある。
- 検証: `swift test` 全26テスト、`scripts/test-core.sh`（49,590 assertions と共有メモリ/リングテスト）、`scripts/build-app.sh`、日英 strings の構文検証、app の厳密な署名検証が通過。
- `build/ReKey-0.1.0-least-privilege.pkg` を作成。既知の `write: Permission denied` 4件が出るが終了コードは0。展開した全14ファイルの SHA-256 がビルド済み app と一致。未署名・未公証の開発用パッケージ。

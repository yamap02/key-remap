# ReKey

macOS 27 / Apple Silicon 向けのメニューバー型キーリマッパー。Swift 6 / SwiftUI の設定アプリ、ユーザー権限の Agent、仮想 HID 出力を統合した C++23 の入力コアで構成します。

**現在は開発版です。管理者インストール、root サービスの起動、仮想 HID 接続を確認済みで、物理入力・出力の検証を進めています。出荷版の完成や遅延目標の達成を示すものではありません。**

仕様原本は [docs/specification-ja.md](docs/specification-ja.md)、要件ごとの進捗と残作業は [docs/requirements.md](docs/requirements.md) にあります。

権限と常駐プロセスの削減可否は [実現性レポート](docs/permission-process-assessment-ja.md) にまとめています。
統合後の実装と確認範囲は [実装・検証記録](docs/consolidated-service-validation-ja.md) にあります。
統合後にさらに削減できる範囲は [追加削減レポート](docs/further-minimization-ja.md) にあります。
GUIのメモリ対策と検証範囲は [メモリ削減の実装記録](docs/memory-refactoring-2026-11-06-ja.md) にあります。

## AIを用いた開発とセキュリティについて

ReKey の独自コードは、全面的に生成AIを用いて作成しています。この開発方法と、現在は開発版であることをご理解のうえで利用してください。第三者のコード・ライブラリについては、[参考プロジェクトとサードパーティー](#参考プロジェクトとサードパーティー) に出典とライセンスを記載しています。

開発では、AIを用いたセキュリティレビューとテストを実施しています。ただし、レビューやテストの実施は、脆弱性が存在しないことや、すべての利用環境で安全に動作することを保証するものではありません。確認した内容と未検証事項は、[実装・検証記録](docs/consolidated-service-validation-ja.md) と [要件ごとの進捗・残作業](docs/requirements.md) を参照してください。各記録は記載された時点・対象の確認結果であり、現行コード全体のセキュリティ監査完了を示すものではありません。

ReKey はキーボード入力を扱い、root 権限で動作する入力サービスを含みます。利用前に [必要な権限とその理由](#必要な権限とその理由) を確認し、信頼できるビルドだけをインストールしてください。

## ビルドとテスト

必要環境: macOS 27、Apple Silicon、Xcode の macOS 27 SDK / Swift 6、Command Line Tools。

```sh
swift test
scripts/test-core.sh
scripts/build-app.sh
open build/ReKey.app
```

配布まわりの検証は `Tests/Distribution/` にあります。`python3 Tests/Distribution/test_*.py` はそのまま実行できます。`Tests/Distribution/test-build-identity.sh` は `rg` を使い、app をビルドします。`test-appcast.sh` と `test-sparkle-*.py` は Sparkle 2.9.6 のツールを `build/sparkle-tools/bin` に置いてから実行します（`swift build` 後なら `ditto .build/artifacts/sparkle/Sparkle/bin build/sparkle-tools/bin`）。

`build/ReKey.app` に UI、Agent、`rekey-core`、`rekey-bench` と SMAppService 用 plist が入ります。開発用には ad-hoc 署名を使います。app の起動だけでは物理キーボードを占有しません。

```sh
scripts/build-pkg.sh
open build/ReKey-0.1.0.pkg
```

開発用 pkg は未公証です。インストーラは `/Applications/ReKey.app` を root:wheel 所有・他ユーザー書き込み不可に配置します。入力サービスは、この配置にある UI と Agent の署名条件を固定して XPC 接続を受け付けます。ソースツリー内のユーザー所有の app は root サービスから拒否されます。

## 必要な権限とその理由

ReKey は物理キーボードの入力を受け取り、設定に従って変換したキーを仮想キーボードから送り直します。そのため、設定アプリだけで動く一般的なアプリより広い権限が必要です。許可先と用途は次のとおりです。

| 権限・承認 | 何のために必要か | 許可しない場合 |
| --- | --- | --- |
| 管理者認証 | インストーラが `/Applications` にアプリを配置し、root 所有で他ユーザーが書き換えられないようにするため。特権サービスが接続元を検証する前提にもなります。 | pkg をインストールできません。認証は macOS の画面で行います。 |
| バックグラウンド項目 | `rekey-core` とユーザー権限の ReKeyAgent を常駐させ、入力の変換やアプリ条件・ホットキーなどを処理するため。仮想 HID の共有デーモンも登録します。 | 対応するサービスが動かず、リマップや関連機能を利用できません。設定アプリのログイン時起動は別途選択できます。 |
| 入力監視 | `rekey-core` が物理キーボードの入力を取得し、元の入力を占有して変換後のキーに置き換えるため。入力内容に関わる強い許可です。 | 通常のリマップができません。許可先は設定アプリではなく `rekey-core` です。 |
| ドライバ拡張の承認 | Karabiner の仮想 HID ドライバが、変換後のキーを macOS に仮想キーボードの入力として届けるため。 | 仮想キーボードに接続できず、リマップ出力を利用できません。 |
| Device Control and Data Access（アクセシビリティ） | EventViewer 使用中、ReKeyAgent がフォーカス中の画面要素の種類を調べ、パスワード欄などで入力表示を抑止するため。実装は入力欄の文字列を取得せず、種類を確認します。ただし OS の許可自体はこの用途だけに限定されません。 | EventViewer の入力表示は抑止されます。通常のリマップには不要です。 |
| 通知 | ルールの `notify` アクションで通知を表示するため。アクション実行時に要求します。 | 通知を表示できませんが、通常のリマップには不要です。 |

`rekey-core` は root で動作します。現在の出力経路では、Karabiner の仮想 HID 接続デーモンへのクライアント接続に root が必要です。設定画面と ReKeyAgent はユーザー権限で動作し、`shell_command` も Agent のユーザー権限で実行します。root や入力監視の許可は広いアクセスを可能にするため、信頼できるビルドだけをインストールしてください。

EventViewer の表示はパスワード欄や Secure Event Input、監視状態を確認できない場合に抑止する設計です。ただし、フォーカス切り替え時を含む完全な秘匿は検証済みではありません。一度付与した OS の許可は自動では解除されないため、不要になった場合はシステム設定からオフにできます。

## セットアップ

公開版向けの初回導入・更新手順案は [インストールと更新](docs/install-update-ja.md) を参照してください。公開前の署名・公証と実機検証は未完了です。

1. 開発用 pkg をインストールする。管理者認証は Mac の認証画面で行う。
2. `/Applications/ReKey.app` を起動し、「権限」から入力サービスを登録する。
3. システム設定で ReKey のバックグラウンド項目を許可する。公式の仮想 HID ドライバがインストール済みなら、共有の `Karabiner-VirtualHIDDevice-Daemon` も登録する。ドライバ拡張が有効でも、このデーモンが停止していると接続できない。
4. 入力監視では `/Applications/ReKey.app/Contents/Library/HelperTools/rekey-core` のみ許可する。EventViewer を使う場合に限り、Device Control and Data Access（アクセシビリティ）では ReKeyAgent のみを許可する。入力監視の「確認する」は Core 自身から権限を要求し、Finder で `rekey-core` を選択する。リストに見つからなければシステム設定の「＋」からそのファイルを追加し、オンにした後「入力サービスを再起動」を押す。設定アプリ ReKey だけに許可しても Core には反映されない。実機では root Core の取得にも入力監視が必要。
5. 既存の Karabiner-Elements を停止してからリマップを再開する。ReKey は Karabiner の入力サービスを検出すると占有しない。
6. 単純リマップを一つ設定し、EventViewer とテキスト欄で押下・解放を確認する。

開発用出力は、承認・起動済みの `Karabiner-DriverKit-VirtualHIDDevice` サービスに接続します。単独ドライバの公式署名・公証済みパッケージ `Vendor/VirtualHID/dist/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg` を使用でき、Karabiner-Elements 本体は不要です。ドライバ拡張自体の版は1.8.0です。`Vendor/VirtualHID` は Git サブモジュールではなく、上流 `ac836ed8a974cd5182495251855cabdb762f50cb` のファイルをこのリポジトリで追跡しています。仮想キーボードの ready 通知を待って接続済みと表示します。ReKey は同リポジトリの公式 launchd plist を同梱し、SMAppService で接続用デーモンを登録します。共有サービスのため、ReKey の入力サービス解除・アンインストールではこの登録を解除しません。ReKey 固有の dext は未提供です。第三者の署名や provisioning profile を使用して再署名することはありません。

旧版から更新する場合は、UI・Agent・Core を同時に更新して再起動した後、ReKey の両権限と ReKeyAgent の入力監視をシステム設定でオフにできます。設定画面は Core の入力監視と Agent が報告するアクセシビリティの状態を表示します。Agent が未許可・停止・応答切れの場合、EventViewer は入力表示を抑止します。通常のリマップには Agent のアクセシビリティは不要です。EventViewer の「アクセスを許可」から必要なときだけ要求できます。入力欄の AX 確認は EventViewer 表示中だけ行います。一度付与した OS の許可は自動解除されないため、不要ならシステム設定でオフにできます。通知の許可は `notify` アクションを実行するときに要求します。

開発用 ad-hoc 署名は更新でハッシュが変わるため、入力監視の項目を追加し直す必要がある場合があります。登録済みでも更新後のヘルパーが起動しない場合は、システム設定の ReKey バックグラウンド項目をオフ→オンにすると署名登録が更新されます。OS の認証画面は利用者が認証してください。

旧 `rekey-vhid` は Core に統合しました。更新用 pkg は置換前に旧 Core / VHID を停止し、更新後 UI が旧 VHID 登録を解除します。「入力サービスを再起動」で現行 Core と Agent を登録してください。旧 VHID の plist は解除用にのみ同梱し、実行ファイルは配布しません。

## 設定と動作

- 保存先: `~/Library/Application Support/ReKey/rekey.json`。変更は 300 ms のデバウンス後に保存。
- 所有者はログインユーザー、アクセス権は 0600。原子的に置換し、直近 20 世代のバックアップを保持。
- UI と Core が同じ C++ コンパイラでルールを検証。無効な設定は配布しない。Core の再読み込みに失敗した場合は直前の有効な設定を維持。
- デバイス固有設定を優先し、その後にプロファイル共通設定を適用。単純リマップ → レイヤー条件・複合ルール、先勝ち、出力は再評価しない。
- hold レイヤーの起動キーは、単押しなら通常のキーを送る。toggle モードは押すたびに切り替える。
- 複合ルールはフォームまたは JSON で編集。有効な変更を自動保存し、不正な編集はその場にエラーを表示。
- `⌃⌥⌘P` で一時停止・再開（Agent が登録されている場合）。プロファイルにもショートカットを指定可能。
- 緊急停止は物理 `⌃⌥⌘Esc` の 1 秒長押し。Core が全キーを解放し、物理キーボードの占有を解除する。
- EventViewer は表示中に限り最大 2,000 行をメモリ上に保持。パスワード欄・Secure Event Input・Agent の監視切断時は表示を抑止し、閉じると破棄。
- キーボード種別は OS/HID 情報で判定できない場合があるため、デバイス画面で ANSI/ISO/JIS を指定可能。
- MX Keys Mini など Windows 兼用 JIS の「カタカナ／ひらがな／ローマ字」は「日本語・国際キー」→同名の項目（`international2`）を選択する。Mac の「かな」（`japanese_kana`）とは別キー。「変換」（`international4`）・「無変換」（`international5`）・「￥」（`international3`）・「ろ」（`international1`）も指定可能。OS によってキー録音へ通知されないキーはメニューから選択する。接続先やキーボードの OS モードで入力が異なる場合は EventViewer の HID コードで確認する。
- 正規表現は C++ の ECMAScript 形式。UI の保存時にも同じ形式でコンパイルする。
- `shell_command` は Agent のユーザー権限でのみ実行。インポート時はコマンドが含まれることを警告する。

## 計測

```sh
build/rekey-bench --config "$HOME/Library/Application Support/ReKey/rekey.json" --events 10000
```

これは **変換処理単体** の p50/p99（µs）です。物理入力から dext 出力までの遅延とは異なります。`--physical` は未対応として失敗し、架空の実機計測値を返しません。

## 配布署名

```sh
REKEY_SIGNING_IDENTITY='Developer ID Application: ...' \
REKEY_INSTALLER_IDENTITY='Developer ID Installer: ...' \
REKEY_NOTARY_PROFILE='your-keychain-profile' \
scripts/build-pkg.sh
```

実在する Team ID、製品 bundle ID、DriverKit entitlement と provisioning profile は未設定です。現在の `jp.example.rekey` は開発用です。署名済み pkg / 公証 / Homebrew Cask / Sparkle 更新を出荷する前に、[要件表](docs/requirements.md) の配布ゲートを満たす必要があります。

## ライセンス

ReKey の独自部分は [Unlicense](LICENSE.md) で公開します。商用・非商用を問わず、利用・コピー・改変・再配布が可能です。ソフトウェアは無保証で提供します。第三者のコード・ライブラリ・その他の素材には、それぞれのライセンスが適用されます。

## 参考プロジェクトとサードパーティー

ReKey は [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) を参考に開発した独立したプロジェクトです。Karabiner-Elements および pqrs.org の公式製品ではなく、提携・推奨を示すものではありません。Karabiner-Elements 本体は [Unlicense](https://github.com/pqrs-org/Karabiner-Elements/blob/main/LICENSE.md) で公開されていますが、その依存物には個別のライセンスがあります。

仮想 HID のクライアント・評価用ドライバには、[pqrs-org/Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) の実装を使用しています。`Vendor/VirtualHID` に取り込んだ上流スナップショットは [`ac836ed8a974cd5182495251855cabdb762f50cb`](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/ac836ed8a974cd5182495251855cabdb762f50cb) です。本体のライセンスは [Unlicense](Vendor/VirtualHID/LICENSE.md)、内包する依存物にはそれぞれのライセンスが適用されます。

Sparkle、Asio、pqrs C++ ヘッダー、Microsoft GSL、nlohmann/json、nod、type_safe などの利用部品と通知文は [第三者ライセンス一覧](Resources/Licenses/README.md) を参照してください。ビルド時には ReKey のライセンスと第三者ライセンスをアプリの `Contents/Resources/Licenses/` に収録します。別途インストールする公式ドライバパッケージの通知文も確認してください。

この記載は独自コード全体の類似性調査や、すべての依存物のライセンス監査が完了したことを示すものではありません。依存物の追加・更新時と公開前には、出典、適用ライセンス、必要な著作権表示・通知文を確認してください。

ソース公開とアプリ配布の担当者は [公開・配布前の権利確認](docs/publication-rights-ja.md) を参照してください。リポジトリ内の未使用ソース・公式ドライバ pkg・公開する履歴も確認対象です。製品名やロゴの調査、権利者の確認、独自 DriverKit 拡張の配布条件など、未確認事項も同文書に記載しています。外部からの変更提供については [貢献ガイド](CONTRIBUTING.md) を参照してください。

macOS 27 常駐型キーリマップツール アプリ仕様書
Oct 21, 2026 · @yamap

> 注記: これは初期仕様の原本です。その後 rekey-vhid（仮想 HID デーモン）は rekey-core に統合され、共有メモリのリングバッファや Unix ドメインソケットは使っていません。現行の構成は [実装・検証記録](consolidated-service-validation-ja.md) を参照してください。

1. 概要・目的
本製品（仮称: ReKey）は、macOS 27 Golden Gate 上でメニューバーに常駐し、キーボード入力をシステムレベルで書き換えるキーリマップツールである。Karabiner-Elements と同じ「ハードウェアを占有 → 書き換え → 仮想 HID デバイスから再送出」の方式を採りつつ、入力遅延の小ささと、内蔵・外付けを問わずキーボードごとに独立したリマップを設計の最優先とする。
項目
内容
製品名（仮）
ReKey
位置づけ
Karabiner-Elements 互換の思想をもつ常駐型リマッパー。設定ファイルの一部互換（simple_modifications / complex_modifications のインポート）を提供
想定ユーザー
外付けキーボードを使う開発者・ライター、US/JIS 配列を切り替える利用者、Caps Lock / 修飾キーの入れ替えを行いたい一般ユーザー
提供価値
GUI だけで完結する設定、アプリ別・デバイス別のプロファイル自動切替、再起動後も途切れない常駐
非対象
マウスジェスチャー、テキスト展開（スニペット）、ウィンドウ管理
Karabiner-Elements との差分として本製品が独自に持つのは、(1) 現行の Karabiner-Elements より小さい入力遅延（8 章に数値目標と計測方法）、(2) キーボードごとのリマップ（内蔵・外付けの各デバイスに別々のキーマップを持たせる）、(3) ルールの GUI 編集と即時反映、(4) レイヤー機能の 4 点とする。
2. 対象環境・前提条件
macOS 27 Golden Gate（2026年9月14日公開）は Apple シリコン搭載 Mac 専用で、Intel Mac では動作しない。本製品は macOS 27.0 以降のみをサポートし、Intel 向けビルドは提供しない（MacRumors）。
項目
要件
OS
macOS 27.0 以降（27.x マイナーアップデートに追従。27.2 以降で追加されるタッチジェスチャーとの競合は 10 章の未決事項）
CPU
Apple シリコン（M1 以降、MacBook Neo を含む）。Rosetta 2 は使用しない（Universal バイナリ不要、arm64 のみ）
開発言語
Swift 6 / SwiftUI（設定 UI・メニューバー）、C++23（イベント処理コア）、DriverKit（仮想 HID）
必要権限
入力監視、アクセシビリティ、システム機能拡張（DriverKit）の承認、特権デーモン（SMAppService.daemon）の登録
署名
Developer ID Application / Developer ID Installer、DriverKit 用 entitlement（com.apple.developer.driverkit.family.hid.device 等）、Apple 公証
配布形態
署名済み .pkg（DriverKit 拡張を含むため App Store 外配布）。Homebrew Cask も併用
前提
SIP 有効のまま動作すること。SIP 無効化や kext は前提にしない
DriverKit の HID 系 entitlement は Apple への申請制で、取得まで数週間かかる。開発着手と同時に申請する。
3. 機能要件
必須（MUST）は v1.0 の出荷条件、推奨（SHOULD）は v1.x、任意（MAY）は v2 以降の候補とする。
ID
機能
内容
優先度
F-01
単純リマップ
1 キー → 1 キーの置換（例: Caps Lock → Control、英数 ↔ かな）。修飾キー・ファンクションキー・メディアキーを含む
MUST
F-02
複合リマップ
from（キー＋修飾キーの組）→ to（キー列）の置換。to_if_alone（単押し時）、to_if_held_down（長押し時）、to_after_key_up を持つ
MUST
F-03
同時押し
2〜4 キーの同時押し（閾値 50 ms 既定、設定可）を 1 つの from として扱う
MUST
F-04
レイヤー
キーを押している間だけ別のキーマップに切り替える（例: Space 長押しで HJKL を矢印に）。トグル型レイヤーも持つ
MUST
F-05
条件
最前面アプリ（bundle ID）、接続デバイス（vendor/product ID）、入力ソース、キーボード種別（ANSI/ISO/JIS）、変数値で有効・無効を切り替える
MUST
F-06
デバイス別設定
内蔵・外付け（USB / Bluetooth）の各キーボードを vendor ID・product ID（同一製品が複数ある場合はシリアル）で識別し、デバイスごとに独立したキーマップ（単純リマップ・複合ルール・レイヤー）を持つ。接続のたびに自動で対応するキーマップを適用する。あわせて「変更対象にする／しない」「内蔵キーボードを外付け接続時に無効化」を設定する
MUST
F-07
プロファイル
複数プロファイルを保持し、メニューバー・ホットキー・条件で切り替える
MUST
F-08
ファンクションキー
F1〜F12 を標準機能キー（輝度・音量など）と素の F キーのどちらで扱うかをデバイス別に設定する
MUST
F-09
マウスボタン・スクロール
マウスボタンのリマップ、ホイール方向の反転をデバイス別に行う
SHOULD
F-10
アクション
シェルコマンド実行、アプリ起動、入力ソース切替、通知表示、スリープ
SHOULD
F-11
Sticky 修飾キー
修飾キーを 1 回押すと次のキー 1 回だけ有効になる
SHOULD
F-12
Karabiner 設定のインポート
karabiner.json の simple_modifications / complex_modifications を読み込み、対応できないルールを一覧で警告する
SHOULD
F-13
EventViewer
受信した生イベントと変換後イベントをリアルタイムに表示し、キーコード・デバイス情報を確認できる
MUST
F-14
ルールの共有
ルールセットを URL スキーム（rekey://import?...）または JSON ファイルで配布・取り込みする
MAY
F-15
マクロ録画
キー操作を記録して to に展開する
MAY
ルール評価の規則
1. ルールはプロファイル内の並び順で上から評価し、最初に from が一致したルールだけを適用する（先勝ち）。
2. 単純リマップは複合リマップより先に適用し、複合リマップの from は単純リマップ適用後のキーで照合する。
3. 条件が 1 つでも不成立のルールは照合対象から外す。
4. 変換後のイベントは再び照合しない（無限ループ防止）。
動作の既定値
• 単押し判定の閾値: 200 ms（to_if_alone）
• 長押し判定の閾値: 500 ms（to_if_held_down）
• 同時押し判定の閾値: 50 ms
• キーリピートは OS 設定に従い、変換後のキーでリピートする
4. アーキテクチャ
入力イベントに触れるのは root 権限のデーモン 2 つだけに限定し、UI・エージェントはユーザー権限で動かす。この分離は Karabiner-Elements の設計（Security）を踏襲したもので、ユーザー権限のプロセスから仮想デバイスへ任意のイベントを流し込めない構造にする。
上段が root / DriverKit 権限の入力経路、下段がユーザー権限のプロセス。キーボードから OS へ戻る経路に、ユーザー権限のプロセスは一切介在しない。
プロセス
権限
役割
起動方法
ReKey.app（メニューバーアプリ）
ログインユーザー
常駐 UI、設定の編集・保存、デーモンへの設定配布、プロファイル切替、更新確認
ログイン項目（SMAppService.mainApp）
ReKey Agent
ログインユーザー
入力監視・アクセシビリティ権限の要求、最前面アプリと入力ソースの監視、シェルコマンド等のユーザーアクション実行
SMAppService.agent
rekey-core（Core デーモン）
root
IOHIDManager でキーボードを占有し、ルールを評価して変換、仮想 HID デーモンへ送出
SMAppService.daemon
rekey-vhid（仮想 HID デーモン）
root
DriverKit 拡張への唯一の接続元。Core からのイベントを仮想デバイスに書き込む
SMAppService.daemon
ReKey VirtualHID（dext）
DriverKit
仮想キーボード・仮想ポインティングデバイスを OS に提供する
OSSystemExtensionRequest
プロセス間通信は、UI ↔ Core が XPC（Mach サービス、コード署名要件で接続元を制限）、Core ↔ 仮想 HID デーモンが root 専用の Unix ドメインソケット、仮想 HID デーモン ↔ dext が IOUserClient とする。設定ファイルは UI が書き、Core はファイル変更通知（DispatchSource）で再読込する。
5. ユーザーインターフェース
UI は「メニューバーメニュー」「設定ウィンドウ」「EventViewer」の 3 つで構成し、Dock アイコンは表示しない（LSUIElement = YES）。SwiftUI で実装し、macOS 27 の Liquid Glass 標準コントロールをそのまま使う。
5.1 メニューバーメニュー
項目
動作
状態アイコン
有効（通常）／一時停止（半透明）／権限不足またはデーモン停止（警告バッジ）の 3 状態
プロファイル一覧
ラジオ形式でアクティブなプロファイルを切り替える
一時停止
すべてのリマップを止める。再開するまでアイコンを半透明にする。ホットキー既定: ⌃⌥⌘P
設定を開く…
設定ウィンドウを前面に出す
EventViewer を開く…
別ウィンドウで EventViewer を開く
設定を再読込
設定ファイルを再読込してデーモンに配布
アップデートを確認…
9 章の更新機構を呼ぶ
ReKey を終了
UI のみ終了。デーモンは「終了時にリマップを無効化する」設定（既定 ON）に従う
5.2 設定ウィンドウ
サイドバー付きの 1 ウィンドウとし、次のタブを持つ。
タブ
内容
単純リマップ
from / to の 2 列表。from 列はキー押下で入力できる「キーキャプチャ」フィールド。デバイス別フィルタをもつ
複合ルール
ルールの一覧（並べ替え可）。各ルールはシート形式のエディタで編集。from・条件・to（alone / held / after_key_up）をフォームで指定し、JSON の直接編集タブも持つ
レイヤー
レイヤー名・起動キー・モード（hold / toggle）と、レイヤー内のキーマップ表
デバイス
接続中デバイス一覧。チェックで「変更対象」「内蔵キーボード無効化」「F キーを標準機能キーに」を切り替える
プロファイル
作成・複製・名前変更・削除。自動切替条件（アプリ・デバイス）
権限
入力監視・アクセシビリティ・システム機能拡張・デーモン登録の 4 項目の状態を表示し、不足項目はシステム設定の該当画面を直接開くボタンをもつ
その他
ログイン時起動、終了時の挙動、判定閾値（単押し／長押し／同時押し）、ログレベル、自動更新
ルールの変更は保存操作なしで即時反映する（デバウンス 300 ms）。変更が無効な JSON になる場合はエディタ内にエラーを表示し、デーモンには配布しない。
5.3 EventViewer
受信した生イベントと変換後イベントを 2 列で時系列表示する。各行に時刻、デバイス名、usage page / usage、キー名、修飾キー状態、適用ルール名を出す。macOS の入力監視権限が無いと表示できないため、権限不足時は権限タブへの導線を出す。
5.4 初回起動フロー
1. ようこそ画面で必要な 4 つの権限を説明する
2. システム機能拡張の承認（システム設定 → 一般 → ログイン項目と機能拡張）
3. 特権デーモンの登録承認
4. 入力監視・アクセシビリティの付与
5. 既存の karabiner.json を検出した場合、インポートを提案する
6. 完了。メニューバーに常駐してリマップを開始する
各ステップは状態を監視し、権限が付与され次第自動で次へ進む。
6. 設定ファイル仕様
設定は 1 つの JSON ファイル ~/Library/Application Support/ReKey/rekey.json に保存する。所有者はログインユーザー、パーミッションは 0600 とし、Core デーモンは所有者がコンソールユーザーと一致する場合のみ読み込む。
項目
仕様
文字コード
UTF-8、改行 LF、インデント 2 スペース（UI が書き出す形式）
スキーマ版
ルートの schema_version（整数）。読み込み時に古い版は自動マイグレーションし、新しい版は拒否してエラー表示
バックアップ
書き込み前に rekey.json.bak.<ISO日時> を Backups/ に残す。直近 20 世代を保持
インポート
Karabiner-Elements の karabiner.json を読み、simple_modifications / complex_modifications / devices を変換。非対応項目は結果画面で一覧表示
エクスポート
プロファイル単位または全体を JSON で書き出す。ルールセットのみの共有用 .rekeyrules も同形式
同期
ファイルを iCloud Drive 配下に置いた場合も動作するよう、シンボリックリンク先を解決して監視する（専用同期機構は持たない）
6.1 ルート構造
{
  "schema_version": 1,
  "global": {
    "check_for_updates": true,
    "show_in_menu_bar": true,
    "disable_on_quit": true,
    "thresholds_ms": { "alone": 200, "held_down": 500, "simultaneous": 50 }
  },
  "profiles": [
    {
      "id": "8f3c…",
      "name": "Default",
      "selected": true,
      "auto_select": { "frontmost_app": [], "device": [] },
      "simple": [ { "from": { "key": "caps_lock" }, "to": [ { "key": "left_control" } ] } ],
      "layers": [ { "name": "nav", "trigger": { "key": "spacebar" }, "mode": "hold", "map": { "h": "left_arrow" } } ],
      "rules": [ { "name": "…", "manipulators": [ /* 6.2 参照 */ ] } ],
      "devices": [ { "id": { "vendor_id": 1452, "product_id": 641 }, "ignore": false, "disable_builtin_when_connected": false, "fn_keys_as_media": true } ]
    }
  ]
}
6.2 manipulator（複合ルールの単位）
フィールド
型
説明
type
string
basic 固定（将来 mouse_motion_to_scroll 等を追加）
from
object
key、modifiers.mandatory[]、modifiers.optional[]、simultaneous[]、any のいずれか
to
array
押下時に送るイベント列。各要素は key / modifiers[] / shell_command / open_app / select_input_source / set_variable / notify / sticky_modifier / layer
to_if_alone
array
単押し時
to_if_held_down
array
長押し時
to_after_key_up
array
キーを離した後
conditions
array
frontmost_app_if/unless、device_if/unless、input_source_if/unless、keyboard_type_if/unless、variable_if/unless、layer_if/unless
parameters
object
このルール限定の閾値上書き
キー名は Karabiner-Elements と同じ識別子（caps_lock、left_command、japanese_eisuu など）を採用し、インポート時の変換表を不要にする。
7. 権限・セキュリティ
本製品はキーボード入力の全量に触れるため、「入力イベントを扱うプロセスを root の 2 プロセスに限定する」「設定もログも平文のキー入力を残さない」の 2 点を設計原則とする。
7.1 必要な権限
権限
要求するプロセス
用途
付与方法
システム機能拡張の承認
ReKey.app → dext
仮想 HID デバイスの提供
システム設定 → 一般 → ログイン項目と機能拡張
特権デーモンの登録
ReKey.app（SMAppService.daemon）
rekey-core / rekey-vhid を root で常駐
同上（バックグラウンド項目）
入力監視
rekey-core
IOHIDDeviceOpen でのイベント受信
システム設定 → プライバシーとセキュリティ → 入力監視
アクセシビリティ
ReKey Agent
セキュアなフォーカス要素の確認（最前面アプリの取得は権限不要）
同上 → アクセシビリティ
入力監視が無ければ Core は物理キーボードを占有せず、リマップは停止する。Agent のアクセシビリティが無ければ入力欄の安全確認ができないため EventViewer の入力表示を抑止するが、リマップと最前面アプリ条件は動作する。UI は両権限を要求せず、Agent も入力監視を要求しない。権限状態は Core の入力監視状態と、Agent が送るアクセシビリティ状態から表示する。Agent の報告が 500 ms 以上途絶えた場合は未許可扱いとし、表示も抑止する。通知権限は notify アクション実行時のみ要求する。
7.2 セキュリティ要件
• XPC 接続は NSXPCConnection の setCodeSigningRequirement で、同一 Team ID かつ同一バンドル ID 接頭辞の署名済みバイナリからのみ受け付ける
• rekey-vhid の Unix ドメインソケットは root:wheel 0600 とし、接続元の UID を getpeereid で検証する
• dext は rekey-vhid 以外の IOUserClient 接続を拒否する（entitlement と Team ID を照合）
• ログにキーコードを出力するのはデバッグレベルのみで、既定は OFF。ON にした場合もパスワード入力フィールド（kAXSecureTextField）にフォーカスがある間は出力を抑止する
• 設定ファイルは所有者チェック（6 章）を通らない場合は読み込まない
• シェルコマンド実行はユーザー権限（Agent）で行い、root 側では決して実行しない
• 自動更新のパッケージは Developer ID 署名と公証チケットを検証してから実行する
• 外部ネットワーク通信は更新確認のみ。テレメトリは収集しない
7.3 macOS 27 固有の確認事項
macOS 27 では AI エージェント対応のためにフルディスクアクセスの扱いが変更された（MacRumors、2026年10月2日）。本製品はフルディスクアクセスを要求しないが、27.2 以降で入力監視・アクセシビリティの付与フローに変更が入っていないかを、各マイナーリリースのベータ段階で確認する。
8. 非機能要件
分類
要件
測定方法
遅延
物理キー押下から仮想デバイス出力まで p99 で 1 ms 以内（単純リマップ）、3 ms 以内（複合ルール 200 件）。同一 Mac・同一ルールで計測した Karabiner-Elements の遅延を常に下回ること
EventViewer のタイムスタンプ差分を 10,000 打鍵で計測
CPU
アイドル時 0.1% 未満、毎秒 20 打鍵の連続入力中に 2% 未満（M1 基準）
Activity Monitor と powermetrics
メモリ
常駐 3 プロセス合計 60 MB 以内
24 時間連続稼働後の RSS
起動
ログイン後 2 秒以内にリマップ有効化。ログイン画面（FileVault 解除後の認証画面）でも動作
ログイン直後の EventViewer 記録
信頼性
デーモンがクラッシュした場合 launchd により 1 秒以内に再起動し、占有していたデバイスを自動で再取得する。クラッシュ中は物理キーボードがそのまま使える状態に戻る
強制 kill の試験
フェイルセーフ
修飾キーがすべて押されたまま（スタック）になった場合、デーモン再起動時に全キー解放イベントを送る。設定が壊れて全キーが反応しなくなる事態を避けるため、起動後 10 秒間に 1 件も変換後イベントが出ず入力があれば一時停止して通知する
障害注入試験
スリープ復帰
スリープ・ディスプレイ復帰・Bluetooth 再接続時に 1 秒以内に再占有
50 回の復帰試験
ログ
統合ログ（os_log、サブシステム jp.example.rekey）に出力。ファイルログは ~/Library/Logs/ReKey/ に 10 MB × 5 世代
—
アクセシビリティ
設定ウィンドウは VoiceOver 対応、キーキャプチャフィールドには代替のポップアップ選択を用意
VoiceOver 手動試験
言語
日本語・英語
—
8.1 低遅延のための設計
遅延は製品の最優先項目とし、イベント経路から「待ち」と「割り当て」を取り除く。
• イベント経路は rekey-core 内の単一スレッドで処理し、スレッドはリアルタイム優先度（THREAD_TIME_CONSTRAINT_POLICY）で動かす
• 1 イベントの処理中にヒープ割り当て・ロック取得・ログ書き込みを行わない。ルールはプロファイル読込時にデバイス別・キー別のテーブルに事前コンパイルし、照合は配列参照だけで済ませる
• 変換後イベントは rekey-vhid へ共有メモリのリングバッファで渡し、ソケットは起動通知にだけ使う。dext への書き込みは 1 イベント 1 回の IOUserClient 呼び出しにまとめる
• to_if_alone / to_if_held_down を使わないルールでは、キー押下を保留せず即時に送出する（保留が必要なのは判定待ちのキーのみ）
• 最前面アプリ・入力ソースの条件評価は、Agent からの通知時に rekey-core 側でフラグを更新しておき、イベント処理時は参照のみとする
• 計測用に rekey-bench コマンドを同梱し、物理キー押下（IOHID 受信時刻）から仮想デバイス出力までの差分を p50 / p99 で出す。CI で Karabiner-Elements 最新版との比較結果を毎リリース記録する
9. 配布・更新・ライフサイクル
項目
仕様
インストーラ
Developer ID で署名・公証した .pkg。/Applications/ReKey.app と /Library/Application Support/ReKey/ にデーモン実行ファイルを配置し、postinstall で既存の旧版デーモンを停止する
Homebrew
brew install --cask rekey を併せて提供（Cask は同じ .pkg を使う）
ログイン時起動
既定 ON。ReKey.app は SMAppService.mainApp、デーモンは SMAppService.daemon で登録し、ユーザーがシステム設定から個別に無効化できる
自動更新
Sparkle 2 系（EdDSA 署名付き appcast）で確認。既定は「確認して通知」、自動インストールはオプトイン。dext の更新は再承認が必要なため、更新後に権限タブへ誘導する
バージョニング
セマンティックバージョン。dext のバージョンはアプリと同じ番号を使い、不一致なら UI が警告する
アンインストール
メニュー「ReKey をアンインストール…」から、デーモン解除 → dext の OSSystemExtensionRequest.deactivationRequest → ファイル削除の順に実行。設定ファイルは残すか削除するかを選べる
macOS アップデート追従
新しい macOS マイナーリリースのベータ公開から 2 週間以内に動作確認し、必要なら対応版を出す
サポート期間
現行メジャー macOS と 1 つ前（27 と 26）。ただし 26 向けは別ブランチとし、本仕様の対象外
10. 制約・リスク・未決事項
10.1 制約
• App Store では配布できない（DriverKit の HID 仮想デバイスと特権デーモンが App Store のサンドボックス要件と両立しない）
• 仮想デバイス経由で再送出するため、一部のアプリやゲームは「ReKey 仮想キーボード」を別デバイスとして認識する。デバイス固有機能（Logi Options+ の Fn 設定など）とは競合しうる
• Touch ID / セキュアキーボード入力モードの間は OS 側の制約でイベントを取得できない
• 占有方式のため、本製品の停止中はリマップが一切効かない（OS 標準の修飾キー設定は併用可）
10.2 リスク
リスク
影響
対策
DriverKit HID entitlement が取得できない、または取得が遅れる
出荷不能
着手時に申請。取得まで Karabiner-DriverKit-VirtualHIDDevice（公開 OSS）を評価用に流用して開発を進める
macOS 27.x マイナーアップデートで権限フローや DriverKit の挙動が変わる
常駐停止
ベータ追従（9 章）。起動時に OS バージョンを確認し、未検証版では警告を出す
全キー無反応の設定ミス
ユーザーが操作不能
8 章のフェイルセーフ。緊急停止ホットキー（⌃⌥⌘⎋ 長押し）はルールより先に評価する
Karabiner-Elements と同時起動
二重占有で入力が消える
起動時に Karabiner のデーモンを検出し、どちらを使うか確認する
10.3 未決事項
[ ] 製品名（ReKey は仮称）と Team ID、バンドル ID 接頭辞
[ ] macOS 27.2 で追加されたタッチジェスチャー（MacRumors、2026年10月5日報道）がポインティング系リマップと競合するかの検証
[ ] レイヤー機能を Karabiner 互換の variable_if へ変換してエクスポートするか、独自形式のままにするか
[ ] 有償・無償の区分と、有償にする場合の課金方式
[ ] 日本語入力ソース（ことえり／ATOK）切替アクションの対応範囲
11. 用語集
用語
意味
HID
Human Interface Device。キーボード・マウスなど入力機器の USB / Bluetooth 規格
DriverKit / dext
ユーザー空間で動くドライバ拡張の仕組みとその実行体。kext（カーネル拡張）の後継
仮想 HID デバイス
dext が OS に提供する「存在しないキーボード」。変換後イベントはここから OS に入る
占有（seize）
kIOHIDOptionsTypeSeizeDevice で物理デバイスを排他的に開き、OS 側に生イベントが届かないようにすること
XPC
macOS のプロセス間通信機構。UI とデーモンの橋渡しに使う
SMAppService
ログイン項目・エージェント・デーモンをアプリから登録する macOS 13 以降の API
manipulator
複合ルールの最小単位（from・条件・to の組）
レイヤー
特定キーを押している間、または切り替えている間だけ有効になる別のキーマップ
プロファイル
リマップ設定の一式。複数持ち、切り替えて使う
EventViewer
生イベントと変換後イベントを表示する診断画面
参考資料
• Karabiner-Elements: Security（プロセス構成と権限）
• MacRumors: macOS Golden Gate roundup（対応機種・リリース日・27.x の変更点）
# Sparkle 配布の準備と出荷ゲート（2026-11-07）

**一般公開不可。** Sparkle の組込みは開発段階であり、製品 ID、実証明書、公証、更新の実機安全性、ドライバの出荷要件は未完了。この文書は未確認のコマンドを完成済みのリリース手順として扱わない。

この出荷ゲートは実行可能な製品の配布を対象とする。ソースリポジトリの公開は別途
[公開・配布前の権利確認](publication-rights-ja.md) に従って判断する。製品配布時には
同文書の成果物・名称・素材・ドライバの確認も行う。ライセンス文の追記だけでは
公式 pkg 内部の監査や商標調査、Apple の配布資格の確認は完了しない。

2026-11-07 時点で、既存の GitHub リポジトリ `yamap02/key-remap` は private。この Mac の有効なコード署名 identity は 0 件。公開先、Apple Developer Team ID、製品 bundle ID は未決定であり、仮の値を配布設定としない。

## 更新方式の判断

通常の app 更新を優先して検証する。現在の pkg は `/Applications/ReKey.app` を root:wheel、他ユーザーから書き込み不可にし、Core はその app と Agent の指定要件を XPC に適用する。2026-11-07、権限を変更せず Sparkle 2.9.6 の権限判定を呼び、現在の root 所有 `/Applications/ReKey.app` は管理者認証が必要、ユーザー所有の一時 app は不要と判定された（`python3 Tests/Distribution/test-sparkle-authorization.py --root-bundle /Applications/ReKey.app`）。この試験は固定版の非公開 API を診断にだけ使用し、更新の実行やアプリの変更はしない。ソース上も認証が必要なら system domain を使う。Sparkle 2.9.6 の通常インストーラは旧 app の所有者・グループを新 app に合わせようとするが、失敗を致命的エラーにしない。したがってコードの存在だけでは root 所有が維持される保証にならない。認証が必要との判定は、認証成功後に所有権が正しく維持される証明にはならない。更新後に全階層の所有権とモード、Core の新しい署名要件および接続、Agent・Core の旧プロセス停止を確認する必要がある。この環境ではパスワードなしの管理者操作は利用できず、署名済み製品版の置換試験は未実施。

成立しない場合のみ flat pkg を検討する。pkg 更新には管理者認証が毎回必要で、サイレントインストール、差分更新、通常の `generate_appcast` の利用に制限がある。初回導入 pkg で既存版を置き換える場合も、先に ReKey のサービスを停止し、アプリを終了する。preinstall は旧 UI または Agent が残っていれば停止前に中止し、launchd の停止失敗、プロセスの残存や検査失敗を検出した場合も中止する。プロセス名の確認は同名の別アプリにも反応する。確認後に別プロセスが起動する競合、旧 Agent の launchd 登録の移行、停止後にインストールが中断した場合の自動再登録は未解決で、postinstall は権限を設定するだけ。実機の停止・失敗時の復旧や Agent の再登録は未検証。現状の pkg を Sparkle 更新として配布しない。[Sparkle package updates](https://sparkle-project.org/documentation/package-updates/) / [publishing](https://sparkle-project.org/documentation/publishing/)

## 現在の実装と検証

- `check_for_updates` は設定 JSON の自動確認設定として使う。設定画面から手動確認できる。自動ダウンロード・自動インストールは無効。feed URL または EdDSA 公開鍵のない開発ビルドでは更新を開始しない。更新前の設定保存が失敗した場合は、未保存の編集がない場合も更新準備を中止する。テストでは設定の保存と I/O エラー時の中止を確認した。
- Sparkle 2.9.6 を固定。`REKEY_FEED_URL` と `REKEY_ED_PUBLIC_KEY` を両方指定して HTTPS feed と公開鍵を埋め込む。feed 署名と更新の展開前検証を必須とする。公開鍵は秘密鍵ではない。
- `REKEY_VERSION` は app と Agent の表示版、`REKEY_BUILD_NUMBER` は app と Agent の build 番号および pkg receipt の版。明示しない開発ビルドではそれぞれ `0.1.0` と Git コミット数を使用。公開時には両方を明示し、build 番号はリリースごとに単調増加させる。`scripts/check-appcast-version.py` は署名検証済み feed の全履歴より新しい整数 build を要求する。試験 pkg の展開結果では ID と build 2001 が app と一致した。
- `swift test`、`scripts/test-core.sh`、開発用 app のビルドと `codesign --verify --deep --strict` が通過。使い捨ての試験鍵で通常 app の zip と署名済み appcast を生成し、署名検証と feed・zip 改ざんの拒否を確認した。試験鍵は一時ディレクトリに作り実行後に削除した。旧 feed だけを次の作業ディレクトリへ引き継ぐ連続2リリースの試験で、両アーカイブの署名、旧 URL と署名の保持、build の新旧順、重複 build の拒否も確認した。実際の配布鍵による検証ではない。
- 2026-11-07 にソース `b523da7` を含む開発版で `Tests/Distribution/test-appcast.sh` を再実行し、2 回の app ビルド、連続 feed と archive の署名検査、改ざん拒否が通過した。生成された app の `codesign --verify --deep --strict` も通過。ad-hoc 署名と試験鍵による結果であり、Developer ID、公証、GitHub 配信を検証したものではない。
- Core は起動時の app・Agent・Core 実行ファイルの実体・属性と親ディレクトリの所有権・書込み権限を100ms間隔で照合し、置換・削除・変更を検知すると入力を解放してプロセスを再起動するまで再取得しない。Core 起動時に app と Agent の両方の署名・所有権が検証できなければ起動を拒否する。オフラインテストで置換・削除・変更・書込み権限と復帰抑止を検証した。Sparkle の更新発見画面で利用者がインストールを選んだ時点で、UI は設定を保存し、有効な Core と Agent の停止完了まで Sparkle に選択を返さない。これにより通常経路では、終了時に自動適用されうる更新の準備より前に停止する。再起動延期コールバックでも停止状態を再検査する。停止前の復旧記録、停止失敗時の更新キャンセル、準備中の更新中断、古い build の保留状態と停止再検査を模擬テストした。同じ旧 build で再起動した保留更新はサービスを停止したままにし、メニューの「更新を確認」から再開またはキャンセルできる。途中終了後は停止状態を再検査する。Sparkle の既存保留更新からの移行、コールバックを経由しない終了経路と macOS の実動作は未検証。UI は記録済みの build 番号が変わった時に、有効だった Core と Agent の再登録を試みる。途中失敗時の次回起動での再試行、無効・承認待ちサービスを有効化しないこと、設定ファイル保持をモックと一時設定ファイルで検証した。旧版で build 番号を記録していない初回移行や、pkg で停止済みと判定されるサービス、bundle ID 変更は対象外であり、実機検証が必要。
- 署名 identity がない開発版は ad-hoc 署名かつ Hardened Runtime を無効にする。Team ID のない ad-hoc app で Hardened Runtime を有効にすると Sparkle framework の読み込みが拒否されたため。公開用 Developer ID 署名では Hardened Runtime とタイムスタンプを必須とする。
- Sparkle を使う一時的なユーザー所有 app で、署名済みローカル feed から build 100 → 101 のアプリ置換と再起動、app 外の設定ファイル保持、置換後の ad-hoc 署名整合性を確認した（`Tests/Distribution/test-sparkle-install.py`）。実際の `UpdateServiceRecovery` を使い、旧 app が模擬 Core を停止、新 app が記録を読み直して以前有効だった模擬 Core のみ再登録することも確認した。サービス状態は一時ファイルで代用しており、通常更新の一部の確認に限る。root 所有、実際の launchd・ReKey のサービスと XPC、Developer ID、公証、HTTPS は対象外。
- 実際の Sparkle 2.9.6 を一時的な試験 app に組み込み、署名済みローカル feed について更新あり・なし、feed 改ざん拒否、通信失敗、同じ長さの改ざん済み更新ファイルの取得後・展開前の EdDSA 署名拒否を確認した（`Tests/Distribution/test-sparkle-probe.py`）。試験は loopback HTTP と使い捨て鍵で、取得する試験ファイルはインストールできないデータに限定し、実行やインストールはしない。本番 HTTPS・配布鍵・ReKey の更新 UI は未検証。通常 app の root 所有維持、更新中断と物理キー解放、実機での設定保持とサービス再接続も未検証。署名済み製品版・公証・GitHub への公開も未実施。
- ダウンロードの取消しは Sparkle がエラーなしでサイクルを終了するため、専用コールバックを受けて終了後にサービス復旧を開始する。使い捨て app・鍵・ローカル feed を用いた Sparkle 2.9.6 の試験でも、取消し通知の後にエラーなしの終了通知が来ることを確認した。別の隔離試験では、実際の Sparkle のダウンロードを取消し、終了通知後に `UpdateServiceRecovery` が以前有効だった模擬 Core を復旧し、旧 app が置換されないことを確認した。試験用の独自 driver と delegate、ファイルで模擬したサービスを使用しており、実際の ReKey UI と launchd サービスでの取消しは未検証。
- 更新前の停止と更新後の復旧を実行中は、終了メニューを無効にし、通常のアプリ終了要求を拒否する。旧 build で保留記録を見つけた場合は、記録直後の異常終了でサービスが残っていても停止を再確認してから保留状態へ入る。停止を確認できない保留状態では、終了時の自動インストールを避けるため通常終了を拒否する。停止途中の異常終了からの再確認、終了判定、隔離 AppKit・SwiftUI プロセスでの終了拒否と処理後の終了はテスト済み（`Tests/Distribution/test-termination-gate.py`）。実際の ReKey UI、ログアウト・システム終了と強制終了の挙動は未検証。強制終了やプロセス異常を防ぐものではなく、処理が完了しない場合の復旧も実機で確認する必要がある。
- `AppState` と復旧ロジックを組み合わせたテストでは、模擬サービスの停止失敗後に通常終了を拒否し、停止が確認できた保留状態では終了を許可し、明示的な取消しで元のサービスを復旧することを確認した。SMAppService と実際の UI は使っていない。
- 保留更新があるときは通常終了の直前にもサービス状態を同期的に再確認し、記録外のサービスが途中で有効になった場合などは終了を拒否する。問題を解消した後、メニューの「入力サービスの停止を再確認」で再試行できる。[Apple の説明](https://developer.apple.com/jp/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval)では、承認待ちサービスは登録済みで、後から利用者が実行を許可できる。模擬サービスの承認状態変更と、隔離 AppKit プロセスの終了拒否・許可をテストした。確認と実際の終了の間にシステム設定が変わる競合、強制終了および実際の SMAppService は未検証。
- 同じ隔離試験で、署名済み feed の更新 zip の内容を同じ長さで改ざんし、Sparkle による EdDSA 署名拒否後に `UpdateServiceRecovery` が模擬 Core を復旧し、旧 app と設定を保持することを確認した。試験用 delegate と模擬サービスによる結果であり、実機の入力解放や XPC 再接続の証明ではない。
- 更新ファイルの HTTP 取得が 404 で失敗する場合と、試験サーバーが 16 KiB を送信した後に接続を切る場合も、実際の Sparkle がダウンロードエラーを通知し、同じ模擬 Core の復旧と旧 app・設定の保持を確認した。いずれも loopback HTTP、試験用 delegate と模擬サービスによる結果であり、実際の HTTPS・ReKey UI・launchd における復旧は未検証。
- 隔離試験で更新準備による模擬 Core の停止後、ダウンロード開始時に試験 app を強制終了した。別プロセスから同じ旧 build と復旧記録を読み直すと停止状態が維持され、明示的な取消し相当の復旧処理を呼んだ後にのみ模擬 Core が再開した。旧 app と設定も保持された。これは実際の Sparkle の開始と復旧ロジックを組み合わせた試験だが、取消し UI、実 launchd、物理キーボードの占有解除は確認していない。

## 出荷前に必要なもの

1. 配布者の Apple Developer Program、実際の Team ID と一意な製品 bundle ID、Developer ID Application 証明書、pkg が必要なら Developer ID Installer 証明書を用意する。`REKEY_PRODUCT_ID` は app、Agent、Core の XPC 判定、pkg ID に反映される。`REKEY_TEAM_ID` を指定すると ad-hoc 署名を拒否し、App・Agent・Core の署名 Team ID を照合する。未指定時は開発用 `jp.example.rekey` と ad-hoc 署名を使う。launchd / Mach service 名と Agent の通知名も製品 ID から生成する。旧 VHID の解除用 plist と初回 pkg 移行時の旧 Core 停止には開発用名を残す。製品 ID 変更時の既存バックグラウンド登録・TCC 承認の移行と同時インストールは未検証。実在の証明書を使った照合も未検証。
2. `xcrun notarytool store-credentials` 等で公証資格情報をキーチェーンに保管し、パスワード、API 秘密鍵、署名鍵をリポジトリ、コマンド履歴、CI ログへ書かない。専用の Sparkle EdDSA 鍵を `generate_keys --account <組織専用名>` でキーチェーンに生成し、公開鍵のみビルド設定に渡す。秘密鍵は管理された安全な場所にバックアップし、紛失・ローテーション方針を決める。
3. GitHub の公開リポジトリと Releases を決め、HTTPS の安定した feed URL と、各バージョンに固定された HTTPS 更新ファイル URL を設計する。`latest/download` を feed に使う場合は Release 公開時の切替・キャッシュと、過去アイテムが元のバージョンの asset を指すことを検証する。認証が必要な private Release の URL を公開 feed とみなさない。
4. 実際の識別子・署名で App、Agent、Core と Sparkle の各ヘルパーを Developer ID 署名し、Apple に公証・staple する。`codesign`、`spctl`、`stapler` と配布アーカイブ展開後の署名を確認する。公開前の署名・公証自動化と本番向け失敗時停止処理は未実装。
5. クリーンな試験 Mac で旧版→新版を検証し、更新の有無、不正な署名、通信断、署名付き feed の改ざん、管理者認証の拒否、インストール中断、再起動、設定保持、Core/Agent の再接続と物理キーボード解放を確認する。[実機検証手順と記録](sparkle-physical-validation-ja.md) の各ケースは未実施。`disable_on_quit=false` でも実機のすべての更新・終了・中断経路で入力が解放されることを検証する。更新選択を経由せずすでに保留されていた更新や異常終了の経路では通常終了通知は非同期であり、設定により Core は入力を保持しうる。検証前に公開しない。

2026-11-07 の事前確認では、ローカルの全 Git ref から到達できる 1,469 個の blob のうち、2 MB 以下で先頭 8,192 バイトに NUL のない 1,383 個を対象に、秘密鍵 PEM、GitHub の代表的な token、AWS access key の形式を値を出力せず検索し、一致はなかった。NUL を含む 63 個と 2 MB 超の 23 個は対象外で、これら以外の認証情報形式やリポジトリ外のファイルも検査していない。公開可能と判断する根拠としては不十分であり、公開する ref・全履歴・バイナリを対象とした専用の秘密情報スキャンと内容確認を公開直前に実施する。

同日、[Gitleaks 8.30.1](https://github.com/gitleaks/gitleaks/tree/v8.30.1) の標準ルールで `git --log-opts=--all --ignore-gitleaks-allow --redact=100` を実行し、ローカル全 ref の Git 履歴から検出 0 件を確認した。結果は標準出力からメモリ内で件数だけを集計し、検出値をログやリポジトリへ保存していない。Git 差分に現れないバイナリの中身や未知の形式は対象外であり、公開直前の再スキャン、配布物と履歴のバイナリ・内容確認は引き続き必要。

対象外だった到達可能な blob を拡張子とパスで分類した結果、VirtualHID 配下に公式 pkg 71 個、画像・アイコン類、provisioning profile 3 個があり、それ以外に ReKey の PDF・PNG アイコンがあった。VirtualHID 配下の追跡ファイルは後述の固定上流コミットと一致している。3 個の profile を `security cms -D` で復号したところ、各 profile に公開証明書が 1 個あり、デバイス一覧と `PrivateKey` 相当の名前のフィールドはなかった。これはプロフィールの構造確認であり、秘密情報の不存在や再利用権限の証明ではない。これらは第三者の公開 profile で、ReKey の署名に使用しない。独自アイコンを含むバイナリと公開する全 ref の最終内容確認は残る。

## 初回導入とドライバ

現状 ReKey は公式の [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) に依存する。公式配布元から互換性のある署名・公証済み単独ドライバ pkg を入手し、管理者としてインストールする。インストール後、公式 Manager の `activate` を実行してから macOS が求めるシステム機能拡張をシステム設定で許可し、必要なら再起動する。ReKey の権限画面の「入力サービスを登録」で共有 Virtual HID デーモンも登録し、バックグラウンド項目と `rekey-core` の入力監視を許可する。EventViewer を使う場合は Agent のアクセシビリティも必要。公式ドライバの本体は Unlicense。ReKey が組み込む Sparkle のライセンス（同梱コンポーネントの告知を含む）と VirtualHID 本体のライセンスは app の `Contents/Resources/Licenses/` に収録する。Core がコンパイルするヘッダーを依存解析し、Asio・pqrs・Microsoft GSL・nlohmann/json・nod・type_safe のライセンスと著作権表示も同じ場所に収録する。各ヘッダーの正確な取得元リビジョンは vendored tree に揃っていないため、更新時と公開前に依存・通知を再監査する。

2026-11-07 に、ReKey の Git で追跡する `Vendor/VirtualHID` の 1,147 ファイルを、[上流の固定コミット](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/ac836ed8a974cd5182495251855cabdb762f50cb)の再帰ツリーと Git blob ID で照合し、全件一致を確認した。Core が使う `vendor/vendor/include` の 912 ファイルも全て追跡対象だった。このスナップショットの一致は各サードパーティ部品の元リビジョンやライセンス告知の完全性を証明しない。ReKey 側ではこれらは通常の Git ファイルであり、サブモジュール初期化は不要。

公式 Manager はインストールされた公式 pkg のものを利用する：

```sh
/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
```

公式の案内と異なり、ReKey は権限画面から共有デーモンを SMAppService に登録するため、ターミナルで `sudo` 起動したデーモンを常時動かす手順は不要。固定された依存の package 8.6.0、driver 1.8.0、client protocol 7 に互換のある公式ドライバを使い、配布元と署名・公証を確認する。異なる protocol のデーモンとは通信できない。

既存要件は独自 dext / IOUserClient と性能・復帰時間などを出荷ゲートとしている（[requirements.md](requirements.md)）。公式ドライバの利用だけでこのゲートが免除されるとは判断できず、独自ドライバ要否の決定、entitlement、承認、ライセンスの最終確認が未解決。

## 障害時の暫定復旧

安全な別入力手段を確保し、ReKey の設定画面から入力サービスを停止する。アプリが操作できない場合は macOS のバックグラウンド項目で ReKey のサービスを無効化し、必要なら再起動する。設定は `~/Library/Application Support/ReKey/` にあり、削除や上書き前にバックアップする。サービス登録の承認、入力監視、ドライバ拡張を再確認し、署名と公証を確認した既知の旧版から復旧する。更新取消し後の自動復旧処理は実装したが実機未検証。保留状態で同じ版が起動した場合は入力サービスを停止したまま、メニューから「更新を確認」で再開・キャンセルする。

復旧記録の更新元 build が欠落している場合やサービス名が不正・重複している場合、自動更新とサービスの自動再開を拒否して記録を残す。以前の開発版が更新後の復旧途中で終了した場合にも更新元のない記録が残る可能性がある。復旧画面の警告を確認し、別入力手段と設定のバックアップを確保したうえで、サービス登録とインストール済み app の状態を手動確認する。この状態の自動修復や実機での復旧操作は未検証。

## 署名済み通常 app のリリース準備手順（出荷ゲート通過後）

以下は通常 app 更新の検証が完了した後に配布担当者が使う手順。事前に署名鍵と公証資格情報をキーチェーンへ登録し、Sparkle 2.9.6 の公式配布物の `bin` を `SPARKLE_BIN` に指定する。`test "$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)" = "$REKEY_ED_PUBLIC_KEY"` でビルドに埋め込む公開鍵が署名用キーチェーンの鍵と一致することを確認し、失敗したら進めない。実際の値は配布担当者が設定する。`REKEY_PRODUCT_ID` や署名チームの変更は TCC・サービス登録への影響があるため、既存利用者向けには移行を検証する。

1. 前回の appcast を HTTPS で取得し、**変更する前に**同じ配布用鍵で検証する。初回のみ、過去リリースがないことを別途確認して feed 比較を省略する。新しい build は前回値より大きく、表示版やタグも配布履歴と重複しないものにする。

   ```sh
   curl --fail --location "$REKEY_FEED_URL" -o build/previous-appcast.xml
   "$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify build/previous-appcast.xml
   python3 scripts/check-appcast-version.py build/previous-appcast.xml "$REKEY_BUILD_NUMBER"
   ```

2. `REKEY_RELEASE=1` と `REKEY_PRODUCT_ID`、`REKEY_TEAM_ID`、`REKEY_SIGNING_IDENTITY`、`REKEY_VERSION`、`REKEY_BUILD_NUMBER`、`REKEY_FEED_URL`、`REKEY_ED_PUBLIC_KEY` を明示して `scripts/build-app.sh` を実行する。公開用モードは開発用 ID、例示用 feed、未設定値を拒否する。App・Agent・Core と Sparkle ヘルパーの Apple の Developer ID 証明書要件、Team ID、Hardened Runtime、署名時刻と署名整合性を検証し、不一致なら失敗する。`codesign --verify --deep --strict --verbose=2 build/ReKey.app` で署名を確認する。
3. `ditto -c -k --sequesterRsrc --keepParent build/ReKey.app build/notary.zip` を作成し、`xcrun notarytool submit build/notary.zip --keychain-profile "$REKEY_NOTARY_PROFILE" --wait` が Accepted になったことを確認する。`xcrun stapler staple build/ReKey.app`、`xcrun stapler validate build/ReKey.app`、`spctl --assess --type execute --verbose=4 build/ReKey.app` を実行し、staple 後の app から配布 zip を作り直す。拒否された場合は公開せず、notarytool のログを Apple から取得して修正する。
4. 空の作業ディレクトリを用意し、直前に検証した旧 feed を `appcast.xml` としてコピーする。そこへ `ditto -c -k --sequesterRsrc --keepParent build/ReKey.app <作業ディレクトリ>/ReKey-<表示版>.zip` で新しい zip を置く。初回は旧 feed を置かない。`generate_appcast --account "$SPARKLE_ACCOUNT" --maximum-versions 0 --maximum-deltas 0 --download-url-prefix "https://github.com/<owner>/<repo>/releases/download/<tag>/" <作業ディレクトリ>` で作成する。owner・repo・tag は実際の GitHub Releases の値に置き換え、過去 item の URL が各旧 release を指したままか確認する。生成後 `sign_update --account "$SPARKLE_ACCOUNT" --verify <作業ディレクトリ>/appcast.xml` で署名を検証し、新旧各項目の build 番号、HTTPS URL、公開鍵、enclosure 署名を点検する。公開鍵と秘密鍵が対応することも署名検証および旧版による実機更新で確認する。

   検証済みの旧 feed を残したまま、`FEED`、`ARCHIVE`、`ASSET_URL` に生成した feed、zip、タグ固定の完全な GitHub asset URL を設定し、次の検査を行う。初回だけ `--previous build/previous-appcast.xml` を省く。各 feed の署名検証はこのメタデータ検査より先に行う。

   ```sh
   signature=$(python3 scripts/check-appcast-assets.py "$FEED" "$ARCHIVE" "$REKEY_BUILD_NUMBER" "$ASSET_URL" --previous build/previous-appcast.xml)
   "$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$ARCHIVE" "$signature"
   ```

   これにより今回の URL・サイズ、build の重複、旧版の URL・サイズ・署名の消失や変更を拒否する。公開後に取得した feed と zip にも同じ署名・整合検査を行う。メタデータ検査自体は署名を検証しない。次の pkg 作成時には、実際の更新 zip を一時ディレクトリに展開し、app の署名・公証チケット・Gatekeeper 評価も再検査する。実在の Developer ID と公証チケットによる成功経路は未検証。
5. `gh release create <tag> --draft --verify-tag` で下書きを作り、署名・公証済み初回導入 pkg、更新 zip、署名済み appcast をアップロードする。下書きと試験環境で asset、内容と順序を確認してから公開する。安定 feed を GitHub の `releases/latest/download/appcast.xml` に置く場合、各正式 release にその名前の feed を含めて `gh release edit <tag> --draft=false --latest` で切り替える。公開後は feed と新旧 asset を HTTPS で実際に取得し、署名と内容を再検証する。初回導入 pkg は `REKEY_RELEASE=1` に加え `REKEY_INSTALLER_IDENTITY`、`REKEY_NOTARY_PROFILE`、手順 4 の zip を指す `REKEY_UPDATE_ARCHIVE` を設定した `scripts/build-pkg.sh` で生成する。公開用モードは app を再ビルドせず、手順 3〜4 で使った `build/ReKey.app` の製品 ID、版、feed、公開鍵、署名、公証チケットを確認して使う。さらに zip 内のファイル内容・権限・シンボリックリンクを app と照合し、異なれば中止する。この照合は署名や公証の検証の代わりにはならない。設定を変えた場合は app のビルドと公証からやり直す。コピー後も署名とチケットを確認する。Developer ID Installer と Team ID・タイムスタンプを検査し、公証応答が `Accepted` 以外なら中止、staple 後にチケット、署名、Gatekeeper の install 評価を検証する。公開用 pkg は検証完了まで一時ディレクトリに置き、完了後に `build/` へ移す。同名の既存リリースを上書きしない。

署名と公証の検査は試験データと ad-hoc 署名の拒否を確認済みだが、実在する証明書での成功、実際の公証・配信先での通し検証は未実施。現在の pkg 停止処理の実機挙動と Sparkle 更新時の入力解放が未検証のため、手順があることを公開承認とみなさない。

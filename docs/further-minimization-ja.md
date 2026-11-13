# 統合後の権限・プロセスをさらに減らせるか

調査日: 2026-10-25（JST）。対象コミット: `65400fb`。インストール済み build 6 を実機で確認した。

前提: [実現性レポート](permission-process-assessment-ja.md)の案 A（Core と VHID の統合）は [実装・検証記録](consolidated-service-validation-ja.md)のとおり反映済み。この文書では、そこからさらに減らせるかを評価する。コードの変更はしていない。

## 結論

**機能を一切変えずに減らせるのは、残骸の掃除と内部の権限の絞り込みまで。** 承認項目の種類と常駐プロセス数は、現在の構成がほぼ下限に当たる。

さらに減らす案は2つあるが、どちらも挙動が変わる。

| 減らすもの | 方法 | 何が変わるか |
| --- | --- | --- |
| 常駐 3→2 | UI と Agent を1プロセスにする | アクセシビリティを UI に付与することになり、「ReKey を終了」の意味も変わる |
| アクセシビリティを不要にする | EventViewer を、自分のウィンドウが最前面にある間だけ表示する方式に変える | 他のアプリで入力しながらイベントを見ることはできなくなる |

root プロセス1つと Karabiner 側の2プロセスは、現在の仮想 HID ドライバを使う限り減らせない。

## 実機の現状

| プロセス | 権限 | 観測 PID | 10秒間の CPU 時間（アイドル時） |
| --- | --- | --- | --- |
| ReKey（UI・メニューバー） | user | 18677 | 0.07 秒（約0.7%） |
| ReKeyAgent | user | 18985 | 0.08 秒（約0.8%） |
| rekey-core | root | 18984 | 0.23 秒（約2.3%） |
| Karabiner-VirtualHIDDevice-Daemon | root | 17122 | — |
| Karabiner DriverKit 拡張 | _driverkit | 563 | — |
| ThemeWidgetControlViewService | user | 18683 ほか | Apple の AppKit サービス。システム全体で7個あり、ReKey 専用ではない |

ReKey 固有のプロセスは3つで、うち root は1つ。キー入力がない状態でも、rekey-core が CPU を約2%使い続けている。

承認の状態（システム設定と `sfltool dumpbtm` で確認。TCC DB はフルディスクアクセスがないため直接は読めなかった）:

- 入力監視: rekey-core
- アクセシビリティ: ReKeyAgent（通常はオフ。EventViewer を使うときだけ必要）
- ドライバ拡張: Karabiner DriverKit
- バックグラウンド項目: rekey-core（有効）、Karabiner Daemon、ReKeyAgent、ReKey 本体
- 通知: `notify` アクションを初めて使ったときだけ要求する

`sfltool dumpbtm` には残骸もあった。

- `rekey-vhid`: 無効化されているが、登録が残っている。
- `ReKey` のアプリ項目が2件ある。うち1件は `pending authorization` の状態で、`rekey-vhid` を子項目として抱えたまま。
- アプリ内には `HelperTools/rekey-bench`（ベンチマーク用）と `LaunchDaemons/jp.example.rekey.vhid.plist`（移行用）が同梱されたまま。

## 1. 機能を変えずにできること（推奨）

### 1-1. 残骸の除去

| 対象 | 対応 | 効果 |
| --- | --- | --- |
| `rekey-bench` | `scripts/build-app.sh` で同梱をやめる | 署名済みの実行ファイルが1つ減る |
| `jp.example.rekey.vhid.plist` と移行処理 | 移行期間を決め、その後のリリースで削除する | バックグラウンド項目の残骸が残らなくなる |
| BTM の重複項目 | 現行の app から vhid の登録を解除したあと、システム設定で表示を確認する | 利用者に見える許可の一覧が実態と一致する |
| Agent の Info.plist | UI の plist を流用していて `NSInputMonitoringUsageDescription` まで引き継いでいる。Agent 用からは削除する | Agent が入力監視を要求するかのような誤解を防ぐ |

`sfltool resetbtm` は他のアプリの登録まで消してしまうため、使わない。

### 1-2. XPC の呼び出しを呼び出し元ごとに絞る

現状の Core は、UI と Agent の署名条件を OR で受け入れ、どちらにも同じ8個のメソッドを公開している（`Core/core.mm` の `Listener`）。

| 呼び出し元 | 実際に使うメソッド |
| --- | --- |
| UI | `status` / `reload` / `events` / `requestInputMonitoring` / `lifecycle` |
| Agent | `context` / `viewerRequested` / `actions` |

接続を受け入れる時点で、どちらの署名条件に一致したかを判定し、それぞれ別のプロトコルを公開する。こうすると、UI は入力のコンテキストを偽装できなくなり、Agent はイベントの履歴を読めなくなる。承認の種類は変わらないが、IPC 上の最小権限としては効果が大きい。

### 1-3. ポーリングをイベント駆動に変える（プロセス数は変わらないが負荷が下がる）

| 箇所 | 現状 | 置き換え先 |
| --- | --- | --- |
| Core の `tick()` | 5 ms ごと（200回/秒）。毎秒、全プロセスを root で走査（`proc_listallpids`）して Karabiner を検出し、設定ファイルも `stat` している | 長押しなどの期限があるときだけタイマーを張る。設定の変化はすでにある vnode 監視に任せる。Karabiner の検出は数秒間隔か、起動通知に変える（2026-11-14: Karabiner の検出は 5 秒間隔に変更。解析に失敗した設定はファイルが変わるまで再解析しない） |
| Agent の `tick()` | 100 ms ごと。最前面アプリ・入力ソース・デバイス・アクションをすべてポーリングしている | `NSWorkspace.didActivateApplicationNotification`、`kTISNotifySelectedKeyboardInputSourceChanged`、IOHIDManager の接続通知、Core から Agent へ XPC で通知を送る方式に変える |
| UI | 3秒ごとに状態を確認し、デバイスを列挙している | デバイス一覧は Core の `status` から受け取り、UI 側での HID 列挙をやめる |

EventViewer を使っている間の AX 判定は、鮮度の要件（500 ms）があるため、その間だけ周期処理を残す。CPU の削減量は未計測で、実装後に今回と同じ方法で比べる必要がある。

## 2. さらに減らす場合の選択肢（挙動が変わる）

### 2-1. UI と Agent を統合する（常駐 3→2）

UI はメニューバーに常駐しているので、Agent の仕事（最前面アプリ・入力ソースの報告、ホットキー、自動プロファイル切替、アクションの実行）は UI でも技術的にはこなせる。ただし代償がある。

- **アクセシビリティの付与先が UI になる。** UI は JSON のインポートやファイルダイアログなど、外部の入力を扱う範囲が広い。
- **シェルコマンドの実行に AX が付いて回る可能性が高い。** macOS の TCC は、子プロセスの権限を親の「責任プロセス」に帰属させる。このため AX を持つプロセスから起動した `shell_command` は、AX を持った状態で動くと考えられる（実機では未検証）。これは現在の Agent にもすでにある問題で、統合すると対象が UI 全体に広がる。
- **終了の意味が変わる。** 今は UI を終了しても、`disable_on_quit=false` なら Agent がアプリ条件やホットキーを維持する。統合すると、「ReKey を終了」は Agent の仕事もすべて止めることになる。

評価: AX を使わない場合に限り、プロセス数を減らす意味がある。最小権限を優先するなら、統合はしない方がよい。

### 2-2. Agent を必要なときだけ起動する（通常は2、条件付きで3）

Agent が必要なのは次のどれかを使っているときに限られる。

- アプリ条件・入力ソース条件
- 自動プロファイル切替
- プロファイルのホットキー
- ユーザーアクション
- EventViewer

ただし、一時停止のグローバルホットキー（⌃⌥⌘P）だけは常に Agent が登録している。Core は一時停止中にキーボードの占有を解いて入力を見なくなるため、Core に移すことはできない。この機能を常時残すなら、Agent も常駐させるしかない。

評価: 一時停止ホットキーをメニューバーからの操作だけに限定してよいなら、成立する。

### 2-3. アクセシビリティを使わない EventViewer

アクセシビリティは、EventViewer で「今の入力欄がパスワード欄ではないか」を確かめるためだけに使っている。そこで、イベントを記録する条件を「最前面アプリが ReKey 自身で、EventViewer のウィンドウがキーウィンドウである間」に限れば、他のアプリのパスワード欄を気にする必要がなくなる。最前面アプリの判定は `NSWorkspace` で取れるため、AX は要らない。Secure Event Input による抑止はそのまま残す。

- 得られるもの: 承認項目からアクセシビリティが完全に消え、Agent の AX 判定コードも削除できる。
- 失うもの: 「TextEdit で入力しながら変換結果を EventViewer で見る」という使い方ができなくなる。EventViewer 上での入力確認だけになる。

評価: 承認の種類を減らす効果は最も大きい。EventViewer の使い方を変えてよいかどうかが判断の分かれ目になる。

## 3. これ以上は減らせないもの

| 項目 | 理由 |
| --- | --- |
| rekey-core の root | Karabiner の仮想 HID クライアントは root で動かす必要がある。接続用ソケットも root 専用のディレクトリにある |
| Karabiner Daemon と DriverKit 拡張 | 公式署名のドライバへの接続経路そのもの。直接つなぐには DriverKit の entitlement と独自署名が必要になる |
| 入力監視 | 物理キーボードを占有するのに必要。付与先はすでに rekey-core の1つだけ |
| ドライバ拡張・バックグラウンド項目の承認 | 仮想 HID とログイン後の常駐に必要 |
| すべてを1つの root プロセスに統合 | UI、JSON の読み込み、シェルの実行まで root で動くことになる。不採用 |
| Event Tap と `CGEventPost` への置き換え | デバイスごとの占有や内蔵キーボードの無効化ができなくなる。不採用 |

## 推奨の順序

1. 1-1 の残骸除去と 1-2 の XPC 分離（機能は変わらない）
2. 1-3 のイベント駆動化（負荷の削減。改善前後の CPU 比較を合格基準にする）
3. 2-3（AX を使わない EventViewer）を採るかどうか判断する。採るなら、2-1 の統合の代償（AX が UI に付く）は大幅に小さくなる
4. 2-1 または 2-2 でプロセス数を減らすかどうかは、3 の判断の後に決める

## 根拠

- `Core/core.mm`: 5 ms タイマー、毎秒の `karabiner()` 走査（現在は 5 秒ごと）と `load()`、`Listener` の OR 条件、全メソッドの公開
- `Sources/ReKeyAgent/main.swift`: 100 ms タイマー、⌃⌥⌘P の登録、`AXIsProcessTrusted`、`shell_command` の実行
- `Sources/ReKeyApp/AppState.swift`: 3秒ポーリング、`refreshDevices()`、vhid の移行処理
- `scripts/build-app.sh`: `rekey-bench` と vhid plist の同梱、Agent の Info.plist の流用
- 実機: `ps`、`top`、`codesign -dv`、`sfltool dumpbtm`（2026-10-25 に取得）

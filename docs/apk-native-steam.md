# APK 内で Steam を完結させる設計（Steamworks SDK 1.63 / androidarm64）

## 結論

**SDK 1.63 だけでは完結しない。** SDK に入っているのはゲーム側の窓口である
`redistributable_bin/androidarm64/libsteam_api.so` だけで、Steam クライアント本体は入っていない。
Valve のドキュメントは `SteamAPI_Init` が失敗する原因として
「Steam クライアントが起動していない（各インターフェースの実装はクライアントが提供する）」を
挙げている。Steam Frame ではクライアントを OS 側で用意するのが前提だと考えられる
（Valve の公式説明は見つかっていない）。スマホにはそのクライアントが無い。

APK 内で完結させるには、次の 3 つをすべて APK に持たせる必要がある。

| 部品 | 中身 | 入手 | APK に同梱できるか |
|---|---|---|---|
| A. `libsteam_api.so` | ゲームが呼ぶ Steamworks API | SDK 1.63 `androidarm64/` | 可（SDK の redistributable） |
| B. `libsteamclient.so` (Android/bionic) | Steam クライアント本体 | Valve の Steam クライアント（Steam Frame 用 Android ビルド） | **不可**。Valve の非公開・非再配布バイナリ。実行時に自分のアカウントで取得するか、自分で置く |
| C. ブートストラップ | B を `dlopen` し、リフレッシュトークンでログインさせる | **自作**（非公開の内部シンボルを解析する必要がある） | 自作なら可 |
| D. ログイン | QR / パスワード + Steam Guard → リフレッシュトークン | JavaSteam | 可 |

実際に動いている先行例は GameNative の「bionic Steam」モードだ（ソースで確認済み）。

- `libsteambootstrap.so`（作者独自のシム。**ソース非公開**・独自ライセンス）を別プロセスとして起動する。
  このシムが Android 版 `libsteamclient.so` を `dlopen` し、リフレッシュトークンでログインさせる
- 環境変数は `HOME`, `Steam3Master`, `SteamClientService`, `SB_ACCOUNT`, `SB_REFRESH_TOKEN`, `SB_STEAMID64`。
  起動状態は `cacheDir/sb_host_ready` に `INIT` / `READY` / `FAILED:...` として書かれる
- `libsteamclient.so` は作者側サーバーから `steam-androidarm64-<日付>.tzst` として配布されている
- ゲームは Wine 内で動き、`lsteamclient.dll` を介してこのクライアントにつながる

このリポジトリの APK はネイティブ Android なので Wine は要らない。
`libsteam_api.so`（A）から B に直接つなぐ形になり、GameNative より 1 段薄くできる。

## 構成

```
┌─────────────── APK (同一 UID) ─────────────────────────────┐
│ :main プロセス                    :steamhost プロセス        │
│  GameActivity                      SteamHostService(前景)   │
│   └ ゲーム本体                      └ bootstrap (C, 自作)   │
│      └ libsteam_api.so (A) ──IPC──────→ libsteamclient.so(B)│
│  LoginActivity (JavaSteam, D)                  │            │
│   └ refresh token → Android Keystore で暗号化保存 ┘          │
└────────────────────────────────────────────────────────────┘
```

- クライアントは `android:process=":steamhost"` の別プロセスで動かす。落ちてもゲームを巻き込まず、
  ゲームを止めずに凍結・終了だけできる。プロセスは同じ UID なので、アプリ専用ディレクトリの
  ソケットや共有メモリで通信できる
- online / offline の切り替えは、Wine 版ランチャー（`bin/steaminghe`）と同じ考え方にする
  - **online**: SteamHostService を前景サービスとして常駐させる。スレッド優先度を下げる
  - **offline**: ゲームの `SteamAPI_Init` 成功をゲーム側の JNI フックで受け取る。
    猶予を置いてから host プロセスを `SIGSTOP`（同じ UID なので可能）するか、終了させる。
    ゲーム終了時は必ず `SIGCONT` してから終了する

## マイルストーン（この順でやる。M1 と M2 で道が決まる）

### M0. APK の中身を確かめる（すぐできる）
```sh
tools/inspect-apk.sh game.apk
```
ここで次の 3 つを確定させる。
- arm64-v8a があるか
- エンジンは何か
- Steam API がどの形で残っているか（Windows 用 `steam_api64.dll` の残骸 / 呼び出し除去済み / arm64 の `.so` 同梱済み）

Unity (IL2CPP) で Steamworks.NET を使っている場合、P/Invoke の呼び出し先名は `steam_api` / `steam_api64` だ。
その名前で `lib/arm64-v8a/libsteam_api.so`（必要なら `libsteam_api64.so` も）を置けばつながる。

### M1. SDK 1.63 を入手して A を解析する
- 入手先は partner.steamgames.com（Steamworks アカウントが要る）。非公式ミラーからは取らない
- 解析は `tools/inspect-apk.sh game.apk <sdk_dir>` で行う。`libsteam_api.so` がクライアントを
  どう探すか（`Steam3Master` などの環境変数、`HOME/.steam`、`steamclient` の名前）を文字列から洗い出す。
  B をどこに置き、どの環境変数を立てれば A が見つけるかを、ここで決める

### M2. 最小の検証アプリ（Spacewar, AppID 480）
- 中身は `SteamAPI_InitFlat()` を呼んで、戻り値（`ESteamAPIInitResult`）とエラーメッセージを画面に出すだけの APK
- クライアント無しで実行すれば「クライアント不在」で失敗するはずだ。その失敗の仕方が、M3 で何を満たせばいいかの仕様になる

### M3. クライアント host（最大の難所）
選択肢は 2 つある。
1. **GameNative 開発者に連絡する**（Discord）。`libsteambootstrap.so` を自作 APK で使えるか、
   相互運用の方法があるかを聞く。独自ライセンスのバイナリなので、**無断で同梱はしない**
2. **自作する**。B の公開シンボル（`CreateInterface` 等）から `IClientEngine` 系のパイプ作成、
   ユーザー作成、トークンログインまでを解析する。非公開の内部仕様なので Steam の更新で壊れる。
   規約上の扱いも灰色だ。GameNative の作者もこれを理由にソースを公開していない

B の入手は、GameNative と同じく**ユーザー自身が実行時に取得したものだけを使う**。APK に入れて配らない。

### M4. ログイン
JavaSteam で QR / パスワード + Steam Guard → リフレッシュトークンを取得し、
Android Keystore で暗号化して保存する。トークンはログにも出さない。

### M5. ライフサイクル
online / offline、凍結・解除、ゲーム異常終了時の後始末。テストは `bin/steaminghe` と同じ観点で書く。

## 赤信号（やらないこと）

- `libsteamclient.so` や他人の `libsteambootstrap.so` を APK に入れて配る
- Goldberg などで Steam API を偽物に差し替えて、DRM チェックを外す。
  アクセス制御の回避は著作権法上も危ない（日本の 2018 年改正で規制が強まっている。具体的な適用は専門家に確認）
- 作り直した APK を他人に配る（ゲームの著作権の問題）。自分の端末で、自分の所有タイトルにだけ使う

## 出典

- Valve, Steamworks API Overview — `SteamAPI_Init` が失敗する条件: https://partner.steamgames.com/doc/sdk/api
- Steamworks SDK 1.63 リリース告知: https://steamcommunity.com/groups/steamworks/announcements/detail/627817201164877826
- GamingOnLinux（SDK 1.63 と Steam Frame）: https://www.gamingonlinux.com/2025/11/steamworks-sdk-adds-support-for-linux-arm-and-android-and-it-seems-we-know-the-first-android-game-on-steam/page=1/
- XDA（GameNative の bionic クライアント）: https://www.xda-developers.com/steam-client-hurting-pc-gaming-android-valve-vr-headset-accidentally-solved-it/
- GameNative のソース（`SteamBootstrap.kt`, `BionicSteamAssetsDependency.kt`, `THIRD_PARTY_NOTICES`）: https://github.com/utkarshdalal/GameNative
- arm64 の `steamclient.so` が未配布だという指摘: https://github.com/ValveSoftware/SteamOS/issues/2192

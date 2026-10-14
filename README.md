# Steaminghe

Android 上で Windows 版 Steam ゲームを動かすとき、**本物の Steam クライアント（自分のアカウントでログイン）**
をゲームの起動条件として、できるだけ低い負荷で動かすためのランチャー。

## 何を解決するか

Steamworks を使うゲームは `SteamAPI_Init()` で「Steam が起動中でログイン済みか」を確認し、
失敗すると起動を拒否する（または Steam から再起動しようとする）。Wine 上ではその判定材料が

- レジストリ `HKCU\Software\Valve\Steam\ActiveProcess`（`pid` / `ActiveUser` / `SteamClientDll`）
- それが指す `steamclient(64).dll` と、動いている `steam.exe` との IPC

になる。ここを**偽装せず**、本物の `steam.exe` を Wine/Box64 で動かして満たす。DRM 回避や
Goldberg 等のエミュレータへの差し替えはやらない（アカウント規約上もこれが安全）。

問題は負荷。Steam クライアントは CEF(Chromium) の UI・更新確認・クラウド同期を抱えたまま
Box64 の動的再コンパイルと DirectX→Vulkan 変換を通るので、ファンの無いスマホでは
ゲームと熱・CPU を奪い合う。そこで用途別に止め方を変える。

| MODE | 動作 | 向いているゲーム |
|---|---|---|
| `online` | ゲーム中ずっと常駐。`nice 19` + 省電力コア固定。任意で `steamwebhelper` を凍結 | マルチ、実績、クラウドセーブ、ワークショップ |
| `offline` + `freeze` | ゲームが Steam に接続（`Apps\<appid>\Running=1`）したら Steam 全プロセスを `SIGSTOP` | DRM チェックだけ通ればいいシングル |
| `offline` + `shutdown` | 同じタイミングで Steam を `-shutdown` | Steam 消失を気にしないゲーム（メモリも解放） |

`freeze` はプロセスと IPC ハンドルを残したまま CPU 消費だけをほぼ 0 にするので、
`shutdown` より壊れにくい。ただしゲームが凍結中の Steam に同期問い合わせをすると
そこで固まる。その場合は `online` に切り替える。ゲーム終了時・Ctrl-C 時は必ず凍結を
解除してから Steam を終了する（凍結したまま残すと wineserver ごと詰まるため）。

## 使い方

前提: Winlator / GameNative のコンテナ、または Termux + Box64 + Wine など、
`wine` と Windows 版 Steam がインストール済みの Linux シェルがあること。

```sh
# 1回目だけ: Steam を普通に起動して自分のアカウントでログイン（パスワード保存にチェック）
wine 'C:\Program Files (x86)\Steam\steam.exe'

# 以後はプロファイルを書いて起動
cp profiles/example.conf profiles/mygame.conf   # APPID と GAME_EXE を書き換える
bin/steaminghe launch profiles/mygame.conf

bin/steaminghe status        # ActiveUser と Steam の PID
bin/steaminghe steam-stop    # Steam を終了
```

Winlator のショートカットや APK ラッパーからは、ゲーム exe の代わりに
`steaminghe launch <profile>` を呼ぶ。

環境変数で上書きできるもの: `WINE`, `STEAM_EXE`, `STEAM_ARGS`（既定 `-silent`）,
`STEAM_LOGIN_TIMEOUT`, `POLL_SEC`。`-no-browser` 等の CEF を減らすオプションは
最近の Steam で削除されたという報告があるので既定にはしていない。自分の環境で試して
効けば `STEAM_ARGS` に足す。

## テスト

```sh
tests/run_tests.sh
```

`wine` と `pgrep` をモックに差し替え、online / offline(freeze) / offline(shutdown) /
webhelper 凍結 / 終了コード伝搬 / ログインタイムアウトを検証する（Linux 上で実行可能）。

## 既存プロジェクトとの関係・今後

- [GameNative](https://github.com/utkarshdalal/GameNative)（Pluvia のフォーク、GPL-3.0）は
  JavaSteam でログイン・ダウンロードし、Winlator 系の環境でゲームを動かす Android アプリ。
  まずはこれで足りるか確認すべき。
- Valve は Steamworks SDK 1.63（2025年11月）で `androidarm64` / `linuxarm64` の
  ライブラリを追加した。GameNative 1.0 はこれを使う「bionic」Steam クライアント
  （UI なし・ヘッドレス）を実験的に載せている。これが安定すれば、Wine 上の
  `steam.exe` を丸ごと置き換えられて負荷は大きく下がる。steaminghe の
  `STEAM_EXE` / 判定関数を差し替える形で対応する予定。

## ネイティブ APK 内で完結させる道

Android 向けに作り直した APK の中で、Steamworks SDK 1.63（androidarm64）を使って完結させる設計は
[docs/apk-native-steam.md](docs/apk-native-steam.md) にまとめた。APK の中身は次で調べる。

```sh
tools/inspect-apk.sh game.apk [steamworks_sdk_dir]
```

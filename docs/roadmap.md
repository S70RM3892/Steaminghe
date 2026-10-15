# ロードマップ（家の環境: REDMAGIC 10 Pro 16GB/512GB + PC）

ゴール: 自分の Steam ゲームを、自分のアカウントのまま Android 上でできるだけ快適に動かす。
主な道具は GameNative。Steam の負荷対策は、GameNative の bionic モード（実験的）か、Winlator 上の `bin/steaminghe` を使う。

**やめた道:** Unity から作り直した APK（Valheim など）。Valheim のソースは公開されていないので、
そのプロジェクトは逆コンパイル由来になる。Steam の確認を外すのは DRM の回避で、正攻法で通すための
Android 版 Steam 本体も、一般に使える形では手に入らない。労力はすべて GameNative 側に回す。

**時間のルール:** 1 回の作業は 60 分まで。寝る 1 時間前には終える。1 回に変える設定は 1 つだけにする。

---

## Phase 0. 環境を作る（初回 30 分）

- [ ] 端末: 開発者向けオプション → USB デバッグ ON
- [ ] PC: Android SDK Platform-Tools を入れる → `adb devices` で端末が見えることを確認
- [ ] GameNative を最新版にする（GitHub Releases から）
- [ ] 端末: GameNative のバッテリーを「制限なし」、バックグラウンド実行を許可にする
      （RM10 Pro + Winlator で、この設定でフレーム落ちがほぼ消えたという報告がある）
- [ ] 端末: Game Space でファンを最大にし、性能モードにする
- [ ] PC: このリポジトリを clone して `tests/run_tests.sh` が通ることを確認

## Phase 1. 計測の型を決める（初回 20 分。以後は毎回同じやり方で測る）

体感ではなく、数字で比べる。

- 計測場面はゲームごとに 1 つに固定する。Valheim なら拠点から決まったルートを 3 分歩く。Detroit なら章の冒頭 3 分
- 記録は 4 つ:
  - 平均 fps（GameNative/Winlator の FPS 表示）
  - プチフリの回数（目で数える）
  - 温度とクロック（PC 側で記録）:
    ```sh
    tools/perf-log.sh 5 logs/valheim-baseline.csv
    ```
    CPU 最大温度が上がったあとに `cpuN_mhz` が落ちていれば、熱による性能低下（サーマルスロットリング）だ
  - 設定の差分 1 行
- 結果は下の「記録表」に追記する

## Phase 2. Valheim（ベースラインあり、プチフリと fps 低下が出ている）

上から順に 1 つずつ試す。効いたら残し、効かなければ戻す。

| # | 変更 | 狙い |
|---|---|---|
| 2-1 | Phase 0 の端末設定を反映した状態で計測し直す | 基準を取り直す |
| 2-2 | fps 上限を 30（または 40）に固定 | 発熱を抑え、フレームを安定させる。体感ではこれが一番効く |
| 2-3 | 起動オプション `-force-vulkan` | DirectX 11 を Vulkan に変換する層（DXVK）を飛ばし、Unity から直接 Vulkan で描く。Android 上で試した報告は未確認 |
| 2-4 | 影・植生・描画距離・SSAO・被写界深度・ブラー・ブルームを下げる | GPU 負荷を下げる |
| 2-5 | Box64 プリセットを Performance にする | CPU 命令の変換コストを下げる |
| 2-6 | bionic Steam モード（Proton 10） | Wine 上の Steam クライアントが食っていた負荷を消す |
| 2-7 | `valheim_Data/boot.config` 先頭に `gfx-enable-gfx-jobs=1` と `gfx-enable-native-gfx-jobs=1` を追加 | PC で効いたという報告が 1 件ある。効けば儲けもの |

プチフリの止まり方で、どの対策が本命かわかる。
- 初めての場所やエフェクトで止まる → シェーダーのコンパイル待ち → 2-3
- 一定間隔で止まる → 保存処理か GC（メモリ掃除） → 設定では消しにくい。頻度だけ記録する
- だんだん重くなる → 熱による性能低下 → 2-2 とファン

Steam の要否: マルチプレイをするなら online（Steam を常駐させる）。ソロなら offline でいい。

## Phase 3. Detroit: Become Human

- PC 版は**最初から Vulkan で描画する**（DirectX は使わない）ので、DXVK の変換が要らない。Android には有利な作りだ
- 目標: 720p、低設定、30fps 固定。会話や映像の多いゲームなので 30fps で十分
- 参考: Snapdragon 8 Elite Gen 5 の端末で「720p・低設定」で動かした動画がある。fps の数値は確認できていない
- 容量が大きいので、インストール前に空き容量を確認する
- 長時間動かすと熱が問題になるはず。`perf-log.sh` を必ず回す
- Steam の要否: ソロなので offline（起動時だけ Steam を動かす）でいいはず

## Phase 4. Steam の負荷を詰める

| 方式 | どこで | 状態 |
|---|---|---|
| GameNative 通常モード | Wine 上の steam.exe | 重い（いまの基準） |
| GameNative bionic モード | Android ネイティブの Steam、画面なし | 実験的。Proton 10 で使う |
| Winlator + `bin/steaminghe` | Wine 上の steam.exe を常駐、または凍結・終了させる | このリポジトリにある。実機では未検証 |

同じゲームの同じ場面で 3 方式を比べ、ゲームごとに一番いい方式を決める。

## Phase 5. ゲームを増やす

新しいゲームは次の順で調べる。
1. 描画 API（DX11 / DX12 / Vulkan）
2. Steam が必要か（ソロか、マルチか）
3. Phase 1 の計測
4. 記録表に追記

---

## 記録表

| 日付 | ゲーム | 変更 | 平均fps | プチフリ/3分 | CPU最大℃ | 結論 |
|---|---|---|---|---|---|---|
|  | Valheim | ベースライン |  |  |  |  |

## 出典

- RM10 Pro + Winlator のバックグラウンド設定: https://redlib.hbubli.cc/r/RedMagic/comments/1hz4j7r/rm_10_pro_winlator_emulation
- Valheim `-force-vulkan`: https://www.pcinvasion.com/?p=359903 / https://steamcommunity.com/app/892970/discussions/0/3164316851902689616
- Valheim boot.config: https://steamcommunity.com/app/892970/discussions/0/3106891514119117461
- Winlator Box64 プリセット: https://github.com/winebox64/winlator
- GameNative bionic Steam: https://www.xda-developers.com/steam-client-hurting-pc-gaming-android-valve-vr-headset-accidentally-solved-it/
- Detroit PC 版が Vulkan であること: https://www.guru3d.com/news-story/detroit-become-human-system-requirements-uses-vulkan.html
- Detroit を Snapdragon 8 Elite Gen 5 + Winlator で動かした動画: https://www.youtube.com/watch?v=miVzMogDOm4

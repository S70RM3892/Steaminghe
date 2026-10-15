#!/usr/bin/env bash
# モック wine/pgrep で steaminghe の起動シーケンスを検証する
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=$ROOT/bin/steaminghe
fail=0

setup() {
  MOCK_STATE=$(mktemp -d)
  export MOCK_STATE MOCK_APPID=480 POLL_SEC=1
  export WINE=$ROOT/tests/mocks/wine PGREP=$ROOT/tests/mocks/pgrep
  PROFILE=$MOCK_STATE/p.conf
  printf 'APPID=480\nGAME_EXE=game.exe\nGRACE_SEC=0\nSTEAM_CPUS=\n' >"$PROFILE"
}
teardown() {
  [ -f "$MOCK_STATE/all_pids" ] && kill -CONT $(cat "$MOCK_STATE/all_pids") 2>/dev/null && kill $(cat "$MOCK_STATE/all_pids") 2>/dev/null
  rm -rf "$MOCK_STATE"
}
check() { # name cond...
  local name=$1; shift
  if "$@"; then echo "ok   - $name"; else echo "FAIL - $name"; fail=1; fi
}
states_all() { # ゲーム終了時点で全 Steam プロセスの状態が $1 か
  [ -s "$MOCK_STATE/states_at_game_end" ] &&
    awk -v s="$1" '$2 != s {bad=1} END {exit bad}' "$MOCK_STATE/states_at_game_end"
}
called() { grep -qF -- "$1" "$MOCK_STATE/calls"; }

# 1. online: ゲーム中 Steam は動き続け、終了後 shutdown
setup
echo MODE=online >>"$PROFILE"
"$BIN" launch "$PROFILE" 2>"$MOCK_STATE/log"; rc=$?
check "online: rc=0" [ "$rc" -eq 0 ]
check "online: Steam は -silent で起動" called 'steam.exe -silent'
check "online: ゲーム中 Steam は凍結されない" bash -c "! grep -q ' T$' '$MOCK_STATE/states_at_game_end'"
check "online: 終了後 -shutdown" called 'steam.exe -shutdown'
teardown

# 2. offline/freeze: ゲーム中 Steam は全プロセス停止(T)、終了後に解除して shutdown
setup
printf 'MODE=offline\nOFFLINE_STRATEGY=freeze\n' >>"$PROFILE"
"$BIN" launch "$PROFILE" 2>"$MOCK_STATE/log"; rc=$?
check "offline/freeze: rc=0" [ "$rc" -eq 0 ]
check "offline/freeze: ゲーム中 Steam は全て凍結" states_all T
check "offline/freeze: 凍結解除ログ" grep -q '凍結解除' "$MOCK_STATE/log"
check "offline/freeze: 終了後 -shutdown" called 'steam.exe -shutdown'
teardown

# 3. offline/shutdown: ゲーム中に Steam は終了済み
setup
printf 'MODE=offline\nOFFLINE_STRATEGY=shutdown\n' >>"$PROFILE"
"$BIN" launch "$PROFILE" 2>"$MOCK_STATE/log"; rc=$?
check "offline/shutdown: rc=0" [ "$rc" -eq 0 ]
check "offline/shutdown: ゲーム中 Steam 不在" grep -qx none "$MOCK_STATE/states_at_game_end"
teardown

# 4. online + WEBHELPER=freeze: webhelper だけ凍結
setup
printf 'MODE=online\nWEBHELPER=freeze\n' >>"$PROFILE"
"$BIN" launch "$PROFILE" 2>"$MOCK_STATE/log"
check "webhelper: webhelper のみ T" bash -c "[ \$(grep -c ' T\$' '$MOCK_STATE/states_at_game_end') -eq 1 ]"
teardown

# 5. ゲームの終了コードを引き継ぐ
setup
export MOCK_GAME_RC=3 MOCK_GAME_SEC=1
"$BIN" launch "$PROFILE" 2>/dev/null; rc=$?
check "rc 伝搬" [ "$rc" -eq 3 ]
unset MOCK_GAME_RC MOCK_GAME_SEC
teardown

# 6. 不正な MODE を拒否
setup
echo MODE=bogus >>"$PROFILE"
"$BIN" launch "$PROFILE" 2>/dev/null; rc=$?
check "不正 MODE で失敗" [ "$rc" -ne 0 ]
teardown

# 7. ログインしないと timeout で失敗
setup
export STEAM_LOGIN_TIMEOUT=2 STEAM_EXE='C:\nologin\steam_never.exe'
"$BIN" launch "$PROFILE" 2>/dev/null; rc=$?
check "ログイン timeout で失敗" [ "$rc" -ne 0 ]
unset STEAM_LOGIN_TIMEOUT STEAM_EXE
teardown

# 8. perf-log: モック adb の出力から温度・クロックを CSV にする
d=$(mktemp -d)
ADB=$ROOT/tests/mocks/adb timeout 1.5 "$ROOT/tools/perf-log.sh" 1 "$d/p.csv" >/dev/null 2>&1
check "perf-log: ヘッダ" grep -qx 'time,battery_c,cpu_max_c,gpu_max_c,skin_c,cpu0_mhz,cpu1_mhz,cpu2_mhz' "$d/p.csv"
check "perf-log: 値（電池38.5 CPU最大72.25 GPU58 表面40.1 MHz）" grep -qE '^[0-9:]+,38\.5,72\.25,58\.0,40\.1,1785,3532,0$' "$d/p.csv"
rm -rf "$d"

exit $fail

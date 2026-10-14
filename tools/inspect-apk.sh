#!/usr/bin/env bash
# APK が Steamworks をどう使っているかを調べる。
#   tools/inspect-apk.sh <game.apk> [steamworks_sdk_dir]
# 出力: ABI 一覧、エンジン推定、steam_api の有無と ABI、Steam 関連ファイル、
#       （SDK を渡せば）androidarm64 libsteam_api.so がクライアントを探す手がかり
set -u
apk=${1:?usage: inspect-apk.sh <game.apk> [steamworks_sdk_dir]}
sdk=${2:-}
[ -f "$apk" ] || { echo "APK が無い: $apk" >&2; exit 1; }

list=$(unzip -Z1 "$apk" 2>/dev/null) || { echo "zip として読めない: $apk" >&2; exit 1; }

echo "== ABI"
abis=$(grep -oE '^lib/[^/]+/' <<<"$list" | cut -d/ -f2 | sort -u)
echo "${abis:-（ネイティブライブラリ無し）}"
grep -qx arm64-v8a <<<"$abis" || echo "!! arm64-v8a が無い。SDK 1.63 の androidarm64 は arm64 専用"

echo "== エンジン推定"
engine=unknown
grep -q '/libil2cpp\.so$' <<<"$list" && engine="Unity (IL2CPP)"
[ "$engine" = unknown ] && grep -q '/libmonobdwgc-2.0\.so$\|/libmono\.so$' <<<"$list" && engine="Unity (Mono)"
grep -q '/libgodot_android\.so$' <<<"$list" && engine=Godot
grep -qE '/libUE4\.so$|/libUnreal\.so$' <<<"$list" && engine=Unreal
grep -q '/libSDL2\.so$' <<<"$list" && [ "$engine" = unknown ] && engine="SDL2 系（自作/移植エンジン）"
echo "$engine"

echo "== Steam 関連ファイル"
steam_files=$(grep -iE 'steam|sdkencryptedappticket' <<<"$list")
echo "${steam_files:-（無し）}"

echo "== 判定"
if grep -q '^lib/arm64-v8a/libsteam_api\.so$' <<<"$list"; then
  echo "arm64 の libsteam_api.so 同梱済み → 足りないのは Steam クライアント側だけ"
elif grep -qiE 'steam_api(64)?\.dll|libsteam_api\.so' <<<"$list"; then
  echo "Steam API はあるが arm64 Android 用ではない → SDK 1.63 の androidarm64/libsteam_api.so に差し替えが要る"
else
  echo "steam_api 本体が見当たらない → 呼び出しが除去済みか、別名・別形式で埋め込まれている"
fi
if [ "$engine" = "Unity (IL2CPP)" ]; then
  tmp=$(mktemp -d)
  unzip -qo "$apk" 'assets/bin/Data/Managed/Metadata/global-metadata.dat' -d "$tmp" 2>/dev/null
  if [ -f "$tmp/assets/bin/Data/Managed/Metadata/global-metadata.dat" ] &&
     grep -aqE 'Steamworks|SteamAPI_Init' "$tmp/assets/bin/Data/Managed/Metadata/global-metadata.dat"; then
    echo "IL2CPP メタデータに Steamworks の参照あり（Steamworks.NET 等）→ P/Invoke 先は \"steam_api\"/\"steam_api64\""
    echo "== Steam 確認に使われている API（メタデータ中の名前）"
    grep -aoE 'Steamworks\.NET|Facepunch\.Steamworks|SteamManager|RestartAppIfNecessary|SteamAPI_Init[A-Za-z]*|IsSteamRunning|steam_appid(\.txt)?|BIsSubscribed[A-Za-z]*|GetAppID|BLoggedOn|DllNotFoundException' \
      "$tmp/assets/bin/Data/Managed/Metadata/global-metadata.dat" | sort | uniq -c | sort -rn
  fi
  rm -rf "$tmp"
fi

if [ -n "$sdk" ]; then
  echo "== SDK androidarm64 libsteam_api.so の手がかり"
  lib=$(find "$sdk" -path '*androidarm64*' -name libsteam_api.so | head -1)
  if [ -z "$lib" ]; then
    echo "androidarm64/libsteam_api.so が SDK 内に無い（1.63 以降か確認）"
  else
    echo "$lib"
    command -v readelf >/dev/null && readelf -d "$lib" | grep -E 'NEEDED|SONAME'
    # クライアントの探し方（環境変数・パス・ライブラリ名）
    strings -n 6 "$lib" | grep -E 'steamclient|Steam3Master|SteamClientService|SteamAppId|SteamGameId|HOME|\.steam|steam\.pid|registry\.vdf|/proc/' | sort -u
  fi
fi

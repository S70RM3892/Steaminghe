#!/usr/bin/env bash
# adb でつないだ端末の温度・CPU クロック・バッテリー温度を一定間隔で CSV に記録する。
#   tools/perf-log.sh [interval_sec] [out.csv]
# ゲーム中に PC 側で回し、Ctrl-C で止める。root 不要。
set -u
ADB=${ADB:-adb}
interval=${1:-5}
out=${2:-perf-$(date +%Y%m%d-%H%M%S).csv}

"$ADB" get-state >/dev/null 2>&1 || { echo "adb で端末が見えない（USB デバッグ ON / adb devices を確認）" >&2; exit 1; }

# 最初の 1 回だけ CPU の数を取る
ncpu=$("$ADB" shell 'ls -d /sys/devices/system/cpu/cpu[0-9]* | wc -l' | tr -d '\r ')
hdr="time,battery_c,cpu_max_c,gpu_max_c,skin_c"
for i in $(seq 0 $((ncpu - 1))); do hdr="$hdr,cpu${i}_mhz"; done
echo "$hdr" | tee "$out"

while :; do
  # 端末側で 1 回の shell 呼び出しにまとめて負荷を抑える
  raw=$("$ADB" shell '
    dumpsys battery | grep -m1 " temperature:" | tr -dc 0-9; echo
    dumpsys thermalservice | grep "mValue=" | sed -n "/Current temperatures/,/Current cooling/p"
    echo ===FREQ
    for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do cat "$f" 2>/dev/null || echo 0; done
  ' 2>/dev/null | tr -d '\r')
  bat=$(sed -n 1p <<<"$raw")
  temps=$(sed -n '2,/===FREQ/p' <<<"$raw")
  # mType: 0=CPU 1=GPU 2=BATTERY 3=SKIN（Android Temperature の定義）
  maxof() { grep -oE "mValue=[0-9.]+, mType=$1," <<<"$temps" | grep -oE '[0-9.]+' | awk 'NR%2==1' | sort -n | tail -1; }
  cpu=$(maxof 0); gpu=$(maxof 1); skin=$(maxof 3)
  freqs=$(sed -n '/===FREQ/,$p' <<<"$raw" | tail -n +2 | awk '{printf ",%d", $1/1000}')
  line="$(date +%H:%M:%S),$(awk -v b="${bat:-0}" 'BEGIN{printf "%.1f", b/10}'),${cpu:-},${gpu:-},${skin:-}$freqs"
  echo "$line" | tee -a "$out"
  sleep "$interval"
done

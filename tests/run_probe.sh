#!/bin/bash
# ----------------------------------------------------------------
# run_probe.sh
#     Runs tests/arctic_probe over many map seeds at once (one Godot
#     process per seed, as many at a time as there are jobs) and prints
#     one line per seed and a summary. A seed repeats the same game, so
#     run it before and after a change and compare the same seeds.
#
#     tests/run_probe.sh [-d days] [-c climate] [-f fields] [-s "seeds"]
#                        [-k crops] [-t time_scale] [-j jobs]
#       -d  game days to run (45)            -c  climate id: 0 temperate, 1 arctic, 2 desert, 3 tropical (1)
#       -f  fields at the start (3)          -s  map seeds, a quoted list ("1 2 3 4 5 6 7 8 9 10 11 12")
#       -k  the fields' crops, comma separated (barley,wheat,radish)
#       -t  Engine.time_scale (4 = 20x game speed; 10 = 50x, see CLAUDE.md before going faster)
#       -j  runs at a time (the number of cores)
#     GODOT=/path/to/godot overrides the binary.
# ----------------------------------------------------------------
GODOT=${GODOT:-/home/rmh/godot/Godot_v4.7.2-stable_linux.x86_64}
DIR=$(cd "$(dirname "$0")/.." && pwd)
DAYS=45; CLIMATE=1; FIELDS=3; SEEDS="1 2 3 4 5 6 7 8 9 10 11 12"; CROPS=""; SCALE=4; JOBS=$(nproc)
while getopts "d:c:f:s:k:t:j:" opt; do
  case $opt in
    d) DAYS=$OPTARG;; c) CLIMATE=$OPTARG;; f) FIELDS=$OPTARG;; s) SEEDS=$OPTARG;;
    k) CROPS=$OPTARG;; t) SCALE=$OPTARG;; j) JOBS=$OPTARG;;
    *) sed -n 2,19p "$0"; exit 2;;
  esac
done
OUT=$(mktemp -d "${TMPDIR:-/tmp}/probe.XXXXXX")
trap 'rm -rf "$OUT"' EXIT

run_one() {
  local seed=$1
  timeout 900 "$GODOT" --headless --path "$DIR" --fixed-fps 60 res://tests/arctic_probe.tscn -- \
    "$DAYS" "$CLIMATE" "$FIELDS" "$seed" x "$CROPS" "$SCALE" 2>&1 | grep "ARCTIC PROBE" > "$OUT/$seed.txt"
}
export -f run_one
export GODOT DIR DAYS CLIMATE FIELDS CROPS SCALE OUT

start=$(date +%s)
printf '%s\n' $SEEDS | xargs -P "$JOBS" -I{} bash -c 'run_one {}'
secs=$(( $(date +%s) - start ))

survived=0; total=0; people=0
for seed in $SEEDS; do
  line=$(cat "$OUT/$seed.txt" 2>/dev/null)
  n=$(echo "$line" | sed -n 's/.*: \([0-9]*\) citizens at day.*/\1/p')
  low=$(echo "$line" | sed -n 's/.*lowest food stock \([0-9]*\).*/\1/p')
  verdict=$(echo "$line" | grep -o "PASS\|FAIL")
  printf 'seed %-8s %-5s %2s citizens left, lowest food %s\n' "$seed" "${verdict:-ERROR}" "${n:-?}" "${low:-?}"
  total=$((total + 1))
  if [ "$verdict" = "PASS" ]; then survived=$((survived + 1)); fi
  people=$((people + ${n:-0}))
done
printf 'climate %s, %s fields, %s days: %d of %d colonies survived, %.1f citizens left on average (%d s)\n' \
  "$CLIMATE" "$FIELDS" "$DAYS" "$survived" "$total" "$(echo "scale=1; $people / $total" | bc)" "$secs"

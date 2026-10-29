#!/bin/bash
# Runs the windowed screenshot tests in one go and lists the pictures.
#   tests/run_shots.sh [out_dir]          (needs a display: run it from the graphical session, or set DISPLAY=:1)
# Everything lands in out_dir (default /tmp/ousted_shots). Look at the PNGs afterwards.
GODOT=${GODOT:-/home/rmh/godot/Godot_v4.7.2-stable_linux.x86_64}
OUT=${1:-/tmp/ousted_shots}
export DISPLAY=${DISPLAY:-:1}
cd "$(dirname "$0")/.." || exit 1
mkdir -p "$OUT"
run() {   # run <scene> [args after --]
    local scene=$1; shift
    echo "== $scene"
    timeout 240 "$GODOT" --display-driver x11 --path . "res://tests/$scene.tscn" -- "$OUT" "$@" 2>&1 | grep -i "script error\|parse error\|X11 Display\|Invalid" | head -5
}
run m4_shot                      # M4 steps 4 to 8, rotation, staked roads, ? help, Accepts filter, Citizens panel, drought
run rotate_shot                  # four houses at each facing and a staked road beside a built one
run changelist_shot              # title screen with the changelist open
run title_shot 1                 # the title screen with the build id (a repeatable season)
run ui_extras_shot               # worker list, priority tag, idle tags
run ghost_shot                   # building ghosts: green, orange, red (one-tile field ghost: see m4_shot)
run gallery_shot blacksmith      # the blacksmith window (no smear)
run gallery_shot nodes 6         # hazel against berry bush and the other plants
run shrub_shot                   # berry bush, hazel and mushrooms side by side
run work_shot                    # work animations
run screenshot                   # dawn, noon, dusk, night (moon direction)
echo
ls -1 "$OUT"/*.png 2>/dev/null

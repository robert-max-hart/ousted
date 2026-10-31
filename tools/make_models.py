#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_models.py
#     Regenerates every model set that has a reduced version, both the full set and the reduced one
#     (the generators' `--low` option, written to assets/models/<set>_low): trees, plants (rocks, shrubs,
#     orchard trees) and crops. The game picks the set from Settings > Model detail.
#         python3 tools/make_models.py
#     then `godot --headless --path . --import`.
# ----------------------------------------------------------------
import os, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
for gen in ("make_trees.py", "make_plants.py", "make_crops.py"):
    for extra in ([], ["--low"]):
        out = subprocess.run([sys.executable, os.path.join(here, gen)] + extra, capture_output=True, text=True)
        print(gen, " ".join(extra), "->", out.stdout.strip().splitlines()[-1] if out.stdout.strip() else out.stderr.strip())

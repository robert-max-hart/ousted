# Ousted: notes for Claude

A colony management game in the style of Banished, built in **Godot 4.7.2** with the **GL Compatibility** renderer.
The focus is realistic agriculture, and there is no combat.

- `design_doc.md` is the user's original concept. Don't rewrite it.
- `docs/plan.md` is the expanded plan: system designs, architecture, milestones M1 to M8, open questions and prototype findings. **Read it before starting work.**

## Current status (handoff, 2026-10-23)

**M1, the core loop prototype, is done (first pass)** and committed:
- `1fd9c8d`: the M1 prototype and the expanded plan.
- `5446d3a`: the colour-temperature day/night cycle.

The work moved to a second workstation at this point.

What works: a heightmap terrain split into 32×32 chunks, which can be edited with raise, lower and flatten brushes. Building placement levels the ground under it automatically. Also working:
- the RTS camera
- the clock, seasons and weather (temperature, rain and snow)
- trees, rocks, iron ore and berry bushes, drawn efficiently in batches (MultiMesh)
- the Harvest tool, roads and the Demolish tool
- construction: clear the site, haul materials, then build
- six citizens with hunger, thirst, energy, warmth and health
- professions (Laborer, Builder, Farmer, Gatherer) with +/− counters
- crop fields (wheat and beans) with soil fertility, moisture and frost
- a HUD built in code

A headless run of one full in-game year had no errors: the colony harvests wheat once and survives winter.

### Decided
- **Terraforming cost (2026-10-23):** terraforming must require citizen labor, not be free and instant. Dirt is not a resource for now. The current terraform UI is chunky and needs fine-tuning later. The plan has this in M5, but the timing is not settled.

### Waiting on the user
These are the open questions from `docs/plan.md` §7. Ask before building anything that depends on them:
1. **Ageing.** A year is about 64 minutes at 1x. Should citizens age faster than the calendar, or should years be longer?
2. **Storage.** Keep the shared colony-wide stock (current), or give each storage building its own inventory?
3. **Crop speed.** Wheat gets one harvest a year because early spring is cold. Keep that, or tune for rotation within a year?

### Likely next steps (M2, Logistics & economy; see plan)
- Per-storage inventories and capacity, a granary, and food spoilage.
- Woodcutter, quarry and mine buildings, firewood for warmth, and tools.
- Fields sized by dragging instead of the fixed 6×6.
- Save and load, probably earlier rather than later.

## User preferences
- Lighting: day/night shows as a **colour-temperature shift, not darkness**. White by day, orange at dawn and dusk, cool blue at night, with night only slightly darker.
- Commit or push only when asked. The user has asked to commit after each finished change so far.
- Banished is a reference point, not a spec. Details recalled from memory may be inaccurate, so verify before copying a mechanic closely.

## Code conventions (match these)
- GDScript is **fully typed**, indented with **4 spaces** and **ends statements with semicolons**. Classes are declared as `class_name X extends Y;`.
- Each file starts with a header comment block (`# ---- / # Name / #  description`). Sections are separated with `# --------------------------------`.
- Data definitions are static dictionaries in `scripts/data/defs.gd` for now. The plan is to move them to `.tres` files later.
- The scene tree is built in code from `World._ready()`, and `scenes/main.tscn` is a single node.

## Architecture (short version)
- Autoloads: `GameClock` (time, speed, and hour/day/season signals), `Weather`, and `Stock` (colony inventory with reservations).
- `World` (`scripts/world/world.gd`) owns the terrain, the `NavGrid` (an AStarGrid2D wrapper), the per-cell occupancy arrays (`occupant`, `node_at`), soil fertility, all entities and the lighting. It's reachable anywhere as `World.instance`.
- Citizens (`Pawn`) run a `Task`, which is a list of steps (MOVE, WORK, ACT) with `on_cancel` and `on_end` callbacks. Tasks come from `JobManager.choose_task()` in this priority order: needs, then dropping off what they carry, then sleep at night, then their profession's work, then general labor, then idling.
- Clicking the terrain is handled by marching a ray through the heightmap (`Terrain.raycast`), with no physics colliders.

## Running and testing
Godot may not be on PATH. On the first workstation the binary was `/home/rmh/godot/Godot_v4.7.2-stable_linux.x86_64`, so check what it is on this machine.
```
godot --headless --path . --import                                   # after pulling, registers classes
godot --headless --path . --fixed-fps 60 res://tests/sim_soak.tscn   # fast-forward run with a daily colony report
godot --path . res://tests/screenshot.tscn -- <out_dir>              # windowed: dawn/noon/dusk/night PNGs
```
Run the soak test after any simulation change, and the screenshot test after visual changes (then view the PNGs).

## Gotchas learned so far
- **Freeing a building that a citizen's task callback still references** logs "Lambda capture was freed". To avoid it, `World.remove_building` ends every task whose `target` is that building before freeing it. Any new task that captures a Node in a callback must set `task.target` to that node.
- Don't write a multi-line lambda followed by another argument (`f(func(): ..., "x")`). Assign the lambda to a local variable first.
- In GL Compatibility, lighting saturates quickly. The sun is around 0.7 energy and ambient around 0.3, set in `LIGHT_KEYS` in `world.gd`, and fog is very light. Materials using vertex colours set `vertex_color_is_srgb = true`.
- On HUD controls with anchors, set the `offset_*` properties, not `position`. The bottom bar needs `grow_vertical = GROW_DIRECTION_BEGIN` or it ends up off-screen.
- `@warning_ignore("integer_division")` goes on the function, not on a variable inside it.
- Performance: about 45 fps at 1600×900 with shadows on an Intel UHD 620.

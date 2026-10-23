# Ousted: notes for Claude

A colony management game in the style of Banished, built in **Godot 4.7.2** with the **GL Compatibility** renderer.
The focus is realistic agriculture, and there is no combat.

- `design_doc.md` is the user's original concept. Don't rewrite it.
- `docs/plan.md` is the expanded plan: system designs, architecture, milestones M1 to M8, open questions and prototype findings. **Read it before starting work.**

## Current status (handoff, end of session 2026-10-23)

**M1, the core loop prototype, is done (first pass)** and committed:
- `3aaa51f`: the M1 prototype and the expanded plan.
- `c232d69`: the colour-temperature day/night cycle.

The work moved to a second workstation at this point. After that, this session also added (all committed):
- smoother terrain colours and shorelines (corner-blended colours with fine texture, depth-faded water mesh)
- gradual weather (`Weather.intensity` eases rain and snow in and out; a rain/snow mix between 0 and 3 C)
- right-drag camera pan (a right click without a drag still cancels the tool)
- **M2 (Logistics & economy) is mostly done**, see below.

M1 work: a heightmap terrain split into 32×32 chunks, which can be edited with raise, lower and flatten brushes. Building placement levels the ground under it automatically. Also working:
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
- **Storage (2026-10-23):** each storage building has its own inventory (and capacity), replacing the shared colony-wide stock. This is the first M2 task. A Granary (food only) is added, every storage building has player-set item filters, capacity is one total per building, workers stop gathering when storage is full and drop carried goods as ground piles, and a storage building can't be demolished until empty.
- **Crop speed (2026-10-23):** crops differ in speed, so there is no single rule. Fast crops (lettuce, radishes) give several harvests a year, slow ones (pumpkins) give one. Some crops are **multi-harvest per sowing**: they keep producing without replanting until they die off. This needs new crops and a per-crop attribute in `Defs.CROPS` (today only wheat and beans, both replant-per-harvest). The wheat/bean tuning is a per-crop matter now.
- **Ageing (2026-10-23):** hybrid. Citizens age faster than the calendar, at an adjustable rate (a setting). Under 5 is a baby (never works, never leaves the house), 5 to 17 is a child (school is their work, or real work if there is no school), 18 and over is an adult. A policy to allow or forbid child labor, with a happiness effect, is a nice-to-have. Schools have a capacity and need a teacher (a worker who staffs the building). A child's role is re-evaluated each time their task ends, with school taking priority, so nobody is locked into the workforce. This is M3 work.

### Waiting on the user
These are the open questions from `docs/plan.md` §7. Ask before building anything that depends on them:
None at the moment. The M3 ageing details are still open: the old-age curve numbers (decided in shape: see plan §7), the default ageing rate, and school capacity and teacher numbers (see `docs/plan.md` §7).

### M2 progress (Logistics & economy; see plan)
Done and committed: per-building inventories with capacity, Granary (food only), per-building item filters, ground piles when storage is full, demolish blocked until a storage building is empty, food spoilage (per food type, temperature and storage building scaled; 10x faster on the ground), drag-sized crop fields (2 to 16 cells a side, click for the default 6x6), and the **Woodcutter** (job building with a visible radius, Woodcutter profession, settings in the inspector: chop off/mature/all, plant, make firewood, and a production cap; trees now have a sapling stage that grows slowly, slower in winter, and needs water loosely; firewood only spoils when lying on the ground), and **house heating** (each house holds firewood, burns it below 15 C, 2 a day at 0 C, citizens stock it; cold houses give no warmth recovery and low warmth costs health; the Town Hall is always warm). Building settings use the `controls` schema in `Defs.BUILDINGS`, and any producing building should get a production cap control.

Next session: pick the next M2 item with the user (quarry and mine need their decisions on workers and placement; tools; save and load). M3 (population: ageing, school, experience) has design notes in `docs/plan.md` §3.5 and §7 but nothing built.

Still to do:
- Quarry and mine buildings (worker model and placement are **deferred by the user**; the Harvest designation tool stays for clearing).
- Tools (they raise work efficiency, never required).
- Save and load, probably earlier rather than later.

## User preferences
- Lighting: day/night shows as a **colour-temperature shift, not darkness**. White by day, orange at dawn and dusk, cool blue at night, with night only slightly darker.
- Commit or push only when asked, and **don't suggest commits** at the moment: the user said (2026-10-23) the prototype is early enough that frequent commits aren't needed. Ask first only if something risky is about to happen.
- Banished is a reference point, not a spec. Details recalled from memory may be inaccurate, so verify before copying a mechanic closely.

## Code conventions (match these)
- GDScript is **fully typed**, indented with **4 spaces** and **ends statements with semicolons**. Classes are declared as `class_name X extends Y;`.
- Each file starts with a header comment block (`# ---- / # Name / #  description`). Sections are separated with `# --------------------------------`.
- Data definitions are static dictionaries in `scripts/data/defs.gd` for now. The plan is to move them to `.tres` files later.
- The scene tree is built in code from `World._ready()`, and `scenes/main.tscn` is a single node.

## Architecture (short version)
- Autoloads: `GameClock` (time, speed, and hour/day/season signals), `Weather`, and `Stock` (read-only colony totals summed over storage buildings; goods live in `Building.stored`, with per-building reservations).
- `World` (`scripts/world/world.gd`) owns the terrain, the `NavGrid` (an AStarGrid2D wrapper), the per-cell occupancy arrays (`occupant`, `node_at`), soil fertility, all entities and the lighting. It's reachable anywhere as `World.instance`.
- Citizens (`Pawn`) run a `Task`, which is a list of steps (MOVE, WORK, ACT) with `on_cancel` and `on_end` callbacks. Tasks come from `JobManager.choose_task()` in this priority order: needs, then dropping off what they carry, then sleep at night, then their profession's work, then general labor, then idling.
- Clicking the terrain is handled by marching a ray through the heightmap (`Terrain.raycast`), with no physics colliders.

## Running and testing
Godot is not on PATH. On both workstations the binary is `/home/rmh/godot/Godot_v4.7.2-stable_linux.x86_64`.
```
godot --headless --path . --import                                   # after pulling, registers classes
godot --headless --path . --fixed-fps 60 res://tests/sim_soak.tscn   # fast-forward run with a daily colony report
godot --path . res://tests/screenshot.tscn -- <out_dir>              # windowed: dawn/noon/dusk/night PNGs
```
Run the soak test after any simulation change, and the screenshot test after visual changes (then view the PNGs).

## Gotchas learned so far
- **`godot --import` rewrites `project.godot`** and strips the `renderer/rendering_method="gl_compatibility"` line. Check `git diff project.godot` after any import and restore it with `git checkout project.godot` before committing.
- The soak test (`tests/sim_soak.gd`) runs only `DAYS = 6` by default, not a full year. Raise it for a year-long check.
- Git identity is set per repo (`robert-max-hart`). The history was rewritten once on 2026-10-23 to fix the old author on the first commits, so any older hashes are gone. There is no remote.
- **Freeing a building that a citizen's task callback still references** logs "Lambda capture was freed". To avoid it, `World.remove_building` ends every task whose `target` is that building before freeing it. Any new task that captures a Node in a callback must set `task.target` to that node.
- Don't write a multi-line lambda followed by another argument (`f(func(): ..., "x")`). Assign the lambda to a local variable first.
- In GL Compatibility, lighting saturates quickly. The sun is around 0.7 energy and ambient around 0.3, set in `LIGHT_KEYS` in `world.gd`, and fog is very light. Materials using vertex colours set `vertex_color_is_srgb = true`.
- On HUD controls with anchors, set the `offset_*` properties, not `position`. The bottom bar needs `grow_vertical = GROW_DIRECTION_BEGIN` or it ends up off-screen.
- `@warning_ignore("integer_division")` goes on the function, not on a variable inside it.
- Performance: about 45 fps at 1600×900 with shadows on an Intel UHD 620.

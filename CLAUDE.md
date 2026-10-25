# Ousted: notes for Claude

A colony management game in the style of Banished, built in **Godot 4.7.2** with the **GL Compatibility** renderer.
The focus is realistic agriculture, and there is no combat.

- `design_doc.md` is the user's original concept. Don't rewrite it.
- `docs/plan.md` is the expanded plan: system designs, architecture, milestones M1 to M8, open questions and prototype findings. **Read it before starting work.**

## Current status (handoff, 2026-10-25)

**M1 (core loop) and M2 (logistics and economy) are done, and M3 (population) has steps 1 to 3 built.** Committed up to M3 steps 1 and 2. **Step 3 (job experience and teacher quality, 2026-10-25) is built, tested and not yet committed.**

**Where to resume: the Policies panel** (a global list of colony-wide on/off rules, saved; child labor allow/forbid is its first rule, forbidden means children with no school idle at home), then step 4 families and births (babies' needs are frozen as a placeholder until then), then step 5 happiness, grief, orphans and the Graveyard. Nothing blocks the Policies panel.

- **M3 step 3, job experience (2026-10-25, built):** `Pawn.job_xp` (profession -> bonus, saved; old saves load with none). `Task.job` marks which profession a task's work earns and uses: building, farming, harvesting (by resource: trees woodcutter, iron and stone miner, the rest gatherer), forging (by the building's profession), digging, planting trees and teaching. Hauling, fetching and the like earn none. In the WORK step `Pawn._run_task` multiplies speed by `1 + experience(job)` and calls `practise(job, dh)`. Gain: `Defs.job_xp_gain`, the same shape and starting constants as schooling (`JOB_XP_RATE` 0.0012, `JOB_XP_HALF` 0.1), about 470 work hours for +25%, which is probably too fast for a "long career" and is a number to tune. `JobManager._most_experienced_laborer` and `_least_experienced` now pick by experience (ties by list order).
- **Teacher quality (decided 2026-10-25, built):** the teacher's teaching experience plus their own general experience, over `Defs.TEACHER_VETERAN_XP` (0.4, my pick), scales a bonus of up to +50% (`Defs.teacher_multiplier`). The teacher sets `Building.teaching_mult` while teaching and pupils' `learn(dh, mult)` uses it. The School inspector shows it. Tests: `tests/experience.tscn`.

Earlier history:
- `3aaa51f`: the M1 prototype and the expanded plan. `c232d69`: the colour-temperature day/night cycle.
- Then terrain colours, gradual weather, right-drag pan, and the first half of M2 (storage, spoilage, woodcutter, heating).
- Then the second half of M2: mine, coal, tools and blacksmith, building upgrades, input inventories, save and load.

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

- **Tools (2026-10-23, built):** made in a Blacksmith (3x3, 2 Blacksmith slots). Generic tools are items stored in storage; a pawn with no tool fetches the best one available (steel > iron > wooden) and keeps it until it breaks. Wooden: 1 wood, +10% work speed, 100 uses. Iron: 1 wood + 1 iron, +25%, 200. Steel: 1 wood + 1 iron + 1 coal, +50%, 500. A "use" is one game hour in a work step (not for sleep, eat, drink, warm, idle). No upgrade swaps and no returning worn tools; a tool is lost if its owner dies. The smith tries steel, then iron, then wooden, each with a toggle and a stock cap (default 5). Coal is mined at the Mine (see below); the soak test also seeds 6 coal. Smith craft times 2, 1 and 0.5 hours are my picks, not user-confirmed.
- **Input inventory (2026-10-23, built for the Blacksmith only):** `inputs` in a building def is an input buffer (item -> target level) kept separate from `stored`, so it doesn't count toward `Stock`. `recipes` define what is made. The building's own workers and idle laborers fetch inputs (`_stock_inputs_task`). Demolishing returns inputs to storage. The **Woodcutter is migrated too** (2026-10-23): it keeps up to 6 wood as an input, splits 2 at a time into firewood (1 wood makes 5) with the same generic `_forge_task` / `_stock_inputs_task`, and its storage accepts firewood only. A recipe can set `yield`, `batch` and a custom `toggle` id. Chopped wood now goes to ordinary storage and is fetched back as input. Target levels are fixed in the def, not player-adjustable.

- **Death and profession targets (2026-10-23, built):** `World.kill_pawn(p, cause, at_home)`: the citizen's carried goods drop as a ground pile where they died (tools are lost), the death is appended to `World.death_log` (saved; the last 5 show in the Town Hall inspector), and `JobManager.reconcile()` refills their profession. A natural death (old age, once ageing exists) should pass `at_home = true` so it happens in bed. Bodies simply vanish for now. **M3 step 5 should add the Banished-style Graveyard**: a building with free plots "stores" a body, which softens the happiness penalty of a death (grief and orphans are also step 5). The HUD profession +/- buttons now change a **target** per profession (`JobManager.targets`, saved); `reconcile()` (hourly, and on a change, death or load) moves citizens between the Laborer pool and professions to match, showing "Farmer: 1 (want 2)" when the pool can't fill it. It picks by experience (see M3 step 3). **Tests that set `pawn.profession` directly must call `world.jobs.sync_targets()`**, or the next reconcile undoes it.

- **M3 step 1, ages and life stages (2026-10-23, built):** `Pawn.age` is a float in citizen years, advancing 1 year per `Defs.ageing_days_per_year` calendar days (default 4, saved with the game, no settings UI yet). Stages: baby under 5, child 5 to 17, adult from 18 (`is_baby`, `is_adult`, `stage_name`). Babies never work and stay indoors (`JobManager._baby_task`) and their needs hold steady, as if the household feeds them (revisit with families in step 4). Children are laborers only: `reconcile()` never drafts them, they work at `Defs.CHILD_EFFICIENCY` 0.5 (a placeholder until schools in step 2). Work speed is `(1 + tool bonus) * Pawn.work_efficiency()`. Old age: efficiency curve `OLD_AGE_EFFICIENCY` (1.0 at 60, 0.95 at 75, 0.4 at 90) and a death chance per citizen year `OLD_AGE_DEATH_PER_YEAR` (2% at 60, 5% at 70, 10% at 75, 20% at 85, 35% at 90, 60% at 100), rolled every frame as a per-hour chance. Old-age deaths pass `at_home = true`. School capacity 12 with 1 teacher is the agreed default for step 2. Tests: `tests/life_stages.tscn` (curves, stages, ageing rate, baby, child, old-age death).

- **M3 step 2, school and teacher (2026-10-23, built):** a 4x4 **School** (`school_capacity` 12, `worker_slots` 1, Teacher profession, `Defs.SCHOOL_START`/`SCHOOL_END` 8:00 to 16:00) and a **Teacher** profession (a target like the others, adults only). The teacher heads over half an hour early (`TEACHER_EARLY`) and teaches while there are children (`Building.teaching`). A child (5 to 17) picks `_school_task` right after needs, carried goods and sleep, ahead of child labor, if it is school hours, the colony has a teacher and a school has a free seat (`Building.attendees`). It waits up to 1.5 hours for a teacher and then avoids that school for 3 hours. It studies until 16:00, the teacher leaves, or a need interrupts it. Studying raises `Pawn.general_xp`, a work speed bonus with diminishing gains (`Defs.general_xp_gain`: full schooling from 5 to 17 gives about +23%), and `work_efficiency()` multiplies by `1 + general_xp`. During school hours a child or teacher carrying goods delivers them instead of topping up the load (`_school_calls`), because long foraging chains kept children from school. As decided, school does **not** interrupt a child's current labor task, only the next pick. Not built: the child labor policy and a forbid-child-labor rule. The build bar is now an `HFlowContainer` that wraps, and the event log tracks the toolbar's height. Tests: `tests/school.tscn`.

### Waiting on the user
Nothing is pending.

### M2 progress (Logistics & economy; see plan)
Done and committed: per-building inventories with capacity, Granary (food only), per-building item filters, ground piles when storage is full, demolish blocked until a storage building is empty, food spoilage (per food type, temperature and storage building scaled; 10x faster on the ground), drag-sized crop fields (2 to 16 cells a side, click for the default 6x6), and the **Woodcutter** (job building with a visible radius, Woodcutter profession, settings in the inspector: chop off/mature/all, plant, make firewood, and a production cap; trees now have a sapling stage that grows slowly, slower in winter, and needs water loosely; firewood only spoils when lying on the ground), and **house heating** (each house holds firewood, burns it below 15 C, 2 a day at 0 C, citizens stock it; cold houses give no warmth recovery and low warmth costs health; the Town Hall is always warm). Building settings use the `controls` schema in `Defs.BUILDINGS`, and any producing building should get a production cap control.

M2 is complete (see the sections below). M3 is in progress, see the status above.

M2 items, all done:
- ~~Quarry and mine~~ done (2026-10-23): one large 5x5 "Mine" with no storage. Miners dig iron first, then stone once iron hits its cap (both caps are settings), carry the ore to a storage building, and are 2.5x slower per unit than surface harvesting (`mine_hours` in the def). Miner profession, 3 slots per mine; with no mine to work at, miners gather loose rock and iron on the surface. Unlimited output, placement is free (no vein needed). The Harvest designation tool stays for clearing.
- **Coal (2026-10-23, built):** mined at the Mine, order iron, coal, stone (each until its cap; coal cap defaults to 30). Coal takes 6 labor-hours per unit (twice iron) and miners without an iron or steel tool (bonus under 25%) dig it at a quarter of the speed (`needs_tool`, `HARD_ORE_UNTOOLED_SPEED`). Mining progress is stored on the mine (`dig_progress`) so interrupted units aren't lost. Coal is also house fuel worth 2 firewood (`heat` in `Defs.ITEMS`; house fuel is counted in firewood-equivalents), with a per-house "Burn: Firewood / Coal / Either" setting (default Firewood so coal stays available for steel). Coal is locked until the Mine's **Deep Shafts** upgrade is built (`locked_until` in the def, `Building.item_unlocked`).
- **Upgrade system (2026-10-23, built):** `upgrades` in a building def (id -> name, cost, work, desc, optional `excludes` and `requires` lists), so a building can have several and some can be mutually exclusive. The inspector shows an "Upgrades:" section: a button per upgrade (disabled with the reason when blocked, a Cancel button while building). One upgrade is built at a time and the building keeps working. It reuses the construction pipeline: while `Building.upgrading` is set, `delivered`/`incoming`/`work_done` belong to the upgrade project (the building's own materials are set aside in `_base_spent`), `cost()` and `work_required()` return the upgrade's, `is_site()` is true, and the existing haul and build tasks do the rest. Cancelling refunds the delivered materials in full; demolishing refunds 50% of everything (`all_delivered()`). Only the Mine has an upgrade so far; the exclusion and prerequisite rules are exercised in `tests/sim_soak.gd` on a copy of the def, not in the real data. The HUD buttons are untested visually.
- ~~Tools~~ done (see Decided).
- ~~Save and load~~ done (2026-10-23), see below.

### Save and load (built 2026-10-23)
`SaveGame` (`scripts/world/save_game.gd`, static functions) writes `World.serialize()` as a ZSTD-compressed Variant dictionary with a `version` (currently 1) to `user://saves/<slot>.sav`. F5 or the Save button writes the `quicksave` slot, F9 or the Load button loads it, and an `autosave` slot is written at each season change (`SaveGame.autosave_enabled` turns that off, and the tests do). Loading builds a fresh `World` from the data between frames (`World.pending_load`), after restoring the `GameClock` and `Weather` autoloads. What is saved: terrain heights and overlay, soil fertility, wetness, every resource node, building (inventories, inputs, settings, filters, upgrades, mining progress, construction state, field plots), ground pile, citizen (needs, profession, tool and wear, carried goods, home, look seed), camera, clock, weather and the RNG state. **Citizens' tasks are not saved**: they restart idle and pick new work, so all reservations and incoming deliveries start empty. Goods a citizen was carrying are kept and delivered. When you add state, put it in the matching `to_dict`/`restore_dict` (Building, Field, Pawn, ResourceNode, GroundPile) or `World.serialize`, and bump `VERSION` only for changes an old save can't load (new keys should be read with defaults). `tests/save_load.tscn` checks that a save loads back into identical data (taken mid-afternoon with an upgrade in progress) and that the game runs on; `tests/save_load_shot.tscn` is the windowed version. Not built: a load menu or multiple named slots (M8 is for that), and map seeds or settings.

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
- **File size (decided 2026-10-25): keep every script under 1000 lines.** Task making is split by theme: `JobManager` (core, targets, logistics, construction, gathering, farming, idle) extends `TaskBase` (shared: `world`, `count`, `workers_at`, `in_radius`, `harvest_node_task`), and holds `needs` (`NeedsTasks`), `school` (`SchoolTasks`) and `production` (`ProductionTasks`: woodcutter, tools, inputs, blacksmith, mining), which also extend `TaskBase`. They must not hold a reference back to `JobManager`: RefCounted cycles leak ("resources still in use at exit"). The sky, lighting, water and precipitation moved from `World` into `WorldVisuals` (`world.visuals`, a child node). Next candidates if files grow: `building.gd`, `hud.gd`, and `World`'s save/restore and building code.
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
- **Screenshot test with no Wayland session** (an ssh or tty shell): run it as `DISPLAY=:1 godot --display-driver x11 --path . res://tests/screenshot.tscn -- <out_dir>` (an X server was on `:1` on this workstation). It now places a finished Mine and Blacksmith and shows their inspectors at the noon and dusk shots.
- The inspector panel scrolls when it is taller than the screen (`_info_scroll` in `hud.gd`).
- **`godot --import` rewrites `project.godot`** and strips the `renderer/rendering_method="gl_compatibility"` line. Check `git diff project.godot` after any import and restore it with `git checkout project.godot` before committing.
- The soak test (`tests/sim_soak.gd`) runs only `DAYS = 6` by default, not a full year. Raise it for a year-long check.
- Git identity is set per repo (`robert-max-hart`). The history was rewritten once on 2026-10-23 to fix the old author on the first commits, so any older hashes are gone. There is no remote.
- **Freeing a building that a citizen's task callback still references** logs "Lambda capture was freed". To avoid it, `World.remove_building` ends every task whose `target` is that building before freeing it. Any new task that captures a Node in a callback must set `task.target` to that node.
- Don't write a multi-line lambda followed by another argument (`f(func(): ..., "x")`). Assign the lambda to a local variable first.
- In GL Compatibility, lighting saturates quickly. The sun is around 0.7 energy and ambient around 0.3, set in `LIGHT_KEYS` in `world.gd`, and fog is very light. Materials using vertex colours set `vertex_color_is_srgb = true`.
- On HUD controls with anchors, set the `offset_*` properties, not `position`. The bottom bar needs `grow_vertical = GROW_DIRECTION_BEGIN` or it ends up off-screen.
- `@warning_ignore("integer_division")` goes on the function, not on a variable inside it.
- Performance: about 45 fps at 1600×900 with shadows on an Intel UHD 620.

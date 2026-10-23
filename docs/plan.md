# Ousted — Expanded Plan

This builds on `design_doc.md`. It covers the system designs, the technical architecture, the
milestone roadmap and the open questions. The doc should change as the prototype teaches us things.

---

## 1. Pillars

1. **Agriculture is the heart of the game.** Every other system (weather, seasons, labor, trade)
   should matter *because* it affects whether the colony eats.
2. **Indirect control.** The player places things and sets priorities. Citizens decide what to do.
3. **Readable simulation.** You can click anything and it tells you *why* (why a crop is slow,
   why someone is cold, why a house isn't built yet).
4. **The land is a resource.** Terrain shape, soil, water and slope all limit what you can build.
   Reshaping it takes effort.
5. **No combat.** The enemies are winter, drought, pests, famine and old age.

---

## 2. Core loop

```
 place buildings / fields / roads ──► citizens haul, build, farm, gather
         ▲                                         │
         │                                         ▼
 adjust jobs, crops, trade  ◄── stockpile grows/shrinks ◄── seasons & weather
```

A year is the main pacing unit. Spring is for planting, summer for growing and building, autumn
for harvest and stocking up, and winter is the test.

---

## 3. Systems

### 3.1 Time & calendar
- Real-time with pause and speeds of 1x, 2x and 5x (maybe 10x later).
- Prototype values (all tunable in `GameClock`): **1 game hour = 5 s at 1x**, 24 h days,
  **8 days per season**, 4 seasons, so a year is 32 days (about 64 min at 1x).
- Day and night: citizens work in daylight (06:00 to 21:00) and sleep at night.
- **Open question:** citizen ageing is decoupled from the calendar (see §7).

### 3.2 Weather & seasons
- **Temperature** follows a smooth seasonal curve, a daily curve and a random offset per day.
- **Rain** starts and stops on per-hour chances that vary by season. It becomes snow below 0 °C.
- Gameplay effects:
  - Crop growth needs the temperature above the crop's minimum. Frost kills tender crops.
  - Rain raises soil moisture and hot dry days lower it.
  - Cold drains citizens' warmth outdoors.
  - Later: snow slows walking, droughts and storms damage crops, and pest outbreaks follow warm wet spells.

### 3.3 Terrain
- Heightmap grid (128×128 cells at 1 m in the prototype, aiming for 256×256), rendered as a
  chunked mesh (32×32 cells per chunk) so edits only rebuild nearby chunks.
- Cells have a surface (grass, sand, rock, road, tilled) and a soil **fertility** value.
- Water level plane. Cells under water cannot be built on and block walking.
- **Manipulation:**
  - Placing a building automatically flattens its footprint (only up to a maximum slope).
  - Raise, lower and flatten brush tools (instant in the prototype; **decided:** they become labor
    jobs that cost worker hours. Whether dirt and stone are moved as resources is not decided).
  - Later: dig irrigation channels connected to water, which raise the moisture of nearby fields.

### 3.4 Buildings
- Data-driven definitions: footprint, cost (wood/stone/iron), labor hours and function flags
  (storage, water, beds, field…).
- Lifecycle: **placed → site cleared → materials hauled → built by laborers → complete**.
- Placing over trees or rocks automatically marks them for clearing.
- Prototype set: Town Hall (start building: storage, water, shelter), House, Well, Stockpile, Crop Field.
- Later: Woodcutter, Forester, Quarry, Mine, Blacksmith, Granary/Barn, Root Cellar, Market/Trading
  Post, Herbalist (health), Tavern (happiness), School, Cemetery, Orchard, Pasture/Barn (livestock).

### 3.5 Citizens (pawns)
- **Needs** (0 to 1): hunger, thirst, energy, warmth, health. Happiness comes later and is
  derived from needs, housing, food variety and so on.
- A need running out damages health, and zero health means death. Each death has a cause that
  is reported to the player.
- **Life cycle (Milestone 3):** child → adult → elder. Couples move into a house together, and
  a family in a house can have children. Death from old age.
- **Decisions:** each pawn picks its next task from: urgent needs → hand off carried goods →
  sleep at night → profession work → general labor → idle.

### 3.6 Jobs & labor
- **Professions** (Banished-style +/− counters in the HUD): Laborer, Builder, Farmer, Gatherer.
  Later: Woodcutter, Stonecutter, Miner, Smith, Trader, Herbalist…
- Each profession has a priority list of task types and falls back to general labor when it
  has nothing to do (farmers help haul in winter).
- **Task model:** a task is a short script of steps (`move → act → work → act`) with cleanup
  callbacks. Reservations (stock, resource nodes, field plots, building slots) stop two pawns
  from doing the same thing.
- **Logistics:** goods are stored at storage buildings. The stock is a colony-wide count in the
  prototype, but pawns still physically walk goods to and from the nearest storage. Later: each
  storage building holds its own inventory with a capacity.

### 3.7 Agriculture (the deep system)
| Mechanic | Prototype | Later |
|---|---|---|
| Crops | Wheat (heavy feeder), Beans (restore nitrogen) | Barley, potatoes, cabbage, flax (fibre), orchards, vegetables, herbs |
| Planting window | Spring and summer, and above the crop's minimum temperature | Per-crop sowing calendars, winter wheat |
| Growth | Hourly. Speed comes from temperature and moisture | Sunlight hours, crop stress states |
| Frost | Kills unripe crops below their frost temperature, and rots ripe crops left into winter | Frost warnings, covered beds |
| Soil fertility | Stored per terrain cell. Harvest changes it according to the crop. Fallow plots slowly recover | Manure/compost, overlay view, nutrients (N/P/K-lite) |
| Crop rotation | Emerges from fertility (beans restore what wheat drains) | Rotation planner per field, bonuses for rotations |
| Water | Per-plot moisture. Rain adds, heat removes. Plots near water stay moist | Irrigation channels, buckets from wells, drought |
| Pests | — | Infestations that spread between plots of the same crop. Countered by rotation, crop diversity and a "pest control" job |
| Seeds | Free | Keep part of the harvest as seed for next year |
| Livestock | — | Pastures, manure for fertility |

Fields are player-placed rectangles (fixed 6×6 in the prototype, drag-sized later). The player picks the crop per field.

### 3.8 Resources & production
- Raw resources: wood (trees), stone (rocks), iron (ore deposits), food (forage, farms), water (wells).
- Later chains: wood → firewood (warmth), iron + wood → tools (work speed), flax → linen →
  clothing (warmth), wheat → flour → bread (better nutrition).
- Food spoils over time unless stored in a granary or cellar.

### 3.9 Trade & barter
- A Trading Post. Merchants arrive by river or road a few times per season with randomized wants and offers.
- Barter uses item values. Luxury goods (TBD: wool, honey, pottery, spirits…) are mostly for trading.
- Merchants can bring new seed types and livestock, which ties trade back into agriculture.

### 3.10 UI
- Top bar: date, time, weather, key resources, population, speed controls.
- Bottom bar: tools (select, harvest, road, terraform, demolish) and the build menu.
- Left: profession counters and an event log. Right: inspector for the selected object.
- Later: overlays (fertility, moisture, happiness), a ledger with graphs, and notifications.

---

## 4. Technical architecture (prototype)

```
scenes/main.tscn          → World (root, builds everything in code for now)
scripts/autoload/
  game_clock.gd           GameClock — time, calendar, speed, hour/day/season signals
  weather.gd              Weather   — temperature, rain/snow
  stock.gd                Stock     — colony inventory with reservations
scripts/data/defs.gd      Defs      — items, buildings, crops, resource nodes (static data)
scripts/world/
  world.gd                World     — owns terrain, nav, entities, occupancy, lighting
  terrain.gd              Terrain   — heightmap, chunked mesh, overlays, analytic ray picking
  nav_grid.gd             NavGrid   — AStarGrid2D wrapper (water/buildings solid, roads cheap)
  resource_renderer.gd    MultiMesh rendering of trees, rocks, bushes
scripts/entities/
  building.gd, field.gd   Buildings and crop fields
  resource_node.gd        Data object for trees, rocks, bushes, ore
  pawn.gd                 Citizen: needs, movement, task execution
scripts/ai/
  task.gd                 Step-scripted task
  job_manager.gd          Task selection, professions
scripts/ui/
  rts_camera.gd, player_tools.gd, hud.gd
tests/
  sim_soak.tscn           Headless fast-forward run with a daily colony report
  screenshot.tscn         Windowed run that saves screenshots (path passed after --)
```

Running the tests:
```
godot --headless --path . --fixed-fps 60 res://tests/sim_soak.tscn
godot --path . res://tests/screenshot.tscn -- /some/output/dir
```

Decisions and why:
- **Grid pathfinding (AStarGrid2D)** instead of NavigationServer, because terrain and buildings
  change all the time and a grid is cheap to update cell by cell.
- **Analytic terrain ray picking** instead of physics colliders, so a terrain edit never has to
  rebuild a collision shape.
- **MultiMesh for nature** (thousands of trees) so draw calls stay low with GL Compatibility.
- **Static dictionaries for data** to make early iteration fast. Moving to custom `Resource` (`.tres`)
  definitions is planned once the data settles, so it can be edited in the inspector.

---

## 5. Milestones

| # | Name | Contents |
|---|---|---|
| **M1** | **Core loop prototype** *(built: first pass)* | Terrain gen and editing, camera, clock/seasons/day-night, weather, trees/rocks/bushes, harvest designation, roads, construction with hauling, pawns with needs, professions, basic farming (wheat/beans, fertility, moisture, frost), HUD |
| M2 | Logistics & economy | Per-storage inventories and capacity, granary/spoilage, woodcutter/quarry/mine buildings, firewood and warmth, tools, field drag-sizing |
| M3 | Population | Ageing, families, births, children and education, deaths from old age, happiness, homelessness effects |
| M4 | Agriculture depth | More crops, sowing calendars, seeds, pests, irrigation channels, fertility overlay, orchards, livestock and manure |
| M5 | Terrain as labor | Terraforming as worker jobs, dirt and stone moved, nicer terrain shader (texture splat, snow) |
| M6 | Trade | Trading post, merchants, barter UI, luxury goods |
| M7 | Content & art pass | Real models and animation, audio, UI theme |
| M8 | Meta | Save and load, map seeds and settings, scenarios and difficulty, tutorial |

Save and load should probably move earlier (M2/M3) once state shapes stabilise, because it gets harder to add the longer it waits.

---

## 6. Prototype controls (M1)

| Input | Action |
|---|---|
| WASD / arrows | Pan camera |
| Q / E, middle-drag | Rotate (and tilt) camera |
| Mouse wheel | Zoom |
| Space, 1/2/3 | Pause, game speed |
| LMB | Select / use tool (drag for areas) |
| RMB / Esc | Cancel tool, deselect |
| R | Rotate building footprint |

---

## 7. Open questions

1. **Ageing vs calendar:** at 64 minutes per year, a 60-year life is far too long. Options: age
   faster than the calendar (Banished-style), or make years longer and lives shorter.
2. **Map size and scale:** 128 m is enough for a prototype. A full game probably wants 256–512 m
   with chunk streaming or LOD.
3. **Storage model:** colony-wide (simple, current) or per-building physical stock (deeper logistics)?
4. ~~**Terraforming cost**~~ **Decided (2026-10-23):** terraforming requires citizen labor (not
   free and instant). Dirt is not a resource, for now. The current brush UI is too chunky and needs
   fine-tuning later. Whether this lands in M5 as planned or earlier is not decided.
5. **Art direction:** low-poly stylised (it fits the procedural approach) or something more realistic?
6. **Failure state:** does the game end when everyone dies, or are there "settler wave" recovery options?

---

## 8. M1 prototype notes (findings so far)

- A one-year soak run: the colony builds houses, a well and fields, gets one wheat harvest
  (planted early spring, ripe at the start of autumn) and gets through winter on stored food.
- Wheat ripens slowly because early spring is cold (around 3 °C mean). One harvest per year fits
  "realistic", but bean/wheat rotation in a single year isn't possible yet. This is a tuning question.
- Spring frosts can kill early plantings, and farmers plant as soon as the daily mean is above
  the crop minimum. Later: let the player set a planting date or a risk tolerance per field.
- About 45 fps on integrated graphics (UHD 620) at 1600×900 with shadows.
- Known simplifications: colony-wide stock, free and instant terraforming, fixed 6×6 fields,
  no seeds, no ageing or births, placeholder primitive art.

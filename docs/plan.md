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
- Citizen ageing is decoupled from the calendar: citizens age faster, at an adjustable rate (see §7).

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
- **Death (decided 2026-10-23):** carried goods drop as a pile, the tool is lost, old-age deaths happen at home in bed, and bodies vanish for now. A Banished-style Graveyard (a building with openings that "stores" bodies and reduces the happiness penalty) comes with M3's happiness work. Professions are player *targets* that the game keeps filled from the laborer pool.
- **Policies panel (built 2026-10-25, see CLAUDE.md):** a global panel of colony-wide rules the player turns on or off, saved with the game. The child labor allow/forbid rule from §7 lives there. A forbidden rule sends children with no school home to idle.
- **Families and births (decided 2026-10-25, M3 step 4, built):**
  - **Pairing:** automatic. Two unpartnered adults (18+) within 10 years of each other can pair, with a daily chance. No sex is tracked: a pair is just two citizens, and births ignore sex. A pair has a fertility window by age (18 to 45 since 2026-10-26, `FERTILE_FROM` and `FERTILE_TO`).
  - **Housing:** a standard house holds 6 residents (2 adults and 4 children for a family, but 6 unrelated adults can share). A pair does not need its own house to form. For a **birth**, the pair's house needs at least one free slot. No hard cap on family size: housing limits it. Birth rate policies are a later idea.
  - **Births:** per-day chance for a fertile pair, up if food is plentiful and the house is warm, down when the colony is starving. Short fixed pregnancy of a few game days, and the pregnant parent works as normal.
  - **Spreading out (2026-10-26):** the homeless take the house with room that is nearest after counting each resident as 10 cells farther away (`HOUSE_CROWD_COST`), so houses fill evenly. A couple in a full house moves together to a house with two free beds, unless a child of theirs lives there. Without this, six settlers fill one house and no baby is ever born. Starting settlers are 18 to 32 (not 40) so their fertile years last. Job experience rate halved (`JOB_XP_RATE` 0.0006): about +10% in the first game year and +30% over a 5-year career.
  - **Graveyard rules (2026-10-26):** a graveyard can't be demolished while any grave is in use. Its **Crematorium** upgrade (40 wood, 60 stone, 10 iron, 60 work-hours) adds a "Cremate to keep free" setting (default off): each day the oldest graves are burned until that many squares are free, one coal per body, from a coal buffer of 4 that citizens fill only while the setting is on.
  - **Shack cleanup (2026-10-26):** policy "Clear empty shacks" (`clear_shacks`, default off) pulls down finished shacks nobody lives in. Shacks are meant to be a nuisance the player deals with, so it is the player's choice.
  - **Ledger and history (2026-10-26, first version built):** `World.ledger` (`scripts/world/ledger.gd`) records from the first day, whether or not Governance is built: one sample per day (population by stage, food, firewood, average happiness, births and deaths that day) and every event-log message as a permanent history (capped at 500 events and 1600 days). Viewing needs Governance: the Town Hall inspector has a Ledger button (disabled with a tooltip until then) that opens a panel with two tabs, Graphs (population, food, happiness, births and deaths per 8 days) and History (newest first). Not built: hover values, a census, other series, filtering history to major events.
  - **Babies:** have real needs, but need half the food of a child or adult. Happiness for babies is left to step 5. Parents spend some time on the baby (such as feeding): a recurring care task, not full-time. Babies stay indoors.
  - **Orphans:** children with no living parent move into any house with a free slot. The Town Hall never houses anyone. An orphanage or boarding house for children is a later building. Homelessness rules are to be discussed later.
  - **Widowed:** the survivor stays in the house and can pair again after a delay.
  - **UI:** the pawn inspector shows Partner and Children, the house inspector lists residents.
- **Happiness, grief and the Graveyard (decided 2026-10-25, M3 step 5, built):**
  - **Happiness** is a stored value per citizen that moves slowly toward a target made of named factors the inspector lists: needs, home (and a cold house), food variety, grief, child labor, a hungry baby in the house. Babies have no happiness. Consequences: below a threshold work is a little slower, very low for a long time and the citizen leaves the colony, happy parents raise the birth chance a little.
  - **Child labor** costs everyone happiness ("our children have to work is depressing"), adults less than children, scaled by how many children are working. It applies only while the policy is on.
  - **Grief:** a death gives the partner, children and parents a large penalty that fades over days, siblings less, and the whole colony a small one. Orphans carry theirs. A buried body softens it.
  - **Bodies show up** where the citizen died (in the house for old age). A family member carries it preferably (they get first call for a while), else any laborer. Burial puts a headstone in a free plot of a Graveyard. With no free plot the body lies there for some days and then vanishes, and the grief stays at full.
  - **Graveyard:** sized by dragging like a crop field, each cell one grave. Graves decompose and free their cell after 10 calendar years (Banished took about 20, which felt too slow). A faster way to free space is to be looked at later.
  - **Homelessness** is the next topic after this step.
- **Homelessness (decided 2026-10-25, M3 step 6, built):**
  - **The Town Hall shelters no one** (no beds, never a fallback). It keeps its storage and well. **PINNED, to discuss:** what the Town Hall becomes. Ideally the base version does almost nothing, and it gains upgrades later or comes with some depending on the starting difficulty.
  - **Shacks (the Tropico idea):** a homeless citizen gets a shack, a 2x2 two-bed building that is very quick to build (1 work-hour, 3 wood), and is **lost entirely when demolished (no refund)**. It carries the homeless mood penalty and warms a little, much less than a house. Shacks are placed automatically (policy "Homeless build shacks", default on) after a few hours of homelessness, a shack with room is reused first (two share one), and no new shack goes up while the houses under construction have enough beds for everyone still homeless (otherwise one does), and a shack dweller moves into a real house as soon as one has room (the shack stays until demolished).
  - **Without any bed:** sleeping outdoors restores energy at half speed, warmth falls as for anyone outside, and the "No home" penalty grows with the days spent homeless (from 15% to 30% over 10 days), plus a small penalty for sleeping in the cold.
  - **Homeless babies and children** get the next free house slot first, and any adult may care for a homeless baby. A HUD line shows how many are homeless.
- **Town Hall (decided 2026-10-25, built):**
  - **Base is only the well.** Everything else is an upgrade, built like the Mine's (materials only). An upgrade only **unlocks** a feature, not how it is reached.
  - **Upgrades:** storage (tier 1), more storage (tier 2, after tier 1), heating (a heated place to warm up, no sleeping or housing: the Town Hall never houses anyone), and **governance**, which unlocks the Policies panel and later the ledger and history.
  - **Starting difficulty sets what it comes with:** hard is the bare well, normal is well plus storage tier 1, easy is both storage tiers plus heating. (The difficulty setting itself is M6; the data can be written now.)
  - **Unique, but never lost for good:** only one at a time, and if it is lost the player can build a new one. The player can also move it. A new one costs 30 wood and 10 stone and starts bare (the unlocks belong to the building). **Relocating** is on every building that can move (not fields, graveyards, shacks or carts): half the build cost and work for a new one at a chosen spot, the old one keeps working and then goes with no refund, and settings, filters, upgrades, fuel, inputs and residents carry over. Storage buildings must be emptied first.
  - **Hard-start supply cart:** the starting goods go into the Town Hall's store room as far as it goes and the rest into a cart beside it, which takes nothing new and vanishes when emptied (as in Banished).
- **Teacher quality (decided 2026-10-25, built):** a teacher's teaching-job experience plus their own general experience raises how fast pupils gain general experience, up to 1.5x for a veteran.
- **Decisions:** each pawn picks its next task from: urgent needs → hand off carried goods →
  sleep at night → profession work → general labor → idle.

- **Experience (M3; built 2026-10-25 as general experience from school and per-job experience):** each pawn has a general experience value that speeds up all
  work, plus a per-job experience (one per job type or job building) that speeds up that job only.
  Doing a job raises its experience and school raises the general value. Pawns have an age and
  nothing else of this kind today. Work speed is currently the same for everyone.
  Decided (2026-10-23): experience never decays; job-specific experience is earned at any age
  (including children doing child labor); gains get harder the higher the value (logarithmic or
  diminishing returns), for both general and job-specific experience.
  Decided (2026-10-23): the HUD profession +/- counters pick by experience. Adding takes the Laborer
  with the most experience in that job. Removing takes the member with the least. Ties fall back to
  list order. Experience is stored per pawn per job type, so reassigning loses nothing. A way to
  assign specific citizens in the inspector is a possible later addition.
  Idea (later, not scheduled): a college-style building where adults earn general experience, as
  something for idle citizens to do. It has much lower priority than school, so it only takes pawns
  who would otherwise idle, and it may differ from school in other ways (capacity, teacher
  requirement, cost, effect size). Details not decided.

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

#### Woodcutter (decided 2026-10-23)
- A building and a job (new Woodcutter profession, +/- counter, 2 worker slots). It works inside a
  visible radius (15 cells) and has three toggleable jobs: **chop** (setting: off, mature trees only,
  or all trees), **plant** trees, and **convert** wood to firewood. Priority is chop, convert, plant.
- Trees have a sapling stage and grow all year, slower in winter. They need water, but far less
  strictly than crops. Planting is allowed all year.
- It is also storage for wood and firewood (120 units, accepts only those).
- Firewood: 1 wood makes 5 firewood, with an adjustable production cap. If the building has no wood
  to split, workers haul wood in from other storage. Houses will burn firewood for warmth.
- **Heating (decided and built 2026-10-23):** each house holds its own firewood (40) and burns it only when
  it is below 15 C, faster the colder it is (2 a day at 0 C), only while someone lives there. Laborers and
  woodcutters keep houses stocked to a per-house target. Without firewood the house is cold: residents
  get no warmth recovery and still lose warmth slowly, and health starts to drop once warmth falls under
  0.2. The Town Hall needs no firewood and is always warm. Heating can be switched off per house, and the
  stock target is adjustable per house.
  **Raw wood as fallback fuel (decided and built 2026-10-26):** 1 wood heats like 3 firewood (`heat` 3 in
  `Defs.ITEMS`), worse than the 5 that splitting gives. A house takes wood only when it is cold out, the house is
  under half its fuel target (`WOOD_FUEL_BELOW_SHARE`) and storage has no firewood (or coal, when allowed), so
  construction wood isn't drained in summer. A house set to burn coal only never takes wood.
  **Any building that produces something should have a production cap setting.**
  Firewood only spoils when it is lying outside on the ground, at the same 10x penalty food gets.
- General rule going forward: tools raise work efficiency, they are not required to work.

### 3.7 Agriculture (the deep system)
| Mechanic | Prototype | Later |
|---|---|---|
| Crops | Wheat (heavy feeder), Beans (restore nitrogen), and since M4 step 1 radishes, lettuce, barley, potatoes, cabbage and pumpkins | Flax (fibre), orchards, more vegetables, herbs |
| Planting window | Per-crop seasons (`sow`) and above the crop's minimum temperature | Winter wheat, player-set planting dates |
| Growth | Hourly. Speed comes from temperature and moisture | Sunlight hours, crop stress states |
| Frost | Kills unripe crops below their frost temperature, and rots ripe crops left into winter | Frost warnings, covered beds |
| Soil fertility | Stored per terrain cell. Harvest changes it according to the crop. Fallow plots slowly recover | Manure/compost, overlay view, nutrients (N/P/K-lite) |
| Crop rotation | Emerges from fertility (beans restore what wheat drains) | Rotation planner per field, bonuses for rotations |
| Water | Per-plot moisture. Rain adds, heat removes. Plots near water stay moist | Irrigation channels, buckets from wells, drought |
| Pests | — | Infestations that spread between plots of the same crop. Countered by rotation, crop diversity and a "pest control" job |
| Seeds | Free | Keep part of the harvest as seed for next year |
| Livestock | — | Pastures, manure for fertility |

**M4 plan (decided 2026-10-26):** step 1 crops (built, see below), step 2 foraging, then seeds, fertility overlay and rotation hints, water (irrigation channels, buckets, drought), pests, orchards, livestock and manure.
- **Step 1, crop system (built 2026-10-26):** `Defs.CROPS` entries now have `sow` (seasons it can be sown in), optional `harvests` and `regrow_days` (a multi-harvest crop: lettuce gives 4 cuttings per sowing, then the plot is fallow), and a `desc`. Crops: wheat, beans, radishes (4 days, hardy, small and not filling: the spring stopgap), lettuce (multi-harvest, spoils fast), barley (hardy, spring only), potatoes (big, slow, frost-tender, hard on soil), cabbage, pumpkins (one huge slow harvest). All give food items with their own spoilage. Fields pick a crop from a menu (`Field.set_crop`, the inspector button opens a popup with each crop's days and sowing window). Farmers now take work by priority: harvest, then clear dead plots, then plant (`Field.ACTION_PRIORITY`, closest first within a priority, across fields too); before, they stuck to the nearest field and left another field's ripe crops rotting. Not yet: seeds, per-field planting dates. **Seeds (decided 2026-10-26, for the seeds step):** crop seeds are not all available at the start: they are obtained through play, and the difficulty decides which seeds the player starts with (data in `Defs.DIFFICULTIES`, like the Town Hall's starting upgrades). Until then every crop is selectable. **Growth note:** growth is slowed by soil moisture (plots out of reach of water, `NEAR_WATER_RANGE` 4, dry out and grow at about a third of the speed) and by cold (`min_temp`), so a crop's `grow_days` is the ideal case and practical times are 2 to 3 times longer. Irrigation (step 4) addresses water.
- **Step 2, foraging (built 2026-10-26):** wild foods are resource nodes with `forage`, `fruit_seasons` and `regrow_days` in `Defs.RESOURCE_NODES`; each gains one unit every `regrow_days` days only in its seasons (replacing the old global spring and summer refill). Berry bushes (spring and summer, daily, picked by gatherers on their own as before), **mushrooms** (spring and autumn, every 2 days, 3 per patch, low nutrition, spoil in 4 days; grow in damp patches among trees) and **hazel groves** (autumn only, 6 per grove, nutritious and keep 150 days: the winter food). Mushrooms and hazel are not picked automatically. The **Forage tool** (toolbar, drag an area) marks forageables as `designated`, so foragers, gatherers and idle laborers pick them when in season; the Harvest tool now ignores them, the Demolish tool unmarks them. The **Forager's Hut** (12 wood, radius 16, 2 slots, new **Forager** profession, a target like the others) sends its workers to the nearest wild food in range that its toggles allow (berries, mushrooms, hazelnuts), and stops when the colony's food stock reaches its cap (`cap_food`, default 120; `Building.production_allowed(&"food")` compares against the whole food stock). A Forager with no hut forages berries like a gatherer. **Measured (`tests/forage_probe.tscn`):** two foragers with about 30 wild foods in range bring in roughly half a six-person colony's food per season; respawn is not the limit (berries stay plentiful, hazelnuts refill in autumn), the limit is forager labor and walking distance, since they take the nearest food first. Not built: choosing which food foragers prefer, wild plants that need no season, herbs.

Fields are player-placed rectangles (fixed 6×6 in the prototype, drag-sized later). The player picks the crop per field.

### 3.8 Resources & production
- Raw resources: wood (trees), stone (rocks), iron (ore deposits), food (forage, farms), water (wells).
- Later chains: wood → firewood (warmth), iron + wood → tools (work speed), flax → linen →
  clothing (warmth), wheat → flour → bread (better nutrition).
- Food spoils over time. **Decided (2026-10-23):** each food type has its own spoilage rate, ambient
  temperature scales it (warmer spoils faster, near and below freezing it nearly stops), and the
  storage building scales it too: the Granary halves the rate. More food storage buildings and
  upgrades or add-ons with different modifiers are planned (`spoil_mult` in the building def).
  Prototype numbers: berries 8 days, beans 90, wheat 120 (time constants at 10 C). Food on the ground spoils 10x
  faster than in ordinary storage, as a penalty for lacking storage.

### 3.9 Trade & barter
- A Trading Post. Merchants arrive by river or road a few times per season with randomized wants and offers.
- Barter uses item values. Luxury goods (TBD: wool, honey, pottery, spirits…) are mostly for trading.
- Merchants can bring new seed types and livestock, which ties trade back into agriculture.

**M5 plan, trade (decided 2026-10-28 as "M6", user's answers; renumbered 2026-10-30):** the terrain milestone was tabled and has since been removed, so trade came next.
- **Goods are hauled by citizens.** A deal reserves what you sell in storage, laborers carry it to the Trading Post's yard, and what you buy is carried from the yard to storage. Nothing teleports.
- **Merchants walk in from the map edge** to the Trading Post a few times a season, stay a few days and walk out again. Offers and wants are random per visit.
- **Luxury goods:** honey (beehives), wool and cloth (sheep, then a weaver), pottery (clay and a kiln), spirits (a still, from barley or fruit), and **gold and silver, to be mined later**.
- Barter, not coins: every item has a trade `value`. **Margins (user, 2026-10-28):** a merchant pays the value times their want multiplier (0.8 to 1.5) for goods they asked for, half the value for anything else, and charges 1.25 times the value for their own goods.
- **Steps:** 1 values, the Trading Post and merchant visits (walk-in, stay, leave); 2 the barter UI, trade orders and the hauling and settlement rules; 3 merchants selling seeds and saplings (`Seeds.unlock`) and livestock; 4 the luxury producers; 5 gold and silver from mines; then polish (merchant types, seasonal prices, a trade history in the ledger).

### 3.10 UI
- Top bar: date, time, weather, key resources, population, speed controls.
- Bottom bar: tools (select, harvest, forage, plant trees, channel, demolish, cancel) and the build menu grouped by category (the terraform brushes were taken off the toolbar on 2026-10-30; the road tool lives under Civic).
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
| **M1** | **Core loop prototype** *(done)* | Terrain gen, camera, clock/seasons/day-night, weather, trees/rocks/bushes, harvest designation, roads, construction with hauling, pawns with needs, professions, basic farming (wheat/beans, fertility, moisture, frost), HUD |
| M2 | Logistics & economy *(done)* | Per-storage inventories and capacity, granary/spoilage, woodcutter/quarry/mine buildings, firewood and warmth, tools, field drag-sizing |
| M3 | Population *(done: death handling, profession targets, life stages, school and teacher, job experience, Policies panel, families and births, happiness, grief and the Graveyard with its Crematorium, homelessness and shacks, Town Hall upgrades, the Governance ledger and history; tuned 2026-10-26)* | Ageing, families, births, children and education, deaths from old age, happiness, homelessness effects |
| M4 | Agriculture depth *(done)* | More crops, sowing calendars, seeds, pests, irrigation channels, fertility overlay, orchards, livestock and manure |
| M5 | Trade *(done, closed 2026-10-30 as 0.5.0; was M6 before the renumbering)* | Trading post, merchants and merchant types, barter UI, trade history, luxury goods (honey, wool and clothing, pottery, spirits, gold and silver), rivers, bridges and fishing came along with it |
| **M6** | **Meta** *(next; was M8)* | See "M6 scope" below: save slots and a load menu, a settings screen, map and game setup (seed, size, river style, climate, difficulty, realism mode, choosing the start), scenarios, a tutorial, and the help overlays |
| M7 | Content & art pass | Real models and animation, audio, UI theme, textures, nicer water, icons, wind sway (see "M7 scope") |
| M8 | Additional features | Everything wanted that has no home in the milestones above (see "M8 scope"): a tavern and other happiness buildings, decorative items, fires, a map editor with terrain modification, more of the economy |

**Removed (2026-10-30):** the old **M5, "Terrain as labor"** (terraforming as worker jobs, dirt and stone moved). Player terrain modification is no longer part of the design; if it ever returns it belongs to a map editor (M8), not to the colony game. (The terrain brush code still exists but is not on the toolbar.) The texture-splat and snow terrain shader that M5 carried moved to M7.

**Renumbering of 2026-10-30** (older notes, decisions and the history in CLAUDE.md use the old numbers): old M6 (trade) is now **M5**; old M8 (meta) is now **M6**; M7 is unchanged; the new **M8** is "Additional features". Old M5 (terrain as labor) is gone.

**M6 scope (Meta).** The load menu with named slots (today only the quicksave and autosave exist, and the title's Continue picks one), a settings screen (also reachable from the Esc menu: graphics such as grass density and shadows, controls, audio later), map and game setup on the New Game screen: seed, **customizable map generation** (river style among other things, hills, size), **climates** picked at the start (temperate, desert, arctic, tropical; the sowing rule is already climate-driven), difficulty beyond the three presets, a **realism mode** (slower time, more realistic ageing), the optional **Banished-style start with no pre-built Town Hall** (choosing the site is built), scenarios, and a tutorial. **Pinned:** tune difficulty with the `arctic_probe` test (the Arctic climate is flagged "not yet tuned" on the New Game screen until then). The **steepness overlay** (which ground can be built on) joins the soil and water overlays here as a help aid.

**M7 scope (Content and art).** Real models and animation, audio, the UI theme and art pass (the generated top-bar icons and the idle bubble are placeholders), **textures** (roads, ground, terrain texture splat and snow), a second look at the **palette** (it still reads a little washed out), **nicer water**, wind sway for grass and trees, real goods in stockpiles (logs, sacks) and the plain panels (Esc menu, Citizens).

**M8 scope (Additional features).** Collected from the playtest notes, nothing here is scheduled:
- **Happiness and daily life:** a tavern (and other happiness buildings, tied to honey and spirits), a **downside to drinking** spirits, **decorative items** (which, whether they affect happiness), **fires** (cold homeless citizens build little fires, maybe real ones that spread).
- **Food and economy:** a root cellar or smokehouse and a spoilage tuning pass, other catches and boats for fishing and smoking or salting fish, a tannery step for leather, jewelry or coins from gold and silver, finite ore veins, swapping to better clothes, a mood effect for clothes, sharing a Paths build tab once there is more than the road and bridge (a paved road, a tunnel).
- **World and weather:** overheating as well as cold, more weather (thunderstorms), a **map editor** (the only home for terrain modification), shrinking buildings and growing others in place, expansion while a building is paused.
- **Known issue to chase, not a feature:** laborers sometimes get stuck hauling in a loop (needs a repro or a save).

Save and load was moved earlier and built at the end of M2 (quicksave, autosave and a round-trip test; see CLAUDE.md). M6 (Meta, was M8) keeps the load menu, named slots, map seeds and settings.

---

## 6. Prototype controls (M1)

| Input | Action |
|---|---|
| WASD / arrows, RMB-drag | Pan camera (RMB-drag grabs the ground) |
| Q / E, middle-drag | Rotate (and tilt) camera |
| Mouse wheel | Zoom |
| Space, 1/2/3 | Pause, game speed |
| LMB | Select / use tool (drag for areas) |
| RMB click / Esc | Cancel tool, deselect (RMB click means no drag) |
| R | Rotate building footprint |

---

## 7. Open questions

1. ~~**Ageing vs calendar**~~ **Decided (2026-10-23):** hybrid. Citizens age faster than the calendar,
   and the rate is an adjustable setting (the calendar and farming stay as they are). Life stages:
   - **Baby, under 5:** never works or attends school, stays home.
   - **Child, 5 to 17:** attends school as their "work". If no school is available, they work instead.
   - **Adult, 18 and over:** works.
   Wanted later: a policy to allow or forbid child labor, with a happiness effect either way.
   Schools have a capacity and need a teacher, who "works" the school like any other job building.
   A child's role is re-evaluated each time their task ends (JobManager.choose_task), with school
   taking priority over labor: if a school loses its teacher or is demolished, children finish the
   current task and fall back to child labor (if the policy allows it, otherwise idle at home); if
   one opens or gets a teacher, working children move to it on their next pick, in order up to its
   capacity. Nobody is locked into the workforce.
   Old age (decided 2026-10-23): work efficiency drops only a few percentage points through most of
   old age, then falls steeply once a citizen is very old. Death rolls also begin in old age, rising
   more gently than the efficiency drop. Experience gain is never reduced by age.
   Still open: the default ageing rate; capacity and teacher numbers; the exact age thresholds and curves.
2. **Map size and scale:** 128 m is enough for a prototype. A full game probably wants 256–512 m
   with chunk streaming or LOD.
3. ~~**Storage model**~~ **Decided (2026-10-23):** per-building physical stock. Each storage building has its
   own inventory and capacity. The colony-wide count (current) is a prototype simplification.
   Details decided 2026-10-23: a new **Granary** holds food only. Every storage building also has
   player-set item filters (allow or forbid each item). Capacity is one total per building. When no
   storage has room, workers stop starting gather jobs for that item and any carried goods are
   dropped on the ground as a loose pile that can be hauled later. A storage building can't be
   demolished until it is empty.
4. ~~**Terraforming cost**~~ **Superseded (2026-10-30):** player terrain modification is no longer part of the design
   (the old M5 was removed); it would belong to a map editor (M8). The older call, kept for reference: terraforming
   requires citizen labor and dirt is not a resource.
5. **Art direction:** low-poly stylised (it fits the procedural approach) or something more realistic?
6. **Failure state:** does the game end when everyone dies, or are there "settler wave" recovery options?

---

## 8. M1 prototype notes (findings so far)

- A one-year soak run: the colony builds houses, a well and fields, gets one wheat harvest
  (planted early spring, ripe at the start of autumn) and gets through winter on stored food.
- **Decided (2026-10-23):** crop speed varies per crop. Quick crops (lettuce, radishes) allow multiple harvests a year,
  slow ones (pumpkins) one. Some crops give multiple harvests per sowing and only need replanting after they die off.
  Needs a per-crop "multi-harvest" attribute and more crops (see M4).
- Wheat ripens slowly because early spring is cold (around 3 °C mean). One harvest per year fits
  "realistic", but bean/wheat rotation in a single year isn't possible yet. This is a tuning question.
- Spring frosts can kill early plantings, and farmers plant as soon as the daily mean is above
  the crop minimum. Later: let the player set a planting date or a risk tolerance per field.
- About 45 fps on integrated graphics (UHD 620) at 1600×900 with shadows.
- Known simplifications: colony-wide stock, free and instant terraforming, fixed 6×6 fields,
  no seeds, no ageing or births, placeholder primitive art.

---

## 9. Later ideas (visual polish)

- **Wind sway for grass and trees (noted 2026-10-26, not built).** Grass tufts (`GrassDetail`), pines, oak crowns and bushes
  (`ResourceRenderer`) are all MultiMeshes with a `StandardMaterial3D` and vertex colours, so they stand perfectly still.
  Sway needs a small custom spatial shader (vertex function) in place of those materials:
  - Displace vertices sideways in proportion to height above the base (`VERTEX.y`, or a baked vertex-colour mask), so roots
    and trunks stay put and tips and crowns move most; trunks nearly rigid, crowns and grass blades more.
  - Phase from the instance's world position (a hash, or `INSTANCE_CUSTOM`) so neighbours don't move in step; a slow large
    wave plus a faster small flutter.
  - The shader must reproduce what the standard material does today: albedo times vertex colour times instance colour
    (the tint trick `add_part` uses, and the per-season colours set on the materials).
  - Drive it from a wind uniform, not `TIME`: an accumulated wind clock advanced by `World.fx_speed()`, so sway pauses with
    the game and speeds up with it (like rain, snow and smoke already do), and a wind strength that follows the weather
    (calm in clear weather, stronger in rain, strongest in storms) and could set the smoke and rain slant.
  - Cost: vertex work only, likely small, but measure on the UHD 620 (about 45 fps at 1600x900 before the tufts); fade the
    sway out at distance, as the grass tufts already fade out of view.
  - Also fits the title screen (frozen town, moving grass and trees).

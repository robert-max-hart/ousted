# Scenario ideas

Brainstormed 2026-10-31. Nothing here is scheduled or built. The five scenarios that exist (riverside, dry season, wetlands, coast, bare hands)
are in `scripts/data/scenarios.gd`: each has a fixed seed, a `setup` (climate, water layout, hills, map size, start type, custom rules) and `goals`
(population, years, stock, building, trade). Ideas below say what each would need beyond that.

## Five serious ones (work with the scenario system as it is, or nearly)

1. **The Long Winter.** Arctic climate, hard supplies. Survive three years with at least 12 citizens and 200 firewood in store.
   Needs: nothing new, but the Arctic difficulty tuning is still pinned (`arctic_probe`), and the first winter is where colonies die.
2. **Merchant's Road.** Few supplies, frequent merchants, a river. Reach a number of trades and learn every seed type.
   Needs: nothing new. Teaches the whole trade loop.
3. **Shepherd's Valley.** Many hills with a flat start. Run three pastures and have every citizen wearing clothes.
   Needs: a goal for "citizens wearing clothes".
4. **Orchard Country.** Temperate, extra orchard seeds at the start. Stock apples and pears, then spirits.
   Needs: nothing new. Rewards patience, orchards take years to pay off.
5. **The Oasis.** Desert (the tan ground), frequent droughts, a well-or-nothing start. Reach 30 citizens by managing wells and channels.
   Needs: nothing new. Shows off the desert look.

## Five completely outrageous ones (small additions: a goal type or a setup override)

1. **Pumpkin Supremacy.** Only pumpkin seeds, winter coming. Stock 500 pumpkins. Needs a seeds override in `setup`. Brutal, pumpkins ripen slowly here.
2. **Cloud Nine.** The smallest map, maximum hills: an island in the cloud sea (the map-edge clouds). Reach 30 citizens and 20 gold. Needs the gold mine upgrade chain.
3. **Bog Barons.** Wetlands at 74% water, expand only by bridges, almost no starting wood. Lay 60 bridge tiles. Needs a "bridge tiles built" goal.
4. **Cow Rush.** Merchants sell only cows. Reach 30 cows and ship out milk before it spoils. Needs a merchant-stock override in `setup`.
5. **The Cart and Six Strangers.** No Town Hall, no merchants, a harsh climate, ten years to survive (the Nothing start). Works now; expect an early starvation spiral.

## Five even wilder ones (each needs at least one new game mechanic)

1. **The Plague Year** (new mechanic: **disease**).
   A sickness arrives with a merchant (or on its own) and spreads between citizens who share a house, a workplace or a school. The sick work slowly and
   may die; the dead go to the graveyard as usual, which feeds grief. The new pieces: an `ill` state on `Pawn` with a spread chance per hour and
   a recovery or death roll, a **Herbalist's Hut** (or an infirmary) that treats the sick, and a **Quarantine** policy (the sick stay home,
   merchants are turned away). Goal: still 15 citizens left after the year, with the graveyard under half full.
   Plays against: school (spread), houses of six (spread), trade (the carrier), happiness (fear and grief).
2. **Tidal Flats** (new mechanic: **tides**).
   A coast map where the sea level rises and falls twice a day: at low tide a belt of mudflat opens (shellfish and walkable shortcuts), at high tide it is
   water again (fields and paths drown, boats float). The new pieces: a time-varying water level in `Terrain` (`is_water` becomes tide-aware, so the
   nav grid and the water overlay refresh with it), flooding rules for fields and storage on the flats, a **Tide Mill** (power from the flow) and shellfish as a catch.
   Goal: a working mill, a fishing harbour and 25 citizens without losing a field to the sea. Plays against: fishing, bridges and fords, wetlands generation.
3. **Smoke Mountain** (new mechanic: **a volcano**).
   One hill is a volcano. Every few years it rumbles (a warning day), then erupts: ash falls across the map (soil fertility drops for a season, then ends up
   higher than before; roofs need clearing; the sky goes grey), lava runs down one side and destroys what is in its path, and a quarter of the land
   becomes rich ash soil. The new pieces: an eruption event with a warning, lava cells (`Terrain` overlay that blocks and burns), an ash cover on the
   weather layer, a fertility bonus, an **Observatory** that gives a longer warning. Goal: survive three eruptions and harvest the ash soil.
   Plays against: soil and fields, snow cover (ash can reuse it), relocation, the Town Hall's unique placement.
4. **The Dragon's Tithe** (new mechanic: **tribute demands**, no combat).
   Something large in the hills sends word each season that it wants a tribute: so many sheep, gold, honey, in a stated number of days.
   Pay it and it leaves you alone and sometimes leaves a gift; short it and it takes more later or something is lost (a field burns, a house is
   taken). The new pieces: a `Demands` system like `Traders` (a deadline, an amount, a deposit point that citizens haul to, consequences), a
   toast and a countdown on the HUD. Goal: pay seven tributes and still have 30 citizens. Plays against: trade (buying what you lack), pastures, mines,
   hauling, the ledger.
5. **The Wandering Colony** (new mechanic: **migration**).
   The land runs out (a blight, a drought that never ends, a season of ash) and the whole colony has to pack up and go. Houses are tents and carts; a **Pack**
   order turns buildings into a convoy, citizens walk it across the map (or to a second map) to a chosen site, and **Unpack** sets it up again with a
   cost in time and some losses. The new pieces: whole-colony relocation (the per-building `Relocation` helper is the starting point), a convoy of
   carts that holds the goods (the supply cart is the model), a long journey with a mood cost, and a map that gets a second site to settle on. Goal: found
   three settlements in turn, each with 10 citizens. Plays against: relocation, carts and the Nothing start, stock, hunger on the road.

## If one were built first

Cheapest to build with the most new play: **Tidal Flats** (one new variable, the water level, that most systems already read through `is_water`) or the
**Dragon's Tithe** (a self-contained event system). **The Plague Year** is the richest but touches the most code (pawns, houses, school, trade).

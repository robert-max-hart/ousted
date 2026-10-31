# ----------------------------------------------------------------
# WorldSave
#     Saving and restoring a World: serialize() builds the dictionary
#     SaveGame writes, restore_entities() puts a saved game's nodes,
#     buildings, citizens and the rest back.
# ----------------------------------------------------------------
class_name WorldSave extends RefCounted;

# Everything needed to rebuild this world. Citizens' tasks are not saved: they restart idle.
static func serialize(world:World) -> Dictionary:
    var node_list:Array = [];
    for rn in world.nodes:
        node_list.append(rn.to_array());
    var building_list:Array = [];
    for b in world.buildings:
        building_list.append(b.to_dict());
    var pawn_list:Array = [];
    for p in world.pawns:
        pawn_list.append(p.to_dict());
    var body_list:Array = [];
    for b in world.bodies:
        body_list.append(b.to_dict());
    var pile_list:Array = [];
    for pl in world.piles:
        pile_list.append(pl.to_dict());
    return {
        "seed": world.world_seed, "rules": GameRules.to_dict(), "scenario": world.scenario.to_dict() if world.scenario != null else {}, "map": {"size": Terrain.SIZE, "river": Terrain.river_style, "climate": Climate.current}, "rng_state": world.rng.state, "wetness": world.wetness,
        "clock": GameClock.save_state(), "weather": Weather.save_state(),
        "heights": world.terrain.heights, "overlay": world.terrain.overlay, "soil": world.soil_fertility,
        "road_kind": world.road_kind.keys().map(func(c:Vector2i) -> Array: return [c, world.road_kind[c]]), "pending_roads": world.pending_roads.keys(), "tree_orders": world.tree_orders.keys(), "road_work": world.road_work.keys().map(func(c:Vector2i) -> Array: return [c, world.road_work[c]]), "seeds": world.seeds.to_array(), "deaths": world.death_log, "ageing_days_per_year": Defs.ageing_days_per_year, "targets": world.jobs.targets, "policies": world.policies.to_dict(), "ledger": world.ledger.to_dict(), "traders": world.traders.to_dict(), "nodes": node_list, "buildings": building_list, "pawns": pawn_list, "piles": pile_list, "bodies": body_list, "next_body_id": world._next_body_id,
        "camera": world.camera_rig.save_state() if world.camera_rig != null else {},
        "summary": {"date": "%s, %s" % [GameClock.date_string(), GameClock.time_string()], "pop": world.pawns.size()},
    };

# Rebuilds nature, buildings, piles and citizens from a save. The terrain and soil are loaded by the caller.
static func _restore_entities(world:World, save:Dictionary) -> void:
    world.soil_fertility = save["soil"];
    world.wetness = save["wetness"];
    Defs.ageing_days_per_year = save.get("ageing_days_per_year", 4.0);
    for a in save["nodes"]:
        var rn:ResourceNode = ResourceNode.from_array(a, world.rng);
        world.nodes.append(rn);
        world.node_at[world.idx(rn.cell)] = rn;
        if rn.growth < 1.0:
            world.saplings.append(rn);
    for bd in save["buildings"]:
        if Defs.LEGACY_PASTURES.has(bd["id"]):       # saves from before there was one pasture building: the old ids were one animal each
            if not bd.has("kind"):
                bd["kind"] = Defs.LEGACY_PASTURES[bd["id"]];
            bd["id"] = &"pasture";
        var b:Building = world.place_building(bd["id"], bd["origin"], bd["size"], false, true, bd.get("facing", 0));
        b.restore_dict(bd);
        if not b.expansion.is_empty():
            Expansion.hold_cells(world, b);
        if bd["id"] == &"town_hall" and b.is_complete():
            world.town_hall = b;
    for i in world.buildings.size():
        var bd2:Dictionary = save["buildings"][i];
        if bd2.get("reloc_from", -1) >= 0:
            world.buildings[i].relocating_from = world.buildings[bd2["reloc_from"]];
        if bd2.get("reloc_to", -1) >= 0:
            world.buildings[i].relocating_to = world.buildings[bd2["reloc_to"]];
    for pd in save["piles"]:
        var pl:GroundPile = GroundPile.new();
        pl.setup(world, pd["item"], pd["amount"], pd["cell"]);
        pl._spoil_acc = pd["spoil_acc"];
        world._entities.add_child(pl);
        world.piles.append(pl);
    for pd in save["pawns"]:
        var p:Pawn = Pawn.new();
        p.restore(world, pd);
        world._entities.add_child(p);
        world.pawns.append(p);
        if pd["home"] >= 0 and pd["home"] < world.buildings.size():
            p.home = world.buildings[pd["home"]];
            p.home.residents.append(p);
    for i in world.pawns.size():
        var pd:Dictionary = save["pawns"][i];
        var partner_i:int = pd.get("partner", -1);
        if partner_i >= 0 and partner_i < world.pawns.size():
            world.pawns[i].partner = world.pawns[partner_i];
        for pi in pd.get("parents", []):
            if pi >= 0 and pi < world.pawns.size():
                world.pawns[i].parents.append(world.pawns[pi]);
    world._next_body_id = save.get("next_body_id", 1);
    for bd in save.get("bodies", []):
        var b:Body = Body.new();
        b.setup(world, bd["id"], bd, bd["position"]);
        for ki in bd["kin"]:
            if ki >= 0 and ki < world.pawns.size():
                b.kin.append(world.pawns[ki]);
        world._entities.add_child(b);
        world.bodies.append(b);
    world._refresh_nav_rect(Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE));
    world.renderer.mark_dirty();
    world.rng.state = save["rng_state"];
    world.death_log = save.get("deaths", []);
    for c in save.get("pending_roads", []):
        world.pending_roads[c] = true;
    for c in save.get("tree_orders", []):
        world.tree_orders[c] = true;
        world._add_order_mark(c);
    for e in save.get("road_work", []):
        world.road_work[e[0]] = e[1];
    for e in save.get("road_kind", []):
        world.road_kind[e[0]] = e[1];
    world.update_irrigation();
    world.policies.restore(save.get("policies", {}));
    world.seeds.restore(save.get("seeds", null));
    world.ledger.restore(save.get("ledger", {}));
    world.traders.restore(save.get("traders", {}));
    var saved_targets:Variant = save.get("targets", null);       # saves made before targets existed
    if saved_targets != null:
        world.jobs.targets = saved_targets;
    else:
        world.jobs.sync_targets();

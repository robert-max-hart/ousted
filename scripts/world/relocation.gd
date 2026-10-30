# ----------------------------------------------------------------
# Relocation
#     Moving a finished building: why it cannot move now, placing the
#     site that takes its place and finishing the move (settings,
#     goods and residents carry over).
# ----------------------------------------------------------------
class_name Relocation extends RefCounted;

static func relocation_block_reason(world:World, b:Building) -> String:
    if not b.def.get("relocatable", true):
        return "Can't be moved";
    if not b.is_complete():
        return "Not finished";
    if b.upgrading != &"":
        return "Upgrade in progress" if b.upgrading != Expansion.ID else "Expansion in progress";
    if b.relocating_to != null and world.alive(b.relocating_to):
        return "Already being moved";
    if b.relocating_from != null:
        return "This is the new site";
    if b.is_storage() and not b.is_empty():
        return "Empty it first";
    if b is TradingPost and not (b as TradingPost).idle():
        return "Finish the trade first";
    return "";

# Starts building the same thing at a new spot for a share of the cost (Defs.RELOCATE_COST_MULT). The old building keeps
# working, takes nothing new, and is replaced once the new one is finished.
static func relocate(world:World, b:Building, origin:Vector2i, size:Vector2i, facing:int = 0) -> Building:
    if Relocation.relocation_block_reason(world, b) != "" or world.can_place(b.def_id, origin, size, true) != "":
        return null;
    var site:Building = world.place_building(b.def_id, origin, size, false, false, facing);
    site.cost_mult = Defs.RELOCATE_COST_MULT;
    site.relocating_from = b;
    b.relocating_to = site;
    world.notify("Moving the %s: a new one is being built." % b.display_name());
    return site;

# The new building takes over: settings, filters, upgrades, fuel, inputs, residents, what is stored, and the Town Hall role.
static func _finish_relocation(world:World, site:Building) -> void:
    var old:Building = site.relocating_from;
    site.relocating_from = null;
    old.relocating_to = null;
    site.settings = old.settings.duplicate();
    site.forbidden = old.forbidden.duplicate();
    site.upgrades_done = old.upgrades_done.duplicate();
    site.dig_progress = old.dig_progress.duplicate();
    site.fuel = old.fuel;
    site.fuel_coal = old.fuel_coal;
    old.fuel = 0;
    site.inputs = old.inputs.duplicate();
    old.inputs.clear();
    site.stored = old.stored.duplicate();
    old.stored.clear();
    for p in old.residents.duplicate():
        world.families.move_home(p, site);
    if old == world.town_hall:
        world.town_hall = site;
    old.in_reserved = 0;
    old.out_reserved.clear();
    world.remove_building(old, false);

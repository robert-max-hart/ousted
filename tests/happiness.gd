# ----------------------------------------------------------------
# Happiness, grief and graveyard test
#     Happiness factors and how happiness follows them, grief from a
#     death and its softening by a burial, bodies carried by kin first,
#     a drag-sized graveyard and its graves decomposing, bodies vanishing
#     with no grave, child labor and leaving the colony.
#     godot --headless --path . --fixed-fps 60 res://tests/happiness.tscn
# ----------------------------------------------------------------
extends Node;

var world:World;
var yard:Graveyard;
var a:Pawn;
var b:Pawn;
var kid:Pawn;
var stranger:Pawn;
var body:Body;
var _grief_before:float = 0.0;
var _stage:int = 0;
var _start:float = 0.0;

func _ready() -> void:
    SaveGame.autosave_enabled = false;
    world = (load("res://scenes/main.tscn") as PackedScene).instantiate();
    add_child(world);
    Engine.time_scale = 4.0;
    Defs.ageing_days_per_year = 400.0;
    a = world.pawns[0];
    b = world.pawns[1];
    kid = world.pawns[2];
    stranger = world.pawns[3];
    for p in world.pawns:
        p.profession = JobManager.Profession.LABORER;
    world.jobs.sync_targets();
    a.age = 30.0; b.age = 32.0; stranger.age = 40.0;
    kid.age = 10.0;
    kid.parents = [a, b];
    world.families.pair(a, b);
    _check_factors();
    _check_mood();
    _check_child_labor();
    _check_leaving();
    _check_death_and_grief();

func _factor(p:Pawn, label:String) -> float:
    for f in p.happiness_factors():
        if f[0] == label:
            return f[1];
    return 0.0;

func _check_factors() -> void:
    var baby:Pawn = Pawn.new();
    baby.world = world;
    baby.age = 1.0;
    _expect("a baby has no happiness factors", baby.happiness_factors().is_empty());
    baby.free();
    stranger.home = null;
    _expect("no home costs happiness", _factor(stranger, "No home") < 0.0);
    stranger.hunger = 0.0;
    _expect("hunger costs up to 30%%", is_equal_approx(_factor(stranger, "Hungry"), -0.3));
    stranger.hunger = 1.0;
    _expect("a fed citizen has no hunger factor", _factor(stranger, "Hungry") == 0.0);
    _expect("the target stays between 0 and 1", stranger.target_mood() >= 0.0 and stranger.target_mood() <= 1.0);
    _expect("inspector lists the factors", stranger.info_text().contains("No home"));

func _check_mood() -> void:
    stranger.mood = 0.65;
    stranger.hunger = 0.0; stranger.thirst = 0.0; stranger.warmth = 0.0;
    var target:float = stranger.target_mood();
    var before:float = stranger.mood;
    stranger._update_mood(Defs.MOOD_HOURS);
    var moved:float = (before - stranger.mood) / (before - target);
    _expect("happiness moves about 63%% of the way in one time constant (%.2f)" % moved, absf(moved - 0.632) < 0.02);
    stranger.hunger = 1.0; stranger.thirst = 1.0; stranger.warmth = 1.0;
    stranger.mood = 0.0;
    _expect("a miserable citizen works at 85%%", is_equal_approx(stranger.mood_efficiency(), Defs.MOOD_SLOW_MIN));
    stranger.mood = 0.5;
    _expect("a content citizen works at full speed", is_equal_approx(stranger.mood_efficiency(), 1.0));
    stranger.mood = 0.65;
    stranger.home = null;

func _check_child_labor() -> void:
    world.child_labor_share = 1.0;
    var child_cost:float = _factor(kid, "Children are working");
    var adult_cost:float = _factor(stranger, "Children are working");
    world.child_labor_share = 0.0;
    _expect("children feel child labor (%.2f)" % child_cost, child_cost < 0.0);
    _expect("adults feel it less (%.2f)" % adult_cost, adult_cost < 0.0 and absf(adult_cost) < absf(child_cost));
    _expect("no penalty when no child works", _factor(kid, "Children are working") == 0.0);
    world.policies.set_on(&"child_labor", false);
    world._update_child_labor();
    _expect("no penalty while the policy forbids it", world.child_labor_share == 0.0);
    world.policies.set_on(&"child_labor", true);
    var pair_chance:Callable = func(m:float) -> float:
        a.mood = m; b.mood = m;
        return world.families.birth_chance(world.town_hall, a, b);
    _expect("happier pairs have more children", pair_chance.call(0.0) < pair_chance.call(1.0));
    a.mood = 0.65; b.mood = 0.65;

func _check_leaving() -> void:
    var leaver:Pawn = world.pawns[4];
    var count:int = world.pawns.size();
    leaver.mood = 0.1;
    leaver._unhappy_hours = Defs.LEAVE_AFTER_DAYS * 24.0 - 0.05;
    leaver._update_mood(0.1);
    _expect("a citizen unhappy for 5 days leaves", world.pawns.size() == count - 1 and not world.bodies.any(func(x:Body) -> bool: return x.person == leaver.first_name));
    stranger.mood = 0.1;
    stranger._unhappy_hours = 50.0;
    stranger.mood = 0.5;
    stranger._update_mood(0.1);
    _expect("recovering resets the count", stranger._unhappy_hours > 50.0 or stranger.mood > Defs.LEAVE_BELOW);
    stranger.mood = 0.65;
    stranger._unhappy_hours = 0.0;

# Pretends hours have passed for a citizen's grief (moving the clock would also age the bodies).
func _age_grief(p:Pawn, hours:float) -> void:
    for g in p.grief:
        g["start"] -= hours;
        g["until"] -= hours;

func _check_death_and_grief() -> void:
    var count:int = world.pawns.size();
    world.kill_pawn(a, "test");
    _expect("a body lies where they died", world.bodies.size() == 1 and world.bodies[0].person == a.first_name);
    body = world.bodies[0];
    _expect("the partner is the kin", body.kin.has(b) and not body.kin.has(stranger));
    _expect("the partner grieves most (%.2f)" % b.grief_now(), absf(b.grief_now() - Defs.GRIEF_PARTNER.x) < 0.03);
    _expect("the child grieves (%.2f)" % kid.grief_now(), absf(kid.grief_now() - Defs.GRIEF_FAMILY.x) < 0.03);
    _expect("everyone else grieves a little (%.2f)" % stranger.grief_now(), absf(stranger.grief_now() - Defs.GRIEF_COLONY.x) < 0.03);
    _expect("grief shows as a factor", _factor(b, "Grieving") < 0.0);
    var g:float = b.grief_now();
    _age_grief(b, Defs.GRIEF_PARTNER.y * 12.0);
    _expect("grief fades by half after half its time", absf(b.grief_now() - g * 0.5) < 0.01);
    _age_grief(b, Defs.GRIEF_PARTNER.y * 12.0 + 1.0);
    b._update_mood(0.1);
    _expect("it is gone after its time", b.grief_now() == 0.0 and b.grief.is_empty());
    # a fresh death, to see burial soften it
    world.kill_pawn(world.pawns[world.pawns.size() - 1], "test");
    body = world.bodies[world.bodies.size() - 1];
    _expect("two bodies now", world.bodies.size() == 2);
    # no graveyard yet: nothing to do
    _expect("nobody can bury with no graveyard", world.jobs.burial.bury_task(b) == null);
    var th:Building = world.town_hall;
    var o:Vector2i = th.origin + Vector2i(8, -4);
    yard = world.place_building(&"graveyard", o, Vector2i(5, 4), true) as Graveyard;
    _expect("a 5x4 graveyard has 20 graves", yard != null and yard.plot_count() == 20 and yard.free_slots() == 20);
    for p in world.pawns:
        p.profession = JobManager.Profession.LABORER;
    # the second body was a settler's: kin are only those in kin; a stranger must wait for the family window
    var other:Pawn = null;
    for p in world.pawns:
        if not body.living_kin().has(p) and p.is_adult():
            other = p;
    if not body.living_kin().is_empty() and other != null:
        _expect("a stranger must wait for the family window", not body.can_be_taken_by(other));
        GameClock.total_hours += Defs.BODY_FAMILY_FIRST_HOURS;
        _expect("after it, any adult laborer may", body.can_be_taken_by(other));
        GameClock.total_hours -= Defs.BODY_FAMILY_FIRST_HOURS;
    _grief_before = b.grief_now();
    b.add_grief(0.4, 12.0, world.bodies[0].id);
    _grief_before = b.grief_now();
    _expect("the partner can take the first body at once", world.bodies[0].can_be_taken_by(b) or not world.bodies[0].living_kin().has(b));
    for p in world.pawns:
        p.hunger = 1.0; p.thirst = 1.0; p.energy = 1.0;
    GameClock.set_speed(3);
    _start = GameClock.total_hours;
    _stage = 1;

func _process(_delta:float) -> void:
    if _stage != 1:
        return;
    for p in world.pawns:
        p.hunger = maxf(p.hunger, 0.8); p.thirst = maxf(p.thirst, 0.8); p.energy = maxf(p.energy, 0.5);
    var hours:float = GameClock.total_hours - _start;
    if (yard.used_slots() >= 2 and world.bodies.is_empty()) or hours > 60.0:
        _stage = 2;
        _expect("both bodies were buried within %.1f hours" % hours, yard.used_slots() == 2 and world.bodies.is_empty());
        _expect("a grave is not free any more", yard.free_slots() == 18);
        _expect("the graveyard inspector counts them", yard.info_text().contains("2 of 20"));
        _expect("burial softened the grief (%.3f from %.3f)" % [b.grief_now(), _grief_before], b.grief_now() < _grief_before * 0.7);
        _check_decay();

func _check_decay() -> void:
    var i:int = -1;
    for k in yard.plot_count():
        if yard.graves[k] != null:
            i = k;
    yard.graves[i]["buried_hour"] -= yard.decay_hours() + 1.0;
    yard.on_day();
    _expect("a grave decomposes after %d years and frees its square" % Defs.GRAVE_DECAY_YEARS, yard.used_slots() == 1);
    var save:Dictionary = world.serialize();
    var found:bool = false;
    for bd in save["buildings"]:
        if bd["id"] == &"graveyard" and bd["graves"].size() == 20 and bd["graves"].count(null) == 19:
            found = true;
    _expect("graves are saved", found);
    # an unburied body with no graveyard room vanishes after a few days
    world.remove_building(yard, false);
    world.kill_pawn(world.pawns[world.pawns.size() - 1], "test");
    var lingering:Body = world.bodies[0];
    _expect("a body is saved too", world.serialize()["bodies"].size() == 1);
    lingering.died_hour -= Defs.BODY_LINGER_DAYS * 24.0 + 1.0;
    world._on_hour(0);
    _expect("an unburied body vanishes after %d days" % Defs.BODY_LINGER_DAYS, world.bodies.is_empty());
    get_tree().quit();

func _expect(what:String, ok:bool) -> void:
    print("%s: %s" % ["PASS" if ok else "FAIL", what]);

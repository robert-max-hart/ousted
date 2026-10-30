# ----------------------------------------------------------------
# BuildingShapes
#     Silhouettes for the buildings that should not read as "a
#     house": the Granary's silos, the Town Hall's clock tower, the
#     Mine's headframe and tunnel, and the extras on the Blacksmith,
#     School and Forager's Hut. Everything is built from boxes,
#     cylinders and spheres in the building's local frame (origin at
#     the centre of its footprint, y up) and added through
#     Building.add_decor, so it hides while the building is a site.
# ----------------------------------------------------------------
class_name BuildingShapes extends RefCounted;

const IRON      :Color = Color(0.2, 0.19, 0.19);
const TIMBER    :Color = Color(0.4, 0.28, 0.17);
const DARK      :Color = Color(0.08, 0.07, 0.07);

# --------------------------------
# Helpers

static func _box(b:Building, dims:Vector3, mat:Material, at:Vector3, rot:Vector3 = Vector3.ZERO) -> MeshInstance3D:
    var m:BoxMesh = BoxMesh.new();
    m.size = dims;
    return b.add_decor(m, mat, at, rot);

static func _cyl(b:Building, top_r:float, bottom_r:float, height:float, mat:Material, at:Vector3, segments:int = 16, rot:Vector3 = Vector3.ZERO) -> MeshInstance3D:
    var m:CylinderMesh = CylinderMesh.new();
    m.top_radius = top_r;
    m.bottom_radius = bottom_r;
    m.height = height;
    m.radial_segments = segments;
    m.rings = 1;
    return b.add_decor(m, mat, at, rot);

static func _ball(b:Building, radius:float, mat:Material, at:Vector3, squash:float = 1.0) -> MeshInstance3D:
    var m:SphereMesh = SphereMesh.new();
    m.radius = radius;
    m.height = radius * 2.0 * squash;
    m.radial_segments = 8;
    m.rings = 4;
    return b.add_decor(m, mat, at);

# A four-sided pyramid roof sitting on a square of half-width w.
static func _pyramid(b:Building, w:float, height:float, mat:Material, base:Vector3) -> MeshInstance3D:
    return _cyl(b, 0.0, w * 1.4142, height, mat, base + Vector3(0, height * 0.5, 0), 4, Vector3(0, PI * 0.25, 0));

static func _colour(c:Color) -> StandardMaterial3D:
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.albedo_color = c;
    m.roughness = 0.9;
    return m;

static func _roof_mat(b:Building) -> StandardMaterial3D:
    return SurfaceTextures.material(&"shingle", b.def.get("roof", Color.BROWN));

# --------------------------------
# Granary: a tall silo with a cone roof, a smaller one beside it, iron bands and a door.

static func silo(b:Building) -> void:
    var s:Vector2 = Vector2(b.vsize);
    var r:float = minf(s.x, s.y) * 0.27;
    var tall:float = 3.1;
    var at:Vector3 = Vector3(-s.x * 0.2, 0.0, -s.y * 0.12);
    var cyl:CylinderMesh = CylinderMesh.new();
    cyl.top_radius = r;
    cyl.bottom_radius = r;
    cyl.height = tall;
    cyl.radial_segments = 20;
    b.set_body(b._add_mesh(cyl, b._body_mat, at + Vector3(0, tall * 0.5, 0)), 0.0, tall);
    var cone:CylinderMesh = CylinderMesh.new();
    cone.top_radius = 0.05;
    cone.bottom_radius = r * 1.2;
    cone.height = 0.9;
    cone.radial_segments = 20;
    b.set_roof(b._add_mesh(cone, _roof_mat(b), at + Vector3(0, tall + 0.45, 0)));
    var iron:StandardMaterial3D = _colour(IRON);
    for y in [0.7, 1.5, 2.3]:
        _cyl(b, r * 1.03, r * 1.03, 0.07, iron, at + Vector3(0, y, 0), 20);
    var r2:float = r * 0.72;
    var tall2:float = 2.1;
    var at2:Vector3 = Vector3(s.x * 0.3, 0.0, -s.y * 0.22);
    _cyl(b, r2, r2, tall2, b._body_mat, at2 + Vector3(0, tall2 * 0.5, 0), 16);
    _cyl(b, 0.04, r2 * 1.2, 0.7, _roof_mat(b), at2 + Vector3(0, tall2 + 0.35, 0), 16);
    _cyl(b, r2 * 1.03, r2 * 1.03, 0.06, iron, at2 + Vector3(0, 1.0, 0), 16);
    _box(b, Vector3(0.5, 0.95, 0.1), _colour(DARK), at + Vector3(0, 0.48, r));
    _box(b, Vector3(0.55, 0.06, 0.12), _colour(TIMBER), at + Vector3(0, 0.98, r));

# --------------------------------
# Town Hall: a long stone hall with a gabled roof, columns at the door and a clock tower.

static func hall(b:Building) -> void:
    var s:Vector2 = Vector2(b.vsize);
    var body:Vector2 = s - Vector2(0.5, 0.5);
    var bh:float = b.def.get("height", 3.0) * 0.62;
    var box:BoxMesh = BoxMesh.new();
    box.size = Vector3(body.x, bh, body.y);
    b.set_body(b._add_mesh(box, b._body_mat, Vector3(0, bh * 0.5, 0)), 0.0, bh);
    var roof_h:float = bh * 0.5;
    var prism:PrismMesh = PrismMesh.new();
    prism.size = Vector3(s.x - 0.1, roof_h, s.y - 0.2);
    b.set_roof(b._add_mesh(prism, _roof_mat(b), Vector3(0, bh + roof_h * 0.5, 0)));
    b._build_door(body, bh);
    var stone:StandardMaterial3D = b._body_mat;
    for sx in [-0.75, 0.75]:
        _cyl(b, 0.11, 0.13, bh * 0.9, stone, Vector3(sx, bh * 0.45, body.y * 0.5 + 0.2), 8);
    _box(b, Vector3(2.0, 0.12, 0.7), stone, Vector3(0, 0.06, body.y * 0.5 + 0.3));
    var tz:float = -s.y * 0.1;
    var base:float = bh + roof_h * 0.55;
    _box(b, Vector3(1.1, 1.5, 1.1), stone, Vector3(0, base + 0.75, tz));
    _pyramid(b, 0.68, 0.9, _roof_mat(b), Vector3(0, base + 1.5, tz));
    _box(b, Vector3(0.5, 0.5, 0.06), _colour(Color(0.93, 0.9, 0.78)), Vector3(0, base + 1.0, tz + 0.58));
    _ball(b, 0.06, _colour(DARK), Vector3(0, base + 1.0, tz + 0.62));

# --------------------------------
# Trading Post: an open market pavilion, not a house. A plank deck under a striped canvas tent on four posts, a
# counter with a balance, crates, barrels and sacks, a banner on the ridge and a hanging sign by the deck.

static var _stripes_tex:Dictionary = {};       # colour pair -> stripe texture

static func _awning(red:Color, cream:Color) -> StandardMaterial3D:
    var key:String = "%s%s" % [red, cream];
    if not _stripes_tex.has(key):
        var img:Image = Image.create(8, 1, false, Image.FORMAT_RGBA8);
        for x in 8:
            img.set_pixel(x, 0, red if x < 4 else cream);
        _stripes_tex[key] = ImageTexture.create_from_image(img);
    var m:StandardMaterial3D = StandardMaterial3D.new();
    m.albedo_texture = _stripes_tex[key];
    m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST;
    m.uv1_triplanar = true;
    m.uv1_scale = Vector3(0.45, 1.0, 1.0);
    m.cull_mode = BaseMaterial3D.CULL_DISABLED;
    m.roughness = 1.0;
    return m;

static func market(b:Building) -> void:
    var s:Vector2 = Vector2(b.vsize);
    var deck:Vector2 = s - Vector2(0.3, 0.3);
    var wood:StandardMaterial3D = SurfaceTextures.material(&"planks", Color(0.7, 0.55, 0.38));
    var timber:StandardMaterial3D = _colour(TIMBER);
    var deck_h:float = 0.22;
    var plat:BoxMesh = BoxMesh.new();
    plat.size = Vector3(deck.x, deck_h, deck.y);
    b.set_body(b._add_mesh(plat, wood, Vector3(0, deck_h * 0.5, 0)), 0.0, deck_h);
    var post_h:float = 2.15;
    var hx:float = deck.x * 0.5 - 0.15;
    var hz:float = deck.y * 0.5 - 0.15;
    for sx in [-hx, hx]:
        for sz in [-hz, hz]:
            _box(b, Vector3(0.14, post_h, 0.14), timber, Vector3(sx, deck_h + post_h * 0.5, sz));
    # the tent: a striped gable, ridge along x, overhanging the deck a little
    var tent_h:float = 0.7;
    var tent_z:float = -0.3;       # shifted back, so the counter and its goods stay open to the sky from the front
    var tent_d:float = deck.y - 0.3;
    var tent:PrismMesh = PrismMesh.new();
    tent.size = Vector3(deck.x + 0.5, tent_h, tent_d);
    b.set_roof(b._add_mesh(tent, _awning(Color(0.72, 0.2, 0.16), Color(0.93, 0.87, 0.7)), Vector3(0, deck_h + post_h + tent_h * 0.5, tent_z)));
    # the roof is a decor-less mesh so it shows while building; the rest hides until the post is finished
    var red:StandardMaterial3D = _colour(Color(0.72, 0.2, 0.16));
    _box(b, Vector3(deck.x + 0.5, 0.2, 0.05), red, Vector3(0, deck_h + post_h - 0.1, tent_z + tent_d * 0.5));       # valance
    _box(b, Vector3(deck.x + 0.5, 0.2, 0.05), red, Vector3(0, deck_h + post_h - 0.1, tent_z - tent_d * 0.5));
    # counter along the front, a cloth over it, a balance on top
    _box(b, Vector3(deck.x * 0.62, 0.62, 0.5), timber, Vector3(-deck.x * 0.1, deck_h + 0.31, hz - 0.35));
    _box(b, Vector3(deck.x * 0.62 + 0.1, 0.05, 0.6), _colour(Color(0.93, 0.87, 0.7)), Vector3(-deck.x * 0.1, deck_h + 0.64, hz - 0.35));
    var iron:StandardMaterial3D = _colour(IRON);
    var scale_at:Vector3 = Vector3(-deck.x * 0.2, deck_h + 0.66, hz - 0.35);
    _box(b, Vector3(0.05, 0.5, 0.05), iron, scale_at + Vector3(0, 0.25, 0));
    _box(b, Vector3(0.62, 0.04, 0.04), iron, scale_at + Vector3(0, 0.5, 0));
    for dx in [-0.28, 0.28]:
        _cyl(b, 0.12, 0.12, 0.025, _colour(Color(0.8, 0.65, 0.2)), scale_at + Vector3(dx, 0.3, 0), 12);
        _box(b, Vector3(0.01, 0.2, 0.01), iron, scale_at + Vector3(dx, 0.4, 0));
    # wares on the counter: fruit, loaves, a basket and a jug
    var top_y:float = deck_h + 0.7;
    var cx:float = -deck.x * 0.1;
    for i in 4:
        _ball(b, 0.1, _colour(Color(0.78, 0.2, 0.16) if i % 2 == 0 else Color(0.55, 0.7, 0.25)), Vector3(cx - 0.9 + i * 0.17, top_y + 0.08, hz - 0.3 + (i % 2) * 0.12), 1.0);
    _cyl(b, 0.2, 0.15, 0.16, _colour(Color(0.6, 0.45, 0.25)), Vector3(cx + 0.1, top_y + 0.1, hz - 0.35), 10);
    for i in 3:
        _ball(b, 0.09, _colour(Color(0.85, 0.65, 0.3)), Vector3(cx + 0.1 + (i - 1) * 0.1, top_y + 0.22, hz - 0.35 + (i % 2) * 0.05), 0.9);
    _box(b, Vector3(0.55, 0.12, 0.2), _colour(Color(0.8, 0.62, 0.3)), Vector3(cx + 0.75, top_y + 0.08, hz - 0.32));
    _box(b, Vector3(0.45, 0.1, 0.18), _colour(Color(0.85, 0.7, 0.4)), Vector3(cx + 0.78, top_y + 0.18, hz - 0.32));
    _cyl(b, 0.09, 0.11, 0.3, _colour(Color(0.5, 0.32, 0.2)), Vector3(cx + 1.2, top_y + 0.17, hz - 0.35), 10);
    # goods at the back: crates, barrels and sacks
    var crate:StandardMaterial3D = SurfaceTextures.material(&"planks", Color(0.82, 0.66, 0.42));
    _box(b, Vector3(0.62, 0.5, 0.55), crate, Vector3(-deck.x * 0.3, deck_h + 0.25, -hz + 0.45), Vector3(0, 0.15, 0));
    _box(b, Vector3(0.55, 0.5, 0.5), crate, Vector3(-deck.x * 0.3 + 0.7, deck_h + 0.25, -hz + 0.42), Vector3(0, -0.1, 0));
    _box(b, Vector3(0.5, 0.45, 0.45), crate, Vector3(-deck.x * 0.3 + 0.3, deck_h + 0.72, -hz + 0.42), Vector3(0, 0.35, 0));
    for i in 2:
        var bx:float = deck.x * 0.28 + i * 0.62;
        _cyl(b, 0.27, 0.3, 0.7, timber, Vector3(bx, deck_h + 0.35, -hz + 0.45), 12);
        for band in [0.18, 0.52]:
            _cyl(b, 0.305, 0.305, 0.05, iron, Vector3(bx, deck_h + band, -hz + 0.45), 12);
    var sack:StandardMaterial3D = _colour(Color(0.78, 0.7, 0.5));
    _ball(b, 0.26, sack, Vector3(deck.x * 0.3, deck_h + 0.2, hz - 0.45), 0.8);
    _ball(b, 0.22, sack, Vector3(deck.x * 0.3 + 0.45, deck_h + 0.17, hz - 0.35), 0.8);
    _ball(b, 0.2, _colour(Color(0.66, 0.5, 0.3)), Vector3(deck.x * 0.3 + 0.1, deck_h + 0.5, hz - 0.4), 0.8);
    # a banner on the ridge and a hanging sign on a bracket at the corner, with a coin on it
    var top:float = deck_h + post_h + tent_h;
    _box(b, Vector3(0.05, 0.7, 0.05), timber, Vector3(deck.x * 0.4, top + 0.3, 0));
    _box(b, Vector3(0.5, 0.3, 0.03), _colour(Color(0.72, 0.2, 0.16)), Vector3(deck.x * 0.4 + 0.27, top + 0.5, 0));
    var sx:float = -s.x * 0.5 - 0.1;
    _box(b, Vector3(0.1, 1.9, 0.1), timber, Vector3(sx, 0.95, s.y * 0.5 - 0.1));
    _box(b, Vector3(0.8, 0.07, 0.07), timber, Vector3(sx + 0.4, 1.8, s.y * 0.5 - 0.1));
    _box(b, Vector3(0.6, 0.5, 0.06), wood, Vector3(sx + 0.45, 1.45, s.y * 0.5 - 0.1));
    _cyl(b, 0.17, 0.17, 0.05, _colour(Color(0.85, 0.7, 0.2)), Vector3(sx + 0.45, 1.45, s.y * 0.5 - 0.06), 14, Vector3(PI * 0.5, 0, 0));
    # lanterns under the tent
    for lx in [-hx + 0.3, hx - 0.3]:
        _ball(b, 0.09, _colour(Color(1.0, 0.8, 0.4)), Vector3(lx, deck_h + post_h - 0.35, hz - 0.1), 1.2);

# --------------------------------
# Mine: a headframe with a winding wheel, a tunnel mouth in a rocky mound, rails with a cart and ore heaps.

static func mine_extras(b:Building) -> void:
    var s:Vector2 = Vector2(b.vsize);
    var timber:StandardMaterial3D = _colour(TIMBER);
    var hx:float = s.x * 0.27;
    var hz:float = -s.y * 0.12;
    for dz in [-0.5, 0.5]:
        for lean in [-1.0, 1.0]:
            _box(b, Vector3(0.14, 2.9, 0.14), timber, Vector3(hx + lean * 0.42, 1.4, hz + dz), Vector3(0, 0, -lean * 0.3));
    _box(b, Vector3(0.2, 0.2, 1.3), timber, Vector3(hx, 2.65, hz));
    _cyl(b, 0.42, 0.42, 0.1, _colour(IRON), Vector3(hx, 2.65, hz), 14, Vector3(PI * 0.5, 0, 0));
    _box(b, Vector3(0.06, 1.9, 0.06), _colour(IRON), Vector3(hx, 1.65, hz + 0.05));       # the rope
    var rock:StandardMaterial3D = SurfaceTextures.material(&"stone", Color(0.5, 0.47, 0.44));
    var ore:StandardMaterial3D = SurfaceTextures.material(&"stone", Color(0.62, 0.32, 0.22));
    var mound_at:Vector3 = Vector3(s.x * 0.02, 0.0, s.y * 0.26);
    _ball(b, 1.3, rock, mound_at, 0.75);
    _ball(b, 0.7, rock, mound_at + Vector3(-1.1, 0.0, 0.1), 0.7);
    _box(b, Vector3(0.6, 0.45, 0.5), rock, mound_at + Vector3(0.9, 0.2, -0.5), Vector3(0, 0.5, 0));
    var mouth:Vector3 = mound_at + Vector3(0, 0.5, 1.12);
    _box(b, Vector3(1.05, 0.95, 0.15), _colour(DARK), mouth);
    for sx in [-0.6, 0.6]:
        _box(b, Vector3(0.14, 1.1, 0.18), timber, mouth + Vector3(sx, 0.05, 0.02));
    _box(b, Vector3(1.4, 0.14, 0.2), timber, mouth + Vector3(0, 0.58, 0.02));
    for sx in [-0.28, 0.28]:
        _box(b, Vector3(0.06, 0.05, 1.5), _colour(IRON), Vector3(mouth.x + sx, 0.04, mouth.z + 0.9));
    _box(b, Vector3(0.55, 0.3, 0.4), timber, Vector3(mouth.x, 0.28, mouth.z + 1.1));
    _ball(b, 0.2, ore, Vector3(mouth.x, 0.46, mouth.z + 1.1), 0.7);
    _ball(b, 0.5, ore, Vector3(-s.x * 0.36, 0.0, s.y * 0.2), 0.8);       # iron ore heap
    _ball(b, 0.62, rock, Vector3(-s.x * 0.28, 0.0, s.y * 0.38), 0.7);                                 # stone heap

# --------------------------------
# Extras on house-shaped buildings, chosen by the def's "decor" key.

static func decorate(b:Building, kind:String) -> void:
    var s:Vector2 = Vector2(b.vsize);
    var body:Vector2 = s - Vector2(0.5, 0.5);
    var h:float = b.def.get("height", 2.0);
    var front:float = body.y * 0.5;
    match kind:
        "forge":
            var stone:StandardMaterial3D = SurfaceTextures.material(&"stone", Color(0.34, 0.32, 0.32));
            var top:float = h + 2.0;
            _box(b, Vector3(0.75, top, 0.75), stone, Vector3(s.x * 0.2, top * 0.5, -s.y * 0.18));
            _box(b, Vector3(0.95, 0.18, 0.95), _colour(IRON), Vector3(s.x * 0.2, top + 0.05, -s.y * 0.18));
            var glow:StandardMaterial3D = _colour(Color(1.0, 0.5, 0.15));
            glow.emission_enabled = true;
            glow.emission = Color(1.0, 0.45, 0.1);
            glow.emission_energy_multiplier = 0.9;
            _box(b, Vector3(0.6, 0.4, 0.04), glow, Vector3(-body.x * 0.25, 0.4, front + 0.09));
            _box(b, Vector3(0.9, 0.7, 0.14), _colour(DARK), Vector3(-body.x * 0.25, 0.4, front));
            _box(b, Vector3(0.45, 0.26, 0.24), _colour(IRON), Vector3(body.x * 0.3, 0.38, front + 0.5));
            _box(b, Vector3(0.22, 0.25, 0.2), _colour(IRON), Vector3(body.x * 0.3, 0.13, front + 0.5));
            _box(b, Vector3(0.75, 0.1, 0.4), _colour(Color(0.3, 0.3, 0.32)), Vector3(-body.x * 0.25, 0.05, front + 0.45));
        "school":
            var plaster:StandardMaterial3D = b._body_mat;
            var peak:float = h + h * b.def.get("roof_pitch", 0.55);
            _box(b, Vector3(0.9, 0.9, 0.9), plaster, Vector3(0, peak + 0.05, 0));
            var slit:StandardMaterial3D = _colour(DARK);
            for sx in [-1.0, 1.0]:
                _box(b, Vector3(0.05, 0.4, 0.28), slit, Vector3(sx * 0.46, peak + 0.2, 0));
                _box(b, Vector3(0.28, 0.4, 0.05), slit, Vector3(0, peak + 0.2, sx * 0.46));
            _ball(b, 0.1, _colour(Color(0.85, 0.65, 0.2)), Vector3(0, peak + 0.15, 0));
            _pyramid(b, 0.62, 0.7, _roof_mat(b), Vector3(0, peak + 0.5, 0));
            _box(b, Vector3(1.8, 0.12, 0.6), plaster, Vector3(0, 0.06, front + 0.3));
            _box(b, Vector3(1.0, 0.55, 0.05), _colour(Color(0.16, 0.3, 0.2)), Vector3(-body.x * 0.28, h * 0.58, front + 0.03));
        "wood":
            var bark:StandardMaterial3D = _colour(Color(0.42, 0.3, 0.19));
            var cut:StandardMaterial3D = _colour(Color(0.78, 0.62, 0.4));
            for row in 3:       # a stack of logs along the side wall, end grain facing out
                for k in 4 - row:
                    var lx:float = body.x * 0.5 + 0.3 + row * 0.2;
                    var ly:float = 0.17 + row * 0.3;
                    var lz:float = -body.y * 0.3 + (k + row * 0.5) * 0.36;
                    _cyl(b, 0.16, 0.16, 0.9, bark, Vector3(lx, ly, lz), 8, Vector3(0, 0, PI * 0.5));
                    _cyl(b, 0.13, 0.13, 0.02, cut, Vector3(lx + 0.46, ly, lz), 8, Vector3(0, 0, PI * 0.5));
            _cyl(b, 0.3, 0.32, 0.45, bark, Vector3(-body.x * 0.3, 0.22, front + 0.6), 10);
            _box(b, Vector3(0.06, 0.55, 0.06), _colour(TIMBER), Vector3(-body.x * 0.3 + 0.1, 0.72, front + 0.6), Vector3(0, 0, 0.5));
            _box(b, Vector3(0.22, 0.14, 0.05), _colour(IRON), Vector3(-body.x * 0.3 + 0.2, 0.95, front + 0.6), Vector3(0, 0, 0.5));
        "loom":
            var wood:StandardMaterial3D = _colour(Color(0.45, 0.32, 0.2));
            var dye:Array[Color] = [Color(0.3, 0.4, 0.75), Color(0.75, 0.3, 0.25), Color(0.85, 0.8, 0.65)];
            for sx in [-0.5, 0.5]:       # a loom standing outside: two posts, a beam and the cloth on it
                _box(b, Vector3(0.1, 1.3, 0.1), wood, Vector3(body.x * 0.5 + 0.7 + sx * 0.5, 0.65, front * 0.3));
            _box(b, Vector3(1.2, 0.1, 0.12), wood, Vector3(body.x * 0.5 + 0.7, 1.25, front * 0.3));
            _box(b, Vector3(0.85, 0.9, 0.04), _colour(dye[0]), Vector3(body.x * 0.5 + 0.7, 0.75, front * 0.3));
            for k in 3:       # bolts of finished cloth by the door
                _cyl(b, 0.14, 0.14, 0.5, _colour(dye[k]), Vector3(-body.x * 0.3 + k * 0.3, 0.14, front + 0.55), 8, Vector3(0, 0, PI * 0.5));
        "still":
            var copper:StandardMaterial3D = _colour(Color(0.72, 0.42, 0.2));
            var oak:StandardMaterial3D = _colour(Color(0.42, 0.3, 0.19));
            var hoop:StandardMaterial3D = _colour(IRON);
            var px:float = body.x * 0.5 + 0.55;       # a copper pot still outside: a belly, a neck, a pipe over to a barrel
            _ball(b, 0.5, copper, Vector3(px, 0.55, front * 0.2), 0.9);
            _cyl(b, 0.14, 0.25, 0.55, copper, Vector3(px, 1.2, front * 0.2), 10);
            _box(b, Vector3(0.7, 0.09, 0.09), copper, Vector3(px - 0.3, 1.5, front * 0.2));
            for k in 2:
                var bz:float = front * 0.2 + 0.2 + k * 0.62;
                _cyl(b, 0.26, 0.26, 0.5, oak, Vector3(px + 0.1, 0.25, bz + 0.45), 10);
                _cyl(b, 0.27, 0.27, 0.04, hoop, Vector3(px + 0.1, 0.12, bz + 0.45), 10);
                _cyl(b, 0.27, 0.27, 0.04, hoop, Vector3(px + 0.1, 0.38, bz + 0.45), 10);
        "kiln":
            var brick:StandardMaterial3D = _colour(Color(0.55, 0.3, 0.22));
            var clay:StandardMaterial3D = _colour(Color(0.74, 0.45, 0.3));
            var kx:float = body.x * 0.5 + 0.6;       # a domed kiln beside the workshop, and pots drying on a shelf
            _cyl(b, 0.55, 0.65, 0.7, brick, Vector3(kx, 0.35, -front * 0.1), 12);
            _ball(b, 0.55, brick, Vector3(kx, 0.7, -front * 0.1), 0.8);
            _cyl(b, 0.12, 0.14, 0.5, _colour(IRON), Vector3(kx, 1.35, -front * 0.1), 8);
            _box(b, Vector3(1.3, 0.08, 0.35), _colour(TIMBER), Vector3(-body.x * 0.25, 0.45, front + 0.45));
            for k in 3:
                _cyl(b, 0.1 + 0.02 * k, 0.07, 0.22 + 0.04 * k, clay, Vector3(-body.x * 0.25 - 0.4 + k * 0.4, 0.62 + 0.02 * k, front + 0.45), 8);
        "hives":
            var box:StandardMaterial3D = _colour(Color(0.86, 0.72, 0.38));
            var lid:StandardMaterial3D = _colour(Color(0.5, 0.36, 0.2));
            for k in 3:       # extra boxy hives on stands in front of the main one
                var hx:float = (k - 1) * 0.6;
                _box(b, Vector3(0.12, 0.2, 0.12), lid, Vector3(hx, 0.1, front + 0.5));
                _box(b, Vector3(0.42, 0.34, 0.42), box, Vector3(hx, 0.37, front + 0.5));
                _box(b, Vector3(0.48, 0.07, 0.48), lid, Vector3(hx, 0.58, front + 0.5));
        "shack":
            var plank:StandardMaterial3D = _colour(Color(0.5, 0.4, 0.28));
            for k in 3:       # spare boards leaning on the side wall
                _box(b, Vector3(0.14, 1.0, 0.03), plank, Vector3(-body.x * 0.5 - 0.22 - k * 0.05, 0.5, -body.y * 0.1 + k * 0.17), Vector3(0, 0, 0.32 + k * 0.05));
            _cyl(b, 0.2, 0.22, 0.45, _colour(Color(0.4, 0.3, 0.2)), Vector3(body.x * 0.5 + 0.28, 0.22, front * 0.4), 8);
            _cyl(b, 0.2, 0.2, 0.03, _colour(IRON), Vector3(body.x * 0.5 + 0.28, 0.45, front * 0.4), 8);
        "hut":
            var rack:StandardMaterial3D = _colour(TIMBER);
            var rz:float = front + 0.75;
            for sx in [-0.55, 0.55]:
                _box(b, Vector3(0.07, 1.1, 0.07), rack, Vector3(body.x * 0.12 + sx, 0.55, rz));
            _box(b, Vector3(1.25, 0.06, 0.06), rack, Vector3(body.x * 0.12, 1.05, rz));
            var cols:Array[Color] = [Color(0.75, 0.2, 0.2), Color(0.5, 0.45, 0.3), Color(0.35, 0.3, 0.2), Color(0.75, 0.2, 0.2)];
            for i in cols.size():
                _ball(b, 0.1, _colour(cols[i]), Vector3(body.x * 0.12 - 0.45 + i * 0.3, 0.9, rz), 1.3);
            var wicker:StandardMaterial3D = _colour(Color(0.55, 0.42, 0.22));
            _cyl(b, 0.24, 0.19, 0.26, wicker, Vector3(-body.x * 0.32, 0.13, front + 0.45), 10);
            _ball(b, 0.2, _colour(Color(0.72, 0.18, 0.2)), Vector3(-body.x * 0.32, 0.3, front + 0.45), 0.7);
            _cyl(b, 0.2, 0.16, 0.22, wicker, Vector3(-body.x * 0.32 - 0.5, 0.11, front + 0.7), 10);

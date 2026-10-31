# ----------------------------------------------------------------
# WaterTexture
#     The seamless noise the water shader reads, made in code (there are
#     no image assets): red and green are the slope of a smooth height
#     noise (the ripples' tilt, 0.5 = flat), blue is a second noise for
#     the foam.
# ----------------------------------------------------------------
class_name WaterTexture extends RefCounted;

const SIZE:int = 128;

static func make(world_seed:int = 1) -> ImageTexture:
    var height:FastNoiseLite = FastNoiseLite.new();
    height.seed = world_seed + 301;
    height.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;
    height.frequency = 0.05;
    height.fractal_octaves = 3;
    var foam:FastNoiseLite = FastNoiseLite.new();
    foam.seed = world_seed + 302;
    foam.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;
    foam.frequency = 0.07;
    foam.fractal_octaves = 2;
    var h:Image = height.get_seamless_image(SIZE, SIZE, false, false, 0.2);
    var f:Image = foam.get_seamless_image(SIZE, SIZE, false, false, 0.2);
    var img:Image = Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8);
    for y in SIZE:
        for x in SIZE:
            var dx:float = h.get_pixel((x + 1) % SIZE, y).r - h.get_pixel((x - 1 + SIZE) % SIZE, y).r;
            var dy:float = h.get_pixel(x, (y + 1) % SIZE).r - h.get_pixel(x, (y - 1 + SIZE) % SIZE).r;
            img.set_pixel(x, y, Color(clampf(0.5 + dx * 3.0, 0.0, 1.0), clampf(0.5 + dy * 3.0, 0.0, 1.0), f.get_pixel(x, y).r));
    img.generate_mipmaps();
    return ImageTexture.create_from_image(img);

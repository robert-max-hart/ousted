# ----------------------------------------------------------------
# TerrainTexture
#     The seamless noise the terrain shader reads, made in code (there are
#     no image assets): red a soft one for patches, green a finer one for
#     grain and rock bands, blue a third for the ragged edge of snow.
# ----------------------------------------------------------------
class_name TerrainTexture extends RefCounted;

const SIZE:int = 256;

static func make(world_seed:int = 1) -> ImageTexture:
    var channels:Array[Image] = [];
    var settings:Array = [[0.04, 3], [0.06, 2], [0.03, 3]];       # frequency and octaves of each channel
    for i in 3:
        var n:FastNoiseLite = FastNoiseLite.new();
        n.seed = world_seed + 401 + i * 17;
        n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;
        n.frequency = settings[i][0];
        n.fractal_octaves = settings[i][1];
        channels.append(n.get_seamless_image(SIZE, SIZE, false, false, 0.2));
    var img:Image = Image.create(SIZE, SIZE, true, Image.FORMAT_RGB8);
    for y in SIZE:
        for x in SIZE:
            img.set_pixel(x, y, Color(channels[0].get_pixel(x, y).r, channels[1].get_pixel(x, y).r, channels[2].get_pixel(x, y).r));
    img.generate_mipmaps();
    return ImageTexture.create_from_image(img);

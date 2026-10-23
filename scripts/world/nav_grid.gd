# ----------------------------------------------------------------
# NavGrid
#     Thin wrapper over AStarGrid2D. World decides what is solid and
#     how expensive each cell is (roads are cheap, forests slow).
# ----------------------------------------------------------------
class_name NavGrid extends RefCounted;

const NO_CELL:Vector2i = Vector2i(-1, -1);

var astar:AStarGrid2D;

func setup(size:int) -> void:
    astar = AStarGrid2D.new();
    astar.region = Rect2i(0, 0, size, size);
    astar.cell_size = Vector2.ONE;
    astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;
    astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE;
    astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE;
    astar.update();

func set_cell(c:Vector2i, solid:bool, weight:float) -> void:
    astar.set_point_solid(c, solid);
    astar.set_point_weight_scale(c, weight);

func is_walkable(c:Vector2i) -> bool:
    return astar.is_in_boundsv(c) and not astar.is_point_solid(c);

func find_path(from:Vector2i, to:Vector2i) -> Array[Vector2i]:
    if not is_walkable(from) or not is_walkable(to):
        return [];
    return astar.get_id_path(from, to);

# Closest walkable cell within max_r rings, or NO_CELL.
func nearest_walkable(c:Vector2i, max_r:int) -> Vector2i:
    if is_walkable(c):
        return c;
    for r in range(1, max_r + 1):
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if absi(dx) != r and absi(dz) != r:
                    continue;
                var n:Vector2i = c + Vector2i(dx, dz);
                if is_walkable(n):
                    return n;
    return NO_CELL;

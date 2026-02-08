extends Node3D

@export var chunk_scene: PackedScene
var noise := FastNoiseLite.new()

# Dictionary storing chunks by chunk coordinate
var loaded_chunks := {}   # Dictionary: Vector2i -> Chunk

const Chunk = preload("res://chunk.gd")
const CHUNK_SIZE = Vector3i(16, 384, 16)

func _ready():
	noise.seed = randi()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM


func _process(_delta):
	var sliderval = $Player/PauseMenu/settingsarea/renderdistance.value
	var player_pos = $Player.global_position

	var cx = int(floor(player_pos.x / Chunk.CHUNK_SIZE.x))
	var cz = int(floor(player_pos.z / Chunk.CHUNK_SIZE.z))
	var render_distance = sliderval

	for x in range(cx - render_distance, cx + render_distance + 1):
		for z in range(cz - render_distance, cz + render_distance + 1):
			var key = Vector2i(x, z)
			if not loaded_chunks.has(key):
				spawn_chunk(x, z)

	# ------------------------------
	# CHUNK UNLOADING
	# ------------------------------

	var chunks_to_unload: Array = []

	for key in loaded_chunks.keys():
		var chunk_pos: Vector2i = key
		var dx = chunk_pos.x - cx
		var dz = chunk_pos.y - cz

		if abs(dx) > render_distance or abs(dz) > render_distance:
			chunks_to_unload.append(chunk_pos)

	for key in chunks_to_unload:
		var chunk = loaded_chunks[key]
		if chunk:
			chunk.queue_free()
		loaded_chunks.erase(key)

# ---------------------------------------------------------
#  CHUNK SPAWNING + REGISTRATION
# ---------------------------------------------------------

func spawn_chunk(cx, cz):
	var chunk = chunk_scene.instantiate()
	chunk.chunk_x = cx
	chunk.chunk_z = cz
	chunk.world_noise = noise
	chunk.world = self

	chunk.position = Vector3(cx * CHUNK_SIZE.x, 0, cz * CHUNK_SIZE.z)
	add_child(chunk)

	loaded_chunks[Vector2i(cx, cz)] = chunk

	# build mesh immediately (sync)
	chunk.build_mesh()

# ---------------------------------------------------------
#  CHUNK LOOKUP
# ---------------------------------------------------------

func get_chunk(cx: int, cz: int):
	return loaded_chunks.get(Vector2i(cx, cz), null)

# ---------------------------------------------------------
#  WORLD-LEVEL BLOCK PLACEMENT (GLOBAL COORDS)
# ---------------------------------------------------------

func set_block(global_x: int, global_y: int, global_z: int, block_type: int):
	# Convert world coords → chunk coords
	var cx = floori(float(global_x) / CHUNK_SIZE.x)
	var cz = floori(float(global_z) / CHUNK_SIZE.z)

	var chunk = get_chunk(cx, cz)
	if chunk == null:
		return  # Optionally: generate chunk here

	# Convert world coords → local chunk coords (0..CHUNK_SIZE-1)
	var local_x = global_x - cx * CHUNK_SIZE.x
	var local_y = global_y
	var local_z = global_z - cz * CHUNK_SIZE.z

	# Safety: if somehow out of bounds, bail
	if local_x < 0 or local_x >= CHUNK_SIZE.x:
		return
	if local_y < 0 or local_y >= CHUNK_SIZE.y:
		return
	if local_z < 0 or local_z >= CHUNK_SIZE.z:
		return

	chunk.place_block_at(local_x, local_y, local_z, block_type)

func get_block(global_x: int, global_y: int, global_z: int) -> int:
	var cx = floori(float(global_x) / CHUNK_SIZE.x)
	var cz = floori(float(global_z) / CHUNK_SIZE.z)

	var chunk = get_chunk(cx, cz)
	if chunk == null:
		return 0  # treat missing chunks as air

	var local_x = global_x - cx * CHUNK_SIZE.x
	var local_y = global_y
	var local_z = global_z - cz * CHUNK_SIZE.z

	if local_x < 0 or local_x >= CHUNK_SIZE.x: return 0
	if local_y < 0 or local_y >= CHUNK_SIZE.y: return 0
	if local_z < 0 or local_z >= CHUNK_SIZE.z: return 0

	return chunk.blocks[local_x][local_z][local_y]

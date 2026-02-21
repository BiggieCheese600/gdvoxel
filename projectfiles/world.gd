extends Node3D

const CHUNK_SCENE: PackedScene = preload("res://Chunk.tscn")
const CHUNK_SIZE := Vector3i(16, 384, 16)

var noise := FastNoiseLite.new()

var loaded_chunks: Dictionary = {}      # Vector2i -> Chunk
var unloading_chunks: Array = []        # Chunks that are in async unload

var mesh_commits_per_frame := 1
var unloads_per_frame := 2

# --- water ---
var water_update_queue: Array = []
var water_updates_per_frame := 256      # increased for stability


func _ready() -> void:
	noise.seed = randi()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM


func _process(_delta: float) -> void:
	var sliderval: int = $Player/PauseMenu/settingsarea/renderdistance.value
	var player_pos: Vector3 = $Player.global_position

	var cx := int(floor(player_pos.x / CHUNK_SIZE.x))
	var cz := int(floor(player_pos.z / CHUNK_SIZE.z))
	var render_distance := sliderval

	# ------------------------------
	# CHUNK LOADING
	# ------------------------------
	for x in range(cx - render_distance, cx + render_distance + 1):
		for z in range(cz - render_distance, cz + render_distance + 1):
			var key := Vector2i(x, z)
			if not loaded_chunks.has(key):
				spawn_chunk(x, z)

	# ------------------------------
	# CHUNK UNLOADING (async)
	# ------------------------------
	var chunks_to_unload: Array = []

	for key in loaded_chunks.keys():
		var chunk_pos: Vector2i = key
		var dx := chunk_pos.x - cx
		var dz := chunk_pos.y - cz

		if abs(dx) > render_distance or abs(dz) > render_distance:
			chunks_to_unload.append(chunk_pos)

	for key in chunks_to_unload:
		var chunk = loaded_chunks[key]
		if chunk and not chunk.unloading:
			chunk.start_unload_async()
			unloading_chunks.append(chunk)
		loaded_chunks.erase(key)

	process_blockgen()
	process_mesh_commits()
	process_unloads()
	process_water_updates()


# ---------------------------------------------------------
#  CHUNK SPAWNING + REGISTRATION
# ---------------------------------------------------------

func spawn_chunk(cx: int, cz: int) -> void:
	var chunk = CHUNK_SCENE.instantiate()
	chunk.chunk_x = cx
	chunk.chunk_z = cz
	chunk.world_noise = noise
	chunk.world = self

	chunk.position = Vector3(cx * CHUNK_SIZE.x, 0, cz * CHUNK_SIZE.z)
	add_child(chunk)

	loaded_chunks[Vector2i(cx, cz)] = chunk

	chunk.start_blockgen_async()


# ---------------------------------------------------------
#  PROCESS ASYNC BLOCK GENERATION
# ---------------------------------------------------------

func process_blockgen() -> void:
	for chunk in loaded_chunks.values():
		if chunk.blockgen_ready and not chunk.mesh_started:
			chunk.start_mesh_async()
			chunk.blockgen_ready = false


# ---------------------------------------------------------
#  PROCESS ASYNC MESH COMMITS (LIMITED PER FRAME)
# ---------------------------------------------------------

func process_mesh_commits() -> void:
	var remaining := mesh_commits_per_frame
	if remaining <= 0:
		return

	for chunk in loaded_chunks.values():
		if remaining <= 0:
			break
		if chunk.mesh_ready:
			chunk.apply_pending_mesh()
			remaining -= 1


# ---------------------------------------------------------
#  PROCESS ASYNC UNLOADS (LIMITED PER FRAME)
# ---------------------------------------------------------

func process_unloads() -> void:
	if unloading_chunks.is_empty():
		return

	var remaining := unloads_per_frame
	if remaining <= 0:
		return

	var to_check := unloading_chunks.duplicate()
	for chunk in to_check:
		if remaining <= 0:
			break

		if not is_instance_valid(chunk):
			unloading_chunks.erase(chunk)
			continue

		if chunk.unload_ready:
			chunk.queue_free()
			unloading_chunks.erase(chunk)
			remaining -= 1


# ---------------------------------------------------------
#  CHUNK LOOKUP
# ---------------------------------------------------------

func get_chunk(cx: int, cz: int):
	return loaded_chunks.get(Vector2i(cx, cz), null)


# ---------------------------------------------------------
#  WORLD-LEVEL BLOCK ACCESS (GLOBAL COORDS)
# ---------------------------------------------------------

func get_block(global_x: int, global_y: int, global_z: int) -> int:
	var cx := floori(float(global_x) / CHUNK_SIZE.x)
	var cz := floori(float(global_z) / CHUNK_SIZE.z)

	var chunk = get_chunk(cx, cz)
	if chunk == null:
		return 0

	if chunk.blocks.is_empty():
		return 0

	var local_x := global_x - cx * CHUNK_SIZE.x
	var local_y := global_y
	var local_z := global_z - cz * CHUNK_SIZE.z

	if local_x < 0 or local_x >= CHUNK_SIZE.x:
		return 0
	if local_z < 0 or local_z >= CHUNK_SIZE.z:
		return 0
	if local_y < 0 or local_y >= CHUNK_SIZE.y:
		return 0

	if local_x >= chunk.blocks.size():
		return 0
	if local_z >= chunk.blocks[local_x].size():
		return 0
	if local_y >= chunk.blocks[local_x][local_z].size():
		return 0

	var val = chunk.blocks[local_x][local_z][local_y]
	if typeof(val) != TYPE_INT:
		return 0

	return val


func get_water_level(global_x: int, global_y: int, global_z: int) -> int:
	var cx: int = floori(float(global_x) / CHUNK_SIZE.x)
	var cz: int = floori(float(global_z) / CHUNK_SIZE.z)

	var chunk = get_chunk(cx, cz)
	if chunk == null:
		return 8

	if chunk.water_level.is_empty():
		return 8

	var local_x: int = global_x - cx * CHUNK_SIZE.x
	var local_y: int = global_y
	var local_z: int = global_z - cz * CHUNK_SIZE.z

	if local_x < 0 or local_x >= CHUNK_SIZE.x:
		return 8
	if local_z < 0 or local_z >= CHUNK_SIZE.z:
		return 8
	if local_y < 0 or local_y >= CHUNK_SIZE.y:
		return 8

	if local_x >= chunk.water_level.size():
		return 8
	if local_z >= chunk.water_level[local_x].size():
		return 8
	if local_y >= chunk.water_level[local_x][local_z].size():
		return 8

	var lvl = chunk.water_level[local_x][local_z][local_y]
	if typeof(lvl) != TYPE_INT:
		return 8

	return lvl


# ---------------------------------------------------------
#  BLOCK SETTING + WATER TRIGGERS
# ---------------------------------------------------------

func set_block(global_x: int, global_y: int, global_z: int, block_type: int, level: int = 0) -> void:
	var cx := floori(float(global_x) / CHUNK_SIZE.x)
	var cz := floori(float(global_z) / CHUNK_SIZE.z)

	var chunk = get_chunk(cx, cz)
	if chunk == null:
		return

	if chunk.blocks.is_empty():
		return

	var local_x := global_x - cx * CHUNK_SIZE.x
	var local_y := global_y
	var local_z := global_z - cz * CHUNK_SIZE.z

	if local_x < 0 or local_x >= CHUNK_SIZE.x:
		return
	if local_y < 0 or local_y >= CHUNK_SIZE.y:
		return
	if local_z < 0 or local_z >= CHUNK_SIZE.z:
		return

	if block_type == 6:
		chunk.blocks[local_x][local_z][local_y] = 6
		chunk.water_level[local_x][local_z][local_y] = level
		schedule_water_update(global_x, global_y, global_z)
	else:
		chunk.blocks[local_x][local_z][local_y] = block_type
		chunk.water_level[local_x][local_z][local_y] = 8
		schedule_neighbor_water_updates(global_x, global_y, global_z)

	chunk.rebuild_mesh()


# ---------------------------------------------------------
#  WATER SYSTEM (MINECRAFT-STYLE LEVELS)
# ---------------------------------------------------------

func schedule_water_update(x: int, y: int, z: int) -> void:
	var pos := Vector3i(x, y, z)

	# dedupe
	if pos in water_update_queue:
		return

	water_update_queue.append(pos)

	# hard cap
	if water_update_queue.size() > 5000:
		water_update_queue.resize(5000)


func schedule_neighbor_water_updates(x: int, y: int, z: int) -> void:
	var dirs := [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0),
		Vector3i(0, -1, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1)
	]

	for d in dirs:
		var nx: int = x + d.x
		var ny: int = y + d.y
		var nz: int = z + d.z
		if get_block(nx, ny, nz) == 6:
			schedule_water_update(nx, ny, nz)


func process_water_updates() -> void:
	var count := water_updates_per_frame

	while count > 0 and water_update_queue.size() > 0:
		var pos: Vector3i = water_update_queue.pop_front()
		update_water_at(pos.x, pos.y, pos.z)
		count -= 1


func update_water_at(x: int, y: int, z: int) -> void:
	# failsafe against storms
	if water_update_queue.size() > 20000:
		return

	if y < 0 or y >= CHUNK_SIZE.y:
		return

	var current := get_block(x, y, z)
	if current != 6:
		return

	var level := get_water_level(x, y, z)
	if level >= 8:
		return

	# 1. Downward flow
	if get_block(x, y - 1, z) == 0:
		set_block(x, y - 1, z, 6, 0)
		schedule_water_update(x, y - 1, z)
		return

	# 2. Sideways flow (throttled)
	var dirs := [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1)
	]

	for d in dirs:
		# throttle sideways spread
		if randi() % 2 == 0:
			continue

		var nx: int = x + d.x
		var ny: int = y
		var nz: int = z + d.z

		var neighbor_block := get_block(nx, ny, nz)
		var neighbor_level := get_water_level(nx, ny, nz)

		if neighbor_block == 0:
			if level + 1 < 8:
				set_block(nx, ny, nz, 6, level + 1)
				schedule_water_update(nx, ny, nz)
		elif neighbor_block == 6 and neighbor_level > level + 1 and level + 1 < 8:
			set_block(nx, ny, nz, 6, level + 1)
			schedule_water_update(nx, ny, nz)

	# 3. Dry up if isolated
	var lowest := 8
	for d in dirs:
		var nx2: int = x + d.x
		var ny2: int = y
		var nz2: int = z + d.z
		var nl := get_water_level(nx2, ny2, nz2)
		if nl < lowest:
			lowest = nl

	if lowest >= level and level > 0:
		set_block(x, y, z, 0)

extends StaticBody3D

const CHUNK_SIZE := Vector3i(16, 384, 16)

const BLOCKS := {
	0: { "name": "air",   "atlas_index": -1 },
	1: { "name": "grass", "atlas_index": 0 },
	2: { "name": "grassside", "atlas_index": 1},
	3: { "name": "dirt",  "atlas_index": 2 },
	4: { "name": "stone", "atlas_index": 3 },
	5: { "name": "sand", "atlas_index": 4 },
	6: { "name": "water", "atlas_index": 5 },
}

const WATER_LEVEL := 129.0

var blocks: Array = []
var water_level: Array = []

var world_noise: FastNoiseLite
var world

@export var atlas: Texture2D
@export var atlas_material: StandardMaterial3D
@export var tile_size := Vector2(16, 16)

@export var chunk_x: int = 0
@export var chunk_z: int = 0

var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D

var blockgen_ready: bool = false
var mesh_started: bool = false
var mesh_ready: bool = false
var _pending_mesh_data: Dictionary = {}

var unloading: bool = false
var unload_ready: bool = false


func _ready() -> void:
	if blocks.is_empty() and world_noise != null and not mesh_started:
		generate_block_data()
		build_mesh()


# ---------------------------------------------------------
#  WATER CORNER HEIGHT HELPER
# ---------------------------------------------------------

func _water_corner_height(world, wx: int, wy: int, wz: int, dx: int, dz: int) -> float:
	var nx: int = wx + dx
	var nz: int = wz + dz
	var nl: int = world.get_water_level(nx, wy, nz)

	if nl == 8:
		return 0.0

	return 1.0 - float(nl) / 8.0


# ---------------------------------------------------------
#  BLOCK GENERATION
# ---------------------------------------------------------

func generate_block_data() -> void:
	blocks.resize(CHUNK_SIZE.x)
	water_level.resize(CHUNK_SIZE.x)

	for x in range(CHUNK_SIZE.x):
		blocks[x] = []
		water_level[x] = []
		blocks[x].resize(CHUNK_SIZE.z)
		water_level[x].resize(CHUNK_SIZE.z)

		for z in range(CHUNK_SIZE.z):
			blocks[x][z] = []
			water_level[x][z] = []
			blocks[x][z].resize(CHUNK_SIZE.y)
			water_level[x][z].resize(CHUNK_SIZE.y)

	for x in range(CHUNK_SIZE.x):
		for z in range(CHUNK_SIZE.z):
			var world_x := chunk_x * CHUNK_SIZE.x + x
			var world_z := chunk_z * CHUNK_SIZE.z + z

			var raw := world_noise.get_noise_2d(world_x, world_z)
			var height := int((raw + 7.0) * 0.099 * CHUNK_SIZE.y / 2)
			height = clamp(height, 0, CHUNK_SIZE.y - 1)

			for y in range(CHUNK_SIZE.y):
				if y > height:
					if y <= WATER_LEVEL:
						blocks[x][z][y] = 6
						water_level[x][z][y] = 0
					else:
						blocks[x][z][y] = 0
						water_level[x][z][y] = 8
				elif y == height:
					blocks[x][z][y] = 1
					water_level[x][z][y] = 8
				elif y >= height - 2:
					blocks[x][z][y] = 3
					water_level[x][z][y] = 8
				else:
					blocks[x][z][y] = 4
					water_level[x][z][y] = 8


func start_blockgen_async() -> void:
	blockgen_ready = false
	mesh_started = false
	WorkerThreadPool.add_task(func(): _blockgen_job(), true)


func _blockgen_job() -> void:
	generate_block_data()
	blockgen_ready = true


# ---------------------------------------------------------
#  ASYNC MESH BUILD
# ---------------------------------------------------------

func start_mesh_async() -> void:
	if mesh_started:
		return
	mesh_started = true
	mesh_ready = false
	_pending_mesh_data.clear()
	WorkerThreadPool.add_task(func(): _mesh_build_job(), true)


func _mesh_build_job() -> void:
	var data := build_mesh_arrays_only()
	_pending_mesh_data = data
	mesh_ready = true


func apply_pending_mesh() -> void:
	if not mesh_ready:
		return
	apply_mesh(_pending_mesh_data)
	mesh_ready = false
	_pending_mesh_data.clear()


func build_mesh() -> void:
	var mesh_data := build_mesh_arrays_only()
	apply_mesh(mesh_data)


func build_mesh_arrays_only() -> Dictionary:
	var st_visual := SurfaceTool.new()
	var st_collision := SurfaceTool.new()

	st_visual.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_collision.begin(Mesh.PRIMITIVE_TRIANGLES)

	for x in range(CHUNK_SIZE.x):
		for y in range(CHUNK_SIZE.y):
			for z in range(CHUNK_SIZE.z):
				var block_type: int = blocks[x][z][y]
				if block_type == 0:
					continue

				add_block_faces(st_visual, x, y, z)

				if block_type != 6:
					add_block_faces(st_collision, x, y, z)

	return {
		"visual": st_visual.commit(),
		"collision": st_collision.commit()
	}


func apply_mesh(mesh_data: Dictionary) -> void:
	if mesh_instance and is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	if collision_shape and is_instance_valid(collision_shape):
		collision_shape.queue_free()

	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh_data.visual
	mesh_instance.material_override = atlas_material
	add_child(mesh_instance)

	collision_shape = CollisionShape3D.new()
	collision_shape.shape = mesh_data.collision.create_trimesh_shape()
	add_child(collision_shape)

# ---------------------------------------------------------
#  ASYNC UNLOAD
# ---------------------------------------------------------

func start_unload_async() -> void:
	if unloading:
		return
	unloading = true
	unload_ready = false
	WorkerThreadPool.add_task(func(): _unload_job(), true)


func _unload_job() -> void:
	unload_ready = true

# ---------------------------------------------------------
#  WATER MESH (SLOPED TOP + SLOPED SIDES)
# ---------------------------------------------------------

func add_water_top_face(st: SurfaceTool, pos: Vector3, x: int, y: int, z: int) -> Dictionary:
	var wx := chunk_x * CHUNK_SIZE.x + x
	var wy := y
	var wz := chunk_z * CHUNK_SIZE.z + z

	var level: int = world.get_water_level(wx, wy, wz)

	# Source block = flat top
	if level == 0:
		add_face(st, pos, Vector3.UP, 6)
		return {
			"tl": 1.0,
			"tr": 1.0,
			"bl": 1.0,
			"br": 1.0
		}

	# Flowing block = sloped top
	var h_tl := _water_corner_height(world, wx, wy, wz, 0, 0)
	var h_tr := _water_corner_height(world, wx, wy, wz, 1, 0)
	var h_bl := _water_corner_height(world, wx, wy, wz, 0, 1)
	var h_br := _water_corner_height(world, wx, wy, wz, 1, 1)

	var x0 := pos.x
	var x1 := pos.x + 1
	var z0 := pos.z
	var z1 := pos.z + 1
	var y0 := pos.y

	var v_tl := Vector3(x0, y0 + h_tl, z0)
	var v_tr := Vector3(x1, y0 + h_tr, z0)
	var v_bl := Vector3(x0, y0 + h_bl, z1)
	var v_br := Vector3(x1, y0 + h_br, z1)

	var uv := get_uv_rect(BLOCKS[6]["atlas_index"])

	_tri(st, v_tl, v_tr, v_br, uv.position, uv.position + Vector2(uv.size.x, 0), uv.position + uv.size, Vector3.UP)
	_tri(st, v_br, v_bl, v_tl, uv.position + uv.size, uv.position + Vector2(0, uv.size.y), uv.position, Vector3.UP)

	return {
		"tl": h_tl,
		"tr": h_tr,
		"bl": h_bl,
		"br": h_br
	}


# ---------------------------------------------------------
#  SLOPED WATER SIDE FACES
# ---------------------------------------------------------

func add_water_side_face(
	st: SurfaceTool,
	pos: Vector3,
	normal: Vector3,
	h1: float,
	h2: float
) -> void:
	var x := pos.x
	var y := pos.y
	var z := pos.z

	var uv := get_uv_rect(BLOCKS[6]["atlas_index"])
	var uv_tl = uv.position
	var uv_tr = uv.position + Vector2(uv.size.x, 0)
	var uv_br = uv.position + uv.size
	var uv_bl = uv.position + Vector2(0, uv.size.y)

	var b1 := Vector3()
	var b2 := Vector3()
	var t1 := Vector3()
	var t2 := Vector3()

	match normal:

		# -------------------------------------------------
		# X+ (RIGHT) — CCW pattern A
		# -------------------------------------------------
		Vector3.RIGHT:
			b1 = Vector3(x+1, y,   z)
			b2 = Vector3(x+1, y,   z+1)
			t1 = Vector3(x+1, y+h1, z)
			t2 = Vector3(x+1, y+h2, z+1)

			_tri(st, b1, b2, t2, uv_bl, uv_tl, uv_tr, normal)
			_tri(st, t2, t1, b1, uv_tr, uv_br, uv_bl, normal)
			return

		# -------------------------------------------------
		# X- (LEFT) — CCW pattern A
		# -------------------------------------------------
		Vector3.LEFT:
			b1 = Vector3(x, y,   z+1)
			b2 = Vector3(x, y,   z)
			t1 = Vector3(x, y+h2, z+1)
			t2 = Vector3(x, y+h1, z)

			_tri(st, b1, b2, t2, uv_bl, uv_tl, uv_tr, normal)
			_tri(st, t2, t1, b1, uv_tr, uv_br, uv_bl, normal)
			return

		# -------------------------------------------------
		# Z+ (FORWARD) — CCW pattern B (different!)
		# -------------------------------------------------
		Vector3.FORWARD:
			b1 = Vector3(x,   y, z+1)
			b2 = Vector3(x+1, y, z+1)
			t1 = Vector3(x,   y+h1, z+1)
			t2 = Vector3(x+1, y+h2, z+1)

			_tri(st, b2, b1, t1, uv_bl, uv_tl, uv_tr, normal)
			_tri(st, t1, t2, b2, uv_tr, uv_br, uv_bl, normal)
			return

		# -------------------------------------------------
		# Z- (BACK) — CCW pattern B (different!)
		# -------------------------------------------------
		Vector3.BACK:
			b1 = Vector3(x+1, y, z)
			b2 = Vector3(x,   y, z)
			t1 = Vector3(x+1, y+h2, z)
			t2 = Vector3(x,   y+h1, z)

			_tri(st, b2, b1, t1, uv_bl, uv_tl, uv_tr, normal)
			_tri(st, t1, t2, b2, uv_tr, uv_br, uv_bl, normal)
			return

# ---------------------------------------------------------
#  TRANSPARENCY + AIR HELPERS
# ---------------------------------------------------------

func is_air_local(x: int, y: int, z: int) -> bool:
	if x < 0 or x >= CHUNK_SIZE.x: return true
	if y < 0 or y >= CHUNK_SIZE.y: return true
	if z < 0 or z >= CHUNK_SIZE.z: return true
	return blocks[x][z][y] == 0


func is_air_global(wx: int, wy: int, wz: int) -> bool:
	return world.get_block(wx, wy, wz) == 0


func is_transparent_local(x: int, y: int, z: int) -> bool:
	if x < 0 or x >= CHUNK_SIZE.x: return true
	if y < 0 or y >= CHUNK_SIZE.y: return true
	if z < 0 or z >= CHUNK_SIZE.z: return true

	var t: int = blocks[x][z][y]
	return t == 0 or t == 6   # air or water


func is_transparent_global(wx: int, wy: int, wz: int) -> bool:
	var t: int = world.get_block(wx, wy, wz)
	return t == 0 or t == 6   # air or water

# ---------------------------------------------------------
#  BLOCK FACE LOGIC (WATER + SOLIDS)
# ---------------------------------------------------------

func add_block_faces(st: SurfaceTool, x: int, y: int, z: int) -> void:
	var pos := Vector3(x, y, z)
	var block_type: int = blocks[x][z][y]

	var wx := chunk_x * CHUNK_SIZE.x + x
	var wy := y
	var wz := chunk_z * CHUNK_SIZE.z + z

	# -------------------------
	# WATER BLOCK
	# -------------------------
	if block_type == 6:
		var h := add_water_top_face(st, pos, x, y, z)

		# RIGHT (+X)
		if is_transparent_local(x + 1, y, z):
			add_water_side_face(st, pos, Vector3.RIGHT, h["tr"], h["br"])

		# LEFT (-X)
		if is_transparent_local(x - 1, y, z):
			add_water_side_face(st, pos, Vector3.LEFT, h["tl"], h["bl"])

		# FORWARD (+Z)  (toward player)
		if is_transparent_local(x, y, z + 1):
			add_water_side_face(st, pos, Vector3.FORWARD, h["bl"], h["br"])

		# BACK (-Z)
		if is_transparent_local(x, y, z - 1):
			add_water_side_face(st, pos, Vector3.BACK, h["tl"], h["tr"])

		return

	# -------------------------
	# SOLID BLOCKS
	# -------------------------

	var top_type := block_type
	var bottom_type := block_type
	var side_type := block_type

	if block_type == 1:
		side_type = 2
		bottom_type = 3

	if x + 1 < CHUNK_SIZE.x:
		if is_transparent_local(x + 1, y, z):
			add_face(st, pos, Vector3.RIGHT, side_type)
	else:
		if is_transparent_global(wx + 1, wy, wz):
			add_face(st, pos, Vector3.RIGHT, side_type)

	if x - 1 >= 0:
		if is_transparent_local(x - 1, y, z):
			add_face(st, pos, Vector3.LEFT, side_type)
	else:
		if is_transparent_global(wx - 1, wy, wz):
			add_face(st, pos, Vector3.LEFT, side_type)

	if y + 1 < CHUNK_SIZE.y:
		if is_transparent_local(x, y + 1, z):
			add_face(st, pos, Vector3.UP, top_type)
	else:
		if is_transparent_global(wx, wy + 1, wz):
			add_face(st, pos, Vector3.UP, top_type)

	if y - 1 >= 0:
		if is_transparent_local(x, y - 1, z):
			add_face(st, pos, Vector3.DOWN, bottom_type)
	else:
		if is_transparent_global(wx, wy - 1, wz):
			add_face(st, pos, Vector3.DOWN, bottom_type)

	if z + 1 < CHUNK_SIZE.z:
		if is_transparent_local(x, y, z + 1):
			add_face(st, pos, Vector3.FORWARD, side_type)
	else:
		if is_transparent_global(wx, wy, wz + 1):
			add_face(st, pos, Vector3.FORWARD, side_type)

	if z - 1 >= 0:
		if is_transparent_local(x, y, z - 1):
			add_face(st, pos, Vector3.BACK, side_type)
	else:
		if is_transparent_global(wx, wy, wz - 1):
			add_face(st, pos, Vector3.BACK, side_type)

# ---------------------------------------------------------
#  UV + TRI HELPERS
# ---------------------------------------------------------

func get_uv_rect(atlas_index: int) -> Rect2:
	if atlas_index < 0:
		return Rect2()

	var atlas_size := atlas.get_size()
	var tiles_x := int(atlas_size.x / tile_size.x)
	var tiles_y := int(atlas_size.y / tile_size.y)

	var tile_x := atlas_index % tiles_x
	var tile_y := atlas_index / tiles_x

	tile_y = tiles_y - 1 - tile_y

	var uv_x := float(tile_x * tile_size.x) / atlas_size.x
	var uv_y := float(tile_y * tile_size.y) / atlas_size.y
	var uv_w := float(tile_size.x) / atlas_size.x
	var uv_h := float(tile_size.y) / atlas_size.y

	return Rect2(uv_x, uv_y, uv_w, uv_h)


func rotate_uv(uv_rect: Rect2, rotation_degrees: int) -> Dictionary:
	var tl := uv_rect.position
	var tr := uv_rect.position + Vector2(uv_rect.size.x, 0)
	var br := uv_rect.position + uv_rect.size
	var bl := uv_rect.position + Vector2(0, uv_rect.size.y)

	match rotation_degrees:
		0:
			return { "tl": tl, "tr": tr, "br": br, "bl": bl }

		90, -270:
			return { "tl": bl, "tr": tl, "br": tr, "bl": br }

		180, -180:
			return { "tl": br, "tr": bl, "br": tl, "bl": tr }

		270, -90:
			return { "tl": tr, "tr": br, "br": bl, "bl": tl }

	return { "tl": tl, "tr": tr, "br": br, "bl": bl }


func _tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	uva: Vector2,
	uvb: Vector2,
	uvc: Vector2,
	normal: Vector3
) -> void:
	st.set_normal(normal)
	st.set_uv(uva)
	st.add_vertex(a)

	st.set_normal(normal)
	st.set_uv(uvb)
	st.add_vertex(b)

	st.set_normal(normal)
	st.set_uv(uvc)
	st.add_vertex(c)

# ---------------------------------------------------------
#  SOLID BLOCK FACE BUILDER
# ---------------------------------------------------------

func add_face(st: SurfaceTool, pos: Vector3, normal: Vector3, block_type: int) -> void:
	var atlas_index: int = BLOCKS[block_type]["atlas_index"]
	var uv_rect := get_uv_rect(atlas_index)

	var rotation := 0

	match normal:
		Vector3.FORWARD: rotation = 90
		Vector3.RIGHT: rotation = 180
		Vector3.BACK: rotation = 180
		Vector3.LEFT: rotation = 90
		Vector3.UP: rotation = 0
		Vector3.DOWN: rotation = 0

	var uv := rotate_uv(uv_rect, rotation)

	var uv_tl = uv["tl"]
	var uv_tr = uv["tr"]
	var uv_br = uv["br"]
	var uv_bl = uv["bl"]

	var x := pos.x
	var y := pos.y
	var z := pos.z
	var s := 1.0

	var v000 := Vector3(x,     y,     z)
	var v001 := Vector3(x,     y,     z+s)
	var v010 := Vector3(x,     y+s,   z)
	var v011 := Vector3(x,     y+s,   z+s)
	var v100 := Vector3(x+s,   y,     z)
	var v101 := Vector3(x+s,   y,     z+s)
	var v110 := Vector3(x+s,   y+s,   z)
	var v111 := Vector3(x+s,   y+s,   z+s)

	match normal:
		Vector3.UP:
			_tri(st, v010, v110, v111, uv_tl, uv_tr, uv_br, normal)
			_tri(st, v111, v011, v010, uv_br, uv_bl, uv_tl, normal)

		Vector3.DOWN:
			_tri(st, v000, v001, v101, uv_tl, uv_tr, uv_br, normal)
			_tri(st, v101, v100, v000, uv_br, uv_bl, uv_tl, normal)

		Vector3.LEFT:
			_tri(st, v000, v010, v011, uv_tl, uv_tr, uv_br, normal)
			_tri(st, v011, v001, v000, uv_br, uv_bl, uv_tl, normal)

		Vector3.RIGHT:
			_tri(st, v100, v101, v111, uv_tl, uv_tr, uv_br, normal)
			_tri(st, v111, v110, v100, uv_br, uv_bl, uv_tl, normal)

		Vector3.FORWARD:
			_tri(st, v001, v011, v111, uv_tl, uv_tr, uv_br, normal)
			_tri(st, v111, v101, v001, uv_br, uv_bl, uv_tl, normal)

		Vector3.BACK:
			_tri(st, v000, v100, v110, uv_tl, uv_tr, uv_br, normal)
			_tri(st, v110, v010, v000, uv_br, uv_bl, uv_tl, normal)


# ---------------------------------------------------------
#  BLOCK BREAKING + PLACING
# ---------------------------------------------------------

func destroy_block_at(world_pos: Vector3, normal: Vector3) -> void:
	var local := world_pos - global_position - normal * 0.1

	var x := int(floor(local.x))
	var y := int(floor(local.y))
	var z := int(floor(local.z))

	if x < 0 or x >= CHUNK_SIZE.x: return
	if y < 0 or y >= CHUNK_SIZE.y: return
	if z < 0 or z >= CHUNK_SIZE.z: return

	blocks[x][z][y] = 0
	water_level[x][z][y] = 8
	rebuild_mesh()

	var gx := chunk_x * CHUNK_SIZE.x + x
	var gy := y
	var gz := chunk_z * CHUNK_SIZE.z + z
	world.schedule_neighbor_water_updates(gx, gy, gz)


func rebuild_mesh() -> void:
	for child in get_children():
		if child is MeshInstance3D or child is CollisionShape3D:
			child.queue_free()

	build_mesh()


func place_block_at(x: int, y: int, z: int, block_type: int) -> void:
	if x < 0 or x >= CHUNK_SIZE.x: return
	if y < 0 or y >= CHUNK_SIZE.y: return
	if z < 0 or z >= CHUNK_SIZE.z: return

	if blocks[x][z][y] != 6:
		if blocks[x][z][y] != 0:
			return

	blocks[x][z][y] = block_type
	if block_type == 6:
		water_level[x][z][y] = 0
	else:
		water_level[x][z][y] = 8

	rebuild_mesh()

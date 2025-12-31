extends StaticBody3D

const CHUNK_SIZE = Vector3i(16, 64, 16) # width, height, depth
const BLOCK_SIZE = 1.0
const BLOCKS = {
	0: { "name": "air",   "atlas_index": -1 },
	1: { "name": "grass", "atlas_index": 0 },
	2: { "name": "grassside", "atlas_index": 1},
	3: { "name": "dirt",  "atlas_index": 2 },
	4: { "name": "stone", "atlas_index": 3 },
}

var blocks = [] # 3D array storing block types
var world_noise: FastNoiseLite

@export var atlas: Texture2D
@export var atlas_material: StandardMaterial3D
@export var tile_size := Vector2(16, 16)
@export var chunk_x: int = 0
@export var chunk_z: int = 0

func _ready():
	generate_block_data()
	build_mesh()

func generate_block_data():
	blocks.resize(CHUNK_SIZE.x)

	for x in range(CHUNK_SIZE.x):
		blocks[x] = []
		for z in range(CHUNK_SIZE.z):
			blocks[x].append([])
			blocks[x][z].resize(CHUNK_SIZE.y)

			# Correct world sampling
			var world_x = chunk_x * CHUNK_SIZE.x + x
			var world_z = chunk_z * CHUNK_SIZE.z + z

			# Noise height
			var raw = world_noise.get_noise_2d(world_x, world_z)
			var height = int((raw + 1.0) * 0.5 * CHUNK_SIZE.y)
			height = clamp(height, 0, CHUNK_SIZE.y - 1)

			# Fill vertical column
			for y in range(CHUNK_SIZE.y):
				if y > height:
					blocks[x][z][y] = 0  # air
				elif y == height:
					blocks[x][z][y] = 1  # grass
				elif y >= height - 2:
					blocks[x][z][y] = 3  # dirt
				else:
					blocks[x][z][y] = 4  # stone

func build_mesh():
	var atlas_size = atlas.get_size()
	var tiles_x = int(atlas_size.x / tile_size.x)
	var tiles_y = int(atlas_size.y / tile_size.y)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for x in CHUNK_SIZE.x:
		for y in CHUNK_SIZE.y:
			for z in CHUNK_SIZE.z:
				if blocks[x][z][y] == 0:
					continue

				add_block_faces(st, x, y, z)

	var mesh = st.commit()

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = atlas_material # or whatever material you're using
	add_child(mesh_instance)

	var col = CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	add_child(col)  # attach to mesh instance

func is_air(x, y, z):
	if x < 0 or x >= CHUNK_SIZE.x: return true
	if y < 0 or y >= CHUNK_SIZE.y: return true
	if z < 0 or z >= CHUNK_SIZE.z: return true
	return blocks[x][z][y] == 0

func add_block_faces(st, x, y, z):
	var pos = Vector3(x, y, z)
	var block_type = blocks[x][z][y]

	# Determine face-specific texture
	var top_type = block_type
	var bottom_type = block_type
	var side_type = block_type

	if block_type == 1:  # grass
		side_type = 2  # grassside
		bottom_type = 3  # dirt

	if is_air(x+1, y, z): add_face(st, pos, Vector3.RIGHT, side_type)
	if is_air(x-1, y, z): add_face(st, pos, Vector3.LEFT, side_type)
	if is_air(x, y+1, z): add_face(st, pos, Vector3.UP, top_type)
	if is_air(x, y-1, z): add_face(st, pos, Vector3.DOWN, bottom_type)
	if is_air(x, y, z+1): add_face(st, pos, Vector3.FORWARD, side_type)
	if is_air(x, y, z-1): add_face(st, pos, Vector3.BACK, side_type)

func add_face(st: SurfaceTool, pos: Vector3, normal: Vector3, block_type: int):
	if block_type == 0:
		return

	var atlas_index = BLOCKS[block_type]["atlas_index"]
	var uv_rect = get_uv_rect(atlas_index)

	# Default rotation
	var rotation = 0

	# Apply per-face rotation
	match normal:
		Vector3.FORWARD:   # South
			rotation = 90
		Vector3.RIGHT:     # East
			rotation = 180
		Vector3.BACK:      # North
			rotation = 180
		Vector3.LEFT:      # West
			rotation = 90
		Vector3.UP:
			rotation = 0
		Vector3.DOWN:
			rotation = 0

	var uv = rotate_uv(uv_rect, rotation)

	var uv_tl = uv["tl"]
	var uv_tr = uv["tr"]
	var uv_br = uv["br"]
	var uv_bl = uv["bl"]

	var x = pos.x
	var y = pos.y
	var z = pos.z
	var s = 1.0

	var v000 = Vector3(x,     y,     z)
	var v001 = Vector3(x,     y,     z+s)
	var v010 = Vector3(x,     y+s,   z)
	var v011 = Vector3(x,     y+s,   z+s)
	var v100 = Vector3(x+s,   y,     z)
	var v101 = Vector3(x+s,   y,     z+s)
	var v110 = Vector3(x+s,   y+s,   z)
	var v111 = Vector3(x+s,   y+s,   z+s)

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

func destroy_block_at(world_pos: Vector3, normal: Vector3):
	# Move slightly INSIDE the block you clicked
	var local = world_pos - global_position - normal * 0.1

	var x = int(floor(local.x))
	var y = int(floor(local.y))
	var z = int(floor(local.z))

	# Bounds check
	if x < 0 or x >= CHUNK_SIZE.x: return
	if y < 0 or y >= CHUNK_SIZE.y: return
	if z < 0 or z >= CHUNK_SIZE.z: return

	# Remove block
	blocks[x][z][y] = 0

	rebuild_mesh()

func rebuild_mesh():
	# Remove old mesh + collider
	for child in get_children():
		if child is MeshInstance3D or child is CollisionShape3D:
			child.queue_free()

	build_mesh()

func place_block_at(x: int, y: int, z: int, block_type: int):
	# Bounds check
	if x < 0 or x >= CHUNK_SIZE.x: return
	if y < 0 or y >= CHUNK_SIZE.y: return
	if z < 0 or z >= CHUNK_SIZE.z: return

	# Only place if empty
	if blocks[x][z][y] != 0:
		return

	blocks[x][z][y] = block_type
	rebuild_mesh()

func get_uv_rect(atlas_index: int) -> Rect2:
	if atlas_index < 0:
		return Rect2()

	var atlas_size = atlas.get_size()
	var tiles_x = int(atlas_size.x / tile_size.x)
	var tiles_y = int(atlas_size.y / tile_size.y)

	var tile_x = atlas_index % tiles_x
	var tile_y = atlas_index / tiles_x

	# Flip Y because Godot UV origin is bottom-left
	tile_y = tiles_y - 1 - tile_y

	var uv_x = float(tile_x * tile_size.x) / atlas_size.x
	var uv_y = float(tile_y * tile_size.y) / atlas_size.y
	var uv_w = float(tile_size.x) / atlas_size.x
	var uv_h = float(tile_size.y) / atlas_size.y

	return Rect2(uv_x, uv_y, uv_w, uv_h)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
uva: Vector2, uvb: Vector2, uvc: Vector2,
normal: Vector3):
	st.set_normal(normal)
	st.set_uv(uva)
	st.add_vertex(a)

	st.set_normal(normal)
	st.set_uv(uvb)
	st.add_vertex(b)

	st.set_normal(normal)
	st.set_uv(uvc)
	st.add_vertex(c)

func rotate_uv(uv_rect: Rect2, rotation_degrees: int) -> Dictionary:
	var tl = uv_rect.position
	var tr = uv_rect.position + Vector2(uv_rect.size.x, 0)
	var br = uv_rect.position + uv_rect.size
	var bl = uv_rect.position + Vector2(0, uv_rect.size.y)

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

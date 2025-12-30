extends StaticBody3D

const CHUNK_SIZE = Vector3i(16, 64, 16) # width, height, depth
const BLOCK_SIZE = 1.0

var blocks = [] # 3D array storing block types
@export var world_noise: FastNoiseLite

func _ready():
	generate_block_data()
	build_mesh()

func generate_block_data():
	blocks.resize(CHUNK_SIZE.x)
	for x in CHUNK_SIZE.x:
		blocks[x] = []
		for z in CHUNK_SIZE.z:
			blocks[x].append([])
			var world_x = int(global_position.x) + x
			var world_z = int(global_position.z) + z

			var height = int((world_noise.get_noise_2d(world_x, world_z) + 1.0) * 10.0)

			for y in CHUNK_SIZE.y:
				if y <= height:
					blocks[x][z].append(1) # solid block
				else:
					blocks[x][z].append(0) # air

func build_mesh():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for x in CHUNK_SIZE.x:
		for y in CHUNK_SIZE.y:
			for z in CHUNK_SIZE.z:
				if blocks[x][z][y] == 0:
					continue

				add_block_faces(st, x, y, z)

	var mesh = st.commit()

	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	var col = CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	add_child(col)

func is_air(x, y, z):
	if x < 0 or x >= CHUNK_SIZE.x: return true
	if y < 0 or y >= CHUNK_SIZE.y: return true
	if z < 0 or z >= CHUNK_SIZE.z: return true
	return blocks[x][z][y] == 0

func add_block_faces(st, x, y, z):
	var pos = Vector3(x, y, z)

	if is_air(x+1, y, z): add_face(st, pos, Vector3.RIGHT)
	if is_air(x-1, y, z): add_face(st, pos, Vector3.LEFT)
	if is_air(x, y+1, z): add_face(st, pos, Vector3.UP)
	if is_air(x, y-1, z): add_face(st, pos, Vector3.DOWN)
	if is_air(x, y, z+1): add_face(st, pos, Vector3.FORWARD)
	if is_air(x, y, z-1): add_face(st, pos, Vector3.BACK)

func add_face(st: SurfaceTool, pos: Vector3, normal: Vector3):
	var size := BLOCK_SIZE
	var x := pos.x
	var y := pos.y
	var z := pos.z

	match normal:
		Vector3.UP:
			st.set_normal(normal)
			st.add_vertex(Vector3(x, y + size, z))
			st.add_vertex(Vector3(x + size, y + size, z))
			st.add_vertex(Vector3(x + size, y + size, z + size))

			st.set_normal(normal)
			st.add_vertex(Vector3(x + size, y + size, z + size))
			st.add_vertex(Vector3(x, y + size, z + size))
			st.add_vertex(Vector3(x, y + size, z))

		Vector3.DOWN:
			st.set_normal(normal)
			st.add_vertex(Vector3(x, y, z))
			st.add_vertex(Vector3(x, y, z + size))
			st.add_vertex(Vector3(x + size, y, z + size))

			st.set_normal(normal)
			st.add_vertex(Vector3(x + size, y, z + size))
			st.add_vertex(Vector3(x + size, y, z))
			st.add_vertex(Vector3(x, y, z))

		Vector3.LEFT:
			st.set_normal(normal)
			st.add_vertex(Vector3(x, y, z))
			st.add_vertex(Vector3(x, y + size, z))
			st.add_vertex(Vector3(x, y + size, z + size))

			st.set_normal(normal)
			st.add_vertex(Vector3(x, y + size, z + size))
			st.add_vertex(Vector3(x, y, z + size))
			st.add_vertex(Vector3(x, y, z))

		Vector3.RIGHT:
			st.set_normal(normal)
			st.add_vertex(Vector3(x + size, y, z))
			st.add_vertex(Vector3(x + size, y, z + size))
			st.add_vertex(Vector3(x + size, y + size, z + size))

			st.set_normal(normal)
			st.add_vertex(Vector3(x + size, y + size, z + size))
			st.add_vertex(Vector3(x + size, y + size, z))
			st.add_vertex(Vector3(x + size, y, z))

		Vector3.FORWARD:
			st.set_normal(normal)
			st.add_vertex(Vector3(x, y, z + size))
			st.add_vertex(Vector3(x, y + size, z + size))
			st.add_vertex(Vector3(x + size, y + size, z + size))

			st.set_normal(normal)
			st.add_vertex(Vector3(x + size, y + size, z + size))
			st.add_vertex(Vector3(x + size, y, z + size))
			st.add_vertex(Vector3(x, y, z + size))

		Vector3.BACK:
			st.set_normal(normal)
			st.add_vertex(Vector3(x, y, z))
			st.add_vertex(Vector3(x + size, y, z))
			st.add_vertex(Vector3(x + size, y + size, z))

			st.set_normal(normal)
			st.add_vertex(Vector3(x + size, y + size, z))
			st.add_vertex(Vector3(x, y + size, z))
			st.add_vertex(Vector3(x, y, z))

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
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()

	build_mesh()

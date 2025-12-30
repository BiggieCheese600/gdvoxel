extends Node3D

@export var chunk_scene: PackedScene
@export var render_distance := 4
var noise := FastNoiseLite.new()
var loaded_chunks := {}
const Chunk = preload("res://chunk.gd")
const CHUNK_SIZE = Vector3i(16, 64, 16)

func _ready():
	noise.seed = randi()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM


func _process(_delta):
	var player_pos = $Player.global_position
	var cx = int(floor(player_pos.x / Chunk.CHUNK_SIZE.x))
	var cz = int(floor(player_pos.z / Chunk.CHUNK_SIZE.z))

	for x in range(cx - render_distance, cx + render_distance + 1):
		for z in range(cz - render_distance, cz + render_distance + 1):
			var key = Vector2i(x, z)
			if not loaded_chunks.has(key):
				spawn_chunk(x, z)

func spawn_chunk(cx, cz):
	var chunk = chunk_scene.instantiate()
	chunk.chunk_x = cx
	chunk.chunk_z = cz
	chunk.world_noise = noise  # ✅ pass shared noise instance
	chunk.position = Vector3(cx * CHUNK_SIZE.x, 0, cz * CHUNK_SIZE.z)
	add_child(chunk)
	loaded_chunks[Vector2i(cx, cz)] = chunk

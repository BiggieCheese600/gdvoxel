extends Node3D

@export var chunk_scene: PackedScene
@export var render_distance := 4
var noise := FastNoiseLite.new()
var loaded_chunks := {}
const Chunk = preload("res://chunk.gd")

func _ready():
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.01

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
	chunk.position = Vector3(
		cx * chunk.CHUNK_SIZE.x,
		0,
		cz * chunk.CHUNK_SIZE.z
	)
	chunk.world_noise = noise
	add_child(chunk)
	loaded_chunks[Vector2i(cx, cz)] = chunk

extends CharacterBody3D

var mouse = InputEventMouseMotion
const SPEED = 10.0
const SENSITIVITY = 0.003
var debug = 0
var captured = 1
var selected_index := 0
var selected_block := 1  # default to grass
const BLOCK_TYPES = [1, 3, 4]  # grass, dirt, stone
var paused = 0

@onready var camera = $Camera3D
@onready var outline = $"../OutlineCube"
@onready var blocklabel = $GUI/BlockSelected
@onready var pausemenu = $PauseMenu
@onready var gui = $GUI

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	captured = 1

func _input(event):
	if debug == 1:
		if event.is_action_pressed("mouse_mode_switch"):
			if captured == 1:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				captured = 0
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				captured = 1

func _unhandled_input(event):
	if event is InputEventMouseMotion and captured == 1:
		# Rotate the whole player horizontally (yaw)
		camera.rotation.y -= event.relative.x * SENSITIVITY
		# Rotate the whole player vertically (pitch)
		camera.rotation.x = clamp(camera.rotation.x - event.relative.y * SENSITIVITY, deg_to_rad(-90), deg_to_rad(90))
	#breaking blocks
	if event.is_action_pressed("break_block"):
		var hit = get_block_hit()
		#print("HIT:", hit)
		if hit:
			hit.collider.destroy_block_at(hit.position, hit.normal)
	if event.is_action_pressed("place_block"):
		var hit = get_block_target()
		if hit:
			place_block(hit)
	if event.is_action_pressed("menu"):
		if paused == 0:
			gui.visible = false
			pausemenu.visible = true
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			captured = 0
		else:
			pausemenu.visible = false
			gui.visible = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			captured = 1

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			selected_index = (selected_index + 1) % BLOCK_TYPES.size()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			selected_index = (selected_index - 1 + BLOCK_TYPES.size()) % BLOCK_TYPES.size()

		selected_block = BLOCK_TYPES[selected_index]


func _physics_process(_delta):
	if selected_block == 1:
		blocklabel.text = "Block Selected: Grass"
	if selected_block == 3:
		blocklabel.text = "Block Selected: Dirt"
	if selected_block == 4:
		blocklabel.text = "Block Selected: Stone"
	update_outline()
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction = (camera.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		velocity.y = direction.y * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		velocity.y = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

func get_block_hit():
	var from = camera.global_position
	var to = from + camera.global_transform.basis.z * -5.0  # 5‑block reach

	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	return space.intersect_ray(query)

func update_outline():
	var hit = get_block_target()
	if not hit:
		outline.visible = false
		return

	var coords = get_block_coords(hit)

	# Convert block coords → world coords
	var world_pos = hit.collider.global_position + Vector3(coords.x, coords.y, coords.z)

	outline.global_position = world_pos + Vector3(0.5, 0.5, 0.5)
	outline.visible = true

func get_block_target():
	var from = camera.global_position
	var to = from + camera.global_transform.basis.z * -5.0

	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	return space.intersect_ray(query)

func get_block_coords(hit):
	var pos = hit.position - hit.normal * 0.5
	pos -= hit.collider.global_position
	return Vector3i(
		int(floor(pos.x)),
		int(floor(pos.y)),
		int(floor(pos.z))
	)

func place_block(hit):
	var chunk = hit.collider
	if not chunk:
		return

	# Block to place INTO = hit.position + normal * 0.5
	var pos = hit.position + hit.normal * 0.5
	pos -= chunk.global_position

	var x = int(floor(pos.x))
	var y = int(floor(pos.y))
	var z = int(floor(pos.z))

	var block_type = BLOCK_TYPES[selected_index]
	chunk.place_block_at(x, y, z, block_type)


func _on_resume_pressed() -> void:
	pausemenu.visible = false
	gui.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	captured = 1


func _on_quit_pressed() -> void:
	get_tree().quit()

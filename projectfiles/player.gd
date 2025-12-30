extends CharacterBody3D

var mouse = InputEventMouseMotion
const SPEED = 10.0
const SENSITIVITY = 0.003
var debug = 1
var captured = 1

@onready var camera = $Camera3D
@onready var outline = $"../OutlineCube"

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
		print("HIT:", hit)
		if hit:
			hit.collider.destroy_block_at(hit.position, hit.normal)

func _physics_process(_delta):
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
	var hit = get_block_hit()

	if hit:
		# Move slightly inside the block you hit
		var pos = hit.position - hit.normal * 0.01

		# Snap to block grid
		pos = pos.snapped(Vector3.ONE)

		# Center the outline on the block
		outline.global_position = pos + Vector3(0.5, 0.5, 0.5)

		outline.visible = true
	else:
		outline.visible = false

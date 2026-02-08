extends CharacterBody3D

var mouse = InputEventMouseMotion
const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0
const JUMP_VELOCITY = 4.5
var speed
const SENSITIVITY = 0.003
var debuginv = true
var captured = 1
var selected_index := 0
var selected_block := 1  # default to grass
const BLOCK_TYPES = [1, 3, 4, 5, 6]  # grass, dirt, stone (2 would be sides of grass)
var paused = 0
var gravity = 9.8
var world: Node3D = null
const WATERLAY_LEVEL = 129.5

@export var grasstex: Texture2D
@export var dirttex: Texture2D
@export var stonetex: Texture2D
@export var sandtex: Texture2D
@export var watertex: Texture2D

@onready var downcheck: Area3D = $downcheck
@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var outline = $"../OutlineCube"
@onready var outlinecolarea: Area3D = $"../OutlineCube/Area3D"
@onready var pausemenu = $PauseMenu
@onready var gui = $GUI
@onready var pausecontainer = $PauseMenu/VBoxContainer
@onready var settingsarea = $PauseMenu/settingsarea
@onready var renderlabel = $PauseMenu/settingsarea/renderlabel
@onready var renderdistance = $PauseMenu/settingsarea/renderdistance
@onready var hotbar = $GUI/hotcontainer/hotbar
@onready var slot1 = $GUI/hotcontainer/slot1
@onready var slot2 = $GUI/hotcontainer/slot2
@onready var slot3 = $GUI/hotcontainer/slot3
@onready var slot4 = $GUI/hotcontainer/slot4
@onready var slot5 = $GUI/hotcontainer/slot5
@onready var slot6 = $GUI/hotcontainer/slot6
@onready var slot7 = $GUI/hotcontainer/slot7
@onready var slot8 = $GUI/hotcontainer/slot8
@onready var slot9 = $GUI/hotcontainer/slot9
@onready var slot10 = $GUI/hotcontainer/slot10
@onready var coordlabel = $GUI/debugmenu/coords
@onready var ocpblock = $GUI/debugmenu/ocpblock
@onready var debugmenu = $GUI/debugmenu
@onready var waterlay = $waterlay

func _ready():
	world = get_parent()
	hotbar.frame = 0
	if debuginv == true:
		slot1.texture = grasstex
		slot2.texture = dirttex
		slot3.texture = stonetex
		slot4.texture = sandtex
		slot5.texture = watertex
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	captured = 1

func _unhandled_input(event):
	if event is InputEventMouseMotion and captured == 1:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))
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
			if hotbar.frame == 0:
				hotbar.frame = 9
			else:
				hotbar.frame -= 1
			#selected_index = (selected_index + 1) % BLOCK_TYPES.size()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if hotbar.frame == 9:
				hotbar.frame = 0
			else:
				hotbar.frame += 1


func _physics_process(delta):
	check_slots()
	update_outline()
	check_block()

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction = (head.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)

	update_coordlabel()

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
	if selected_index == -1:
		return

	if outlinecolarea.overlaps_area(downcheck):
		return

	var world = get_parent()

	var pos = hit.position + hit.normal * 0.5

	var x = int(floor(pos.x))
	var y = int(floor(pos.y))
	var z = int(floor(pos.z))

	var block_type = BLOCK_TYPES[selected_index]
	world.set_block(x, y, z, block_type)


func _on_resume_pressed() -> void:
	pausemenu.visible = false
	gui.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	captured = 1


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_settings_pressed() -> void:
	pausecontainer.visible = false
	settingsarea.visible = true


func _on_back_pressed() -> void:
	settingsarea.visible = false
	pausecontainer.visible = true


func _on_renderdistance_value_changed(value: float) -> void:
	renderlabel.text = "Render Distance: " + str(renderdistance.value)

func check_slots():
	if hotbar.frame == 0:
		check_slot1()
	if hotbar.frame == 1:
		check_slot2()
	if hotbar.frame == 2:
		check_slot3()
	if hotbar.frame == 3:
		check_slot4()
	if hotbar.frame == 4:
		check_slot5()
	if hotbar.frame == 5:
		check_slot6()
	if hotbar.frame == 6:
		check_slot7()
	if hotbar.frame == 7:
		check_slot8()
	if hotbar.frame == 8:
		check_slot9()
	if hotbar.frame == 9:
		check_slot10()

func check_slot1():
	var slottex = slot1.texture
	if slottex == grasstex:
		selected_index = 0
	if slottex == dirttex:
		selected_index = 1
	if slottex == stonetex:
		selected_index = 2
	if slottex == sandtex:
		selected_index = 3
	if slottex == watertex:
		selected_index = 4
	if slottex == null:
		selected_index = -1

func check_slot2():
	var slottex = slot2.texture
	if slottex == grasstex:
		selected_index = 0
	if slottex == dirttex:
		selected_index = 1
	if slottex == stonetex:
		selected_index = 2
	if slottex == sandtex:
		selected_index = 3
	if slottex == watertex:
		selected_index = 4
	if slottex == null:
		selected_index = -1

func check_slot3():
	var slottex = slot3.texture
	if slottex == grasstex:
		selected_index = 0
	if slottex == dirttex:
		selected_index = 1
	if slottex == stonetex:
		selected_index = 2
	if slottex == sandtex:
		selected_index = 3
	if slottex == watertex:
		selected_index = 4
	if slottex == null:
		selected_index = -1

func check_slot4():
	var slottex = slot4.texture
	if slottex == grasstex:
		selected_index = 0
	if slottex == dirttex:
		selected_index = 1
	if slottex == stonetex:
		selected_index = 2
	if slottex == sandtex:
		selected_index = 3
	if slottex == watertex:
		selected_index = 4
	if slottex == null:
		selected_index = -1

func check_slot5():
	var slottex = slot5.texture
	if slottex == grasstex:
		selected_index = 0
	if slottex == dirttex:
		selected_index = 1
	if slottex == stonetex:
		selected_index = 2
	if slottex == sandtex:
		selected_index = 3
	if slottex == watertex:
		selected_index = 4
	if slottex == null:
		selected_index = -1

func check_slot6():
	var slottex = slot6.texture
	if slottex == grasstex:
		selected_index = 0
	if slottex == dirttex:
		selected_index = 1
	if slottex == stonetex:
		selected_index = 2
	if slottex == sandtex:
		selected_index = 3
	if slottex == watertex:
		selected_index = 4
	if slottex == null:
		selected_index = -1

func check_slot7():
	var slottex = slot7.texture
	if slottex == grasstex:
		selected_index = 0
	if slottex == dirttex:
		selected_index = 1
	if slottex == stonetex:
		selected_index = 2
	if slottex == sandtex:
		selected_index = 3
	if slottex == watertex:
		selected_index = 4
	if slottex == null:
		selected_index = -1

func check_slot8():
	var slottex = slot8.texture
	if slottex == grasstex:
		selected_index = 0
	if slottex == dirttex:
		selected_index = 1
	if slottex == stonetex:
		selected_index = 2
	if slottex == sandtex:
		selected_index = 3
	if slottex == watertex:
		selected_index = 4
	if slottex == null:
		selected_index = -1

func check_slot9():
	var slottex = slot9.texture
	if slottex == grasstex:
		selected_index = 0
	if slottex == dirttex:
		selected_index = 1
	if slottex == stonetex:
		selected_index = 2
	if slottex == sandtex:
		selected_index = 3
	if slottex == watertex:
		selected_index = 4
	if slottex == null:
		selected_index = -1

func check_slot10():
	var slottex = slot10.texture
	if slottex == grasstex:
		selected_index = 0
	if slottex == dirttex:
		selected_index = 1
	if slottex == stonetex:
		selected_index = 2
	if slottex == sandtex:
		selected_index = 3
	if slottex == watertex:
		selected_index = 4
	if slottex == null:
		selected_index = -1

func update_coordlabel():
	coordlabel.text = "XYZ: " + str(round(self.position.x)) + ", " + str(round(self.position.y - 65)) + ", " + str(round(self.position.z))

func get_block_player_is_in() -> int:
	var pos = global_position

	var bx = int(floor(pos.x))
	var by = int(floor(pos.y))
	var bz = int(floor(pos.z))

	return world.get_block(bx, by, bz)

func check_block():
	var block = get_block_player_is_in()

	if block == 0:
		ocpblock.text = "Inside block type: Air"
		waterlay.visible = false
	elif block == 6:
		ocpblock.text = "Inside block type: Water"
		if self.position.y < WATERLAY_LEVEL:
			waterlay.visible = true
		else:
			waterlay.visible = false
	else:
		ocpblock.text = "Inside block type: ?"
		waterlay.visible = false

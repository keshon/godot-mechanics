class_name FxRange
extends Node3D
## The workbench. Nobody gives you one of these; you build it first.
##
## Two numbers on the HUD are the point of the whole probe. BUILT is how many
## effect nodes were ever actually created, REUSED is how many times one came
## back out of the pool. Hold the trigger down and watch the first climb to a
## handful and stop while the second runs away.
##
## And the list on the left is read off the folder at startup. Nothing in this
## file, or in fx.gd, or anywhere else, knows what a "spark" is.

## How far the aim ray reaches, m.
const AIM_RANGE := 120.0
## How far in front of the camera an effect lands when the ray finds nothing, m.
const AIM_FALLBACK := 12.0
## How far off the surface an effect is placed, m. Any less and it sits half
## inside the wall it just hit.
const SURFACE_LIFT := 0.03

## Seconds between shots while the trigger is held.
@export_range(0.02, 1.0, 0.01) var repeat_interval := 0.06
## How fast the free camera flies, m/s.
@export_range(1.0, 30.0, 0.5) var fly_speed := 9.0
## Radians of rotation per pixel of mouse motion.
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0025

var _yaw := 0.0
var _pitch := 0.0
var _picked := 0
var _cooldown := 0.0

@onready var _fx: FxPool = $Fx
@onready var _camera: Camera3D = $Camera
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	_yaw = _camera.rotation.y
	_pitch = _camera.rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var input: Vector2 = Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	var lift := 1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.0
	var direction := _camera.global_basis * Vector3(input.x, 0.0, input.y) + Vector3.UP * lift
	_camera.global_position += direction * fly_speed * delta

	_cooldown -= delta
	var firing := (
			Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			or Input.is_key_pressed(KEY_SPACE)
	)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _cooldown <= 0.0 and firing:
		_cooldown = repeat_interval
		var hit := _aim()
		var at: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		_fx.play(_current(), at, normal)

	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(
				_pitch - event.relative.y * mouse_sensitivity,
				-deg_to_rad(89.0),
				deg_to_rad(89.0))
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)
		return
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	var button := event as InputEventMouseButton
	if (
			button
			and button.pressed
			and button.button_index == MOUSE_BUTTON_LEFT
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		_picked = mini(key.keycode - KEY_1, _fx.names().size() - 1)
	elif key.keycode == KEY_R:
		# Rescanning at runtime is the whole promise made good: save a new
		# scene into effects/, press R, and it is in the list. No restart, no
		# code, no rebuild.
		_fx.rescan()


func _current() -> String:
	var available := _fx.names()
	return available[_picked] if _picked < available.size() else ""


## Where the crosshair meets the world, and which way that surface faces.
##
## Probe 06 got away with plane arithmetic because everything there happened on
## flat ground. The moment surfaces tilt, only a real raycast will do — and the
## thing worth collecting from it is not the point but the NORMAL, which is
## what turns "an effect at a place" into "an effect on a surface".
func _aim() -> Dictionary:
	var from := _camera.global_position
	var direction := -_camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * AIM_RANGE)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"position": from + direction * AIM_FALLBACK, "normal": -direction}
	var at: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	return {"position": at + normal * SURFACE_LIFT, "normal": normal}


func _draw_hud() -> void:
	var lines := PackedStringArray([
		"на экране [b]%d[/b]   собрано узлов %d   переиспользований %d" % [
			_fx.live, _fx.built, _fx.reused],
		"",
		"ЛКМ или ПРОБЕЛ выстрелить   WASD лететь   SHIFT вверх   R перечитать папку",
		"эффекты найдены в effects/ при запуске, 1…9 выбирают:",
	])
	var available := _fx.names()
	for i in available.size():
		lines.append("%s %d  %-10s   в запасе %d" % [
			"[color=#7fe08a]>[/color]" if i == _picked else " ",
			i + 1, available[i], _fx.pooled(available[i])])
	lines.append_array(PackedStringArray([
		"искры отлетают от того, во что попал, по его нормали — попробуй две наклонные",
		"панели и землю",
		"",
		"[color=#66ccff]эффект — это сцена, реестр — папка, таймлайн — AnimationPlayer:"
			+ " ни у одного эффекта здесь нет скрипта[/color]",
	]))
	_hud.text = "\n".join(lines)


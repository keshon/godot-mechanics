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
## file, or in Fx.gd, or anywhere else, knows what a "spark" is.

@export_range(0.02, 1.0, 0.01) var repeat_interval := 0.06
@export_range(1.0, 30.0, 0.5) var fly_speed := 9.0
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0025

@onready var _fx: Fx = $Fx
@onready var _cam: Camera3D = $Camera
@onready var _big: Label = $Ui/Hud/Big
@onready var _detail: RichTextLabel = $Ui/Hud/Detail

var _yaw := 0.0
var _pitch := 0.0
var _pick := 0
var _cooldown := 0.0


func _ready() -> void:
	_yaw = _cam.rotation.y
	_pitch = _cam.rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity,
			-deg_to_rad(89.0), deg_to_rad(89.0))
		_cam.rotation = Vector3(_pitch, _yaw, 0.0)
		return
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		_pick = mini(key.keycode - KEY_1, _fx.names().size() - 1)
	elif key.keycode == KEY_R:
		# Rescanning at runtime is the whole promise made good: save a new
		# scene into effects/, press R, and it is in the list. No restart, no
		# code, no rebuild.
		_fx._scan()


func _process(delta: float) -> void:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var lift := 1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.0
	_cam.global_position += (_cam.global_basis * Vector3(input.x, 0.0, input.y)
		+ Vector3.UP * lift) * fly_speed * delta

	_cooldown -= delta
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _cooldown <= 0.0 \
			and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
				or Input.is_key_pressed(KEY_SPACE)):
		_cooldown = repeat_interval
		var hit := _aim()
		_fx.play(_current(), hit.position, hit.normal)

	_draw_hud()


func _current() -> String:
	var all := _fx.names()
	return all[_pick] if _pick < all.size() else ""


## Where the crosshair meets the world, and which way that surface faces.
##
## Probe 06 got away with plane arithmetic because everything there happened on
## flat ground. The moment surfaces tilt, only a real raycast will do — and the
## thing worth collecting from it is not the point but the NORMAL, which is
## what turns "an effect at a place" into "an effect on a surface".
func _aim() -> Dictionary:
	var from := _cam.global_position
	var dir := -_cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"position": from + dir * 12.0, "normal": -dir}
	# A hair off the surface, or the effect sits half inside it.
	return {"position": hit.position + hit.normal * 0.03, "normal": hit.normal}


func _draw_hud() -> void:
	_big.text = "%d / %d" % [_fx.built, _fx.reused]
	var lines := [
		"nodes ever built  /  times one was reused",
		"",
		"[color=#8ecbff]found in effects/ at startup — press R to rescan[/color]",
	]
	var all := _fx.names()
	for i in all.size():
		lines.append("%s %d  %-10s   pooled %d" % [
			"[color=#7ee081]>[/color]" if i == _pick else " ", i + 1,
			all[i], _fx.pooled(all[i])])
	lines.append("")
	lines.append("on screen now    [b]%d[/b]" % _fx.live)
	_detail.text = "\n".join(lines)

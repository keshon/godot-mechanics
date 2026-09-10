class_name BoomRange
extends Node3D
## The firing range. Click to set one off, then take the layers apart.
##
## The two controls that matter are not the layer switches, they are TIME and
## the style. Drop time to a tenth and the five layers stop overlapping: you
## can watch the flash finish before the fireball has finished growing, and the
## sparks arc down while the smoke is still going up. At full speed all of that
## arrives as one impression, which is the point of it — but it is not how you
## learn to build one.
##
## This node also fills the HUD. There is no separate hud.gd in this probe: two
## labels did not need a class of their own, and the file budget was better
## spent on the shader.

## How far the aim ray reaches before it gives up and picks a point in the air.
const AIM_RANGE := 120.0
## How far in front of the camera a blast lands when the ray finds no ground.
const AIM_FALLBACK := 14.0

@export var blast_scene: PackedScene

@export_group("Layers")
@export var flash_enabled := true
@export var fireball_enabled := true
@export var smoke_enabled := true
@export var sparks_enabled := true
@export var ring_enabled := true

@export_group("Look")
@export var style: BoomBlast.Style = BoomBlast.Style.PHOTO
@export_range(0.05, 1.0, 0.05) var time_scale := 1.0:
	set(value):
		time_scale = value
		Engine.time_scale = value

@export_group("Camera")
## How fast the free camera flies, m/s.
@export_range(1.0, 30.0, 0.5) var fly_speed := 8.0
## Radians of rotation per pixel of mouse motion.
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0025

var _yaw := 0.0
var _pitch := 0.0
var _last_blast: BoomBlast

@onready var _camera: Camera3D = $Camera
@onready var _blasts: Node3D = $Booms
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	_yaw = _camera.rotation.y
	_pitch = _camera.rotation.x
	Engine.time_scale = time_scale
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	# The camera is deliberately NOT slowed with the world. Being able to walk
	# around a frozen explosion at full speed is most of why slow motion is
	# useful here, and Engine.time_scale would take that away.
	var step := delta / maxf(Engine.time_scale, 0.001)
	var input: Vector2 = Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	var lift := 1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.0
	var direction := _camera.global_basis * Vector3(input.x, 0.0, input.y) + Vector3.UP * lift
	_camera.global_position += direction * fly_speed * step

	_draw_hud()


func _exit_tree() -> void:
	# time_scale is global and outlives the scene. Leaving it at 0.1 would make
	# the next thing you run look broken for no visible reason.
	Engine.time_scale = 1.0


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
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			spawn(_aim_point())
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1: flash_enabled = not flash_enabled
		KEY_2: fireball_enabled = not fireball_enabled
		KEY_3: smoke_enabled = not smoke_enabled
		KEY_4: sparks_enabled = not sparks_enabled
		KEY_5: ring_enabled = not ring_enabled
		# NOT S/W/Q/E: S is move_back and W is move_forward, so flying used to
		# change the style and slow time down. Caught project-wide long after
		# this probe was closed; rule 7 of the charter exists because of it.
		KEY_TAB:
			style = (
					BoomBlast.Style.STYLISED if style == BoomBlast.Style.PHOTO
					else BoomBlast.Style.PHOTO
			)
		KEY_Z: time_scale = 1.0
		KEY_X: time_scale = 0.25
		KEY_C: time_scale = 0.1
		KEY_SPACE: spawn(_aim_point())


func spawn(at: Vector3) -> void:
	var blast: BoomBlast = blast_scene.instantiate()
	# Everything the explosion is gets written in before it enters the tree —
	# the same handshake as the bullet in probe 03, with more to say.
	blast.style = style
	blast.flash_enabled = flash_enabled
	blast.fireball_enabled = fireball_enabled
	blast.smoke_enabled = smoke_enabled
	blast.sparks_enabled = sparks_enabled
	blast.ring_enabled = ring_enabled
	_blasts.add_child(blast)
	blast.global_position = at
	_last_blast = blast


## Where the crosshair meets the ground, or a point in front if it meets sky.
## Same plane arithmetic as probe 06 — no collider needed for a flat world.
func _aim_point() -> Vector3:
	var from := _camera.global_position
	var direction := -_camera.global_basis.z
	if direction.y < -0.02:
		var at := from + direction * (-(from.y - 0.6) / direction.y)
		if at.length() < AIM_RANGE:
			return at
	return from + direction * AIM_FALLBACK


func _draw_hud() -> void:
	var live := "—"
	var age := 0.0
	if is_instance_valid(_last_blast):
		age = _last_blast.age
		var running := _last_blast.alive()
		live = "погас" if running.is_empty() else "  ".join(running)
	_hud.text = "
".join(PackedStringArray([
		"время [b]×%.2f[/b]   вид: [b]%s[/b]   взрывов в мире %d" % [
			Engine.time_scale,
			"условный" if style == BoomBlast.Style.STYLISED else "фотографический",
			_blasts.get_child_count()],
		"последнему [b]%.2f[/b] с   ещё горят: %s" % [age, live],
		"",
		"ЛКМ или ПРОБЕЛ подорвать   WASD лететь   SHIFT вверх   ESC отпустить мышь",
		"1 вспышка %s   2 огонь %s   3 дым %s   4 искры %s   5 кольцо %s" % [
			_on_off(flash_enabled), _on_off(fireball_enabled), _on_off(smoke_enabled),
			_on_off(sparks_enabled), _on_off(ring_enabled)],
		"TAB сменить вид   Z X C время ×1 ×0.25 ×0.1",
		"",
		"[color=#66ccff]взрыв — стопка эффектов на разных часах: замедли до предела, и"
			+ " слои расходятся[/color]",
	]))


func _on_off(value: bool) -> String:
	return "[color=#7fe08a]вкл[/color]" if value else "выкл"


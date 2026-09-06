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
## This node also fills the HUD. There is no Hud.gd in this probe: two labels
## did not need a class of their own, and the file budget was better spent on
## the shader.

@export var boom_scene: PackedScene

@export_group("Layers")
@export var flash := true
@export var fireball := true
@export var smoke := true
@export var sparks := true
@export var ring := true

@export_group("Look")
@export var style: Boom.Style = Boom.Style.PHOTO
@export_range(0.05, 1.0, 0.05) var time_scale := 1.0:
	set(v):
		time_scale = v
		Engine.time_scale = v

@export_group("Camera")
@export_range(1.0, 30.0, 0.5) var fly_speed := 8.0
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0025

@onready var _cam: Camera3D = $Camera
@onready var _booms: Node3D = $Booms
@onready var _detail: RichTextLabel = $Ui/Hud/Detail
@onready var _big: Label = $Ui/Hud/Big

var _yaw := 0.0
var _pitch := 0.0
var _last: Boom


func _ready() -> void:
	_yaw = _cam.rotation.y
	_pitch = _cam.rotation.x
	Engine.time_scale = time_scale
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	# time_scale is global and outlives the scene. Leaving it at 0.1 would make
	# the next thing you run look broken for no visible reason.
	Engine.time_scale = 1.0


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
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			spawn(_aim_point())
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1: flash = not flash
		KEY_2: fireball = not fireball
		KEY_3: smoke = not smoke
		KEY_4: sparks = not sparks
		KEY_5: ring = not ring
		# NOT S/W/Q/E: S is move_back and W is move_forward, so flying used to change
		# the style and slow time down. Caught project-wide long after this probe was
		# closed; rule 7 exists because of it.
		KEY_TAB: style = (Boom.Style.STYLISED if style == Boom.Style.PHOTO
			else Boom.Style.PHOTO)
		KEY_Z: time_scale = 1.0
		KEY_X: time_scale = 0.25
		KEY_C: time_scale = 0.1
		KEY_SPACE: spawn(_aim_point())


## Where the crosshair meets the ground, or a point in front if it meets sky.
## Same plane arithmetic as probe 06 — no collider needed for a flat world.
func _aim_point() -> Vector3:
	var from := _cam.global_position
	var dir := -_cam.global_basis.z
	if dir.y < -0.02:
		var p := from + dir * (-(from.y - 0.6) / dir.y)
		if p.length() < 120.0:
			return p
	return from + dir * 14.0


func spawn(at: Vector3) -> void:
	var b: Boom = boom_scene.instantiate()
	# Everything the explosion is gets written in before it enters the tree —
	# the same handshake as the bullet in probe 03, with more to say.
	b.style = style
	b.flash = flash
	b.fireball = fireball
	b.smoke = smoke
	b.sparks = sparks
	b.ring = ring
	_booms.add_child(b)
	b.global_position = at
	_last = b


func _process(delta: float) -> void:
	# The camera is deliberately NOT slowed with the world. Being able to walk
	# around a frozen explosion at full speed is most of why slow motion is
	# useful here, and Engine.time_scale would take that away.
	var step := delta / maxf(Engine.time_scale, 0.001)
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var lift := 1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.0
	_cam.global_position += (_cam.global_basis * Vector3(input.x, 0.0, input.y)
		+ Vector3.UP * lift) * fly_speed * step

	_big.text = "x%.2f" % Engine.time_scale
	var live := "[color=#7a7f88]—[/color]"
	var age := 0.0
	if is_instance_valid(_last):
		age = _last.age
		var names := _last.alive()
		live = "[color=#7a7f88]finished[/color]" if names.is_empty() else "  ".join(names)
	_detail.text = "\n".join([
		"time",
		"style    [b]%s[/b]" % ("STYLISED" if style == Boom.Style.STYLISED else "PHOTO"),
		"",
		"1 flash %s   2 fire %s   3 smoke %s   4 sparks %s   5 ring %s"
			% [_on(flash), _on(fireball), _on(smoke), _on(sparks), _on(ring)],
		"",
		"last blast    [b]%.2f s[/b] old" % age,
		"still running    %s" % live,
		"live explosions    %d" % _booms.get_child_count(),
	])


func _on(v: bool) -> String:
	return "[color=#7ee081]on[/color]" if v else "[color=#7a7f88]off[/color]"

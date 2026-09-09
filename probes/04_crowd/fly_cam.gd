class_name CrowdFlyCam
extends Camera3D
## A debug camera: WASD to fly, mouse to look, shift to hurry, wheel to change
## speed. Nothing to learn here — it exists so the flock can be looked at from
## the inside, which is where the interesting part happens.

## Radians of rotation per pixel of mouse motion.
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0025
## How fast the camera flies, m/s. Shift multiplies it by three; the wheel
## changes it by a fifth per notch.
@export_range(1.0, 200.0, 1.0) var fly_speed := 30.0

var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var input: Vector2 = Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	var lift := 1.0 if Input.is_action_pressed(&"jump") else 0.0
	var direction := global_basis * Vector3(input.x, 0.0, input.y) + Vector3.UP * lift
	var rush := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	global_position += direction * fly_speed * rush * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(
				_pitch - event.relative.y * mouse_sensitivity,
				-deg_to_rad(89.0),
				deg_to_rad(89.0))
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			fly_speed = minf(fly_speed * 1.2, 200.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fly_speed = maxf(fly_speed / 1.2, 1.0)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

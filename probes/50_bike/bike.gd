class_name BikeRig
extends Node3D
## Input, camera and comparisons belong to the experiment; the motorcycle takes intentions.

const SECTIONS: Array[String] = ["гребёнка", "малый стол", "большой прыжок"]
const SPRINGS: Array[float] = [11000.0, 18000.0, 30000.0]
const HYPOTHESIS := "гипотеза: подвеска и положение в воздухе меняют цену приземления"

@export var follow_distance := 5.5
@export var follow_height := 2.5

var section: int = 0
var _spring: int = 1
var _loose := false
var _close_camera := false
var _facing := Vector3.FORWARD
var _landing_note := "прыжка ещё не было"

@onready var bike: BikeBody = $Bike
@onready var _camera: Camera3D = $Camera
@onready var _spawns: Array[Node3D] = [$Track/BumpsStart, $Track/TableStart, $Track/JumpStart]
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	bike.landed.connect(_on_bike_landed)
	bike.crashed.connect(_on_bike_crashed)
	reset()


func _process(delta: float) -> void:
	_follow(delta)
	_readout()


func _physics_process(_delta: float) -> void:
	bike.throttle = Input.get_action_strength(&"move_forward")
	bike.brake = Input.get_action_strength(&"move_back")
	bike.steering = Input.get_axis(&"move_right", &"move_left")
	bike.rider = float(Input.is_physical_key_pressed(KEY_DOWN)) - float(
			Input.is_physical_key_pressed(KEY_UP))
	bike.rear_brake = Input.is_action_pressed(&"jump")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_R:
			reset()
		KEY_TAB:
			section = (section + 1) % SECTIONS.size()
			reset()
		KEY_1:
			_spring = (_spring + 1) % SPRINGS.size()
			for wheel in bike.wheels:
				wheel.stiffness = SPRINGS[_spring]
				wheel.damping = 1600.0 * sqrt(SPRINGS[_spring] / SPRINGS[1])
		KEY_2:
			bike.air_control = not bike.air_control
		KEY_3:
			bike.balance_enabled = not bike.balance_enabled
		KEY_4:
			_loose = not _loose
			bike.grip = 0.55 if _loose else 0.95
		KEY_5:
			_close_camera = not _close_camera


func reset() -> void:
	var pose: Transform3D = _spawns[section].global_transform
	bike.reset_at(pose)
	_facing = -pose.basis.z
	_camera.global_position = pose.origin - _facing * follow_distance + Vector3.UP * follow_height
	_camera.look_at(pose.origin + Vector3.UP * 0.6)
	_landing_note = "прыжка ещё не было"


func _follow(delta: float) -> void:
	var forward: Vector3 = (-bike.global_basis.z).slide(Vector3.UP).normalized()
	if forward.length_squared() < 0.1:
		forward = _facing
	_facing = _facing.lerp(forward, 1.0 - exp(-4.0 * delta)).normalized()
	var distance: float = 3.4 if _close_camera else follow_distance
	var height: float = 1.6 if _close_camera else follow_height
	var focus: Vector3 = bike.global_position + Vector3.UP * 0.65
	var wanted: Vector3 = focus - _facing * distance + Vector3.UP * height
	var query := PhysicsRayQueryParameters3D.create(focus, wanted, 1, [bike.get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		wanted = hit.position + hit.normal * 0.25
	_camera.global_position = _camera.global_position.lerp(wanted, 1.0 - exp(-7.0 * delta))
	_camera.look_at(focus + _facing * 2.0)
	_camera.fov = lerpf(_camera.fov, 65.0 + minf(absf(bike.speed) * 0.35, 12.0), delta * 4.0)


func _readout() -> void:
	var status := "[color=#ff8a6a]падение — R подняться[/color]" if bike.fallen else (
			"в воздухе %.2f с" % bike.airborne if bike.contacts == 0 else "на колёсах")
	_hud.text = "\n".join(PackedStringArray([
		"[b]%d км/ч[/b]   %s   участок: %s" % [roundi(bike.speed * 3.6), status, SECTIONS[section]],
		"нос %+.0f°   крен %+.0f°   контакт %d/2" % [
			rad_to_deg(bike.pitch), rad_to_deg(bike.lean), bike.contacts],
		"сжатие перед/зад: %.0f / %.0f мм   пробоев: %d" % [
			bike.wheels[0].compression * 1000.0, bike.wheels[1].compression * 1000.0, bike.bottomed],
		_landing_note,
		"",
		"W газ   S тормоз   A/D руль   ↑/↓ наклон тела   ПРОБЕЛ задний тормоз   R заново   TAB участок",
		"1 подвеска: %s" % ["мягкая", "штатная", "жёсткая"][_spring],
		"2 помощь тангажу в воздухе: %s" % _switch(bike.air_control),
		"3 помощь равновесию на земле: %s" % _switch(bike.balance_enabled),
		"4 сцепление: %s" % ("рыхло, 0.55" if _loose else "плотно, 0.95"),
		"5 камера: %s" % ("близко" if _close_camera else "погоня"),
		"",
		"[color=#66ccff]%s[/color]" % HYPOTHESIS,
	]))


func _switch(on: bool) -> String:
	return "вкл" if on else "выкл"


func _on_bike_landed(seconds: float, distance: float, closing_speed: float) -> void:
	_landing_note = "прыжок %.2f с / %.1f м   скорость к склону при касании %.1f м/с" % [
		seconds, distance, closing_speed]


func _on_bike_crashed() -> void:
	_landing_note = "[color=#ff8a6a]равновесие потеряно — R повторить участок[/color]"

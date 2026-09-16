class_name SplitRig
extends Node3D
## TWO WORLDS OVER ONE GROUND, AND ONE PAIR OF HANDS THAT HOLDS EITHER HERO.
##
## The rig owns everything that is not a thing in the world: both cameras, the screen, the keys and
## the readout. Heroes, bridges and switches read no input and hold no camera, so the same scenes
## go into a two-player mix without a single change.
##
## A split mechanic has to be accepted by one person, or it is not accepted until two people
## happen to be in a room. Hence TAB: the hands move to the other hero, and the first one stays
## where it was left, its half of the screen still watching. Pull a lever on one side, then look
## across the divider — that is the whole mechanic, played alone.

enum Screen {
	SPLIT,
	MINE,
	OTHER,
}

## Metres behind the head the camera sits. Close enough that a hero standing on a bridge the other
## world cannot see is still big on its half of the screen.
const CAMERA_DISTANCE := 4.5
## Height of the head above the feet, m.
const CAMERA_HEIGHT := 1.6
## How far the view may tilt, radians: down to the feet, up a little past the horizon.
const PITCH_DOWN := 1.2
const PITCH_UP := 0.5
## A hero past this line along -Z has crossed the pit, m.
const FAR_SIDE := -14.0
const WORLD_NAMES: Array[String] = ["фантастика", "фэнтези"]
const VERDICT := ("вид делится слоями сам, вместе со светом и тенью; мир — нет: физика у двоих"
		+ " одна, и делить её приходится руками")

## Degrees of turn per pixel of mouse travel.
@export_range(0.05, 1.0, 0.01) var look_speed := 0.2

var _hands := 0
var _screen := Screen.SPLIT
var _method := SplitDual.Method.LAYERS
var _shared_physics := false
var _pitch := PackedFloat32Array([-0.35, -0.35])

@onready var _heroes: Array[SplitHero] = [$HeroScifi, $HeroFantasy]
@onready var _halves: Array[SubViewportContainer] = [$Ui/Views/Left, $Ui/Views/Right]
@onready var _views: Array[SubViewport] = [$Ui/Views/Left/View, $Ui/Views/Right/View]
@onready var _cameras: Array[Camera3D] = [
	$Ui/Views/Left/View/Camera,
	$Ui/Views/Right/View/Camera,
]
@onready var _scifi_bridge: SplitBridge = $ScifiBridge
@onready var _fantasy_bridge: SplitBridge = $FantasyBridge
@onready var _divider: ColorRect = $Ui/Marks/Divider
@onready var _hands_mark: ColorRect = $Ui/Marks/Hands
@onready var _hud: RichTextLabel = $Ui/Info


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for view in _views:
		# Both halves look into THIS world. A SubViewport otherwise starts an empty one of its own,
		# and the half is simply black, without an error.
		view.world_3d = get_viewport().world_3d
		RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	_apply_screen()


func _process(_delta: float) -> void:
	_drive()
	for i in 2:
		_place_camera(_cameras[i], _heroes[i], _pitch[i])
	_readout()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event
		_heroes[_hands].yaw -= deg_to_rad(motion.relative.x * look_speed)
		_pitch[_hands] = clampf(
				_pitch[_hands] - deg_to_rad(motion.relative.y * look_speed),
				-PITCH_DOWN,
				PITCH_UP)
		return
	if event.is_action_pressed(&"respawn"):
		_heroes[_hands].respawn()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	_apply_key(key.keycode)


func _apply_key(keycode: Key) -> void:
	match keycode:
		KEY_TAB:
			_hands = 1 - _hands
			_apply_screen()
		KEY_E:
			var lever := _reachable(_heroes[_hands])
			if lever != null:
				lever.use()
		KEY_1:
			_screen = ((_screen + 1) % Screen.size()) as Screen
			_apply_screen()
		KEY_2:
			_method = (SplitDual.Method.SHADER if _method == SplitDual.Method.LAYERS
					else SplitDual.Method.LAYERS)
			for node in get_tree().get_nodes_in_group(&"split_dual"):
				var dual: SplitDual = node
				dual.method = _method
		KEY_3:
			_shared_physics = not _shared_physics
			for hero in _heroes:
				hero.touches_other_world = _shared_physics
		KEY_ESCAPE:
			Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
					if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
					else Input.MOUSE_MODE_CAPTURED)


## The held hero gets the keys; the other gets nothing, so it stops instead of walking on with
## whatever it was last told.
func _drive() -> void:
	var held := _heroes[_hands]
	var idle := _heroes[1 - _hands]
	held.move = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	held.jumping = Input.is_action_pressed(&"jump")
	idle.move = Vector2.ZERO
	idle.jumping = false


func _place_camera(camera: Camera3D, hero: SplitHero, pitch: float) -> void:
	var head := hero.global_position + Vector3.UP * CAMERA_HEIGHT
	var aim := Basis(Vector3.UP, hero.yaw) * Basis(Vector3.RIGHT, pitch)
	camera.global_position = head + aim * Vector3(0.0, 0.0, CAMERA_DISTANCE)
	camera.look_at(head, Vector3.UP)


## A hidden half is not drawn at all: its SubViewport stops updating together with its container,
## so MINE and OTHER measure what one view costs against two.
func _apply_screen() -> void:
	var mine := _halves[_hands]
	var other := _halves[1 - _hands]
	mine.visible = _screen != Screen.OTHER
	other.visible = _screen != Screen.MINE
	_divider.visible = _screen == Screen.SPLIT
	_hands_mark.visible = _screen == Screen.SPLIT
	_hands_mark.set_anchor_and_offset(SIDE_LEFT, 0.5 * _hands, 0.0)
	_hands_mark.set_anchor_and_offset(SIDE_RIGHT, 0.5 * (_hands + 1), 0.0)


func _reachable(hero: SplitHero) -> SplitSwitch:
	var found: SplitSwitch = null
	for node in get_tree().get_nodes_in_group(&"split_switch"):
		var lever: SplitSwitch = node
		if found == null and lever.can_reach(hero):
			found = lever
	return found


func _readout() -> void:
	var held := _heroes[_hands]
	var near := _reachable(held)
	var crossed := 0
	for hero in _heroes:
		if hero.global_position.z < FAR_SIDE and hero.global_position.y > -1.0:
			crossed += 1
	var lines := PackedStringArray([
		"руки: [b]%s[/b], %s половина   на том берегу: [b]%d из 2[/b]%s" % [
			WORLD_NAMES[_hands], "левая" if _hands == 0 else "правая", crossed,
			"   рядом %s — E" % near.title if near != null else ""],
		"мост фантастики: %s   его поднимает руна в мире фэнтези" % _raised(_scifi_bridge),
		"мост фэнтези: %s   его поднимает пульт в мире фантастики" % _raised(_fantasy_bridge),
		"левая половина: %s" % _cost(0),
		"правая половина: %s" % _cost(1),
		"",
		"WASD идти   мышь смотреть   ПРОБЕЛ прыжок   E дёрнуть   TAB другой герой   R на старт",
		"1 экран: %s" % ["пополам", "только мой герой", "только чужой герой"][_screen],
		"2 два прочтения: %s" % (
			"два меша, каждый на слое своего мира" if _method == SplitDual.Method.LAYERS
			else "один меш, шейдер читает слой камеры — форма общая"),
		"3 физика: %s" % (
			"[color=#ffd479]одна на двоих — чужой мост держит, чужой пульт мешает[/color]"
			if _shared_physics else "у каждого своя"),
		"",
		"[color=#66ccff]%s[/color]" % VERDICT,
	])
	_hud.text = "\n".join(lines)


func _raised(bridge: SplitBridge) -> String:
	return "[color=#7fe08a]поднят[/color]" if bridge.raised else "внизу"


## What drawing one half cost last frame. Shadow draw calls are counted with the rest: each half
## renders its own directional shadow maps, and they are part of the price of a second view.
func _cost(index: int) -> String:
	if not _halves[index].visible:
		return "не рисуется"
	var rid := _views[index].get_viewport_rid()
	var calls := (RenderingServer.viewport_get_render_info(
				rid,
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
			+ RenderingServer.viewport_get_render_info(
				rid,
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
	return "%.2f мс процессора, %.2f мс видеокарты, %d вызовов отрисовки" % [
		RenderingServer.viewport_get_measured_render_time_cpu(rid),
		RenderingServer.viewport_get_measured_render_time_gpu(rid),
		calls]

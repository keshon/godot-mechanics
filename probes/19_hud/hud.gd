class_name HudArena
extends Node3D
## 19 — the combat HUD. Two halves that look like one thing and are not.
##
##   the bar      an interface made of clocks: cooldowns, a global cooldown, charges,
##                a cast that a step can break.
##   the overlay  an interface made of geometry: the world projected onto the screen,
##                and everything that goes wrong when the target is behind you.
##
## WASD moves and breaks a cast. 1..6 use abilities. C swaps the cooldown to the wrong
## way of counting. H stops updating the bar, the way a closed panel would. U takes
## away the behind-the-camera guard. TAB spins the camera.

const SPIN_RATE := 0.9
const HERO_SPEED := 7.0

@export_range(4, 200) var count := 10
@export var spin := 0.0

var enemies: Array[Dictionary] = []
var hero := Vector3.ZERO
var hits := 0
var yaw := 0.0
## Game time, seconds. The bar reads it and stores none of its own.
var clock := 0.0
## False = the bar is still in the tree but nobody ticks it. The whole point of the
## probe in one boolean.
var awake := true

var _random := RandomNumberGenerator.new()

@onready var _bar: HudBar = $Ui/Root/Bar
@onready var _overlay: HudOverlay = $Ui/Overlay
@onready var _rig: Node3D = $Rig
@onready var _hero_mesh: MeshInstance3D = $Hero
@onready var _foes: MultiMeshInstance3D = $Foes
@onready var _info: RichTextLabel = $Ui/Root/Info


func _ready() -> void:
	_overlay.setup($Rig/Camera)
	_bar.cast_done.connect(_on_bar_cast_done)
	_spawn()


func _process(delta: float) -> void:
	_move(delta)
	_wander(delta)
	clock += delta
	_bar.tick(clock, awake)
	_overlay.tick(delta, enemies)
	yaw += spin * delta
	_rig.rotation.y = yaw
	_rig.position = hero
	_hero_mesh.position = hero + Vector3(0, 0.9, 0)
	_paint()
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_bar.press(event.keycode - KEY_1)
		KEY_C:
			_bar.countdown_mode = not _bar.countdown_mode
		KEY_H:
			awake = not awake
		KEY_U:
			_overlay.guard = not _overlay.guard
		KEY_TAB:
			spin = 0.0 if spin != 0.0 else SPIN_RATE
		KEY_R:
			_spawn()
		KEY_SPACE:
			count = 10 if count > 60 else 120
			_spawn()


func _spawn() -> void:
	_random.seed = 8
	enemies.clear()
	for _i in count:
		var angle := _random.randf() * TAU
		var away := _random.randf_range(4.0, 17.0)
		enemies.append({
			"position": Vector3(cos(angle) * away, 0.0, sin(angle) * away),
			"hp": 60.0,
			"hp_max": 60.0,
			"phase": _random.randf() * TAU,
		})
	hits = 0


func _move(delta: float) -> void:
	var wanted := Vector3(
			Input.get_action_strength(&"move_right")
			- Input.get_action_strength(&"move_left"),
			0.0,
			Input.get_action_strength(&"move_back")
			- Input.get_action_strength(&"move_forward"))
	if wanted == Vector3.ZERO:
		return
	# Moving breaks a cast. One line, and it is most of what casting FEELS like.
	_bar.break_cast()
	var facing := Basis.from_euler(Vector3(0, yaw, 0))
	hero += facing * wanted.normalized() * HERO_SPEED * delta


func _wander(delta: float) -> void:
	for enemy in enemies:
		if enemy["hp"] <= 0.0:
			continue
		enemy["phase"] += delta * 0.7
		var to_hero: Vector3 = hero - enemy["position"]
		var drift := Vector3(cos(enemy["phase"]), 0.0, sin(enemy["phase"])) * 1.2
		if to_hero.length() > 6.0:
			enemy["position"] += (to_hero.normalized() * 2.0 + drift) * delta
		else:
			enemy["position"] += drift * delta


func _paint() -> void:
	var mesh: MultiMesh = _foes.multimesh
	mesh.instance_count = enemies.size()
	for i in enemies.size():
		var enemy: Dictionary = enemies[i]
		var alive: bool = enemy["hp"] > 0.0
		mesh.set_instance_transform(i, Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * (1.0 if alive else 0.001)),
				enemy["position"] + Vector3(0, 0.7, 0)))
		mesh.set_instance_color(i, Color(0.9, 0.4, 0.35))


func _draw_hud() -> void:
	var alive := 0
	for enemy in enemies:
		if enemy["hp"] > 0.0:
			alive += 1
	var text := "[b]%d enemies, %d alive[/b]    %d hits landed\n\n" % [
		enemies.size(), alive, hits]
	text += "[b]C  how the cooldown is counted:[/b]  %s\n" % (
			"[color=#ff8a6a]left -= delta   (stops when the bar stops)[/color]"
			if _bar.countdown_mode else "[color=#7fe08a]a moment it ends[/color]")
	text += "[b]H  bar updated:[/b]  %s\n" % (
			"[color=#7fe08a]yes[/color]" if awake
			else "[color=#ff8a6a]NO — hold a cooldown, wait, press H again[/color]")
	text += "[b]U  behind-the-camera guard:[/b]  %s\n" % (
			"[color=#7fe08a]on[/color]" if _overlay.guard
			else "[color=#ff8a6a]off — look away from them[/color]")
	text += "   behind the camera now: %d    arrows on the rim: %d, wrong way %d\n\n" % [
		_overlay.behind_now, _overlay.arrows_now, _overlay.wrong_arrows]
	text += "floating numbers alive %d, pool %d    overlay draw %.0f us\n" % [
		_overlay.live_count(), _overlay.floats.size(), _overlay.draw_usec]
	text += "casts fired %d, refused %d\n\n" % [_bar.fired, _bar.refused]
	text += "WASD move (breaks a cast)   1..6 abilities   TAB spin the camera\n"
	text += "SPACE 10 or 120 enemies   R reset"
	_info.text = text


func _on_bar_cast_done(slot: int) -> void:
	var ability: Dictionary = HudBar.ABILITIES[slot]
	var head := hero + Vector3(0, 1.6, 0)
	if ability["name"] == "Dash":
		hero += Basis.from_euler(Vector3(0, yaw, 0)) * Vector3(0, 0, -5.0)
		_overlay.add_float(head, "dash", Color(0.6, 0.95, 0.7))
		return
	if float(ability["damage"]) <= 0.0:
		_overlay.add_float(head, "+30", Color(0.5, 0.95, 0.55))
		return
	var reach := 14.0 if ability["aoe"] else 7.0
	var struck := 0
	for enemy in enemies:
		if enemy["hp"] <= 0.0 or enemy["position"].distance_to(hero) > reach:
			continue
		var dealt: float = float(ability["damage"]) * _random.randf_range(0.85, 1.15)
		var crit := _random.randf() < 0.2
		if crit:
			dealt *= 2.0
		enemy["hp"] = maxf(enemy["hp"] - dealt, 0.0)
		_overlay.add_float(
				enemy["position"] + Vector3(0, 1.7, 0),
				"%d%s" % [roundi(dealt), "!" if crit else ""],
				Color(1, 0.9, 0.35) if crit else Color(1, 1, 1))
		struck += 1
		hits += 1
		if not ability["aoe"]:
			break
	if struck == 0:
		_overlay.add_float(hero + Vector3(0, 1.9, 0), "out of reach", Color(1, 0.5, 0.45))

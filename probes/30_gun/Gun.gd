extends Node3D

# 30 — a shot is a chord.
#
# Pull the trigger once and eight things happen inside two hundred milliseconds. None of
# them is "the shot"; the feel lives in which ones fire, and WHEN. Every layer is on its
# own digit, so you can take the chord apart note by note and hear what each one was
# holding up.
#
#   1 вспышка      a light for a few frames. The LIGHT, not the sprite: a muzzle flash
#                  that does not light the room is a sticker.
#   2 трассер      a stretched quad along the path, alive about forty milliseconds.
#   3 дырка        a Decal, oriented by the SURFACE, not by the bullet.
#   4 искры        one-shot particles thrown along the normal.
#   5 гильза       a real rigid body, ejected a moment AFTER the shot.
#   6 отдача       the barrel climbs and settles. This is what makes a burst feel heavy.
#   7 тряска       the camera is knocked, briefly.
#   8 подвисание   time stops for a few dozen milliseconds. DOOM's secret ingredient, and
#                  the one that turns into a bug the instant it is too long.

const RATE := 0.095          ## seconds between shots
const RANGE := 60.0

## ПОВЕРХНОСТИ. Сталь бросает густой сноп быстрых бело-калёных осколков; дерево — горстку
## тусклых угольков и в основном пыль; бетон — что-то среднее, серое. Один и тот же сноп на
## любом материале превращает тир в картонную декорацию, и это замечает даже тот, кто не
## может объяснить, что именно не так.
const SURFACES := {
	"Wood": {"count": 9, "speed": 5.0, "life": 0.32, "streak": 0.010,
		"hot": Color(1.0, 0.62, 0.28), "hole": Color(0.34, 0.23, 0.12)},
	"Metal": {"count": 30, "speed": 16.0, "life": 0.8, "streak": 0.034,
		"hot": Color(1.0, 0.98, 0.9), "hole": Color(0.82, 0.83, 0.86)},
	"": {"count": 15, "speed": 9.0, "life": 0.5, "streak": 0.020,
		"hot": Color(1.0, 0.86, 0.6), "hole": Color(0.62, 0.61, 0.58)},
}

@export var flash := true
## 0 нет, 1 каждый третий, 2 каждый. Настоящие ленты снаряжают один трассер на четыре-пять
## — иначе видно не полёт, а геометрию разброса.
@export_range(0, 2) var tracer_mode := 1
## Пламегаситель не гасит пламя: он рассекает струю газа, и та же энергия расходится по
## большему углу. Вспышка становится шире, тусклее и заметно короче со стороны стрелка.
@export var hider := false
@export var decals := true
@export var sparks := true
@export var shells := true
@export var recoil := true
@export var shake := true
@export var hitstop := true

## Frames the muzzle light lives. One is invisible at high framerate and obvious at low —
## the flash has to be measured in TIME, not in frames, or it changes with the machine.
@export_range(0.01, 0.12) var flash_time := 0.045
@export_range(0.0, 0.14) var hitstop_time := 0.035

var shots := 0
var ms_frame := 0.0
var holes := 0

var _fx: GunFx
var _next := 0.0
var _clock := 0.0
var _flash_until := 0.0
var _stop_until := 0
var _kick := 0.0
var _kick_v := 0.0
var _shake := 0.0
var _yaw := 0.0
var _pitch := -0.05
var _shell_at := 0.0
var _pos := Vector3.ZERO


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_fx = $Fx as GunFx
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# THE viewmodel trick, and it is not "make the gun bigger". A shooter draws the world at
	# 80-100 degrees and the WEAPON at 50-65, through a second camera on its own visual
	# layer, composited over the top. That is why a rifle in Battlefield looks heavy and the
	# same rifle glued to a 78-degree camera looks like a toy: at a wide field of view
	# anything close to the eye is squeezed and warped, and the eye reads that as small.
	#
	# Main camera: everything except layer 2. Weapon camera: layer 2 only, transparent
	# background, sharing the same World3D so the same lights reach it. Probe 25 met the
	# empty-World3D trap already; here it is the same one line.
	var sub: SubViewport = $Hands/Wrap/Sub
	# NOT a shared World3D this time. The viewmodel needs its OWN lights and they must not
	# touch the level; with a shared world, lights confined by light_cull_mask leaked out and
	# lit the wall anyway. A private world settles it: three lamps in there reach the weapon
	# and nothing else, and the gun is lit the same in a dark room and a bright one — which
	# is what every shooter does, and why the weapon always reads.
	sub.own_world_3d = true


func _process(delta: float) -> void:
	_clock += delta
	_walk(delta)
	# Aim and hold BEFORE firing: the muzzle the flash and the tracer come out of has to be
	# where the weapon is THIS frame, not where it was last one.
	_aim()
	_hold()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _clock >= _next:
		_next = _clock + RATE
		_shoot()
	# Delayed ejection: the case leaves after the shot, not with it. Forty milliseconds is
	# nothing to read about and everything to look at — with zero delay the shell appears
	# inside the flash and reads as part of it.
	if _shell_at > 0.0 and _clock >= _shell_at:
		_shell_at = 0.0
		if shells:
			var port: Node3D = $Hands/Wrap/Sub/Weapon/Port
			var t := ($Cam as Camera3D).global_transform * port.global_transform
			_fx.shell(t.origin, t.basis.x, t.basis.y)

	($Muzzle as OmniLight3D).visible = _clock < _flash_until
	var fl: MeshInstance3D = $Hands/Wrap/Sub/Weapon/Muzzle/Flash
	fl.visible = _clock < _flash_until
	if fl.visible:
		var age := 1.0 - (_flash_until - _clock) / maxf(flash_time, 0.001)
		(fl.material_override as ShaderMaterial).set_shader_parameter(
			"age", clampf(age, 0.0, 1.0))
	# hitstop is measured on the REAL clock: delta is what we are distorting, so it cannot
	# also be what times the distortion
	if _stop_until > 0 and Time.get_ticks_msec() >= _stop_until:
		_stop_until = 0
		Engine.time_scale = 1.0

	# Slower and larger: 120 was a 1.7 Hz buzz, and a buzz reads as a rattle, not a kick.
	_kick_v -= _kick * 62.0 * delta        # a spring, not a fade: it overshoots and settles
	_kick_v *= exp(-6.5 * delta)
	_kick += _kick_v * delta
	_shake *= exp(-7.5 * delta)
	# The weapon camera follows nothing: in its own world it stands at the origin and the
	# weapon hangs in front of it. A viewmodel is always before your eyes, so there is
	# nothing for it to track.
	ms_frame = lerpf(ms_frame,
		RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		0.05)
	_hud()


func _shoot() -> void:
	shots += 1
	var cam: Camera3D = $Cam
	var from := cam.global_position
	# SPREAD, and it is not a nicety. Without it every shot lands on the same pixel, forty
	# eight holes stack into one, and the wall looks untouched after a magazine. The cone
	# GROWS with the recoil already in the barrel, which is what makes holding the trigger
	# feel different from tapping it.
	var cone := 0.006 + _kick * 0.045
	var dir := (-cam.global_transform.basis.z
		+ cam.global_transform.basis.x * randf_range(-cone, cone)
		+ cam.global_transform.basis.y * randf_range(-cone, cone)).normalized()
	var hit_at := from + dir * RANGE
	var normal := -dir

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		hit_at = r["position"]
		normal = r["normal"]

	# The muzzle lives in the VIEWMODEL world, whose camera sits at the origin looking down
	# -Z. That makes its position there identical to a position in eye space, so one matrix
	# multiply puts it back into the real world — where the light, the tracer and the ray all
	# need it. Two worlds, one transform between them.
	var muzzle_vm: Node3D = $Hands/Wrap/Sub/Weapon/Muzzle
	var muzzle_world: Vector3 = cam.global_transform * muzzle_vm.global_position
	if flash:
		_flash_until = _clock + flash_time
		($Muzzle as OmniLight3D).global_position = muzzle_world
		# A flash hider does not make the shot dimmer for everyone — it spreads the gas, so
		# the SHOOTER sees much less of it. Hence the light drops with the hider on.
		($Muzzle as OmniLight3D).light_energy = 5.0 if hider else 9.0
		var fm: ShaderMaterial = ($Hands/Wrap/Sub/Weapon/Muzzle/Flash as MeshInstance3D).material_override
		fm.set_shader_parameter("hider", 1.0 if hider else 0.0)
		fm.set_shader_parameter("seed", randf())
		# In first person you are ALWAYS looking down your own barrel, so the projected
		# direction is near zero and the flash comes out as a symmetric star. The long
		# sideways flame in the references is the same flash seen from outside.
		fm.set_shader_parameter("barrel_screen", Vector2(muzzle_vm.global_position.x * 0.4, 0.0))
	# Fired from the WEAPON's muzzle, not from a point near the eye. Starting a hand's width
	# from the face draws the spread cone as a visible fan, and the gun reads as enormous —
	# which is exactly what a player said when it did.
	if tracer_mode == 2 or (tracer_mode == 1 and shots % 3 == 0):
		_fx.tracer(muzzle_world, hit_at)
	if not r.is_empty():
		var surf: Dictionary = _surface_of(r["collider"])
		if decals:
			_fx.hole(hit_at, normal, dir, surf["hole"])
			holes = mini(holes + 1, GunFx.DECALS)
		if sparks:
			_fx.sparks(hit_at, normal, dir, surf)
	if shells:
		_shell_at = _clock + 0.04
	if recoil:
		_kick_v += 4.6
		# CLAMPED, and it has to be. The spring settles in about a fifth of a second; fire
		# faster than that and the kicks stack, the barrel walks off the top of the screen
		# and every shot misses. Found by firing forty times a second, which no player does
		# and every stress test should.
		_kick = minf(_kick, 1.3)
		_kick_v = minf(_kick_v, 9.0)
	if shake:
		_shake = 0.032
	# NOT re-armed while already running. Each shot extending the freeze means a fast enough
	# weapon pins Engine.time_scale at 0.06 for good: the game simply stops. A hitstop is an
	# event, not a state, and events do not stack.
	if hitstop and _stop_until == 0:
		# Engine.time_scale, not a manual multiplier: it slows physics and particles too,
		# which is the whole point — a hitstop that freezes only the camera reads as a stutter.
		Engine.time_scale = 0.06
		_stop_until = Time.get_ticks_msec() + int(hitstop_time * 1000.0)


## Moves the EYE, not the scene root. The first version moved `position` — and the walls,
## the floor and the crates are all children of that same root, so the whole world walked
## along with the player and nothing moved relative to anything. The coordinate changed, the
## picture did not, and it read as "WASD does not work".
##
## Anything that is the parent of the world cannot also be the player.
## Which material was hit. The node name is the whole lookup — enough for a probe; a real
## game would put a physics material or a group on the body.
func _surface_of(body: Object) -> Dictionary:
	var n: String = (body as Node).name if body is Node else ""
	for key in SURFACES:
		if key != "" and n.begins_with(key):
			return SURFACES[key]
	return SURFACES[""]


func _walk(delta: float) -> void:
	var v := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if v != Vector3.ZERO:
		_pos += Basis(Vector3.UP, _yaw) * v.normalized() * 5.5 * delta
	_pos.x = clampf(_pos.x, -13.0, 13.0)
	_pos.z = clampf(_pos.z, -13.0, 13.0)


## The gun in the hand. Everything a viewmodel does is a lie about weight: it lags the
## camera, dips when you walk, and climbs with the recoil the barrel already has. Without
## it the flash hangs in the air and the shells come out of nothing.
func _hold() -> void:
	var w: Node3D = $Hands/Wrap/Sub/Weapon
	var bob := sin(_clock * 9.5) * 0.008
	# Two overcorrections later: at 0.34 m and full size it filled a quarter of the screen,
	# at 0.58 m and 0.55 it read as a toy. A shooter's weapon takes the bottom third — big
	# enough to have weight, small enough to leave the sights room.
	w.position = Vector3(0.24, -0.24 + bob, -0.62 + _kick * 0.07)
	# БЕЗ доворота и крена. Я попробовал развернуть оружие, чтобы читались сразу верх и бок,
	# — и потерял главное: ствол перестал смотреть туда, куда смотрит игрок. Форму лучше
	# набирать ступенькой силуэта (ресивер толще цевья), а ось оставить параллельной взгляду.
	w.rotation = Vector3(_kick * 0.16, 0.0, 0.0)


func _aim() -> void:
	var cam: Camera3D = $Cam
	cam.rotation = Vector3(_pitch + _kick * 0.06, _yaw, 0.0)
	# SMOOTH shake, not a fresh random offset every frame. Per-frame noise is white noise,
	# and white noise at frame rate is a tremble: the player sees the crates buzzing rather
	# than the camera being knocked. Two sines of unrelated frequency wander instead.
	var t := _clock * 26.0
	cam.position = _pos + Vector3(
		(sin(t) + 0.55 * sin(t * 1.73)) * _shake,
		1.6 + (cos(t * 1.31) + 0.55 * cos(t * 2.11)) * _shake, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0032
		_pitch = clampf(_pitch - event.relative.y * 0.0032, -1.3, 1.3)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1:
			flash = not flash
		KEY_2:
			tracer_mode = (tracer_mode + 1) % 3
		KEY_9:
			hider = not hider
		KEY_3:
			decals = not decals
		KEY_4:
			sparks = not sparks
		KEY_5:
			shells = not shells
		KEY_6:
			recoil = not recoil
		KEY_7:
			shake = not shake
		KEY_8:
			hitstop = not hitstop
		KEY_0:
			flash = true
			tracer_mode = 1
			decals = true
			sparks = true
			shells = true
			recoil = true
			shake = true
			hitstop = true
		KEY_R:
			_fx.clear_all()
			holes = 0
			shots = 0
		KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if
				Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED)


func _row(on: bool, key: String, name: String) -> String:
	return "[cell]%s  [/cell][cell]%s%s[/color][/cell]" % [key,
		"[color=#7fe08a]" if on else "[color=#555a63]", name]


func _hud() -> void:
	var t := "[b]СТРЕЛЬБА[/b]    выстрелов %d\n\n" % shots
	t += "[table=2]"
	t += _row(flash, "1", "вспышка — свет на %.0f мс" % (flash_time * 1000.0))
	t += _row(hider, "9", "пламегаситель — шире, тусклее, короче")
	t += _row(tracer_mode > 0, "2", "трассер: %s" % ["нет", "каждый третий", "каждый"][tracer_mode])
	t += _row(decals, "3", "дырка (в кольце %d, занято %d)" % [GunFx.DECALS, holes])
	t += _row(sparks, "4", "искры — направление от угла удара, длина от скорости")
	t += _row(shells, "5", "гильза — через 40 мс после выстрела")
	t += _row(recoil, "6", "отдача — пружина, а не затухание")
	t += _row(shake, "7", "тряска")
	t += _row(hitstop, "8", "подвисание — %.0f мс на 6%% скорости" % (hitstop_time * 1000.0))
	t += "[cell]кадр  [/cell][cell]%.2f мс на GPU[/cell]" % ms_frame
	t += "[/table]\n\n"
	t += "ЛКМ — огонь (удерживать)    WASD — ходить    мышь — целиться\n"
	t += "1…8 — слои по одному    0 — включить всё    R — стереть следы    ESC — мышь\n"
	t += "[color=#66ccff]выключай по одному и слушай, чего не хватает[/color]"
	$Ui/Info.text = t

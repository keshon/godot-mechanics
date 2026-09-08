extends Node3D
class_name ShoulderLauncher

## THE TUBE ON A SHOULDER.
##
## Three things the forty-fourth and forty-fifth probes had no room for, because neither of
## them had a person holding anything.
##
## The tube VENTS BACKWARDS. A recoilless launcher throws as much gas aft as it throws mass
## forward, and that gas is the reason it can sit on a shoulder at all. It is also the reason
## the weapon cannot be fired from a room, from behind a wall, or with anybody standing
## behind — and that is a position rule, not a damage number.
##
## RELOADING TAKES A WHILE. Between shots the shooter is a man holding a pipe.
##
## And the ROUND IS A SCENE, handed out rather than owned: what happens to it afterwards is
## not the tube's business.
##
## Reads no keys. `aim()` points it, `fire()` pulls the trigger.

signal fired(shot: ShoulderRound)
signal refused(why: String)

@export var round_scene: PackedScene
@export_range(0.5, 20.0, 0.1) var reload := 6.0
@export_range(1, 12, 1) var rounds := 6
## How far back the jet is still dangerous, and how wide. The distance lives on the raycast
## node in the scene, so it is dragged rather than typed.
@export_range(0.0, 4.0, 0.05) var flash_time := 0.35
## THE SIGHT IS A RANGE SCALE, not a crosshair. An unguided round drops nearly ten metres over
## a hundred and sixty, so the tube is held ABOVE the line of sight by an angle the shooter
## dials in. Dial it wrong and the round lands short or long — that is the whole cost of an
## unguided launcher, and it is paid before the trigger rather than after it.
@export_range(20.0, 600.0, 10.0) var sight_range := 160.0
## The speed the scale is cut for. A sight belongs to one round; hand the tube a different one
## and every mark on it lies.
@export_range(20.0, 500.0, 5.0) var sight_speed := 170.0

var left := 0
var ready_in := 0.0
var blocked := false      ## something is standing in the backblast right now
var last := ""

@onready var _muzzle: Node3D = $Muzzle
@onready var _blast: RayCast3D = $Blast
@onready var _flash: Node3D = $Blast/Flash

var _flash_left := 0.0


func _ready() -> void:
	left = rounds
	if _flash != null:
		_flash.visible = false


func _physics_process(delta: float) -> void:
	ready_in = maxf(0.0, ready_in - delta)
	blocked = _blast != null and _blast.is_colliding()
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash != null:
			_flash.visible = _flash_left > 0.0


## Where the tube points. The hand writes this; the tube has no opinion.
func aim(dir: Vector3, up: Vector3) -> void:
	if dir.length_squared() < 1e-6:
		return
	look_at(global_position + dir, up)


## The trigger. Refusing is a result, not an error: a launcher that fires into a wall behind
## the shooter is a launcher that has never been carried.
##
## The round comes back UNLAUNCHED. A node outside the tree has no world transform, so lighting
## it here and parenting it afterwards means launching from nowhere; the tube hands it over and
## whoever takes it decides where it lives.
func fire() -> ShoulderRound:
	if left <= 0:
		last = "пусто"
		refused.emit(last)
		return null
	if ready_in > 0.0:
		last = "перезаряжается"
		refused.emit(last)
		return null
	if blocked:
		last = "струя упирается — стрелять нельзя"
		refused.emit(last)
		return null
	if round_scene == null:
		return null
	var shot := round_scene.instantiate() as ShoulderRound
	left -= 1
	ready_in = reload
	_flash_left = flash_time
	if _flash != null:
		_flash.visible = true
	last = ""
	fired.emit(shot)
	return shot


func reset() -> void:
	left = rounds
	ready_in = 0.0
	_flash_left = 0.0
	last = ""
	if _flash != null:
		_flash.visible = false


## How far above the line of sight the tube is held, in radians. Straight out of the ballistic
## range equation, which is why the far marks on a real scale crowd together.
func elevation() -> float:
	var s := clampf(9.81 * sight_range / (sight_speed * sight_speed), -1.0, 1.0)
	return 0.5 * asin(s)


## Where the round leaves from, in world space. The sight rides on this and not on the eye:
## the beam a round follows is the one the TUBE is holding, and the two differ by the width
## of a shoulder — which is exactly the error a beam rider has to gather out at short range.
func muzzle() -> Transform3D:
	return _muzzle.global_transform

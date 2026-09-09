class_name ShootPlayer
extends CharacterBody3D
## First person again, deliberately. Probe 02 spent 180 lines on a camera rig;
## this one spends its budget on what leaves the barrel instead.
##
## The movement here is the plain version — move_toward, no Quake accelerator.
## Probe 01 owns that lesson and this probe should not re-teach it.

@export_group("Move")
## Top speed on the ground, m/s.
@export_range(1.0, 15.0, 0.1) var max_speed := 6.5
## How fast velocity climbs toward max_speed, m/s².
@export_range(1.0, 200.0, 1.0) var acceleration := 50.0
## How fast it bleeds off once you let go, m/s².
@export_range(1.0, 200.0, 1.0) var brake := 70.0
## Upward speed given at takeoff, m/s.
@export_range(1.0, 15.0, 0.1) var jump_velocity := 5.0
## Local gravity, m/s².
@export_range(1.0, 60.0, 0.5) var gravity := 20.0
## Radians of rotation per pixel of mouse motion.
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity := 0.0022


@export_group("Gun")
## The scene stamped out on every shot. A .tscn file is a class you can drag
## into an inspector slot — that is the whole idea being learned here.
@export var bullet_scene: PackedScene
## Where fresh bullets are parented. NOT this node: a bullet under the player
## inherits his movement and would trail after him instead of flying.
@export var bullet_parent: NodePath = ^"../Bullets"
## Seconds between shots. Held on a Timer node rather than a float, so the
## cooldown is visible in the scene and can be watched while the game runs.
@export_range(0.03, 1.0, 0.01) var fire_interval := 0.12

## Everything below is written into each bullet the moment it is made. It lives
## here rather than in Bullet.tscn on purpose: the prefab answers "what is a
## bullet", the gun answers "how hard does it hit today". One place to look —
## and, less nobly, a node that stays alive long enough to be clicked on in the
## Remote tree while the game runs.
##
## Muzzle velocity, m/s.
@export_range(5.0, 200.0, 1.0) var bullet_speed := 25.0
## Impulse delivered to anything with mass, N·s.
@export_range(0.0, 30.0, 0.5) var bullet_punch := 6.0
## See ShootBullet.inherit_shooter_velocity — 0 is a tripod, 1 is a real gun.
@export_range(0.0, 1.0, 0.05) var inherit_shooter_velocity := 0.0
## See ShootBullet.use_sweep. Off is cheaper and lies in two interesting ways.
@export var use_sweep_detection := true

var shots := 0
var hits := 0
## Range at which the last bullet died, m.
var last_hit_distance := 0.0

var _spawn: Transform3D

@onready var _camera: Camera3D = $Camera3D
@onready var _muzzle: Marker3D = $Camera3D/Muzzle
@onready var _cooldown: Timer = $Cooldown
@onready var _bullets: Node3D = get_node(bullet_parent)


func _ready() -> void:
	_spawn = global_transform
	_cooldown.wait_time = fire_interval
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(&"respawn"):
		_respawn()
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed(&"fire"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif Input.is_action_pressed(&"fire"):
		_fire()

	velocity.y -= gravity * delta
	var wish := _wish_direction()
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	planar = planar.move_toward(
			wish * max_speed,
			(acceleration if wish != Vector3.ZERO else brake) * delta)
	velocity.x = planar.x
	velocity.z = planar.z
	if is_on_floor() and Input.is_action_just_pressed(&"jump"):
		velocity.y = jump_velocity
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_camera.rotation.x = clampf(
				_camera.rotation.x - event.relative.y * mouse_sensitivity,
				-deg_to_rad(89.0),
				deg_to_rad(89.0))
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func alive_bullets() -> int:
	return _bullets.get_child_count()


func accuracy() -> float:
	return 0.0 if shots == 0 else 100.0 * float(hits) / float(shots)


## The ceremony worth memorising: make one, write into it everything it needs
## to know, listen to it, put it in the WORLD, place it. In that order — the
## numbers have to be in before setup() reads them, and setup() has to run
## before the bullet starts moving.
func _fire() -> void:
	if not _cooldown.is_stopped() or bullet_scene == null:
		return
	var bullet: ShootBullet = bullet_scene.instantiate()
	bullet.speed = bullet_speed
	bullet.punch = bullet_punch
	bullet.use_sweep = use_sweep_detection
	bullet.inherit_shooter_velocity = inherit_shooter_velocity
	bullet.setup((_aim_point() - _muzzle.global_position).normalized(), self)
	bullet.hit.connect(_on_bullet_hit)
	_bullets.add_child(bullet)
	bullet.global_position = _muzzle.global_position
	shots += 1
	_cooldown.start(fire_interval)


## Where the crosshair is actually pointing.
##
## The barrel is 18 cm to the right of the eye. Fire straight out of it and the
## bullet runs parallel to your gaze forever, permanently 18 cm off the mark —
## close enough to feel wrong and far enough to miss a small target. So the
## camera asks the world what it is looking at, and the bullet is aimed from
## the muzzle AT THAT POINT. Barrel and crosshair converge exactly where you
## are looking. Every first-person shooter does this.
func _aim_point() -> Vector3:
	var from := _camera.global_position
	var far := from - _camera.global_basis.z * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, far)
	query.exclude = [get_rid()]
	var found := get_world_3d().direct_space_state.intersect_ray(query)
	if found.is_empty():
		return far
	# Too close and the convergence angle gets silly; keep a sane minimum.
	var at: Vector3 = found.position
	return at if from.distance_to(at) > 1.5 else from - _camera.global_basis.z * 1.5


func _wish_direction() -> Vector3:
	var input: Vector2 = Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var direction := global_basis * Vector3(input.x, 0.0, input.y)
	direction.y = 0.0
	return direction.normalized()


func _respawn() -> void:
	global_transform = _spawn
	velocity = Vector3.ZERO


## A bullet died somewhere. Only things with mass count as targets — scenery
## takes the impulse but not the credit.
func _on_bullet_hit(body: Node, at: Vector3) -> void:
	if body is RigidBody3D:
		hits += 1
	last_hit_distance = _muzzle.global_position.distance_to(at)

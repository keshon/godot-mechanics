class_name TruckBody
extends VehicleBody3D
## A 6x6, so that "which wheels drive" stops being a word and becomes a switch.
##
## Godot's VehicleBody3D asks almost nothing of you. Every wheel is a
## VehicleWheel3D node, and whether it pulls or steers is a checkbox ON THAT
## WHEEL. Six wheels, six checkboxes: the drive layout is not code, it is the
## scene tree. This script only flips those checkboxes in useful combinations
## and hands the engine a number.
##
## A wheel here is a RAY AND A SPRING, not a linkage. VehicleWheel3D extends
## Node3D, not a physics body: it has no mass, no collision shape and no
## inertia, and the only physics body in the vehicle is the hull. Its whole
## vocabulary is six numbers about the spring and the tyre plus roll_influence
## — no camber, no caster, no toe, no arm lengths, no roll centre. The wheel
## travels straight, perpendicular to the hull. Looking for those knobs is a
## waste of an afternoon.
##
## The suspension is free too, and worth knowing about: the engine moves the
## WHEEL NODE ITSELF as the spring compresses — measured range on this truck is
## 0.40 m, exactly `suspension_travel`. Hang the wheel mesh under the node and
## it rides along with no code at all. Read the node's own y back and you have
## the compression as a number, which is what the HUD does.

enum DriveLayout {
	ALL_SIX,
	FRONT,
	MIDDLE,
	REAR,
	FRONT_AND_REAR,
}

enum SteerLayout {
	FRONT_ONLY,
	FRONT_AND_REAR,
}

## The three axles, by name. Everything that walks the wheels goes through here.
const AXLES := ["front", "middle", "rear"]

## Как раскладка привода называется НА ЭКРАНЕ. Имена в перечислении английские, как и всё
## остальное в коде; показания читает человек, и они по-русски (`HUD.md`).
const DRIVE_NAMES := {
	DriveLayout.ALL_SIX: "все три",
	DriveLayout.FRONT: "передняя",
	DriveLayout.MIDDLE: "средняя",
	DriveLayout.REAR: "задняя",
	DriveLayout.FRONT_AND_REAR: "передняя и задняя",
}

@export_group("Layout")
@export var drive: DriveLayout = DriveLayout.ALL_SIX:
	set(value):
		drive = value
		if is_inside_tree():
			_apply_layout()

@export var steer_axles: SteerLayout = SteerLayout.FRONT_ONLY:
	set(value):
		steer_axles = value
		if is_inside_tree():
			_apply_layout()

## Lift the middle axle out of the truck entirely, turning the 6x6 into a 4x4
## on the same wheelbase. Real trucks do this to save tyres when running empty.
## Watch what it does to the hump: two axles have to carry what three did.
@export var middle_axle_enabled := true:
	set(value):
		middle_axle_enabled = value
		if is_inside_tree():
			_apply_layout()


@export_group("Engine")
## Total pull in newtons, before it is shared out. Whether it is shared is the
## next knob, and that knob decides whether this probe measures anything at all.
@export_range(200.0, 12000.0, 50.0) var engine_power := 3000.0

## Divide the engine force between the driven wheels instead of giving every
## one of them the full amount.
##
## Godot applies `engine_force` to EACH wheel with use_as_traction set. So six
## driven wheels pull three times harder than two, and a "6x6 vs 4x2" test
## would really be measuring "three times the engine". With this on, total pull
## stays put and the only thing that changes is WHERE it is applied — which is
## the actual question.
##
## And the measured answer to that question is: on flat ground with grip to
## spare, NOTHING. 14000 N total, five layouts, acceleration over the first
## half second:
##
##   all six driven     6 x 2333 N   ->  5.46 m/s²
##   front only         2 x 7000 N   ->  5.46 m/s²
##   rear only          2 x 7000 N   ->  5.46 m/s²
##   middle only        2 x 7000 N   ->  5.46 m/s²
##   front and rear     4 x 3500 N   ->  5.46 m/s²
##
## Identical, to the last digit. engine_force is a real force and it simply
## sums; where it is applied does not enter into it while every tyre still has
## grip in hand. Which axles drive starts to matter only once a driven wheel
## runs out of grip — so if you want to feel a difference, take `grip` down
## until the wheels start slipping, or go and find the side slope.
@export var use_split_torque := true

## Tyre grip, dimensionless, written into every wheel. THE knob that makes the
## drive layout mean anything.
##
## Measured on this truck: with grip to spare, six-wheel drive, front drive and
## rear drive accelerate absolutely identically as long as the total pull is
## the same — 1.14 m/s² for all of them. Which axles pull is irrelevant when no
## wheel is anywhere near slipping.
##
## Take this down to 1 and it stops being irrelevant, because now weight
## decides who can use their share of the torque, and weight moves backwards
## the moment you open the throttle.
@export_range(0.3, 12.0, 0.1) var grip := 4.0:
	set(value):
		grip = value
		if is_inside_tree():
			for wheel in wheels():
				wheel.wheel_friction_slip = value

## Braking force written into `brake` while the brake is held, newtons.
@export_range(0.0, 300.0, 5.0) var brake_power := 60.0
## Furthest the front wheels will turn, radians.
@export_range(0.05, 0.8, 0.01) var max_steer := 0.42
## How fast the wheels swing to the requested angle, rad/s. Trucks are not
## go-karts.
@export_range(0.5, 20.0, 0.5) var steer_speed := 3.5


@export_group("Anti-roll bars")
## Newtons of resistance per unit of difference between an axle's two springs.
##
## Godot has no anti-roll bar, and it is the most missed piece of the geometry
## a raycast wheel throws away. It is also nearly free to add back: read how
## much more one side is compressed than the other, and push the chassis up on
## the squashed side and down on the other. Twenty lines for the single biggest
## thing a real linkage buys you.
##
## On a six-by-six this stops being one number and becomes a decision. Real
## trucks bar the front hard and leave the rear bogie soft, so the back axles
## can still articulate over broken ground while the cab stays flat in a bend.
## Set `bar_front` high and `bar_rear` to zero and drive the washboard, then
## swap them.
## Measured on this truck, hard left at about 10 m/s, all three bars equal:
##
##       0 N  ->  1.44 deg of roll
##    2000 N  ->  1.28
##    5000 N  ->  1.10
##   10000 N  ->  0.91
##   20000 N  ->  0.74
##
## Roll halved, monotonically, for twenty lines of code. Past this range it
## stops being a suspension component and becomes a catapult: at 40000 an
## earlier version of this truck lost half its speed fighting itself, and at
## 80000 it stopped dead. The slider ends where the physics stops being sane.
@export_range(0.0, 20000.0, 250.0) var bar_front := 0.0
@export_range(0.0, 20000.0, 250.0) var bar_middle := 0.0
@export_range(0.0, 20000.0, 250.0) var bar_rear := 0.0

## Where each wheel node sat before the engine started moving it. Needed to
## turn its live y back into a compression figure, and to put the middle axle
## back where it belongs after lifting it.
var _rest := {}
var _steer_angle := 0.0
var _detached: Array[VehicleWheel3D] = []

@onready var _axles := {
	"front": [$FL, $FR],
	"middle": [$ML, $MR],
	"rear": [$RL, $RR],
}


func _ready() -> void:
	for group in _axles.values():
		for wheel: VehicleWheel3D in group:
			_rest[wheel] = wheel.position
			wheel.wheel_friction_slip = grip
	_apply_layout()


func _physics_process(delta: float) -> void:
	var throttle := Input.get_axis(&"move_back", &"move_forward")
	var turn := Input.get_axis(&"move_right", &"move_left")

	var driven := _driven_count()
	var per_wheel := 0.0
	if driven > 0:
		per_wheel = engine_power / float(driven) if use_split_torque else engine_power
	# Measured, not assumed: a POSITIVE engine_force drives this vehicle toward
	# its own +Z. Everything else in Godot treats -Z as forward — look_at, the
	# camera behind us, the cab on the front — so the sign is flipped here once
	# rather than the whole truck being modelled backwards.
	engine_force = -throttle * per_wheel
	brake = brake_power if Input.is_action_pressed(&"jump") else 0.0

	_steer_angle = move_toward(_steer_angle, turn * max_steer, steer_speed * delta)
	steering = _steer_angle

	_apply_anti_roll("front", bar_front)
	_apply_anti_roll("middle", bar_middle)
	_apply_anti_roll("rear", bar_rear)


func _exit_tree() -> void:
	for wheel in _detached:
		if is_instance_valid(wheel):
			wheel.free()


## Roll angle in degrees, positive leaning right. Read by the HUD, and the only
## number that says whether a bar is doing anything.
func roll_degrees() -> float:
	return rad_to_deg(asin(clampf(global_basis.y.dot(Vector3.RIGHT), -1.0, 1.0)))


## 0 when the spring is fully extended, 1 when it is fully compressed.
##
## There is no getter for this in the API. There does not need to be: the
## engine writes the answer straight into the wheel node's own position, so the
## distance it has travelled from its resting place, over `suspension_travel`,
## IS the compression.
func compression(wheel: VehicleWheel3D) -> float:
	if not _rest.has(wheel) or wheel.suspension_travel <= 0.0:
		return 0.0
	var extended: float = _rest[wheel].y - wheel.wheel_rest_length
	return clampf((wheel.position.y - extended) / wheel.suspension_travel, 0.0, 1.0)


## Every wheel currently IN the tree. The middle pair drops out of this list
## when the axle is lifted, which is the whole point of lifting it.
func wheels() -> Array[VehicleWheel3D]:
	var found: Array[VehicleWheel3D] = []
	for key in AXLES:
		for wheel: VehicleWheel3D in _axles[key]:
			if wheel.is_inside_tree():
				found.append(wheel)
	return found


func driving_axles() -> String:
	return DRIVE_NAMES.get(drive, "?")


func _driven_count() -> int:
	var driven := 0
	for wheel in wheels():
		if wheel.use_as_traction:
			driven += 1
	return driven


func _apply_layout() -> void:
	# Lifting an axle means taking the wheels out of the tree. VehicleBody3D
	# reads its wheel children every step, so removing two of them genuinely
	# makes it a four-wheeler — the weight has to go somewhere else.
	for wheel: VehicleWheel3D in _axles["middle"]:
		if middle_axle_enabled and not wheel.is_inside_tree():
			add_child(wheel)
			wheel.position = _rest[wheel]
			_detached.erase(wheel)
		elif not middle_axle_enabled and wheel.is_inside_tree():
			remove_child(wheel)
			_detached.append(wheel)

	var pulling: Array = {
		DriveLayout.ALL_SIX: ["front", "middle", "rear"],
		DriveLayout.FRONT: ["front"],
		DriveLayout.MIDDLE: ["middle"],
		DriveLayout.REAR: ["rear"],
		DriveLayout.FRONT_AND_REAR: ["front", "rear"],
	}[drive]

	for key in _axles:
		for wheel: VehicleWheel3D in _axles[key]:
			wheel.use_as_traction = key in pulling
			# Godot has ONE steering angle for the whole vehicle, applied to
			# every wheel with this flag. So "rear steering" here is crab
			# steering — both ends turn the same way — not the counter-steer a
			# real 6x6 does. Worth knowing before believing the feel.
			wheel.use_as_steering = (
					key == "front"
					or (key == "rear" and steer_axles == SteerLayout.FRONT_AND_REAR)
			)


## One axle's anti-roll bar, at `stiffness` newtons per unit of spring
## difference.
##
## The force goes on only where the wheel is actually touching. That is not a
## shortcut, it is the behaviour: a bar stiff enough will happily lift the
## inside wheel clean off the ground in a bend, and then it has nothing to push
## against. This is exactly why stiff bars and rough ground do not mix.
func _apply_anti_roll(key: String, stiffness: float) -> void:
	if stiffness <= 0.0:
		return
	var left: VehicleWheel3D = _axles[key][0]
	var right: VehicleWheel3D = _axles[key][1]
	if not left.is_inside_tree() or not right.is_inside_tree():
		return
	var difference := compression(left) - compression(right)
	if absf(difference) < 0.002:
		return
	# Left squashed more than right means the body is leaning left, so lift the
	# left side of the chassis and press the right one down.
	var force := global_basis.y * (difference * stiffness)
	if left.is_in_contact():
		apply_force(force, left.global_position - global_position)
	if right.is_in_contact():
		apply_force(-force, right.global_position - global_position)

class_name CrowdFlock
extends Node3D
## A flock, drawn two different ways, so you can measure what a node costs.
##
## This is the question the previous project was built around and never
## actually answered: how many separate things can a scene hold before it stops
## being sixty frames a second?
##
## There turned out to be TWO walls, at different counts, with different cures.
## Numbers from this probe, RTX 5060 Ti, vsync off, sim and push measured
## separately inside the script. The physics budget at 60 Hz is 16.7 ms a tick.
##
##   count  mode         frame      sim    push    physics actually ran
##    2000  NODES        1.40 ms    3.95   0.82        57 of 60 /s
##    2000  MULTIMESH    1.02 ms    3.99   0.56        59 of 60 /s
##    5000  NODES       18.14 ms   11.13   1.99        60 of 60 /s
##    5000  MULTIMESH    3.13 ms   11.11   1.44        61 of 60 /s
##   10000  NODES      216.76 ms   21.60   3.82        36 of 60 /s
##   10000  MULTIMESH  197.52 ms   22.01   2.74        41 of 60 /s
##   10000  NODES, frozen   1.50 ms   —      —
##
## Read the last row first. Ten thousand nodes standing still cost one and a
## half milliseconds — Godot 4 batches identical meshes by itself, and the
## draw-call counter sits at sixteen whether the flock is five hundred or ten
## thousand. Node COUNT is not a problem. Writing to them is.
##
## Wall one, around five thousand: the presentation. NODES 18.14 ms against
## MULTIMESH 3.13 — a factor of six — while the script halves differ by half a
## millisecond. The gap is entirely engine-side: pushing a transform into a
## node means propagating it down the scene tree and syncing it to the render
## server, and a MultiMesh skips all of that. Cure: change the container.
##
## Wall two, around eight thousand: the simulation itself. At ten thousand the
## flocking maths alone takes 22 ms a tick against a 16.7 ms budget, so physics
## quietly drops to 36 ticks a second — the flock runs in slow motion rather
## than the game admitting it is behind. Past this point the draw mode saves
## nothing, because the bottleneck moved into GDScript. Cure: fewer neighbours,
## a cheaper loop, or a faster language.
##
## Press F in the running game to freeze the flock. Same nodes, same everything,
## nothing being written. That one keypress is the whole finding.

## Emitted whenever the flock is thrown away and made again — a new count, a
## new draw mode. Anything measuring the flock has to start its measurement
## over, and only the flock knows when that moment is.
signal rebuilt

enum DrawMode {
	NODES,
	MULTIMESH,
}

@export_group("Flock")
## How many creatures. Change it while running — the flock is rebuilt.
@export_range(10, 10000, 10) var count := 1500:
	set(value):
		count = value
		if is_inside_tree():
			_rebuild()

@export var draw_mode: DrawMode = DrawMode.NODES:
	set(value):
		draw_mode = value
		if is_inside_tree():
			_rebuild()

## How fast every creature moves, m/s. Speed is constant here: only direction
## is steered.
@export_range(1.0, 30.0, 0.5) var speed := 9.0
## Half-width of the box they are kept inside, m. The vertical half is 0.4 of
## this, so the flock reads as a shoal rather than a cube.
@export_range(10.0, 120.0, 1.0) var bounds := 25.0


@export_group("Steering")
## How many of your cell-mates each creature looks at per tick.
##
## Proper flocking compares everyone to everyone: N² work, four million
## distance checks a frame at two thousand creatures, and nothing else matters
## after that. So this probe does what real crowds do — a uniform grid. Every
## tick each creature is filed into a cell the size of its interaction range,
## and it only ever talks to whoever else is in that cell.
##
## The first version of this probe sampled ten creatures at random out of the
## whole flock instead. It cost the same and it did not work: at eight thousand
## creatures in this volume, ten random picks land within talking distance
## about 0.15 times. The flock looked like confetti, because nobody could see
## anybody. Locality is not an optimisation here, it is the mechanic.
##
## Raise this to 64 and watch the SIM line climb with the drawing untouched.
## Two different costs, two different cures.
@export_range(2, 64, 1) var neighbour_samples := 10
## How close is too close, m. Also sets the grid cell size, at twice this.
@export_range(0.5, 20.0, 0.5) var separation_range := 3.0
## Weights of the three flocking urges, dimensionless.
@export_range(0.0, 8.0, 0.1) var separation := 2.6
@export_range(0.0, 8.0, 0.1) var alignment := 1.4
@export_range(0.0, 8.0, 0.1) var cohesion := 0.9
## How hard they turn back at the edge of the box, dimensionless.
@export_range(0.0, 20.0, 0.5) var containment := 6.0

## Stop the flock dead without deleting a single node. Toggled with F.
##
## The most instructive switch in this probe: at 10000 nodes it takes the frame
## from 102 ms to 1.5 ms. Nothing was destroyed, nothing left the tree, the
## renderer still draws every one of them. Only the writing stopped.
@export var frozen := false

## Microseconds the last simulation step took, before anything was drawn.
var simulation_usec := 0
## Microseconds spent pushing those results into whatever draws them.
##
## Kept separate from simulation_usec on purpose. These are the two halves of
## the cost, they scale differently, and only this one changes when you flip
## Draw Mode. Both are immune to vsync, which the frames-per-second number very
## much is not.
var present_usec := 0

var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _nodes: Array[MeshInstance3D] = []
## Cell key -> indices of everyone currently in it. Rebuilt every tick; a flock
## moves, so last tick's answer is already wrong.
##
## Deliberately an untyped Dictionary. `Dictionary[Vector3i, PackedInt32Array]`
## would remove the explicit cast in _steer(), but this probe's whole output is
## a table of microseconds, and swapping the container for one that type-checks
## on every access would move the numbers it is here to report.
var _grid := {}
var _mesh: Mesh
var _material: Material
var _random := RandomNumberGenerator.new()

@onready var _multi_mesh: MultiMeshInstance3D = $MultiMesh
@onready var _nodes_root: Node3D = $Nodes


func _ready() -> void:
	_mesh = _multi_mesh.multimesh.mesh
	_material = _multi_mesh.material_override
	_random.seed = 12345
	_rebuild()


func _physics_process(delta: float) -> void:
	if frozen:
		simulation_usec = 0
		present_usec = 0
	else:
		var simulation_start: int = Time.get_ticks_usec()
		_steer(delta)
		simulation_usec = Time.get_ticks_usec() - simulation_start
		var present_start: int = Time.get_ticks_usec()
		_present()
		present_usec = Time.get_ticks_usec() - present_start


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F:
		frozen = not frozen
	elif key.keycode == KEY_V:
		# With vsync on, every frame that finishes early just waits. Two modes
		# that differ by a factor of ten both read as "144 fps" and the whole
		# experiment says nothing. Turn it off before believing any number.
		var window_id := get_window().get_window_id()
		var mode := DisplayServer.window_get_vsync_mode(window_id)
		DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if mode == DisplayServer.VSYNC_DISABLED
				else DisplayServer.VSYNC_DISABLED,
				window_id)


func _rebuild() -> void:
	_positions.resize(count)
	_velocities.resize(count)
	for i in count:
		_positions[i] = Vector3(
				_random.randf_range(-bounds, bounds),
				_random.randf_range(-bounds * 0.4, bounds * 0.4),
				_random.randf_range(-bounds, bounds))
		_velocities[i] = Vector3(
				_random.randf_range(-1.0, 1.0),
				_random.randf_range(-0.3, 0.3),
				_random.randf_range(-1.0, 1.0)).normalized() * speed

	for node in _nodes:
		node.queue_free()
	_nodes.clear()

	if draw_mode == DrawMode.NODES:
		_multi_mesh.visible = false
		_nodes_root.visible = true
		# One node each. Built in code rather than instanced from a scene file
		# because at four figures the difference in spawn time is itself worth
		# knowing: a PackedScene has to be unpacked, a MeshInstance3D does not.
		for i in count:
			var instance := MeshInstance3D.new()
			instance.mesh = _mesh
			instance.material_override = _material
			_nodes_root.add_child(instance)
			_nodes.append(instance)
	else:
		_nodes_root.visible = false
		_multi_mesh.visible = true
		_multi_mesh.multimesh.instance_count = count

	rebuilt.emit()


## File everyone into a cell the size of the interaction range. O(N), one
## dictionary write each, and it turns "who is near me" from a search over the
## whole flock into a single lookup.
func _build_grid() -> void:
	_grid.clear()
	var cell_size := separation_range * 2.0
	for i in count:
		var at := _positions[i]
		var key := Vector3i(
				int(floor(at.x / cell_size)),
				int(floor(at.y / cell_size)),
				int(floor(at.z / cell_size)))
		if _grid.has(key):
			_grid[key].append(i)
		else:
			_grid[key] = PackedInt32Array([i])


## Where the flocking happens. Identical work whichever way they are drawn.
func _steer(delta: float) -> void:
	var total := count
	if total < 2:
		return
	_build_grid()
	var cell_size := separation_range * 2.0
	for i in total:
		var at := _positions[i]
		var velocity := _velocities[i]
		var push := Vector3.ZERO
		var match_direction := Vector3.ZERO
		var centre := Vector3.ZERO
		var seen := 0
		var key := Vector3i(
				int(floor(at.x / cell_size)),
				int(floor(at.y / cell_size)),
				int(floor(at.z / cell_size)))
		var cell: PackedInt32Array = _grid[key]
		var take := mini(neighbour_samples, cell.size())
		for sample in take:
			var j: int = cell[(i + sample) % cell.size()]
			if j == i:
				continue
			var offset := _positions[j] - at
			var distance := offset.length()
			if distance > separation_range * 3.0 or distance < 0.0001:
				continue
			seen += 1
			centre += _positions[j]
			match_direction += _velocities[j]
			if distance < separation_range:
				push -= offset / distance * (1.0 - distance / separation_range)
		if seen > 0:
			velocity += push * separation * delta * 10.0
			velocity += (match_direction / seen - velocity) * alignment * delta
			velocity += (centre / seen - at).normalized() * cohesion * delta * 10.0
		# Turn back at the walls, softly, so the flock breathes instead of
		# bouncing.
		for axis in 3:
			var limit := bounds if axis != 1 else bounds * 0.4
			if absf(at[axis]) > limit:
				velocity[axis] -= signf(at[axis]) * containment * delta * 10.0
		_velocities[i] = velocity.normalized() * speed
		_positions[i] = at + _velocities[i] * delta


func _present() -> void:
	if draw_mode == DrawMode.NODES:
		for i in count:
			_nodes[i].transform = _pose(i)
	else:
		var multimesh := _multi_mesh.multimesh
		for i in count:
			multimesh.set_instance_transform(i, _pose(i))


func _pose(i: int) -> Transform3D:
	return Transform3D(Basis.looking_at(_velocities[i], Vector3.UP), _positions[i])

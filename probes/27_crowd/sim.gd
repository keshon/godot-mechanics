class_name CrowdSim
extends RefCounted
## Three answers to "they walk through each other", and the third is the engine.
##
##   NONE  nothing at all. This is what probe 26 left: a heap at the goal.
##   PUSH  pairwise separation. Everyone pushes everyone within reach apart. Reactive:
##         it fixes overlap that has ALREADY happened.
##   RVO   NavigationServer3D avoidance. Predictive: each agent picks a velocity that
##         will not collide over the next second, given what the others are doing.
##         Native, and the reason crowds form lanes instead of a scrum.
##
## Walls are not in this probe at all. Two streams cross in the open, with four pillars
## handled identically in every mode, so the comparison is purely agent against agent.

enum Mode {
	NONE,
	PUSH,
	RVO,
}

## Agent radius, metres.
const RADIUS := 0.42
const SPEED := 4.2
const ARENA := 46.0
const PILLARS: Array[Vector2] = [
	Vector2(-9.0, -9.0),
	Vector2(9.0, -9.0),
	Vector2(-9.0, 9.0),
	Vector2(9.0, 9.0),
]
const PILLAR_RADIUS := 2.6

var mode := Mode.RVO
var count := 300
var spots := PackedVector2Array()
var velocities := PackedVector2Array()
## What RVO handed back, one frame late.
var safe := PackedVector2Array()
## 0 walks right, 1 walks left.
var side := PackedByteArray()

## Quality, not cost: how deep agents stand inside one another, metres. This is the
## number the whole probe turns on, because "they do not walk through each other" is
## otherwise an opinion.
var overlap_avg := 0.0
var overlap_max := 0.0
var pairs := 0
var arrivals := 0
var step_usec := 0.0
## Timed apart from the simulation, and it has to be: counting overlaps walks every
## neighbour, so a heap of agents makes the METRIC expensive exactly where the thing
## being measured is worst. Folded together, the numbers said RVO was cheaper than
## doing nothing.
var measure_usec := 0.0

var _map := RID()
var _agents: Array[RID] = []
var _bucket := {}
var _cell_size := RADIUS * 4.0


func build(agents: int) -> void:
	release()
	count = agents
	spots.resize(agents)
	velocities.resize(agents)
	safe.resize(agents)
	side.resize(agents)
	var random := RandomNumberGenerator.new()
	random.seed = 20260902
	for i in agents:
		var rightwards := i % 2 == 0
		side[i] = 0 if rightwards else 1
		var x := random.randf_range(ARENA * 0.36, ARENA * 0.5)
		if rightwards:
			x = random.randf_range(-ARENA * 0.5, -ARENA * 0.36)
		spots[i] = Vector2(x, random.randf_range(-ARENA * 0.42, ARENA * 0.42))
		velocities[i] = Vector2.ZERO
		safe[i] = Vector2.ZERO
	if mode == Mode.RVO:
		_make_rvo()


func release() -> void:
	for agent in _agents:
		NavigationServer3D.free_rid(agent)
	_agents.clear()
	if _map.is_valid():
		NavigationServer3D.free_rid(_map)
		_map = RID()


func set_mode(to_mode: Mode) -> void:
	if to_mode == mode:
		return
	mode = to_mode
	build(count)


func step(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_rehash()
	for i in count:
		var want := _desire(i)
		match mode:
			Mode.NONE:
				velocities[i] = want
			Mode.PUSH:
				velocities[i] = want + _separate(i)
			Mode.RVO:
				NavigationServer3D.agent_set_position(
						_agents[i], Vector3(spots[i].x, 0.0, spots[i].y))
				NavigationServer3D.agent_set_velocity(
						_agents[i], Vector3(want.x, 0.0, want.y))
				# One frame late on purpose: the server answers after it has synced, and
				# waiting for it inside the same frame would force a full map update.
				velocities[i] = safe[i]
		velocities[i] += _pillars(i)
		if velocities[i].length() > SPEED:
			velocities[i] = velocities[i].normalized() * SPEED
		spots[i] += velocities[i] * delta
		_wrap(i)
	step_usec = float(Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	_measure()
	measure_usec = float(Time.get_ticks_usec() - started)


## The crowd of the engine lives on the NavigationServer, not in nodes. A
## NavigationAgent3D per agent would be a node per agent; the server takes bare RIDs and
## is the only thing that scales. The price is that results come back through ONE
## CALLABLE PER AGENT PER FRAME.
func _make_rvo() -> void:
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_map, true)
	NavigationServer3D.map_set_up(_map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(_map, 0.25)
	for i in count:
		var agent := NavigationServer3D.agent_create()
		NavigationServer3D.agent_set_map(agent, _map)
		NavigationServer3D.agent_set_avoidance_enabled(agent, true)
		NavigationServer3D.agent_set_radius(agent, RADIUS)
		NavigationServer3D.agent_set_max_speed(agent, SPEED)
		NavigationServer3D.agent_set_neighbor_distance(agent, RADIUS * 8.0)
		NavigationServer3D.agent_set_max_neighbors(agent, 10)
		NavigationServer3D.agent_set_time_horizon_agents(agent, 1.2)
		NavigationServer3D.agent_set_position(
				agent, Vector3(spots[i].x, 0.0, spots[i].y))
		NavigationServer3D.agent_set_avoidance_callback(agent, _on_avoidance.bind(i))
		_agents.append(agent)


## Where an agent wants to go with nobody in the way: STRAIGHT across, holding its own
## line. The first version pulled everyone toward the centre line as well, and the two
## streams collapsed into one heap instead of passing through each other — which hid the
## very thing the probe exists to show. A crowd test needs the streams to overlap along
## their whole width, not to meet at a point.
func _desire(index: int) -> Vector2:
	var across := ARENA * 0.55 if side[index] == 0 else -ARENA * 0.55
	return (Vector2(across, spots[index].y) - spots[index]).normalized() * SPEED


func _wrap(index: int) -> void:
	var over := spots[index].x > ARENA * 0.5
	if side[index] != 0:
		over = spots[index].x < -ARENA * 0.5
	if over:
		side[index] = 1 - side[index]
		arrivals += 1
	spots[index].y = clampf(spots[index].y, -ARENA * 0.5, ARENA * 0.5)


func _pillars(index: int) -> Vector2:
	var push := Vector2.ZERO
	for pillar in PILLARS:
		var away := spots[index] - pillar
		var gap := away.length() - PILLAR_RADIUS - RADIUS
		if gap < 0.0 and away.length() > 0.001:
			push += away.normalized() * (-gap) * 26.0
	return push


## A spatial hash, because both the separation and the overlap metric ask "who is near
## me", and asking it by walking all N would be N squared. At 1200 agents that is 1.4
## million pairs a frame, and the metric alone would cost more than what it measures.
func _rehash() -> void:
	_bucket.clear()
	for i in count:
		var key := Vector2i(
				floori(spots[i].x / _cell_size), floori(spots[i].y / _cell_size))
		if not _bucket.has(key):
			_bucket[key] = PackedInt32Array()
		_bucket[key].append(i)


func _near(index: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	var home := Vector2i(
			floori(spots[index].x / _cell_size), floori(spots[index].y / _cell_size))
	for dy in 3:
		for dx in 3:
			var key := home + Vector2i(dx - 1, dy - 1)
			if _bucket.has(key):
				found.append_array(_bucket[key])
	return found


## Reactive separation: push apart what is already inside. Simple, cheap, and visibly
## different from RVO — it cannot form a lane, because it only ever answers the present.
func _separate(index: int) -> Vector2:
	var push := Vector2.ZERO
	for other in _near(index):
		if other == index:
			continue
		var away := spots[index] - spots[other]
		var gap := away.length()
		if gap > RADIUS * 2.0 or gap < 0.0001:
			continue
		push += away / gap * (RADIUS * 2.0 - gap) * 9.0
	return push


func _measure() -> void:
	var total := 0.0
	var worst := 0.0
	var overlapping := 0
	for i in count:
		for other in _near(i):
			if other <= i:
				continue
			var inside := RADIUS * 2.0 - spots[i].distance_to(spots[other])
			if inside <= 0.0:
				continue
			total += inside
			worst = maxf(worst, inside)
			overlapping += 1
	pairs = overlapping
	overlap_avg = total / float(overlapping) if overlapping > 0 else 0.0
	overlap_max = worst


func _on_avoidance(velocity: Vector3, index: int) -> void:
	safe[index] = Vector2(velocity.x, velocity.z)

class_name CrowdSim
extends RefCounted

## Three answers to "they walk through each other", and the third is the engine's.
##
##   0 НИКАК       nothing at all. This is what probe 26 left: a heap at the goal.
##   1 СВОЁ        pairwise separation. Everyone pushes everyone within reach apart.
##                 Reactive: it fixes overlap that has ALREADY happened.
##   2 RVO         NavigationServer3D avoidance. Predictive: each agent picks a velocity
##                 that will not collide over the next second, given what the others are
##                 doing. Native, and the reason crowds form lanes instead of a scrum.
##
## Walls are not in this probe at all. Two streams cross in the open, with four pillars
## handled identically in every mode, so the comparison is purely agent against agent.

const R := 0.42          ## agent radius
const SPEED := 4.2
const ARENA := 46.0
const PILLARS: Array[Vector2] = [
	Vector2(-9.0, -9.0), Vector2(9.0, -9.0), Vector2(-9.0, 9.0), Vector2(9.0, 9.0)]
const PILLAR_R := 2.6

var mode := 2
var count := 300
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var safe := PackedVector2Array()   ## what RVO handed back, one frame late
var side := PackedByteArray()      ## 0 walks right, 1 walks left

## Quality, not cost: how deep agents are inside one another. This is the number the whole
## probe turns on, because "they do not walk through each other" is otherwise an opinion.
var overlap_avg := 0.0
var overlap_max := 0.0
var pairs := 0
var arrivals := 0
var us_step := 0.0
## Timed apart from the simulation, and it has to be: counting overlaps walks every
## neighbour, so a heap of agents makes the METRIC expensive exactly where the thing being
## measured is worst. Folded together, the numbers said RVO was cheaper than doing nothing.
var us_measure := 0.0

var _map := RID()
var _agents: Array[RID] = []
var _bucket := {}
var _cell := R * 4.0


func build(n: int) -> void:
	release()
	count = n
	pos.resize(n)
	vel.resize(n)
	safe.resize(n)
	side.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260902
	for i in n:
		var left := i % 2 == 0
		side[i] = 0 if left else 1
		pos[i] = Vector2(
			rng.randf_range(-ARENA * 0.5, -ARENA * 0.36) if left
				else rng.randf_range(ARENA * 0.36, ARENA * 0.5),
			rng.randf_range(-ARENA * 0.42, ARENA * 0.42))
		vel[i] = Vector2.ZERO
		safe[i] = Vector2.ZERO
	if mode == 2:
		_make_rvo()


## The engine's crowd lives on the NavigationServer, not in nodes. A NavigationAgent3D per
## agent would be a node per agent; the server takes bare RIDs and is the only thing that
## scales. The price is that results come back through ONE CALLABLE PER AGENT PER FRAME.
func _make_rvo() -> void:
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_map, true)
	NavigationServer3D.map_set_up(_map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(_map, 0.25)
	for i in count:
		var a := NavigationServer3D.agent_create()
		NavigationServer3D.agent_set_map(a, _map)
		NavigationServer3D.agent_set_avoidance_enabled(a, true)
		NavigationServer3D.agent_set_radius(a, R)
		NavigationServer3D.agent_set_max_speed(a, SPEED)
		NavigationServer3D.agent_set_neighbor_distance(a, R * 8.0)
		NavigationServer3D.agent_set_max_neighbors(a, 10)
		NavigationServer3D.agent_set_time_horizon_agents(a, 1.2)
		NavigationServer3D.agent_set_position(a, Vector3(pos[i].x, 0.0, pos[i].y))
		NavigationServer3D.agent_set_avoidance_callback(a, _got_safe.bind(i))
		_agents.append(a)


func release() -> void:
	for a in _agents:
		NavigationServer3D.free_rid(a)
	_agents.clear()
	if _map.is_valid():
		NavigationServer3D.free_rid(_map)
		_map = RID()


func _got_safe(v: Vector3, i: int) -> void:
	safe[i] = Vector2(v.x, v.z)


func set_mode(m: int) -> void:
	if m == mode:
		return
	mode = m
	build(count)


func step(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_hash()
	for i in count:
		var want := _desire(i)
		match mode:
			0:
				vel[i] = want
			1:
				vel[i] = want + _separate(i)
			2:
				NavigationServer3D.agent_set_position(
					_agents[i], Vector3(pos[i].x, 0.0, pos[i].y))
				NavigationServer3D.agent_set_velocity(
					_agents[i], Vector3(want.x, 0.0, want.y))
				# one frame late on purpose: the server answers after it has synced, and
				# waiting for it inside the same frame would mean forcing a full map update
				vel[i] = safe[i]
		vel[i] += _pillars(i)
		if vel[i].length() > SPEED:
			vel[i] = vel[i].normalized() * SPEED
		pos[i] += vel[i] * delta
		_wrap(i)
	us_step = float(Time.get_ticks_usec() - t0)
	var t1 := Time.get_ticks_usec()
	_measure()
	us_measure = float(Time.get_ticks_usec() - t1)


## Where an agent wants to go with nobody in the way: STRAIGHT across, holding its own
## line. The first version pulled everyone toward the centre line as well, and the two
## streams collapsed into one heap instead of passing through each other — which hid the
## very thing the probe exists to show. A crowd test needs the streams to overlap along
## their whole width, not to meet at a point.
func _desire(i: int) -> Vector2:
	var to := Vector2(ARENA * 0.55 if side[i] == 0 else -ARENA * 0.55, pos[i].y)
	return (to - pos[i]).normalized() * SPEED


func _wrap(i: int) -> void:
	var over: bool = pos[i].x > ARENA * 0.5 if side[i] == 0 else pos[i].x < -ARENA * 0.5
	if over:
		side[i] = 1 - side[i]
		arrivals += 1
	pos[i].y = clampf(pos[i].y, -ARENA * 0.5, ARENA * 0.5)


func _pillars(i: int) -> Vector2:
	var push := Vector2.ZERO
	for p in PILLARS:
		var d := pos[i] - p
		var gap := d.length() - PILLAR_R - R
		if gap < 0.0 and d.length() > 0.001:
			push += d.normalized() * (-gap) * 26.0
	return push


## A spatial hash, because both the separation and the overlap metric ask "who is near me"
## and asking it by walking all N would be N squared. At 1200 agents that is 1.4 million
## pairs a frame, and the measurement alone would cost more than the thing measured.
func _hash() -> void:
	_bucket.clear()
	for i in count:
		var k := Vector2i(floori(pos[i].x / _cell), floori(pos[i].y / _cell))
		if not _bucket.has(k):
			_bucket[k] = PackedInt32Array()
		_bucket[k].append(i)


func _near(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var k := Vector2i(floori(pos[i].x / _cell), floori(pos[i].y / _cell))
	for dy in 3:
		for dx in 3:
			var key := k + Vector2i(dx - 1, dy - 1)
			if _bucket.has(key):
				out.append_array(_bucket[key])
	return out


## Reactive separation: push apart what is already inside. Simple, cheap, and visibly
## different from RVO — it cannot form a lane, because it only ever answers the present.
func _separate(i: int) -> Vector2:
	var push := Vector2.ZERO
	for j in _near(i):
		if j == i:
			continue
		var d := pos[i] - pos[j]
		var dist := d.length()
		if dist > R * 2.0 or dist < 0.0001:
			continue
		push += d / dist * (R * 2.0 - dist) * 9.0
	return push


func _measure() -> void:
	var sum := 0.0
	var worst := 0.0
	var n := 0
	for i in count:
		for j in _near(i):
			if j <= i:
				continue
			var d := pos[i].distance_to(pos[j])
			var over := R * 2.0 - d
			if over <= 0.0:
				continue
			sum += over
			worst = maxf(worst, over)
			n += 1
	pairs = n
	overlap_avg = sum / float(maxi(n, 1)) if n > 0 else 0.0
	overlap_max = worst

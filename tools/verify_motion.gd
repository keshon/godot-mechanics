extends SceneTree
## Animation interruption and moving-support regressions, not a substitute for a playtest.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame


func _run() -> void:
	await _animation()
	await _platforms()
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _animation() -> void:
	var rig: AnimationProbeRig = load("res://probes/53_animation/animation.tscn").instantiate()
	root.add_child(rig)
	rig.set_physics_process(false)
	var player: AnimationProbePlayer = rig.player
	await _ticks(30)
	_check(player.state == &"idle" and player.is_on_floor(), "settled animation is idle")
	var skeleton: Skeleton3D = player.get_node("Visual/Model/Character/Rig/Skeleton3D")
	var mesh: MeshInstance3D = skeleton.get_node("Mannequin")
	_check(skeleton.get_bone_count() == 53 and mesh.skin != null, "third-party mesh has a bound skin")
	var arm: int = skeleton.find_bone("DEF-upper_arm.L")
	var resting: Quaternion = skeleton.get_bone_pose_rotation(arm)
	player.action_pressed = true
	await _ticks(35)
	_check(player.state == &"action", "imported interaction starts")
	_check(skeleton.get_bone_pose_rotation(arm).angle_to(resting) > 0.05,
			"imported interaction animates a skeleton bone")
	var initial: Vector3 = player.position
	player.wish = Vector3.RIGHT
	await _ticks(15)
	_check(player.interruptions == 1 and player.position.x > initial.x + 0.5,
			"movement interrupts gesture without locking motion")
	_check(player.state == &"run" and player.animation.current_animation == &"Sprint",
			"running selects visible run clip")
	player.wish = Vector3.ZERO
	await _ticks(35)
	_check(player.state == &"idle" and skeleton.get_bone_pose_rotation(arm).angle_to(resting) < 0.15,
			"interruption leaves no residual arm pose")
	player.walking = true
	player.wish = Vector3.FORWARD
	await _ticks(20)
	_check(player.state == &"walk" and absf(player.ground_speed - 2.5) < 0.1, "walk speed and clip")
	player.walking = false
	player.run_speed = 4.0
	await _ticks(20)
	_check(player.state == &"run" and absf(player.animation.speed_scale - 4.0 / 6.0) < 0.05,
			"gait tempo uses the authored speed rather than the configured movement cap")
	player.wish = Vector3.FORWARD * 0.6
	await _ticks(20)
	_check(player.animation.speed_scale < 1.0, "partial input adjusts gait tempo")
	player.match_stride = false
	await _ticks(3)
	_check(player.animation.speed_scale == 1.0, "fixed-tempo comparison")
	player.match_stride = true
	player.run_speed = 6.0
	player.wish = Vector3.ZERO
	await _ticks(20)
	player.turn_input = 1.0
	initial = player.position
	var facing: Basis = player.visual.global_basis
	await _ticks(20)
	_check(player.state == &"turn" and player.position.distance_to(initial) < 0.01
			and player.visual.global_basis.z.distance_to(facing.z) > 0.5, "turn in place")
	player.turn_input = 0.0
	player.action_pressed = true
	await _ticks(5)
	player.jump_pressed = true
	await _ticks(3)
	_check(player.state == &"takeoff" and player.velocity.y > 0, "jump interrupts gesture")
	var observed: Array[StringName] = []
	for i in range(90):
		await physics_frame
		if not observed.has(player.state):
			observed.append(player.state)
	_check(observed.has(&"rise") and observed.has(&"fall") and observed.has(&"land")
			and observed.has(&"idle"), "jump resolves through flight, landing and idle")
	player.action_pressed = true
	await _ticks(150)
	_check(player.state == &"idle", "uninterrupted one-shot exits")
	player.reset_at(Vector3(0, 2.0, 4))
	await _ticks(4)
	_check(player.state == &"fall", "falling without takeoff selects fall")
	await _ticks(60)
	_check(player.is_on_floor() and player.state == &"idle", "fall recovery is not stuck")
	player.reset_at(Vector3(0, 0.05, 4))
	_check(player.visual.position.distance_to(player.position) < 0.001, "animation reset snaps pose")
	print("ANIMATION clips=", player.animation.get_animation_list(), " states=", observed)
	rig.queue_free()
	await process_frame


func _board(rig: PlatformProbeRig, section: int) -> void:
	rig.set_physics_process(true)
	rig.section = section
	rig.reset()
	await _ticks(15)
	rig.set_physics_process(false)
	rig.player.wish = Vector3.ZERO


func _platforms() -> void:
	var rig: PlatformProbeRig = load("res://probes/54_platforms/platforms.tscn").instantiate()
	root.add_child(rig)
	var player: PlatformProbePlayer = rig.player
	for section in range(3):
		await _board(rig, section)
		var platform: MovingProbePlatform = rig.platforms[section]
		_check(player.support == platform, "standing on platform %d" % section)
		var anchor: Vector3 = platform.global_transform.affine_inverse() * player.position
		var max_drift := 0.0
		var grounded_ticks: int = 0
		for tick in range(360):
			await physics_frame
			var point: Vector3 = platform.global_transform.affine_inverse() * player.position
			max_drift = maxf(max_drift, point.distance_to(anchor))
			grounded_ticks += int(player.is_on_floor())
		_check(grounded_ticks == 360, "continuous floor contact %d" % section)
		_check(max_drift < 0.15, "bounded standing drift %d" % section)
		print("PLATFORM ", section, " max_drift_m=", max_drift, " grounded=", grounded_ticks)
	for policy in range(3):
		await _board(rig, 0)
		player.platform_on_leave = policy
		var carried: Vector3 = player.get_platform_velocity()
		player.jump_pressed = true
		player.jump_held = true
		await _ticks(3)
		_check(not player.is_on_floor(), "jump leaves platform")
		var expected: float = 0.0 if policy == 2 else carried.x
		_check(absf(player.departure.x - expected) < 0.15, "departure policy %d" % policy)
		print("DEPARTURE ", policy, " support=", carried, " actual=", player.departure)
		await _ticks(60)
		_check(player.is_on_floor(), "jump lands again")
	await _board(rig, 1)
	player.platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	var tangent: Vector3 = player.get_platform_velocity()
	player.jump_pressed = true
	player.jump_held = true
	await _ticks(3)
	_check(Vector2(player.departure.x, player.departure.z).distance_to(
			Vector2(tangent.x, tangent.z)) < 0.1, "rotating platform adds tangential departure velocity")
	await _board(rig, 0)
	rig.platforms[0].running = false
	await _ticks(8)
	var stopped: Vector3 = player.position
	await _ticks(60)
	_check(player.position.distance_to(stopped) < 0.01, "stopping platform leaves no residual carry")
	rig.platforms[0].running = true
	await _ticks(30)
	_check(player.support == rig.platforms[0], "resuming platform preserves contact")
	await _board(rig, 2)
	# At pi seconds the lift is descending. Compare the policies at identical phases.
	for policy in [0, 1]:
		await _board(rig, 2)
		await _ticks(174)
		player.platform_on_leave = policy
		var vertical: float = player.get_platform_velocity().y
		player.jump_held = true
		player.jump_pressed = true
		await _ticks(3)
		var expected: float = 8.6 + (vertical if policy == 0 else 0.0)
		_check(absf(player.departure.y - expected) < 0.15, "descending lift policy")
		print("LIFT ", policy, " support_y=", vertical, " departure_y=", player.departure.y)
	await _board(rig, 3)
	_check(rig.platforms[3].triggered, "landing arms falling deck")
	await _ticks(100)
	_check(rig.platforms[3].position.y < -3.0, "deck falls after delay")
	_check(player.position.y > -3.0, "catch floor protects the rider")
	await _board(rig, 3)
	_check(player.support == rig.platforms[3], "falling deck restart clears old support motion")
	await _traversal_controls(rig)
	for phase in [0, 90, 180]:
		await _route(rig, phase)
	rig.queue_free()
	await process_frame


func _traversal_controls(rig: PlatformProbeRig) -> void:
	await _board(rig, 0)
	var player: PlatformProbePlayer = rig.player
	var jumps: int = player.jumps
	player.jump_held = true
	player.jump_pressed = true
	await _ticks(15)
	player.jump_pressed = true
	await _ticks(3)
	player.jump_pressed = true
	await _ticks(3)
	_check(player.jumps == jumps + 2, "one double jump per flight")
	player.wish = Vector3.FORWARD
	player.dash_pressed = true
	await _ticks(3)
	_check(player.velocity.z < -16.0 and not player.dash_left, "air dash restored")
	await _ticks(14)
	player.dash_pressed = true
	await _ticks(3)
	_check(player.velocity.z > -16.0, "air dash cannot be repeated")
	await _board(rig, 0)
	_check(player.dash_left and player.air_jump_left, "boarding resets traversal resources")
	var heights: Array[float] = []
	for hold in [3, 50]:
		await _board(rig, 0)
		var start: float = player.position.y
		var peak := 0.0
		player.jump_held = true
		player.jump_pressed = true
		for frame in range(60):
			if frame == hold:
				player.jump_held = false
			await physics_frame
			peak = maxf(peak, player.position.y - start)
		heights.append(peak)
	_check(heights[1] > heights[0] + 0.5, "variable jump height restored")
	print("PLATFORM JUMP heights=", heights)


func _route(rig: PlatformProbeRig, phase: int) -> void:
	var player: PlatformProbePlayer = rig.player
	rig.set_physics_process(false)
	player.set_physics_process(false)
	for platform in rig.platforms:
		platform.reset_motion()
	await _ticks(5 + phase)
	player.platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	player.reset_at(Vector3(0, 1.55, 5))
	player.set_physics_process(true)
	await _ticks(20)
	var targets: Array[Node3D] = []
	for platform in rig.platforms:
		targets.append(platform)
	targets.append(rig.get_node("Course/Finish"))
	for index in range(targets.size()):
		var target: Node3D = targets[index]
		player.jump_pressed = true
		player.jump_held = true
		var arrived := false
		for frame in range(140):
			var difference: Vector3 = (target.position - player.position).slide(Vector3.UP)
			player.wish = difference.normalized() * minf(difference.length() / 1.5, 1.0)
			if frame == 20:
				player.jump_pressed = true
			await physics_frame
			if frame > 5 and player.is_on_floor():
				arrived = player.support == target if index < 4 else player.position.z < -29.5
				break
		_check(arrived, "connected route reaches panel %d" % index)
		print("ROUTE phase=", phase, " panel=", index, " landed=", arrived, " position=", player.position)
		if not arrived:
			break
		player.wish = Vector3.ZERO
		await _ticks(2)

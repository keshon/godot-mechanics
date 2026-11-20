extends SceneTree
## Session transitions and traversal mechanics; physical controller handling and feel need people.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _session()
	await _traversal()
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame


func _session() -> void:
	var rig: SessionRig = load("res://probes/51_session/session.tscn").instantiate()
	root.add_child(rig)
	_check(rig.join(10) == 0 and rig.join(11) == 1, "two devices occupy different slots")
	_check(rig.join(10) == 0 and rig.join(-1) == -1, "duplicate and third join do not steal slots")
	_check(rig.filter_stick(Vector2(0.05, 0.05)) == Vector2.ZERO, "radial deadzone")
	_check(rig.filter_stick(Vector2.ONE).length() <= 1.001, "diagonal stick clamped")
	var motion := InputEventJoypadMotion.new()
	motion.device = 10
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 0.8
	Input.parse_input_event(motion)
	await _ticks(2)
	_check(rig.read_move(10).x > 0.6 and rig.read_move(11) == Vector2.ZERO,
			"axis events route to their own device")
	var other: Vector3 = rig.players[1].position
	var first: Vector3 = rig.players[0].position
	await _ticks(20)
	_check(rig.players[0].position.x > first.x + 0.5, "assigned pawn moves")
	_check(rig.players[1].position.distance_to(other) < 0.02, "unaddressed pawn stays still")
	rig.toggle_pause(10)
	await _ticks(2)
	first = rig.players[0].position
	await _ticks(15)
	_check(rig.paused and rig.players[0].position == first, "pause freezes movement")
	rig.toggle_pause(11)
	_check(rig.paused, "other player cannot resume owner's pause")
	rig.toggle_pause(10)
	_check(not rig.paused, "owner resumes")
	rig.players[0].deliveries = 3
	rig.players[0].carrying = true
	rig._on_connection_changed(10, false)
	await _ticks(2)
	first = rig.players[0].position
	_check(rig.paused and rig.pause_owner == 0 and not rig.connected[0], "disconnect reserves slot")
	rig.toggle_pause(11)
	_check(rig.paused, "missing controller prevents premature resume")
	rig._on_connection_changed(10, true)
	_check(not rig.connected[0], "connection alone never claims a slot")
	_check(rig.join(12) == 0, "replacement device reclaims reserved slot")
	_check(rig.devices == [12, 11], "replacement does not reassign partner")
	_check(rig.players[0].deliveries == 3 and rig.players[0].carrying
			and rig.players[0].position == first, "reconnect preserves position and progress")
	rig.toggle_pause(12)
	_check(not rig.paused, "replacement owns resume confirmation")
	rig._on_connection_changed(12, false)
	rig.leave(12)
	_check(rig.pause_owner == 1, "leaving pause owner transfers ownership")
	rig.toggle_pause(11)
	_check(not rig.paused, "remaining player can resume")
	rig._on_connection_changed(11, false)
	_check(rig.join(-1) == 1, "keyboard may explicitly replace disconnected controller")
	rig.toggle_pause(-1)
	_check(not rig.paused, "keyboard replacement resumes")
	rig.leave(-1)
	_check(rig.devices == [-2, -2], "both slots released")
	_check(rig.join(-1) == 0 and rig.join(13) == 1, "keyboard and pad combination")
	rig._on_connection_changed(13, false)
	rig.leave(-1)
	_check(rig.join(14) == 1, "reserved slot survives remaining player leaving")
	rig.toggle_pause(14)
	_check(not rig.paused, "recovery has no orphaned pause owner")
	motion.axis_value = 0.0
	Input.parse_input_event(motion)
	rig.queue_free()
	await process_frame
	print("CHECKED session assignments, routed input, pause and reconnect transitions")


func _settle(player: TraversalPlayer, point := Vector3(0, 0.05, 5)) -> void:
	player.wish = Vector3.ZERO
	player.reset_at(point)
	await _ticks(20)


func _jump_peak(player: TraversalPlayer, held_frames: int) -> float:
	await _settle(player)
	player.jump_pressed = true
	player.jump_held = true
	var peak := 0.0
	for frame in range(70):
		if frame == held_frames:
			player.jump_held = false
		await physics_frame
		peak = maxf(peak, player.position.y)
	return peak


func _traversal() -> void:
	var rig: TraversalRig = load("res://probes/52_traversal/traversal.tscn").instantiate()
	root.add_child(rig)
	rig.set_physics_process(false)
	var player: TraversalPlayer = rig.player
	await _settle(player)
	_check(player.is_on_floor(), "traversal starts grounded")
	var short: float = await _jump_peak(player, 3)
	var tall: float = await _jump_peak(player, 60)
	_check(tall > short + 0.5, "holding jump increases height")
	player.variable_jump = false
	var fixed: float = await _jump_peak(player, 3)
	_check(absf(fixed - tall) < 0.05, "disabled variable jump preserves full height")
	player.variable_jump = true
	print("JUMP short=", short, " held=", tall, " fixed=", fixed)
	player.double_enabled = false
	for enabled in [false, true]:
		player.coyote_enabled = enabled
		await _settle(player, Vector3(0, 0.05, -1.2))
		player.wish = Vector3.FORWARD
		for frame in range(60):
			await physics_frame
			if not player.is_on_floor():
				break
		await _ticks(3)
		var before: int = player.jumps
		player.jump_held = true
		player.jump_pressed = true
		await _ticks(2)
		_check((player.jumps > before) == enabled, "coyote comparison")
	player.coyote_enabled = true
	for enabled in [false, true]:
		player.buffer_enabled = enabled
		await _settle(player)
		player.reset_at(Vector3(0, 1.0, 5))
		player.velocity.y = -4.0
		for frame in range(30):
			await physics_frame
			if player.position.y < 0.35:
				break
		var before: int = player.jumps
		player.jump_pressed = true
		player.jump_held = true
		await _ticks(10)
		_check((player.jumps > before) == enabled, "pre-landing jump buffer comparison")
	player.buffer_enabled = true
	player.double_enabled = true
	await _settle(player)
	var count: int = player.jumps
	player.jump_pressed = true
	player.jump_held = true
	await _ticks(12)
	player.jump_pressed = true
	await _ticks(3)
	player.jump_pressed = true
	await _ticks(3)
	_check(player.jumps == count + 2 and not player.air_jump_left, "only one air jump")
	player.dash_pressed = true
	player.wish = Vector3.RIGHT
	await _ticks(3)
	_check(player.velocity.x > 16 and not player.dash_left, "dash follows intention")
	await _ticks(14)
	player.dash_pressed = true
	await _ticks(2)
	_check(player.velocity.x < 16, "cannot repeat dash in same flight")
	await _settle(player)
	_check(player.air_jump_left and player.dash_left, "reset replenishes abilities")
	player.jump_pressed = true
	player.jump_held = true
	await _ticks(12)
	player.jump_pressed = true
	await _ticks(3)
	player.dash_left = false
	await _ticks(80)
	_check(player.is_on_floor() and player.air_jump_left and player.dash_left,
			"actual landing replenishes abilities")
	player.wish = Vector3.FORWARD
	await _ticks(10)
	player.wish = Vector3.ZERO
	await _ticks(20)
	_check(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "ground movement brakes")
	var falls: int = player.falls
	player.reset_at(Vector3(0, -9, 5))
	player.spawn = Vector3(0, 0.05, 5)
	await _ticks(3)
	_check(player.falls == falls + 1 and player.position.y > -1, "fall resets to selected section")
	var speeds: Array[float] = []
	for acceleration in [5.0, 24.0]:
		await _settle(player)
		player.air_acceleration = acceleration
		player.reset_at(Vector3(0, 10, 5))
		player.wish = Vector3.FORWARD
		await _ticks(20)
		speeds.append(-player.velocity.z)
	_check(speeds[1] > speeds[0] + 3.0, "air control setting changes steering authority")
	player.air_acceleration = 16.0
	await _settle(player)
	rig._yaw = PI * 0.5
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await _ticks(2)
	rig._physics_process(1.0 / 60.0)
	_check(player.wish.x < -0.9 and absf(player.wish.z) < 0.01,
			"forward follows camera yaw instead of character facing")
	var release: InputEventKey = key.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await _courses(player)
	await _narrow(player)
	rig.queue_free()
	await process_frame


func _courses(player: TraversalPlayer) -> void:
	for lane in range(2):
		await _settle(player, Vector3(lane * 18, 0.05, 5))
		var falls: int = player.falls
		var jumped := false
		var air_frames: int = 0
		for frame in range(600):
			player.wish = Vector3.FORWARD
			player.jump_held = true
			if player.is_on_floor():
				jumped = false
				air_frames = 0
				var ahead: Vector3 = player.position + Vector3.FORWARD * 1.0
				var query := PhysicsRayQueryParameters3D.create(
						ahead + Vector3.UP, ahead + Vector3.DOWN * 2, 1)
				if player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
					player.jump_pressed = true
					jumped = true
			elif jumped:
				air_frames += 1
				if lane == 1:
					player.dash_pressed = air_frames == 10
					player.jump_pressed = air_frames == 25
			await physics_frame
			if player.position.z < (-26.0 if lane == 0 else -38.0) and player.is_on_floor():
				break
		_check(player.falls == falls and player.position.z < (-25 if lane == 0 else -37),
				"authored course %d traversable" % lane)
		print("COURSE ", lane, " position=", player.position, " falls=", player.falls - falls)


func _narrow(player: TraversalPlayer) -> void:
	await _settle(player, Vector3(36, 0.05, -1))
	var falls: int = player.falls
	var targets: Array[Vector3] = [Vector3(36, 0.4, -6), Vector3(38, 0.8, -10),
		Vector3(35, 1.2, -14), Vector3(37, 1.6, -18), Vector3(36, 1.6, -24)]
	for target in targets:
		player.jump_pressed = true
		player.jump_held = true
		for frame in range(120):
			var offset: Vector3 = (target - player.position).slide(Vector3.UP)
			player.wish = offset.normalized() * minf(offset.length() / 1.8, 1.0)
			if frame == 20:
				player.jump_pressed = true
			await physics_frame
			if frame > 5 and player.is_on_floor() and player.position.distance_to(target) < 0.8:
				break
		player.wish = Vector3.ZERO
		await _ticks(10)
		_check(player.is_on_floor() and player.position.distance_to(target) < 1.0,
				"narrow raised landing reachable")
	_check(player.falls == falls, "narrow course completed without fall")

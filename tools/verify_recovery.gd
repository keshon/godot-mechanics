extends SceneTree
## Recovery races and authored puzzle restore/save round trips, using a dedicated test save file.

const SAVE_PATH := "user://audit_probe58_checkpoint.json"
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
	root.size = Vector2i(1280, 720)
	await _recovery()
	await _puzzle()
	for path in [SAVE_PATH, SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _recovery() -> void:
	var rig: RecoveryRig = load("res://probes/57_recovery/recovery.tscn").instantiate()
	root.add_child(rig)
	rig.read_input = false
	await _ticks(20)
	_check(rig.checkpoint == 0 and not rig.dead.has(true), "start has two live players")
	rig.fail(0)
	var initial: Vector3 = rig.players[1].position
	rig.players[1].wish = Vector3.RIGHT
	await _ticks(20)
	_check(rig.players[1].position.x > initial.x + 1.0, "survivor continues during partner respawn")
	_check(rig.dead[0] and not rig.players[0].active, "failed player cannot move")
	rig.players[1].wish = Vector3.ZERO
	await _ticks(65)
	_check(not rig.dead[0] and rig.returns[0] == 1, "individual respawn occurs once")
	_check(rig.players[0].position.distance_to(Vector3(-1.2, 0.05, 4)) < 0.1,
			"individual respawn uses safe start")
	rig.reset_all()
	rig.fail(0)
	rig.players[1].reset_at(Vector3(1.2, 0.05, -7.5))
	await _ticks(15)
	_check(rig.checkpoint == 1 and rig.dead[0], "survivor advances shared point while partner waits")
	await _ticks(65)
	_check(rig.players[0].position.z < -7.0, "pending respawn adopts latest shared point")
	rig.fail(0)
	rig.checkpoint = 0
	rig.remaining[0] = 0.001
	await _ticks(2)
	_check(rig.players[0].position.z < -7.0,
			"safe point won on expiry tick commits before partner respawns")
	rig.players[1].reset_at(Vector3(1.2, 0.05, 4))
	await _ticks(10)
	_check(rig.checkpoint == 1, "returning to earlier island cannot regress checkpoint")
	rig.fail(0)
	rig.fail(1)
	var timer: float = rig.wipe_remaining
	rig.fail(0)
	_check(rig.wipe_remaining == timer, "repeated failure cannot restart wipe timer")
	rig.paused = true
	await _ticks(30)
	_check(rig.wipe_remaining == timer and rig.dead == [true, true], "pause freezes recovery")
	rig.paused = false
	await _ticks(80)
	_check(rig.dead == [true, true], "wipe replaces shorter individual timer")
	await _ticks(35)
	_check(not rig.dead.has(true) and rig.wipes == 1, "both recover together exactly once")
	_check(rig.players.all(func(player: RecoveryPlayer) -> bool: return player.position.z < -7),
			"wipe uses latest shared point")
	_check(rig.players[0].position.distance_to(rig.players[1].position) > 2.0,
			"respawn slots are separated")
	rig.fail(0)
	await _ticks(60)
	rig.fail(1)
	await _ticks(20)
	_check(rig.dead == [true, true], "late second failure cancels nearly finished solo respawn")
	await _ticks(95)
	_check(not rig.dead.has(true) and rig.wipes == 2, "late wipe returns both")
	rig.fail(0)
	rig.restart()
	await _ticks(90)
	_check(not rig.dead.has(true) and rig.wipe_remaining == 0, "manual restart cancels pending recovery")
	rig.reset_all()
	rig.players[0].reset_at(Vector3(-1.2, 3.0, -7.5))
	await _ticks(3)
	_check(rig.checkpoint == 0, "flying across safe marker cannot activate it")
	rig.players[0].reset_at(Vector3(-1.2, -4, 0))
	await _ticks(3)
	_check(rig.dead[0], "fall below arena triggers recovery without injected failure")
	rig.restart()
	for section in range(2):
		var player: RecoveryPlayer = rig.players[0]
		player.reset_at(Vector3(-1.2, 0.05, 0.8 if section == 0 else -12.2))
		await _ticks(10)
		var target_z: float = -7.5 if section == 0 else -21.5
		player.jump_pressed = true
		player.jump_held = true
		for frame in range(130):
			player.wish = Vector3(0, 0, clampf((target_z - player.position.z) / 1.5, -1, 1))
			if frame == 20:
				player.jump_pressed = true
			await _ticks(1)
			if frame > 10 and player.is_on_floor() and player.position.z < target_z + 1.0:
				break
		player.wish = Vector3.ZERO
		await _ticks(12)
		print("RECOVERY route=", section, " position=", player.position,
				" checkpoint=", rig.checkpoint, " dead=", rig.dead[0])
		_check(not rig.dead[0] and rig.checkpoint == section + 1,
				"course gap %d reaches next checkpoint with traversal controls" % section)
	_check(not rig.both_safe(), "first player reaching finish does not claim both arrived")
	rig.fail(1)
	await _ticks(85)
	_check(rig.both_safe(), "late partner recovers to unlocked finish safely")
	_check(rig.get_node("Ui/Info").get_content_height() <= rig.get_node("Ui/Info").size.y,
			"recovery readout fits")
	rig.queue_free()
	await _ticks(3)


func _puzzle() -> void:
	var rig: CheckpointsRig = load("res://probes/58_checkpoints/checkpoints.tscn").instantiate()
	root.add_child(rig)
	rig.read_input = false
	rig.checkpoint.path = SAVE_PATH
	await _ticks(20)
	var identity: int = rig.core.get_instance_id()
	_check(rig.phase == "unpowered" and not rig.door.opened, "new puzzle starts closed and unpowered")
	rig.interact(0)
	await _ticks(4)
	_check(rig.core.carrier == rig.players[0], "player can grab the required key")
	rig.checkpoint.capture(rig.phase)
	_check(rig.checkpoint.save_file(), "save while carrying writes authored checkpoint")
	rig.restore()
	_check(rig.core.carrier == null and not rig.core.locked, "restore clears ownership")
	_check(rig.core.position.distance_to(Vector3(0, 0.4, 2.5)) < 0.01,
			"free key restored to reachable home")
	await _power(rig)
	_check(rig.phase == "powered" and rig.core.locked, "installing key powers puzzle")
	_check(rig.checkpoint.phase == "powered", "power stage captures shared checkpoint")
	rig.players[0].reset_at(Vector3(-4, 0.05, -0.5))
	rig.interact(0)
	await _ticks(3)
	_check(rig.gate_remaining > 5 and rig.door.opened, "powered lever opens timed door")
	_check(rig.checkpoint.save_file(), "save replaces existing file while timer runs")
	rig.restore()
	_check(rig.gate_remaining == 0 and not rig.door.opened and rig.core.locked,
			"powered restore resets timer and preserves installed key")
	_check(rig.players.all(func(player: CheckpointPlayer) -> bool: return player.position.z > -5),
			"powered restore puts both players on lever side")
	rig.gate_duration = 0.2
	rig.players[0].reset_at(Vector3(-4, 0.05, -0.5))
	rig.interact(0)
	await _ticks(3)
	rig.players[1].reset_at(Vector3(0, 0.05, -5))
	await _ticks(20)
	_check(rig.gate_remaining == 0 and rig.door.opened and rig.door.waiting,
			"expired gate waits for occupied doorway")
	rig.players[1].reset_at(Vector3(0, 0.05, -6.5))
	await _ticks(4)
	_check(not rig.door.opened, "gate closes after doorway clears")
	_check(rig.phase == "powered", "one player through gate cannot complete the puzzle")
	rig.interact(0)
	await _ticks(3)
	_check(rig.door.opened, "separated partner can reopen expired gate")
	rig.restore()
	rig.gate_duration = 6
	rig.players[0].reset_at(Vector3(-4, 0.05, -0.5))
	rig.interact(0)
	await _ticks(3)
	# Walk through the actual collision opening before finishing, rather than only setting stage flags.
	for slot in range(2):
		rig.players[slot].reset_at(Vector3(-0.6 + slot * 1.2, 0.05, -3.5))
		rig.players[slot].wish = Vector3.FORWARD
	await _ticks(75)
	for player in rig.players:
		player.wish = Vector3.ZERO
	_check(rig.phase == "complete" and rig.door.opened, "both players walk through gate to completion")
	_check(rig.checkpoint.phase == "complete" and rig.checkpoint.save_file(),
			"completed checkpoint persists")
	for stage in PuzzleCheckpoint.PHASES:
		rig.checkpoint.capture(stage)
		_check(rig.checkpoint.save_file(), "save stage " + stage)
		rig.checkpoint.capture("unpowered")
		rig.restore()
		_check(rig.load_checkpoint() and rig.phase == stage, "load restores stage " + stage)
		_check(rig.core.get_instance_id() == identity and rig.core.carrier == null,
				"restore reuses one unowned key for " + stage)
		_check(rig.door.opened == (stage == "complete"), "door restored for " + stage)
		_check(rig.core.locked == (stage != "unpowered"), "key restored for " + stage)
	for malformed in ["{", "[]", '{"kind":"other","version":1,"phase":"powered"}',
			'{"kind":"puzzle58","version":2,"phase":"powered"}',
			'{"kind":"puzzle58","version":1,"phase":"unknown"}',
			'{"kind":"puzzle58","version":true,"phase":"powered"}',
			'{"kind":false,"version":1,"phase":"powered"}',
			'{"kind":"puzzle58","version":1,"phase":[]}', '{}']:
		var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		file.store_string(malformed)
		file.close()
		var position_before: Vector3 = rig.players[0].position
		_check(not rig.load_checkpoint() and rig.phase == "complete"
				and rig.players[0].position == position_before,
				"invalid save leaves live room and checkpoint unchanged")
	rig.checkpoint.capture("powered")
	_check(rig.checkpoint.save_file(), "valid save replaces rejected data")
	rig.checkpoint.path = SAVE_PATH + ".missing"
	_check(not rig.load_checkpoint() and rig.phase == "complete", "missing save leaves room unchanged")
	rig.checkpoint.path = SAVE_PATH
	rig.queue_free()
	await _ticks(3)
	rig = load("res://probes/58_checkpoints/checkpoints.tscn").instantiate()
	root.add_child(rig)
	rig.read_input = false
	rig.checkpoint.path = SAVE_PATH
	_check(rig.load_checkpoint() and rig.phase == "powered", "new scene loads persisted puzzle")
	_check(rig.core.locked and not rig.door.opened and rig.gate_remaining == 0,
			"new-scene restore includes key, door and timer")
	for repeat in range(20):
		rig.restore()
	_check(rig.get_children().filter(func(child: Node) -> bool: return child is CheckpointCore).size() == 1,
			"repeated restores do not duplicate required object")
	await _ticks(4)
	_check(rig.get_node("Ui/Info").get_content_height() <= rig.get_node("Ui/Info").size.y,
			"checkpoint readout fits")
	rig.queue_free()
	await _ticks(3)


func _power(rig: CheckpointsRig) -> void:
	rig.players[0].reset_at(Vector3(0, 0.05, 3.5))
	await _ticks(3)
	rig.interact(0)
	for frame in range(50):
		rig.players[0].wish = Vector3.FORWARD
		await _ticks(1)
	rig.players[0].wish = Vector3.ZERO
	rig.interact(0)
	await _ticks(3)

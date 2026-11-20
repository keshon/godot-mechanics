extends SceneTree
## Mechanical regressions, not a substitute for playing the probes.

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("ENV ", JSON.stringify({
		"engine": Engine.get_version_info(), "os": OS.get_name(),
		"cpu": OS.get_processor_name(), "display": DisplayServer.get_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"physics_hz": Engine.physics_ticks_per_second,
		"renderer": RenderingServer.get_current_rendering_method(),
		"seed_range": [0, 99],
	}))
	_paths()
	_saves()
	await _scale()
	await _duo()
	await _mixes()
	await _sound()
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func _paths() -> void:
	var field := PathField.new()
	field.solid.resize(PathField.SIZE * PathField.SIZE)
	field.solid.fill(0)
	field.solid[1 * PathField.SIZE + 2] = 1
	field.solid[2 * PathField.SIZE + 1] = 1
	_check(not field.is_clear(Vector2i(1, 1), Vector2i(2, 2)), "diagonal blocked corner")
	_check(not field.is_clear(Vector2i(1, 1), Vector2i(3, 2)), "shallow ray crosses wall")
	_check(field.is_clear(Vector2i(3, 0), Vector2i(3, 4)), "vertical open ray")
	_check(field.is_clear(Vector2i(3, 4), Vector2i(3, 0)), "reverse open ray")
	for seed_value in 100:
		field.build(seed_value)
		var goal: Vector2i = field.open_cells[0]
		field.sweep(goal)
		_check(field.visited == field.open_cells.size(), "connected seed %d" % seed_value)
		var route: Array[Vector2i] = field.path(field.open_cells[-1], goal)
		var index: int = field.open_cells[-1].y * PathField.SIZE + field.open_cells[-1].x
		_check(route.size() - 1 == field.reach[index], "equal path costs seed %d" % seed_value)
		var smooth: Array[Vector2i] = field.smoothed(route)
		for i in range(1, smooth.size()):
			_check(field.is_clear(smooth[i - 1], smooth[i]), "smoothing stays clear")
	print("CHECKED path geometry, connectivity and equal costs: seeds 0..99")


func _saves() -> void:
	var world := SaveWorld.new()
	world.begin(3)
	for i in 60:
		world.play(SaveWorld.DIRS[i % 4])
	var state_path := "user://audit_state.sav"
	var replay_path := "user://audit_replay.sav"
	var bad_path := "user://audit_bad.sav"
	_check(SaveIO.write_state(world, state_path, true) > 0, "write state")
	_check(SaveIO.write_replay(world, replay_path) > 0, "write replay")
	var state: SaveWorld = SaveIO.read_state(state_path)
	var replay: SaveWorld = SaveIO.read_replay(replay_path)
	_check(state != null and replay != null, "load both kinds")
	if state != null and replay != null:
		_check(state.digest() == world.digest(), "state restores past")
		_check(replay.digest() == world.digest(), "replay restores past")
		for i in 40:
			world.play(SaveWorld.DIRS[i % 4])
			state.play(SaveWorld.DIRS[i % 4])
			replay.play(SaveWorld.DIRS[i % 4])
		_check(state.digest() == world.digest(), "state preserves future")
		_check(replay.digest() == world.digest(), "replay preserves future")
	_check(SaveIO.read_state(replay_path) == null, "reject replay as state")
	_check(SaveIO.read_replay(state_path) == null, "reject state as replay")
	for source in [state_path, replay_path]:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
		var wrong_version: PackedByteArray = bytes.duplicate()
		wrong_version.encode_u32(4, 999)
		_write_bytes(bad_path, wrong_version)
		_check(SaveIO.read_state(bad_path) == null, "state rejects unknown version")
		_check(SaveIO.read_replay(bad_path) == null, "replay rejects unknown version")
		for length in [0, 4, 11, 19, bytes.size() - 1]:
			_write_bytes(bad_path, bytes.slice(0, length))
			_check(SaveIO.read_state(bad_path) == null, "state rejects truncation")
			_check(SaveIO.read_replay(bad_path) == null, "replay rejects truncation")
	for path in [state_path, replay_path, bad_path]:
		DirAccess.remove_absolute(path)
	print("CHECKED save past/future, file kinds, versions and truncation")


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _scale() -> void:
	var rig: ScaleRig = load("res://probes/34_scale/scale.tscn").instantiate()
	root.add_child(rig)
	rig.set_process(false)
	for distance in [100000.0, 1000000.0]:
		rig.world = PackedFloat64Array([distance, 60.0, 0.0])
		rig._rebase()
		var before: Vector3 = rig.local_position()
		for i in 100:
			rig.advance(Vector3(0.001, 0.0, 0.0))
		_check(absf(rig.local_position().x - before.x - 0.1) < 0.000001,
				"millimetre accumulation at %.0f m" % distance)
		_check(rig._chunks._origin.x == rig.origin[0], "chunk origin follows rig")
		_check(rig._clipmap._origin.x == rig.origin[0], "clipmap origin follows rig")
	var reset := InputEventKey.new()
	reset.pressed = true
	reset.physical_keycode = KEY_R
	rig._unhandled_input(reset)
	_check(rig.origin[0] == 0.0 and rig._chunks._origin == Vector3.ZERO,
			"reset clears chunk origin")
	_check(rig._clipmap._origin == Vector3.ZERO, "reset clears clipmap origin")
	rig.queue_free()
	await process_frame
	print("CHECKED floating origin: 100 km, 1000 km and reset")


func _duo() -> void:
	var rig: DuoRig = load("res://probes/49_duo/duo.tscn").instantiate()
	root.add_child(rig)
	rig.set_process(false)
	var nail: DuoNail = rig.nail_scene.instantiate()
	rig._shelf.add_child(nail)
	nail.set_physics_process(false)
	nail.position = rig._swinger.hand() + Vector3(1.0, 1.0, 0.0)
	rig._nails.append(nail)
	_check(not rig._nail_ahead(), "flying nail is not available")
	nail.state = DuoNail.State.STUCK
	_check(rig._nail_ahead(), "reachable stuck nail is available")
	nail.position.x += 20.0
	_check(not rig._nail_ahead(), "distant nail is not available")
	nail.position.x -= 20.0
	rig._released_at = 0.0
	rig._clock = 0.9
	rig._toggle_grab()
	_check(rig._handoffs == 1 and rig._swinger.hanging, "successful handoff counted")
	rig._swinger.respawn()
	_check(rig._failed_handoffs == 1, "respawn ends an unsuccessful release")
	rig._restart()
	_check(rig._handoffs == 0 and rig._failed_handoffs == 0, "restart clears counters")
	rig.queue_free()
	await process_frame
	print("CHECKED co-op instrumentation; two-player feel remains untested")


func _mixes() -> void:
	for path in ["res://mixes/01_gunrun/gunrun.tscn", "res://mixes/02_drive/drive.tscn"]:
		var rig: Node3D = load(path).instantiate()
		root.add_child(rig)
		await physics_frame
		Input.action_press(&"move_forward")
		Input.action_press(&"fire")
		var started: int = rig.shots
		for i in 90:
			if i == 30:
				Input.action_press(&"jump")
			if i == 45:
				Input.action_release(&"jump")
			Input.action_press(&"move_left", 0.5 if i > 45 else 0.0)
			await physics_frame
		for action in [&"move_forward", &"move_left", &"fire", &"jump"]:
			Input.action_release(action)
		_check(rig.shots > started + 3, "firing continues while moving: " + path)
		var camera: Camera3D = rig._camera
		_check(camera.global_position.is_finite(), "camera remains finite: " + path)
		var fx: GunFx = rig.get_node("Fx")
		_check(fx._shell_at > 0, "shell ejection runs: " + path)
		_check(fx._tracer_at > 0, "tracer creation runs: " + path)
		# Give the ray a known target: startup and shots alone do not exercise impact calls.
		var target := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 4.0, 4.0)
		collider.shape = box
		target.add_child(collider)
		root.add_child(target)
		target.global_position = camera.global_position - camera.global_basis.z * 6.0
		rig.set_process(false)
		rig.set_physics_process(false)
		if rig.has_method("_apply_key"):
			rig._car.freeze = true
		else:
			rig._player.set_physics_process(false)
		await physics_frame
		var decals_before: int = fx._decal_at
		var sparks_before: int = fx._spark_at
		rig._shoot()
		_check(fx._decal_at != decals_before, "impact creates decal: " + path)
		_check(fx._spark_at != sparks_before, "impact creates sparks: " + path)
		target.queue_free()
		if rig.has_method("_apply_key"):
			rig._apply_key(KEY_2)
			rig._place_camera()
			_check(not rig._hands.visible, "chase view hides viewmodel")
			rig._apply_key(KEY_2)
			rig._place_camera()
			_check(rig._hands.visible, "gunner view restores viewmodel")
		rig.queue_free()
		await process_frame
	print("CHECKED scripted movement, firing and impacts in M1 and M2")


func _sound() -> void:
	var buses: int = AudioServer.bus_count
	for attempt in 2:
		var rig: Node3D = load("res://probes/31_sound/sound.tscn").instantiate()
		root.add_child(rig)
		for i in 60:
			await physics_frame
		rig.queue_free()
		# Audio commands are consumed asynchronously; normal scene exit precedes engine exit.
		for i in 30:
			await process_frame
		_check(AudioServer.bus_count == buses, "sound scene releases its buses")
	print("CHECKED sound scene entered and exited twice")

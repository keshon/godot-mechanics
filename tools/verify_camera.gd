extends SceneTree
## Run with --fixed-fps N. Compare steady motion at mismatched render/physics frequencies.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func _run() -> void:
	var rig: TraversalRig = load("res://probes/52_traversal/traversal.tscn").instantiate()
	root.add_child(rig)
	rig.set_physics_process(false)
	var player: TraversalPlayer = rig.player
	var errors: Array[float] = []
	for smooth in [false, true]:
		player.wish = Vector3.ZERO
		player.reset_at(Vector3(-4, 0.05, 5))
		player.smooth_visuals = smooth
		for tick in range(10):
			await physics_frame
		player.wish = Vector3.RIGHT
		for tick in range(20):
			await physics_frame
		await process_frame
		var previous: Vector3 = player.visual_position()
		var square_error := 0.0
		var elapsed := 0.0
		var samples: int = 0
		var aimed := true
		while elapsed < 0.5:
			await process_frame
			var delta: float = player.get_process_delta_time()
			var rendered: Vector3 = player.visual_position()
			var error: float = rendered.x - previous.x - player.run_speed * delta
			square_error += error * error
			previous = rendered
			elapsed += delta
			samples += 1
			var camera: Camera3D = rig.get_node("Camera")
			var direction: Vector3 = (rendered + Vector3.UP * 1.1 - camera.position).normalized()
			aimed = aimed and direction.dot(-camera.global_basis.z) > 0.99999
		_check(aimed, "camera targets the same rendered pose as the visible character")
		errors.append(sqrt(square_error / samples))
		player.wish = Vector3.ZERO
	_check(errors[1] < 0.001, "interpolated displacement error below one millimetre")
	if errors[0] > 0.005:
		_check(errors[1] < errors[0] * 0.1, "interpolation removes at least 90% of tick stepping")
	player.reset_at(Vector3(36, 0.05, 5))
	_check(player.visual_position().distance_to(player.global_position) < 0.001,
			"teleport snaps visual history immediately")
	await process_frame
	_check(player.visual_position().distance_to(player.global_position) < 0.05,
			"teleport does not interpolate across the course")
	print("CAMERA render_hz=", roundi(1.0 / rig.get_process_delta_time()),
			" raw_rms_m=", errors[0], " smooth_rms_m=", errors[1])
	rig.queue_free()
	await process_frame
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

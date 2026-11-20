extends SceneTree
## Deterministic riding scenarios; these do not establish that the bike feels good.

var checks: int = 0
var failures: int = 0
var rig: BikeRig
var bike: BikeBody


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	rig = load("res://probes/50_bike/bike.tscn").instantiate()
	root.add_child(rig)
	rig.set_physics_process(false)
	bike = rig.bike
	await _flat()
	await _courses()
	await _air_control()
	rig.queue_free()
	await process_frame
	OS.delay_msec(250)
	await process_frame
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


func _reset(position: Vector3) -> void:
	bike.throttle = 0.0
	bike.brake = 0.0
	bike.steering = 0.0
	bike.rider = 0.0
	bike.rear_brake = false
	bike.reset_at(Transform3D(Basis.IDENTITY, position))
	await _ticks(120)


func _flat() -> void:
	await _reset(Vector3(50, 0.7, 18))
	_check(bike.contacts == 2 and not bike.fallen, "both wheels settle")
	_check(absf(bike.position.y - 0.591) < 0.02, "static spring sag")
	bike.throttle = 1.0
	await _ticks(120)
	_check(bike.speed > 9 and bike.speed < 13, "accelerates without wheelie")
	var start: Vector3 = bike.position
	bike.throttle = 0.0
	bike.brake = 1.0
	await _ticks(180)
	_check(absf(bike.speed) < 0.2 and not bike.fallen, "braking stops upright")
	_check(start.distance_to(bike.position) < 10.0, "braking distance")
	print("BRAKE distance=", start.distance_to(bike.position))
	for turn in [-0.6, 0.6]:
		await _reset(Vector3(50, 0.7, 18))
		bike.throttle = 1.0
		await _ticks(120)
		bike.throttle = 0.5
		bike.steering = turn
		await _ticks(90)
		_check((50.0 - bike.position.x) * turn > 1.0, "steering direction")
		_check(not bike.fallen and bike.speed > 8.0, "turn keeps moving upright")
	var sag: Array[float] = []
	for rate in [11000.0, 30000.0]:
		for wheel in bike.wheels:
			wheel.stiffness = rate
		await _reset(Vector3(50, 0.7, 18))
		sag.append(bike.wheels[0].compression)
	_check(sag[0] > sag[1] * 2.0, "spring setting changes loaded sag")
	for wheel in bike.wheels:
		wheel.stiffness = 18000.0


func _courses() -> void:
	for section in range(3):
		var x: float = [0.0, 20.0, -20.0][section]
		await _reset(Vector3(x, 0.7, 18))
		bike.throttle = 1.0
		var max_air := 0.0
		for frame in range(420):
			await physics_frame
			if section == 2:
				bike.rider = -0.6 if (bike.contacts == 0 and bike.position.z < -20
						and bike.pitch > -0.10) else 0.0
			max_air = maxf(max_air, bike.airborne)
		_check(not bike.fallen, "course %d stays upright" % section)
		_check(bike.position.z < -45.0, "course %d traversed" % section)
		_check(max_air > 0.2 and bike.last_airtime > 0.15, "course jump and landing recorded")
		print("COURSE ", section, " max_air=", max_air, " last_air=", bike.last_airtime,
				" distance=", bike.last_distance, " closing_speed=", bike.last_landing,
				" bottomed=", bike.bottomed)


func _air_control() -> void:
	var pitches: Array[float] = []
	for enabled in [false, true]:
		bike.air_control = enabled
		await _reset(Vector3(50, 0.7, 18))
		bike.reset_at(Transform3D(Basis.IDENTITY, Vector3(50, 20, 18)))
		bike.rider = -1.0
		await _ticks(45)
		pitches.append(bike.pitch)
	_check(absf(pitches[0]) < 0.01, "disabled airborne assistance applies no torque")
	_check(pitches[1] < -0.15, "forward rider input lowers nose in air")
	bike.air_control = true
	bike.reset_at(Transform3D(Basis(Vector3.FORWARD, PI), Vector3(50, 2, 18)))
	await _ticks(5)
	_check(bike.fallen, "inverted bike enters fallen state")
	await _reset(Vector3(50, 0.7, 18))
	_check(not bike.fallen and bike.contacts == 2, "reset recovers from crash")
	_check(bike.bottomed == 0 and bike.last_airtime == 0, "reset clears run telemetry")

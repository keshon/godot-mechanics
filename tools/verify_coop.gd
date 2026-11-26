extends SceneTree
## Camera geometry and object ownership regressions; visual comfort still needs two players.

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
	await _cameras()
	await _ownership()
	print("RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _cameras() -> void:
	var rig: CompositionRig = load("res://probes/55_composition/composition.tscn").instantiate()
	root.add_child(rig)
	rig.set_physics_process(false)
	await _ticks(20)
	var first: CompositionPlayer = rig.players[0]
	var second: CompositionPlayer = rig.players[1]
	var camera: CompositionCamera = rig.cameras[0]
	var other: CompositionCamera = rig.cameras[1]
	for player in rig.players:
		player.set_physics_process(false)
	_check(camera.get_world_3d() == first.get_world_3d(), "left viewport shares physics world")
	_check(other.get_world_3d() == first.get_world_3d(), "right viewport shares physics world")
	_check(camera.get_viewport() != other.get_viewport(), "independent viewports")
	first.reset_at(Vector3(-8, 0.05, -49))
	second.reset_at(Vector3(8, 0.05, -49))
	await _ticks(90)
	_check(camera.zone_caption == "левая ветка" and other.zone_caption == "правая ветка",
			"separated players select independent camera zones")
	_check(absf(camera.view_yaw + 0.6) < 0.01 and absf(other.view_yaw - 0.6) < 0.01,
			"opposite zone orientations converge")
	_check(camera.is_position_in_frustum(first.visual_position() + Vector3.UP),
			"left player remains framed")
	_check(other.is_position_in_frustum(second.visual_position() + Vector3.UP),
			"right player remains framed")
	var unchanged: Transform3D = other.global_transform
	camera.zones_enabled = false
	camera.look(Vector2(0.8, 0.2))
	await _ticks(90)
	_check(absf(camera.view_yaw + 0.8) < 0.01, "interrupted zone restores manual orbit")
	_check(other.global_position.distance_to(unchanged.origin) < 0.01,
			"one orbit cannot move the other view")
	first.reset_at(Vector3(0, 0.05, -10))
	camera.reset()
	camera.yaw = PI / 2.0
	await _ticks(90)
	print("CAMERA wall arm=", camera.arm_length, " position=", camera.global_position)
	_check(camera.arm_length < 2.0 and camera.arm_length > 1.0,
			"sphere sweep contracts against corridor wall")
	_check(camera.position.x < 1.8, "camera volume stays inside wall")
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
	query.collision_mask = 1
	_check(camera.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),
			"camera clearance sphere does not intersect geometry")
	camera.collision_enabled = false
	await _ticks(60)
	_check(camera.arm_length > 6.0, "collision-off comparison extends behind wall")
	camera.collision_enabled = true
	camera.update_view(1.0 / 144.0)
	_check(camera.arm_length < 2.0, "collision recovery contracts immediately")
	first.reset_at(Vector3(0, 0.05, 5))
	camera.reset()
	await _ticks(60)
	_check(camera.arm_length > 6.0, "camera extends after leaving obstruction")
	_check(camera.global_position.distance_to(first.visual_position()) < 8.0,
			"teleport does not leave camera at former section")
	camera.zones_enabled = true
	first.reset_at(Vector3(0, 0.05, -20))
	await _ticks(40)
	_check(camera.zone_caption == "высота", "vertical section selects elevated view")
	_check(camera.is_position_in_frustum(Vector3(-1.7, 1.0, -25)),
			"vertical view includes next landing")
	first.reset_at(Vector3(0, 0.05, 5))
	await _ticks(60)
	_check(camera.zone_caption == "свободная", "leaving an unfinished blend clears zone")
	first.set_physics_process(true)
	first.wish = Vector3.FORWARD
	var start: Vector3 = first.position
	await _ticks(30)
	_check(first.position.z < start.z - 2.0, "traversal remains responsive")
	first.jump_pressed = true
	first.jump_held = true
	await _ticks(8)
	_check(first.velocity.y > 0 and not first.is_on_floor(), "camera probe retains jump")
	first.jump_pressed = true
	await _ticks(4)
	_check(not first.air_jump_left, "camera probe retains double jump")
	first.dash_pressed = true
	await _ticks(4)
	_check(not first.dash_left and absf(first.velocity.z) > 16, "camera probe retains dash")
	var maximum_error := 0.0
	for frame in range(50):
		await process_frame
		var focus: Vector3 = camera.global_position - camera.global_basis.z * camera.arm_length
		maximum_error = maxf(maximum_error,
				focus.distance_to(first.visual_position() + Vector3.UP * 1.1))
	_check(maximum_error < 0.001, "camera and character share the rendered pose")
	_check(rig.get_node("Ui/Info").get_content_height() <= rig.get_node("Ui/Info").size.y,
			"camera readout fits its container")
	rig.queue_free()
	await _ticks(3)


func _ownership() -> void:
	var rig: OwnershipRig = load("res://probes/56_ownership/ownership.tscn").instantiate()
	root.add_child(rig)
	rig.set_physics_process(false)
	await _ticks(20)
	var item: OwnershipItem = rig.items[0]
	var first: OwnershipPlayer = rig.players[0]
	var second: OwnershipPlayer = rig.players[1]
	_check(item.can_reach(first) and item.can_reach(second), "both players can reach starting core")
	item.request(1, second)
	item.request(0, first)
	await _ticks(2)
	_check(item.owner_slot == 0, "tie resolves by priority, not request insertion order")
	_check(rig.prompt(1).contains("P1"), "loser prompt identifies owner")
	item.request(1, second)
	await _ticks(2)
	_check(item.owner_slot == 0, "occupied object cannot be stolen")
	rig.cancel(0)
	_check(item.owner_slot == -1 and item.carrier == null, "cancel releases ownership")
	first.reset_at(Vector3(-0.5, 0.1, 3))
	second.reset_at(Vector3(0.5, 0.1, 3))
	item.request(0, first)
	item.request(1, second)
	await _ticks(2)
	_check(item.owner_slot == 1, "next contested grab rotates priority")
	rig.set_connected(1, false)
	_check(item.owner_slot == -1 and not second.available, "disconnect releases immediately")
	rig.set_connected(1, true)
	item.request(1, second)
	rig.cancel(1)
	await _ticks(2)
	_check(item.owner_slot == -1, "cancellation removes pending request")
	item.request(1, second)
	rig.set_connected(1, false)
	await _ticks(2)
	_check(item.owner_slot == -1, "disconnect removes pending request")
	rig.set_connected(1, true)
	rig.reset()
	await _ticks(10)
	rig.interact(0)
	await _ticks(3)
	_check(item.owner_slot == 0, "rig routes nearest-item request")
	first.wish = Vector3.FORWARD
	await _ticks(30)
	first.wish = Vector3.ZERO
	_check(item.owner_slot == 0 and item.position.distance_to(first.hand_position()) < 0.3,
			"carried object follows moving carrier")
	_check(not item.use_at(1, rig.socket.position), "non-owner cannot use item")
	_check(not item.use_at(0, rig.socket.position), "use rejects distant socket")
	rig.fail(0)
	_check(item.owner_slot == -1 and not first.available, "death releases before teleport")
	rig.set_physics_process(true)
	await _ticks(70)
	_check(first.available, "death recovery restores control")
	rig.set_physics_process(false)
	rig.reset()
	await _ticks(10)
	first.reset_at(Vector3(3.3, 0.1, 0))
	item.global_position = Vector3(4.7, 0.5, 0)
	_check(not item.can_reach(first), "nearby object across wall cannot be grabbed")
	item.request(0, first)
	await _ticks(3)
	_check(item.owner_slot == -1, "wall-blocked request is rejected at resolution")
	first.reset_at(Vector3(-8, 0.1, 4))
	item.request(0, first)
	await _ticks(2)
	_check(item.owner_slot == -1, "out-of-range request rejected")
	first.reset_at(Vector3(3.25, 0.1, 0))
	first.facing = -PI / 2.0
	item.global_position = Vector3(3.25, 1.1, 0)
	item.request(0, first)
	await _ticks(10)
	_check(item.owner_slot == 0 and item.position.x < 3.5,
			"carrying sweeps the object instead of placing it through the barrier")
	item.release("test")
	first.reset_at(Vector3(0, 0.1, -5.5))
	item.global_position = Vector3(0, 1.1, -6.4)
	item.request(0, first)
	await _ticks(3)
	_check(item.owner_slot == 0 and item.use_at(0, rig.socket.position), "owner uses core at socket")
	_check(item.owner_slot == -1 and item.uses == 1, "use releases and records exactly once")
	_check(not item.use_at(0, rig.socket.position) and item.uses == 1, "repeated use cannot duplicate")
	rig.interact(0)
	await _ticks(3)
	_check(item.owner_slot == 0, "used core can be picked up again")
	first.available = false
	await _ticks(3)
	_check(item.owner_slot == -1, "entity defends against unavailable carrier without rig event")
	first.available = true
	item.request(0, first)
	await _ticks(3)
	first.reset_at(Vector3(8, 0.1, 4))
	await _ticks(3)
	_check(item.owner_slot == -1, "unexpected carrier teleport breaks ownership safely")
	rig.reset()
	await _ticks(10)
	item.request(0, first)
	item.reset()
	await _ticks(3)
	_check(item.owner_slot == -1 and item.uses == 0, "reset clears requests and use state")
	rig.devices[0] = 77
	item.request(0, first)
	await _ticks(3)
	rig._on_connection_changed(77, false)
	_check(item.owner_slot == -1 and not rig.connected[0], "device-disconnect callback releases slot")
	rig.set_connected(0, true)
	rig.interact(0)
	await _ticks(3)
	_check(item.owner_slot == 0, "carrier owns item before removal")
	rig.set_process(false)
	first.queue_free()
	await _ticks(3)
	_check(item.owner_slot == -1 and item.carrier == null, "removed carrier cannot retain ownership")
	_check(rig.get_node("Ui/Info").get_content_height() <= rig.get_node("Ui/Info").size.y,
			"ownership readout fits its container")
	rig.queue_free()
	await _ticks(3)

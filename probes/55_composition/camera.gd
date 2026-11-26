class_name CompositionCamera
extends Camera3D
## Render-clock orbit, zone blending and a swept sphere protecting the near plane.

@export var distance := 6.5
@export var blend_speed := 5.0
@export var collision_enabled := true
@export var zones_enabled := true
var yaw := 0.0
var pitch := -0.3
var view_yaw := 0.0
var arm_length := 6.5
var zone_caption := "свободная"
var target: CompositionPlayer
var zones: Array[CompositionZone] = []
var _view_pitch := -0.3
var _distance := 6.5
var _sphere := SphereShape3D.new()


func _ready() -> void:
	process_priority = 10
	_sphere.radius = 0.28


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	update_view(delta)


func configure(player: CompositionPlayer, volumes: Array[CompositionZone]) -> void:
	target = player
	zones = volumes
	reset()


func look(amount: Vector2) -> void:
	yaw -= amount.x
	pitch = clampf(pitch - amount.y, -1.1, 0.25)


func reset() -> void:
	yaw = 0.0
	pitch = -0.3
	view_yaw = yaw
	_view_pitch = pitch
	_distance = distance
	arm_length = distance
	update_view(0.0)


func update_view(delta: float) -> void:
	var selected: CompositionZone = null
	if zones_enabled:
		for zone in zones:
			if zone.contains(target.visual_position()):
				if selected == null or zone.priority > selected.priority:
					selected = zone
	zone_caption = selected.caption if selected != null else "свободная"
	var weight: float = 1.0 - exp(-blend_speed * delta)
	view_yaw = lerp_angle(view_yaw, selected.yaw if selected != null else yaw, weight)
	_view_pitch = lerpf(_view_pitch, selected.pitch if selected != null else pitch, weight)
	_distance = lerpf(_distance, selected.distance if selected != null else distance, weight)
	var focus: Vector3 = target.visual_position() + Vector3.UP * 1.1
	var direction: Vector3 = Basis.from_euler(Vector3(_view_pitch, view_yaw, 0)) * Vector3.BACK
	var safe: float = _distance
	if collision_enabled:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _sphere
		query.transform = Transform3D(Basis.IDENTITY, focus)
		query.motion = direction * _distance
		query.collision_mask = 1
		var fractions: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
		safe = maxf(0.05, _distance * fractions[0] - 0.04)
	# Contraction is immediate: smoothing it would leave the camera behind the wall.
	arm_length = minf(safe, lerpf(arm_length, safe, 1.0 - exp(-8.0 * delta)))
	global_position = focus + direction * arm_length
	look_at(focus)

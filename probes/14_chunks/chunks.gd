class_name ChunkWorld
extends Node3D
## 14 — a level made of hand-made pieces.
##
## The pieces live in the scene under Library, hidden. Each one is a normal Node3D you
## can open and edit: a Floor whose BoxMesh size IS the footprint, and Marker3D gates
## whose -Z points out. Add a node there, press R, and it starts showing up in levels.
##
## This file reads that library into plain dictionaries, hands them to Layout.gd, and
## instantiates whatever comes back. Layout.gd never sees a node.

@export_range(4, 60) var target := 22
## half the side of the plot everything must fit inside. shrink it and watch
## the solver start taking pieces back off.
@export_range(12.0, 70.0) var extent := 30.0
## how many pieces the solver may take back off before it settles for less
@export_range(0, 20000) var budget := 600
@export_range(20.0, 120.0) var view_size := 60.0
## draw the rim wall around each piece, with a gap at every gate that got used
@export var walls := true

var seed_value := 5
var solve_ms := 0.0

var _layout := ChunkLayout.new()
var _library: Array = []
var _focus := Vector3.ZERO
var _last_signature := ""

@onready var _library_root: Node3D = $Library
@onready var _board: Node3D = $Board
@onready var _limit: MeshInstance3D = $Limit
@onready var _wall_mesh: MultiMeshInstance3D = $Walls
@onready var _camera: Camera3D = $Camera
@onready var _seed_label: Label = $Ui/Hud/Seed
@onready var _detail: RichTextLabel = $Ui/Hud/Detail


func _ready() -> void:
	_library_root.visible = false
	_library = _read_library()
	_rebuild()


func _process(delta: float) -> void:
	var pan := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if pan != Vector3.ZERO:
		_focus += Basis.from_euler(Vector3(0, PI * 0.25, 0)) * pan * delta * view_size * 0.8
	_place_camera()
	var now := "%d|%d|%.1f|%d|%s" % [seed_value, target, extent, budget, walls]
	if now != _last_signature:
		_last_signature = now
		_rebuild()
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				seed_value = randi() & 0xFFFF
			KEY_LEFT:
				seed_value -= 1
			KEY_RIGHT:
				seed_value += 1
			KEY_UP:
				target = mini(target + 2, 60)
			KEY_DOWN:
				target = maxi(target - 2, 4)
			KEY_Q:
				extent = maxf(extent - 2.0, 12.0)
			KEY_E:
				extent = minf(extent + 2.0, 70.0)
			KEY_G:
				walls = not walls
			KEY_R:
				_library = _read_library()
				_last_signature = ""
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			view_size = maxf(view_size - 4.0, 20.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			view_size = minf(view_size + 4.0, 120.0)


func _read_library() -> Array:
	var found: Array = []
	for node in _library_root.get_children():
		var box: BoxMesh = (node.get_node("Floor") as MeshInstance3D).mesh
		var gates: Array[Transform3D] = []
		var kinds := PackedStringArray()
		for child in node.get_children():
			if not str(child.name).begins_with("Gate"):
				continue
			gates.append((child as Node3D).transform)
			kinds.append(str(child.get_meta("kind", "std")))
		found.append({
			"name": str(node.name),
			"size": Vector2(box.size.x, box.size.z),
			"gates": gates,
			"kinds": kinds,
			"max_uses": int(node.get_meta("max_uses", 99)),
			"node": node,
		})
	return found


func _rebuild() -> void:
	var started := Time.get_ticks_usec()
	_layout.solve(_library, seed_value, target, extent, budget)
	solve_ms = (Time.get_ticks_usec() - started) / 1000.0

	for child in _board.get_children():
		child.free()
	for placing in _layout.placed:
		var source: Node3D = _library[placing["chunk"]]["node"]
		var copy: Node3D = source.duplicate()
		_board.add_child(copy)
		copy.visible = true
		copy.transform = placing["xform"]
	_build_walls()

	_limit.scale = Vector3(extent * 2.0, 1.0, extent * 2.0)
	_focus = Vector3.ZERO
	view_size = clampf(extent * 1.55, 20.0, 120.0)


func _build_walls() -> void:
	var spots: Array[Transform3D] = []
	if walls:
		for placing in _layout.placed:
			var rect: Rect2 = placing["rect"]
			for x in range(roundi(rect.position.x), roundi(rect.end.x)):
				_add_segment(Vector3(x + 0.5, 0.45, rect.position.y), 0.0, spots)
				_add_segment(Vector3(x + 0.5, 0.45, rect.end.y), 0.0, spots)
			for z in range(roundi(rect.position.y), roundi(rect.end.y)):
				_add_segment(Vector3(rect.position.x, 0.45, z + 0.5), PI * 0.5, spots)
				_add_segment(Vector3(rect.end.x, 0.45, z + 0.5), PI * 0.5, spots)
	var multi_mesh: MultiMesh = _wall_mesh.multimesh
	multi_mesh.instance_count = spots.size()
	for i in spots.size():
		multi_mesh.set_instance_transform(i, spots[i])


func _add_segment(spots: Vector3, yaw: float, into: Array[Transform3D]) -> void:
	for door in _layout.doors:
		if absf(door.x - spots.x) < 1.0 and absf(door.z - spots.z) < 1.0:
			return  # a gate that got used is a doorway, so leave the hole
	into.append(Transform3D(Basis.from_euler(Vector3(0, yaw, 0)), spots))


func _place_camera() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = view_size
	_camera.position = _focus + Vector3(1.0, 1.0, 1.0).normalized() * 160.0
	_camera.look_at(_focus, Vector3.UP)


func _draw_hud() -> void:
	_seed_label.text = "SEED %d" % seed_value
	var text := "[table=2]"
	text += "[cell]plot  [/cell][cell]%.0f x %.0f[/cell]" % [extent * 2.0, extent * 2.0]
	text += "[cell]pieces asked for  [/cell][cell]%d[/cell]" % target
	text += "[cell]pieces placed  [/cell][cell]%d[/cell]" % _layout.placed.size()
	text += "[cell]backtracks  [/cell][cell]%d of %d%s[/cell]" % [_layout.backtracks, budget,
		"   RAN OUT" if _layout.spent else ""]
	text += "[cell]gates walled up  [/cell][cell]%d[/cell]" % _layout.capped
	text += "[cell]fits tested  [/cell][cell]%d[/cell]" % _layout.tried
	text += "[cell]solved in  [/cell][cell]%.2f ms[/cell]" % solve_ms
	text += "[/table]\n\n"
	var row := ""
	for i in _library.size():
		row += "%s %d   " % [_library[i]["name"], _layout.uses[i]]
	text += row
	_detail.text = text

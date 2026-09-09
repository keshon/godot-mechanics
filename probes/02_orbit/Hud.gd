extends Control
## Numbers for the orbit probe.
##
## FACING is the one to watch. It is the angle between where the body points
## and where the camera points. Run around in free mode and it swings through
## the whole circle; hold the aim button and it collapses to zero and stays
## there. Those are the two modes of every third-person game, in one number.

@export var player_path: NodePath = ^"../../Player"

@onready var player: OrbitPlayer = get_node(player_path)
@onready var rig: OrbitRig = player.get_node(^"CameraRig")

@onready var _speed: Label = $Speed
@onready var _detail: RichTextLabel = $Detail


func _process(_delta: float) -> void:
	_speed.text = "%.1f" % player.speed()

	var want := rig.wanted_length()
	var got := rig.actual_length()
	var squeezed := got < want - 0.05
	_detail.text = "\n".join([
		"mode    %s" % ("[color=#ffcf7a][b]AIM[/b][/color]" if player.is_aiming()
			else "[color=#7a7f88]free[/color]"),
		"facing    %s" % _facing_text(),
		"camera    %.2f m %s" % [got,
			"[color=#8ecbff](pushed in from %.2f)[/color]" % want if squeezed else ""],
		"lag    %.2f m %s" % [rig.lag(),
			"[color=#8ecbff](camera trailing)[/color]" if rig.lag() > 0.15 else ""],
		"fps    %d" % Engine.get_frames_per_second(),
	])


func _facing_text() -> String:
	var error := player.facing_error()
	var color := "#7ee081" if absf(error) < 5.0 else "#ffffff"
	return "[color=%s][b]%+.0f°[/b][/color]" % [color, error]

extends Control
## The three numbers this probe exists to produce.
##
## SIM is how long the flocking maths took, measured before anything was drawn.
## It depends on `count` and `neighbour_samples` and nothing else.
##
## DRAW CALLS is how many separate times the GPU was asked to draw something
## this frame — and it is here because it is the surprise. It does NOT climb
## with the flock. Ten thousand separate MeshInstance3D nodes still cost about
## sixteen draw calls, because Godot 4 batches identical meshes by itself. The
## cost of a node is somewhere else entirely: press F to freeze the flock and
## watch the frame time collapse while every node stays exactly where it is.

@export var crowd_path: NodePath = ^"../../Crowd"

@onready var crowd: Crowd = get_node(crowd_path)
@onready var _big: Label = $Big
@onready var _detail: RichTextLabel = $Detail

var _worst := 0.0
var _settle := 0
var _smooth := 0.016


func _process(delta: float) -> void:
	_smooth = lerpf(_smooth, delta, 0.05)
	var frame_ms := _smooth * 1000.0
	_big.text = "%.0f" % (1.0 / maxf(_smooth, 0.0001))

	# Ignore the first second after a rebuild: allocating a few thousand nodes
	# makes one very slow frame that says nothing about steady state.
	_settle += 1
	if _settle > 60:
		_worst = maxf(_worst, frame_ms)

	var calls := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var mode := ("[color=#7ee081]MULTIMESH[/color]" if crowd.draw_mode == Crowd.Draw.MULTIMESH
		else "[color=#ffcf7a]NODES[/color]")
	var vsync := DisplayServer.window_get_vsync_mode(get_window().get_window_id())
	var capped := vsync != DisplayServer.VSYNC_DISABLED
	_detail.text = "
".join([
		"frames per second%s" % ("    [color=#ff8f7a](VSYNC ON - fps is capped, press V)[/color]"
			if capped else "    [color=#7ee081]vsync off[/color]"),
		"count    [b]%d[/b]    drawn as %s" % [crowd.count, mode],
		"frame    %.2f ms   (worst since rebuild %.1f)" % [frame_ms, _worst],
		"sim      [b]%.2f ms[/b]   at %d samples each" % [crowd.sim_usec / 1000.0, crowd.neighbour_samples],
		"push     [b]%.2f ms[/b]   <- this is the one Draw Mode changes" % (crowd.present_usec / 1000.0),
		"draw calls    [b]%d[/b]" % calls,
		"nodes in tree    %d%s" % [get_tree().get_node_count(),
			"    [color=#ffcf7a][b]FROZEN[/b][/color]" if crowd.frozen else ""],
	])


func reset_worst() -> void:
	_worst = 0.0
	_settle = 0

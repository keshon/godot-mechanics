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

@export var flock_path: NodePath = ^"../../Flock"

## Worst frame seen since the flock was last rebuilt, ms.
var _worst_ms := 0.0
## Frames since the rebuild. Allocating a few thousand nodes makes one very slow
## frame that says nothing about steady state, so the first second is ignored.
var _settle_frames := 0
var _smoothed_delta := 0.016

@onready var flock: CrowdFlock = get_node(flock_path)

@onready var _fps: Label = $Fps
@onready var _detail: RichTextLabel = $Detail


func _ready() -> void:
	flock.rebuilt.connect(_on_flock_rebuilt)


func _process(delta: float) -> void:
	_smoothed_delta = lerpf(_smoothed_delta, delta, 0.05)
	var frame_ms := _smoothed_delta * 1000.0
	_fps.text = "%.0f" % (1.0 / maxf(_smoothed_delta, 0.0001))

	_settle_frames += 1
	if _settle_frames > 60:
		_worst_ms = maxf(_worst_ms, frame_ms)

	var calls := RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var mode := (
			"[color=#7ee081]MULTIMESH[/color]"
			if flock.draw_mode == CrowdFlock.DrawMode.MULTIMESH
			else "[color=#ffcf7a]NODES[/color]"
	)
	var vsync := DisplayServer.window_get_vsync_mode(get_window().get_window_id())
	var capped := vsync != DisplayServer.VSYNC_DISABLED
	_detail.text = "\n".join([
		"frames per second%s" % (
			"    [color=#ff8f7a](VSYNC ON - fps is capped, press V)[/color]" if capped
			else "    [color=#7ee081]vsync off[/color]"),
		"count    [b]%d[/b]    drawn as %s" % [flock.count, mode],
		"frame    %.2f ms   (worst since rebuild %.1f)" % [frame_ms, _worst_ms],
		"sim      [b]%.2f ms[/b]   at %d samples each" % [
			flock.simulation_usec / 1000.0, flock.neighbour_samples],
		"push     [b]%.2f ms[/b]   <- this is the one Draw Mode changes" % (
			flock.present_usec / 1000.0),
		"draw calls    [b]%d[/b]" % calls,
		"nodes in tree    %d%s" % [get_tree().get_node_count(),
			"    [color=#ffcf7a][b]FROZEN[/b][/color]" if flock.frozen else ""],
	])


## A rebuild throws every measurement away. "Worst since rebuild" used to be a
## lie: nothing ever reset it, so after changing the count the line still showed
## the spike from the previous configuration.
func _on_flock_rebuilt() -> void:
	_worst_ms = 0.0
	_settle_frames = 0

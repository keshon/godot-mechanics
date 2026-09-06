extends Control
## On-screen numbers for the movement probe.
##
## The probe is about feel, and feel is easier to trust once you can watch the
## number underneath it. The one to watch is LAST JUMP: chained strafe jumps
## push it positive, a straight-line hop pushes it negative.

## Which node to read. A path rather than a direct node reference, so the
## wiring stays visible in walk.tscn as plain readable text.
@export var player_path: NodePath = ^"../../Player"

@onready var player: Player = get_node(player_path)

@onready var _speed: Label = $Speed
@onready var _detail: RichTextLabel = $Detail

var _last_gain := 0.0
var _gain_age := 99.0


func _ready() -> void:
	# A signal, not a poll. The HUD never reaches into the player to ask
	# whether it landed this frame — the player says so, and only the nodes
	# that care are woken up.
	player.landed.connect(_on_landed)


func _on_landed(speed_delta: float) -> void:
	_last_gain = speed_delta
	_gain_age = 0.0


func _process(delta: float) -> void:
	_gain_age += delta
	_speed.text = "%.1f" % player.speed()
	_detail.text = "\n".join([
		"peak    [b]%.1f[/b] m/s" % player.peak_speed,
		"last jump    %s" % _gain_text(),
		"state    %s" % ("ground" if player.is_on_floor() else "[color=#8ecbff]air[/color]"),
		"fps    %d" % Engine.get_frames_per_second(),
	])


func _gain_text() -> String:
	if _gain_age > 3.0:
		return "[color=#7a7f88]—[/color]"
	var color := "#7ee081" if _last_gain >= 0.0 else "#ff8f7a"
	return "[color=%s][b]%+.2f[/b] m/s[/color]" % [color, _last_gain]

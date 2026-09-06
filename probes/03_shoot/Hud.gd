extends Control
## ALIVE is the line to watch. It is the number of bullet nodes that exist in
## the scene tree right now, and it goes up while you hold the trigger and back
## down to zero on its own. Nothing else in this project has ever appeared and
## disappeared like that — every node in probes 01 and 02 was there from the
## moment the level loaded until you quit.

@export var player_path: NodePath = ^"../../Player"

@onready var player: ShootPlayer = get_node(player_path)
@onready var _big: Label = $Big
@onready var _detail: RichTextLabel = $Detail

func _process(_delta: float) -> void:
	_big.text = "%d" % player.alive_bullets()
	# Read straight off the gun. Reading it off a living bullet, as this used
	# to, meant the readout went blank whenever nothing was in the air.
	var mode := ("[color=#7ee081]sweep[/color]" if player.sweep_detection
		else "[color=#ffcf7a]area only[/color]")
	_detail.text = "\n".join([
		"alive bullets",
		"shots    %d" % player.shots,
		"hits     %d   ([b]%.0f%%[/b])" % [player.hits, player.accuracy()],
		"last hit at    %.1f m" % player.last_hit_distance,
		"bullet speed    %.0f m/s" % player.bullet_speed,
		"hit detection    %s" % mode,
		"fps    %d" % Engine.get_frames_per_second(),
	])

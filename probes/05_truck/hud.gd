extends Control
## Six wheels, six bars. Each bar is one suspension, read straight off the
## wheel node's position: empty means the spring is hanging free, full means it
## is stuffed all the way into its travel.
##
## Drive over the washboard in SIDE view and watch the three axles ripple in
## order. That ripple is the thing this probe exists to show.

## Wheel node name -> what to call it on screen, padded so the bars line up.
const WHEEL_NAMES := {
	"FL": "front L",
	"FR": "front R",
	"ML": "mid   L",
	"MR": "mid   R",
	"RL": "rear  L",
	"RR": "rear  R",
}
## How many characters wide a compression bar is drawn.
const BAR_WIDTH := 16

@export var truck_path: NodePath = ^"../../Truck"

@onready var truck: TruckBody = get_node(truck_path)

@onready var _speed: Label = $Speed
@onready var _detail: RichTextLabel = $Detail


func _process(_delta: float) -> void:
	var speed_kph := truck.linear_velocity.length() * 3.6
	_speed.text = "%.0f" % speed_kph

	var lines := [
		"km/h",
		"drive    [b]%s[/b]    %s torque" % [
			truck.driving_axles(),
			"split" if truck.use_split_torque
			else "[color=#ffcf7a]full to each wheel[/color]"],
		"axles    %s" % (
			"[b]6x6[/b]" if truck.middle_axle_enabled
			else "[color=#ffcf7a]4x4 (middle lifted)[/color]"),
		"roll     [b]%+.2f deg[/b]    bars  %.0f / %.0f / %.0f" % [
			truck.roll_degrees(), truck.bar_front, truck.bar_middle, truck.bar_rear],
		"",
	]
	for wheel in truck.wheels():
		lines.append("%s  %s %s%s" % [
			WHEEL_NAMES.get(wheel.name, wheel.name),
			_compression_bar(truck.compression(wheel)),
			"" if wheel.is_in_contact() else "[color=#ff8f7a]  airborne[/color]",
			"  [color=#7ee081]drive[/color]" if wheel.use_as_traction else "",
		])
	_detail.text = "\n".join(lines)


## Compression drawn as a bar, because a column of numbers hides a rhythm and
## a column of bars shows it.
func _compression_bar(value: float) -> String:
	var filled := int(round(value * BAR_WIDTH))
	var colour := "#7ee081" if value < 0.85 else "#ff8f7a"
	return "[color=%s]%s[/color][color=#4a4f58]%s[/color]" % [
		colour, "|".repeat(filled), "-".repeat(BAR_WIDTH - filled)]

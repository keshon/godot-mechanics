class_name UiBench
extends Node3D
## 18 — the interface, by hand.
##
## Three BagViews, one script between them: the bag (10x6, takes anything), the
## equipment strip (3 slots, each with a tag, one item per slot), and the floor. Same
## Control, three configurations — which is the whole argument for writing one Control
## that reads its shape from exports instead of three that nearly match.
##
## Keys: L draws every Control's rectangle. F cycles the mouse_filter on the panel
## lying over the bag, which is the single most common way to lose your clicks.

const ITEMS: Array[Dictionary] = [
	{"name": "Broadsword", "width": 1, "height": 3, "tag": "weapon",
		"colour": Color(0.78, 0.8, 0.86)},
	{"name": "Axe", "width": 2, "height": 2, "tag": "weapon",
		"colour": Color(0.72, 0.68, 0.6)},
	{"name": "Dagger", "width": 1, "height": 2, "tag": "weapon",
		"colour": Color(0.85, 0.86, 0.9)},
	{"name": "Bow", "width": 1, "height": 3, "tag": "weapon",
		"colour": Color(0.66, 0.5, 0.3)},
	{"name": "Mail", "width": 2, "height": 3, "tag": "armour",
		"colour": Color(0.55, 0.6, 0.68)},
	{"name": "Shield", "width": 2, "height": 2, "tag": "armour",
		"colour": Color(0.5, 0.55, 0.72)},
	{"name": "Helm", "width": 2, "height": 2, "tag": "armour",
		"colour": Color(0.62, 0.64, 0.7)},
	{"name": "Ring", "width": 1, "height": 1, "tag": "trinket",
		"colour": Color(0.95, 0.82, 0.35)},
	{"name": "Amulet", "width": 1, "height": 1, "tag": "trinket",
		"colour": Color(0.9, 0.7, 0.95)},
	{"name": "Idol", "width": 1, "height": 1, "tag": "trinket",
		"colour": Color(0.55, 0.9, 0.8)},
	{"name": "Potion", "width": 1, "height": 1, "tag": "junk",
		"colour": Color(0.9, 0.35, 0.45)},
	{"name": "Elixir", "width": 1, "height": 1, "tag": "junk",
		"colour": Color(0.4, 0.85, 0.5)},
	{"name": "Scroll", "width": 2, "height": 1, "tag": "junk",
		"colour": Color(0.88, 0.85, 0.66)},
	{"name": "Torch", "width": 1, "height": 2, "tag": "junk",
		"colour": Color(0.95, 0.6, 0.25)},
	{"name": "Rope", "width": 2, "height": 1, "tag": "junk",
		"colour": Color(0.6, 0.5, 0.38)},
	{"name": "Lantern", "width": 2, "height": 2, "tag": "junk",
		"colour": Color(0.95, 0.75, 0.4)},
]

## Read by mouse_filter, so the order is the engine's: STOP, PASS, IGNORE.
const FILTERS := [
	"STOP — the panel eats every click",
	"PASS — panel first, then through",
	"IGNORE — as if the panel were not there",
]

const LOOT_COUNT := 13

var clicks_panel := 0
## Time to first-fit thirteen items into the bag, microseconds.
var pack_usec := 0.0

var _random := RandomNumberGenerator.new()
## The loot on the table right now. Kept whole so that keys 1 and 2 pack the SAME
## thirteen items two ways — otherwise the comparison says nothing.
var _pool: Array[Dictionary] = []
var _worn: Array[Node3D] = []

@onready var _bag: BagView = $Hud/Root/Main/Left/Bag
@onready var _floor: BagView = $Hud/Root/Main/Left/Floor
@onready var _worn_view: BagView = $Hud/Root/Main/Right/Worn
@onready var _cover: ColorRect = $Hud/Root/Main/Left/Bag/Cover
@onready var _skeleton: UiSkeleton = $Hud/Skeleton
@onready var _info: RichTextLabel = $Hud/Root/Main/Right/Info
@onready var _worn_root: Node3D = $Worn
@onready var _proto: MeshInstance3D = $Proto/Bit


func _ready() -> void:
	_random.seed = 5
	_cover.gui_input.connect(_on_cover_gui_input)
	for bag in _bags():
		bag.changed.connect(_on_bag_changed)
	_refill()


func _process(delta: float) -> void:
	var seconds := float(Time.get_ticks_msec()) * 0.001
	for i in _worn.size():
		var angle := TAU * float(i) / maxf(_worn.size(), 1.0) + seconds * 0.5
		_worn[i].position = Vector3(
				cos(angle) * 1.2,
				1.5 + sin(seconds * 1.5 + i) * 0.12,
				sin(angle) * 1.2)
		_worn[i].rotate_y(delta)
	_draw_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_L:
			_skeleton.showing = not _skeleton.showing
			_skeleton.queue_redraw()
		KEY_F:
			_cover.mouse_filter = (_cover.mouse_filter + 1) % FILTERS.size()
			clicks_panel = 0
			_bag.clicks = 0
		KEY_R:
			for bag in _bags():
				if bag.rotate_hovered():
					break
		KEY_SPACE:
			_refill()
		KEY_1, KEY_2:
			# Pack the same loot two ways and see how much of it fits.
			_pack(event.keycode == KEY_1)


func _bags() -> Array[BagView]:
	return [_bag, _worn_view, _floor]


func _refill() -> void:
	for bag in _bags():
		bag.grid.setup(bag.columns, bag.rows, bag.compact, bag.slot_tags)
	_pool.clear()
	for _i in LOOT_COUNT:
		_pool.append(ITEMS[_random.randi_range(0, ITEMS.size() - 1)])
	_pack(true)


func _pack(biggest_first: bool) -> void:
	var started := Time.get_ticks_usec()
	_bag.grid.pack(_pool, biggest_first)
	pack_usec = float(Time.get_ticks_usec() - started)
	for bag in _bags():
		bag.queue_redraw()
	_on_bag_changed()


func _draw_hud() -> void:
	var filter: int = _cover.mouse_filter
	var text := "[b]drag anything anywhere.[/b]  bag %d/%d cells used, %d items\n" % [
		_bag.grid.cells_used(), _bag.columns * _bag.rows, _bag.grid.items.size()]
	text += "worn %d/3    on the floor %d    packed in %.0f us\n\n" % [
		_worn_view.grid.items.size(), _floor.grid.items.size(), pack_usec]
	text += "[b]the red rectangle is a ColorRect INSIDE the bag Control.[/b]\n"
	text += "a plain Control does not lay its children out, so it stays where\n"
	text += "you put it. Move it into a Container and the Container takes over.\n\n"
	text += "[b]F  its mouse_filter:[/b]\n"
	text += "   [color=#ffd479]%s[/color]\n" % FILTERS[filter]
	text += "   clicks: panel %d, bag %d\n\n" % [clicks_panel, _bag.clicks]
	text += "L  draw every Control's rectangle\n"
	text += "R  turn the item under the cursor\n"
	text += "1  pack biggest first     2  pack in the order found\n"
	text += "SPACE  new loot"
	_info.text = text


## The world reacts to the bag: worn items orbit the figure.
func _on_bag_changed() -> void:
	for node in _worn_root.get_children():
		node.free()
	_worn.clear()
	for item in _worn_view.grid.items:
		var definition: Dictionary = item["definition"]
		var instance := MeshInstance3D.new()
		instance.mesh = _proto.mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = definition["colour"]
		material.emission_enabled = true
		material.emission = material.albedo_color * 0.35
		instance.material_override = material
		_worn_root.add_child(instance)
		_worn.append(instance)


func _on_cover_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		clicks_panel += 1

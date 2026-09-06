extends Node3D

# 18 — the interface, by hand.
#
# Three BagViews, one script between them: the bag (10x6, takes anything), the
# equipment strip (3 slots, each with a tag, one item per slot), and the floor. Same
# Control, three configurations — which is the whole argument for writing one Control
# that reads its shape from exports instead of three that nearly match.
#
# Keys: L draws every Control's rectangle. F cycles the mouse_filter on the panel
# lying over the bag, which is the single most common way to lose your clicks.

const ITEMS := [
	{"name": "Broadsword", "w": 1, "h": 3, "tag": "weapon", "col": Color(0.78, 0.8, 0.86)},
	{"name": "Axe", "w": 2, "h": 2, "tag": "weapon", "col": Color(0.72, 0.68, 0.6)},
	{"name": "Dagger", "w": 1, "h": 2, "tag": "weapon", "col": Color(0.85, 0.86, 0.9)},
	{"name": "Bow", "w": 1, "h": 3, "tag": "weapon", "col": Color(0.66, 0.5, 0.3)},
	{"name": "Mail", "w": 2, "h": 3, "tag": "armour", "col": Color(0.55, 0.6, 0.68)},
	{"name": "Shield", "w": 2, "h": 2, "tag": "armour", "col": Color(0.5, 0.55, 0.72)},
	{"name": "Helm", "w": 2, "h": 2, "tag": "armour", "col": Color(0.62, 0.64, 0.7)},
	{"name": "Ring", "w": 1, "h": 1, "tag": "trinket", "col": Color(0.95, 0.82, 0.35)},
	{"name": "Amulet", "w": 1, "h": 1, "tag": "trinket", "col": Color(0.9, 0.7, 0.95)},
	{"name": "Idol", "w": 1, "h": 1, "tag": "trinket", "col": Color(0.55, 0.9, 0.8)},
	{"name": "Potion", "w": 1, "h": 1, "tag": "junk", "col": Color(0.9, 0.35, 0.45)},
	{"name": "Elixir", "w": 1, "h": 1, "tag": "junk", "col": Color(0.4, 0.85, 0.5)},
	{"name": "Scroll", "w": 2, "h": 1, "tag": "junk", "col": Color(0.88, 0.85, 0.66)},
	{"name": "Torch", "w": 1, "h": 2, "tag": "junk", "col": Color(0.95, 0.6, 0.25)},
	{"name": "Rope", "w": 2, "h": 1, "tag": "junk", "col": Color(0.6, 0.5, 0.38)},
	{"name": "Lantern", "w": 2, "h": 2, "tag": "junk", "col": Color(0.95, 0.75, 0.4)},
]

const FILTERS := ["STOP — the panel eats every click", "PASS — panel first, then through",
	"IGNORE — as if the panel were not there"]

var clicks_panel := 0
var clicks_bag := 0
var relayout_us := 0.0

var _rng := RandomNumberGenerator.new()
var _worn: Array[Node3D] = []


func _ready() -> void:
	$Ui/Root/Main/Left/Bag/Cover.gui_input.connect(_on_cover_click)
	$Ui/Root/Main/Left/Bag/Cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for bag in _bags():
		bag.changed.connect(_on_changed)
	_refill()


func _bags() -> Array[BagView]:
	return [$Ui/Root/Main/Left/Bag, $Ui/Root/Main/Right/Worn, $Ui/Root/Main/Left/Floor] as Array[BagView]


func _refill() -> void:
	_rng.seed = 5
	for bag in _bags():
		bag.grid.setup(bag.cols, bag.rows, bag.compact, bag.slot_tags)
		bag.queue_redraw()
	var pool: Array = []
	for i in 13:
		pool.append(ITEMS[_rng.randi_range(0, ITEMS.size() - 1)])
	var t0 := Time.get_ticks_usec()
	$Ui/Root/Main/Left/Bag.grid.pack(pool, true)
	relayout_us = float(Time.get_ticks_usec() - t0)
	for bag in _bags():
		bag.queue_redraw()
	_on_changed()


func _on_changed() -> void:
	# the world reacts to the bag: worn items orbit the figure
	for n in $Worn.get_children():
		n.free()
	_worn.clear()
	var worn: BagView = $Ui/Root/Main/Right/Worn
	for i in worn.grid.items.size():
		var m := MeshInstance3D.new()
		m.mesh = $Proto/Bit.mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = worn.grid.items[i]["def"]["col"]
		mat.emission_enabled = true
		mat.emission = mat.albedo_color * 0.35
		m.material_override = mat
		$Worn.add_child(m)
		_worn.append(m)


func _process(delta: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	for i in _worn.size():
		var a := TAU * float(i) / maxf(_worn.size(), 1.0) + t * 0.5
		_worn[i].position = Vector3(cos(a) * 1.2, 1.5 + sin(t * 1.5 + i) * 0.12, sin(a) * 1.2)
		_worn[i].rotate_y(delta)
	_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_L:
			$Ui/Skeleton.on = not $Ui/Skeleton.on
			$Ui/Skeleton.queue_redraw()
		KEY_F:
			var c: Control = $Ui/Root/Main/Left/Bag/Cover
			c.mouse_filter = (c.mouse_filter + 1) % 3
			clicks_panel = 0
			clicks_bag = 0
		KEY_R:
			for bag in _bags():
				if bag.rotate_hovered():
					break
		KEY_SPACE:
			_refill()
		KEY_1, KEY_2:
			# pack the same loot two ways and see how much of it fits
			var pool: Array = []
			_rng.seed = 5
			for i in 13:
				pool.append(ITEMS[_rng.randi_range(0, ITEMS.size() - 1)])
			var bag: BagView = $Ui/Root/Main/Left/Bag
			bag.grid.pack(pool, event.keycode == KEY_1)
			bag.queue_redraw()
			_on_changed()


func _on_cover_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		clicks_panel += 1


func _hud() -> void:
	var bag: BagView = $Ui/Root/Main/Left/Bag
	var worn: BagView = $Ui/Root/Main/Right/Worn
	var floor_bag: BagView = $Ui/Root/Main/Left/Floor
	var f: int = $Ui/Root/Main/Left/Bag/Cover.mouse_filter
	var t := "[b]drag anything anywhere.[/b]  bag %d/%d cells used, %d items\n" % [
		bag.grid.used(), bag.cols * bag.rows, bag.grid.items.size()]
	t += "worn %d/3    on the floor %d\n\n" % [worn.grid.items.size(), floor_bag.grid.items.size()]
	t += "[b]the red rectangle is a ColorRect INSIDE the bag Control.[/b]\n"
	t += "a plain Control does not lay its children out, so it stays where\n"
	t += "you put it. Move it into a Container and the Container takes over.\n\n"
	t += "[b]F  its mouse_filter:[/b]\n"
	t += "   [color=#ffd479]%s[/color]\n" % FILTERS[f]
	t += "   clicks the panel swallowed: %d\n\n" % clicks_panel
	t += "L  draw every Control's rectangle\n"
	t += "R  turn the item under the cursor\n"
	t += "1  pack biggest first     2  pack in the order found\n"
	t += "SPACE  new loot"
	$Ui/Root/Main/Right/Info.text = t

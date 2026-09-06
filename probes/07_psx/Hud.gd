extends Control
## Which constraints are currently switched on, and what each one is doing.
##
## Read it as a checklist and turn them off one by one. The interesting question
## is not "does this look like a PlayStation game" but "which single line was I
## reacting to" — and the answer is usually the first one.

@export var look_path: NodePath = ^"../.."

@onready var look: Look = get_node(look_path)
@onready var _big: Label = $Big
@onready var _detail: RichTextLabel = $Detail


func _process(_delta: float) -> void:
	var view: SubViewport = look.get_node(^"Screen/View")
	_big.text = "%dx%d" % [view.size.x, view.size.y]
	_detail.text = "\n".join([
		"rendered at, then blown up with no smoothing",
		"",
		"1  vertex snap     %s   %.2f rendered pixels" % [_on(look.snap_vertices),
			look.snap_coarseness],
		"2  affine UV       %s   (perspective correction off)" % _on(look.affine_uv),
		"3  colour crush    %s   %d levels per channel" % [_on(look.post_enabled), look.levels],
		"4  dither          %s" % _on(look.dither and look.post_enabled),
		"5  resolution      %s   shrink x%d" % ["[b]low[/b]" if look.shrink > 1 else "full", look.shrink],
		"6  smooth textures %s   (what a PS2 did to a PS1 disc)" % _on(look.smooth_textures),
		"7  scanlines       %s   (a separate pass, after the upscale)" % _on(look.scanlines),
		"8  floor cut into  %s" % ("[b]%d x %d[/b] pieces" % [look.floor_subdivide + 1,
			look.floor_subdivide + 1] if look.floor_subdivide > 0
			else "[color=#ff8f7a]2 triangles — the swim goes wild[/color]"),
		"",
		"[color=#8ecbff]turn them off one at a time —[/color]",
		"[color=#8ecbff]the one you miss most is the one doing the work[/color]",
	])


func _on(v: bool) -> String:
	return "[color=#7ee081]ON [/color]" if v else "[color=#7a7f88]off[/color]"

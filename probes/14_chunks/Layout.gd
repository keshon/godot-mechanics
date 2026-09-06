class_name ChunkLayout
extends RefCounted

# Laying out hand-made pieces. No grid of cells anywhere in this file.
#
# A piece is a rectangle with gates on its edges. A gate is a Transform3D whose -Z
# points OUT of the piece. To hang piece B on an open gate, you want B's chosen gate
# to end up nose to nose with it:
#
#   want = open_gate * turn_180
#   B_world = want * B_gate_local.inverse()
#
# That is the whole geometry. Two lines, and they are the reason the pieces click.
#
# The rest is a search. Pick a gate, list the pieces that fit, take one, keep going.
# When nothing fits anywhere, take the last piece back off and try the next option —
# that is the backtracking.
#
# Backtracking has to be on a budget. Chronological backtracking on a nearly-full plot
# does not politely slow down, it detonates: measured here at 24761 undos and 1.4 s
# for one layout. Real level generators all cap it and accept a smaller level.

const TURN := Vector3(0.0, PI, 0.0)
## pieces are allowed to touch, not to overlap
const SLACK := 0.25

var library: Array = []
var placed: Array = []
var doors: Array[Vector3] = []
var uses := PackedInt32Array()
var bounds := Rect2()

var backtracks := 0
var tried := 0
var capped := 0
## true when the layout stopped because it ran out of backtracks, not out of room
var spent := false

var _limit := Rect2()
var _open: Array = []
var _steps: Array = []
var _rng := RandomNumberGenerator.new()


func solve(lib: Array, seed_value: int, target: int, extent: float, budget: int) -> bool:
	library = lib
	_limit = Rect2(-extent, -extent, extent * 2.0, extent * 2.0)
	_rng.seed = seed_value
	placed = []
	doors = []
	_open = []
	_steps = []
	backtracks = 0
	tried = 0
	capped = 0
	uses = PackedInt32Array()
	uses.resize(lib.size())
	if lib.is_empty():
		return false

	var first := _rng.randi_range(0, lib.size() - 1)
	if not _fits(_rect_of(lib[first], Transform3D.IDENTITY)):
		return false
	_seat(first, Transform3D.IDENTITY, -1)
	spent = false
	while placed.size() < target:
		if _extend():
			continue
		# the frontier is closed. either buy our way out of it or settle for this.
		if backtracks >= budget:
			spent = true
			break
		if not _undo():
			break
	_measure()
	return placed.size() >= target


# --- the search ---------------------------------------------------------------

func _extend() -> bool:
	if _open.is_empty():
		return false
	var gi := _rng.randi_range(0, _open.size() - 1)
	var step := {
		"open": _open.duplicate(true),
		"placed": placed.size(),
		"doors": doors.size(),
		"gate": gi,
		"options": _options(_open[gi]),
	}
	_steps.append(step)
	if (step["options"] as Array).is_empty():
		# nothing fits against this gate. wall it up and carry on; this is a dead
		# end, not a failure, and most of them are fine.
		_open.remove_at(gi)
		capped += 1
		return true
	_apply(step)
	return true


func _undo() -> bool:
	while not _steps.is_empty():
		var step: Dictionary = _steps[-1]
		placed.resize(step["placed"])
		doors.resize(step["doors"])
		_open = (step["open"] as Array).duplicate(true)
		_recount()
		backtracks += 1
		if (step["options"] as Array).is_empty():
			_steps.pop_back()
			continue
		_apply(step)
		return true
	return false


func _options(gate: Dictionary) -> Array:
	var want: Transform3D = (gate["xform"] as Transform3D) * Transform3D(Basis.from_euler(TURN), Vector3.ZERO)
	var out: Array = []
	for ci in library.size():
		var c: Dictionary = library[ci]
		if uses[ci] >= int(c["max_uses"]):
			continue
		var gates: Array = c["gates"]
		for gj in gates.size():
			if c["kinds"][gj] != gate["kind"]:
				continue
			tried += 1
			var xf: Transform3D = want * (gates[gj] as Transform3D).affine_inverse()
			if _fits(_rect_of(c, xf)):
				out.append([ci, gj, xf])
	# shuffled with OUR rng. Array.shuffle() uses the global one and would throw the
	# seed away without saying so.
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Variant = out[i]
		out[i] = out[j]
		out[j] = t
	return out


func _apply(step: Dictionary) -> void:
	var opt: Array = (step["options"] as Array).pop_back()
	var gate: Dictionary = _open[step["gate"]]
	_open.remove_at(step["gate"])
	doors.append((gate["xform"] as Transform3D).origin)
	_seat(opt[0], opt[2], opt[1])


func _seat(ci: int, xf: Transform3D, skip_gate: int) -> void:
	var c: Dictionary = library[ci]
	placed.append({"chunk": ci, "xform": xf, "rect": _rect_of(c, xf)})
	uses[ci] += 1
	var gates: Array = c["gates"]
	for i in gates.size():
		if i == skip_gate:
			continue
		_open.append({
			"xform": xf * (gates[i] as Transform3D),
			"kind": (c["kinds"] as PackedStringArray)[i],
		})


# --- geometry -----------------------------------------------------------------

func _rect_of(c: Dictionary, xf: Transform3D) -> Rect2:
	var s: Vector2 = c["size"]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			var p: Vector3 = xf * Vector3(s.x * sx, 0.0, s.y * sz)
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	return Rect2(lo, hi - lo)


func _fits(r: Rect2) -> bool:
	# the plot is finite. this single line is what turns growth into a search:
	# without it the layout sprawls into empty space and never has to back up.
	if not _limit.encloses(r):
		return false
	var test := r.grow(-SLACK)
	for p in placed:
		if test.intersects((p["rect"] as Rect2).grow(-SLACK)):
			return false
	return true


func _recount() -> void:
	uses = PackedInt32Array()
	uses.resize(library.size())
	for p in placed:
		uses[p["chunk"]] += 1


func _measure() -> void:
	if placed.is_empty():
		bounds = Rect2()
		return
	bounds = placed[0]["rect"]
	for p in placed:
		bounds = bounds.merge(p["rect"])

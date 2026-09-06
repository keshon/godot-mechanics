class_name SaveIO
extends RefCounted

# Two ways to write the same moment down.
#
# STATE   everything the world currently is. Big, dull, survives anything.
# REPLAY  the seed and the list of moves. Tiny, elegant, and it only works if the
#         simulation is deterministic to the last bit AND the build never changes.
#
# Roguelikes have shipped both. The choice is not taste, it is which risk you take.

const MAGIC := 0x57424F58
const VERSION := 1


static func write_state(w: SaveWorld, path: String, keep_die: bool) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_32(MAGIC)
	f.store_32(VERSION)
	f.store_32(w.seed_value)
	f.store_32(w.turn)
	f.store_32(w.map.size())
	f.store_buffer(w.map)
	f.store_32(w.actors.size())
	for a in w.actors:
		f.store_16(a["x"])
		f.store_16(a["y"])
		f.store_16(a["hp"])
		f.store_16(a["speed"])
		f.store_32(a["energy"])
	# the position of the die. forget this one field and the past loads perfectly
	# while the future is somebody else's.
	f.store_8(1 if keep_die else 0)
	f.store_64(w.rng.state if keep_die else 0)
	f.close()
	return FileAccess.get_file_as_bytes(path).size()


static func read_state(path: String) -> SaveWorld:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_32() != MAGIC:
		return null
	f.get_32()
	var w := SaveWorld.new()
	w.seed_value = f.get_32()
	w.turn = f.get_32()
	w.map = f.get_buffer(f.get_32())
	w.actors = []
	var n := f.get_32()
	for _i in n:
		w.actors.append({
			"x": f.get_16(), "y": f.get_16(), "hp": f.get_16(),
			"speed": f.get_16(), "energy": f.get_32(),
		})
	var keep := f.get_8() == 1
	var state := f.get_64()
	w.rng = RandomNumberGenerator.new()
	w.rng.seed = w.seed_value
	if keep:
		w.rng.state = state
	# note what did not come back: the move list. a state save cannot be replayed on.
	w.actions = []
	f.close()
	return w


static func write_replay(w: SaveWorld, path: String) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_32(MAGIC)
	f.store_32(VERSION)
	f.store_32(w.seed_value)
	f.store_32(w.actions.size())
	for d in w.actions:
		f.store_8(d.x + 1)
		f.store_8(d.y + 1)
	f.close()
	return FileAccess.get_file_as_bytes(path).size()


static func read_replay(path: String) -> SaveWorld:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_32() != MAGIC:
		return null
	f.get_32()
	var w := SaveWorld.new()
	w.begin(f.get_32())
	var n := f.get_32()
	for _i in n:
		var x := f.get_8() - 1
		var y := f.get_8() - 1
		w.play(Vector2i(x, y))
	f.close()
	return w

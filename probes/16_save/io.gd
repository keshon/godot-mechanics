class_name SaveIO
extends RefCounted
## Two ways to write the same moment down.
##
## STATE   everything the world currently is. Big, dull, survives anything.
## REPLAY  the seed and the list of moves. Tiny, elegant, and it only works if
##         the simulation is deterministic to the last bit AND the build never
##         changes.
##
## Roguelikes have shipped both. The choice is not taste, it is which risk you
## take.

## First four bytes of either file. A file that does not start with this is not
## ours, and reading it as if it were is how a save loader corrupts a save.
const MAGIC := 0x57424F58
const VERSION := 1


## Returns the size of the file it wrote, in bytes.
static func write_state(world: SaveWorld, path: String, store_die: bool) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_32(MAGIC)
	file.store_32(VERSION)
	file.store_32(world.seed_value)
	file.store_32(world.turn)
	file.store_32(world.map.size())
	file.store_buffer(world.map)
	file.store_32(world.actors.size())
	for actor in world.actors:
		file.store_16(actor["x"])
		file.store_16(actor["y"])
		file.store_16(actor["hp"])
		file.store_16(actor["speed"])
		file.store_32(actor["energy"])
	# The position of the die. Forget this one field and the past loads
	# perfectly while the future is somebody else's.
	file.store_8(1 if store_die else 0)
	file.store_64(world.rng.state if store_die else 0)
	file.close()
	return FileAccess.get_file_as_bytes(path).size()


static func read_state(path: String) -> SaveWorld:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_32() != MAGIC:
		return null
	file.get_32()  # version, read past: there is only one of them so far
	var world := SaveWorld.new()
	world.seed_value = file.get_32()
	world.turn = file.get_32()
	world.map = file.get_buffer(file.get_32())
	world.actors = []
	var count := file.get_32()
	for _i in count:
		world.actors.append({
			"x": file.get_16(),
			"y": file.get_16(),
			"hp": file.get_16(),
			"speed": file.get_16(),
			"energy": file.get_32(),
		})
	var stored_die := file.get_8() == 1
	var die_state := file.get_64()
	world.rng = RandomNumberGenerator.new()
	world.rng.seed = world.seed_value
	if stored_die:
		world.rng.state = die_state
	# Note what did NOT come back: the move list. A state save cannot be
	# replayed on.
	world.actions = []
	file.close()
	return world


## Returns the size of the file it wrote, in bytes.
static func write_replay(world: SaveWorld, path: String) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_32(MAGIC)
	file.store_32(VERSION)
	file.store_32(world.seed_value)
	file.store_32(world.actions.size())
	for direction in world.actions:
		file.store_8(direction.x + 1)
		file.store_8(direction.y + 1)
	file.close()
	return FileAccess.get_file_as_bytes(path).size()


## Note that this does not load a world — it REBUILDS one, by starting from the
## seed and playing every move again. That is the whole difference between the
## two formats.
static func read_replay(path: String) -> SaveWorld:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_32() != MAGIC:
		return null
	file.get_32()  # version
	var world := SaveWorld.new()
	world.begin(file.get_32())
	var count := file.get_32()
	for _i in count:
		var x := file.get_8() - 1
		var y := file.get_8() - 1
		world.play(Vector2i(x, y))
	file.close()
	return world

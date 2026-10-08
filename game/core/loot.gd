class_name Loot
## Energy drops (Story 3.3): rolls a `tuning.drops.<key>` row and asks a Spawner
## for the orbs. Static only. Called from the enemy and asteroid death paths.
##
## Spawning is deferred: deaths happen inside physics callbacks (area_entered),
## where adding a collision object would hit Godot's "flushing queries" error.
## A deferred call on a spawner freed meanwhile is dropped.


## Orbs a drop `row` ({chance, orbs}) gives for a `roll` in [0, 1): row.orbs
## when roll < row.chance, else 0. A missing or non-number field gives 0.
static func orb_count(row: Dictionary, roll: float) -> int:
	var chance: Variant = row.get("chance")
	var orbs: Variant = row.get("orbs")
	if not (chance is float or chance is int) or not (orbs is float or orbs is int):
		return 0
	if roll < float(chance):
		return maxi(int(orbs), 0)
	return 0


## Rolls `drops.<table_key>` and requests that many orbs from the Spawner
## `spawner_ref` (deferred), `energy.orb_spread_px` apart horizontally and
## centred on `at`. Returns the orb count; 0 (silently) for a null or freed
## spawner. The parameter is untyped on purpose: a `Spawner`-typed parameter
## rejects a previously freed instance with a script error.
static func drop(spawner_ref: Variant, table_key: String, at: Vector2, roll: float = randf()) -> int:
	if not is_instance_valid(spawner_ref):
		return 0
	var spawner: Spawner = spawner_ref as Spawner
	if spawner == null:
		return 0
	var n: int = orb_count(Config.section("drops." + table_key), roll)
	if n <= 0:
		return 0
	var spread: float = Config.num("energy.orb_spread_px")
	for i: int in n:
		var offset: float = (float(i) - float(n - 1) / 2.0) * spread
		spawner.spawn_orb.call_deferred({"position": at + Vector2(offset, 0.0)})
	return n

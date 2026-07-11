class_name Upgrades
extends Object

## The upgrade draft pool (roadmap M4). Weapons/utility only — flight-model
## mods are deliberately absent so no upgrade can break the tuned feel.
## Upgrades stack across drafts (picking Rapid Blaster twice compounds).

const POOL: Array[Dictionary] = [
	{"id": &"rapid_blaster", "title": "Rapid Blaster", "desc": "+35% blaster fire rate"},
	{"id": &"heavy_bolts", "title": "Heavy Bolts", "desc": "+40% blaster damage"},
	{"id": &"twin_racks", "title": "Twin Racks", "desc": "-50% missile cooldown"},
	{"id": &"seeker_optics", "title": "Seeker Optics", "desc": "35% faster missile lock, +25% lock cone"},
	{"id": &"armor_plating", "title": "Armor Plating", "desc": "+40 max hull"},
	{"id": &"self_repair", "title": "Self-Repair", "desc": "Regenerate 1.5 hull/s"},
	{"id": &"salvage_magnet", "title": "Salvage Magnet", "desc": "+50% score from kills"},
]


static func apply(id: StringName, mods: RunMods) -> void:
	match id:
		&"rapid_blaster":
			mods.fire_rate_mult *= 1.35
		&"heavy_bolts":
			mods.damage_mult *= 1.4
		&"twin_racks":
			mods.missile_cooldown_mult *= 0.5
		&"seeker_optics":
			mods.lock_time_mult *= 0.65
			mods.lock_cone_mult *= 1.25
		&"armor_plating":
			mods.max_health_bonus += 40.0
		&"self_repair":
			mods.regen_rate += 1.5
		&"salvage_magnet":
			mods.score_mult *= 1.5


static func title_of(id: StringName) -> String:
	for option: Dictionary in POOL:
		if option["id"] == id:
			return option["title"]
	return String(id)


## A draft of `count` distinct random options.
static func draft(count: int = 3) -> Array[Dictionary]:
	var pool: Array[Dictionary] = POOL.duplicate()
	pool.shuffle()
	var options: Array[Dictionary] = []
	for i: int in mini(count, pool.size()):
		options.append(pool[i])
	return options

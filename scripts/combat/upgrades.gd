class_name Upgrades
extends Object

## The upgrade draft pool (roadmap M4). Weapons/utility only — flight-model
## mods are deliberately absent so no upgrade can break the tuned feel.
## Upgrades stack across drafts (picking Rapid Blaster twice compounds).

const POOL: Array[Dictionary] = [
	{"id": &"rapid_blaster", "title": "Rapid Blaster", "desc": "+35% blaster fire rate"},
	{"id": &"heavy_bolts", "title": "Heavy Bolts", "desc": "+40% blaster damage"},
	{"id": &"heat_sinks", "title": "Heat Sinks", "desc": "+45% blaster heat capacity"},
	{"id": &"vent_ports", "title": "Vent Ports", "desc": "+50% blaster cooling"},
	{"id": &"autoloader", "title": "Autoloader", "desc": "+35% flak fire rate"},
	{"id": &"dense_frag", "title": "Dense Fragments", "desc": "+40% flak damage"},
	{"id": &"twin_racks", "title": "Twin Racks", "desc": "-50% missile cooldown"},
	{"id": &"seeker_optics", "title": "Seeker Optics", "desc": "35% faster missile lock, +25% lock cone"},
	{"id": &"armor_plating", "title": "Armor Plating", "desc": "+40 max hull"},
	{"id": &"self_repair", "title": "Self-Repair", "desc": "Regenerate 0.7 hull/s"},
	{"id": &"salvage_magnet", "title": "Salvage Magnet", "desc": "+50% score from kills"},
]


static func apply(id: StringName, mods: RunMods) -> void:
	match id:
		&"rapid_blaster":
			mods.fire_rate_mult *= 1.35
		&"heavy_bolts":
			mods.damage_mult *= 1.4
		# The duty-cycle pair. They are the answer to what Rapid Blaster now
		# costs: it buys rounds-per-second and spends them out of the same sink,
		# so a run that stacks fire rate without ever taking one of these is
		# buying a shorter burst.
		&"heat_sinks":
			mods.heat_capacity_mult *= 1.45
		&"vent_ports":
			mods.heat_cool_mult *= 1.5
		# The pod's own curve (v1.86). Both cards used to be free riders on the
		# two above: one "blaster" pick bought the flak the same buff, and
		# cadence is where a burst weapon's power actually lives, so the half
		# nobody paid for was the bigger half.
		&"autoloader":
			mods.flak_fire_rate_mult *= 1.35
		&"dense_frag":
			mods.flak_damage_mult *= 1.4
		&"twin_racks":
			mods.missile_cooldown_mult *= 0.5
		&"seeker_optics":
			mods.lock_time_mult *= 0.65
			mods.lock_cone_mult *= 1.25
		&"armor_plating":
			mods.max_health_bonus += 40.0
		&"self_repair":
			# Nerfed 1.5 -> 0.7 (playtest: one pick made the run effectively
			# invincible once fire rate scaled; see design doc v1.7).
			mods.regen_rate += 0.7
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

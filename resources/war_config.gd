class_name WarConfig
extends TunableConfig

## War-sim tunables (GAMEPLAY-DESIGN Iteration 1, P1). Same TunableConfig
## pattern as everything else; no overlay section yet — the war-sim is
## headless-only for now and the soak harness loads the defaults directly.
## Every number the generator and tick engine use lives here.

@export_group("Theater Generation")
## Node count (the P1.q1 lever, 20-40; ~30 fits current content variety).
@export var node_count: float = 30.0
## Hex-distance radius of the player's starting friendly pocket.
@export var player_pocket_hops: float = 2.0
## Garrison strength at the player's doorstep…
@export var garrison_base: float = 8.0
## …plus this per hex of distance from the player home (the difficulty
## gradient: easy pocket, hard depth).
@export var garrison_per_hop: float = 2.5
@export var garrison_cap: float = 40.0

@export_group("War Tick")
## Garrison strength a supplied factory adds to its sector each tick.
@export var production_rate: float = 2.0
## Garrison multiplier per tick while cut off from supply (siege decay).
@export var unsupplied_decay: float = 0.85
## Enemy offensive operations per tick.
@export var enemy_op_budget: float = 2.0
## Fraction of a garrison an attack commits (the rest holds the node).
@export var attack_commit_fraction: float = 0.6
## Strength ratio the enemy AI wants before it attacks.
@export var attack_win_ratio: float = 1.3
## Enemy aggression grows by this per tick — the P1.7 escalation clock. The
## war never settles into a static equilibrium; hesitate and it comes to you.
@export var escalation_per_tick: float = 0.003
@export var max_ticks: float = 300.0

@export_group("Sorties (proxy player)")
@export var starting_pilots: float = 5.0
## Strike reach in hexes from any player-owned airbase (P1.1).
@export var sortie_range_hops: float = 4.0
## Garrison strength a successful sortie removes (scaled by skill).
@export var sortie_damage: float = 10.0
## Baseline chance a failed/contested sortie costs a pilot; risk adds more.
@export var pilot_loss_base: float = 0.03
## HQ becomes attackable when enemy command posts alive <= this (P1.5).
@export var hq_unlock_command_posts: float = 1.0


const SAVE_PATH: String = "user://war_config.tres"
const DEFAULTS_PATH: String = "res://resources/default_war_config.tres"


func save_path() -> String:
	return SAVE_PATH


func defaults_path() -> String:
	return DEFAULTS_PATH

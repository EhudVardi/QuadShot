class_name FlightConfig
extends Resource

## Every flight tunable lives here (handoff §5): scripts read it, the debug
## overlay (Phase 3) writes it live. Fields are added per phase — no dead
## tunables. Defaults per handoff §6.

@export_group("Airframe")
@export var mass: float = 0.65
@export var arm_length: float = 0.12

@export_group("Motors")
@export var thrust_to_weight_ratio: float = 4.5
## First-order lag time constant (s). Instant thrust feels arcade-y.
@export var motor_lag_tau: float = 0.05

@export_group("Aerodynamics")
## Quadratic drag: F = -c * |v| * v
@export var drag_coefficient: float = 0.03
## Explicit angular damping torque: T = -k * angular_velocity.
## Godot's built-in damping is disabled on the drone body so this stays tunable.
@export var angular_damping: float = 0.02

@export_group("Arming")
## Arming is refused above this throttle fraction (safety, handoff §6.6).
@export var arm_throttle_threshold: float = 0.05

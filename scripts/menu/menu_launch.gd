class_name MenuLaunch

## Cross-scene launch flags for the flyable menu (GAMEPLAY-DESIGN B5).
## change_scene_to_file cannot carry arguments, so the tower parks the chosen
## mode here and the target scene reads it — the same static-layer pattern as
## RunMods. Defaults mean a directly-booted scene behaves exactly as before
## the menu existed.

## FLY FREE (B.q2): main.tscn arms without starting the run — no waves, no
## score, no summary; pure sandbox flight in the game map.
static var free_fly: bool = false

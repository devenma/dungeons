class_name CollisionLayers
extends RefCounted

## Single source of truth for 2D physics collision layer bits (HP-2).
## Every .tscn collision literal must match these values.

const WORLD: int = 1
const PLAYER_BODY: int = 2
const ENEMY_BODY: int = 4
const PLAYER_HURTBOX: int = 8
const ENEMY_HURTBOX: int = 16

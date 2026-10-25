class_name RewardChest
extends Area2D

## One-shot reward chest (RC-1..RC-3). Placed by the Spawner in REWARD
## zones; on `interact` grants one weapon from a seeded pool plus a seeded
## roll of `drop_table`, emitting `granted` / `loot_found` exactly once —
## later interacts are no-ops. The chest never touches RunManager directly:
## the Spawner relays both signals upward.

signal granted(weapon_data: WeaponData)
signal loot_found(items: Array[ItemData], gold: int)

## Salt for the seeded pick (RC-3). Defined once here and referenced by
## the Spawner so placement and selection never diverge (R4).
const REWARD_SALT: int = 0x5EED
## Sal extra de la tirada de botín (RC-3) / Extra salt for the loot roll (RC-3)
const LOOT_SALT: int = 0x1007

## Armas posibles; el Spawner la inyecta / Possible weapons; injected by the Spawner
@export var weapon_pool: Array[WeaponData] = []
## Botín además del arma; null = solo arma / Loot besides the weapon; null = weapon only
@export var drop_table: DropTable
## Seed del piso y zona del cofre: fijan la tirada (RC-3) / Floor seed and chest zone: they fix the roll (RC-3)
@export var floor_seed: int = 0
@export var zone_id: int = 0

var _player_inside: bool = false
var _used: bool = false

@onready var _visual: ColorRect = $VisualColorRect


func _ready() -> void:
	# Detect only the player body (same layer/mask contract as ExitArea).
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_inside and not _used:
		_grant()


func _grant() -> void:
	if _used:
		return  # RC-1: locked/empty after the first grant.
	_used = true
	var data: WeaponData = _pick_weapon()
	var loot_items: Array[ItemData] = []
	var loot_gold: int = 0
	if drop_table != null:
		# Otra sal que la del arma para no correlacionar las tiradas / A different salt than the weapon pick so rolls are not correlated
		var rng := RandomNumberGenerator.new()
		rng.seed = floor_seed ^ zone_id ^ REWARD_SALT ^ LOOT_SALT
		loot_items = drop_table.roll_items(rng)
		loot_gold = drop_table.roll_gold(rng)
	if data == null and loot_items.is_empty() and loot_gold == 0:
		return
	# Dim visuals to mark the chest as used/empty.
	_visual.self_modulate = Color(0.4, 0.4, 0.4, 1.0)
	if data != null:
		granted.emit(data)
	if not loot_items.is_empty() or loot_gold > 0:
		loot_found.emit(loot_items, loot_gold)


func _pick_weapon() -> WeaponData:
	if weapon_pool.is_empty():
		return null
	# RC-3: seeded selection — same seed + zone always picks the same
	# weapon (§37 reproducibility).
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed ^ zone_id ^ REWARD_SALT
	var pool: Array[WeaponData] = weapon_pool
	var index: int = rng.randi_range(0, pool.size() - 1)
	return pool[index]


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		_player_inside = true


func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		_player_inside = false

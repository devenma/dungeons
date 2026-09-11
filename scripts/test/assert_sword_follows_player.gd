extends SceneTree

# Runtime assertion for scene-level transform wiring:
# the Sword must follow the Player. Regression for the plain-Node "Weapons"
# container bug — a Node (non-CanvasItem) parent severs the CanvasItem
# transform chain, leaving the sword at the world origin (map corner) with its
# hitbox swinging around (0,0) → zero damage.
# Run: godot --headless -s scripts/test/assert_sword_follows_player.gd

var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_fails += 1
		print("VERIFY_FAIL: " + msg)


func _initialize() -> void:
	_run()


func _run() -> void:
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: CharacterBody2D = player_scene.instantiate()
	root.add_child(player)
	# Nodes added during _initialize receive READY on the first loop iteration;
	# wait one frame so _ready/@onready run and transforms propagate.
	await process_frame

	var sword: Node2D = player.get_node("Weapons/Sword") as Node2D
	_check(sword != null, "sword exists under Weapons")
	if sword == null:
		quit(1)
		return
	_check(sword.get_node_or_null("Hitbox") != null, "sword hitbox @onready resolved")

	# ── Sword follows the player ──
	player.position = Vector2(500, 300)
	await process_frame
	_check(sword.global_position.distance_to(player.global_position) < 0.01,
			"sword global position follows the player")

	player.position += Vector2(123, 456)
	await process_frame
	_check(sword.global_position.distance_to(player.global_position) < 0.01,
			"sword still follows after the player moves")

	# ── Swing places the hitbox arc at the player + aim offset ──
	var swung: bool = sword.try_attack(Vector2.DOWN)
	_check(swung, "try_attack accepted the swing")
	await process_frame
	var shape: CollisionShape2D = sword.get_node("Hitbox/CollisionShape2D") \
			as CollisionShape2D
	# Hitbox arc offset is scene-tuned: sword.tscn places the 30x30 swing
	# shape at (23, 0); rotated DOWN (PI/2) that lands at (0, 23).
	var expected_center: Vector2 = player.global_position + Vector2(0, 23)
	_check(shape.global_position.distance_to(expected_center) < 0.01,
			"hitbox arc centered at player + aim*hitbox_offset (DOWN)")

	# ── Wiring sanity ──
	_check(player.is_in_group("player"), "player in 'player' group")
	_check(player.get_node_or_null("Health") != null, "player has Health node")
	_check(player.get_node_or_null("Hurtbox") != null, "player has Hurtbox")

	player.queue_free()
	await process_frame

	if _fails == 0:
		print("VERIFY_ALL_OK")
		quit(0)
	else:
		print("VERIFY_FAILED fails=%d" % _fails)
		quit(1)

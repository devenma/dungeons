extends Node

var run_seed: int = 0
var current_floor: int = 0


func start_new_run() -> void:
	run_seed = randi()
	current_floor = 0


func next_floor() -> void:
	current_floor += 1
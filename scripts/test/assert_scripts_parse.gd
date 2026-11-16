extends SceneTree

## Run: godot --headless -s scripts/test/assert_scripts_parse.gd
## Loads every .gd under res:// so a script no other test touches still fails the suite when it
## does not parse (`--import` and `--quit-after` exit 0 on a parse error).
## Exit 0 = pass, 1 = fail.

var _fails: int = 0
var _checked: int = 0


func _initialize() -> void:
	_walk("res://")
	if _checked == 0:
		_fails += 1
		print("VERIFY_FAIL: found no scripts to check")
	print("PASS: %d scripts parse" % _checked if _fails == 0 else "checked %d scripts" % _checked)
	quit(1 if _fails > 0 else 0)


func _walk(dir_path: String) -> void:
	for sub: String in DirAccess.get_directories_at(dir_path):
		# Cache del editor y carpetas ocultas / Editor cache and hidden folders
		if not sub.begins_with("."):
			_walk(dir_path.path_join(sub))
	for file: String in DirAccess.get_files_at(dir_path):
		if file.get_extension() == "gd":
			var path: String = dir_path.path_join(file)
			var script: Script = load(path) as Script
			_checked += 1
			if script == null or not script.can_instantiate():
				_fails += 1
				print("VERIFY_FAIL: %s does not parse" % path)

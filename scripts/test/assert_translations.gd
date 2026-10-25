extends SceneTree

## Translations assertion (D16): strings.csv loads as es and en, Spanish is the
## default locale, switching locale changes tr() and every item key resolves.
## Exit 0 = pass, 1 = fail.

const ITEM_PATHS: Array[String] = [
	"res://resources/items/blue_stone.tres",
	"res://resources/items/slime_gel.tres",
	"res://resources/items/bone_shard.tres",
	"res://resources/items/silver_ring.tres",
]

var _failures: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	_check(locales.has("es") and locales.has("en"), "translations loaded for es and en")
	_check(TranslationServer.get_locale().begins_with("es"), "default locale is es")
	_check(tr("ui.hud.picked_up") == "Recogido: %s", "es: ui.hud.picked_up")
	for path in ITEM_PATHS:
		var item: ItemData = load(path)
		_check(item.display_name() != item.name_key and item.display_description() != item.desc_key,
				"es: name and description keys resolve for " + path)
		_check(item.icon != null, "icon set for " + path)

	TranslationServer.set_locale("en")
	_check(tr("ui.hud.picked_up") == "Picked up: %s", "en: ui.hud.picked_up")
	var stone: ItemData = load("res://resources/items/blue_stone.tres")
	_check(stone.display_name() == "Blue stone", "en: blue stone name")
	TranslationServer.set_locale("es")
	_check(stone.display_name() == "Piedra azul", "es: blue stone name after switching back")

	_check(_failures == 0, "translations: all checks passed")
	quit(0 if _failures == 0 else 1)

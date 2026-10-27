extends SceneTree

## Run: godot --headless -s scripts/test/assert_text_consistency.gd
## Every strings.csv row has Spanish and English text with the same %s / %d placeholders; every
## term in locale/GLOSARIO.md is translated with one of its fixed forms; and in each locale the
## Labels and Buttons of the screen-space UI scenes stay inside the 480x270 screen.
## Exit 0 = pass, 1 = fail.

const STRINGS_PATH: String = "res://locale/strings.csv"
const GLOSSARY_PATH: String = "res://locale/GLOSARIO.md"
# Escenas de UI en coordenadas de pantalla / UI scenes in screen coordinates
const SCREEN_SCENES: Array[String] = [
	"res://scenes/ui/hud.tscn",
	"res://scenes/ui/backpack_panel.tscn",
	"res://scenes/ui/shop_panel.tscn",
	"res://scenes/ui/pause_menu.tscn",
	"res://scenes/ui/death_screen.tscn",
]
const LOCALES: Array[String] = ["es", "en"]

var _failures: int = 0
var _fit_checked: int = 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		print("FAIL: " + label)


func _run() -> void:
	var rows: Array[PackedStringArray] = _load_rows()
	_check(rows.size() > 100, "strings.csv has rows (%d)" % rows.size())
	_check_rows(rows)
	_check_glossary(rows)
	await _check_fit()
	if _failures == 0:
		print("PASS: %d rows consistent with the glossary, %d UI texts fit the screen in %s"
				% [rows.size(), _fit_checked, ", ".join(LOCALES)])
	quit(0 if _failures == 0 else 1)


func _load_rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var file: FileAccess = FileAccess.open(STRINGS_PATH, FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			rows.append(row)
	return rows


func _check_rows(rows: Array[PackedStringArray]) -> void:
	var placeholder: RegEx = RegEx.create_from_string("%[sd]")
	for row in rows:
		_check(not row[1].strip_edges().is_empty() and not row[2].strip_edges().is_empty(),
				"%s: missing es or en text" % row[0])
		var es_marks: Array[String] = _sorted_matches(placeholder, row[1])
		var en_marks: Array[String] = _sorted_matches(placeholder, row[2])
		_check(es_marks == en_marks, "%s: placeholders differ (es %s, en %s)" % [row[0], es_marks, en_marks])


func _sorted_matches(regex: RegEx, text: String) -> Array[String]:
	var found: Array[String] = []
	for result: RegExMatch in regex.search_all(text):
		found.append(result.get_string())
	found.sort()
	return found


## Filas de la tabla de términos: [formas es, formas en, claves exceptuadas]
## Rows of the terms table: [es forms, en forms, excepted keys]
func _load_glossary() -> Array[Array]:
	var terms: Array[Array] = []
	var file: FileAccess = FileAccess.open(GLOSSARY_PATH, FileAccess.READ)
	var in_terms: bool = false
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.begins_with("## "):
			in_terms = line == "## Términos"
			continue
		if not in_terms or not line.begins_with("|") or line.begins_with("|---"):
			continue
		var cells: PackedStringArray = line.trim_prefix("|").trim_suffix("|").split("|")
		if cells.size() < 3 or cells[0].strip_edges() == "Español":
			continue
		terms.append([_forms(cells[0]), _forms(cells[1]), _forms(cells[2].replace(",", " / "))])
	return terms


func _forms(cell: String) -> PackedStringArray:
	var forms: PackedStringArray = []
	for form: String in cell.split("/"):
		if not form.strip_edges().is_empty():
			forms.append(form.strip_edges())
	return forms


## Palabra completa; respeta mayúsculas solo si el término empieza con mayúscula
## Whole word; case-sensitive only when the term starts with a capital letter
func _word_regex(term: String) -> RegEx:
	var flags: String = "" if term[0] != term[0].to_lower() else "(?i)"
	var escaped: String = term.replace("-", "\\-")
	return RegEx.create_from_string(flags + "(?<![\\p{L}])" + escaped + "(?![\\p{L}])")


func _check_glossary(rows: Array[PackedStringArray]) -> void:
	var terms: Array[Array] = _load_glossary()
	_check(terms.size() > 10, "glossary has terms (%d)" % terms.size())
	for term: Array in terms:
		var es_forms: PackedStringArray = term[0]
		var en_forms: PackedStringArray = term[1]
		var excepted: PackedStringArray = term[2]
		var es_regexes: Array[RegEx] = []
		for form in es_forms:
			es_regexes.append(_word_regex(form))
		var en_regexes: Array[RegEx] = []
		for form in en_forms:
			en_regexes.append(RegEx.create_from_string("(?i)" + form.replace("-", "\\-")))
		for row in rows:
			if excepted.has(row[0]) or not _any_match(es_regexes, row[1]):
				continue
			_check(_any_match(en_regexes, row[2]), "%s: '%s' should be translated as '%s' (en: %s)"
					% [row[0], es_forms[0], " / ".join(en_forms), row[2]])


func _any_match(regexes: Array[RegEx], text: String) -> bool:
	for regex in regexes:
		if regex.search(text) != null:
			return true
	return false


func _check_fit() -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height")))
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		for path in SCREEN_SCENES:
			var scene: Control = (load(path) as PackedScene).instantiate() as Control
			root.add_child(scene)
			_show_all(scene)
			await process_frame
			await process_frame
			_check_inside(scene, screen, "%s %s" % [locale, path.get_file()])
			scene.free()
	TranslationServer.set_locale("es")


## Muestra todo, aunque la escena arranque oculta, para medir cada texto
## Shows everything, even what the scene hides at start, to measure every text
func _show_all(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = true
	for child in node.get_children():
		_show_all(child)


func _check_inside(node: Node, screen: Rect2, tag: String) -> void:
	if (node is Label or node is Button) and not (node as Control).text.is_empty():
		var control: Control = node
		_fit_checked += 1
		var rect: Rect2 = control.get_global_rect()
		_check(screen.encloses(rect), "%s: %s '%s' leaves the screen (%s)"
				% [tag, control.name, control.tr(control.text), rect])
	for child in node.get_children():
		_check_inside(child, screen, tag)

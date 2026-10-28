extends Control

## Mochila y almacén del gremio (acción `inventory`, I): grillas de slots con ícono, cantidad,
## borde de rareza y tooltip. Se navega con el mouse o con el foco (flechas / cruceta).
## En el gremio pausa el juego y deja pasar objetos: activar un slot mueve la pila al otro lado,
## con `transfer_one` (Shift / X del mando) mueve una unidad, y "Guardar todo" deposita la mochila
## y banca el oro. Guarda el perfil tras cada cambio. En la mazmorra el almacén es solo lectura.
## Corre con PROCESS_MODE_ALWAYS (en la escena) para recibir input en pausa.
## Backpack and guild storage (`inventory` action, I): slot grids with icon, count, rarity
## border and tooltip. Navigable with the mouse or with focus (arrows / d-pad).
## In the guild it pauses the game and lets items through: activating a slot moves the stack to
## the other side, `transfer_one` (Shift / gamepad X) moves one unit, and "Store all" deposits the
## backpack and banks the gold. Saves the profile after every change. In the dungeon the storage
## is read-only. Runs with PROCESS_MODE_ALWAYS (set in the scene) to get input while paused.

## Variación del tema por rareza, en el orden de ItemData.Rarity / Theme variation per rarity, in ItemData.Rarity order
const RARITY_VARIATIONS: Array[StringName] = [
	&"InventorySlot",
	&"InventorySlotCommon",
	&"InventorySlotUncommon",
	&"InventorySlotRare",
	&"InventorySlotLegendary",
]
## Lado de un slot del kit (px) / Kit slot side (px)
const SLOT_SIZE: int = 20

@export var run_manager_node_path: NodePath = NodePath("../../RunManager")
@export var profile_state_node_path: NodePath = NodePath("../../ProfileState")

var _run_manager: RunManager
var _profile: ProfileState
# El panel pausó el árbol y debe despausarlo / The panel paused the tree and must unpause it
var _paused_by_panel: bool = false

@onready var _backpack_grid: GridContainer = %BackpackGrid
@onready var _storage_grid: GridContainer = %StorageGrid
@onready var _deposit_button: Button = %DepositButton
@onready var _tooltip: PanelContainer = %Tooltip
@onready var _tooltip_name: Label = %TooltipName
@onready var _tooltip_desc: Label = %TooltipDesc


func _ready() -> void:
	hide()
	_tooltip.hide()
	_deposit_button.pressed.connect(deposit_all)
	_run_manager = get_node_or_null(run_manager_node_path) as RunManager
	_profile = get_node_or_null(profile_state_node_path) as ProfileState
	if _run_manager != null:
		_run_manager.backpack_changed.connect(_refresh)
	if _profile != null:
		_profile.profile_changed.connect(_refresh)
	_refresh()


# En _input para ganarle al menú de pausa: `pause` con el panel abierto solo lo cierra
# In _input to beat the pause menu: `pause` with the panel open only closes it
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		# No se abre sobre otra pausa (menú, tienda, cámara) / Does not open over another pause (menu, shop, camera)
		if visible or not get_tree().paused:
			set_open(not visible)


func set_open(open: bool) -> void:
	visible = open
	_tooltip.hide()
	if open and storage_accessible() and not get_tree().paused:
		get_tree().paused = true
		_paused_by_panel = true
	elif not open and _paused_by_panel:
		_paused_by_panel = false
		get_tree().paused = false
	_refresh()
	if open and _backpack_grid.get_child_count() > 0:
		var first_slot: Button = _backpack_grid.get_child(0)
		# Diferido: la grilla se acomoda al final del frame y el tooltip necesita su posición
		# Deferred: the grid lays out at the end of the frame and the tooltip needs its position
		first_slot.grab_focus.call_deferred()


## El almacén solo se toca en el gremio (piso 0) / Storage can only be touched in the guild (floor 0)
func storage_accessible() -> bool:
	return _run_manager != null and _profile != null and _run_manager.current_floor == 0


func deposit_all() -> void:
	if not storage_accessible():
		return
	_profile.deposit(_run_manager.backpack, _run_manager.take_backpack_gold())
	_profile.save_profile()


func _transfer_slot(grid: GridContainer, index: int, one_unit: bool) -> void:
	if not storage_accessible():
		return
	var source: Inventory = _inventory_of(grid)
	var target: Inventory = _profile.storage if grid == _backpack_grid else _run_manager.backpack
	if index >= source.slots.size():
		return
	var count: int = source.slots[index]["count"]
	var item: ItemData = source.slots[index]["item"]
	var amount: int = 1 if one_unit else count
	# El tope de lo que se lleva encima vale también al sacar del almacén (D25) / The carry cap also applies when taking from storage (D25)
	if target == _run_manager.backpack and item.max_carried > 0:
		amount = mini(amount, item.max_carried - target.count_of(item))
	if source.move_slot_to(index, target, amount) == 0:
		return
	_profile.save_profile()
	# La mochila avisa antes de que el almacén termine de cambiar / The backpack signals before storage finishes changing
	_refresh()
	var slot: Button = grid.get_child(index)
	_show_tooltip(slot, grid, index)


func _on_slot_pressed(grid: GridContainer, index: int) -> void:
	_transfer_slot(grid, index, Input.is_action_pressed("transfer_one"))


# Shift se mantiene como modificador; el botón del mando mueve una unidad solo
# Shift is held as a modifier; the gamepad button moves one unit on its own
func _on_slot_gui_input(event: InputEvent, grid: GridContainer, index: int) -> void:
	if event is InputEventJoypadButton and event.is_action_pressed("transfer_one"):
		_transfer_slot(grid, index, true)
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if not visible:
		return
	_deposit_button.visible = storage_accessible()
	if _run_manager != null:
		_fill_grid(_backpack_grid, _run_manager.backpack)
	if _profile != null:
		_fill_grid(_storage_grid, _profile.storage)


func _inventory_of(grid: GridContainer) -> Inventory:
	if grid == _backpack_grid:
		return _run_manager.backpack if _run_manager != null else null
	return _profile.storage if _profile != null else null


# Los slots se crean una vez por capacidad; refrescar solo cambia su contenido
# Slots are created once per capacity; a refresh only changes their content
func _fill_grid(grid: GridContainer, inventory: Inventory) -> void:
	while grid.get_child_count() < inventory.capacity:
		grid.add_child(_new_slot(grid, grid.get_child_count()))
	for i in grid.get_child_count():
		var slot: Button = grid.get_child(i)
		var item: ItemData = _item_at(inventory, i)
		var count: int = inventory.slots[i]["count"] if item != null else 0
		slot.icon = item.icon if item != null else null
		slot.theme_type_variation = RARITY_VARIATIONS[item.rarity] if item != null else RARITY_VARIATIONS[0]
		var count_label: Label = slot.get_node("Count")
		count_label.text = str(count) if count > 1 else ""


func _new_slot(grid: GridContainer, index: int) -> Button:
	var slot: Button = Button.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var count_label: Label = Label.new()
	count_label.name = "Count"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# La línea mide 11 px: se baja para que los dígitos apoyen en el borde / The line is 11 px: lowered so digits sit on the border
	count_label.offset_top = SLOT_SIZE - 11
	count_label.offset_right = -1
	slot.add_child(count_label)
	slot.pressed.connect(_on_slot_pressed.bind(grid, index))
	slot.gui_input.connect(_on_slot_gui_input.bind(grid, index))
	slot.mouse_entered.connect(_show_tooltip.bind(slot, grid, index))
	slot.focus_entered.connect(_show_tooltip.bind(slot, grid, index))
	slot.mouse_exited.connect(_tooltip.hide)
	slot.focus_exited.connect(_tooltip.hide)
	return slot


func _item_at(inventory: Inventory, index: int) -> ItemData:
	if inventory == null or index >= inventory.slots.size():
		return null
	var item: ItemData = inventory.slots[index]["item"]
	return item


func _show_tooltip(slot: Button, grid: GridContainer, index: int) -> void:
	var item: ItemData = _item_at(_inventory_of(grid), index)
	if item == null:
		_tooltip.hide()
		return
	_tooltip_name.text = item.display_name()
	_tooltip_desc.text = item.display_description()
	_tooltip.show()
	_tooltip.reset_size()
	var below: Vector2 = slot.global_position - global_position + Vector2(0, slot.size.y + 1)
	_tooltip.position = below.clamp(Vector2.ZERO, size - _tooltip.size)

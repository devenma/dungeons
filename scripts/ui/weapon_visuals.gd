extends RefCounted

## Ícono y nombre traducido de cada familia de arma, para el HUD y el toast.
## Icon and translated name of each weapon family, for the HUD and the toast.
## shortcut: se resuelve por familia (WeaponKind), no por arma; pasar a campos icon/name_key
## en WeaponData cuando haya dos armas de la misma familia.

const ICONS: Dictionary = {
	WeaponData.WeaponKind.MELEE: preload("res://assets/art/items/espada_oxidada.png"),
	WeaponData.WeaponKind.RANGED_PHYSICAL: preload("res://assets/art/items/arco.png"),
	WeaponData.WeaponKind.RANGED_MAGIC: preload("res://assets/art/items/baston_hueso.png"),
}
const NAME_KEYS: Dictionary = {
	WeaponData.WeaponKind.MELEE: "item.espada_oxidada.name",
	WeaponData.WeaponKind.RANGED_PHYSICAL: "item.arco.name",
	WeaponData.WeaponKind.RANGED_MAGIC: "item.baston_hueso.name",
}


static func icon(data: WeaponData) -> Texture2D:
	if data == null:
		return null
	var texture: Texture2D = ICONS.get(data.weapon_kind)
	return texture


static func display_name(data: WeaponData) -> String:
	if data == null:
		return ""
	var key: String = NAME_KEYS.get(data.weapon_kind, data.weapon_name)
	return String(TranslationServer.translate(key))

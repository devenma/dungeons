class_name ShopData
extends Resource

## Lo que vende una tienda del pueblo (D2, D25, §39). Lo que compra sale del ItemData.value de cada objeto.
## What a town shop sells (D2, D25, §39). What it buys is priced by each item's ItemData.value.

## Objeto a la venta; null = no vende objetos / Item for sale; null = sells no items
@export var item: ItemData
## Precio en oro bancado; mayor que el valor de venta para que no se pueda revender con ganancia
## Price in banked gold; above the sell value so it cannot be resold at a profit
@export var price: int = 0
## Mejoras permanentes a la venta (D11), se compran una vez / Permanent upgrades for sale (D11), bought once
@export var upgrades: Array[UpgradeData] = []
## Clave del título del panel / Panel title key
@export var title_key: String = "ui.shop.merchant_title"
## Prefijo de las líneas de quien atiende (<prefijo>.open, .buy, .no_money...) / Prefix of the keeper's lines (<prefix>.open, .buy, .no_money...)
@export var lines_prefix: String = "npc.merchant.shop"
## Compra lo de la mochila (solo la Urraca) / Buys what is in the backpack (only the Magpie)
@export var buys_loot: bool = true

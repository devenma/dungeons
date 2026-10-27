class_name ShopData
extends Resource

## Lo que vende una tienda del gremio (D2, §39). Lo que compra sale del ItemData.value de cada objeto.
## What a guild shop sells (D2, §39). What it buys is priced by each item's ItemData.value.

## Objeto a la venta / Item for sale
@export var item: ItemData
## Precio en oro bancado; mayor que el valor de venta para que no se pueda revender con ganancia
## Price in banked gold; above the sell value so it cannot be resold at a profit
@export var price: int = 0
## Mejoras permanentes a la venta (D11), se compran una vez / Permanent upgrades for sale (D11), bought once
@export var upgrades: Array[UpgradeData] = []

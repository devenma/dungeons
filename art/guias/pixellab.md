# PixelLab: costos, presupuesto y plan

Precios de las herramientas del MCP de PixelLab al 2026-11-01 (el costo exacto de cada herramienta está en su
descripción y `get_pro_flash_capabilities` lo cotiza gratis). Antes de una prueba nueva se avisa el costo estimado.

## Presupuesto

- Plan actual: **Tier 1, 2000 generaciones por mes**, se recarga el 24. El saldo se ve con `get_balance`.
- El primer ciclo (oct-nov 2026) gastó ~1180 buscando estilo y armando el flujo: fue el costo de arranque.
- El arte va al ritmo del juego, no al revés: no hace falta producir en masa.

## Costo por asset

| Asset | Generaciones |
|---|---|
| Personaje con el flujo 3D (solo la referencia de 8 direcciones, Pro Flash 64-96 px, 2-3 intentos) | **~15-20** |
| Animaciones y variantes de un personaje 3D (salen de rig3d) | 0 |
| Boceto de personaje, 8 direcciones hasta 88 px (`create_character` modo v3, sin ancla de estilo) | 2 |
| Personaje animado solo con PixelLab (referencia + 8-9 animaciones en 4 direcciones) | ~50-100 |
| Objeto o prop, 1 dirección / 8 direcciones (Pro Flash) | 5 / 6-7 |
| Hoja de 16 tiles de 32 px (`create_tiles_pro`) | 10 |
| Tileset de transición de terreno, estándar / pro | 1 / 15-25 |
| Referencia de jefe de 128-256 px, 8 direcciones | 8-17 por intento |
| Animación a medida (v3) de 160-256 px | 4-8 por dirección |
| Efectos y retoques (`vfx_workbench`, `pixelart_workbench`) | 0 |

Ejemplo de un mes de 2000: ~40 personajes (720), ~60 props (420), ~20 hojas de tiles (200) y ~30 % de reserva para
pruebas.

## Jefes y criaturas grandes

Valen gastar más: se ven una vez por dungeon y son el pico de cada expedición. Para abaratarlos:

- Un jefe fijo (como la Madre de la Fosa) necesita 1-2 direcciones, no 4.
- Las criaturas grandes se arman por partes (cabeza, cuerpo, alas) animadas en Godot (AGENTS §38.1): PixelLab dibuja
  las piezas una vez.
- Las criaturas no humanoides no entran en rig3d: gastan en animaciones de PixelLab (30-80 cada una).

Un jefe fijo con 5-6 ataques en una dirección anda por 60-120 generaciones.

## Cuándo subir de plan

| Plan | Qué agrega | Para nosotros |
|---|---|---|
| Tier 2 (USD 24/mes) | 5000 por mes, 10 trabajos en paralelo, imágenes y ediciones de hasta 512×512, acceso anticipado | Lo único que importa es **512 px**: la pantalla es de 480×270, así que cubre fondos, fachadas, arenas de jefe, jefes de más de 256 px y arte de portada o de diálogos |
| Tier 3 (USD 50/mes) | 10000 por mes, 20 en paralelo, votar prioridades, canal con el equipo de PixelLab | No se justifica |

Subir a **Tier 2 por un mes** cuando haya un bloque de trabajo que use los 512 px o el volumen extra: el mes del
primer jefe grande, una pasada de fondos y arenas, o una tanda de personajes que pase las ~1500 generaciones. Después
se vuelve a bajar. **Antes de pagar:** confirmar con PixelLab que el tope de 512 vale también para la API y el MCP
(hoy las herramientas del MCP dicen "máximo 256").

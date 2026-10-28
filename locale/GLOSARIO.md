# Glosario de traducción

Términos que se traducen **siempre igual** en `strings.csv`. Si la misma palabra sale de dos formas, el jugador cree que son dos cosas distintas (dos mecánicas, dos lugares). Cualquier persona o agente que traduzca recibe esta tabla.

`assert_text_consistency` lee la tabla: en cada fila de `strings.csv` donde aparece el término en español, el inglés tiene que traer alguna de sus formas. Los términos con mayúscula se buscan respetando mayúsculas (nombres propios); los demás, sin importar mayúsculas. Varias formas van separadas por ` / `. En "Excepciones" van las claves donde el término se usa con otro sentido o en un juego de palabras, con el motivo en las notas.

## Términos

| Español | English | Excepciones | Notas |
|---|---|---|---|
| Farol | Lantern | | El faro del gremio que trae de vuelta a los muertos. |
| gremio | guild | | "Gremio del Farol" → "The Lantern Guild". |
| Boca | Mouth | | La entrada a la mazmorra. |
| mochila | pack | | Lo que se lleva encima y se pierde al morir. |
| almacén | storage / storeroom | | "storeroom" solo cuando lo dice un personaje. |
| aguante | stamina | | El recurso de los golpes y la voltereta. |
| piedra azul / piedras azules | blue stone / blue stones | | Consumible que salva la mochila al morir (D1). |
| vial de sangre / viales de sangre | blood vial / blood vials | | Lo vende la botica: cura 35 y se llevan 3 como máximo (D25). |
| maná | mana | | |
| expedición | expedition | | Una bajada, de la puerta del gremio a la vuelta. |
| botín | loot | | |
| reliquia | relic | | |
| Urraca | Magpie | | Ilse, la reducidora. |
| Hermana | Sister | | La sanadora, Hermana Ancel. |
| herrera | blacksmith | | |
| Cosido | Stitched | | Jefe. "El Cosido" → "The Stitched"; "del Cosido" → "Stitched's". |
| Madre | Mother | | Jefa, "la Madre de la Fosa" → "the Mother of the Pit". |
| fosa | pit | | |
| osario | ossuary | | |
| cripta | crypt | | |
| errante | wandering | | "Cadáver errante" → "Wandering corpse". |
| Escupebilis | Bile-spitter | | |
| Reptante | Crawler | | |
| Cultista | Cultist | | |

## Estilo

- **Registro:** el español usa "tú" neutro mientras D16 no decida entre "tú" y "vos".
- **Inglés británico:** *armour*, *colour*, *grey*. Es el que ya usa el archivo.
- **Tono Fear & Hunger:** frases cortas y secas. Ante la duda, traducir el sentido y el tono, no palabra por palabra.
- **Marcadores:** cada `%s` y `%d` del español va en el inglés, la misma cantidad de cada uno. El test lo revisa.
- **Retrotraducción:** para revisar un texto narrativo traducido con IA, otra pasada que no vea el original lo vuelve a traducir al español; si no dice lo mismo, se marca para revisión humana.

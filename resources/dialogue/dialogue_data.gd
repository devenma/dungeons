class_name DialogueData
extends Resource

## Diálogo data-driven (D14, §39): líneas en orden, cada una con quién habla. Todo son claves de texto que
## pasan por tr(), así el diálogo se traduce con el resto (D16).
## Data-driven dialogue (D14, §39): lines in order, each with who speaks. Everything is a text key that goes
## through tr(), so the dialogue is translated with the rest (D16).

## Claves de las líneas, en orden / Line keys, in order
@export var lines: PackedStringArray = []
## Clave del nombre de quien dice cada línea (mismo índice); vacía = narración
## Name key of who says each line (same index); empty = narration
@export var speakers: PackedStringArray = []


func speaker_at(index: int) -> String:
	return speakers[index] if index < speakers.size() else ""

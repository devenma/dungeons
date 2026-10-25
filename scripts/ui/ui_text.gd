extends RefCounted

## Texto traducido por clave, con un texto de respaldo mientras la clave no esté en las traducciones.
## Translated text by key, with a fallback text while the key is missing from the translations.


static func tr_or(key: String, fallback: String) -> String:
	var text: String = TranslationServer.translate(key)
	return fallback if text == key else text

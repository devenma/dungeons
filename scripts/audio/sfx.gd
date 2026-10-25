extends RefCounted

## Sonidos sueltos: copia un AudioStreamPlayer2D armado en una escena (stream, volumen y bus) y lo toca en el
## mundo, así sobrevive al dueño (enemigo que muere, flecha que impacta). La copia se libera al terminar.
## Detached sounds: copies an AudioStreamPlayer2D authored in a scene (stream, volume and bus) and plays it in
## the world, so it outlives its owner (a dying enemy, an arrow on impact). The copy frees itself when done.


static func play_detached(template: AudioStreamPlayer2D) -> void:
	var tree: SceneTree = template.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	var copy: AudioStreamPlayer2D = template.duplicate() as AudioStreamPlayer2D
	parent.add_child(copy)
	copy.global_position = template.global_position
	copy.finished.connect(copy.queue_free)
	copy.play()

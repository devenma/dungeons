extends PointLight2D

## Parpadeo sutil de antorcha con ruido sembrado (reproducible) / Subtle seeded-noise torch flicker (reproducible).

# Semilla del ruido: misma semilla, mismo parpadeo / Noise seed: same seed, same flicker
@export var flicker_seed: int = 7
# Variación de energía, fracción de la base (0.12 = ±12%) / Energy variation, fraction of the base
@export var energy_amount: float = 0.12
# Variación de tamaño, fracción de texture_scale / Size variation, fraction of texture_scale
@export var scale_amount: float = 0.03
# Rasgos de ruido por segundo / Noise features per second
@export var flicker_speed: float = 4.0

var _noise: FastNoiseLite = FastNoiseLite.new()
# Energía y escala de la escena, centro del parpadeo / Scene energy and scale, centre of the flicker
var _base_energy: float = 1.0
var _base_scale: float = 1.0
# Tiempo de ruido acumulado (s × flicker_speed) / Accumulated noise time (s × flicker_speed)
var _time: float = 0.0


func _ready() -> void:
	_noise.seed = flicker_seed
	_noise.frequency = 1.0
	_base_energy = energy
	_base_scale = texture_scale


func _process(delta: float) -> void:
	_time += delta * flicker_speed
	energy = _base_energy * (1.0 + _noise.get_noise_1d(_time) * energy_amount)
	# Segunda muestra desfasada para que tamaño y brillo no vayan juntos / Offset sample so size and brightness drift apart
	texture_scale = _base_scale * (1.0 + _noise.get_noise_1d(_time + 100.0) * scale_amount)

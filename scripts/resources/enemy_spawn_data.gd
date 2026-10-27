class_name EnemySpawnData
extends Resource

## Una entrada del pool de enemigos de un piso (D22): qué escena, cuánto cuesta del presupuesto de amenaza,
## qué tan seguido sale y en grupos de cuántos.
## One entry of a floor's enemy pool (D22): which scene, how much of the threat budget it costs, how often it
## comes up and in groups of how many.

@export var scene: PackedScene
## Coste de amenaza del grupo entero / Threat cost of the whole group
@export var threat_cost: int = 2
## Peso en el sorteo / Weight in the draw
@export var weight: float = 1.0
## Tamaño del grupo (ratas: 5-8) / Group size (rats: 5-8)
@export var group_min: int = 1
@export var group_max: int = 1
## Ataca a distancia: cuenta para el tope de un tercio del presupuesto / Ranged attacker: counts toward the one-third budget cap
@export var ranged: bool = false
## Grupos por zona como máximo; 0 = sin tope / Max groups per zone; 0 = no cap
@export var max_per_zone: int = 0

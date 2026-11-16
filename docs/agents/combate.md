# Combate, armas y habilidades (AGENTS.md §10-19, §28)

Parte del contrato de [`AGENTS.md`](../../AGENTS.md); los números de sección son los de ese documento.

---

# 10. Sistema de combate

El combate debe ser independiente del tipo de arma.

Arquitectura conceptual:

```text
Player
 │
 └── CombatController
        │
        ├── Weapon
        ├── Ability
        └── Target
```

El sistema de daño debe ser reutilizable:

```text
Attacker
   │
   ▼
Hitbox
   │
   ▼
Hurtbox
   │
   ▼
Health
   │
   ▼
Death
```

Debe funcionar tanto para:

```text
Player → Enemy
```

como:

```text
Enemy → Player
```

y:

```text
Projectile → Enemy
Explosion → Player
Trap → Player
Boss attack → Player
Spell → Enemies
```

---

# 11. Hitbox y Hurtbox

## Hitbox

Una `Hitbox` representa algo que puede causar daño.

Ejemplos:

```text
SwordHitbox
ArrowHitbox
FireballHitbox
EnemyAttackHitbox
ExplosionHitbox
```

## Hurtbox

Una `Hurtbox` representa algo que puede recibir daño.

Ejemplos:

```text
Player
└── Hurtbox

Enemy
└── Hurtbox
```

No implementar sistemas de daño completamente diferentes para cada arma.

El objetivo es que todas las fuentes de daño utilicen el mismo protocolo.

---

# 12. Health y Damage

El sistema debe permitir separar:

```text
Health
Damage
Death
Knockback
Status Effects
```

Una entidad con vida debería poder recibir información de daño de forma genérica.

Estado actual: el knockback (`KnockbackComponent`, decae en 0.2 s), los i-frames del jugador (`HealthComponent.invulnerability_seconds`, 0.35 s), el hit flash (`HitFlash`), el hit-stop (`HitStop`, congela `Engine.time_scale` 60-110 ms por golpe aceptado, sin acumularse) y el combo de 3 de la espada (`WeaponData.combo` con un `SwingData` por golpe) ya existen. Cada golpe emite `swing_phase_changed`: `PlayerAnimator` reparte los frames de la animación de ataque en las fases del `SwingData` (preparación, golpe, recuperación) y la espada lanza el smear al activar la hitbox. `HitVfx` saca chispa, sangre y manchas de piso en cada golpe aceptado.

Peso del combate (D4): durante un golpe de espada el jugador queda plantado (solo avanza `SwingData.step_distance` en el golpe activo) y la orientación se fija al empezar. La voltereta (`RollComponent`) cuesta stamina, recorre una distancia fija, da invulnerabilidad con `HealthComponent.grant_invulnerability` y no se cancela; el ataque pedido durante ella sale al terminar. Un golpe aceptado aturde al enemigo (`EnemyData.stagger_seconds`) y corta su ataque, salvo que tenga `poise_while_attacking` y ya esté comprometido; empujado o aturdido no actúa. `CameraShake` (hijo de la `Camera2D`) solo mueve el `offset` en px enteros. Muerto, el jugador no se mueve, no rueda, no ataca y la salida no cambia de piso.

El sistema podrá crecer posteriormente para soportar:

- daño físico;
- daño mágico;
- críticos;
- resistencias;
- vulnerabilidades;
- knockback;
- efectos de estado;
- daño periódico.

No implementar todas estas características hasta que sean necesarias.

---

# 13. Armas

El juego tendrá inicialmente tres familias principales:

### Melee

```text
Espada
```

### Ranged físico

```text
Arco
```

### Ranged mágico

```text
Bastón
```

Estado actual: las tres familias existen bajo el nodo `Weapons` del jugador, pero
se equipa **una sola arma a la vez**, montada por `EquipmentController`. Se arranca
con la espada; el arco y el bastón se obtienen de cofres en zonas REWARD.

```text
attack       → ataca con el arma equipada
swap_weapon  → Tab: cambia el arma equipada
```

Todas las armas comparten el mismo slot de arma equipada. Atacar siempre cuesta
stamina; no hay cooldowns de arma. Con arco o bastón moverse no impide disparar,
pero abre un desvío de puntería (`WeaponData.aim_spread_*`) que se cierra quieto.

El arma debe definir principalmente cómo produce su ataque.

No debe contener lógica específica del jugador.

---

# 14. WeaponData

Siempre que sea apropiado, utilizar un `Resource` para almacenar datos de armas.

Ejemplo conceptual:

```text
WeaponData
├── type
├── scene
├── damage
├── knockback
├── stamina_cost
├── projectile_data
└── aim_spread_*       # desvío al moverse (arco y bastón)
```

`attack_speed` y `cooldown` están deprecados: el gating es la stamina, no un
cooldown de arma.

El ataque básico del bastón todavía no define si consume maná (D19); si lo hace,
`WeaponData` suma `mana_cost`.

Ejemplos de recursos:

```text
resources/weapons/
├── sword_basic.tres
├── sword_heavy.tres
├── bow_basic.tres
└── magic_staff.tres
```

La escena/script del arma utilizará estos datos para definir su comportamiento.

---

# 15. Espada

Flujo esperado:

```text
Player
 ↓
Attack
 ↓
Sword Hitbox
 ↓
Enemy Hurtbox
 ↓
Damage
```

Características posibles:

- daño alto;
- alcance corto;
- knockback;
- combos;
- ataques cargados;
- dash ofensivo.

Estas características se implementarán progresivamente.

---

# 16. Arco

Flujo esperado:

```text
Player
 ↓
Bow
 ↓
Arrow
 ↓
Projectile
 ↓
Enemy
```

Características posibles:

- daño moderado;
- largo alcance;
- velocidad de proyectil;
- penetración;
- múltiples flechas;
- flechas especiales.

El proyectil debe ser reutilizable para otros ataques que compartan comportamiento.

---

# 17. Bastón mágico

El bastón debe poder producir proyectiles mágicos:

```text
Staff
 ↓
Magic Projectile
 ↓
Enemy
```

Pero el sistema mágico debe poder evolucionar más allá del ataque básico.

Estado actual: el bastón se ataca con `attack` como cualquier arma equipada (no
tiene una acción de input propia) y el gating es stamina.

---

# 18. Ability System

Las habilidades **pertenecen al arma equipada**, no son un sistema suelto
(reframe Albion, D12). Cada arma tiene su propio kit intercambiable:

```text
Activas        → slots 1-4
Buffs/debuff   → slots Q/E/R
```

- Varias opciones por slot; **una sola activa por slot**.
- La maestría del arma desbloquea opciones nuevas.
- Cada habilidad declara su coste: **stamina** (físico), **maná** (mágico) o **ambos a la vez** (D19).
- El coste es atómico: si falta cualquiera de los recursos declarados, la habilidad no se ejecuta.
- Los ataques físicos de arma siguen costando solo stamina.
- Sin cooldown, salvo para el slot "ultimate".

Estado actual: cada `WeaponData.abilities` trae su slot 1 (`AbilityData` en `resources/abilities/`): tajo giratorio (espada, stamina), disparo triple (arco, stamina) y bola de fuego (bastón, maná). `AbilityCaster` (nodo `Abilities` del jugador) cobra el coste de forma atómica y crea el efecto: `burst` (golpe de área con empuje radial) o `volley` (proyectiles en abanico; `arrow.gd` puede explotar con `explosion_scene`). El maná es un segundo `StaminaComponent` (nodo `Mana`, 100 de pozo, 4/s) con su barra en el HUD. Faltan los slots 2-4 y Q/E/R, las opciones por slot y la maestría.

Para el vertical slice alcanza con 1-2 activas + 1 pasiva por arma, pero la
abstracción de slot se conserva para no reescribir después.

Categorías iniciales:

```text
Damage
Crowd Control
Buff
Debuff
```

Ejemplos:

### Crowd Control

- congelar;
- ralentizar;
- empujar;
- aturdir;
- atraer enemigos.

### Buffs

- aumentar velocidad;
- aumentar daño;
- aumentar crítico;
- regeneración;
- escudo;
- reducción de coste de stamina.

---

# 19. AbilityData

Utilizar `Resource` cuando sea apropiado.

Ejemplo:

```text
AbilityData
├── name
├── slot
├── stamina_cost
├── mana_cost
├── cast_time
├── damage
├── range
└── effect
```

El coste puede ser **stamina**, **maná** o **ambos** (D19); `mana_cost = 0`
significa que la habilidad no usa maná. Los cooldowns solo aplican al
slot "ultimate". `AbilityData` describe el kit del arma equipada, no habilidades
globales sueltas.

Ejemplos:

```text
resources/abilities/
├── fireball.tres
├── ice_nova.tres
├── speed_buff.tres
└── chain_lightning.tres
```

La implementación puede evolucionar hacia tipos como:

```text
Ability
├── ProjectileAbility
├── MeleeAbility
├── AreaAbility
├── BuffAbility
└── CrowdControlAbility
```

No crear toda esta jerarquía hasta que el proyecto realmente la necesite.

---

# 28. Builds

El diseño del juego debe permitir crear builds.

Ejemplo melee:

```text
Espada
+ crítico
+ coste de stamina reducido
+ knockback
+ dash
+ sangrado
```

Ejemplo arquero:

```text
Arco
+ velocidad de proyectil
+ multishot
+ penetración
+ crítico
+ daño a distancia
```

Ejemplo mágico:

```text
Bastón
+ poder mágico
+ coste de stamina reducido
+ congelación
+ AoE
+ regeneración de stamina
+ regeneración de maná
```

Ejemplo híbrido:

```text
Espada con su kit
+
Ice Nova
+
Speed Buff
+
Fireball
```

La arquitectura de armas, habilidades y upgrades debe permitir estas combinaciones sin obligar a que cada build tenga código completamente separado.

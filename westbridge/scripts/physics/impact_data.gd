class_name ImpactData
extends RefCounted
## Describes one physical impact on a character.

enum Source { PUNCH, KICK, PUSH, OBJECT, VEHICLE, FALL, BUMP, WALL, EXPLOSION }

var position: Vector3 = Vector3.ZERO      ## world-space contact point
var direction: Vector3 = Vector3.FORWARD  ## normalized push direction
var impulse: float = 0.0                  ## N*s
var source_velocity: float = 0.0          ## m/s of the hitting object
var source_mass: float = 0.0              ## kg of the hitting object (0 = unknown)
var source: int = Source.PUSH
var instigator: Node = null
var damage: float = 0.0


static func create(pos: Vector3, dir: Vector3, p_impulse: float, p_source: int = Source.PUSH, p_instigator: Node = null) -> ImpactData:
	var d := ImpactData.new()
	d.position = pos
	d.direction = dir.normalized() if dir.length() > 0.0001 else Vector3.FORWARD
	d.impulse = p_impulse
	d.source = p_source
	d.instigator = p_instigator
	return d


## Impact from a moving object: uses reduced mass so a light fast object and a heavy
## slow one behave differently. restitution 0.2 = mostly inelastic (bodies are soft).
static func from_object(pos: Vector3, velocity: Vector3, mass: float, body_mass: float, p_source: int = Source.OBJECT, p_instigator: Node = null) -> ImpactData:
	var reduced := (mass * body_mass) / maxf(mass + body_mass, 0.001)
	var d := create(pos, velocity, reduced * velocity.length() * 1.2, p_source, p_instigator)
	d.source_velocity = velocity.length()
	d.source_mass = mass
	return d


func to_dict() -> Dictionary:
	return {"position": position, "direction": direction, "impulse": impulse, "source": source,
		"source_velocity": source_velocity, "source_mass": source_mass, "damage": damage}

class_name Seat
extends Interactable
## A place to sit (bench, chair, booth). Players and NPCs can reserve it.
## The seat's -Z is where the sitter faces (same as a body's forward).

var occupant: Node = null


func _ready() -> void:
	super._ready()
	prompt = "Sit down"
	interact_radius = 1.6
	add_to_group("seat")


func can_interact(actor: Node) -> bool:
	return enabled and (occupant == null or occupant == actor)


func get_prompt(_actor: Node) -> String:
	return "Sit down"


func interact(actor: Node) -> void:
	if occupant != null:
		return
	if actor is PlayerController:
		occupant = actor
		(actor as PlayerController).sit_on(self, sit_transform())


func reserve(who: Node) -> bool:
	if occupant != null and occupant != who:
		return false
	occupant = who
	return true


func release(who: Node) -> void:
	if occupant == who:
		occupant = null


## Body transform while seated (feet origin slightly in front of the seat).
func sit_transform() -> Transform3D:
	return Transform3D(global_basis, global_position - global_basis.z * 0.12)

class_name Interactable
extends Node3D
## Base class for anything the player (or NPCs) can use: doors, seats, vending
## machines, beds, notice boards, shop counters, NPCs...
## Registered in the "interactable" group and found by distance + facing.

@export var prompt: String = "Use"
@export var interact_radius: float = 2.0
@export var enabled: bool = true


func _ready() -> void:
	add_to_group("interactable")


func get_prompt(_actor: Node) -> String:
	return prompt


func can_interact(_actor: Node) -> bool:
	return enabled


func interact(_actor: Node) -> void:
	pass


## Point used for distance checks.
func interact_position() -> Vector3:
	return global_position

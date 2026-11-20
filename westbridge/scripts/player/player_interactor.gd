class_name PlayerInteractor
extends Node
## Finds the best interactable near the player (distance + facing) a few times per
## second and exposes a prompt for the HUD / touch "interact" button.

var player: PlayerController
var current: Node = null
var _timer: float = 0.0


func _ready() -> void:
	player = get_parent() as PlayerController


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.12
	var best: Node = null
	var best_score := -INF
	var pos := player.global_position
	var fwd := -player.global_basis.z
	for n in get_tree().get_nodes_in_group("interactable"):
		if not n.has_method("interact_position") or not n.is_inside_tree():
			continue
		if n == player or not n.can_interact(player):
			continue
		var ip: Vector3 = n.interact_position()
		var to := ip - pos
		to.y = 0.0
		var d := to.length()
		var radius: float = n.get("interact_radius") if n.get("interact_radius") != null else 2.0
		if d > radius or absf(ip.y - pos.y) > 2.5:
			continue
		var facing := fwd.dot(to.normalized()) if d > 0.05 else 1.0
		var score := -d + facing * 0.8
		if score > best_score:
			best_score = score
			best = n
	if best != current:
		current = best
	var text := ""
	if current:
		text = current.get_prompt(player)
	EventBus.interaction_prompt_changed.emit(text, current != null)


func interact() -> void:
	if current and is_instance_valid(current) and current.can_interact(player):
		current.interact(player)

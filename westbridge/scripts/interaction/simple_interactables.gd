class_name SimpleInteractable
extends Interactable
## Data-driven interactables: vending machine, bed (sleep + save), wardrobe,
## notice boards, trash bins... `action` selects the behaviour.

@export var action: String = "info"
@export var info_text: String = ""
@export var price: int = 0
var place: Place = null


func get_prompt(_actor: Node) -> String:
	match action:
		"vending":
			return "Buy soda ($%d)" % price
		"snack":
			return "Buy snack ($%d)" % price
		"bed":
			return "Sleep (save game)"
		"wardrobe":
			return "Change clothes"
		"trash":
			return "Search trash"
		"coffee":
			return "Buy coffee ($%d)" % price
		"food":
			return "Order meal ($%d)" % price
		"shop":
			return "Buy groceries ($%d)" % price
	return prompt


func interact(actor: Node) -> void:
	var player := actor as PlayerController
	match action:
		"vending", "coffee", "snack", "food", "shop":
			if place and not place.is_open(GameTime.get_hour_float()):
				EventBus.toast.emit("%s is closed" % place.name)
				return
			if Game.spend_money(price, info_text):
				if player:
					var gains := {"vending": {"energy": 8, "hunger": 4}, "coffee": {"energy": 22},
						"snack": {"hunger": 18}, "food": {"hunger": 55, "energy": 6}, "shop": {"hunger": 30}}
					player.restore_stats(gains.get(action, {}))
					player.model.animator.play_upper("drink" if action in ["vending", "coffee"] else "eat")
		"bed":
			_sleep(player)
		"wardrobe":
			if Game.current_world and Game.current_world.has_method("open_wardrobe"):
				Game.current_world.open_wardrobe()
		"trash":
			if randf() < 0.25:
				var found := randi_range(1, 6)
				Game.add_money(found, "found in the trash")
			else:
				EventBus.toast.emit("Nothing useful here...")
			if player:
				player.model.animator.play_full("pick_up")
		_:
			EventBus.toast.emit(info_text)


func _sleep(player: PlayerController) -> void:
	if player == null:
		return
	var hour := GameTime.get_hour_float()
	if hour > 7.0 and hour < 20.0 and player.stats.energy > 60.0:
		EventBus.toast.emit("You're not tired enough to sleep")
		return
	var world := Game.current_world
	if world and world.has_method("fade_sleep"):
		world.fade_sleep(func() -> void:
			var slept := GameTime.skip_to_hour(7.0)
			player.restore_stats({"energy": 100, "health": 30, "hunger": -slept / 60.0 * 2.5})
			SaveSystem.save_game(0, "Home")
			EventBus.toast.emit("Slept until 07:00 — game saved"))

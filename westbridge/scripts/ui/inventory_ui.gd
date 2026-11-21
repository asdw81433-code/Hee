class_name InventoryUI
extends Control
## The player's bag (use / drop items), money, bank, job and recent shifts.

var world: Node
var eco: Economy
var _body: VBoxContainer
var _msg: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerInput.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PANEL, 20))
	UIKit.anchor(panel, Control.PRESET_CENTER, Vector2(-500, -320), Vector2(1000, 640))
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := UIKit.label("Bag", 30, UIKit.ACCENT)
	title.custom_minimum_size = Vector2(820, 0)
	top.add_child(title)
	top.add_child(UIKit.button("Close", _close, Vector2(140, 52)))
	_msg = UIKit.label("", 21, Color(0.6, 0.95, 0.6))
	root.add_child(_msg)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(960, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	refresh()


func _close() -> void:
	PlayerInput.enabled = true
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory"):
		_close()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	var j := eco.job
	_body.add_child(UIKit.label("Cash $%d   ·   Bank $%d%s   ·   Rent $%d in %d day(s)" % [Game.get_money(), eco.bank, ("   ·   DEBT $%d" % eco.debt) if eco.debt > 0 else "", Economy.RENT, eco.days_until_rent()], 22))
	if j.is_empty():
		_body.add_child(UIKit.label("No job. Look for \"jobs\" at shop doors, or read the Westbridge Gazette.   Experience: %d shifts" % eco.experience, 20, UIKit.MUTED))
	else:
		_body.add_child(UIKit.label("Job: %s at %s  ·  $%d/h  ·  %02d:00-%02d:00 Mon-Fri  ·  shifts %d  ·  warnings %d/%d  ·  today: %s" % [eco.job_title(), j.place_name, eco.wage_now(), int(j.start), int(j.end) % 24, int(j.shifts), int(j.misses), Economy.FIRE_AFTER - 1, Economy.state_text(eco.shift_state())], 20, UIKit.MUTED))
	if not eco.history.is_empty():
		var h: Dictionary = eco.history[0]
		_body.add_child(UIKit.label("Last shift: +$%d  (%d%% performance, %.1f h)" % [int(h.pay), int(float(h.performance) * 100.0), float(h.hours)], 20, UIKit.MUTED))
	_body.add_child(UIKit.label("Items  (%d/%d slots)" % [eco.slots_used(), eco.capacity()], 24, UIKit.ACCENT))
	if eco.inventory.is_empty():
		_body.add_child(UIKit.label("Empty. Buy things at shops, cafes, the mall...", 20, UIKit.MUTED))
	for id in eco.inventory.keys():
		var it := ItemDB.get_item(id)
		var row := HBoxContainer.new()
		var l := UIKit.label("%s  x%d   %s" % [it.name, eco.count(id), _describe(it)], 21)
		l.custom_minimum_size = Vector2(620, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(l)
		var use_text: String = {"consumable": "Use", "clothing": "Wear", "gift": "Use", "tool": "Use"}.get(String(it.kind), "Use")
		row.add_child(UIKit.button(use_text, func() -> void:
			_msg.text = eco.use_item(id, world.player if world else null)
			refresh(), Vector2(150, 48)))
		row.add_child(UIKit.button("Drop", func() -> void:
			eco.remove_item(id)
			_msg.text = "Dropped %s" % it.name
			refresh(), Vector2(150, 48)))
		_body.add_child(row)


static func _describe(it: Dictionary) -> String:
	match String(it.get("kind", "")):
		"consumable":
			var fx: Array = []
			for k in (it.get("effects", {}) as Dictionary).keys():
				fx.append("%s %+d" % [k, int(it.effects[k])])
			return "(" + ", ".join(fx) + ")"
		"gift":
			return "(gift - give it while talking to someone)"
		"clothing":
			return "(wear it%s)" % (" - +%d bag slots" % int(it.capacity) if it.has("capacity") else "")
		"tool":
			return "(tool)"
		"misc":
			return "(%s)" % it.desc if it.has("desc") else ""
	return ""

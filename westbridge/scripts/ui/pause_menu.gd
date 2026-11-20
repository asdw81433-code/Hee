class_name PauseMenu
extends Control
## Pause: resume, save/load (4 slots with backups), settings, edit touch layout, quit.

var hud: HUD
var _box: VBoxContainer
var _prev_mouse: int = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIKit.theme()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	PlayerInput.clear()
	_main_page()


func close() -> void:
	visible = false
	for c in get_children():
		c.queue_free()
	get_tree().paused = false
	if _prev_mouse == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _clear() -> void:
	for c in get_children():
		c.queue_free()


func _main_page() -> void:
	_clear()
	_box = UIKit.modal(self, "Paused", 520)
	_box.add_child(UIKit.label(GameTime.get_clock_string() + "   $%d" % Game.get_money(), 22, UIKit.MUTED))
	_box.add_child(UIKit.button("Resume", close))
	_box.add_child(UIKit.button("Save game", _slots_page.bind(true)))
	_box.add_child(UIKit.button("Load game", _slots_page.bind(false)))
	_box.add_child(UIKit.button("Settings", _settings))
	_box.add_child(UIKit.button("Physics debug (F3)", func() -> void: hud.toggle_debug()))
	_box.add_child(UIKit.button("Quit to main menu", func() -> void:
		close()
		Game.return_to_menu()))


func _slots_page(saving: bool) -> void:
	_clear()
	_box = UIKit.modal(self, "Save game" if saving else "Load game", 620)
	for i in SaveSystem.MAX_SLOTS:
		var info := SaveSystem.slot_info(i)
		var text := "Slot %d   " % (i + 1)
		text += ("%s  (%s)" % [info.get("game_clock", ""), String(info.get("timestamp", "")).replace("T", " ")]) if not info.is_empty() else "— empty —"
		var b := UIKit.button(text, _slot_chosen.bind(i, saving), Vector2(560, 56))
		if not saving and info.is_empty():
			b.disabled = true
		_box.add_child(b)
	_box.add_child(UIKit.button("Back", _main_page))


func _slot_chosen(slot: int, saving: bool) -> void:
	if saving:
		SaveSystem.save_game(slot, "Slot %d" % (slot + 1))
		_main_page()
	else:
		close()
		Game.continue_game(slot)


func _settings() -> void:
	_clear()
	var s := SettingsMenu.new()
	add_child(s)
	s.closed.connect(_main_page)
	s.edit_controls_requested.connect(_edit_controls)


func _edit_controls() -> void:
	_clear()
	visible = false
	get_tree().paused = false
	GameTime.running = false
	hud.touch.visible = true
	hud.touch.set_editing(true)
	var done := UIKit.button("Done editing", func() -> void:
		hud.touch.set_editing(false)
		hud.touch.visible = Settings.touch_controls_enabled()
		GameTime.running = true, Vector2(260, 56))
	UIKit.anchor(done, Control.PRESET_CENTER_TOP, Vector2(-130, 90), Vector2(260, 56))
	done.theme = UIKit.theme()
	hud.root.add_child(done)
	done.pressed.connect(done.queue_free)

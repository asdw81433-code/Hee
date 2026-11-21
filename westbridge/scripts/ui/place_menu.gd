class_name PlaceMenu
extends Control
## What you can do at a place: buy, sell, ask for work / clock in, bank, rent a room.

var world: Node
var place: Place
var eco: Economy
var _body: VBoxContainer
var _header: Label
var _msg: Label
var _tab: String = ""


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
	UIKit.anchor(panel, Control.PRESET_CENTER, Vector2(-520, -320), Vector2(1040, 640))
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	_header = UIKit.label("", 28, UIKit.ACCENT)
	root.add_child(_header)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	if not ItemDB.catalog_for(place).is_empty():
		tabs.add_child(UIKit.button("Shop", func() -> void: _show("shop"), Vector2(140, 52)))
	if ItemDB.BUYS.has(place.type):
		tabs.add_child(UIKit.button("Sell", func() -> void: _show("sell"), Vector2(120, 52)))
	if not place.jobs.is_empty():
		tabs.add_child(UIKit.button("Work", func() -> void: _show("jobs"), Vector2(130, 52)))
	if Economy.has_bank(place):
		tabs.add_child(UIKit.button("Bank" if place.type == "bank" else "ATM", func() -> void: _show("bank"), Vector2(120, 52)))
	if place.type == "hotel":
		tabs.add_child(UIKit.button("Room", func() -> void: _show("room"), Vector2(120, 52)))
	tabs.add_child(UIKit.button("Bag", func() -> void: _show("bag"), Vector2(110, 52)))
	tabs.add_child(UIKit.button("Close", _close, Vector2(120, 52)))
	_msg = UIKit.label("", 21, Color(0.6, 0.95, 0.6))
	root.add_child(_msg)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1000, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	var first := "jobs" if (not eco.job.is_empty() and int(eco.job.place) == place.id) else ("shop" if not ItemDB.catalog_for(place).is_empty() else ("jobs" if not place.jobs.is_empty() else ("bank" if Economy.has_bank(place) else "room")))
	_show(first)


func _close() -> void:
	PlayerInput.enabled = true
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		_close()
		get_viewport().set_input_as_handled()


func _refresh_header() -> void:
	var open := place.is_open(GameTime.get_hour_float())
	var hours := "open 24h" if place.open_hour <= 0.0 and place.close_hour >= 24.0 else "%02d:00-%02d:00" % [int(place.open_hour), int(place.close_hour) % 24]
	_header.text = "%s  ·  %s  ·  %s%s      Cash $%d  ·  Bank $%d" % [place.name, place.district, hours, "" if open else " (CLOSED)", Game.get_money(), eco.bank]


func _say(t: String, ok: bool = true) -> void:
	_msg.text = t
	_msg.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6) if ok else Color(1.0, 0.55, 0.45))


func _row(text: String, btn_text: String, cb: Callable, enabled: bool = true, extra: Array = []) -> void:
	var row := HBoxContainer.new()
	var l := UIKit.label(text, 21)
	l.custom_minimum_size = Vector2(760 - 170 * extra.size(), 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	row.add_child(l)
	for e in extra:                      # [text, callable]
		row.add_child(UIKit.button(e[0], e[1], Vector2(160, 48)))
	if btn_text != "":
		var b := UIKit.button(btn_text, cb, Vector2(200, 48))
		b.disabled = not enabled
		row.add_child(b)
	_body.add_child(row)


func _show(tab: String) -> void:
	_tab = tab
	_refresh_header()
	for c in _body.get_children():
		c.queue_free()
	match tab:
		"shop":
			for id in ItemDB.catalog_for(place):
				var it := ItemDB.get_item(id)
				var fx := ""
				for k in (it.get("effects", {}) as Dictionary).keys():
					fx += " %s%+d" % [k, int(it.effects[k])]
				if fx == "":
					fx = InventoryUI._describe(it).trim_prefix("(").trim_suffix(")")
				var have := eco.count(id)
				var extra: Array = []
				if String(it.kind) == "consumable":
					extra.append(["Have now", func() -> void:
						var err2 := eco.buy(id, place)
						_say((eco.use_item(id, world.player) if err2 == "" else err2), err2 == "")
						_show("shop")])
				_row("%s  -  $%d%s%s" % [it.name, ItemDB.price_at(id, place), ("   (" + fx.strip_edges() + ")") if fx != "" else "", "   [have %d]" % have if have > 0 else ""],
					"Buy", func() -> void:
						var err := eco.buy(id, place)
						_say("Bought %s" % it.name if err == "" else err, err == "")
						_show("shop"), true, extra)
		"sell":
			var any := false
			for id in eco.inventory.keys():
				if ItemDB.buys(place, id):
					any = true
					_row("%s x%d  -  they pay $%d" % [ItemDB.item_name(id), eco.count(id), ItemDB.sell_price(id)], "Sell one", func() -> void:
						var err := eco.sell(id, place)
						_say("Sold" if err == "" else err, err == "")
						_show("sell"))
			if not any:
				_row("You have nothing they want to buy.", "", Callable())
		"jobs":
			if not eco.job.is_empty() and int(eco.job.place) == place.id:
				var st := eco.shift_state()
				_row("You work here as %s  ·  $%d/h  ·  %02d:00-%02d:00 Mon-Fri  ·  shifts %d  ·  warnings %d/%d" % [eco.job_title(), eco.wage_now(), int(eco.job.start), int(eco.job.end) % 24, int(eco.job.shifts), int(eco.job.misses), Economy.FIRE_AFTER - 1],
					"Start shift" if st == "open" else st.capitalize(), func() -> void:
						var err := eco.start_shift(place)
						if err == "":
							_close()
							world.begin_work(place)
						else:
							_say(err, false), st == "open")
				_row("Not happy here?", "Quit job", func() -> void:
					eco.quit_job()
					_show("jobs"))
			var opens := eco.openings(place)
			for jd in place.jobs:
				var free := opens.any(func(o: Dictionary) -> bool: return o.title == jd.title)
				var need := Economy.required_experience(int(jd.wage))
				var mine: bool = not eco.job.is_empty() and int(eco.job.place) == place.id and eco.job.title == jd.title
				if mine:
					continue
				var info := "%s  -  $%d/h  ·  %02d:00-%02d:00  ·  %s%s" % [jd.title, int(jd.wage), int(jd.start), int(jd.end) % 24,
					"hiring" if free else "no opening", ("  ·  needs %d shifts experience (you: %d)" % [need, eco.experience]) if need > 0 else ""]
				_row(info, "Apply", func() -> void:
					var err := eco.apply(place, jd)
					_say("Hired! You start as %s. Your shift: %02d:00-%02d:00 on weekdays." % [jd.title, int(jd.start), int(jd.end) % 24] if err == "" else err, err == "")
					_show("jobs"), free)
		"bank":
			_row("Account balance: $%d   ·   Cash: $%d   ·   Rent $%d due in %d day(s)%s" % [eco.bank, Game.get_money(), Economy.RENT, eco.days_until_rent(), ("   ·   DEBT $%d" % eco.debt) if eco.debt > 0 else ""], "", Callable())
			for amt in [20, 100]:
				_row("Deposit $%d" % amt, "Deposit", func() -> void:
					var err := eco.deposit(amt)
					_say("Deposited" if err == "" else err, err == "")
					_show("bank"))
			_row("Deposit all cash", "Deposit all", func() -> void:
				var err := eco.deposit(Game.get_money())
				_say("Deposited" if err == "" else err, err == "")
				_show("bank"))
			for amt2 in [20, 100]:
				_row("Withdraw $%d" % amt2, "Withdraw", func() -> void:
					var err := eco.withdraw(amt2)
					_say("Withdrew $%d" % amt2 if err == "" else err, err == "")
					_show("bank"))
		"room":
			var price := 40 * (1 + place.price_level)
			_row("A room for the night: sleep until 07:00, full energy, game saved  ($%d)" % price, "Rent room", func() -> void:
				if not Game.spend_money(price, "hotel room"):
					_say("Not enough cash", false)
					return
				_close()
				world.fade_sleep(func() -> void:
					var slept := GameTime.skip_to_hour(7.0)
					world.player.restore_stats({"energy": 100, "health": 30, "hunger": -slept / 60.0 * 2.0})
					SaveSystem.save_game(0, place.name)
					EventBus.toast.emit("Slept at %s - game saved" % place.name)))
		"bag":
			_row("Bag: %d/%d slots" % [eco.slots_used(), eco.capacity()], "", Callable())
			for id in eco.inventory.keys():
				_row("%s x%d" % [ItemDB.item_name(id), eco.count(id)], "Use", func() -> void:
					_say(eco.use_item(id, world.player))
					_show("bag"))

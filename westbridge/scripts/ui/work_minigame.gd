class_name WorkMinigame
extends Control
## A work shift you actually play (6 tasks), three styles chosen by the job:
##   orders - serve what the customer asked for (barista, cashier, waiter...)
##   timing - stop the moving marker in the green zone (lifting, welding, driving...)
##   typing - pick the record that exactly matches (office, bank, hospital, police...)
## Performance + speed decide pay and tips; then the shift's remaining hours pass.

signal done(performance: float, tips: int)

const ROUNDS := 6
var mode: String = "orders"
var place: Place
var job_title: String = ""
var _round: int = 0
var _score: float = 0.0
var _tips: int = 0
var _t: float = 0.0
var _limit: float = 12.0
var _body: VBoxContainer
var _title: Label
var _status: Label
var _answer: Variant
var _tray: Array = []
var _bar: Control
var _marker: float = 0.0
var _speed: float = 0.9
var _zone: Vector2 = Vector2(0.4, 0.6)
var _rng := RandomNumberGenerator.new()
var auto_play: float = -1.0      ## tests: probability of a correct answer, played automatically


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerInput.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rng.randomize()
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PANEL, 20))
	UIKit.anchor(panel, Control.PRESET_CENTER, Vector2(-500, -290), Vector2(1000, 580))
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	_title = UIKit.label("", 28, UIKit.ACCENT)
	root.add_child(_title)
	_status = UIKit.label("", 21, UIKit.MUTED)
	root.add_child(_status)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	root.add_child(_body)
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	bottom.add_child(UIKit.button("Leave early", func() -> void: _finish(), Vector2(200, 52)))
	_next()


func _process(delta: float) -> void:
	if _round >= ROUNDS:
		return
	_t += delta
	if mode == "timing":
		_marker += _speed * delta
		if _marker > 1.0 or _marker < 0.0:
			_speed = -_speed
			_marker = clampf(_marker, 0.0, 1.0)
		if _bar:
			_bar.queue_redraw()
	_status.text = "Task %d/%d  ·  score %d%%  ·  tips $%d  ·  %.0fs" % [_round + 1, ROUNDS, int(100.0 * _score / maxf(_round, 1)), _tips, maxf(0.0, _limit - _t)]
	if auto_play >= 0.0 and _t > 0.15:
		_answer_round(_rng.randf() < auto_play)
	elif _t > _limit:
		_answer_round(false)


func _next() -> void:
	for c in _body.get_children():
		c.queue_free()
	_bar = null
	_t = 0.0
	_tray = []
	if _round >= ROUNDS:
		_summary()
		return
	_title.text = "%s at %s" % [job_title, place.name if place else "work"]
	match mode:
		"orders":
			_limit = 14.0
			var menu: Array = ItemDB.catalog_for(place).slice(0, 6)
			if menu.size() < 4:
				menu = ["coffee", "sandwich", "soda", "burger", "salad", "water"]
			var order: Array = []
			for k in _rng.randi_range(1, 3):
				order.append(menu[_rng.randi() % menu.size()])
			_answer = order
			_body.add_child(UIKit.label('Customer: "%s, please."' % ", ".join(order.map(func(i: String) -> String: return ItemDB.item_name(i))), 26))
			var tray_l := UIKit.label("Tray: (empty)", 22, UIKit.MUTED)
			_body.add_child(tray_l)
			var grid := GridContainer.new()
			grid.columns = 3
			_body.add_child(grid)
			for id in menu:
				grid.add_child(UIKit.button(ItemDB.item_name(id), func() -> void:
					_tray.append(id)
					tray_l.text = "Tray: " + ", ".join(_tray.map(func(i: String) -> String: return ItemDB.item_name(i))), Vector2(300, 56)))
			var row := HBoxContainer.new()
			_body.add_child(row)
			row.add_child(UIKit.button("Serve", func() -> void: _answer_round(_same(_tray, order)), Vector2(220, 56)))
			row.add_child(UIKit.button("Clear tray", func() -> void:
				_tray = []
				tray_l.text = "Tray: (empty)", Vector2(220, 56)))
		"timing":
			_limit = 7.0
			_speed = (0.7 + _round * 0.12) * (1.0 if _rng.randf() < 0.5 else -1.0)
			_marker = _rng.randf()
			var w := 0.24 - _round * 0.025
			var c := _rng.randf_range(0.2, 0.8)
			_zone = Vector2(c - w * 0.5, c + w * 0.5)
			_body.add_child(UIKit.label(["Lift the crate!", "Line up the load!", "Weld the seam!", "Hit the mark!", "Steady...", "Last one!"][_round], 26))
			_bar = Control.new()
			_bar.custom_minimum_size = Vector2(940, 70)
			_bar.draw.connect(func() -> void:
				var sz := _bar.size
				_bar.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.2, 0.22, 0.25))
				_bar.draw_rect(Rect2(Vector2(sz.x * _zone.x, 0), Vector2(sz.x * (_zone.y - _zone.x), sz.y)), Color(0.3, 0.75, 0.35))
				_bar.draw_rect(Rect2(Vector2(sz.x * _marker - 4, -6), Vector2(8, sz.y + 12)), Color(1, 0.85, 0.2)))
			_body.add_child(_bar)
			_body.add_child(UIKit.button("NOW!", func() -> void: _answer_round(_marker >= _zone.x and _marker <= _zone.y), Vector2(300, 70)))
		_:
			_limit = 10.0
			var code := "%s-%04d  ·  $%d.%02d" % [["INV", "PAT", "ACC", "CASE", "REF"][_rng.randi() % 5], _rng.randi_range(1000, 9999), _rng.randi_range(5, 900), _rng.randi_range(0, 99)]
			_answer = code
			_body.add_child(UIKit.label("Find this record:", 22, UIKit.MUTED))
			_body.add_child(UIKit.label(code, 32))
			var opts: Array = [code]
			while opts.size() < 4:
				var v := _mutate(code)
				if not (v in opts):
					opts.append(v)
			opts.shuffle()
			var grid2 := GridContainer.new()
			grid2.columns = 2
			_body.add_child(grid2)
			for o in opts:
				grid2.add_child(UIKit.button(o, func() -> void: _answer_round(o == code), Vector2(460, 60)))


func _mutate(code: String) -> String:
	var chars := code.split("")
	var digits: Array = []
	for k in chars.size():
		if chars[k] >= "0" and chars[k] <= "9":
			digits.append(k)
	var k2: int = digits[_rng.randi() % digits.size()]
	chars[k2] = str((int(chars[k2]) + _rng.randi_range(1, 8)) % 10)
	return "".join(chars)


static func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var x := a.duplicate()
	var y := b.duplicate()
	x.sort()
	y.sort()
	return x == y


func _answer_round(ok: bool) -> void:
	if _round >= ROUNDS:
		return
	if ok:
		_score += 1.0
		if _t < _limit * 0.5:
			_tips += _rng.randi_range(1, 3) if mode == "orders" else 0
	_round += 1
	_next()


func _summary() -> void:
	_title.text = "Shift complete"
	var perf := _score / ROUNDS
	_body.add_child(UIKit.label("Tasks done right: %d/%d   ·   tips: $%d" % [int(_score), ROUNDS, _tips], 26))
	_body.add_child(UIKit.label("The rest of your shift passes...", 22, UIKit.MUTED))
	_body.add_child(UIKit.button("Collect pay", func() -> void: _finish(), Vector2(260, 60)))
	if auto_play >= 0.0:
		_finish()


func _finish() -> void:
	var perf := _score / ROUNDS
	PlayerInput.enabled = true
	done.emit(perf, _tips)
	queue_free()

class_name UIKit
extends RefCounted
## Theme + widget helpers so every menu is built consistently in code
## (large touch-friendly controls, readable on phones).

const BG := Color(0.07, 0.09, 0.12, 0.88)
const PANEL := Color(0.12, 0.15, 0.19, 0.94)
const ACCENT := Color(0.98, 0.72, 0.28)
const TEXT := Color(0.95, 0.95, 0.93)
const MUTED := Color(0.68, 0.71, 0.75)

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.1, 0.1))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_stylebox("normal", "Button", _box(Color(0.2, 0.24, 0.3), 14))
	t.set_stylebox("hover", "Button", _box(Color(0.26, 0.31, 0.38), 14))
	t.set_stylebox("pressed", "Button", _box(ACCENT, 14))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), 14, ACCENT))
	t.set_stylebox("disabled", "Button", _box(Color(0.16, 0.17, 0.2), 14))
	t.set_stylebox("panel", "Panel", _box(PANEL, 18))
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 18))
	t.set_stylebox("slider", "HSlider", _box(Color(0.25, 0.28, 0.33), 6))
	t.set_stylebox("grabber_area", "HSlider", _box(ACCENT.darkened(0.2), 6))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, 6))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_stylebox("normal", "LineEdit", _box(Color(0.18, 0.2, 0.25), 10))
	t.set_stylebox("normal", "OptionButton", _box(Color(0.2, 0.24, 0.3), 12))
	t.set_stylebox("hover", "OptionButton", _box(Color(0.26, 0.31, 0.38), 12))
	t.set_stylebox("pressed", "OptionButton", _box(Color(0.26, 0.31, 0.38), 12))
	t.set_stylebox("panel", "TabContainer", _box(PANEL, 12))
	t.set_stylebox("tab_selected", "TabContainer", _box(ACCENT.darkened(0.1), 10))
	t.set_stylebox("tab_unselected", "TabContainer", _box(Color(0.18, 0.2, 0.25), 10))
	t.set_color("font_selected_color", "TabContainer", Color(0.08, 0.08, 0.08))
	t.set_stylebox("panel", "PopupMenu", _box(PANEL, 10))
	_theme = t
	return t


static func _box(c: Color, radius: int, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(2)
	return s


static func panel_style(c: Color = PANEL, radius: int = 18) -> StyleBoxFlat:
	return _box(c, radius)


static func button(text: String, cb: Callable, min_size: Vector2 = Vector2(220, 58)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.pressed.connect(cb)
	return b


static func label(text: String, size: int = 22, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func slider_row(title: String, min_v: float, max_v: float, step: float, value: float, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(title, 20)
	l.custom_minimum_size = Vector2(250, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(300, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := label(str(snappedf(value, step)), 20, MUTED)
	val.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(v: float) -> void:
		val.text = str(snappedf(v, step))
		cb.call(v))
	row.add_child(s)
	row.add_child(val)
	return row


static func option_row(title: String, options: Array, selected: int, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(title, 20)
	l.custom_minimum_size = Vector2(250, 0)
	row.add_child(l)
	var prev := button("<", Callable(), Vector2(56, 50))
	var val := label(str(options[clampi(selected, 0, options.size() - 1)]), 20)
	val.custom_minimum_size = Vector2(220, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var next := button(">", Callable(), Vector2(56, 50))
	var state := {"i": clampi(selected, 0, options.size() - 1)}
	var update := func(d: int) -> void:
		state.i = wrapi(state.i + d, 0, options.size())
		val.text = str(options[state.i])
		cb.call(state.i)
	prev.pressed.connect(update.bind(-1))
	next.pressed.connect(update.bind(1))
	row.add_child(prev)
	row.add_child(val)
	row.add_child(next)
	return row


static func check_row(title: String, value: bool, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(title, 20)
	l.custom_minimum_size = Vector2(250, 0)
	row.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(cb)
	row.add_child(c)
	return row


static func color_row(title: String, palette: Array, current: Color, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := label(title, 20)
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in palette:
		var b := Button.new()
		b.custom_minimum_size = Vector2(42, 42)
		b.add_theme_stylebox_override("normal", _box(c, 21, Color.WHITE if c.is_equal_approx(current) else Color(0, 0, 0, 0)))
		b.add_theme_stylebox_override("hover", _box(c.lightened(0.15), 21))
		b.add_theme_stylebox_override("pressed", _box(c, 21, ACCENT))
		b.pressed.connect(cb.bind(c))
		flow.add_child(b)
	row.add_child(flow)
	return row


## Full-screen dim layer with a centred panel; returns the VBox to fill.
static func modal(parent: Node, title: String, width: float = 760.0) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var t := label(title, 34, ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.set_meta("root", dim)
	return vb

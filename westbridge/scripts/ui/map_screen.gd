class_name MapScreen
extends Control
## Full-screen world map (M key / MAP button): districts, roads, Route 9, the river,
## the sea, landmarks, the player arrow and a waypoint. Drag to pan, wheel / pinch
## or the +/- buttons to zoom, tap a place to read its name, long-press or the
## "Set waypoint" button to mark it. The HUD shows distance + direction to it.

signal waypoint_changed(pos: Variant)

const ICONS := {
	"work": Color(0.35, 0.6, 1.0), "food": Color(1.0, 0.6, 0.25), "leisure": Color(0.8, 0.45, 1.0),
	"services": Color(1.0, 0.35, 0.35), "shop": Color(1.0, 0.85, 0.3), "outdoor": Color(0.45, 0.9, 0.45),
	"nightlife": Color(1.0, 0.35, 0.8), "transit": Color(0.9, 0.9, 0.95),
}

var world: GameWorld
var waypoint: Variant = null          ## Vector3 or null
var _zoom: float = 1.0                ## pixels per metre
var _center: Vector2 = Vector2.ZERO   ## world XZ at the screen centre
var _drag_from: Vector2
var _dragging: bool = false
var _selected: Place
var _info: Label
var _touches: Dictionary = {}
var _pinch_d: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	theme = UIKit.theme()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	UIKit.anchor(top, Control.PRESET_TOP_RIGHT, Vector2(-640, 14), Vector2(620, 60))
	add_child(top)
	top.add_child(UIKit.button("+", func() -> void: _zoom_by(1.35), Vector2(60, 56)))
	top.add_child(UIKit.button("-", func() -> void: _zoom_by(1.0 / 1.35), Vector2(60, 56)))
	top.add_child(UIKit.button("Me", func() -> void: _focus_player(), Vector2(80, 56)))
	top.add_child(UIKit.button("Clear pin", func() -> void: set_waypoint(null), Vector2(150, 56)))
	top.add_child(UIKit.button("Close", func() -> void: close(), Vector2(130, 56)))
	_info = UIKit.label("Tap a place for details. Long-press or 'Set waypoint' to mark it.", 22)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	UIKit.anchor(_info, Control.PRESET_BOTTOM_LEFT, Vector2(20, -120), Vector2(900, 90))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_info)
	var setb := UIKit.button("Set waypoint", func() -> void:
		if _selected:
			set_waypoint(_selected.entry_pos), Vector2(220, 56))
	UIKit.anchor(setb, Control.PRESET_BOTTOM_RIGHT, Vector2(-240, -80), Vector2(220, 56))
	add_child(setb)


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_focus_player()
	queue_redraw()


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func set_waypoint(p: Variant) -> void:
	waypoint = p
	waypoint_changed.emit(p)
	if p != null:
		EventBus.toast.emit("Waypoint set")
	queue_redraw()


func _focus_player() -> void:
	var r := CityMap.world_rect()
	_zoom = minf(size.x / r.size.x, size.y / r.size.y) * 1.6 if size.x > 0 else 1.0
	if world and world.player:
		_center = Vector2(world.player.global_position.x, world.player.global_position.z)
	queue_redraw()


func _zoom_by(f: float) -> void:
	_zoom = clampf(_zoom * f, 0.25, 8.0)
	queue_redraw()


func w2s(p: Vector2) -> Vector2:
	return size * 0.5 + (p - _center) * _zoom


func s2w(p: Vector2) -> Vector2:
	return _center + (p - size * 0.5) / _zoom


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by(1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by(1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_from = mb.position
				_dragging = false
			elif not _dragging:
				_select_at(mb.position, mb.double_click)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var wp := s2w(mb.position)
			set_waypoint(Vector3(wp.x, CityMap.ground_y(wp.x, wp.y), wp.y))
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		if (event.position - _drag_from).length() > 6.0:
			_dragging = true
		_center -= event.relative / _zoom
		queue_redraw()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_d = 0.0
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var d := (pts[0] as Vector2).distance_to(pts[1])
			if _pinch_d > 0.0:
				_zoom_by(d / _pinch_d)
			_pinch_d = d
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_M, KEY_ESCAPE]:
		close()
		accept_event()


func _select_at(sp: Vector2, mark: bool) -> void:
	if world == null:
		return
	var best: Place = null
	var best_d := 22.0
	for p in world.city.places:
		if (p as Place).type in ["home", "apartment"]:
			continue
		var d := w2s(Vector2(p.entry_pos.x, p.entry_pos.z)).distance_to(sp)
		if d < best_d:
			best_d = d
			best = p
	_selected = best
	if best:
		var hours := "open 24h" if best.open_hour <= 0.0 and best.close_hour >= 24.0 else "%02d:00-%02d:00" % [int(best.open_hour), int(best.close_hour) % 24]
		var jobs := ""
		if not best.jobs.is_empty():
			jobs = "  |  jobs: " + ", ".join(best.jobs.map(func(j: Dictionary) -> String: return "%s ($%d/h)" % [j.title, j.wage]))
		_info.text = "%s  -  %s  (%s)%s" % [best.name, best.district, hours, jobs]
		if mark:
			set_waypoint(best.entry_pos)
	else:
		var wp := s2w(sp)
		_info.text = "%s  -  %s" % [CityMap.district_at(Vector3(wp.x, 0, wp.y)), CityMap.cell_type(CityMap.cell_of(Vector3(wp.x, 0, wp.y)).x, CityMap.cell_of(Vector3(wp.x, 0, wp.y)).y).capitalize()]
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.33, 0.46))
	var half := CityMap.PITCH * 0.5
	# cells
	for key in CityMap.all_cells():
		var cc := CityMap.block_center(key.x, key.y)
		var r := Rect2(w2s(Vector2(cc.x - half, cc.z - half)), Vector2.ONE * CityMap.PITCH * _zoom)
		var kind := CityMap.cell_kind(key.x, key.y)
		var col: Color
		match kind:
			"water":
				col = Color(0.22, 0.45, 0.62)
			"block":
				col = (CityMap.DISTRICT_COLORS.get(CityMap.cell_district(key.x, key.y), Color(0.6, 0.6, 0.6)) as Color).lerp(Color(0.85, 0.84, 0.8), 0.35)
			"beach":
				col = Color(0.9, 0.83, 0.6)
			_:
				col = (WorldTerrain.ground_style(CityMap.cell_type(key.x, key.y))[0] as Color).lightened(0.15)
		draw_rect(r, col)
	# roads
	for a in range(CityMap.GI_MIN, CityMap.GI_MAX + 2):
		for b in range(CityMap.GJ_MIN, CityMap.GJ_MAX + 2):
			for axis in ["v", "h"]:
				var kind2: String = CityMap.vedge(a, b) if axis == "v" else CityMap.hedge(a, b)
				if kind2 == "":
					continue
				var p0 := CityMap.intersection(a, b)
				var p1 := CityMap.intersection(a, b + 1) if axis == "v" else CityMap.intersection(a + 1, b)
				var rc := Color(0.55, 0.45, 0.33) if kind2 == "dirt" else Color(0.97, 0.97, 0.95)
				draw_line(w2s(Vector2(p0.x, p0.z)), w2s(Vector2(p1.x, p1.z)), rc, maxf(1.5, CityMap.road_width(kind2) * _zoom * 0.8))
	var r0 := CityMap.world_rect()
	draw_line(w2s(Vector2(r0.position.x, CityMap.HIGHWAY_Z)), w2s(Vector2(r0.end.x, CityMap.HIGHWAY_Z)), Color(0.98, 0.78, 0.25), maxf(3.0, CityMap.HIGHWAY_W * _zoom * 0.8))
	# district names
	var font := get_theme_default_font()
	var seen := {}
	for key in CityMap.all_cells():
		var dn := CityMap.cell_district(key.x, key.y)
		if seen.has(dn) or CityMap.cell_kind(key.x, key.y) in ["water", "corridor"]:
			continue
		seen[dn] = true
		var cells: Array = CityMap.all_cells().filter(func(k: Vector2i) -> bool: return CityMap.cell_district(k.x, k.y) == dn and CityMap.cell_kind(k.x, k.y) not in ["water", "corridor"])
		var avg := Vector2.ZERO
		for k in cells:
			var cp := CityMap.block_center(k.x, k.y)
			avg += Vector2(cp.x, cp.z)
		avg /= cells.size()
		draw_string_outline(font, w2s(avg) + Vector2(-130, 0), dn.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 260, 16, 5, Color(0, 0, 0, 0.8))
		draw_string(font, w2s(avg) + Vector2(-130, 0), dn.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 260, 16, Color(1, 1, 1))
	# places
	if world:
		for p in world.city.places:
			var pl := p as Place
			if pl.type in ["home", "apartment"]:
				continue
			var col2 := Color(0.85, 0.85, 0.85)
			for tg in ["services", "transit", "nightlife", "food", "shop", "leisure", "outdoor", "work"]:
				if tg in pl.tags:
					col2 = ICONS[tg]
					break
			var sp := w2s(Vector2(pl.entry_pos.x, pl.entry_pos.z))
			draw_circle(sp, 4.5 if pl != _selected else 8.0, Color(0, 0, 0, 0.6))
			draw_circle(sp, 3.2 if pl != _selected else 6.5, col2)
		if world.player_home():
			var hp := world.player_home().entry_pos
			_draw_house(w2s(Vector2(hp.x, hp.z)))
		# player arrow
		var pp := world.player.global_position
		var fwd := -world.player.global_basis.z
		var sp2 := w2s(Vector2(pp.x, pp.z))
		var dir := Vector2(fwd.x, fwd.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([sp2 + dir * 13, sp2 - dir * 8 + side * 8, sp2 - dir * 4, sp2 - dir * 8 - side * 8]), Color(1, 0.25, 0.2))
	if waypoint != null:
		var wp := w2s(Vector2((waypoint as Vector3).x, (waypoint as Vector3).z))
		draw_circle(wp, 9.0, Color(0, 0, 0, 0.7))
		draw_circle(wp, 6.5, Color(1, 0.85, 0.1))
	# legend
	var y := 90.0
	for k in ["work", "food", "shop", "leisure", "nightlife", "outdoor", "services", "transit"]:
		draw_circle(Vector2(30, y), 6.0, ICONS[k])
		draw_string(font, Vector2(44, y + 6), k.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1))
		y += 26.0


func _draw_house(p: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(-8, 0), p + Vector2(0, -9), p + Vector2(8, 0), p + Vector2(8, 8), p + Vector2(-8, 8)]), Color(0.2, 1.0, 0.5))

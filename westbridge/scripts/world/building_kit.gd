class_name BuildingKit
extends RefCounted
## Procedural buildings. Every function builds in a local frame where the building
## front (street side) faces local +Z and the ground is y = 0, then `xf` places it.
## Returns the world position of the main entrance (outside the door).

const K := GeoBatch.Kind
const FLOOR_H := 3.1


static func _win(b: GeoBatch, xf: Transform3D, local: Vector3, size: Vector2, frame: Color, rnd: float, normal_axis: String = "+z") -> void:
	# Glass pane + frame on a facade. normal_axis tells which face the window is on.
	var basis := Basis.IDENTITY
	match normal_axis:
		"-z":
			basis = Basis(Vector3.UP, PI)
		"+x":
			basis = Basis(Vector3.UP, PI * 0.5)
		"-x":
			basis = Basis(Vector3.UP, -PI * 0.5)
	var wx := xf * Transform3D(basis, local)
	b.box(wx * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.02)), Vector3(size.x, size.y, 0.06), Color(0.32, 0.42, 0.5), K.GLASS, rnd, ["bottom", "-z"])
	b.box(wx * Transform3D(Basis.IDENTITY, Vector3(0, -size.y * 0.5 - 0.05, 0.06)), Vector3(size.x + 0.2, 0.08, 0.14), frame, K.PAINT, 0.0, ["-z"])
	b.box(wx * Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5 + 0.04, 0.04)), Vector3(size.x + 0.12, 0.08, 0.1), frame, K.PAINT, 0.0, ["-z"])
	for sx in [-1.0, 1.0]:
		b.box(wx * Transform3D(Basis.IDENTITY, Vector3(sx * (size.x * 0.5 + 0.03), 0, 0.04)), Vector3(0.07, size.y, 0.1), frame, K.PAINT, 0.0, ["-z", "top", "bottom"])


static func _door(b: GeoBatch, xf: Transform3D, local: Vector3, color: Color, frame: Color, width: float = 1.05) -> void:
	var dx := xf * Transform3D(Basis.IDENTITY, local)
	b.box(dx * Transform3D(Basis.IDENTITY, Vector3(0, 1.05, 0.03)), Vector3(width, 2.1, 0.08), color, K.WOOD)
	b.box(dx * Transform3D(Basis.IDENTITY, Vector3(0, 2.18, 0.05)), Vector3(width + 0.25, 0.14, 0.12), frame, K.PAINT)
	for sx in [-1.0, 1.0]:
		b.box(dx * Transform3D(Basis.IDENTITY, Vector3(sx * (width * 0.5 + 0.06), 1.05, 0.05)), Vector3(0.12, 2.1, 0.12), frame, K.PAINT)
	b.sphere((dx * Transform3D(Basis.IDENTITY, Vector3(width * 0.32, 1.0, 0.1))).origin, Vector3(0.04, 0.04, 0.04), Color(0.8, 0.7, 0.35), K.METAL, 6)


# --------------------------------------------------------------------- house
static func house(b: GeoBatch, cols: ColliderSet, xf: Transform3D, w: float, d: float, floors: int, wall: Color, roof: Color, trim: Color, rng: RandomNumberGenerator) -> Vector3:
	var base_h := 0.45
	var h := floors * 2.9
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, base_h * 0.5, 0)), Vector3(w + 0.2, base_h, d + 0.2), Color(0.55, 0.53, 0.5), K.CONCRETE)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, base_h + h * 0.5, 0)), Vector3(w, h, d), wall, K.WOOD, rng.randf())
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, (base_h + h) * 0.5, 0)), Vector3(w + 0.2, base_h + h, d + 0.2))
	# corner trims
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx * (w * 0.5 + 0.02), base_h + h * 0.5, sz * (d * 0.5 + 0.02))), Vector3(0.16, h, 0.16), trim, K.PAINT)
	# roof
	var rise := 1.8 + w * 0.08
	b.gable_roof(xf * Transform3D(Basis.IDENTITY, Vector3(0, base_h + h, 0)), Vector3(w + 0.8, 0, d + 0.9), rise, roof, wall)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, base_h + h - 0.05, 0)), Vector3(w + 0.85, 0.12, d + 0.95), trim, K.PAINT)
	if rng.randf() < 0.6:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(w * 0.3, base_h + h + rise * 0.7, -d * 0.2)), Vector3(0.6, 1.6, 0.6), Color(0.5, 0.3, 0.25), K.BRICK)
	# windows (front, sides, back)
	var rnd := rng.randf()
	for f in floors:
		var y := base_h + 1.55 + f * 2.9
		for sx in [-w * 0.3, w * 0.3]:
			if f == 0 and absf(sx) < 0.01:
				continue
			_win(b, xf, Vector3(sx, y, d * 0.5), Vector2(1.1, 1.3), trim, rnd)
		if f > 0:
			_win(b, xf, Vector3(0, y, d * 0.5), Vector2(0.9, 1.1), trim, rnd)
		for sz in [-d * 0.22, d * 0.22]:
			_win(b, xf, Vector3(w * 0.5, y, sz), Vector2(1.0, 1.2), trim, rnd, "+x")
			_win(b, xf, Vector3(-w * 0.5, y, sz), Vector2(1.0, 1.2), trim, rnd, "-x")
		_win(b, xf, Vector3(0, y, -d * 0.5), Vector2(1.2, 1.2), trim, rnd, "-z")
	_door(b, xf, Vector3(0, base_h, d * 0.5), Color(0.42, 0.25, 0.15).lerp(trim, 0.2), trim)
	# porch: deck, posts, railing, roof, steps
	var pd := 2.2
	var deck_y := base_h
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, deck_y - 0.05, d * 0.5 + pd * 0.5)), Vector3(w * 0.85, 0.12, pd), Color(0.5, 0.38, 0.26), K.WOOD)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, deck_y * 0.5 - 0.06, d * 0.5 + pd * 0.5)), Vector3(w * 0.85, deck_y - 0.1, pd - 0.1), Color(0.45, 0.43, 0.4), K.CONCRETE)
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, deck_y * 0.5, d * 0.5 + pd * 0.5)), Vector3(w * 0.85, deck_y, pd))
	for px in [-w * 0.42, -0.9, 0.9, w * 0.42]:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(px, deck_y + 1.3, d * 0.5 + pd - 0.12)), Vector3(0.14, 2.6, 0.14), trim, K.PAINT)
	b.box(xf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, deck_y + 2.7, d * 0.5 + pd * 0.5)), Vector3(w * 0.9, 0.1, pd + 0.4), roof.lightened(0.05), K.ROOF)
	for side in [-1.0, 1.0]:
		var rail_len := w * 0.42 - 0.9
		var cx: float = side * (0.9 + rail_len * 0.5)
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(cx, deck_y + 0.9, d * 0.5 + pd - 0.12)), Vector3(rail_len, 0.08, 0.08), trim, K.PAINT)
		var n := int(rail_len / 0.25)
		for k in n:
			b.box(xf * Transform3D(Basis.IDENTITY, Vector3(side * (0.95 + k * 0.25), deck_y + 0.45, d * 0.5 + pd - 0.12)), Vector3(0.05, 0.85, 0.05), trim, K.PAINT, 0.0, ["top", "bottom"])
		cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(cx, deck_y + 0.5, d * 0.5 + pd - 0.12)), Vector3(rail_len, 1.0, 0.12))
	for k in 2:
		var sh := deck_y * (2 - k) / 3.0
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, sh * 0.5, d * 0.5 + pd + 0.2 + k * 0.32)), Vector3(1.6, sh, 0.32), Color(0.5, 0.48, 0.45), K.CONCRETE)
		cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, sh * 0.5, d * 0.5 + pd + 0.2 + k * 0.32)), Vector3(1.6, sh, 0.32))
	return xf * Vector3(0, 0, d * 0.5 + pd + 1.0)


# --------------------------------------------------------------------- shop row building
static func shopfront(b: GeoBatch, cols: ColliderSet, xf: Transform3D, w: float, d: float, floors: int, wall: Color, wall_kind: int, awning: Color, sign_col: Color, rng: RandomNumberGenerator) -> Vector3:
	var h := floors * FLOOR_H + 0.6
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, h, d), wall, wall_kind, rng.randf())
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, h, d))
	# parapet + cornice
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h + 0.15, d * 0.5 - 0.15)), Vector3(w + 0.1, 0.3, 0.35), wall.darkened(0.15), K.CONCRETE)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h - 0.1, 0)), Vector3(w + 0.25, 0.2, d + 0.25), Color(0.8, 0.78, 0.72), K.CONCRETE)
	# ground floor: display windows + door
	var gx := w * 0.5 - 0.6
	_win(b, xf, Vector3(-gx * 0.5 - 0.5, 1.5, d * 0.5), Vector2(gx - 1.0, 1.9), Color(0.15, 0.15, 0.16), rng.randf())
	_win(b, xf, Vector3(gx * 0.5 + 0.5, 1.5, d * 0.5), Vector2(gx - 1.0, 1.9), Color(0.15, 0.15, 0.16), rng.randf())
	_door(b, xf, Vector3(0, 0, d * 0.5), Color(0.3, 0.4, 0.45), Color(0.15, 0.15, 0.16), 1.2)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.25, d * 0.5 + 0.05)), Vector3(w, 0.5, 0.1), wall.darkened(0.25), K.CONCRETE)
	# awning
	var ab := Basis(Vector3.RIGHT, 0.35)
	b.box(xf * Transform3D(ab, Vector3(0, 2.95, d * 0.5 + 0.75)), Vector3(w - 0.4, 0.06, 1.6), awning, K.PAINT)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.62, d * 0.5 + 1.47)), Vector3(w - 0.4, 0.28, 0.05), awning.darkened(0.15), K.PAINT)
	# sign board
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.55, d * 0.5 + 0.08)), Vector3(w * 0.7, 0.62, 0.12), sign_col, K.SIGN)
	# upper floors windows
	for f in range(1, floors):
		var y := f * FLOOR_H + 1.6
		var n := maxi(2, int(w / 2.6))
		for k in n:
			var x := -w * 0.5 + (k + 0.5) * w / n
			_win(b, xf, Vector3(x, y, d * 0.5), Vector2(1.1, 1.5), Color(0.9, 0.88, 0.82), rng.randf())
	# rooftop AC box
	if rng.randf() < 0.7:
		b.abox(xf * Vector3(rng.randf_range(-w * 0.3, w * 0.3), h + 0.45, -d * 0.2), Vector3(1.4, 0.9, 1.0), Color(0.7, 0.72, 0.74), K.METAL, xf.basis.get_euler().y)
	return xf * Vector3(0, 0, d * 0.5 + 1.0)


# --------------------------------------------------------------------- apartment block
static func apartment(b: GeoBatch, cols: ColliderSet, xf: Transform3D, w: float, d: float, floors: int, wall: Color, rng: RandomNumberGenerator) -> Vector3:
	var h := floors * FLOOR_H + 0.4
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, h, d), wall, K.BRICK, rng.randf())
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, h, d))
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h + 0.2, 0)), Vector3(w + 0.3, 0.4, d + 0.3), Color(0.7, 0.68, 0.62), K.CONCRETE)
	var n := int(w / 3.2)
	for f in floors:
		var y := f * FLOOR_H + 1.7
		for k in n:
			var x := -w * 0.5 + (k + 0.5) * w / n
			if f == 0 and absf(x) < 2.0:
				continue
			_win(b, xf, Vector3(x, y, d * 0.5), Vector2(1.2, 1.5), Color(0.92, 0.9, 0.85), rng.randf())
			_win(b, xf, Vector3(x, y, -d * 0.5), Vector2(1.2, 1.5), Color(0.92, 0.9, 0.85), rng.randf(), "-z")
			if f > 0 and k % 2 == 0:
				# balcony
				b.box(xf * Transform3D(Basis.IDENTITY, Vector3(x, f * FLOOR_H + 0.05, d * 0.5 + 0.6)), Vector3(2.2, 0.15, 1.2), Color(0.7, 0.7, 0.68), K.CONCRETE)
				b.box(xf * Transform3D(Basis.IDENTITY, Vector3(x, f * FLOOR_H + 0.6, d * 0.5 + 1.17)), Vector3(2.2, 0.95, 0.05), Color(0.2, 0.22, 0.24), K.METAL, 0.0, ["bottom"])
	# entrance canopy
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, d * 0.5 + 0.9)), Vector3(3.6, 0.15, 1.8), Color(0.25, 0.27, 0.3), K.METAL)
	_door(b, xf, Vector3(0, 0, d * 0.5), Color(0.25, 0.32, 0.38), Color(0.2, 0.2, 0.22), 1.6)
	return xf * Vector3(0, 0, d * 0.5 + 1.2)


# --------------------------------------------------------------------- office tower
static func tower(b: GeoBatch, cols: ColliderSet, xf: Transform3D, w: float, d: float, floors: int, frame: Color, rng: RandomNumberGenerator) -> Vector3:
	var fh := 3.4
	var h := floors * fh + 1.0
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, h, d), Color(0.36, 0.46, 0.55), K.GLASS, rng.randf())
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(w, h, d))
	for f in floors + 1:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, f * fh + 0.15, 0)), Vector3(w + 0.12, 0.3, d + 0.12), frame, K.CONCRETE, 0.0, ["bottom"])
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx * w * 0.5, h * 0.5, sz * d * 0.5)), Vector3(0.5, h, 0.5), frame, K.CONCRETE)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h + 0.6, 0)), Vector3(w * 0.4, 1.2, d * 0.4), frame.darkened(0.1), K.CONCRETE)
	# lobby
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.6, d * 0.5 + 1.2)), Vector3(6.0, 0.25, 2.4), frame, K.CONCRETE)
	_door(b, xf, Vector3(-0.7, 0, d * 0.5), Color(0.3, 0.38, 0.42), Color(0.18, 0.18, 0.2), 1.2)
	_door(b, xf, Vector3(0.7, 0, d * 0.5), Color(0.3, 0.38, 0.42), Color(0.18, 0.18, 0.2), 1.2)
	return xf * Vector3(0, 0, d * 0.5 + 1.5)


# --------------------------------------------------------------------- hollow, enterable building
## Walls with a door opening on the front, floor, roof. Returns interior info.
static func hollow(b: GeoBatch, cols: ColliderSet, xf: Transform3D, w: float, d: float, h: float, wall: Color, kind: int, floor_col: Color, door_w: float = 2.0, door_x: float = 0.0) -> Dictionary:
	var t := 0.25
	# back + sides
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, -d * 0.5 + t * 0.5)), Vector3(w, h, t), wall, kind)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 + t * 0.5, h * 0.5, 0)), Vector3(t, h, d), wall, kind)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - t * 0.5, h * 0.5, 0)), Vector3(t, h, d), wall, kind)
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, -d * 0.5 + t * 0.5)), Vector3(w, h, t))
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 + t * 0.5, h * 0.5, 0)), Vector3(t, h, d))
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - t * 0.5, h * 0.5, 0)), Vector3(t, h, d))
	# front wall split around the door
	var left_w := (w * 0.5 + door_x - door_w * 0.5)
	var right_w := (w * 0.5 - door_x - door_w * 0.5)
	if left_w > 0.05:
		var cx := -w * 0.5 + left_w * 0.5
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(cx, h * 0.5, d * 0.5 - t * 0.5)), Vector3(left_w, h, t), wall, kind)
		cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(cx, h * 0.5, d * 0.5 - t * 0.5)), Vector3(left_w, h, t))
	if right_w > 0.05:
		var cx2 := w * 0.5 - right_w * 0.5
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(cx2, h * 0.5, d * 0.5 - t * 0.5)), Vector3(right_w, h, t), wall, kind)
		cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(cx2, h * 0.5, d * 0.5 - t * 0.5)), Vector3(right_w, h, t))
	var lintel_h := h - 2.4
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(door_x, 2.4 + lintel_h * 0.5, d * 0.5 - t * 0.5)), Vector3(door_w, lintel_h, t), wall, kind)
	# floor & ceiling (ceiling visible from inside, roof from outside)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), Vector3(w - t * 2.0, 0.06, d - t * 2.0), floor_col, K.TILES, 0.0, ["bottom"])
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, h + 0.1, 0)), Vector3(w + 0.3, 0.2, d + 0.3), Color(0.55, 0.55, 0.56), K.CONCRETE, 0.0, [])
	b.box(xf * Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, h - 0.01, 0)), Vector3(w - t * 2.0, 0.02, d - t * 2.0), Color(0.92, 0.92, 0.9), K.PAINT, 0.0, ["bottom"])
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, h + 0.1, 0)), Vector3(w, 0.2, d))
	return {"door_world": xf * Vector3(door_x, 0, d * 0.5 + 0.8), "door_inside": xf * Vector3(door_x, 0, d * 0.5 - 1.0), "xf": xf}


static func counter(b: GeoBatch, cols: ColliderSet, xf: Transform3D, length: float, top: Color, body: Color) -> void:
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), Vector3(length, 1.0, 0.7), body, K.WOOD)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.03, 0)), Vector3(length + 0.1, 0.06, 0.8), top, K.PAINT)
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)), Vector3(length, 1.1, 0.75))


static func shelf(b: GeoBatch, cols: ColliderSet, xf: Transform3D, length: float, rng: RandomNumberGenerator) -> void:
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)), Vector3(length, 1.6, 0.25), Color(0.85, 0.85, 0.86), K.METAL)
	for lvl in 4:
		b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.15 + lvl * 0.42, 0)), Vector3(length, 0.04, 0.8), Color(0.8, 0.8, 0.82), K.METAL)
		var x := -length * 0.5 + 0.15
		while x < length * 0.5 - 0.15:
			var sz := Vector3(rng.randf_range(0.12, 0.3), rng.randf_range(0.15, 0.3), rng.randf_range(0.15, 0.3))
			var c := Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.8), rng.randf_range(0.6, 0.95))
			for side in [-0.2, 0.2]:
				b.box(xf * Transform3D(Basis.IDENTITY, Vector3(x + sz.x * 0.5, 0.17 + lvl * 0.42 + sz.y * 0.5, side)), sz, c, K.PAINT)
			x += sz.x + 0.04
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)), Vector3(length, 1.6, 0.8))


static func table(b: GeoBatch, cols: ColliderSet, xf: Transform3D, size: Vector2, color: Color) -> void:
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.74, 0)), Vector3(size.x, 0.06, size.y), color, K.WOOD)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.37, 0)), Vector3(0.12, 0.74, 0.12), color.darkened(0.3), K.METAL)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)), Vector3(0.5, 0.04, 0.5), color.darkened(0.3), K.METAL)
	cols.add(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.4, 0)), Vector3(size.x, 0.8, size.y))


static func chair(b: GeoBatch, xf: Transform3D, color: Color) -> void:
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)), Vector3(0.45, 0.06, 0.45), color, K.WOOD)
	b.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.75, -0.2)), Vector3(0.45, 0.55, 0.05), color, K.WOOD)
	for sx in [-0.18, 0.18]:
		for sz in [-0.18, 0.18]:
			b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, 0.22, sz)), Vector3(0.04, 0.44, 0.04), color.darkened(0.3), K.WOOD)


static func ceiling_light(b: GeoBatch, pos: Vector3) -> void:
	b.box(Transform3D(Basis.IDENTITY, pos), Vector3(1.2, 0.05, 0.3), Color(1.0, 0.97, 0.9), K.SIGN)

extends Control
## Экранный слой поверх ночи: всплывающие надписи и светлячки.

var world


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var ct: Transform2D = world.get_viewport().get_canvas_transform()
	var sc: float = ct.get_scale().x
	if world.dark > 0.01:
		for p in world.parts:
			if p.type != "firefly":
				continue
			var a: float = (0.5 + 0.5 * sin(p.life * 4.0 + p.ph)) * minf(1.0, p.life)
			var s: Vector2 = ct * Vector2(p.x, p.y)
			draw_rect(Rect2(s - Vector2(sc * 1.5, sc * 1.5), Vector2(sc * 3, sc * 3)), Color(1, 0.94, 0.55, a * 0.25 * world.dark / 0.42))
			draw_rect(Rect2(s - Vector2(sc / 2, sc / 2), Vector2(sc, sc)), Color(1, 0.98, 0.75, a))
	# салют и прожекторы светятся поверх ночи
	for p in world.parts:
		if p.type != "rocket" and p.type != "spark":
			continue
		var s: Vector2 = ct * Vector2(p.x, p.y)
		var col := Color(p.col)
		if p.type == "rocket":
			draw_rect(Rect2(s - Vector2(sc / 2, sc / 2), Vector2(sc, sc * 2)), Color(1, 0.95, 0.8, 0.9))
			continue
		var a: float = clampf(p.life / p.mx * 1.5, 0.0, 1.0)
		col.a = a * 0.35
		draw_rect(Rect2(s - Vector2(sc * 2, sc * 2), Vector2(sc * 4, sc * 4)), col)
		col.a = a
		draw_rect(Rect2(s - Vector2(sc, sc), Vector2(sc * 2, sc * 2)), col)
		draw_rect(Rect2(s - Vector2(sc / 2, sc / 2), Vector2(sc, sc)), Color(1, 1, 1, a))
	var ev = world.events.active
	if ev != null and ev.kind == "premiere" and world.dark > 0.05:
		var base: Vector2 = ct * (ev.pos * 16.0 + Vector2(8, -10))
		for k in 2:
			var ang := -PI / 2.0 + sin(world.anim_time * 0.7 + k * 2.4) * 0.45
			var dir := Vector2(cos(ang), sin(ang))
			var side := Vector2(-dir.y, dir.x)
			var far := base + dir * sc * 220.0
			var bw := sc * 18.0
			draw_colored_polygon(PackedVector2Array([base - side * sc, base + side * sc, far + side * bw, far - side * bw]), Color(1, 0.97, 0.8, 0.13 * world.dark / 0.42))
	var font := get_theme_default_font()
	for f in world.floats:
		var k: float = 1.0 - f.life / f.mx
		var s: Vector2 = ct * f.pos - Vector2(0, k * 30.0)
		var a := minf(1.0, f.life * 2.0)
		var w := 400.0
		var pos := s - Vector2(w / 2.0, 0)
		draw_string_outline(font, pos, f.text, HORIZONTAL_ALIGNMENT_CENTER, w, 16, 6, Color(1, 0.97, 0.94, a))
		var col: Color = f.color
		col.a = a
		draw_string(font, pos, f.text, HORIZONTAL_ALIGNMENT_CENTER, w, 16, col)

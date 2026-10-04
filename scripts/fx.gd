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

extends RefCounted
## Генератор пиксельных зданий по описанию из defs.gd («look»):
## стены, крыша, окна, дверь, вывеска со значком и детали (неон, антенны, бассейн…).


const GLYPHS := {
	"train": [".xxx.", "x.x.x", "xxxxx", "xxxxx", ".x.x."],
	"plane": ["..x..", ".xxx.", "xxxxx", "..x..", ".xxx."],
	"tv": ["xxxxx", "x...x", "x...x", "xxxxx", ".x.x."],
	"chip": [".x.x.", "xxxxx", "x.x.x", "xxxxx", ".x.x."],
	"shirt": ["xx.xx", "xxxxx", ".xxx.", ".xxx.", ".xxx."],
	"car": [".....", ".xxx.", "xxxxx", "xxxxx", ".x.x."],
	"book": ["xx.xx", "x.x.x", "x.x.x", "x.x.x", "xx.xx"],
	"flower": [".x.x.", "xxxxx", ".xxx.", "..x..", ".xx.."],
	"tooth": ["xxxxx", "xxxxx", "xxxxx", "xx.xx", "x...x"],
	"paw": ["x.x.x", ".....", ".xxx.", "xxxxx", ".xxx."],
	"star": ["..x..", "xxxxx", ".xxx.", ".x.x.", "x...x"],
	"note": ["..xxx", "..x.x", "..x..", "xxx..", "xx..."],
	"fish": ["....x", ".xx.x", "xxxxx", ".xx.x", "....x"],
	"cup": ["xxxx.", "x..xx", "x..x.", "xxxx.", ".xx.."],
	"dollar": [".xxx.", "x.x..", ".xxx.", "..x.x", ".xxx."],
	"wrench": ["x...x", "xx.xx", ".xxx.", "..x..", "..x.."],
	"fuel": ["xxx..", "x.xx.", "xxx.x", "xxx.x", "xxx.."],
	"cross": ["..x..", "..x..", "xxxxx", "..x..", "..x.."],
	"bolt": ["..xx.", ".xx..", "xxxx.", "..xx.", ".xx.."],
	"drop": ["..x..", ".xxx.", "xxxxx", "xxxxx", ".xxx."],
	"leaf": ["...xx", ".xxxx", "xxxx.", "xxx..", "x...."],
	"burger": [".xxx.", "xxxxx", ".....", "xxxxx", ".xxx."],
	"game": [".....", "xxxxx", "x.x.x", "xxxxx", "....."],
	"camera": [".xx..", "xxxxx", "x.x.x", "xxxxx", "....."],
	"mic": [".xxx.", ".xxx.", ".xxx.", "..x..", ".xxx."],
	"scissors": ["x...x", ".x.x.", "..x..", ".x.x.", "xx.xx"],
	"heart": [".x.x.", "xxxxx", "xxxxx", ".xxx.", "..x.."],
	"bed": ["x....", "x.xx.", "xxxxx", "xxxxx", "x...x"],
	"cart": ["x....", "xxxxx", ".xxxx", ".xxx.", ".x.x."],
	"bus": ["xxxxx", "x.x.x", "xxxxx", "xxxxx", ".x.x."],
	"recycle": [".xxx.", "x...x", "x.x.x", "x...x", ".xxx."],
	"sun": ["x.x.x", ".xxx.", "xxxxx", ".xxx.", "x.x.x"],
	"ball": [".xxx.", "xx.xx", "x.x.x", "xx.xx", ".xxx."],
	"mask": ["xxxxx", "x.x.x", "xxxxx", "x...x", ".xxx."],
	"paint": [".xxx.", "x.x.x", "xxxxx", "xxx..", "x...."],
	"scale": ["..x..", "xxxxx", "x.x.x", "xx.xx", "..x.."],
	"grad": ["..x..", ".xxx.", "xxxxx", ".xxx.", ".x..."],
	"flask": [".xxx.", "..x..", ".xxx.", "xxxxx", "xxxxx"],
	"box": ["xxxxx", "x.x.x", "xxxxx", "x...x", "xxxxx"],
	"house": ["..x..", ".xxx.", "xxxxx", ".x.x.", ".xxx."],
	"bowling": ["..x..", ".xxx.", "..x..", ".xxx.", ".xxx."],
	"milk": [".xxx.", "..x..", ".xxx.", "x.x.x", "xxxxx"],
	"log": [".xxx.", "x...x", "x.x.x", "x...x", ".xxx."],
	"anchor": ["..x..", ".xxx.", "..x..", "x.x.x", ".xxx."],
	"sofa": [".....", "x...x", "xxxxx", "xxxxx", "x...x"],
}


static func _glyph(p, x0: int, y0: int, name: String, sc, fg) -> void:
	p.R(x0, y0, 7, 7, sc)
	var g: Array = GLYPHS.get(name, GLYPHS["star"])
	for r in 5:
		for c in 5:
			if g[r][c] == "x":
				p.P(x0 + 1 + c, y0 + 1 + r, fg)


static func _darker(hex: String, f := 0.85) -> Color:
	return Color(hex).darkened(1.0 - f)


## Рисует здание на холсте, который создаёт make(w, h) из sprites.gd.
## Обводку и тень добавляет sprites.gd.
static func build(look: Dictionary, sz: int, make: Callable):
	var w := 16 * sz
	var ex: Array = look.get("extra", [])
	var roof: String = look.get("roof", "flat")
	var sign: String = look.get("sign", "")
	var m := 2
	var bw := w - 2 * m
	var roof_h := 0
	match roof:
		"flat", "awning":
			roof_h = 3
		"gable":
			roof_h = maxi(4, bw / 3)
		"dome":
			roof_h = int(bw / 2.5)
		"saw":
			roof_h = 6
		"shed":
			roof_h = 5
	var sign_on_roof := sign != "" and roof in ["flat", "awning", "saw", "shed"]
	var top := 0
	if sign_on_roof:
		top = 8
	for e in ex:
		match e:
			"bigdonut":
				top = maxi(top, 13)
			"bigpin":
				top = maxi(top, 12)
			"flag", "chimney", "antenna":
				top = maxi(top, 8)
			"dish":
				top = maxi(top, 5)
			"ears":
				top = maxi(top, 4)
			"tower":
				top = maxi(top, 14)
			"silo":
				top = maxi(top, 6)
			"runway":
				top = maxi(top, 30)
			"windmill":
				top = maxi(top, 12)
	var min_body := 12 if sz == 1 else 16
	var h: int = maxi(int(look.get("h", 24 if sz == 1 else 40)), top + roof_h + min_body + 1)
	var p = make.call(w, h)
	var full := roof == "none" or ex.has("stalls")
	var by0 := top + roof_h
	var body_h := h - 1 - by0
	var wall: String = look.get("wall", "f2e6cc")
	var rc: String = look.get("rc", "8a8fb0")
	var wc: String = look.get("wc", "9fd3e6")
	var cx := w / 2
	if ex.has("runway"):
		_runway(p, w, by0)

	if not full:
		# крыша
		match roof:
			"flat", "awning":
				p.R(m - 1, by0 - 3, bw + 2, 3, rc)
				p.R(m - 1, by0 - 3, bw + 2, 1, Color(rc).lightened(0.25))
			"gable":
				for y in roof_h:
					var hw := roundi(float(y + 1) * (bw / 2.0 + 1.0) / roof_h)
					p.R(cx - hw, top + y, hw * 2, 1, rc if y < roof_h - 1 else _darker(rc))
			"dome":
				p.C(cx, by0 + 1, bw / 2.0, rc)
				p.C(cx - bw / 6.0, by0 - roof_h / 2.0, 1.5, Color(rc).lightened(0.3))
			"saw":
				var teeth := 2 if sz == 1 else 3
				var tw := bw / teeth
				for k in teeth:
					var x0 := m + k * tw
					for y in roof_h:
						var ln := maxi(1, roundi(float(y + 1) * tw / roof_h))
						p.R(x0 + tw - ln, top + y, ln, 1, rc)
					p.R(x0 + tw - 1, top, 1, roof_h, "bfe3f2")
			"shed":
				for x in bw + 2:
					var hh := roundi(roof_h * (1.0 - float(x) / (bw + 2)))
					p.R(m - 1 + x, by0 - hh, 1, hh, rc)
		# стены
		p.R(m, by0, bw, body_h, wall)
		p.R(m, h - 3, bw, 2, _darker(wall))
		# окна
		var door_w := 4 if sz == 1 else 6
		var door_h := 6 if sz == 1 else 8
		var dx0 := cx - door_w / 2
		match look.get("win", "grid"):
			"grid":
				var ww := 2 if sz == 1 else 3
				var wh := 3 if sz == 1 else 4
				var step_x := 4 if sz == 1 else 6
				var step_y := 6 if sz == 1 else 7
				var y := by0 + 2
				while y + wh < h - 3:
					var x := m + 1
					while x + ww <= m + bw - 1:
						var in_door := y + wh > h - 2 - door_h - 1 and x + ww > dx0 - 1 and x < dx0 + door_w + 1
						if not in_door:
							p.win(x, y, ww, wh, wc)
						x += step_x
					y += step_y
			"shop":
				var wy := h - 2 - door_h
				if dx0 - m - 2 >= 2:
					p.win(m + 1, wy, dx0 - m - 2, door_h - 2, wc)
				if m + bw - (dx0 + door_w) - 2 >= 2:
					p.win(dx0 + door_w + 1, wy, m + bw - (dx0 + door_w) - 2, door_h - 2, wc)
				var y2 := by0 + 2
				while y2 + 3 < wy - 3:
					p.win(m + 2, y2, bw - 4, 2, wc)
					y2 += 5
			"glass":
				p.R(m + 1, by0 + 1, bw - 2, body_h - 3, wc)
				var x2 := m + 1
				while x2 < m + bw - 1:
					p.R(x2, by0 + 1, 1, body_h - 3, _darker(wall, 0.92))
					x2 += 4
				var y3 := by0 + 6
				while y3 < h - 3:
					p.R(m + 1, y3, bw - 2, 1, _darker(wall, 0.92))
					y3 += 6
				# каждое окно — отдельная ячейка: ночью горят не все
				var wy := by0 + 2
				while wy + 3 < h - 3:
					var wx := m + 2
					while wx + 3 <= m + bw - 1:
						p.wins.append(Rect2i(wx, wy, 3, 3))
						wx += 4
					wy += 6
		# маркиза
		if look.has("awn"):
			var ay := h - 2 - door_h - 3
			for x in range(m - 1, m + bw + 1):
				var c: String = look.awn if ((x - m) >> 1) % 2 == 0 else "ffffff"
				p.R(x, ay, 1, 2, c)
				if ((x - m) >> 1) % 2 == 0:
					p.P(x, ay + 2, c)
		# дверь
		p.R(dx0, h - 2 - door_h, door_w, door_h, look.get("door", "8a5a3b"))
		p.P(dx0 + door_w - 1, h - 2 - door_h / 2, "ffd75e")
		# вывеска
		if sign != "":
			if sign_on_roof:
				p.R(cx, 7, 1, by0 - roof_h - 7 + 3, "6a6478")
				_glyph(p, cx - 3, 0, sign, look.get("sc", "ffffff"), look.get("fg", "3b2a3a"))
			else:
				_glyph(p, cx - 3, by0 + 1, sign, look.get("sc", "ffffff"), look.get("fg", "3b2a3a"))

	for e in ex:
		_extra(p, e, w, h, by0, body_h, sz, look)
	return p


## Взлётная полоса и стоянка самолётов позади здания аэропорта.
static func _runway(p, w: int, by0: int) -> void:
	p.R(0, 1, w, by0 - 1, "a8d08a")
	# полоса
	p.R(0, 3, w, 9, "5d5b6a"); p.R(0, 3, w, 1, "e6e6ee"); p.R(0, 11, w, 1, "e6e6ee")
	for x in range(2, w - 2, 6):
		p.R(x, 7, 3, 1, "ffffff")
	p.R(1, 4, 1, 7, "ffffff"); p.R(3, 4, 1, 7, "ffffff"); p.R(w - 2, 4, 1, 7, "ffffff"); p.R(w - 4, 4, 1, 7, "ffffff")
	# перрон
	p.R(0, 13, w, by0 - 13, "c9c4d6")
	for x in range(4, w, 16):
		p.R(x, 14, 1, by0 - 15, "ffd23f")
	# самолёт на полосе и два на стоянке
	_mini_plane(p, 26, 5, "3d5a98")
	_mini_plane(p, 9, 17, "e45b6b")
	# площадка для вертолёта справа
	p.C(w - 6, 21.5, 4, "8a8898"); p.R(w - 8, 20, 1, 4, "ffffff"); p.R(w - 5, 20, 1, 4, "ffffff"); p.R(w - 8, 21, 4, 1, "ffffff")
	# диспетчерская вышка слева
	p.R(2, 9, 3, by0 - 9, "dfe5ee"); p.R(1, 6, 5, 3, "3d5a98"); p.R(2, 7, 3, 1, "9fd3e6"); p.P(3, 5, "ff6b6b")
	# огни полосы
	for x in range(1, w, 8):
		p.P(x, 2, "ffd23f")
		p.P(x + 4, 12, "5fd3c8")


static func _mini_plane(p, x: int, y: int, stripe: String) -> void:
	# нос вправо: фюзеляж, крыло, хвост
	p.R(x, y + 2, 14, 3, "3b2a3a"); p.R(x + 1, y + 2, 12, 2, "f4f7fb"); p.P(x + 14, y + 3, "3b2a3a")
	p.R(x + 1, y + 3, 12, 1, stripe)
	p.R(x + 12, y + 2, 1, 1, "9fd3e6")
	p.R(x + 5, y + 4, 4, 3, "dfe5ee"); p.R(x + 5, y + 6, 4, 1, "3b2a3a")
	p.R(x + 6, y, 2, 2, "dfe5ee")
	p.R(x, y, 2, 2, stripe); p.R(x - 1, y, 1, 3, "3b2a3a")


static func _extra(p, e: String, w: int, h: int, by0: int, body_h: int, sz: int, look: Dictionary) -> void:
	var cx := w / 2
	match e:
		"ears":
			# кошачьи ушки на крыше — как у маленького домика
			var rc2: String = look.get("rc", "f28fa6")
			for ex0 in [cx - 10, cx + 6]:
				var ty := by0
				for yy in h:
					if p.img.get_pixel(ex0 + 2, yy).a > 0.5:
						ty = yy
						break
				p.R(ex0, ty - 2, 5, 3, rc2)
				p.R(ex0 + 1, ty - 4, 3, 2, rc2)
				p.P(ex0 + 2, ty - 5, rc2)
				p.R(ex0 + 2, ty - 3, 1, 2, "ffc8d4")
		"trailer":
			p.R(1, 7, 14, 7, "d8dce4"); p.R(2, 6, 12, 1, "e8ecf2"); p.R(1, 12, 14, 1, "b8bcc4")
			p.win(3, 8, 3, 2); p.win(10, 8, 3, 2)
			p.R(7, 8, 2, 5, "8a8fb0")
			p.C(4, 14, 1.6, "2b2b3a")
			for x in range(1, 15, 2):
				p.P(x, 5, ["ff6b8b", "ffd23f", "5fd3c8"][x % 3])
		"porch":
			p.R(1, h - 4, w - 2, 2, "c08f5f")
			p.R(2, h - 9, 1, 5, "c08f5f"); p.R(w - 3, h - 9, 1, 5, "c08f5f")
		"pool":
			p.R(3, h - 8, 12, 5, "5fc8e8"); p.R(4, h - 7, 10, 1, "a8e4f4")
			p.R(18, h - 6, 6, 2, "ff9fc0")
		"palm":
			p.R(w - 4, h - 16, 1, 13, "a0764a")
			for lv in [[-1, 0], [1, 0], [-1, 1], [1, 1], [0, -1]]:
				for k in 4:
					p.P(w - 4 + lv[0] * k, h - 17 + lv[1] * k + (k * k) / 4, "4fae5a")
		"antenna":
			p.R(cx + 5, maxi(0, by0 - 9), 1, 7, "6a6478"); p.P(cx + 5, maxi(0, by0 - 10), "ff6b6b")
		"carts":
			for k in 3:
				p.R(3 + k * 3, h - 4, 2, 2, "c9c4d6")
		"truck":
			p.R(1, 6, 14, 7, "ffd23f"); p.R(1, 12, 14, 1, "e0b020")
			p.R(10, 7, 3, 3, "bfe6f7")
			p.R(2, 7, 7, 3, "fff4e0")
			for x in range(2, 9):
				p.P(x, 6, "e45b6b" if x % 2 else "5fae73")
			p.C(4, 13.5, 1.6, "2b2b3a"); p.C(12, 13.5, 1.6, "2b2b3a")
			p.wins.append(Rect2i(2, 7, 7, 3))
		"bigdonut":
			p.C(cx, 6.5, 6.4, "c08040")
			p.C(cx, 6, 5.6, "f4a0b8")
			p.C(cx, 6, 2.0, Color(0, 0, 0, 0))
			for pt in [[cx - 3, 3], [cx + 2, 2], [cx + 4, 6], [cx - 4, 7], [cx + 1, 9]]:
				p.P(pt[0], pt[1], ["5fd3c8", "ffd23f", "ffffff"][pt[1] % 3])
			p.R(cx, 12, 1, by0 - 12 - 2, "6a6478")
		"stalls":
			var n := 3 if sz == 2 else 2
			var sw := (w - 2) / n
			for k in n:
				var x0 := 1 + k * sw
				for x in range(x0, x0 + sw - 1):
					p.R(x, h - 16, 1, 3, "ff9f43" if x % 2 else "ffffff")
				p.R(x0 + 1, h - 13, 1, 9, "8a5a3b"); p.R(x0 + sw - 3, h - 13, 1, 9, "8a5a3b")
				p.R(x0, h - 8, sw - 1, 5, "c99a6b")
				for x in range(x0 + 1, x0 + sw - 2, 2):
					p.P(x, h - 9, ["e45b6b", "7cc46a", "ffd23f", "ff9f43"][(x + k) % 4])
		"pole":
			p.R(w - 4, h - 12, 2, 8, "ffffff")
			for y in range(h - 12, h - 4, 2):
				p.P(w - 4 + (y / 2) % 2, y, "e45b6b")
		"washers":
			for x in [4, 10]:
				p.C(x + 0.5, h - 6.5, 1.8, "c9c4d6"); p.P(x, h - 7, "8fb3f2")
		"pumps":
			p.R(0, h - 15, w, 2, "e45b6b")
			p.R(1, h - 13, 1, 9, "c9c4d6"); p.R(w - 2, h - 13, 1, 9, "c9c4d6")
			p.R(3, h - 8, 2, 5, "e45b6b"); p.R(11, h - 8, 2, 5, "e45b6b")
			p.P(3, h - 7, "fff6c2"); p.P(11, h - 7, "fff6c2")
		"bubbles":
			p.R(3, h - 11, 10, 9, "3b3b4a")
			for pt in [[5, h - 9], [9, h - 8], [7, h - 6], [11, h - 10], [4, h - 5]]:
				p.C(pt[0] + 0.5, pt[1] + 0.5, 1.4, "ffffff")
		"garage_door":
			var gw := (w - 8) if sz == 1 else (w / 2 - 4)
			var gx := 4 if sz == 1 else 3
			p.R(gx, h - 11, gw, 9, "c9c4d6")
			for y in range(h - 10, h - 2, 2):
				p.R(gx, y, gw, 1, "aaa4bc")
		"lotcars":
			var cols := ["e45b6b", "ffd23f", "5fd3c8", "ff9fc0"]
			for k in 4:
				var x0 := 2 + k * 7
				p.R(x0, h - 6, 6, 3, cols[k]); p.R(x0 + 1, h - 7, 4, 1, "bfe6f7")
				p.P(x0 + 1, h - 3, "2b2b3a"); p.P(x0 + 4, h - 3, "2b2b3a")
		"neon":
			for x in range(1, w - 1, 2):
				p.P(x, by0 - 1, "ff6fae" if (x / 2) % 2 == 0 else "5fd3c8")
			p.wins.append(Rect2i(1, by0 - 1, w - 2, 1))
		"flag":
			p.R(4, maxi(0, by0 - 10), 1, 10, "6a6478"); p.R(5, maxi(0, by0 - 10), 4, 3, "e45b6b"); p.R(5, maxi(0, by0 - 9), 4, 1, "ffffff")
		"columns":
			var x := 4
			while x < w - 4:
				p.R(x, by0 + 2, 2, body_h - 4, "ffffff")
				p.R(x + 1, by0 + 2, 1, body_h - 4, "e6dccb")
				x += 6
		"servers":
			var x := 4
			while x < w - 6:
				p.R(x, by0 + 3, 5, body_h - 7, "2b2b3a")
				for y in range(by0 + 4, h - 5, 2):
					p.P(x + 1, y, "5fd38f" if (x + y) % 3 else "5fd3c8")
					p.P(x + 3, y, "ff6b6b" if (x * y) % 5 == 0 else "5fd38f")
				p.wins.append(Rect2i(x + 1, by0 + 4, 3, body_h - 9))
				x += 7
		"dish":
			p.C(w - 6, by0 - 3, 2.5, "e8e8e8"); p.P(w - 6, by0 - 1, "6a6478")
		"mast":
			p.R(w - 5, 0, 1, by0, "e45b6b")
			for y in range(1, by0, 3):
				p.P(w - 5, y, "ffffff")
			p.P(w - 6, 0, "ff6b6b"); p.P(w - 4, 0, "ff6b6b")
		"chimney":
			p.R(w - 7, by0 - 9, 3, 7, "a05a4a"); p.R(w - 7, by0 - 9, 3, 1, "c07060")
		"deck":
			# мостки из досок со швартовыми тумбами
			p.R(0, h - 10, w, 9, "c9a77a")
			for x in range(0, w, 3):
				p.R(x, h - 10, 1, 9, "a8865a")
			p.R(0, h - 2, w, 1, "8a6a48")
			p.R(1, h - 12, 2, 3, "6a6478"); p.R(w - 3, h - 12, 2, 3, "6a6478")
			p.R(2, h - 11, w - 4, 1, "e8d6bc")
		"silo":
			# силос у правого края
			var sx := w - 8
			p.R(sx, 3, 6, h - 4, "dfe3ea"); p.R(sx, 3, 1, h - 4, "c3c8d2"); p.R(sx + 5, 3, 1, h - 4, "eef1f6")
			p.C(sx + 3, 3.5, 3, "c8553d")
			for y in range(8, h - 2, 4):
				p.R(sx, y, 6, 1, "c3c8d2")
		"cows":
			p.R(1, h - 6, w - 12, 1, "c08f5f"); p.R(1, h - 9, w - 12, 1, "c08f5f")
			for k in [3, 12]:
				p.R(k, h - 8, 7, 4, "ffffff"); p.R(k + 1, h - 7, 2, 2, "2b2b3a"); p.R(k + 5, h - 8, 1, 2, "2b2b3a")
				p.R(k + 7, h - 9, 3, 3, "ffffff"); p.P(k + 9, h - 8, "2b2b3a"); p.R(k + 8, h - 7, 2, 1, "ffb3c1")
				p.P(k, h - 4, "3b3b4a"); p.P(k + 5, h - 4, "3b3b4a")
		"sheep":
			# пастбище с загородкой и пушистыми овечками
			for x in range(0, w, 4):
				p.R(x, h - 4, 1, 3, "c08f5f")
			p.R(0, h - 3, w, 1, "c08f5f"); p.R(0, 4, w, 1, "c08f5f")
			for x in range(0, w, 4):
				p.R(x, 3, 1, 3, "c08f5f")
			for k in [[3, 8], [15, 6], [8, 14], [21, 13]]:
				p.C(k[0] + 3, k[1] + 2, 2.6, "ffffff"); p.C(k[0] + 5, k[1] + 1.5, 2.2, "f4f0ec")
				p.R(k[0] + 6, k[1] + 1, 3, 3, "4a4050"); p.P(k[0] + 7, k[1] + 2, "ffffff")
				p.P(k[0] + 2, k[1] + 5, "4a4050"); p.P(k[0] + 5, k[1] + 5, "4a4050")
			p.R(w - 7, 7, 5, 4, "a0704a"); p.R(w - 8, 6, 7, 1, "c8553d")
		"cotton":
			for r in range(2, h - 2, 4):
				p.R(1, r, w - 2, 2, "6a9a3a")
				for x in range(2, w - 2, 3):
					p.P(x + (r / 4) % 2, r, "ffffff")
					p.P(x + 1, r + 1, "f4f0e6")
			p.R(w - 10, h - 9, 8, 6, "c9a77a"); p.R(w - 11, h - 10, 10, 1, "a0704a")
			p.R(w - 9, h - 8, 6, 3, "ffffff")
		"logs":
			for k in 3:
				var y0 := h - 4 - k * 3
				for j in 3 - k:
					var x0 := 2 + j * 4 + k * 2
					p.C(x0 + 1.5, y0 + 1.5, 1.7, "a0704a"); p.P(x0 + 1, y0 + 1, "f1dfa6")
			p.R(w - 12, h - 6, 10, 3, "e8c89a"); p.R(w - 12, h - 7, 10, 1, "c08a5a")
		"mine":
			# вход в гору, рельсы и тележка с рудой
			p.C(w / 2, h - 8, 12, "9a8a74"); p.C(w / 2, h - 10, 9, "b4a48c")
			p.R(0, h - 4, w, 3, "9a8a74")
			p.C(w / 2, h - 5, 5, "3b3340"); p.R(w / 2 - 5, h - 5, 10, 4, "3b3340")
			p.R(w / 2 - 6, h - 11, 12, 1, "a0704a"); p.R(w / 2 - 6, h - 11, 1, 9, "a0704a"); p.R(w / 2 + 5, h - 11, 1, 9, "a0704a")
			p.R(2, h - 2, w - 4, 1, "6a6478")
			p.R(4, h - 6, 7, 3, "6a6478"); p.R(5, h - 7, 5, 1, "c9ccd6"); p.P(6, h - 8, "e8eaf0")
			p.P(5, h - 3, "2b2b33"); p.P(9, h - 3, "2b2b33")
		"windmill":
			var mx := w / 2
			var my := 5
			for k in 6:
				p.R(mx - k - 1, my - k, 2, 1, "f4f0e6"); p.R(mx + k, my + k, 2, 1, "f4f0e6")
				p.R(mx + k, my - k, 2, 1, "f4f0e6"); p.R(mx - k - 1, my + k, 2, 1, "f4f0e6")
			p.R(mx - 1, my - 1, 2, 2, "a0704a")
		"containers":
			var cols := ["e45b6b", "5b8de4", "5fae73", "ff9f43", "ffd23f", "9b7ad1"]
			for r in 3:
				for k in 3:
					p.R(2 + k * 8, h - 6 - r * 4, 7, 3, cols[(r * 3 + k) % cols.size()])
					p.R(2 + k * 8, h - 4 - r * 4, 7, 1, Color(cols[(r * 3 + k) % cols.size()]).darkened(0.25))
		"crane":
			p.R(26, 2, 2, h - 4, "ff9f43"); p.R(8, 2, 22, 2, "ff9f43")
			p.R(12, 4, 1, 10, "6a6478"); p.R(11, 14, 3, 2, "6a6478")
		"towers":
			for tx in [9, 23]:
				for y in range(by0 - 4, h - 2):
					var t := float(y - (by0 - 4)) / float(h - 2 - (by0 - 4))
					var hw := roundi(5.0 - 2.0 * sin(t * PI) )
					p.R(tx - hw, y, hw * 2, 1, "d8d4e4" if y % 3 else "c9c4d6")
		"panels":
			for r in 4:
				for k in 2:
					var x0 := 2 + k * 15
					var y0 := 4 + r * 5
					p.R(x0, y0, 13, 4, "2e4a8a"); p.R(x0, y0, 13, 1, "6a8ad0")
					for x in range(x0 + 3, x0 + 13, 3):
						p.R(x, y0, 1, 4, "4a6aa8")
		"tanks":
			p.C(6, h - 9, 4, "e8eef6"); p.C(26, h - 9, 4, "e8eef6")
			p.R(3, h - 9, 7, 6, "e8eef6"); p.R(23, h - 9, 7, 6, "e8eef6")
		"tower":
			p.R(cx - 3, 4, 6, by0 - 4, look.get("wall", "f2e6cc"))
			for y in 4:
				p.R(cx - y, y, y * 2, 1, look.get("rc", "8a8fb0"))
			p.C(cx, 8, 1.8, "ffffff"); p.P(cx, 7, "3b2a3a")
		"stairs":
			p.R(3, h - 9, 10, 7, "3b3b4a")
			for y in range(h - 8, h - 2, 2):
				p.R(4, y, 8, 1, "6a6478")
		"helipad":
			p.C(8, 8.5, 7, "6a6478"); p.C(8, 8.5, 6, "8a8898")
			p.R(5, 5, 1, 7, "ffffff"); p.R(10, 5, 1, 7, "ffffff"); p.R(5, 8, 6, 1, "ffffff")
			p.P(1, 8, "ffd23f"); p.P(15, 8, "ffd23f"); p.P(8, 1, "ffd23f"); p.P(8, 15, "ffd23f")
		"ramps":
			p.R(1, h - 18, w - 2, 16, "d8d4e4")
			for k in 2:
				var x0 := 3 + k * 15
				for x in 11:
					var hh := roundi(6.0 * pow(absf(x - 5.0) / 5.0, 2.0))
					p.R(x0 + x, h - 10 - hh, 1, hh + 1, "aaa4bc")
			p.R(3, h - 4, w - 6, 1, "ff6fae")
		"court":
			p.R(1, 4, w - 2, h - 6, "5fae73")
			p.R(3, 6, w - 6, h - 10, "6fbf70")
			p.R(3, 6, w - 6, 1, "ffffff"); p.R(3, h - 5, w - 6, 1, "ffffff"); p.R(3, 6, 1, h - 10, "ffffff"); p.R(w - 4, 6, 1, h - 10, "ffffff")
			p.R(cx, 4, 1, h - 6, "2b2b3a"); p.R(cx - 1, 4, 3, 1, "ffffff")
			p.P(cx + 6, 9, "f2e060")
		"net":
			p.R(2, 4, 1, 10, "8a5a3b"); p.R(13, 4, 1, 10, "8a5a3b")
			p.R(2, 5, 12, 3, "ffffff")
			for x in range(3, 13, 2):
				p.P(x, 6, "c9c4d6")
			p.C(11, 12, 1.5, "ffd23f")
		"bigpin":
			p.C(cx, 3, 2.2, "ffffff"); p.R(cx - 1, 5, 2, 2, "ffffff"); p.C(cx, 9, 3, "ffffff")
			p.R(cx - 2, 4, 4, 1, "e45b6b"); p.R(cx - 2, 6, 4, 1, "e45b6b")
		"zoo":
			p.R(1, 6, w - 2, h - 8, "9ccf7a")
			for x in range(1, w - 1, 3):
				p.R(x, h - 4, 1, 3, "c08f5f")
			p.R(1, h - 3, w - 2, 1, "c08f5f")
			p.C(8, h - 10, 3.5, "5fc8e8")
			p.R(20, 8, 2, 12, "f2c14e"); p.R(20, 7, 5, 2, "f2c14e"); p.R(19, 18, 6, 4, "f2c14e")
			p.P(20, 11, "a0703a"); p.P(21, 14, "a0703a"); p.P(23, 7, "3b2a3a")
			p.R(19, 22, 1, 3, "f2c14e"); p.R(24, 22, 1, 3, "f2c14e")
			p.C(28, 10, 2.5, "4fae5a"); p.R(28, 12, 1, 4, "8a5a3b")
			p.R(10, 18, 3, 4, "2b2b3a"); p.R(11, 19, 1, 2, "ffffff"); p.P(11, 17, "ff9f43")
		"billboard":
			p.R(3, 12, 1, 11, "6a6478"); p.R(12, 12, 1, 11, "6a6478")
			p.R(0, 2, 16, 10, "ffffff"); p.R(1, 3, 14, 8, "5fc8e8")
			p.C(6, 7, 2.5, "ffd23f")
			for k in 5:
				p.P(9 + k, 5 + (k % 2), "ff6b8b")
			p.R(9, 8, 5, 2, "ff9f43")
			p.wins.append(Rect2i(1, 3, 14, 8))
		"watertower":
			p.R(4, 14, 1, 16, "8a8fb0"); p.R(11, 14, 1, 16, "8a8fb0")
			for i in 6:
				p.P(5 + i, 16 + i * 2, "8a8fb0")
			p.R(3, 6, 10, 8, "c9c4d6"); p.R(3, 9, 10, 1, "aaa4bc")
			for y in 4:
				p.R(8 - y - 1, 2 + y, (y + 1) * 2, 1, "8a8fb0")

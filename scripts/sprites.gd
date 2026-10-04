extends RefCounted
## Вся пиксельная графика рисуется кодом — пиксель за пикселем, без внешних картинок.

const D = preload("res://scripts/defs.gd")
const BG = preload("res://scripts/buildgen.gd")
const INK := Color("3b2a3a")
const SHADOW := Color(0.157, 0.118, 0.196, 0.22)


class Painter:
	var img: Image
	var w: int
	var h: int
	var wins: Array = []

	func _init(width: int, height: int) -> void:
		w = width
		h = height
		img = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)

	func R(x: int, y: int, ww: int, hh: int, col) -> void:
		var c: Color = col if col is Color else Color(col)
		var x0: int = maxi(0, x)
		var y0: int = maxi(0, y)
		var x1: int = mini(w, x + ww)
		var y1: int = mini(h, y + hh)
		if x1 <= x0 or y1 <= y0:
			return
		img.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), c)

	func P(x: int, y: int, col) -> void:
		R(x, y, 1, 1, col)

	func C(cx: float, cy: float, r: float, col) -> void:
		var c: Color = col if col is Color else Color(col)
		for y in range(int(floor(cy - r)), int(ceil(cy + r)) + 1):
			for x in range(int(floor(cx - r)), int(ceil(cx + r)) + 1):
				var dx := x + 0.5 - cx
				var dy := y + 0.5 - cy
				if dx * dx + dy * dy <= r * r and x >= 0 and y >= 0 and x < w and y < h:
					img.set_pixel(x, y, c)

	func win(x: int, y: int, ww: int, hh: int, glass = "9fd3e6") -> void:
		R(x, y, ww, hh, glass)
		P(x, y, "d7f1fa")
		wins.append(Rect2i(x, y, ww, hh))


# ---------- готовые спрайты ----------
var obj := {}
var windows := {}
var trees: Array = []
var palms: Array = []
var flowers: Array = []
var icons := {}
var small := {}
var scaffold := {}
var _cat_cache := {}
var _veh_cache := {}


static func outline(img: Image, col: Color = INK) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate() as Image
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a >= 0.63:
				continue
			if _solid(src, x - 1, y) or _solid(src, x + 1, y) or _solid(src, x, y - 1) or _solid(src, x, y + 1):
				img.set_pixel(x, y, col)


static func _solid(img: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.63


static func add_shadow(img: Image, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var edge := (x == r.position.x or x == r.end.x - 1) and y == r.end.y - 1 and r.size.y > 1
			if not edge and img.get_pixel(x, y).a < 0.05:
				img.set_pixel(x, y, SHADOW)


static func tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func flipped(t: Texture2D) -> ImageTexture:
	var img := t.get_image()
	img.flip_x()
	return ImageTexture.create_from_image(img)


## Увеличенная копия (для кнопок интерфейса).
static func scaled(t: Texture2D, k: int) -> ImageTexture:
	var img := t.get_image()
	img.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


static func grid(rows: Array, pal: Dictionary) -> Image:
	var h := rows.size()
	var w: int = rows[0].length()
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for j in h:
		var row: String = rows[j]
		for i in w:
			var ch := row[i]
			if pal.has(ch) and pal[ch] != null:
				img.set_pixel(i, j, pal[ch] if pal[ch] is Color else Color(pal[ch]))
	return img


func drawn(w: int, h: int, fn: Callable, do_outline := true, shadow := Rect2i()) -> ImageTexture:
	var p := Painter.new(w, h)
	fn.call(p)
	if do_outline:
		outline(p.img)
	if shadow.size.x > 0:
		add_shadow(p.img, shadow)
	return tex(p.img)


func bld(key: String, w: int, h: int, fn: Callable) -> void:
	var p := Painter.new(w, h)
	fn.call(p)
	outline(p.img)
	add_shadow(p.img, Rect2i(1, h - 1, w - 2, 1))
	obj[key] = tex(p.img)
	windows[key] = p.wins


# ---------- Котики на двух лапках ----------
const UP_BODY := [
	"............",
	"............",
	".k......k...",
	"kpk....kpk..",
	"kaakkkkaak..",
	"kaaabbaaak..",
	"kaeaaaaeak..",
	"kcaappaack..",
	".kaaaaaak...",
	".kswttwsk.k.",
	"ksssttssskak",
	"ksssttssskak",
	"kassssssakk.",
	".kllllllk...",
]
const UP_LEGS := {
	"stand": ["..kl..lk....", "..ko..ok...."],
	"walkA": ["..kl..ok....", "..ko........"],
	"walkB": ["..ok..lk....", "......ok...."],
}
const SLEEP_EYES := "kakkaakkak.."

## Профессии: s — пиджак/куртка, t — галстук/вставка, w — рубашка, l — брюки.
const OUTFITS := {
	"fisher": {"s": "ffd23f", "t": "e6b800", "w": "ffd23f", "l": "4a6a8a", "hat": "sou", "hc": "ffd23f"},
	"seller": {"s": "ff8fab", "t": "ff8fab", "w": "ffffff", "l": "5b7bb0"},
	"baker": {"s": "ffffff", "t": "f2e2c8", "w": "ffffff", "l": "8a6a4a", "hat": "chef", "hc": "ffffff"},
	"barista": {"s": "6a4a3a", "t": "fff4e0", "w": "fff4e0", "l": "3b3b4a", "hat": "beret", "hc": "e07a8a"},
	"clerk": {"s": "7d8898", "t": "5b8de4", "w": "ffffff", "l": "5d6573"},
	"official": {"s": "2f3a5a", "t": "d9483b", "w": "ffffff", "l": "2f3a5a"},
	"worker": {"s": "4a7fc4", "t": "4a7fc4", "w": "e8e8e8", "l": "3e6aa8", "hat": "cap", "hc": "4a7fc4"},
	"builder": {"s": "ff9f43", "t": "fff066", "w": "ff9f43", "l": "5b6b8a", "hat": "hard", "hc": "ffd23f"},
	"teacher": {"s": "7aa86a", "t": "f2c14e", "w": "ffffff", "l": "6b5a4a", "glasses": true},
	"doctor": {"s": "f4f7fb", "t": "9fd3e6", "w": "9fd3e6", "l": "9fd3e6", "steth": true},
	"police": {"s": "3d5a98", "t": "26365e", "w": "b8d0f0", "l": "2c3e66", "hat": "cap", "hc": "2c3e66", "badge": true},
	"fire": {"s": "d9483b", "t": "ffe066", "w": "d9483b", "l": "3b3b4a", "hat": "hard", "hc": "e0483a", "badge": true},
	"mail": {"s": "5b8de4", "t": "ffd75e", "w": "5b8de4", "l": "3d5a98", "hat": "cap", "hc": "ffd75e"},
	"librarian": {"s": "9b7ad1", "t": "ffffff", "w": "ffffff", "l": "5a4a6a", "glasses": true},
	"developer": {"s": "4a4e69", "t": "4a4e69", "w": "6c7090", "l": "3e5a8a", "glasses": true, "phones": true},
	"blogger": {"s": "ff6fae", "t": "ffffff", "w": "ffffff", "l": "3b3b4a", "shades": true, "hat": "beanie", "hc": "c8a8ff"},
	"actor": {"s": "2b2b3a", "t": "ffffff", "w": "ffffff", "l": "2b2b3a", "shades": true},
	"surfer": {"s": "2e3440", "t": "5fd3c8", "w": "2e3440", "l": "2e3440"},
	"trainer": {"s": "5fd38f", "t": "5fd38f", "w": "5fd38f", "l": "3b3b4a", "hat": "band", "hc": "e45b6b"},
	"icecream": {"s": "ffffff", "t": "ff9fc0", "w": "ff9fc0", "l": "8fb3f2", "hat": "cap", "hc": "ff9fc0"},
	"usher": {"s": "b02e3a", "t": "ffd75e", "w": "ffffff", "l": "2b2b3a", "hat": "cap", "hc": "b02e3a"},
	"sushi": {"s": "ffffff", "t": "2b2b3a", "w": "ffffff", "l": "2b2b3a", "hat": "band", "hc": "e45b6b"},
	"pizza": {"s": "ffffff", "t": "5fae73", "w": "e45b6b", "l": "3b3b4a", "hat": "chef", "hc": "ffffff"},
	"groomer": {"s": "ff9fc0", "t": "ffffff", "w": "ffffff", "l": "8fb3f2", "hat": "beanie", "hc": "ffffff"},
	"farmer": {"s": "5b8de4", "t": "5b8de4", "w": "e45b6b", "l": "4a6fb8", "hat": "straw", "hc": "e8c870"},
	"trader": {"s": "2f3a5a", "t": "ffd23f", "w": "cfe0ff", "l": "2f3a5a", "glasses": true},
	"lifeguard": {"s": "e0483a", "t": "ffffff", "w": "e0483a", "l": "e0483a", "shades": true, "hat": "cap", "hc": "ffd75e"},
}
const CASUAL_SHIRTS := ["ff8fab", "7fc4e8", "ffd75e", "9ed8c8", "c8a8ff", "ffb07a"]
const HATS := {
	"hard": [[2, 1, 6, 2], [1, 3, 8, 1]],
	"sou": [[2, 2, 6, 2], [0, 4, 10, 1]],
	"cap": [[2, 2, 6, 2], [2, 4, 7, 1]],
	"chef": [[2, 0, 6, 2], [3, 2, 4, 2]],
	"beret": [[2, 2, 6, 2], [4, 1, 1, 1]],
	"beanie": [[2, 2, 6, 2], [3, 1, 4, 1]],
	"band": [[1, 5, 8, 1]],
	"straw": [[2, 1, 6, 3], [0, 4, 10, 1]],
	"sombrero": [[3, 1, 4, 2], [0, 3, 10, 1]],
	"top": [[3, 0, 4, 3], [1, 3, 8, 1]],
	"grad": [[1, 2, 8, 1], [3, 3, 4, 1]],
}


static func outfit(key: String) -> Dictionary:
	if OUTFITS.has(key):
		return OUTFITS[key]
	if D.JOB_OUTFITS.has(key):
		return D.JOB_OUTFITS[key]
	var i := int(key.trim_prefix("casual")) % CASUAL_SHIRTS.size()
	var s: String = CASUAL_SHIRTS[i]
	return {"s": s, "t": s, "w": s, "l": "5b7bb0"}


static func make_cat_frame(fur: Dictionary, o: Dictionary, legs: String, sleeping: bool) -> Image:
	var rows: Array = UP_BODY.duplicate()
	if sleeping:
		rows[6] = SLEEP_EYES
	rows.append_array(UP_LEGS[legs])
	var pal := {
		"k": fur.get("k", "3b2a3a"), "a": fur["a"], "b": fur["b"], "e": fur.get("e", "2b2233"),
		"p": "ff8fab", "c": "f7b2c0", "s": o["s"], "t": o["t"], "w": o["w"], "l": o["l"], "o": "4a3434",
	}
	match fur.get("pat", ""):
		"fold":
			rows[2] = "............"
			rows[3] = ".kkk...kkk.."
	var img := grid(rows, pal)
	var px := func(x: int, y: int, col: String) -> void: img.set_pixel(x, y, Color(col))
	var fa := Color(fur["a"])
	var fb: String = fur["b"]
	var pat_pts := []
	match fur.get("pat", ""):
		"tux":
			pat_pts = [[3, 7], [6, 7], [2, 8], [3, 8], [4, 8], [5, 8], [6, 8], [7, 8]]
		"stripes":
			pat_pts = [[3, 5], [6, 5], [1, 7], [8, 7], [2, 4], [7, 4]]
		"spots":
			pat_pts = [[2, 5], [7, 5], [6, 8], [1, 8]]
		"mask":
			pat_pts = [[3, 6], [4, 6], [5, 6], [6, 6], [3, 7], [6, 7], [4, 8], [5, 8]]
		"patch":
			pat_pts = [[1, 5], [2, 5], [3, 5], [1, 7], [2, 8]]
	for pt in pat_pts:
		if img.get_pixel(pt[0], pt[1]).is_equal_approx(fa):
			img.set_pixel(pt[0], pt[1], Color(fb))
	if o.get("glasses", false) and not sleeping:
		for x in [1, 3, 6, 8]:
			px.call(x, 6, "cfe9ff")
		px.call(4, 6, "3b2a3a")
		px.call(5, 6, "3b2a3a")
	if o.get("shades", false) and not sleeping:
		for x in [1, 2, 3, 4, 5, 6, 7, 8]:
			px.call(x, 6, "1e1e2a")
		px.call(1, 6, "4a4a66")
		px.call(6, 6, "4a4a66")
	if o.get("phones", false):
		for x in range(3, 7):
			px.call(x, 3, "2b2b3a")
		for y in [5, 6]:
			px.call(0, y, "5fd3c8")
			px.call(9, y, "5fd3c8")
	if o.get("goggles", false) and not sleeping:
		for x in [1, 2, 3, 6, 7, 8]:
			px.call(x, 6, "a8e4f4")
		px.call(4, 6, "3b2a3a")
		px.call(5, 6, "3b2a3a")
	if o.get("mask", false):
		for x in range(2, 8):
			px.call(x, 7, "f4f7fb")
		for x in range(3, 7):
			px.call(x, 8, "f4f7fb")
	if o.get("steth", false):
		px.call(3, 10, "6a6478")
		px.call(3, 11, "6a6478")
		px.call(4, 12, "6a6478")
		px.call(6, 11, "e45b6b")
	if o.get("badge", false) and not o.has("hat"):
		px.call(3, 10, "ffd75e")
	if o.has("hat"):
		var hat := Image.create_empty(12, 16, false, Image.FORMAT_RGBA8)
		for r in HATS[o["hat"]]:
			hat.fill_rect(Rect2i(r[0], r[1], r[2], r[3]), Color(o["hc"]))
		if o["hat"] == "hard":
			hat.set_pixel(3, 1, Color("fff3a0"))
		if o["hat"] == "grad":
			hat.set_pixel(8, 3, Color("ffd23f"))
		if o["hat"] == "sombrero":
			hat.set_pixel(4, 2, Color("e45b6b")); hat.set_pixel(5, 2, Color("5fae73"))
		if o.get("badge", false):
			hat.set_pixel(4, 2, Color("ffd75e"))
		outline(hat)
		# только верх головы — чтобы не закрыть глаза
		img.blend_rect(hat, Rect2i(0, 0, 12, 6), Vector2i(0, 0))
	return img


## Набор кадров котика: stand / walkA / walkB / sleep, каждый [вправо, влево].
func cat_set(color_key: String, outfit_key: String) -> Dictionary:
	var key := color_key + "|" + outfit_key
	if _cat_cache.has(key):
		return _cat_cache[key]
	var fur: Dictionary = D.CAT_COLORS.get(color_key, D.CAT_COLORS["ginger"])
	var o := outfit(outfit_key)
	var out := {}
	for f in [["stand", "stand", false], ["walkA", "walkA", false], ["walkB", "walkB", false], ["sleep", "stand", true]]:
		var t := tex(make_cat_frame(fur, o, f[1], f[2]))
		out[f[0]] = [t, flipped(t)]
	_cat_cache[key] = out
	return out


# ---------- Машины ----------
func vehicle(kind: String, col_hex: String) -> Dictionary:
	var key := kind + "|" + col_hex
	if _veh_cache.has(key):
		return _veh_cache[key]
	var van := not (kind == "car" or kind == "police" or kind == "taxi")
	var col := Color(col_hex)
	var sh := col.darkened(0.18)
	var glass := Color("bfe6f7")
	var dark := Color("3b3b4a")
	var wheel := Color("2b2b33")
	var deco := func(p: Painter, view: String) -> void:
		match kind:
			"police":
				if view == "side":
					p.R(1, 6, 14, 1, "3d5a98")
					p.R(6, 0, 4, 1, "d8d4e4")
				else:
					p.R(1, 7, 10, 1, "3d5a98")
					p.R(4, 1, 4, 1, "d8d4e4")
			"ambulance":
				if view == "side":
					p.R(1, 6, 14, 1, "e45b6b")
					p.R(6, 3, 1, 3, "e45b6b")
					p.R(5, 4, 3, 1, "e45b6b")
					p.R(3, 1, 10, 1, "d8d4e4")
				else:
					p.R(1, 8, 10, 1, "e45b6b")
					p.R(3, 0, 6, 1, "d8d4e4")
			"fire":
				if view == "side":
					p.R(2, 1, 10, 1, "d8d4e4")
					for x in range(3, 12, 2):
						p.P(x, 0, "d8d4e4")
					p.R(1, 7, 14, 1, "ffe066")
				else:
					p.R(1, 8, 10, 1, "ffe066")
					p.R(3, 0, 6, 1, "d8d4e4")
			"mail":
				if view == "side":
					p.R(1, 6, 14, 1, "ffd75e")
					p.R(4, 3, 3, 2, "ffffff")
				else:
					p.R(1, 8, 10, 1, "ffd75e")
			"taxi":
				if view == "side":
					p.R(6, 0, 4, 1, "2b2b3a"); p.P(7, 0, "ffffff")
					for x in range(2, 14, 2):
						p.P(x, 6, "2b2b3a")
				else:
					p.R(4, 1, 4, 1, "2b2b3a")
			"cargo":
				# грузовик: белая кабина и кузов цвета груза
				if view == "side":
					p.R(1, 1, 10, 8, col); p.R(1, 4, 10, 1, col.lightened(0.35)); p.R(10, 1, 1, 8, sh)
					p.R(11, 3, 4, 6, "f4f6fb"); p.R(12, 4, 2, 2, glass); p.P(14, 7, "fff6c2")
					p.R(1, 8, 14, 1, sh)
				elif view == "back":
					p.R(1, 1, 10, 8, col); p.R(6, 2, 1, 6, sh); p.R(1, 1, 10, 1, col.lightened(0.35))
					p.P(2, 7, "ff6b6b"); p.P(9, 7, "ff6b6b")
				else:
					p.R(1, 0, 10, 2, col)
			"bus":
				if view == "side":
					p.R(1, 6, 14, 1, dark)
				else:
					p.R(1, 8, 10, 1, dark)
	var side_fn := func(p: Painter) -> void:
		if not van:
			p.R(1, 5, 14, 3, col)
			p.R(2, 4, 13, 1, col)
			p.R(4, 1, 8, 3, col)
			p.R(5, 2, 2, 2, glass)
			p.R(8, 2, 3, 2, glass)
			p.R(1, 7, 14, 1, sh)
			p.P(14, 5, "fff6c2")
			p.P(1, 5, "ff6b6b")
			deco.call(p, "side")
			p.C(4.5, 8.5, 1.7, wheel)
			p.C(11.5, 8.5, 1.7, wheel)
			p.P(4, 8, "aaaaaa")
			p.P(11, 8, "aaaaaa")
		else:
			p.R(1, 2, 14, 7, col)
			p.R(1, 8, 14, 1, sh)
			if kind == "bus":
				for x in range(2, 11, 3):
					p.R(x, 3, 2, 2, glass)
			else:
				p.R(3, 3, 3, 2, glass)
				p.R(7, 3, 3, 2, glass)
			p.R(12, 3, 2, 3, glass)
			p.P(14, 7, "fff6c2")
			p.P(1, 7, "ff6b6b")
			deco.call(p, "side")
			p.C(4.5, 9.5, 1.7, wheel)
			p.C(11.5, 9.5, 1.7, wheel)
			p.P(4, 9, "aaaaaa")
			p.P(11, 9, "aaaaaa")
	var fb_fn := func(p: Painter, back: bool) -> void:
		if not van:
			p.R(1, 5, 10, 4, col)
			p.R(2, 2, 8, 3, col)
			p.R(3, 2, 6, 2, glass)
			p.R(1, 8, 10, 1, sh)
			if back:
				p.P(2, 6, "ff6b6b")
				p.P(9, 6, "ff6b6b")
				p.R(5, 7, 2, 1, "ffffff")
			else:
				p.P(2, 6, "fff6c2")
				p.P(9, 6, "fff6c2")
				p.R(4, 7, 4, 1, dark)
			deco.call(p, "fb")
			p.R(1, 9, 2, 2, wheel)
			p.R(9, 9, 2, 2, wheel)
		else:
			p.R(1, 1, 10, 8, col)
			p.R(1, 9, 10, 1, sh)
			if back:
				p.R(2, 2, 3, 2, glass)
				p.R(7, 2, 3, 2, glass)
				p.P(2, 7, "ff6b6b")
				p.P(9, 7, "ff6b6b")
			else:
				p.R(2, 2, 8, 3, glass)
				p.P(2, 7, "fff6c2")
				p.P(9, 7, "fff6c2")
				p.R(4, 7, 4, 1, dark)
			deco.call(p, "back" if back else "fb")
			p.R(1, 10, 2, 2, wheel)
			p.R(9, 10, 2, 2, wheel)
	var side := drawn(16, 12 if van else 10, side_fn)
	var front := drawn(12, 12 if van else 11, func(p): fb_fn.call(p, false))
	var back := drawn(12, 12 if van else 11, func(p): fb_fn.call(p, true))
	var lights = null
	if kind == "police":
		lights = {"side": [[6, 0], [8, 0]], "fb": [[4, 1], [6, 1]]}
	elif kind == "ambulance" or kind == "fire":
		lights = {"side": [[3, 1], [11, 1]], "fb": [[3, 0], [7, 0]]}
	var res := {
		"side": [side, flipped(side)], "front": front, "back": back,
		"driver": {"side": Vector2i(12, 3), "front": Vector2i(5, 2)} if van else {"side": Vector2i(8, 2), "front": Vector2i(5, 2)},
		"lights": lights,
	}
	_veh_cache[key] = res
	return res


# ---------- построение всего набора ----------
func _init() -> void:
	scaffold[1] = _make_scaffold(16, 20)
	scaffold[2] = _make_scaffold(32, 34)
	scaffold[3] = _make_scaffold(48, 46)
	_make_nature()
	_make_homes()
	_make_work()
	_make_city()
	_make_fun()
	_make_la()
	_make_more()
	_make_parking()
	_make_icons()
	_make_generated()


func _make_scaffold(w: int, h: int) -> ImageTexture:
	return drawn(w, h, func(p: Painter) -> void:
		p.R(1, h - 3, w - 2, 3, "c9c4d6")
		p.R(3, 6, w - 6, h - 9, "bfe8c8")
		for y in range(7, h - 3, 2):
			for x in range(3 + (1 if y % 4 == 1 else 0), w - 3, 2):
				p.P(x, y, "a0d8b0")
		var poles := [2, 13] if w == 16 else ([2, 15, 29] if w == 32 else [2, 17, 31, 45])
		for x in poles:
			p.R(x, 3, 1, h - 6, "8a5a3b")
		var y2 := h - 6
		while y2 > 3:
			p.R(1, y2, w - 2, 1, "c08f5f")
			y2 -= 6
	, false, Rect2i(1, h - 1, w - 2, 1))


func _round_tree(dark: String, main: String, light: String) -> ImageTexture:
	return drawn(16, 24, func(p: Painter) -> void:
		p.R(7, 15, 2, 7, "8a5a3b")
		p.R(7, 15, 1, 7, "a0704a")
		p.C(8, 10.5, 6.2, dark)
		p.C(8, 9.5, 5.6, main)
		p.C(6.2, 7.2, 2.4, light)
		p.P(10, 12, dark)
		p.P(5, 12, dark)
		p.P(11, 7, light)
		p.P(9, 5, light)
	, true, Rect2i(3, 22, 10, 2))


func _palm(h: int, lean: float) -> ImageTexture:
	return drawn(16, h, func(p: Painter) -> void:
		var top := 9
		var span := float(h - 2 - top)
		for y in range(top, h - 2):
			var t := float(y - top) / span
			var x := 7 + roundi(lean * (1.0 - t) * (1.0 - t) * 3.0)
			p.R(x, y, 2, 1, "a0764a")
			if y % 3 == 0:
				p.P(x, y, "7f5a38")
		var cx := 8 + roundi(lean * 3.0)
		p.P(cx - 1, top + 1, "7a5236")
		p.P(cx + 1, top + 1, "7a5236")
		for lv in [[-1.0, -0.35], [1.0, -0.35], [-1.0, 0.15], [1.0, 0.15], [-0.6, -0.9], [0.6, -0.9], [-0.35, 0.6], [0.35, 0.6]]:
			for k in 8:
				var x2 := roundi(cx + lv[0] * k)
				var y2 := roundi(top + lv[1] * k + 0.06 * k * k)
				p.P(x2, y2, "4fae5a" if k < 5 else "3a8f4a")
				if k > 1 and k < 6:
					p.P(x2, y2 + 1, "3a8f4a")
	, true, Rect2i(4, h - 2, 8, 2))


func _make_nature() -> void:
	var fan := drawn(16, 24, func(p: Painter) -> void:
		p.R(7, 12, 3, 10, "a0764a")
		for y in range(13, 22, 2):
			p.R(7, y, 3, 1, "7f5a38")
		p.C(8.5, 8, 6.2, "3a8f4a")
		p.C(8.5, 7.5, 5.4, "5fbf6a")
		for a in 9:
			var ang := PI + a * PI / 8.0
			for k in range(2, 6):
				p.P(roundi(8.5 + cos(ang) * k), roundi(7.5 + sin(ang) * k * 0.9), "3a8f4a")
	, true, Rect2i(4, 22, 9, 2))
	palms = [_palm(40, 0.6), _palm(32, -0.5), fan]
	trees = palms
	obj["jacaranda"] = _round_tree("7a5aa8", "9b7ad1", "c8b0f0")
	obj["agave"] = drawn(16, 16, func(p: Painter) -> void:
		for lv in [[-1.0, -0.2], [1.0, -0.2], [-0.6, -0.8], [0.6, -0.8], [0.0, -1.0], [-0.9, -0.5], [0.9, -0.5]]:
			for k in 7:
				var c := "8cc4b0" if k < 4 else "5f9a88"
				p.P(roundi(8 + lv[0] * k), roundi(13 + lv[1] * k), c)
				if k < 4:
					p.P(roundi(8 + lv[0] * k) + (1 if lv[0] >= 0 else -1), roundi(13 + lv[1] * k), "7fb8a4")
	, true, Rect2i(3, 15, 10, 1))
	obj["rock"] = drawn(16, 16, func(p: Painter) -> void:
		p.C(7, 11, 3.6, "b8aa98")
		p.C(10.5, 12, 2.8, "a89a88")
		p.C(6.5, 10, 1.6, "d4c8b8")
	, true, Rect2i(3, 15, 10, 1))


func _make_homes() -> void:
	bld("house", 16, 24, func(p: Painter) -> void:
		p.R(2, 13, 12, 10, "fbe8cf"); p.R(2, 21, 12, 2, "ead2b2")
		for y in range(6, 13):
			var hw := y - 6
			p.R(7 - hw, y, 2 + 2 * hw, 1, "c95f73" if y >= 11 else "e07a8a")
		p.P(3, 6, "e07a8a"); p.R(3, 7, 2, 1, "e07a8a"); p.R(3, 8, 3, 1, "e07a8a"); p.P(4, 8, "ffc2d1")
		p.P(12, 6, "e07a8a"); p.R(11, 7, 2, 1, "e07a8a"); p.R(10, 8, 3, 1, "e07a8a"); p.P(11, 8, "ffc2d1")
		p.P(7, 8, "f29aa8"); p.P(5, 10, "f29aa8"); p.P(10, 10, "f29aa8"); p.P(8, 11, "f29aa8")
		p.R(6, 17, 4, 6, "a0603a"); p.R(6, 17, 4, 1, "b8774d"); p.P(8, 20, "ffd75e")
		p.R(2, 14, 4, 4, "b8774d"); p.win(3, 15, 2, 2)
		p.R(10, 14, 4, 4, "b8774d"); p.win(11, 15, 2, 2)
		p.R(10, 18, 4, 1, "8a5a3b"); p.P(10, 17, "ff8fab"); p.P(13, 17, "fff3a0")
	)
	bld("cottage", 32, 40, func(p: Painter) -> void:
		p.R(3, 20, 26, 17, "cfe6f5"); p.R(3, 34, 26, 3, "b5d4ea")
		for y in range(8, 21):
			var hw := roundi((y - 7) * 15.0 / 13.0)
			p.R(16 - hw, y, hw * 2, 1, "5a6fb0" if y >= 19 else "7088cc")
		p.P(7, 8, "7088cc"); p.R(7, 9, 2, 1, "7088cc"); p.R(7, 10, 3, 1, "7088cc"); p.R(7, 11, 4, 1, "7088cc"); p.P(8, 10, "ffc2d1")
		p.P(24, 8, "7088cc"); p.R(23, 9, 2, 1, "7088cc"); p.R(22, 10, 3, 1, "7088cc"); p.R(21, 11, 4, 1, "7088cc"); p.P(23, 10, "ffc2d1")
		p.P(12, 14, "8aa0dc"); p.P(18, 12, "8aa0dc"); p.P(9, 17, "8aa0dc"); p.P(22, 16, "8aa0dc")
		p.win(14, 14, 4, 3)
		p.R(13, 27, 6, 1, "7088cc"); p.R(14, 28, 4, 9, "a0603a"); p.P(17, 32, "ffd75e")
		p.R(4, 23, 6, 6, "ffffff"); p.win(5, 24, 4, 4)
		p.R(22, 23, 6, 6, "ffffff"); p.win(23, 24, 4, 4)
		p.R(5, 29, 4, 1, "8a5a3b"); p.P(5, 28, "ff8fab"); p.P(8, 28, "fff3a0")
		p.R(23, 29, 4, 1, "8a5a3b"); p.P(23, 28, "c8a8ff"); p.P(26, 28, "ff8fab")
		for x in range(1, 31, 3):
			if x < 12 or x > 19:
				p.R(x, 35, 1, 4, "fff4e6")
		p.R(1, 36, 11, 1, "fff4e6"); p.R(20, 36, 11, 1, "fff4e6")
	)
	bld("apartments", 32, 54, func(p: Painter) -> void:
		p.R(2, 10, 28, 42, "f7d6c4"); p.R(2, 10, 28, 1, "ffe6d8")
		for y in [12, 19, 26, 33]:
			p.win(4, y, 4, 4); p.win(10, y, 4, 4); p.win(18, y, 4, 4); p.win(24, y, 4, 4)
			p.R(9, y + 4, 6, 1, "c8a8ff"); p.R(17, y + 4, 6, 1, "9ed8c8")
		p.win(4, 42, 4, 4); p.win(24, 42, 4, 4)
		p.R(11, 41, 10, 2, "9ed8c8"); p.R(13, 43, 6, 9, "a0603a"); p.R(15, 43, 2, 9, "8a5030")
		p.R(1, 8, 30, 2, "b88a7a")
		p.P(3, 5, "b88a7a"); p.R(3, 6, 2, 1, "b88a7a"); p.R(3, 7, 3, 1, "b88a7a")
		p.P(28, 5, "b88a7a"); p.R(27, 6, 2, 1, "b88a7a"); p.R(26, 7, 3, 1, "b88a7a")
		p.C(16, 6, 2, "d8d4e4"); p.R(16, 3, 1, 3, "9aa5b8")
	)


func _make_work() -> void:
	bld("pier", 16, 16, func(p: Painter) -> void:
		p.R(1, 5, 14, 9, "c08f5f"); p.R(1, 5, 14, 1, "d8a874")
		p.R(1, 8, 14, 1, "a5764a"); p.R(1, 11, 14, 1, "a5764a")
		p.R(2, 14, 2, 2, "7a5236"); p.R(12, 14, 2, 2, "7a5236")
		p.R(3, 8, 4, 4, "8fb4d4"); p.R(2, 8, 6, 1, "b8d4ea")
		p.R(4, 6, 1, 2, "f2a65a"); p.P(3, 5, "f2a65a"); p.P(5, 5, "f2a65a"); p.P(6, 7, "7fc4e8")
		for pt in [[9, 11], [10, 9], [11, 7], [12, 5], [13, 3], [14, 1]]:
			p.P(pt[0], pt[1], "6b4a2f"); p.P(pt[0], pt[1] + 1, "6b4a2f")
	)
	bld("shop", 16, 22, func(p: Painter) -> void:
		p.R(3, 9, 10, 6, "6e4f63")
		p.wins.append(Rect2i(3, 9, 10, 3))
		p.R(2, 8, 1, 13, "8a5a3b"); p.R(13, 8, 1, 13, "8a5a3b")
		p.R(2, 3, 12, 1, "d96a8a")
		for x in range(1, 15):
			var pink := ((x - 1) >> 1) % 2 == 0
			var c := "f48aa8" if pink else "fff4f6"
			p.R(x, 4, 1, 5, c)
			if pink:
				p.R(x, 9, 1, 1, c)
		p.R(1, 15, 14, 6, "c99a6b"); p.R(1, 15, 14, 1, "e0b88a"); p.R(1, 18, 14, 1, "b38558")
		p.C(4.5, 13.5, 1.8, "e45b6b"); p.C(8, 13.5, 1.8, "5b8de4"); p.C(11.5, 13.5, 1.8, "f2c14e")
		p.P(4, 12, "ff9aa5"); p.P(7, 12, "8fb3f2"); p.P(11, 12, "ffe08a")
	)
	bld("bakery", 16, 24, func(p: Painter) -> void:
		p.R(2, 10, 12, 13, "fbe3c0"); p.R(2, 21, 12, 2, "ecc9a0")
		p.R(1, 7, 14, 3, "a0603a"); p.R(1, 9, 14, 1, "8a5a3b")
		p.R(4, 4, 8, 3, "e0a050"); p.R(5, 3, 6, 1, "e0a050"); p.P(6, 4, "f2c88a"); p.P(8, 4, "f2c88a"); p.P(10, 4, "f2c88a")
		for x in range(1, 15):
			p.R(x, 12, 1, 2, "ffd75e" if x % 2 else "ffffff")
		p.win(3, 15, 5, 4, "fff1b0"); p.P(4, 18, "e0a050"); p.R(5, 18, 2, 1, "e0a050")
		p.R(10, 16, 3, 7, "a0603a"); p.P(12, 19, "ffd75e")
	)
	bld("cafe", 16, 24, func(p: Painter) -> void:
		p.R(1, 11, 14, 12, "a8dccd"); p.R(1, 21, 14, 2, "86c4b2")
		p.R(1, 9, 14, 2, "6a9e96")
		p.R(4, 3, 8, 6, "fff4e0"); p.P(4, 1, "fff4e0"); p.R(4, 2, 2, 1, "fff4e0"); p.P(11, 1, "fff4e0"); p.R(10, 2, 2, 1, "fff4e0")
		p.P(6, 5, INK); p.P(9, 5, INK); p.R(7, 6, 2, 1, "ff8fab"); p.P(5, 6, "f7b2c0"); p.P(10, 6, "f7b2c0")
		for x in range(1, 15):
			p.R(x, 11, 1, 2, "ffffff" if x % 2 else "e07a8a")
		p.win(2, 14, 3, 2, "fff1b0"); p.win(6, 14, 3, 2, "fff1b0"); p.win(2, 17, 3, 2, "fff1b0"); p.win(6, 17, 3, 2, "fff1b0")
		p.R(5, 14, 1, 5, "86c4b2"); p.R(2, 16, 7, 1, "86c4b2")
		p.R(10, 15, 4, 8, "a0603a"); p.R(10, 15, 4, 1, "b8774d"); p.P(11, 19, "ffd75e")
	)
	bld("office", 32, 50, func(p: Painter) -> void:
		p.R(3, 8, 26, 40, "cfd8e6"); p.R(3, 8, 26, 1, "e6ecf5"); p.R(3, 46, 26, 2, "b5c0d0")
		for y in [11, 17, 23, 29]:
			for x in [5, 11, 17, 23]:
				p.win(x, y, 4, 4, "8fb8d8")
		p.R(9, 35, 14, 2, "3d5a98")
		for x in range(11, 21, 2):
			p.P(x, 35, "ffffff")
		p.R(10, 39, 12, 9, "8fb8d8"); p.R(15, 39, 2, 9, "cfd8e6"); p.R(10, 39, 12, 1, "b5c0d0")
		p.R(2, 6, 28, 2, "9aa5b8"); p.R(24, 1, 1, 5, "6a6478"); p.P(24, 0, "ff6b6b")
		p.R(5, 3, 6, 3, "9aa5b8")
	)
	bld("factory", 32, 44, func(p: Painter) -> void:
		p.R(1, 22, 30, 20, "e8b4a0"); p.R(1, 22, 30, 1, "f2c8b6")
		for y in range(25, 41, 3):
			for x in range(2 + (y % 2) * 2, 30, 5):
				p.R(x, y, 2, 1, "d89c88")
		for k in 3:
			var x0 := 1 + k * 10
			for y in range(14, 22):
				var ln := maxi(1, roundi((y - 13) * 10.0 / 8.0))
				p.R(x0 + 10 - ln, y, ln, 1, "8a8fb0")
			p.R(x0 + 9, 14, 1, 8, "bfe3f2")
		p.R(25, 4, 4, 18, "a05a4a"); p.R(25, 4, 4, 1, "c07060"); p.R(25, 8, 4, 1, "fff4e6"); p.R(25, 12, 4, 1, "fff4e6")
		p.R(4, 30, 9, 12, "8a8fb0")
		for y in range(31, 42, 2):
			p.R(4, y, 9, 1, "7a7fa0")
		p.win(16, 26, 4, 4); p.win(22, 26, 4, 4)
		p.C(23, 36, 2.8, "ff8fab"); p.P(22, 35, "ffc2d1"); p.P(24, 37, "e07a9c"); p.R(16, 34, 3, 1, "ff8fab")
	)
	bld("construction", 32, 44, func(p: Painter) -> void:
		p.R(22, 4, 2, 34, "ffb020")
		for y in range(6, 38, 3):
			p.P(22, y, "e08a00"); p.P(23, y + 1, "e08a00")
		p.R(8, 4, 24, 2, "ffb020")
		for x in range(9, 31, 3):
			p.P(x, 5, "e08a00")
		p.R(27, 6, 4, 4, "6a6478")
		p.R(11, 6, 1, 9, "6a6478"); p.R(10, 15, 3, 2, "6a6478")
		p.R(19, 6, 4, 3, "ffd75e")
		p.R(2, 26, 13, 12, "5b8de4"); p.R(2, 25, 13, 1, "3d5a98"); p.win(4, 28, 4, 3); p.R(10, 29, 3, 9, "3d5a98")
		p.R(16, 32, 6, 6, "d9734f"); p.R(16, 34, 6, 1, "b85a3c"); p.R(16, 36, 6, 1, "b85a3c"); p.R(18, 32, 1, 2, "b85a3c")
		p.R(1, 38, 30, 4, "ffd75e")
		for x in range(1, 31, 4):
			p.R(x, 38, 2, 4, "3b3b4a")
		p.P(26, 36, "ff7a3a"); p.P(27, 35, "ff7a3a"); p.R(25, 37, 3, 1, "ff7a3a")
	)


func _make_city() -> void:
	bld("townhall", 32, 46, func(p: Painter) -> void:
		p.C(16, 7, 4.2, "7aa0e8")
		p.R(12, 7, 8, 8, "f4ead8"); p.C(16, 10, 2.4, "ffffff"); p.P(16, 9, INK); p.P(16, 10, INK); p.P(17, 10, INK)
		p.R(16, 0, 1, 4, "6b4a2f"); p.R(17, 0, 3, 2, "ff6b8b")
		for y in range(14, 22):
			var hw := roundi(2 + (y - 14) * 13.0 / 7.0)
			p.R(16 - hw, y, hw * 2, 1, "d8ccb6" if y == 21 else "e8dcc6")
		p.P(15, 18, "ff9fb5"); p.P(16, 18, "ff9fb5"); p.P(14, 17, "ff9fb5"); p.P(17, 17, "ff9fb5")
		p.R(3, 22, 26, 18, "f4ead8")
		p.win(7, 27, 2, 5); p.win(11, 27, 2, 5); p.win(20, 27, 2, 5); p.win(24, 27, 2, 5)
		for x in [5, 9, 13, 18, 22, 26]:
			p.R(x, 23, 2, 17, "ffffff"); p.P(x + 1, 23, "e6dccb"); p.R(x + 1, 25, 1, 15, "e6dccb")
		p.R(14, 31, 4, 9, "8a5a3b"); p.P(16, 35, "ffd75e")
		p.R(6, 40, 20, 2, "e6e2f0"); p.R(4, 42, 24, 3, "d8d4e4")
	)
	bld("school", 32, 44, func(p: Painter) -> void:
		for y in range(14, 21):
			var ins := 20 - y
			p.R(1 + ins, y, 30 - ins * 2, 1, "6b6f9a")
		p.R(1, 20, 30, 22, "f2a477"); p.R(1, 40, 30, 2, "e08a5e")
		for y in range(23, 40, 3):
			for x in range(2 + (y % 2) * 3, 30, 6):
				p.R(x, y, 2, 1, "e8956b")
		p.R(12, 6, 8, 15, "f2a477")
		for y in range(1, 7):
			p.R(16 - y, y, y * 2, 1, "6b6f9a")
		p.R(15, 8, 2, 2, "ffd75e")
		p.C(16, 14, 2.4, "ffffff"); p.P(16, 13, INK); p.P(16, 14, INK); p.P(17, 14, INK)
		p.R(11, 21, 10, 2, "fff4e0"); p.P(13, 21, "e45b6b"); p.P(16, 21, "5b8de4"); p.P(19, 21, "5fae73")
		for x in [3, 7, 22, 26]:
			p.win(x, 25, 3, 4); p.win(x, 33, 3, 4)
		p.win(14, 25, 4, 4)
		p.R(13, 32, 6, 10, "8a5a3b"); p.R(16, 32, 1, 10, "6b4a2f")
		p.R(12, 42, 8, 2, "d8d4e4")
	)
	bld("hospital", 32, 44, func(p: Painter) -> void:
		p.R(12, 3, 8, 8, "ffffff"); p.R(15, 4, 2, 6, "e45b6b"); p.R(13, 6, 6, 2, "e45b6b")
		p.R(0, 11, 32, 2, "9aa5b8")
		p.R(1, 13, 30, 29, "f6f8fb"); p.R(1, 21, 30, 1, "9ed8c8"); p.R(1, 30, 30, 1, "9ed8c8")
		for y in [15, 24]:
			for x in [3, 8, 20, 25]:
				p.win(x, y, 4, 4)
			p.win(13, y, 6, 4)
		p.R(10, 32, 12, 2, "e45b6b")
		p.R(12, 34, 8, 8, "9fd3e6"); p.R(15, 34, 2, 8, "cfd8e4")
		p.R(3, 35, 5, 5, "ffffff"); p.R(5, 36, 1, 3, "e45b6b"); p.R(4, 37, 3, 1, "e45b6b")
	)
	bld("police", 16, 26, func(p: Painter) -> void:
		p.R(2, 10, 12, 15, "9fb8e8"); p.R(2, 22, 12, 3, "7f9ad0")
		p.R(1, 8, 14, 2, "3d5a98"); p.R(6, 6, 4, 2, "3d5a98"); p.R(6, 5, 2, 1, "ff6b6b"); p.R(8, 5, 2, 1, "5b8de4")
		p.P(7, 11, "ffd75e"); p.P(8, 11, "ffd75e"); p.R(6, 12, 4, 1, "ffd75e"); p.P(7, 13, "ffd75e"); p.P(8, 13, "ffd75e"); p.P(6, 14, "ffd75e"); p.P(9, 14, "ffd75e")
		p.win(3, 16, 2, 4); p.win(11, 16, 2, 4)
		p.R(6, 18, 4, 7, "3d5a98"); p.P(9, 21, "ffd75e")
	)
	bld("fire", 16, 28, func(p: Painter) -> void:
		p.R(10, 2, 4, 8, "e05a4a"); p.R(9, 1, 6, 1, "a03a2a"); p.R(11, 4, 2, 2, "ffd75e")
		p.R(1, 8, 14, 2, "a03a2a")
		p.R(1, 10, 14, 17, "e05a4a"); p.R(1, 10, 14, 1, "f07a6a")
		p.win(3, 12, 3, 3); p.win(10, 12, 3, 3)
		p.R(3, 17, 10, 10, "f4e6d8")
		for y in range(18, 27, 2):
			p.R(3, y, 10, 1, "d8c4b0")
	)
	bld("post", 16, 24, func(p: Painter) -> void:
		p.R(5, 3, 6, 4, "ffffff"); p.P(6, 4, "5b8de4"); p.P(7, 5, "5b8de4"); p.P(8, 5, "5b8de4"); p.P(9, 4, "5b8de4")
		p.R(1, 7, 14, 2, "3d5a98")
		p.R(2, 9, 12, 14, "fff4e0"); p.R(2, 9, 12, 2, "5b8de4"); p.R(2, 11, 12, 1, "ffd75e")
		p.win(3, 14, 4, 4)
		p.R(9, 15, 4, 8, "5b8de4"); p.P(12, 19, "ffd75e")
		p.R(3, 19, 3, 4, "3d6ac0"); p.R(3, 19, 3, 1, "ffd75e")
	)
	bld("library", 16, 26, func(p: Painter) -> void:
		for y in range(5, 12):
			var hw := 1 + (y - 5)
			p.R(8 - hw, y, hw * 2, 1, "8f6fc4")
		p.R(6, 8, 4, 3, "ffffff"); p.R(8, 8, 1, 3, "8a5a3b")
		p.R(2, 12, 12, 13, "c9a0d8"); p.R(2, 23, 12, 2, "b088c4")
		p.R(3, 13, 1, 12, "ffffff"); p.R(12, 13, 1, 12, "ffffff")
		p.win(5, 14, 2, 3, "fff1b0"); p.win(9, 14, 2, 3, "fff1b0")
		p.R(6, 18, 4, 7, "8a5a3b"); p.P(8, 21, "ffd75e")
	)


func _make_fun() -> void:
	obj["cattree"] = drawn(16, 24, func(p: Painter) -> void:
		p.R(3, 21, 10, 2, "8f6fc4"); p.R(3, 21, 10, 1, "a98ae0")
		p.R(7, 6, 2, 15, "e6c99a")
		for y in range(7, 21, 2):
			p.R(7, y, 2, 1, "cfae7c")
		p.R(2, 15, 6, 2, "8f6fc4"); p.R(2, 15, 6, 1, "a98ae0")
		p.R(9, 10, 5, 2, "8f6fc4"); p.R(9, 10, 5, 1, "a98ae0")
		p.R(4, 3, 8, 3, "8f6fc4"); p.R(5, 3, 6, 1, "c2a8ef")
		p.R(13, 12, 1, 3, "fff4f6"); p.C(13.5, 16.5, 1.5, "ff8fab")
	, true, Rect2i(2, 23, 12, 1))
	var fpos := [
		[[4, 7], [8, 6], [12, 8], [6, 10], [10, 11]],
		[[3, 9], [7, 7], [11, 6], [9, 10], [13, 10]],
		[[5, 6], [10, 8], [3, 11], [7, 11], [12, 11]],
	]
	var fcol := ["ff8fab", "fff3a0", "c8a8ff", "ffffff", "ff9f6b"]
	for v in 3:
		flowers.append(drawn(16, 16, func(p: Painter) -> void:
			p.R(2, 9, 12, 5, "9a6b4a"); p.R(1, 10, 14, 3, "9a6b4a"); p.R(2, 9, 12, 1, "b07f5a")
			var k := 0
			for f in fpos[v]:
				var c: String = fcol[(k + v * 2) % fcol.size()]
				var x: int = f[0]
				var y: int = f[1]
				p.P(x, y + 1, "5f9e4f"); p.P(x, y + 2, "5f9e4f"); p.P(x + 1, y + 2, "7cc46a")
				p.P(x - 1, y, c); p.P(x + 1, y, c); p.P(x, y - 1, c); p.P(x, y + 1, c)
				p.P(x, y, "ffd75e")
				k += 1
		))
	obj["fountain"] = drawn(16, 20, func(p: Painter) -> void:
		p.R(3, 12, 10, 1, "c9c4d6"); p.R(1, 13, 14, 5, "c9c4d6"); p.R(3, 18, 10, 1, "c9c4d6")
		p.R(2, 13, 12, 1, "e2deec"); p.R(1, 17, 14, 1, "aaa4bc")
		p.R(3, 14, 10, 3, "74c3e6"); p.R(4, 14, 8, 1, "a5def2")
		p.R(7, 6, 2, 8, "c9c4d6"); p.R(7, 6, 1, 8, "e2deec")
		p.R(5, 6, 6, 2, "c9c4d6"); p.R(5, 6, 6, 1, "e2deec"); p.R(6, 6, 4, 1, "74c3e6")
		p.R(7, 3, 2, 3, "a5def2"); p.R(6, 2, 4, 1, "cfeff9")
	, true, Rect2i(2, 19, 12, 1))
	obj["lantern"] = drawn(16, 24, func(p: Painter) -> void:
		p.R(6, 21, 4, 2, "4a4458"); p.R(7, 9, 2, 12, "4a4458"); p.R(8, 9, 1, 12, "6a6478")
		p.R(5, 3, 6, 6, "4a4458"); p.R(6, 3, 4, 5, "ffe7a3"); p.R(7, 4, 2, 3, "fff6d0")
		p.R(4, 2, 8, 1, "4a4458"); p.R(6, 1, 4, 1, "4a4458")
	, true, Rect2i(5, 23, 6, 1))
	windows["lantern"] = [Rect2i(6, 3, 4, 5)]
	obj["cushion"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(3, 8, 10, 5, "f4a6c0"); p.R(2, 9, 12, 3, "f4a6c0")
		p.R(4, 9, 8, 3, "ffc8d8"); p.R(5, 10, 6, 1, "ffdbe6")
		p.P(2, 8, "e07a9c"); p.P(13, 8, "e07a9c"); p.P(2, 12, "e07a9c"); p.P(13, 12, "e07a9c")
	, true, Rect2i(2, 14, 12, 1))
	obj["bench"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(2, 5, 12, 2, "c08f5f"); p.R(2, 5, 12, 1, "d8a874")
		p.R(2, 9, 12, 2, "c08f5f"); p.R(2, 9, 12, 1, "d8a874")
		p.R(3, 7, 1, 2, "4a4458"); p.R(12, 7, 1, 2, "4a4458")
		p.R(3, 11, 1, 3, "4a4458"); p.R(12, 11, 1, 3, "4a4458")
	, true, Rect2i(2, 14, 12, 1))
	obj["statue"] = drawn(16, 26, func(p: Painter) -> void:
		p.R(3, 18, 10, 6, "c9c4d6"); p.R(3, 18, 10, 1, "e2deec"); p.R(4, 21, 8, 1, "aaa4bc")
		p.C(8, 13.5, 3.6, "b9b4c7"); p.C(8, 8, 2.9, "b9b4c7")
		p.R(5, 5, 1, 2, "b9b4c7"); p.R(10, 5, 1, 2, "b9b4c7")
		p.R(11, 15, 2, 1, "b9b4c7"); p.R(12, 12, 1, 3, "b9b4c7")
		p.P(7, 8, "8a86a0"); p.P(9, 8, "8a86a0"); p.P(7, 12, "d4d0e0")
	, true, Rect2i(2, 25, 12, 1))
	obj["playground"] = drawn(32, 32, func(p: Painter) -> void:
		p.R(1, 12, 30, 19, "f7c9b0"); p.R(1, 12, 30, 1, "fadcc9")
		p.R(3, 22, 11, 7, "c0905a"); p.R(4, 23, 9, 5, "f1dfa6"); p.P(6, 24, "ff8fab"); p.R(9, 25, 2, 1, "5b8de4")
		p.R(4, 5, 1, 15, "5b8de4"); p.R(14, 5, 1, 15, "5b8de4"); p.R(4, 5, 11, 1, "5b8de4")
		p.R(7, 6, 1, 8, "9aa5b8"); p.R(11, 6, 1, 8, "9aa5b8"); p.R(6, 14, 7, 1, "ffd75e")
		p.R(19, 8, 1, 14, "e07a8a"); p.R(22, 8, 1, 14, "e07a8a")
		for y in range(10, 22, 3):
			p.R(19, y, 4, 1, "ffffff")
		p.R(18, 7, 7, 2, "ff8fab")
		for i in 12:
			p.R(24 + (i >> 1), 9 + i, 2, 1, "ffd75e")
	, true, Rect2i(1, 31, 30, 1))
	obj["tower"] = drawn(16, 32, func(p: Painter) -> void:
		p.R(3, 29, 10, 2, "8f6fc4")
		p.R(4, 12, 8, 17, "f2d6a2")
		for y in range(14, 29, 3):
			p.R(4, y, 8, 1, "e0bd82")
		p.R(5, 16, 2, 3, "9fd3e6"); p.R(9, 16, 2, 3, "9fd3e6")
		p.R(6, 23, 4, 6, "a0603a"); p.R(7, 22, 2, 1, "a0603a")
		p.R(2, 11, 12, 2, "8f6fc4"); p.R(2, 11, 12, 1, "a98ae0")
		p.R(3, 4, 10, 7, "9b7ad1"); p.R(4, 3, 8, 1, "9b7ad1")
		p.P(3, 1, "9b7ad1"); p.R(3, 2, 2, 2, "9b7ad1"); p.P(4, 3, "ffc2d1")
		p.P(12, 1, "9b7ad1"); p.R(11, 2, 2, 2, "9b7ad1"); p.P(11, 3, "ffc2d1")
		p.R(5, 6, 1, 2, INK); p.R(10, 6, 1, 2, INK); p.R(7, 8, 2, 1, "ff8fab")
		p.P(4, 8, "f7b2c0"); p.P(11, 8, "f7b2c0")
	, true, Rect2i(2, 31, 12, 1))
	windows["tower"] = [Rect2i(5, 16, 2, 3), Rect2i(9, 16, 2, 3)]


const LETTERS := {
	"K": ["x.x", "xx.", "x..", "xx.", "x.x"],
	"O": ["xxx", "x.x", "x.x", "x.x", "xxx"],
	"T": ["xxx", ".x.", ".x.", ".x.", ".x."],
	"W": ["x.x", "x.x", "x.x", "xxx", "x.x"],
	"D": ["xx.", "x.x", "x.x", "x.x", "xx."],
}


func _make_la() -> void:
	bld("villa", 32, 40, func(p: Painter) -> void:
		p.R(2, 30, 28, 8, "f4f0e8")
		p.R(5, 31, 14, 5, "5fc8e8"); p.R(6, 32, 12, 1, "a8e4f4"); p.R(9, 34, 5, 1, "a8e4f4")
		p.R(21, 32, 6, 2, "ff9fc0"); p.R(21, 34, 1, 1, "c9c4d6"); p.R(26, 34, 1, 1, "c9c4d6")
		p.R(3, 14, 26, 15, "fbfbf8"); p.R(3, 27, 26, 2, "e8e4dc")
		p.R(2, 12, 28, 2, "d8d4cc")
		p.R(12, 6, 16, 6, "fbfbf8"); p.R(11, 5, 18, 1, "d8d4cc")
		p.win(5, 17, 8, 7); p.win(15, 17, 6, 7)
		p.win(14, 7, 5, 4); p.win(21, 7, 5, 4)
		p.R(23, 19, 4, 8, "c08f5f"); p.P(24, 23, "ffd75e")
		p.R(3, 16, 1, 9, "c08f5f")
	)
	bld("icecream", 16, 26, func(p: Painter) -> void:
		p.R(2, 14, 12, 11, "ffd1e8"); p.R(2, 22, 12, 3, "f2b8d4")
		p.R(1, 12, 14, 2, "ff8fab")
		for x in range(1, 15):
			p.R(x, 14, 1, 2, "ffffff" if x % 2 else "ff8fab")
		p.win(3, 17, 10, 3, "fff6e8")
		p.R(3, 20, 10, 1, "c99a6b")
		for y in range(6, 12):
			var hw := maxi(1, 3 - (y - 6) / 2)
			p.R(8 - hw, y, hw * 2, 1, "e0a050")
		p.P(7, 7, "c08040"); p.P(9, 9, "c08040")
		p.C(8, 4.5, 3.2, "ff9fc0"); p.C(6.8, 3.6, 1.2, "ffd0e0"); p.P(8, 1, "e45b6b")
	)
	bld("gym", 16, 26, func(p: Painter) -> void:
		p.R(2, 11, 12, 14, "d8e6f0"); p.R(2, 22, 12, 3, "b8c8d8"); p.R(1, 9, 14, 2, "3d5a98")
		p.R(4, 6, 8, 1, "6a6478"); p.R(3, 4, 2, 5, "3b3b4a"); p.R(11, 4, 2, 5, "3b3b4a")
		p.win(3, 13, 10, 5)
		p.R(4, 16, 3, 1, "6a6478"); p.R(9, 16, 3, 1, "6a6478")
		p.R(6, 19, 4, 6, "3d5a98"); p.P(9, 22, "ffd75e")
		p.R(2, 19, 3, 1, "5fd38f"); p.R(11, 19, 3, 1, "5fd38f")
	)
	bld("cinema", 16, 30, func(p: Painter) -> void:
		p.R(6, 1, 4, 11, "b02e3a")
		for y in range(2, 11, 2):
			p.P(7, y, "ffe680"); p.P(8, y + 1, "ffe680")
		p.R(2, 12, 12, 17, "e8d4b0"); p.R(2, 27, 12, 2, "d4bc94")
		p.R(1, 12, 14, 5, "b02e3a")
		for x in range(2, 14, 2):
			p.P(x, 12, "ffe680"); p.P(x + 1, 16, "ffe680")
		p.R(3, 13, 10, 2, "fff6e8")
		for x in range(4, 12, 2):
			p.P(x, 13, "2b2b3a")
		p.wins.append(Rect2i(3, 13, 10, 2))
		p.R(2, 19, 2, 5, "5b8de4"); p.R(12, 19, 2, 5, "ffd23f")
		p.R(5, 20, 6, 9, "7a1e2a"); p.R(8, 20, 1, 9, "5a1420")
	)
	bld("blogstudio", 16, 26, func(p: Painter) -> void:
		p.R(13, 2, 1, 7, "6a6478"); p.P(12, 2, "6a6478"); p.P(14, 2, "6a6478"); p.P(11, 1, "6a6478"); p.P(15, 1, "6a6478")
		p.R(3, 4, 8, 5, "e45b6b"); p.P(6, 5, "ffffff"); p.R(6, 6, 2, 1, "ffffff"); p.P(6, 7, "ffffff")
		p.R(1, 9, 14, 2, "9b7ad1")
		p.R(2, 11, 12, 14, "f7d6e8"); p.R(2, 22, 12, 3, "e8bcd4")
		p.win(3, 13, 10, 6, "fff6e8")
		p.C(10, 15.5, 2.3, "ffffff"); p.P(10, 15, "fff6e8"); p.P(10, 16, "fff6e8"); p.P(9, 15, "fff6e8"); p.P(11, 16, "fff6e8")
		p.R(5, 16, 2, 3, "f4a259"); p.P(5, 15, "f4a259"); p.P(6, 15, "f4a259")
		p.R(10, 20, 3, 5, "9b7ad1"); p.P(4, 21, "ff4d5e"); p.R(5, 21, 3, 1, "2b2b3a")
	)
	bld("surf", 16, 24, func(p: Painter) -> void:
		p.R(2, 12, 10, 11, "c08f5f")
		for y in range(14, 23, 3):
			p.R(2, y, 10, 1, "a5764a")
		p.R(1, 9, 12, 3, "e0c070")
		for x in range(1, 13, 2):
			p.P(x, 11, "c8a850")
		p.R(3, 13, 8, 3, "fff4e0"); p.P(4, 14, "5b8de4"); p.P(5, 15, "5b8de4"); p.P(6, 14, "5b8de4"); p.P(7, 15, "5b8de4"); p.P(8, 14, "5b8de4")
		p.win(4, 17, 4, 3)
		p.R(12, 6, 2, 16, "5fd3c8"); p.R(12, 12, 2, 1, "ffffff")
		p.R(14, 8, 2, 14, "ff9f43"); p.R(14, 14, 2, 1, "ffffff")
	)
	bld("lifeguard", 16, 30, func(p: Painter) -> void:
		p.R(14, 1, 1, 5, "6a6478"); p.R(15, 1, 1, 2, "e45b6b")
		p.R(1, 5, 14, 3, "ffd23f")
		p.R(2, 8, 12, 10, "8fd0f0"); p.R(2, 8, 12, 1, "b8e4f8")
		p.win(4, 10, 8, 4, "e8f6fc")
		p.R(6, 15, 3, 3, "ffffff"); p.R(7, 15, 1, 3, "e45b6b"); p.R(6, 16, 3, 1, "e45b6b")
		p.R(3, 18, 1, 11, "c9c4d6"); p.R(12, 18, 1, 11, "c9c4d6")
		for i in 8:
			p.P(4 + i, 19 + i, "c9c4d6")
	)
	bld("itoffice", 32, 46, func(p: Painter) -> void:
		p.R(3, 10, 26, 34, "cfeef0"); p.R(3, 42, 26, 2, "b0dce0")
		p.R(2, 8, 28, 2, "5fae73"); p.C(6, 7, 1.8, "5fae73"); p.C(26, 7, 1.8, "5fae73"); p.C(16, 7, 1.5, "7cc46a")
		for y in [13, 19, 25]:
			for x in [5, 11, 17, 23]:
				p.win(x, y, 4, 4, "7fd0d8")
		p.R(8, 31, 16, 5, "2b2b3a")
		for pt in [[12, 32], [11, 33], [12, 34], [17, 32], [16, 33], [15, 34], [19, 32], [20, 33], [19, 34]]:
			p.P(pt[0], pt[1], "5fd3c8")
		p.R(12, 37, 8, 7, "7fd0d8"); p.R(15, 37, 2, 7, "cfeef0")
		p.C(6, 41, 1.8, "ff9fc0"); p.C(26, 41, 1.8, "ffd23f")
	)
	bld("studio", 32, 40, func(p: Painter) -> void:
		for y in range(5, 17):
			var hw := roundi(sqrt(maxf(0.0, 225.0 - pow(17.0 - y, 2.0) * 1.6)))
			p.R(16 - hw, y, hw * 2, 1, "e8d8b4" if y % 2 else "dccaa0")
		p.R(1, 16, 30, 22, "f2e6cc"); p.R(1, 36, 30, 2, "dccaa0")
		p.R(12, 19, 8, 2, "b02e3a"); p.R(17, 21, 2, 3, "b02e3a"); p.R(16, 24, 2, 3, "b02e3a"); p.R(15, 27, 2, 2, "b02e3a")
		p.R(9, 29, 14, 9, "8a8fb0")
		for y in range(30, 38, 2):
			p.R(9, y, 14, 1, "7a7fa0")
		p.R(2, 19, 7, 6, "2b2b3a")
		for x in range(2, 9, 2):
			p.P(x, 19, "ffffff"); p.P(x + 1, 20, "ffffff")
		p.R(25, 21, 4, 3, "6a6478"); p.P(24, 20, "fff6c2"); p.P(23, 19, "fff6c2")
		p.win(25, 27, 4, 4)
	)
	obj["umbrella"] = drawn(16, 24, func(p: Painter) -> void:
		p.R(3, 19, 9, 4, "5fd3c8"); p.R(3, 20, 9, 1, "ffffff")
		p.R(8, 8, 1, 14, "ffffff")
		var widths := [2, 4, 5, 6, 7, 7]
		for k in widths.size():
			var hw: int = widths[k]
			for x in range(8 - hw, 8 + hw):
				p.P(x, 3 + k, "e45b6b" if (x / 2) % 2 == 0 else "ffffff")
	, true, Rect2i(2, 23, 12, 1))
	obj["palm"] = palms[0]
	# знак на холме: буквы рисуем после обводки, чтобы они не слипались
	var sp := Painter.new(32, 32)
	sp.C(16, 36, 18, "a89a64")
	sp.C(16, 36, 16, "b4a670")
	for k in 12:
		sp.P(4 + k * 2, 26 + (k % 3), "8a9a58")
	var word := "KOTOWOOD"
	for i in word.length():
		sp.R(i * 4 + 1, 17, 1, 3, "6a6478")
	outline(sp.img)
	for i in word.length():
		var g: Array = LETTERS[word[i]]
		for r in 5:
			for c in 3:
				if g[r][c] == "x":
					sp.P(i * 4 + c, 12 + r, "ffffff")
	add_shadow(sp.img, Rect2i(1, 31, 30, 1))
	obj["sign"] = tex(sp.img)


func _make_more() -> void:
	bld("sushi", 16, 24, func(p: Painter) -> void:
		p.R(1, 8, 14, 3, "3b2a3a"); p.R(0, 10, 16, 1, "5a4a5a")
		p.R(2, 11, 12, 12, "c99a6b"); p.R(2, 21, 12, 2, "a5764a")
		for x in range(3, 13, 3):
			p.R(x, 12, 2, 4, "e45b6b"); p.P(x, 13, "ffffff")
		p.win(3, 17, 5, 3, "fff1b0")
		p.R(10, 17, 3, 6, "5a3c30")
		p.C(8, 5, 3, "2b3a2a"); p.C(8, 5, 2, "ffffff"); p.C(8, 5, 1, "ff8f6b")
		p.R(14, 12, 1, 4, "6a6478"); p.R(13, 16, 3, 3, "ff6b6b")
	)
	bld("pizzeria", 16, 24, func(p: Painter) -> void:
		p.R(2, 10, 12, 13, "d9734f")
		for y in range(12, 22, 3):
			for x in range(2 + (y % 2) * 2, 14, 4):
				p.R(x, y, 2, 1, "c0603e")
		p.R(1, 8, 14, 2, "3b7a4a")
		for x in range(1, 15):
			p.R(x, 12, 1, 2, "5fae73" if x % 2 else "ffffff")
		p.win(3, 15, 5, 4, "fff1b0")
		p.R(10, 16, 3, 7, "7a4a2a"); p.P(12, 19, "ffd75e")
		p.C(8, 4.5, 3.4, "f2c14e"); p.C(8, 4.5, 2.5, "ffd75e")
		p.P(7, 3, "e45b6b"); p.P(9, 5, "e45b6b"); p.P(7, 6, "e45b6b"); p.P(9, 3, "5fae73")
	)
	bld("groomer", 16, 24, func(p: Painter) -> void:
		p.R(2, 10, 12, 13, "fde4ef"); p.R(2, 21, 12, 2, "f2c4d8")
		p.R(1, 8, 14, 2, "ff8fab")
		p.win(3, 13, 10, 4, "e8f6fc")
		p.R(4, 19, 3, 4, "ff8fab")
		p.R(9, 18, 4, 5, "c06080")
		p.C(5, 4, 1.5, "9aa5b8"); p.C(11, 4, 1.5, "9aa5b8")
		p.P(6, 5, "9aa5b8"); p.P(7, 6, "9aa5b8"); p.P(10, 5, "9aa5b8"); p.P(9, 6, "9aa5b8"); p.P(8, 7, "6a6478")
	)
	bld("farm", 32, 40, func(p: Painter) -> void:
		p.R(1, 24, 30, 14, "8a6a48")
		for y in range(25, 37, 3):
			p.R(2, y, 28, 1, "6f5236")
			for x in range(3, 30, 3):
				p.P(x, y - 1, "7cc46a" if (x + y) % 2 else "ffd75e")
		p.R(3, 9, 14, 13, "c0392b"); p.R(3, 9, 14, 1, "e05a4a")
		for y in range(3, 9):
			var hw := y + 1
			p.R(10 - hw, y, hw * 2, 1, "8a2a20")
		p.R(7, 13, 6, 9, "ffffff"); p.R(8, 14, 4, 8, "8a2a20"); p.P(10, 14, "ffffff"); p.P(9, 16, "ffffff"); p.P(11, 18, "ffffff")
		p.R(21, 6, 6, 16, "c9c4d6"); p.C(24, 6, 3, "9aa5b8"); p.R(21, 10, 6, 1, "aaa4bc"); p.R(21, 15, 6, 1, "aaa4bc")
		for x in range(1, 31, 3):
			p.R(x, 37, 1, 3, "fff4e6")
		p.R(1, 38, 30, 1, "fff4e6")
		p.wins.append(Rect2i(8, 14, 4, 3))
	)
	bld("exchange", 32, 48, func(p: Painter) -> void:
		for y in range(8, 16):
			var hw := roundi(3 + (y - 8) * 12.0 / 7.0)
			p.R(16 - hw, y, hw * 2, 1, "e8dcc6")
		p.R(13, 10, 6, 4, "ffd23f"); p.R(15, 9, 2, 6, "c8a020")
		p.R(2, 16, 28, 4, "2b2b3a")
		for x in range(3, 29, 2):
			p.P(x, 17, "5fd38f" if x % 4 == 1 else "ff6b6b")
			p.P(x + 1, 18, "ffd23f")
		p.R(3, 20, 26, 22, "f4ead8")
		for x in [4, 9, 14, 19, 24]:
			p.R(x, 21, 3, 20, "ffffff"); p.R(x + 2, 21, 1, 20, "e6dccb")
		p.win(7, 24, 2, 8); p.win(12, 24, 2, 8); p.win(17, 24, 2, 8); p.win(22, 24, 2, 8)
		p.R(13, 34, 6, 8, "8a5a3b")
		p.R(2, 42, 28, 2, "e6e2f0"); p.R(1, 44, 30, 3, "d8d4e4")
		for i in 7:
			p.P(22 + i, 6 - i / 2, "5fd38f"); p.P(22 + i, 7 - i / 2, "5fd38f")
		p.P(28, 2, "5fd38f"); p.P(27, 2, "5fd38f"); p.P(28, 3, "5fd38f")
	)
	# --- чудеса света ---
	bld("pier_wheel", 32, 44, func(p: Painter) -> void:
		p.R(0, 34, 32, 4, "c08f5f"); p.R(0, 34, 32, 1, "d8a874")
		for x in range(1, 32, 5):
			p.R(x, 38, 2, 5, "7a5236")
		var cx := 12.0
		var cy := 16.0
		p.C(cx, cy, 13, "e45b6b"); p.C(cx, cy, 11.6, "ffffff00")
		for a in 12:
			var ang := a * TAU / 12.0
			for k in range(1, 12):
				p.P(roundi(cx + cos(ang) * k), roundi(cy + sin(ang) * k), "d8d4e4")
		for a in 120:
			var ang := a * TAU / 120.0
			p.P(roundi(cx + cos(ang) * 12.0), roundi(cy + sin(ang) * 12.0), "e45b6b")
		var cab := ["ffd23f", "5fd3c8", "ff9fc0", "5b8de4", "5fd38f", "ff9f43"]
		for a in 12:
			var ang := a * TAU / 12.0
			p.R(roundi(cx + cos(ang) * 12.0) - 1, roundi(cy + sin(ang) * 12.0), 3, 2, cab[a % cab.size()])
		p.C(cx, cy, 1.5, "6a6478")
		p.P(roundi(cx) - 2, 30, "6a6478"); p.R(roundi(cx) - 3, 28, 1, 6, "9aa5b8"); p.R(roundi(cx) + 3, 28, 1, 6, "9aa5b8")
		for i in 9:
			p.P(23 + i, 33 - roundi(sin(i * 0.7) * 3.0 + 3.0), "5b8de4")
			p.P(23 + i, 34 - roundi(sin(i * 0.7) * 3.0 + 3.0), "5b8de4")
		p.R(24, 28, 1, 6, "9aa5b8"); p.R(30, 28, 1, 6, "9aa5b8")
		for a in 12:
			var ang := a * TAU / 12.0
			p.wins.append(Rect2i(roundi(cx + cos(ang) * 12.0), roundi(cy + sin(ang) * 12.0), 1, 1))
	)
	bld("observatory", 32, 40, func(p: Painter) -> void:
		p.C(16, 46, 22, "8fae68"); p.C(16, 46, 20, "a3c27a")
		p.R(4, 22, 24, 12, "fbfbf8"); p.R(4, 32, 24, 2, "e8e4dc")
		p.R(2, 30, 28, 4, "f4f0e8")
		p.C(16, 18, 7, "4a7a78"); p.R(9, 18, 14, 4, "fbfbf8"); p.C(15, 15, 2, "6aa09c")
		p.C(6, 22, 3.2, "4a7a78"); p.C(26, 22, 3.2, "4a7a78")
		p.R(3, 22, 6, 3, "fbfbf8"); p.R(23, 22, 6, 3, "fbfbf8")
		for x in [7, 11, 20, 24]:
			p.win(x, 25, 2, 4)
		p.R(14, 26, 4, 6, "8a6a48")
		p.R(16, 10, 1, 2, "6a6478")
		p.R(1, 34, 30, 2, "d8d0c4")
	)
	bld("concert", 32, 40, func(p: Painter) -> void:
		p.R(1, 34, 30, 4, "d8d4e4")
		var sails := [[3, 30, 10, 18], [9, 30, 9, 24], [15, 30, 10, 20], [21, 30, 9, 26], [12, 30, 14, 12]]
		var cols := ["c8ccd8", "dfe3ec", "b8bccb", "e8ebf2", "aeb3c4"]
		for k in sails.size():
			var sl: Array = sails[k]
			for i in sl[3]:
				var t: float = float(i) / sl[3]
				var w: int = roundi(sl[2] * (1.0 - t * t * 0.7))
				var x0: int = sl[0] + roundi(sin(t * 2.2 + k) * 2.0)
				p.R(x0, sl[1] - i, w, 1, cols[k])
				p.P(x0, sl[1] - i, "ffffff")
		p.win(10, 30, 12, 3, "fff1b0")
		p.R(14, 31, 4, 3, "6a6478")
	)
	bld("urban_light", 32, 30, func(p: Painter) -> void:
		p.R(1, 24, 30, 5, "d8d4e4"); p.R(1, 24, 30, 1, "e8e6f0")
		# ряды старинных фонарей
		for row in 3:
			for col in 6:
				var x := 3 + col * 5 + (row % 2)
				var y := 6 + row * 6
				p.R(x, y, 1, 22 - row * 6, "6a6478")
				p.R(x - 1, y - 2, 3, 2, "8a8fa0")
				p.P(x, y - 3, "fff6c2")
				p.wins.append(Rect2i(x - 1, y - 2, 3, 2))
	)
	bld("bowl", 32, 36, func(p: Painter) -> void:
		p.C(16, 44, 22, "8fae68"); p.C(16, 44, 20, "a3c27a")
		# концентрические арки «ракушки»
		var arcs := [[13, "ffffff"], [11, "e6e8f0"], [9, "ffffff"], [7, "e6e8f0"], [5, "fff6e0"]]
		for a in arcs:
			p.C(16, 22, a[0], a[1])
		p.R(2, 22, 28, 14, "ffffff00")
		p.R(3, 22, 26, 3, "c8a070"); p.R(3, 22, 26, 1, "e0b888")
		# ряды зрителей
		for k in 4:
			p.R(4 - k, 26 + k * 2, 24 + k * 2, 1, "5b8de4" if k % 2 == 0 else "4a7ac8")
		p.wins.append(Rect2i(11, 18, 10, 3))
	)
	bld("chinese", 32, 40, func(p: Painter) -> void:
		p.R(1, 34, 30, 4, "e8dcc4"); p.R(1, 34, 30, 1, "f4ead8")
		p.R(5, 20, 22, 14, "c8323a")
		for x in [6, 12, 19, 25]:
			p.R(x, 20, 1, 14, "8a1e26")
		p.R(13, 26, 6, 8, "ffd23f"); p.R(14, 27, 4, 7, "c89a28")
		# многоярусная крыша-пагода с загнутыми краями
		p.R(2, 16, 28, 3, "2f8a6a"); p.P(1, 15, "2f8a6a"); p.P(30, 15, "2f8a6a")
		p.R(6, 10, 20, 3, "2f8a6a"); p.P(5, 9, "2f8a6a"); p.P(26, 9, "2f8a6a")
		p.R(7, 13, 18, 3, "c8323a")
		p.R(10, 5, 12, 3, "2f8a6a"); p.P(9, 4, "2f8a6a"); p.P(22, 4, "2f8a6a")
		p.R(11, 8, 10, 2, "c8323a")
		p.R(15, 1, 2, 4, "ffd23f")
		# отпечатки лапок у входа
		for x in [4, 8, 22, 26]:
			p.P(x, 36, "8a6a48")
		p.wins.append(Rect2i(8, 22, 3, 3)); p.wins.append(Rect2i(21, 22, 3, 3))
	)
	bld("capitol", 32, 46, func(p: Painter) -> void:
		p.R(2, 40, 28, 5, "d8d4e4")
		# круглая башня — стопка «пластинок»
		for i in 10:
			var y := 10 + i * 3
			p.R(9, y, 14, 2, "f4f4f8")
			p.R(8, y + 2, 16, 1, "3b3b4a")
			p.wins.append(Rect2i(10, y, 3, 1)); p.wins.append(Rect2i(19, y, 3, 1))
		p.R(9, 40, 14, 1, "3b3b4a")
		# шпиль-игла с красным огоньком
		p.R(15, 1, 2, 9, "8a8fa0"); p.P(15, 0, "ff4a4a")
		p.wins.append(Rect2i(15, 0, 1, 1))
		p.R(14, 34, 4, 6, "8a5a3b")
	)
	bld("getty", 32, 36, func(p: Painter) -> void:
		p.C(16, 44, 22, "8fae68"); p.C(16, 44, 20, "a3c27a")
		# белые травертиновые корпуса и круглый павильон
		p.R(2, 16, 12, 12, "f4efe6"); p.R(2, 16, 12, 1, "ffffff")
		p.R(16, 12, 14, 16, "efe8da"); p.R(16, 12, 14, 1, "ffffff")
		p.C(14, 20, 5, "fbf8f0"); p.R(9, 20, 10, 8, "fbf8f0")
		for x in [4, 8, 18, 22, 26]:
			p.win(x, 19, 2, 6)
		p.R(12, 23, 4, 5, "8a6a48")
		# сады
		for x in [3, 7, 25, 28]:
			p.C(x, 30, 1.8, "5fae73")
		p.R(1, 28, 30, 2, "d8d0c4")
	)
	bld("stadium", 32, 34, func(p: Painter) -> void:
		for y in range(6, 32):
			var t := (y - 19.0) / 13.0
			var hw := roundi(15.0 * sqrt(maxf(0.0, 1.0 - t * t)))
			p.R(16 - hw, y, hw * 2, 1, "5b8de4" if y % 2 else "4a7ac8")
		for y in range(11, 27):
			var t := (y - 19.0) / 8.0
			var hw := roundi(10.0 * sqrt(maxf(0.0, 1.0 - t * t)))
			p.R(16 - hw, y, hw * 2, 1, "5fbf6a" if (y / 2) % 2 else "6fcf78")
		for i in 6:
			p.P(16 - i, 24 - i, "e8c890"); p.P(16 + i, 24 - i, "e8c890")
		p.P(16, 19, "ffffff")
		for x in [2, 29]:
			p.R(x, 0, 1, 10, "9aa5b8"); p.R(x - 1, 0, 3, 2, "fff6c2")
			p.wins.append(Rect2i(x - 1, 0, 3, 2))
		p.R(10, 29, 12, 3, "ffffff"); p.R(11, 30, 10, 1, "e45b6b")
	)


## Места для машин на парковках (для отрисовки припаркованных машин).
var PARKING_SLOTS: Array = [Vector2i(2, 4), Vector2i(9, 4), Vector2i(2, 11), Vector2i(9, 11)]
var GARAGE_SLOTS: Array = []


func _make_parking() -> void:
	obj["parking"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 1, 16, 15, "8a8898")
		p.R(7, 2, 1, 13, "f4f4f8")
		p.R(1, 8, 14, 1, "f4f4f8")
		p.R(1, 1, 4, 4, "3d6ac0")
		p.R(2, 2, 1, 2, "ffffff"); p.P(3, 2, "ffffff")
	, false)
	bld("garage", 32, 40, func(p: Painter) -> void:
		p.R(2, 10, 28, 28, "c9c4d6")
		for y in [13, 19, 25, 31]:
			p.R(3, y, 26, 4, "5a5868")
			p.R(2, y + 4, 28, 1, "9aa5b8")
		p.R(12, 2, 8, 8, "3d6ac0"); p.R(14, 3, 1, 6, "ffffff"); p.R(15, 3, 3, 1, "ffffff"); p.R(17, 4, 1, 2, "ffffff"); p.R(15, 6, 3, 1, "ffffff")
		p.R(15, 10, 2, 1, "6a6478")
		p.R(12, 36, 8, 3, "7a7888")
	)
	windows["garage"] = []
	GARAGE_SLOTS = []
	for y in [14, 20, 26, 32]:
		for x in [4, 9, 14, 19, 24]:
			GARAGE_SLOTS.append(Vector2i(x, y))


## Широкие версии маленьких зданий, нарисованных вручную (для пар).
const PAIR_LOOKS := {
	"house": {"wall": "ffe9d6", "roof": "gable", "rc": "f28fa6", "win": "grid", "wc": "9fd3e6", "door": "8a5a3b", "h": 26, "extra": ["ears"]},
	"pier": {"wall": "c8a070", "roof": "shed", "rc": "5b8de4", "win": "none", "door": "8a5a3b", "sign": "fish", "sc": "5b8de4", "fg": "ffffff", "h": 20},
	"shop": {"wall": "fff4e0", "roof": "awning", "rc": "ff8fab", "win": "shop", "wc": "9fd3e6", "door": "8a5a3b", "sign": "cart", "sc": "ff8fab", "fg": "ffffff", "h": 22},
	"icecream": {"wall": "fff0f5", "roof": "awning", "rc": "ff9fc0", "win": "shop", "wc": "ffe0ec", "door": "c8706a", "sign": "cup", "sc": "ff9fc0", "fg": "ffffff", "h": 20},
	"bakery": {"wall": "f7e3c4", "roof": "awning", "rc": "c8955a", "win": "shop", "wc": "ffe9a8", "door": "8a5a3b", "sign": "cup", "sc": "c8955a", "fg": "ffffff", "h": 22},
	"sushi": {"wall": "f4efe6", "roof": "flat", "rc": "2b2b3a", "win": "shop", "wc": "9fd3e6", "door": "8a3a3a", "sign": "fish", "sc": "e45b6b", "fg": "ffffff", "h": 22},
	"pizzeria": {"wall": "fff1d6", "roof": "awning", "rc": "5fae73", "win": "shop", "wc": "ffe9a8", "door": "8a5a3b", "sign": "cup", "sc": "e45b6b", "fg": "ffffff", "h": 22},
	"groomer": {"wall": "ffe1ec", "roof": "awning", "rc": "ff9fc0", "win": "shop", "wc": "9fd3e6", "door": "c8706a", "sign": "scissors", "sc": "ff9fc0", "fg": "ffffff", "h": 22},
	"cafe": {"wall": "9ed8c8", "roof": "flat", "rc": "fff4e0", "win": "shop", "wc": "fff4e0", "door": "8a5a3b", "sign": "paw", "sc": "fff4e0", "fg": "3b2a3a", "h": 24, "extra": ["ears"]},
	"gym": {"wall": "d8e4f0", "roof": "flat", "rc": "5fd38f", "win": "glass", "wc": "9fd3e6", "door": "3b3b4a", "sign": "bolt", "sc": "5fd38f", "fg": "ffffff", "h": 24},
	"cinema": {"wall": "b02e3a", "roof": "flat", "rc": "ffd75e", "win": "none", "door": "2b2b3a", "sign": "camera", "sc": "ffd75e", "fg": "3b2a3a", "h": 26, "extra": ["neon"]},
	"blogstudio": {"wall": "f0e0ff", "roof": "flat", "rc": "c8a8ff", "win": "glass", "wc": "9fd3e6", "door": "5a4a6a", "sign": "camera", "sc": "ff6fae", "fg": "ffffff", "h": 24, "extra": ["antenna"]},
	"lifeguard": {"wall": "ffffff", "roof": "shed", "rc": "e0483a", "win": "grid", "wc": "9fd3e6", "door": "e0483a", "sign": "cross", "sc": "e0483a", "fg": "ffffff", "h": 22},
	"post": {"wall": "5b8de4", "roof": "flat", "rc": "ffd75e", "win": "grid", "wc": "cfe0ff", "door": "3d5a98", "sign": "box", "sc": "ffd75e", "fg": "3b2a3a", "h": 24},
	"police": {"wall": "d8e0f0", "roof": "flat", "rc": "3d5a98", "win": "grid", "wc": "9fd3e6", "door": "3d5a98", "sign": "star", "sc": "3d5a98", "fg": "ffffff", "h": 26},
	"fire": {"wall": "e0483a", "roof": "flat", "rc": "8a2a2a", "win": "grid", "wc": "ffe9a8", "door": "3b3b4a", "sign": "fuel", "sc": "ffffff", "fg": "e0483a", "h": 26, "extra": ["garage_door"]},
	"library": {"wall": "e8d8b8", "roof": "gable", "rc": "8a5a3b", "win": "grid", "wc": "9fd3e6", "door": "6a4a3a", "sign": "book", "sc": "8a5a3b", "fg": "ffffff", "h": 28, "extra": ["columns"]},
	"surf": {"wall": "5fd3c8", "roof": "shed", "rc": "ffd75e", "win": "shop", "wc": "e8fbf8", "door": "8a5a3b", "sign": "sun", "sc": "ffd75e", "fg": "e45b6b", "h": 20},
}


func _make_generated() -> void:
	var make := func(w: int, h: int): return Painter.new(w, h)
	for key in D.DEFS:
		var d: Dictionary = D.DEFS[key]
		if not d.has("look") or obj.has(key):
			continue
		var p = BG.build(d.look, int(d.get("size", 1)), make)
		outline(p.img)
		add_shadow(p.img, Rect2i(1, p.h - 1, p.w - 2, 1))
		obj[key] = tex(p.img)
		windows[key] = p.wins
	# широкие «парные» версии маленьких домов, магазинов и служб
	for key in D.DEFS:
		var d: Dictionary = D.DEFS[key]
		if int(d.get("size", 1)) != 1 or not (d.has("cap") or d.has("jobs")):
			continue
		var look: Dictionary = PAIR_LOOKS.get(key, d.get("look", {}))
		if look.is_empty() or look.get("extra", []).has("trailer"):
			continue
		var p = BG.build(look, 2, make)
		outline(p.img)
		add_shadow(p.img, Rect2i(1, p.h - 1, p.w - 2, 1))
		obj["pair_" + key] = tex(p.img)
		windows["pair_" + key] = p.wins


func _make_icons() -> void:
	icons["coin"] = tex(grid([
		"..kkkk..", ".kyyyyk.", "kyywyyyk", "kywyyyyk", "kyyyyyok", "kyyyyook", ".kyoook.", "..kkkk..",
	], {"k": INK, "y": "ffd75e", "w": "fff6c2", "o": "e8a93a"}))
	icons["fish"] = tex(grid([
		"k....kkk...", "kk..kbbbk..", "kbkkbbbbbk.", "kbbbbbbkbbk", "kbkkbwbbbk.", "kk..kbbbk..", "k....kkk...",
	], {"k": INK, "b": "7fc4e8", "w": "bfe6f7"}))
	icons["heart"] = tex(grid([
		".kk.kk.", "krrkrrk", "krwrrrk", "krrrrrk", ".krrrk.", "..krk..", "...k...",
	], {"k": INK, "r": "ff6b8b", "w": "ffd0db"}))
	icons["cat"] = tex(grid([
		"k.......k", "kpk...kpk", "kaakkkaak", "kaaaaaaak", "kaeaaaeak", "kcaapaack", ".kaaaaak.", "..kkkkk..",
	], {"k": INK, "a": "f4a259", "p": "ff8fab", "e": "2b2233", "c": "f7b2c0"}))
	icons["briefcase"] = drawn(12, 11, func(p: Painter) -> void:
		p.R(4, 1, 4, 1, "8a5a3b"); p.P(4, 2, "8a5a3b"); p.P(7, 2, "8a5a3b")
		p.R(1, 3, 10, 7, "a0703a"); p.R(1, 5, 10, 1, "8a5a3b"); p.R(5, 5, 2, 2, "ffd75e")
	)
	icons["paw"] = drawn(13, 13, func(p: Painter) -> void:
		p.C(6.5, 8.8, 3.2, "ff9fb5")
		p.C(2.5, 5, 1.6, "ff9fb5"); p.C(5, 2.6, 1.6, "ff9fb5"); p.C(8, 2.6, 1.6, "ff9fb5"); p.C(10.5, 5, 1.6, "ff9fb5")
	)
	icons["shovel"] = drawn(14, 14, func(p: Painter) -> void:
		for i in 6:
			p.P(1 + i, 1 + i, "a0704a"); p.P(2 + i, 1 + i, "a0704a")
		p.R(1, 1, 3, 1, "a0704a")
		p.C(9.5, 9.5, 3, "b9c2cc"); p.C(9, 9, 1.4, "dde3ea")
	)
	icons["path"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 4, 16, 8, "a8907e"); p.R(0, 5, 16, 6, "e9dccd")
		p.P(3, 7, "d3c1b0"); p.P(9, 9, "d3c1b0"); p.P(12, 6, "f7efe4"); p.P(6, 9, "f7efe4")
	, false)
	icons["road"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 2, 16, 12, "7a7888"); p.R(0, 2, 16, 1, "b8b6c4"); p.R(0, 13, 16, 1, "b8b6c4")
		p.R(1, 7, 4, 1, "f4ecd0"); p.R(9, 7, 4, 1, "f4ecd0")
	, false)
	icons["oneway"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 2, 16, 12, "7a7888"); p.R(0, 2, 16, 1, "b8b6c4"); p.R(0, 13, 16, 1, "b8b6c4")
		p.R(2, 7, 8, 2, "ffffff"); p.R(10, 5, 1, 6, "ffffff"); p.R(11, 6, 1, 4, "ffffff"); p.R(12, 7, 1, 2, "ffffff")
	, false)
	icons["t_grass"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 0, 16, 16, "6cc1e0"); p.C(8, 8, 6.5, "9bd67f"); p.P(6, 6, "b0e294"); p.P(10, 9, "8bc871"); p.P(7, 11, "8bc871")
	)
	icons["t_sand"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 0, 16, 16, "6cc1e0"); p.C(8, 8, 6.5, "f1dfa6"); p.P(6, 6, "f8ecc4"); p.P(10, 9, "e4cc8c")
	)
	icons["t_hill"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 0, 16, 16, "9bd67f"); p.C(8, 10, 6.5, "b4e294"); p.C(8, 10, 4, "c8eca8"); p.R(1, 13, 14, 2, "7fb868")
	)
	icons["t_mountain"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 0, 16, 16, "9bd67f")
		for y in range(3, 15):
			var hw := (y - 2)
			p.R(8 - hw / 2 - 1, y, hw + 2, 1, "b4a48c")
		p.R(7, 3, 2, 3, "ffffff"); p.R(9, 6, 3, 8, "9a8a74")
	)
	icons["t_dry"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 0, 16, 16, "d4c88a"); p.P(4, 5, "a89a5a"); p.P(10, 8, "a89a5a"); p.R(6, 11, 3, 2, "8a9a58")
	)
	icons["t_meadow"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 0, 16, 16, "9bd67f"); p.P(4, 4, "ff6b6b"); p.P(11, 6, "ffd23f"); p.P(6, 11, "ff6b6b"); p.P(12, 12, "ffffff")
	)
	icons["highway"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 1, 16, 14, "5d5b6a"); p.R(0, 7, 16, 1, "ffd23f"); p.R(0, 8, 16, 1, "ffd23f")
		p.R(1, 4, 3, 1, "ffffff"); p.R(8, 4, 3, 1, "ffffff"); p.R(1, 11, 3, 1, "ffffff"); p.R(8, 11, 3, 1, "ffffff")
	, false)
	icons["rail"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 3, 16, 10, "b8ad9a")
		for x in range(1, 16, 4):
			p.R(x, 3, 2, 10, "7a5a3b")
		p.R(0, 5, 16, 1, "8a8fa0"); p.R(0, 10, 16, 1, "8a8fa0")
	, false)
	icons["t_water"] = drawn(16, 16, func(p: Painter) -> void:
		p.R(0, 0, 16, 16, "6cc1e0"); p.R(3, 5, 4, 1, "d6f2fa"); p.R(9, 9, 4, 1, "d6f2fa"); p.R(5, 12, 3, 1, "a3dcef")
	)
	small["heart"] = tex(grid([".r.r.", "rrrrr", "rrrrr", ".rrr.", "..r.."], {"r": "ff6b8b"}))
	small["z"] = tex(grid(["kkkk", "..k.", ".k..", "kkkk"], {"k": "ffffff"}))
	small["star"] = tex(grid(["..k..", ".kyk.", "kyyyk", ".kyk.", "k.k.k"], {"k": INK, "y": "ffd23f"}))
	small["sparkle"] = tex(grid([".w.", "www", ".w."], {"w": "fff6c2"}))


## Текстура постройки по объекту на карте.
func obj_texture(o: Dictionary) -> Texture2D:
	match o.t:
		"wildpalm":
			return palms[int(o.v) % palms.size()]
		"palm":
			return palms[int(o.v) % 2]
		"flowers":
			return flowers[int(o.v) % flowers.size()]
	var lvl := int(o.get("lvl", 1))
	if lvl > 1 and obj.has(o.t):
		return level_variant(o.t, lvl)[0]
	return obj.get(o.t)


## Окна для ночного света с учётом уровня здания.
func windows_for(o: Dictionary) -> Array:
	var lvl := int(o.get("lvl", 1))
	if lvl > 1 and obj.has(o.t):
		return level_variant(o.t, lvl)[1]
	return windows.get(o.t, [])


var _lvl_cache := {}
var _pair_cache := {}


## Два одинаковых маленьких здания рядом — одно широкое здание с одной дверью.
## Для улучшенных — тот же широкий дом с этажами и украшениями уровня.
func has_pair(t: String) -> bool:
	return obj.has("pair_" + t)


func pair_variant(o: Dictionary) -> Array:
	var key: String = "pair_" + o.t
	var lvl := int(o.get("lvl", 1))
	if lvl > 1:
		return level_variant(key, lvl)
	return [obj[key], windows.get(key, [])]


## Улучшенное здание: на каждый уровень — ещё один этаж (копия ряда окон),
## на 2 уровне — зелень на крыше, на 3 — золотой карниз, флаг и гирлянда.
func level_variant(key: String, lvl: int) -> Array:
	var ck := "%s|%d" % [key, lvl]
	if _lvl_cache.has(ck):
		return _lvl_cache[ck]
	var img: Image = obj[key].get_image()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var wins: Array = windows.get(key, []).duplicate()
	for n in lvl - 1:
		var h := img.get_height()
		# этаж = ряд окон ближе к середине здания (с рамками)
		var r0 := int(h * 0.55)
		var bh := 5 if w <= 16 else 7
		var best := 1e9
		for r in wins:
			var d := absf(r.position.y - h * 0.5)
			if d < best and r.position.y > 4 and r.end.y < h - 6:
				best = d
				r0 = r.position.y - 1
				bh = r.size.y + 2
		var out := Image.create_empty(w, h + bh, false, Image.FORMAT_RGBA8)
		out.blit_rect(img, Rect2i(0, 0, w, r0 + bh), Vector2i(0, 0))
		out.blit_rect(img, Rect2i(0, r0, w, h - r0), Vector2i(0, r0 + bh))
		var nw := []
		for r in wins:
			if r.position.y >= r0:
				nw.append(Rect2i(r.position + Vector2i(0, bh), r.size))
				if r.position.y < r0 + bh:
					nw.append(r)
			else:
				nw.append(r)
		wins = nw
		img = out
	var pad := 8
	var fin := Image.create_empty(w, img.get_height() + pad, false, Image.FORMAT_RGBA8)
	fin.blit_rect(img, Rect2i(0, 0, w, img.get_height()), Vector2i(0, pad))
	var shifted := []
	for r in wins:
		shifted.append(Rect2i(r.position + Vector2i(0, pad), r.size))
	# верхняя строка крыши
	var top := pad
	for y in fin.get_height():
		var found := false
		for x in w:
			if fin.get_pixel(x, y).a > 0.5:
				found = true
				break
		if found:
			top = y
			break
	# верх крыши в нужном столбце — чтобы украшения стояли на крыше, а не висели в воздухе
	var col_top := func(cx: int) -> int:
		for y in fin.get_height():
			if fin.get_pixel(clampi(cx, 0, w - 1), y).a > 0.5:
				return y
		return top
	var deco := Painter.new(w, fin.get_height())
	var x1 := roundi(w * 0.3)
	var x2 := roundi(w * 0.7)
	deco.C(x1 + 0.5, col_top.call(x1) - 1.5, 1.7, "5fae73")
	deco.C(x2 + 0.5, col_top.call(x2) - 1.5, 1.7, "7cc46a")
	deco.P(x1, col_top.call(x1) - 3, "ff8fab")
	if lvl >= 3:
		var fx := w / 2
		var ft: int = col_top.call(fx)
		deco.R(fx, ft - 8, 1, 8, "6a6478")
		deco.R(fx + 1, ft - 8, 4, 3, "ffd23f")
		deco.R(fx + 1, ft - 7, 4, 1, "ff8fab")
	outline(deco.img)
	fin.blend_rect(deco.img, Rect2i(0, 0, w, fin.get_height()), Vector2i.ZERO)
	if lvl >= 3:
		# золотой карниз и гирлянда по краю крыши
		var ink := INK
		for y in range(top, mini(top + 2, fin.get_height())):
			for x in w:
				if fin.get_pixel(x, y).is_equal_approx(ink):
					fin.set_pixel(x, y, Color("e8b830"))
		for x in range(1, w - 1, 3):
			if fin.get_pixel(x, top).a > 0.5:
				fin.set_pixel(x, top, [Color("ff6b8b"), Color("5fd3c8"), Color("fff6c2")][(x / 3) % 3])
	var res := [tex(fin), shifted]
	_lvl_cache[ck] = res
	return res


## Текстура для кнопки инструмента.
func tool_texture(t: String) -> Texture2D:
	match t:
		"hand":
			return icons["paw"]
		"bulldoze":
			return icons["shovel"]
		"path":
			return icons["path"]
		"road":
			return icons["road"]
		"flowers":
			return flowers[0]
		"t_grass", "t_sand", "t_water", "t_hill", "t_mountain", "t_dry", "t_meadow", "highway", "rail", "oneway":
			return icons[t]
	return obj.get(t)

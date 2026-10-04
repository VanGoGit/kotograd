extends CanvasLayer
## Интерфейс: верхняя панель, вкладки построек, карточки, подсказки, справка.

const D = preload("res://scripts/defs.gd")
const Spr = preload("res://scripts/sprites.gd")

const INK := Color("3b2a3a")
const PAPER := Color("fff6ea")
const PAPER2 := Color("ffecd8")
const PINK := Color("ffd1dc")
const GOLD := Color("fff1b0")

var world
var spr
var sound
var root: Control
var tab := 0
var tool_buttons := {}
var tab_buttons: Array = []
var tools_box: HBoxContainer
var tools_scroll: ScrollContainer
var chk_unlim: CheckButton
var unlimited := false
var toolbar_panel: PanelContainer
var tabs_box: HFlowContainer
var fixed_box: HBoxContainer

var lbl_coins: Label
var lbl_coin_rate: Label
var lbl_food: Label
var lbl_food_rate: Label
var lbl_cats: Label
var lbl_jobs: Label
var happy_bar: ProgressBar
var lbl_happy: Label
var lbl_clock: Label
var btn_speed: Button
var btn_music: Button
var hint: Label

var info_panel: PanelContainer
var info_img: TextureRect
var info_name: Label
var info_sub: Label
var info_body: Label
var info_pet: Button
var info_up: Button
var toasts_box: VBoxContainer
var help_modal: Control
var menu_modal: Control
var settings_modal: Control
var opt_res: OptionButton
var opt_scale: OptionButton
var chk_full: CheckButton
var chk_music: CheckButton
var ui_scale := 1.0
var res_idx := 1
var fullscreen := false
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1440, 900), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const UI_SCALES := [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
var new_game_btn: Button
var _confirm_new := false
var _web := OS.has_feature("web")
var _js_import_cb  # колбэк JavaScript должен жить, пока открыт выбор файла
var _hud_t := 0.0
var _info_t := 0.0
var _styles := {}


func build(w, sprites, snd) -> void:
	world = w
	spr = sprites
	sound = snd
	layer = 3
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_load_settings()
	get_viewport().size_changed.connect(_fit_root)
	_build_top()
	_build_bottom()
	_build_info()
	_build_toasts()
	_build_help()
	_build_menu()
	_build_settings()
	set_tab(2)
	refresh_speed()
	_apply_display()
	_apply_ui_scale()
	world.unlimited = unlimited


# ---------- тема ----------

func _sb(bg: Color, border := INK, bw := 3, radius := 8, pad := 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	sb.shadow_color = Color(INK, 0.25)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 3)
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_stylebox("panel", "PanelContainer", _sb(PAPER))
	t.set_stylebox("normal", "Button", _sb(PAPER, INK, 3, 8, 8.0))
	t.set_stylebox("hover", "Button", _sb(Color.WHITE, INK, 3, 8, 8.0))
	t.set_stylebox("pressed", "Button", _sb(PINK, INK, 3, 8, 8.0))
	t.set_stylebox("disabled", "Button", _sb(PAPER2, Color(INK, 0.4), 3, 8, 8.0))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.5))
	t.set_color("font_color", "Label", INK)
	var tip := _sb(PAPER, INK, 3, 8, 10.0)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 14)
	var bg := _sb(Color.WHITE, INK, 2, 4, 0.0)
	bg.shadow_size = 0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ff8fab")
	fill.set_corner_radius_all(2)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	_styles["tool"] = _sb(PAPER2, Color(0, 0, 0, 0), 3, 8, 4.0)
	_styles["tool"].shadow_size = 0
	_styles["tool_hover"] = _sb(Color.WHITE, Color(0, 0, 0, 0), 3, 8, 4.0)
	_styles["tool_hover"].shadow_size = 0
	_styles["tool_sel"] = _sb(PINK, INK, 3, 8, 4.0)
	_styles["tool_sel"].shadow_size = 0
	return t


func _icon(tex: Texture2D, target := 24) -> TextureRect:
	var r := TextureRect.new()
	var k := maxi(1, target / maxi(tex.get_width(), tex.get_height()))
	r.texture = Spr.scaled(tex, k)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _btn(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


# ---------- верхняя панель ----------

func _res(tex: Texture2D, tip: String) -> Array:
	var p := PanelContainer.new()
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	hb.add_child(_icon(tex, 22))
	var v := Label.new()
	v.add_theme_font_size_override("font_size", 18)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(v)
	var r := Label.new()
	r.add_theme_font_size_override("font_size", 12)
	r.add_theme_color_override("font_color", Color("4f8a4f"))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(r)
	return [p, v, r, hb]


func _build_top() -> void:
	var top := HFlowContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_top = 10
	top.offset_right = -10
	top.add_theme_constant_override("h_separation", 8)
	top.add_theme_constant_override("v_separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	var brand := PanelContainer.new()
	brand.add_theme_stylebox_override("panel", _sb(PINK))
	var bh := HBoxContainer.new()
	brand.add_child(bh)
	bh.add_child(_icon(spr.icons.cat, 20))
	var bl := Label.new()
	bl.text = "Котоград"
	bl.add_theme_font_size_override("font_size", 20)
	bh.add_child(bl)
	top.add_child(brand)

	var r := _res(spr.icons.coin, "Монетки")
	top.add_child(r[0]); lbl_coins = r[1]; lbl_coin_rate = r[2]
	r = _res(spr.icons.fish, "Еда для котиков")
	top.add_child(r[0]); lbl_food = r[1]; lbl_food_rate = r[2]
	r = _res(spr.icons.cat, "Котики / мест в домах")
	top.add_child(r[0]); lbl_cats = r[1]
	r = _res(spr.icons.briefcase, "Работают / рабочих мест")
	top.add_child(r[0]); lbl_jobs = r[1]
	r = _res(spr.icons.heart, "Счастье города")
	top.add_child(r[0])
	happy_bar = ProgressBar.new()
	happy_bar.custom_minimum_size = Vector2(80, 14)
	happy_bar.show_percentage = false
	happy_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	happy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r[3].add_child(happy_bar)
	r[3].move_child(happy_bar, 1)
	lbl_happy = r[1]
	r = _res(spr.icons.heart, "")
	r[3].get_child(0).queue_free()
	top.add_child(r[0]); lbl_clock = r[1]
	lbl_clock.add_theme_font_size_override("font_size", 16)


	btn_speed = _btn("", func(): world.cycle_speed(), "Скорость времени (пробел)")
	top.add_child(btn_speed)
	top.add_child(_btn(" − ", func(): world.set_zoom(world.zoom - 1), "Отдалить (−)"))
	top.add_child(_btn(" + ", func(): world.set_zoom(world.zoom + 1), "Приблизить (+)"))
	btn_music = _btn("", _toggle_music, "Включить / выключить музыку")
	top.add_child(btn_music)
	_update_music_btn()
	top.add_child(_btn(" ? ", func(): open_modal(help_modal), "Как играть"))
	top.add_child(_btn("Меню", func(): open_modal(menu_modal)))


func _toggle_music() -> void:
	sound.set_music(not sound.music_on)
	_update_music_btn()
	chk_music.set_pressed_no_signal(sound.music_on)


func _update_music_btn() -> void:
	btn_music.text = "Звук" if sound.music_on else "Тихо"


func refresh_speed() -> void:
	btn_speed.text = ["Пауза", "x1", "x2", "x3"][world.speed]


# ---------- нижняя панель: вкладки и постройки ----------

func _build_bottom() -> void:
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -10
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	hint = Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color.WHITE)
	hint.add_theme_color_override("font_outline_color", INK)
	hint.add_theme_constant_override("outline_size", 7)
	hint.add_theme_font_size_override("font_size", 16)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(hint)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toolbar_panel = panel
	bottom.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 4)
	tabs.add_theme_constant_override("v_separation", 4)
	tabs_box = tabs
	vb.add_child(tabs)
	for k in D.TABS.size():
		var tb: Dictionary = D.TABS[k]
		var b := _btn(tb.name, func(): set_tab(k))
		b.icon = Spr.scaled(spr.tool_texture(tb.icon), 1)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 18)
		tabs.add_child(b)
		tab_buttons.append(b)

	# постройки — в одну строку с прокруткой вправо (колесо мыши тоже листает)
	tools_scroll = ScrollContainer.new()
	tools_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tools_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vb.add_child(tools_scroll)
	tools_box = HBoxContainer.new()
	tools_box.add_theme_constant_override("separation", 4)
	tools_scroll.add_child(tools_box)
	fixed_box = HBoxContainer.new()
	fixed_box.add_theme_constant_override("separation", 4)
	tools_box.add_child(fixed_box)
	fixed_box.add_child(_tool_button("hand", "Esc"))
	fixed_box.add_child(_tool_button("bulldoze", "B"))
	fixed_box.add_child(VSeparator.new())


func _tool_button(t: String, key: String) -> Button:
	var d: Dictionary = D.DEFS.get(t, D.TOOL_INFO.get(t, {}))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(86, 104)
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 12)
	b.clip_text = false
	var tex: Texture2D = spr.tool_texture(t)
	var k := clampi(48 / maxi(tex.get_width(), tex.get_height()), 1, 3)
	b.icon = Spr.scaled(tex, k)
	b.add_theme_stylebox_override("normal", _styles.tool)
	b.add_theme_stylebox_override("hover", _styles.tool_hover)
	b.add_theme_stylebox_override("pressed", _styles.tool_sel)
	b.set_meta("key", key)
	b.tooltip_text = _tooltip(t)
	b.pressed.connect(func(): world.select_tool(t))
	tool_buttons[t] = b
	_update_tool_button(t)
	return b


func _tooltip(t: String) -> String:
	var d: Dictionary = D.DEFS.get(t, D.TOOL_INFO.get(t, {}))
	var s: String = d.name
	if d.has("terra"):
		s += "  ·  бесплатно"
	elif d.has("cost"):
		s += "  ·  %d мон." % d.cost
	s += "\n" + d.desc
	var extra := []
	if d.get("wonder", false):
		extra.append("Чудо света — можно построить только одно")
		extra.append("Туристы: +%s мон./с" % str(d.tourism))
	if d.get("size", 1) == 2:
		extra.append("Размер: 2×2")
	if d.has("cap"):
		extra.append("Жильцов: %d" % d.cap)
	if d.has("jobs"):
		extra.append("Рабочих мест: %d (%s)" % [d.jobs, D.PROFESSIONS[d.job].to_lower()])
	if d.has("food"):
		extra.append("Даёт еду")
	if d.has("happy"):
		extra.append("Радость +%d в радиусе %d" % [d.happy, d.radius])
	if d.has("service"):
		extra.append("Уют района +%d (радиус %d)" % [d.service, d.sradius])
	if d.has("shop"):
		extra.append("Приносит монетки")
	if d.has("vehicle"):
		extra.append("Служебная машина (нужна дорога)")
	if d.has("build"):
		extra.append("Стройка: %d с" % int(d.build))
	if d.has("up"):
		extra.append("Можно улучшить до уровня %d" % (d.up.size() + 1))
	if d.get("need_high", false):
		extra.append("Только на холмах и в горах")
	if d.has("store_coins"):
		extra.append("Хранилище монет +%d" % d.store_coins)
	if d.has("store_food"):
		extra.append("Хранилище еды +%d" % d.store_food)
	if d.has("tourism") and not d.get("wonder", false):
		extra.append("Туристы: +%s мон./с" % str(d.tourism))
	if d.get("unlock", 0) > 0:
		extra.append("Открывается при %d котиках" % d.unlock)
	if extra.size() > 0:
		s += "\n\n" + "\n".join(extra)
	return s


func _update_tool_button(t: String) -> void:
	var b: Button = tool_buttons.get(t)
	if b == null or not is_instance_valid(b):
		return
	var d: Dictionary = D.DEFS.get(t, D.TOOL_INFO.get(t, {}))
	var locked: bool = d.has("unlock") and world.max_cats < d.unlock and not world.unlimited
	var line2 := ""
	if locked:
		line2 = "нужно %d кот." % d.unlock
	elif d.get("wonder", false) and world.wonder_built(t):
		line2 = "построено"
	elif d.has("terra") or (world.unlimited and d.has("cost")):
		line2 = "бесплатно"
	elif d.has("cost"):
		line2 = "%d мон." % d.cost
	b.text = "%s\n%s" % [d.name, line2]
	b.modulate = Color(1, 1, 1, 0.45) if locked else Color.WHITE
	var poor: bool = d.has("cost") and world.coins < d.cost and not locked and not world.unlimited
	b.add_theme_color_override("font_color", Color("c24a5a") if poor else INK)
	b.add_theme_color_override("font_hover_color", Color("c24a5a") if poor else INK)
	b.add_theme_stylebox_override("normal", _styles.tool_sel if world.tool == t else _styles.tool)


func refresh_tools() -> void:
	for t in tool_buttons:
		_update_tool_button(t)


func set_tab(k: int) -> void:
	tab = k
	tools_scroll.scroll_horizontal = 0
	for c in tools_box.get_children():
		if c == fixed_box:
			continue
		tool_buttons.erase(_tool_of(c))
		tools_box.remove_child(c)
		c.queue_free()
	var tools: Array = D.TABS[k].tools
	for n in tools.size():
		tools_box.add_child(_tool_button(tools[n], str(n + 1)))
	for i in tab_buttons.size():
		tab_buttons[i].add_theme_stylebox_override("normal", _sb(PINK) if i == k else _sb(PAPER))
	_layout_bottom.call_deferred()


## Ширина нижней панели: по содержимому, но не шире окна — иначе кнопки переносятся.
func _layout_bottom() -> void:
	if toolbar_panel == null:
		return
	var avail := root.size.x - 24.0
	var tabs_w := 0.0
	for b in tab_buttons:
		tabs_w += b.get_combined_minimum_size().x + 4.0
	var tools_w := 0.0
	var tools_h := 0.0
	for c in tools_box.get_children():
		if c.is_queued_for_deletion():
			continue
		tools_w += c.get_combined_minimum_size().x + 4.0
		tools_h = maxf(tools_h, c.get_combined_minimum_size().y)
	var pw := minf(maxf(tabs_w, tools_w) + 24.0, avail)
	toolbar_panel.custom_minimum_size.x = pw
	var need_bar := tools_w + 24.0 > avail
	tools_scroll.custom_minimum_size = Vector2(pw - 24.0, tools_h + (14.0 if need_bar else 0.0))


func _tool_of(b: Button) -> String:
	for t in tool_buttons:
		if tool_buttons[t] == b:
			return t
	return ""


func next_tab(dir: int) -> void:
	set_tab(posmod(tab + dir, D.TABS.size()))


func select_tab_tool(n: int) -> void:
	var tools: Array = D.TABS[tab].tools
	if n < tools.size():
		world.select_tool(tools[n])


func hide_tooltip() -> void:
	pass


# ---------- карточка котика / постройки ----------

func _build_info() -> void:
	info_panel = PanelContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_panel.offset_top = 64
	info_panel.offset_right = -10
	info_panel.custom_minimum_size = Vector2(290, 0)
	info_panel.visible = false
	root.add_child(info_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	info_panel.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	info_img = TextureRect.new()
	info_img.custom_minimum_size = Vector2(56, 56)
	info_img.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	head.add_child(info_img)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(names)
	info_name = Label.new()
	info_name.add_theme_font_size_override("font_size", 20)
	names.add_child(info_name)
	info_sub = Label.new()
	info_sub.add_theme_font_size_override("font_size", 13)
	info_sub.add_theme_color_override("font_color", Color(INK, 0.7))
	info_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(info_sub)
	var close := _btn("✕", func(): world.info_target = null)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(close)
	info_body = Label.new()
	info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_body.custom_minimum_size = Vector2(266, 0)
	info_body.add_theme_font_size_override("font_size", 14)
	vb.add_child(info_body)
	info_pet = _btn("Погладить", _pet_selected)
	vb.add_child(info_pet)
	info_up = _btn("Улучшить", _upgrade_selected, "Улучшенное здание вмещает больше котиков, даёт больше монет и радости")
	info_up.add_theme_stylebox_override("normal", _sb(GOLD, INK, 3, 8, 8.0))
	vb.add_child(info_up)


func _pet_selected() -> void:
	if world.info_target != null and world.info_target.has("cat"):
		world.pet_cat(world.info_target.cat)


func _upgrade_selected() -> void:
	var it = world.info_target
	if it == null or not it.has("tile"):
		return
	if not world.upgrade(it.tile):
		toast("Не хватает монеток для улучшения")
	_info_t = 1.0


func _render_info() -> void:
	var it = world.info_target
	if it == null:
		info_panel.visible = false
		return
	var lines := []
	if it.has("cat"):
		var c: Dictionary = it.cat
		if not world.cats.has(c):
			world.info_target = null
			info_panel.visible = false
			return
		var fs: Dictionary = spr.cat_set(c.color, world.outfit_key(c))
		info_img.texture = Spr.scaled(fs.stand[0], 3)
		info_name.text = c.name
		info_sub.text = "%s котик · %s" % [D.CAT_COLORS[c.color].name, world.profession(c)]
		lines.append("Сейчас: " + world.activity_text(c))
		lines.append("Работа: " + (world.bname(c.job) if c.job >= 0 else "—"))
		lines.append("Дом: " + (world.bname(c.home) if c.home >= 0 else "пока нет — ждёт новое жильё"))
		var car_txt := "ходит пешком"
		if c.car != "":
			if c.state == "drive":
				car_txt = "за рулём"
			elif c.car_lot >= 0:
				car_txt = "на парковке «%s»" % world.bname(c.car_lot)
			elif c.car_tile >= 0:
				car_txt = "стоит прямо на дороге"
			else:
				car_txt = "в гараже дома"
		lines.append("Машина: " + car_txt)
		var hv: float = world.stats.house_happy.get(c.home, 50.0) - (25.0 if world.hungry else 0.0)
		lines.append("Настроение: " + _mood(hv))
		if world.hungry:
			lines.append("Хочет кушать! Нужен рыбный причал или пекарня.")
		info_pet.visible = true
		info_up.visible = false
	else:
		var i: int = it.tile
		var o = world.objs[i]
		if o == null or o.i != i:
			world.info_target = null
			info_panel.visible = false
			return
		var d := D.def(o.t)
		var tex: Texture2D = spr.scaffold[o.w] if o.build > 0.0 else spr.obj_texture(o)
		var k := clampi(56 / maxi(tex.get_width(), tex.get_height()), 1, 3)
		info_img.texture = Spr.scaled(tex, k)
		info_name.text = d.name
		var lvl := int(o.get("lvl", 1))
		var maxl: int = d.get("up", []).size() + 1
		info_sub.text = "Строится… %d%%" % int((1.0 - o.build / d.build) * 100.0) if o.build > 0.0 else ("Чудо света" if d.get("wonder", false) else ("Уровень %d из %d" % [lvl, maxl] if maxl > 1 else ""))
		if d.get("wonder", false) and o.build <= 0.0:
			lines.append("Туристы приносят +%s мон./с" % str(d.tourism))
		lines.append(d.desc)
		if d.has("cap") and o.build <= 0.0:
			var res: Array = world.residents.get(i, [])
			lines.append("")
			lines.append("Жильцы: %d/%d" % [res.size(), world.stat(o, "cap")])
			for c in res:
				lines.append("  • %s — %s" % [c.name, world.profession(c).to_lower()])
			if res.is_empty():
				lines.append("  Скоро сюда кто-нибудь переедет…")
			var hh: float = world.stats.house_happy.get(i, 0.0)
			lines.append("Уют: %d%%" % int(hh))
			if hh < 60.0:
				lines.append("Совет: дорога, тротуар, клумбы и городские службы рядом делают дом уютнее.")
		if d.has("jobs") and o.build <= 0.0:
			var ws: Array = world.workers.get(i, [])
			lines.append("")
			lines.append("Работники: %d/%d (%s)" % [ws.size(), world.stat(o, "jobs"), D.PROFESSIONS[d.job].to_lower()])
			for c in ws:
				lines.append("  • %s%s" % [c.name, " — на месте" if c.state == "in" and c.at == i else ""])
			if ws.is_empty():
				lines.append("  Ждём сотрудников — нужны новые жители.")
			if d.has("vehicle") and world.roads_around(i).is_empty():
				lines.append("Подведите дорогу, чтобы выезжала служебная машина.")
		if d.has("parking") and o.build <= 0.0:
			lines.append("")
			lines.append("Машин: %d/%d" % [world.lot_count.get(i, 0), int(world.stat(o, "parking"))])
			if world.roads_around(i).is_empty():
				lines.append("Подведите дорогу — иначе сюда не заехать.")
		if d.has("happy"):
			lines.append("Радость: +%d домам в радиусе %d" % [int(world.stat(o, "happy")), d.radius])
		if d.has("service"):
			lines.append("Уют района: +%d в радиусе %d" % [int(world.stat(o, "service")), d.sradius])
		if d.has("store_coins"):
			lines.append("Хранилище монет: +%d" % int(world.stat(o, "store_coins")))
		if d.has("store_food"):
			lines.append("Хранилище еды: +%d" % int(world.stat(o, "store_food")))
		info_pet.visible = false
		var uc: int = world.upgrade_cost(i) if o.build <= 0.0 else -1
		info_up.visible = uc >= 0
		if uc >= 0:
			info_up.text = "Улучшить до уровня %d — %s" % [int(o.get("lvl", 1)) + 1, "бесплатно" if world.unlimited else "%d мон." % uc]
			info_up.disabled = world.coins < uc and not world.unlimited
	info_body.text = "\n".join(lines)
	info_panel.visible = true


func _mood(v: float) -> String:
	if v >= 85.0:
		return "на седьмом небе"
	if v >= 65.0:
		return "счастливое"
	if v >= 45.0:
		return "спокойное"
	if v >= 25.0:
		return "скучает"
	return "грустное"


# ---------- уведомления ----------

func _build_toasts() -> void:
	toasts_box = VBoxContainer.new()
	toasts_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts_box.offset_top = 64
	toasts_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts_box)


func toast(msg: String, gold := false) -> void:
	if toasts_box == null:
		return
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if gold:
		p.add_theme_stylebox_override("panel", _sb(GOLD))
	var l := Label.new()
	l.text = msg
	p.add_child(l)
	toasts_box.add_child(p)
	if toasts_box.get_child_count() > 4:
		toasts_box.get_child(0).queue_free()
	var tw := p.create_tween()
	tw.tween_interval(3.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


# ---------- окна ----------

func _modal(content: Control) -> Control:
	var m := ColorRect.new()
	m.color = Color(0.157, 0.098, 0.196, 0.45)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(cc)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(PAPER, INK, 3, 10, 20.0))
	cc.add_child(p)
	# прокрутка — если окно выше экрана (большой масштаб интерфейса)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	sc.add_child(content)
	m.set_meta("scroll", sc)
	m.set_meta("content", content)
	m.visible = false
	root.add_child(m)
	return m


func _fit_modal(m: Control) -> void:
	var sc: ScrollContainer = m.get_meta("scroll")
	var content: Control = m.get_meta("content")
	var need := content.get_combined_minimum_size()
	sc.custom_minimum_size = Vector2(need.x + 12.0, minf(need.y, root.size.y - 90.0))


func _label(text: String, size := 16, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(560, 0)
	return l


func _build_help() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(_label("Добро пожаловать в Котоград!", 26, false))
	var cats := HBoxContainer.new()
	cats.alignment = BoxContainer.ALIGNMENT_CENTER
	cats.add_theme_constant_override("separation", 18)
	for pair in [["ginger", "builder"], ["gray", "developer"], ["white", "doctor"], ["calico", "blogger"], ["black", "police"], ["cream", "actor"], ["tabby", "surfer"], ["siamese", "lifeguard"]]:
		var r := TextureRect.new()
		r.texture = Spr.scaled(spr.cat_set(pair[0], pair[1]).stand[0], 4)
		cats.add_child(r)
	vb.add_child(cats)
	vb.add_child(_label("На солнечном калифорнийском побережье всегда хорошая погода. Постройте настоящий город, где котики живут, работают и отдыхают!"))
	vb.add_child(_label(
		"• Рельеф — начинаем на небольшом островке. Насыпайте землю и песок, а инструментом «Вода» убирайте сушу. Это бесплатно!\n" +
		"• Жильё — домики, коттеджи, виллы и многоэтажки. Сколько мест в домах — столько котиков в городе.\n" +
		"• Работа и бизнес — котики сами устраиваются на работу и надевают форму: блогеры, разработчики в худи, актёры, серферы, строители в касках…\n" +
		"• Город — мэрия, школа, больница, полиция, почта. Делают районы уютнее, а их машины разъезжают по улицам.\n" +
		"• Дороги — двусторонние, по ним котики утром едут на работу, а вечером домой. Дом и работа должны стоять у дороги. Пешком котики ходят по тротуарам и только переходят дорогу.\n" +
		"• Магистраль — по 2 полосы в каждую сторону: быстро и с обгонами. Здания к ней не подключаются.\n" +
		"• Холмы и горы — дома с видом уютнее, а особняки строятся только наверху.\n" +
		"• Улучшения — нажмите на здание: многие можно улучшить до 3 уровня — здание станет выше и наряднее.\n" +
		"• Лимиты — монеты и еда копятся до предела хранилищ: банки, склады и супермаркеты поднимают его.\n" +
		"• Парковки — котики оставляют на них машины. Если парковки рядом нет, машину бросают прямо на дороге, и начинаются пробки!\n" +
		"• Еда — рыбные причалы и пекарни. Отдых и природа — пляжи, пальмы, зонтики, фонтаны и знак KOTOWOOD.\n" +
		"• Чудеса — достопримечательности Лос-Анджелеса: обсерватория, пирс с колесом обозрения, стадион… Каждое строится один раз и привлекает туристов.\n" +
		"• Если снести дом, котики не пропадут: погуляют и переедут, как только появится новое жильё.", 15))
	var keys := PanelContainer.new()
	keys.add_theme_stylebox_override("panel", _sb(PAPER2, Color(0, 0, 0, 0), 0, 6, 10.0))
	keys.add_child(_label(
		"ЛКМ — строить (дороги можно вести мышью) · ПКМ / перетаскивание — двигать карту\n" +
		"Колесо — масштаб · WASD — камера · Tab — вкладки · 1–9 — постройки · B — лопатка\n" +
		"Рельеф, дороги и клумбы можно «рисовать», ведя мышью с зажатой кнопкой\n" +
		"Клик по котику или машине — узнать, кто это · Пробел — скорость · Esc — отмена", 13))
	vb.add_child(keys)
	var start := _btn("Мяу, начинаем!", func(): close_modals())
	start.add_theme_font_size_override("font_size", 20)
	start.add_theme_stylebox_override("normal", _sb(PINK, INK, 3, 8, 14.0))
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(start)
	help_modal = _modal(vb)


func _build_menu() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.add_child(_label("Меню", 24, false))
	vb.add_child(_label("Город сохраняется автоматически.", 15, false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	new_game_btn = _btn("Новый город", _on_new_game)
	row.add_child(new_game_btn)
	row.add_child(_btn("Настройки", func(): open_modal(settings_modal)))
	row.add_child(_btn("Продолжить", func(): close_modals()))
	if not _web:  # из браузера выходят, просто закрыв вкладку
		row.add_child(_btn("Выйти из игры", _quit_game, "Город сохранится автоматически"))
	vb.add_child(row)
	menu_modal = _modal(vb)


func _quit_game() -> void:
	world.save_game()
	get_tree().quit()


func _on_new_game() -> void:
	if not _confirm_new:
		_confirm_new = true
		new_game_btn.text = "Точно? Нажмите ещё раз"
		return
	world.new_game()
	close_modals()
	refresh_tools()
	toast("Новый остров ждёт котиков!")


func _setting_row(grid: GridContainer, title: String, ctrl: Control) -> void:
	grid.add_child(_label(title, 16, false))
	ctrl.custom_minimum_size = Vector2(240, 0)
	grid.add_child(ctrl)


func _build_settings() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.add_child(_label("Настройки", 24, false))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(grid)
	opt_res = OptionButton.new()
	opt_res.focus_mode = Control.FOCUS_NONE
	for r in RESOLUTIONS:
		opt_res.add_item("%d × %d" % [r.x, r.y])
	opt_res.selected = res_idx
	opt_res.item_selected.connect(_on_res)
	if not _web:  # в браузере игра занимает всю вкладку
		_setting_row(grid, "Разрешение окна", opt_res)
	chk_full = CheckButton.new()
	chk_full.focus_mode = Control.FOCUS_NONE
	chk_full.text = "Во весь экран"
	chk_full.button_pressed = fullscreen
	chk_full.toggled.connect(_on_full)
	_setting_row(grid, "Экран", chk_full)
	opt_scale = OptionButton.new()
	opt_scale.focus_mode = Control.FOCUS_NONE
	for k in UI_SCALES:
		opt_scale.add_item("%d%%" % int(k * 100))
	opt_scale.selected = maxi(0, UI_SCALES.find(ui_scale))
	opt_scale.item_selected.connect(_on_scale)
	_setting_row(grid, "Масштаб интерфейса", opt_scale)
	chk_music = CheckButton.new()
	chk_music.focus_mode = Control.FOCUS_NONE
	chk_music.text = "Включена"
	chk_music.button_pressed = sound.music_on
	chk_music.toggled.connect(_on_music)
	_setting_row(grid, "Музыка", chk_music)
	chk_unlim = CheckButton.new()
	chk_unlim.focus_mode = Control.FOCUS_NONE
	chk_unlim.text = "Неограниченные ресурсы"
	chk_unlim.tooltip_text = "Строить и улучшать всё бесплатно, без ожидания котиков. Котики всё равно переезжают постепенно."
	chk_unlim.button_pressed = unlimited
	chk_unlim.toggled.connect(_on_unlim)
	_setting_row(grid, "Режим игры", chk_unlim)
	var hint_lbl := _label("Масштаб карты меняется колёсиком мыши или кнопками − и +.", 13, false)
	hint_lbl.add_theme_color_override("font_color", Color(INK, 0.7))
	vb.add_child(hint_lbl)
	vb.add_child(_label("Сохранения", 18, false))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	srow.add_child(_btn("Экспорт в файл…", _on_export, "Сохранить город в файл .json — например, чтобы перенести на другой компьютер"))
	srow.add_child(_btn("Импорт из файла…", _on_import, "Загрузить город из файла .json. Текущий город будет заменён."))
	vb.add_child(srow)
	var done := _btn("Готово", func(): close_modals())
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(done)
	settings_modal = _modal(vb)


func _file_dialog(mode: int) -> FileDialog:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = mode
	fd.filters = PackedStringArray(["*.json ; Сохранение Котограда"])
	fd.use_native_dialog = true
	fd.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	add_child(fd)
	fd.canceled.connect(fd.queue_free)
	return fd


func _on_export() -> void:
	if _web:
		world.save_game()
		var name := "kotograd_den%d_%s.json" % [world.day, Time.get_date_string_from_system()]
		JavaScriptBridge.download_buffer(world.serialize().to_utf8_buffer(), name, "application/json")
		toast("Город скачан: " + name, true)
		return
	var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	var date := Time.get_date_string_from_system()
	fd.current_file = "kotograd_den%d_%s.json" % [world.day, date]
	fd.file_selected.connect(_export_to)
	fd.popup_centered(Vector2i(900, 600))


func _export_to(path: String) -> void:
	world.save_game()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		toast("Не получилось сохранить файл")
		return
	f.store_string(world.serialize())
	f.close()
	toast("Город сохранён: " + path.get_file(), true)


func _on_import() -> void:
	if _web:
		_web_import()
		return
	var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	fd.file_selected.connect(_import_from)
	fd.popup_centered(Vector2i(900, 600))


func _import_from(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	_import_text("" if f == null else f.get_as_text(), path.get_file())


func _import_text(text: String, fname: String) -> void:
	if text == "" or not world.import_save(text):
		toast("Этот файл не похож на сохранение Котограда")
		return
	close_modals()
	refresh_tools()
	refresh_speed()
	toast("Город загружен: " + fname, true)


## В браузере нет системного окна выбора файла — открываем выбор файла средствами страницы.
func _web_import() -> void:
	_js_import_cb = JavaScriptBridge.create_callback(_on_web_file)
	JavaScriptBridge.get_interface("window").kotoImport = _js_import_cb
	JavaScriptBridge.eval("""
		(function () {
			var inp = document.createElement('input');
			inp.type = 'file';
			inp.accept = '.json,application/json';
			inp.onchange = function () {
				var f = inp.files[0];
				if (f) f.text().then(function (t) { window.kotoImport(t, f.name); });
			};
			inp.click();
		})();
	""", true)


func _on_web_file(args: Array) -> void:
	_import_text(str(args[0]), str(args[1]))


func _on_res(i: int) -> void:
	res_idx = i
	_apply_display()
	_save_settings()


func _on_full(on: bool) -> void:
	fullscreen = on
	_apply_display()
	_save_settings()


func _on_scale(i: int) -> void:
	ui_scale = UI_SCALES[i]
	_apply_ui_scale()
	_save_settings()


func _on_unlim(on: bool) -> void:
	unlimited = on
	world.unlimited = on
	_save_settings()
	refresh_tools()
	toast("Неограниченные ресурсы: " + ("включены" if on else "выключены"), true)


func _on_music(on: bool) -> void:
	sound.set_music(on)
	_update_music_btn()


func _fit_root() -> void:
	var vs := get_viewport().get_visible_rect().size
	root.position = Vector2.ZERO
	root.size = vs / ui_scale
	_layout_bottom.call_deferred()


func _apply_ui_scale() -> void:
	scale = Vector2(ui_scale, ui_scale)
	_fit_root()


func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if _web:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var sz: Vector2i = RESOLUTIONS[res_idx]
	var scr := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(scr)
	sz = Vector2i(mini(sz.x, usable.size.x), mini(sz.y, usable.size.y))
	DisplayServer.window_set_size(sz)
	DisplayServer.window_set_position(usable.position + (usable.size - sz) / 2)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		res_idx = clampi(int(cfg.get_value("display", "resolution", 1)), 0, RESOLUTIONS.size() - 1)
		fullscreen = bool(cfg.get_value("display", "fullscreen", false))
		ui_scale = float(cfg.get_value("display", "ui_scale", 1.0))
		unlimited = bool(cfg.get_value("game", "unlimited", false))
		if not UI_SCALES.has(ui_scale):
			ui_scale = 1.0


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("display", "resolution", res_idx)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "ui_scale", ui_scale)
	cfg.set_value("game", "unlimited", unlimited)
	cfg.save("user://settings.cfg")


func open_modal(m: Control) -> void:
	close_modals()
	m.visible = true
	_fit_modal(m)


func close_modals() -> void:
	help_modal.visible = false
	menu_modal.visible = false
	if settings_modal:
		settings_modal.visible = false
	_confirm_new = false
	new_game_btn.text = "Новый город"


# ---------- обновление ----------

func _process(delta: float) -> void:
	_hud_t += delta
	if _hud_t > 0.2:
		_hud_t = 0.0
		_update_hud()
	_info_t += delta
	if _info_t > 0.3:
		_info_t = 0.0
		_render_info()


func _fmt(n: float) -> String:
	return "%.1fk" % (n / 1000.0) if n >= 10000.0 else str(int(n))


func _update_hud() -> void:
	lbl_coins.text = "∞" if world.unlimited else "%s/%s" % [_fmt(world.coins), _fmt(world.stats.coin_cap)]
	lbl_coins.add_theme_color_override("font_color", Color("c08a1a") if world.coins >= world.stats.coin_cap - 0.5 else INK)
	lbl_coin_rate.text = "+%.1f/с" % world.income
	lbl_food.text = "%s/%s" % [_fmt(world.food), _fmt(world.stats.food_cap)]
	lbl_food.add_theme_color_override("font_color", Color("c08a1a") if world.food >= world.stats.food_cap - 0.5 else INK)
	var net: float = world.stats.food_prod - world.eat_rate
	lbl_food_rate.text = "%s%.1f/с" % ["+" if net >= 0.0 else "", net]
	lbl_food_rate.add_theme_color_override("font_color", Color("c24a5a") if net < 0.0 else Color("4f8a4f"))
	lbl_cats.text = "%d/%d" % [world.cats.size(), world.stats.cap]
	lbl_jobs.text = "%d/%d" % [world.employed_count(), world.stats.jobs]
	happy_bar.value = world.happy
	lbl_happy.text = "%d%%" % int(world.happy)
	var h: float = world.hour()
	var hh := int(h)
	var mm := int((h - hh) * 6.0) * 10
	lbl_clock.text = "День %d · %02d:%02d" % [world.day, hh, mm]
	hint.text = _hint_text()
	refresh_tools()


func _hint_text() -> String:
	var st: Dictionary = world.stats
	if st.houses.is_empty() and st.constructing.is_empty():
		return "Начнём! Во вкладке «Жильё» постройте Домик, а во вкладке «Рельеф» можно бесплатно расширять остров."
	if world.cats.is_empty():
		return "Котик уже собирает чемодан и скоро приедет…"
	var homeless: int = world.homeless_count()
	if homeless > 0:
		return "Котиков без дома: %d. Постройте жильё — они сразу переедут!" % homeless
	if st.workplaces.is_empty():
		return "Подсказка: котикам нужна работа! Поставьте Рыбный причал у воды (вкладка «Работа»)."
	if world.hungry:
		return "Еда закончилась! Нужен ещё один рыбный причал или пекарня."
	var roads := 0
	for o in world.objs:
		if o != null and o.t == "road":
			roads += 1
			if roads >= 3:
				break
	if roads < 3:
		return "Подсказка: проложите Дорогу мимо домов и работы — котики поедут на машинах!"
	if world.cats.size() >= st.cap:
		return "Все дома заняты — постройте ещё жильё, чтобы приехали новые котики."
	var employed: int = world.employed_count()
	if employed < world.cats.size() and st.jobs <= employed:
		return "Не всем хватает работы — постройте магазин, пекарню или городские службы."
	if world.coins >= st.coin_cap - 0.5 and not world.unlimited:
		return "Хранилище монет заполнено! Потратьте монетки или постройте Банк (вкладка «Бизнес»)."
	if world.food >= st.food_cap - 0.5 and world.stats.food_prod > world.eat_rate:
		return "Склады еды полны — постройте Склад или Супермаркет, чтобы запасать больше."
	if world.street_parked.size() >= 3:
		return "Машины стоят прямо на дорогах — бывают пробки! Постройте Парковку рядом с работой и магазинами."
	if world.happy < 45.0:
		return "Котикам скучновато: украсьте город клумбами и деревьями рядом с домами."
	return ""

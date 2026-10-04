extends CanvasLayer
## Интерфейс: верхняя панель, вкладки построек, карточки, подсказки, справка.

const D = preload("res://scripts/defs.gd")
const Spr = preload("res://scripts/sprites.gd")
const Goals = preload("res://scripts/goals.gd")
const Title = preload("res://scripts/title.gd")
const I18n = preload("res://scripts/i18n.gd")

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
var title
var ui_font: SystemFont
var top_bar: HFlowContainer
var bottom_box: VBoxContainer
var lbl_brand: Label
var left_col: VBoxContainer
var goal_panel: PanelContainer
var goal_name: Label
var goal_desc: Label
var goal_bar: ProgressBar
var goal_count: Label
var event_panel: PanelContainer
var event_lbl: Label
var goals_modal: Control
var goals_list: VBoxContainer
var celebrate_modal: Control
var _ev_pos := Vector2.ZERO
var _tdrag_on := false        # листаем панель построек пальцем или мышью
var _tdrag_moved := false
var _tdrag_x := 0.0
var _tdrag_scroll := 0
var ui_scale := 1.0
var res_idx := 1
var fullscreen := false
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1440, 900), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const UI_SCALES := [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
var new_game_btn: Button
var _confirm_new := false
var build_hidden := false     # панель построек спрятана — любуемся городом
var show_build_btn: Button
var zen := false             # режим «Дзен»: без целей, подсказок и новостей
var btn_zen: Button
var chk_zen: CheckButton
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
	_build_left()
	title = Title.new()
	title.setup(self, world, spr)
	title.visible = false
	root.add_child(title)
	_build_help()
	_build_goals()
	_build_celebrate()
	_build_menu()
	_build_settings()
	set_tab(2)
	refresh_speed()
	_apply_display()
	_apply_ui_scale()
	world.unlimited = unlimited
	set_zen(zen, false)


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
	# мягкий округлый шрифт; в браузере системных шрифтов нет — там встроенный
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["Avenir Next", "Nunito", "Segoe UI", "Helvetica Neue"])
	ui_font.font_weight = 600
	ui_font.hinting = TextServer.HINTING_LIGHT
	ui_font.fallbacks = [ThemeDB.fallback_font]
	t.default_font = ui_font
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
	# полоса прокрутки в стиле игры: светлая дорожка, розовый бегунок
	var track := StyleBoxFlat.new()
	track.bg_color = PAPER2
	track.set_corner_radius_all(4)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color("ff8fab")
	grab.set_corner_radius_all(4)
	grab.border_color = Color(INK, 0.6)
	grab.set_border_width_all(1)
	var grab_h := grab.duplicate()
	grab_h.bg_color = Color("ffb3c6")
	for sb_name in ["HScrollBar", "VScrollBar"]:
		t.set_stylebox("scroll", sb_name, track)
		t.set_stylebox("scroll_focus", sb_name, track)
		t.set_stylebox("grabber", sb_name, grab)
		t.set_stylebox("grabber_highlight", sb_name, grab_h)
		t.set_stylebox("grabber_pressed", sb_name, grab_h)
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
	top_bar = top
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
	lbl_brand = bl
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
	btn_music = _btn("", _toggle_music, "Включить / выключить музыку")
	top.add_child(btn_music)
	_update_music_btn()
	top.add_child(_btn("Цели", _open_goals, "Задания и достижения"))
	btn_zen = _btn("Дзен", func(): set_zen(not zen), "Режим «Дзен»: спрятать цели, подсказки, новости и надписи над городом (Z)")
	btn_zen.toggle_mode = true
	top.add_child(btn_zen)
	top.add_child(_btn(" ? ", func(): open_modal(help_modal), "Как играть"))
	top.add_child(_btn("Меню", func(): open_modal(menu_modal)))


func _toggle_music() -> void:
	sound.set_music(not sound.music_on)
	_update_music_btn()


func _update_music_btn() -> void:
	btn_music.text = tr("Звук") if sound.music_on else tr("Тихо")


func refresh_speed() -> void:
	btn_speed.text = [tr("Пауза"), "x1", "x2", "x3"][world.speed]


# ---------- нижняя панель: вкладки и постройки ----------

func _build_bottom() -> void:
	var bottom := VBoxContainer.new()
	bottom_box = bottom
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
	show_build_btn = _btn("Постройки ▴", func(): set_build_hidden(false), "Показать панель построек (V)")
	show_build_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	show_build_btn.visible = false
	bottom.add_child(show_build_btn)
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
	tabs.add_child(_btn("Скрыть ▾", func(): set_build_hidden(true), "Спрятать панель построек и любоваться городом (V)"))

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
	b.pressed.connect(func(): _pick_tool(t))
	# пальцем по кнопкам можно листать панель — кнопка сама забирает касание у прокрутки
	b.gui_input.connect(_on_tools_drag)
	tool_buttons[t] = b
	_update_tool_button(t)
	return b


func _pick_tool(t: String) -> void:
	# кнопку отпустили после перелистывания — это не выбор постройки
	if _tdrag_moved:
		_tdrag_moved = false
		return
	world.select_tool(t)


func _on_tools_drag(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_tdrag_on = true
			_tdrag_moved = false
			_tdrag_x = e.global_position.x
			_tdrag_scroll = tools_scroll.scroll_horizontal
		else:
			_tdrag_on = false
	elif e is InputEventMouseMotion and _tdrag_on:
		var dx: float = (e.global_position.x - _tdrag_x) / ui_scale
		if absf(dx) > 8.0:
			_tdrag_moved = true
		if _tdrag_moved:
			tools_scroll.scroll_horizontal = int(_tdrag_scroll - dx)
			hide_tooltip()


func _tooltip(t: String) -> String:
	var d: Dictionary = D.DEFS.get(t, D.TOOL_INFO.get(t, {}))
	var s: String = tr(d.name)
	if d.has("terra"):
		s += tr("  ·  бесплатно")
	elif d.has("cost"):
		s += tr("  ·  %d мон.") % d.cost
	s += "\n" + tr(d.desc)
	var extra := []
	if d.get("wonder", false):
		extra.append(tr("Чудо света — можно построить только одно"))
		extra.append(tr("Туристы: +%s мон./с") % str(d.tourism))
	if d.get("size", 1) == 2:
		extra.append(tr("Размер: 2×2"))
	if d.has("cap"):
		extra.append(tr("Жильцов: %d") % d.cap)
	if d.has("jobs"):
		extra.append(tr("Рабочих мест: %d (%s)") % [d.jobs, tr(D.PROFESSIONS[d.job]).to_lower()])
	if d.has("food"):
		extra.append(tr("Даёт еду"))
	if d.has("happy"):
		extra.append(tr("Радость +%d в радиусе %d") % [d.happy, d.radius])
	if d.has("service"):
		extra.append(tr("Уют района +%d (радиус %d)") % [d.service, d.sradius])
	if d.has("shop"):
		extra.append(tr("Приносит монетки"))
	if d.has("vehicle"):
		extra.append(tr("Служебная машина (нужна дорога)"))
	if D.MAKES.has(t):
		var mk: Array = D.MAKES[t]
		if (mk[1] as Array).is_empty():
			extra.append(tr("Производит: %s") % tr(D.GOODS[mk[0]].name).to_lower())
		else:
			extra.append(tr("Перерабатывает: %s → %s") % [_goods_list(mk[1]), tr(D.GOODS[mk[0]].name).to_lower()])
	if D.USES.has(t):
		extra.append(tr("Ждёт товары: %s") % _goods_list(D.USES[t]))
	if d.has("build"):
		extra.append(tr("Стройка: %d с") % int(d.build))
	if not D.ups(t).is_empty():
		extra.append(tr("Можно улучшить до уровня %d") % (D.ups(t).size() + 1))
	if d.get("need_high", false):
		extra.append(tr("Только на холмах и в горах"))
	if d.has("store_coins"):
		extra.append(tr("Хранилище монет +%d") % d.store_coins)
	if d.has("store_food"):
		extra.append(tr("Хранилище еды +%d") % d.store_food)
	if d.has("tourism") and not d.get("wonder", false):
		extra.append(tr("Туристы: +%s мон./с") % str(d.tourism))
	if d.get("unlock", 0) > 0:
		extra.append(tr("Открывается при %d котиках") % d.unlock)
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
		line2 = tr("нужно %d кот.") % d.unlock
	elif d.get("wonder", false) and world.wonder_built(t):
		line2 = tr("построено")
	elif d.has("terra") or d.get("free", false) or (world.unlimited and d.has("cost")):
		line2 = tr("бесплатно")
	elif d.has("cost"):
		line2 = tr("%d мон.") % d.cost
	b.text = "%s\n%s" % [tr(d.name), line2]
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
		if build_hidden:
			set_build_hidden(false)
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
		toast(tr("Не хватает монеток для улучшения"))
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
		info_name.text = I18n.cat(c.name)
		info_sub.text = tr("%s котик · %s") % [tr(D.CAT_COLORS[c.color].name), world.profession(c)]
		lines.append(tr("Сейчас: ") + world.activity_text(c))
		lines.append(tr("Работа: ") + (world.bname(c.job) if c.job >= 0 else "—"))
		lines.append(tr("Дом: ") + (world.bname(c.home) if c.home >= 0 else tr("пока нет — ждёт новое жильё")))
		var car_txt := tr("ходит пешком")
		if c.car != "":
			if c.state == "drive":
				car_txt = tr("за рулём")
			elif c.car_lot >= 0:
				car_txt = tr("на парковке «%s»") % world.bname(c.car_lot)
			elif c.car_tile >= 0:
				car_txt = tr("стоит прямо на дороге")
			else:
				car_txt = tr("в гараже дома")
		lines.append(tr("Машина: ") + car_txt)
		var hv: float = world.stats.house_happy.get(c.home, 50.0) - (25.0 if world.hungry else 0.0)
		lines.append(tr("Настроение: ") + _mood(hv))
		if world.hungry:
			lines.append(tr("Хочет кушать! Нужен рыбный причал или пекарня."))
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
		info_name.text = tr(d.name)
		var lvl := int(o.get("lvl", 1))
		var maxl: int = D.ups(o.t).size() + 1
		info_sub.text = tr("Строится… %d%%") % int((1.0 - o.build / d.build) * 100.0) if o.build > 0.0 else (tr("Чудо света") if d.get("wonder", false) else (tr("Уровень %d из %d") % [lvl, maxl] if maxl > 1 else ""))
		if d.get("wonder", false) and o.build <= 0.0:
			lines.append(tr("Туристы приносят +%s мон./с") % str(d.tourism))
		lines.append(tr(d.desc))
		if d.has("cap") and o.build <= 0.0:
			var res: Array = world.residents.get(i, [])
			lines.append("")
			lines.append(tr("Жильцы: %d/%d") % [res.size(), world.stat(o, "cap")])
			for c in res:
				lines.append("  • %s — %s" % [I18n.cat(c.name), world.profession(c).to_lower()])
			if res.is_empty():
				lines.append(tr("  Скоро сюда кто-нибудь переедет…"))
			var hh: float = world.stats.house_happy.get(i, 0.0)
			lines.append(tr("Уют: %d%%") % int(hh))
			if hh < 60.0:
				lines.append(tr("Совет: дорога, тротуар, клумбы и городские службы рядом делают дом уютнее."))
		if d.has("jobs") and o.build <= 0.0:
			var ws: Array = world.workers.get(i, [])
			lines.append("")
			lines.append(tr("Работники: %d/%d (%s)") % [ws.size(), world.stat(o, "jobs"), tr(D.PROFESSIONS[d.job]).to_lower()])
			for c in ws:
				lines.append("  • %s%s" % [I18n.cat(c.name), tr(" — на месте") if c.state == "in" and c.at == i else ""])
			if ws.is_empty():
				lines.append(tr("  Ждём сотрудников — нужны новые жители."))
			if d.has("vehicle") and world.roads_around(i).is_empty():
				lines.append(tr("Подведите дорогу, чтобы выезжала служебная машина."))
		if o.build <= 0.0:
			lines.append_array(_chain_lines(o))
		if d.has("parking") and o.build <= 0.0:
			lines.append("")
			lines.append(tr("Машин: %d/%d") % [world.lot_count.get(i, 0), int(world.stat(o, "parking"))])
			if world.roads_around(i).is_empty():
				lines.append(tr("Подведите дорогу — иначе сюда не заехать."))
		if d.has("happy"):
			lines.append(tr("Радость: +%d домам в радиусе %d") % [int(world.stat(o, "happy")), d.radius])
		if d.has("service"):
			lines.append(tr("Уют района: +%d в радиусе %d") % [int(world.stat(o, "service")), d.sradius])
		if d.has("store_coins"):
			lines.append(tr("Хранилище монет: +%d") % int(world.stat(o, "store_coins")))
		if d.has("store_food"):
			lines.append(tr("Хранилище еды: +%d") % int(world.stat(o, "store_food")))
		info_pet.visible = false
		var uc: int = world.upgrade_cost(i) if o.build <= 0.0 else -1
		info_up.visible = uc >= 0
		if uc >= 0:
			info_up.text = tr("Улучшить до уровня %d — %s") % [int(o.get("lvl", 1)) + 1, tr("бесплатно") if world.unlimited else tr("%d мон.") % uc]
			info_up.disabled = world.coins < uc and not world.unlimited
	info_body.text = "\n".join(lines)
	info_panel.visible = true


func _goods_list(gs: Array) -> String:
	var names: Array = []
	for g in gs:
		names.append(tr(D.GOODS[g].name).to_lower())
	return ", ".join(names)


## Кто производит товар (для подсказок «откуда привезти»).
func _maker_of(g: String) -> String:
	for t in D.MAKES:
		if D.MAKES[t][0] == g:
			return tr(D.DEFS[t].name)
	return "—"


## Строки о производстве, сырье и поставках в карточке здания.
func _chain_lines(o: Dictionary) -> Array:
	var out: Array = []
	var d := D.def(o.t)
	if D.MAKES.has(o.t):
		var mk: Array = D.MAKES[o.t]
		out.append("")
		out.append(tr("Производит: %s — готово к отправке %d из %d") % [tr(D.GOODS[mk[0]].name).to_lower(), int(o.get("out", 0.0)), int(world.OUT_CAP)])
		var waiting: Array = []
		for g in mk[1]:
			var v: float = world.stock_of(o, g)
			out.append(tr("  Сырьё: %s — %d") % [tr(D.GOODS[g].name).to_lower(), int(v)])
			if v < 0.5:
				waiting.append(g)
		if not waiting.is_empty():
			for g in waiting:
				out.append(tr("  Ждёт сырьё: %s привезут грузовики от «%s»") % [tr(D.GOODS[g].name).to_lower(), _maker_of(g)])
		elif not (mk[1] as Array).is_empty() and o.get("busy", false):
			out.append(tr("  Работает на полную: доход +50%"))
		if world.workers.get(o.i, []).is_empty():
			out.append(tr("  Без работников производство стоит."))
		elif world.access_roads(o.i).is_empty():
			out.append(tr("  Подведите дорогу — грузовикам не выехать."))
	var uses: Array = D.USES.get(o.t, [])
	if not uses.is_empty():
		out.append("")
		var parts: Array = []
		var have := 0
		var missing: Array = []
		for g in uses:
			var v: float = world.stock_of(o, g)
			if v > 0.0:
				have += 1
				parts.append("%s ✓ %d" % [tr(D.GOODS[g].name), ceili(v)])
			else:
				parts.append("%s —" % tr(D.GOODS[g].name))
				missing.append(g)
		out.append(tr("Товары: %s") % "  ·  ".join(parts))
		if have > 0:
			out.append(tr("  С товарами доход выше: +%d%%") % int(60.0 * have / uses.size()))
		for g in missing:
			out.append(tr("  Нужно: %s — от «%s»") % [tr(D.GOODS[g].name).to_lower(), _maker_of(g)])
	if d.get("depot", false):
		out.append("")
		var parts: Array = []
		for g in o.get("stock", {}):
			if o.stock[g] >= 1.0:
				parts.append("%s %d" % [tr(D.GOODS[g].name), int(o.stock[g])])
		out.append(tr("На складе: %s") % (", ".join(parts) if not parts.is_empty() else tr("пусто")))
	if d.get("export", false):
		out.append("")
		out.append(tr("Продано на экспорт: %d") % world.exported)
	return out


func _mood(v: float) -> String:
	if v >= 85.0:
		return tr("на седьмом небе")
	if v >= 65.0:
		return tr("счастливое")
	if v >= 45.0:
		return tr("спокойное")
	if v >= 25.0:
		return tr("скучает")
	return tr("грустное")


# ---------- уведомления ----------

func _build_toasts() -> void:
	toasts_box = VBoxContainer.new()
	toasts_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts_box.offset_top = 64
	toasts_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts_box)


## news — городские новости и цели: в режиме «Дзен» их не показываем.
func toast(msg: String, gold := false, news := false) -> void:
	if toasts_box == null or (news and zen):
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
	while toasts_box.get_child_count() > 4:
		var old := toasts_box.get_child(0)
		toasts_box.remove_child(old)
		old.queue_free()
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
	# каждая строка — отдельная подпись: так она сама переводится при смене языка
	var bl := VBoxContainer.new()
	bl.add_theme_constant_override("separation", 2)
	for line in [
		"• Рельеф — начинаем на небольшом островке. Насыпайте землю и песок, а инструментом «Вода» убирайте сушу. Это бесплатно!",
		"• Жильё — домики, коттеджи, виллы и многоэтажки. Сколько мест в домах — столько котиков в городе.",
		"• Работа и бизнес — котики сами устраиваются на работу и надевают форму: блогеры, разработчики в худи, актёры, серферы, строители в касках…",
		"• Город — мэрия, школа, больница, полиция, почта. Делают районы уютнее, а их машины разъезжают по улицам.",
		"• Дороги — двусторонние, по ним котики утром едут на работу, а вечером домой. Дом и работа должны стоять у дороги. Пешком котики ходят по тротуарам и только переходят дорогу.",
		"• Магистраль — по 2 полосы в каждую сторону: быстро и с обгонами. Здания к ней не подключаются: подведите обычную дорогу вплотную — на стыке появится съезд с зелёным указателем.",
		"• Перекрёстки — где сходятся 3–4 дороги, сами появляются светофоры и пешеходные зебры: машины ждут зелёного, а котики переходят по зебре.",
		"• Поезда — проложите рельсы и поставьте вплотную к ним вокзал или платформу (минимум две). Поезд будет ходить сам, а котики — ездить в другие районы. Рельсы через дорогу — переезд со шлагбаумом.",
		"• Аэропорты — если их хотя бы два, котики летают между ними. Удобно для дальних островов.",
		"• Холмы и горы — дома с видом уютнее, а особняки строятся только наверху.",
		"• Улучшения — нажмите на здание: многие можно улучшить до 3 уровня — здание станет выше и наряднее.",
		"• Лимиты — монеты и еда копятся до предела хранилищ: банки, склады и супермаркеты поднимают его.",
		"• Парковки — котики оставляют на них машины. Если парковки рядом нет, машину бросают прямо на дороге, и начинаются пробки!",
		"• Еда — рыбные причалы и пекарни. Отдых и природа — пляжи, пальмы, зонтики, фонтаны и знак KOTOWOOD.",
		"• Чудеса — достопримечательности Лос-Анджелеса: обсерватория, пирс с колесом обозрения, стадион… Каждое строится один раз и привлекает туристов.",
		"• Если снести дом, котики не пропадут: погуляют и переедут, как только появится новое жильё.",
		"• Цели — слева сверху текущее задание, за каждое дают монетки. Все задания и достижения — кнопка «Цели».",
		"• События — иногда в городе праздник: фестиваль на пляже, ярмарка, премьера, салют. Гости приходят сами, а котики становятся счастливее.",
	]:
		bl.add_child(_label(line, 15))
	vb.add_child(bl)
	var keys := PanelContainer.new()
	keys.add_theme_stylebox_override("panel", _sb(PAPER2, Color(0, 0, 0, 0), 0, 6, 10.0))
	var kl := VBoxContainer.new()
	kl.add_theme_constant_override("separation", 0)
	keys.add_child(kl)
	for line in [
		"ЛКМ — строить (дороги можно вести мышью) · ПКМ / перетаскивание — двигать карту",
		"Колесо — масштаб · WASD — камера · Tab — вкладки · 1–9 — постройки · B — лопатка",
		"Рельеф, дороги и клумбы можно «рисовать», ведя мышью с зажатой кнопкой",
		"Клик по котику или машине — узнать, кто это · Пробел — скорость · Z — режим «Дзен» · V — спрятать постройки · Esc — отмена",
		"На телефоне: касание — строить или выбрать · один палец — двигать карту · два пальца — масштаб",
	]:
		kl.add_child(_label(line, 13))
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
	var title_l := _label("Меню", 24, false)
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title_l)
	var sub := _label("Город сохраняется автоматически.", 15, false)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	# кнопки — вертикальным столбиком, как на стартовом экране
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var cont := _menu_btn("Продолжить", func(): close_modals())
	cont.add_theme_stylebox_override("normal", _sb(PINK, INK, 3, 8, 12.0))
	col.add_child(cont)
	col.add_child(_menu_btn("Настройки", func(): open_modal(settings_modal)))
	col.add_child(_menu_btn("Главное меню", func(): show_title(true)))
	new_game_btn = _menu_btn("Новый город", _on_new_game)
	col.add_child(new_game_btn)
	if not _web:  # из браузера выходят, просто закрыв вкладку
		var q := _menu_btn("Выйти из игры", _quit_game)
		q.tooltip_text = "Город сохранится автоматически"
		col.add_child(q)
	vb.add_child(col)
	menu_modal = _modal(vb)


func _menu_btn(text: String, cb: Callable) -> Button:
	var b := _btn(text, cb)
	b.custom_minimum_size = Vector2(300, 0)
	b.add_theme_font_size_override("font_size", 20)
	return b


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
	toast(tr("Новый остров ждёт котиков!"))


func _setting_row(grid: GridContainer, title: String, ctrl: Control) -> void:
	grid.add_child(_label(title, 16, false))
	ctrl.custom_minimum_size = Vector2(240, 0)
	grid.add_child(ctrl)


func _build_settings() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.add_child(_label("Настройки", 24, false))
	var grid := GridContainer.new()
	var opt_lang := OptionButton.new()
	opt_lang.focus_mode = Control.FOCUS_NONE
	opt_lang.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for lg in I18n.LANGS:
		opt_lang.add_item(lg[1])
		if lg[0] == I18n.lang():
			opt_lang.selected = opt_lang.item_count - 1
	opt_lang.item_selected.connect(_on_lang)
	_setting_row(grid, "Язык · Language", opt_lang)
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
	_setting_row(grid, "Музыка", _volume_slider("music", sound.music_vol))
	var opt_track := OptionButton.new()
	opt_track.focus_mode = Control.FOCUS_NONE
	for tk in sound.TRACKS:
		opt_track.add_item(tk.name)
		if tk.id == sound.track:
			opt_track.selected = opt_track.item_count - 1
	opt_track.item_selected.connect(_on_track)
	_setting_row(grid, "Трек", opt_track)
	_setting_row(grid, "Звуки", _volume_slider("sfx", sound.sfx_vol))
	_setting_row(grid, "Окружение", _volume_slider("amb", sound.amb_vol))
	chk_unlim = CheckButton.new()
	chk_unlim.focus_mode = Control.FOCUS_NONE
	chk_unlim.text = "Неограниченные ресурсы"
	chk_unlim.tooltip_text = "Строить и улучшать всё бесплатно, без ожидания котиков. Котики всё равно переезжают постепенно."
	chk_unlim.button_pressed = unlimited
	chk_unlim.toggled.connect(_on_unlim)
	_setting_row(grid, "Режим игры", chk_unlim)
	chk_zen = CheckButton.new()
	chk_zen.focus_mode = Control.FOCUS_NONE
	chk_zen.text = "Режим «Дзен»"
	chk_zen.tooltip_text = "Только город, музыка и стройка: без целей, подсказок, новостей, гудков и надписей над котиками и машинами. Цели всё равно засчитываются тихо."
	chk_zen.button_pressed = zen
	chk_zen.toggled.connect(set_zen)
	_setting_row(grid, "", chk_zen)
	var hint_lbl := _label("Масштаб карты — колёсико мыши, клавиши − и + или два пальца на телефоне.", 13, false)
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
	fd.filters = PackedStringArray([tr("*.json ; Сохранение Котограда")])
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
		toast(tr("Город скачан: ") + name, true)
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
		toast(tr("Не получилось сохранить файл"))
		return
	f.store_string(world.serialize())
	f.close()
	toast(tr("Город сохранён: ") + path.get_file(), true)


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
		toast(tr("Этот файл не похож на сохранение Котограда"))
		return
	close_modals()
	refresh_tools()
	refresh_speed()
	toast(tr("Город загружен: ") + fname, true)


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
	toast(tr("Неограниченные ресурсы: ") + (tr("включены") if on else tr("выключены")), true)


func _volume_slider(kind: String, v: float) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 5
	sl.value = v * 100.0
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(240, 24)
	sl.value_changed.connect(func(x: float): sound.set_volume(kind, x / 100.0))
	return sl


func _fit_root() -> void:
	var vs := get_viewport().get_visible_rect().size
	root.position = Vector2.ZERO
	root.size = vs / ui_scale
	_layout_bottom.call_deferred()


func _apply_ui_scale() -> void:
	scale = Vector2(ui_scale, ui_scale)
	# буквы растеризуем сразу в нужном размере — иначе при масштабе 175–200% они мутные
	ui_font.oversampling = ui_scale
	ThemeDB.fallback_font.oversampling = ui_scale
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
	# первый запуск: масштаб интерфейса по плотности экрана (телефоны, Retina)
	ui_scale = _auto_scale()
	if cfg.load("user://settings.cfg") == OK and cfg.has_section_key("display", "ui_scale"):
		res_idx = clampi(int(cfg.get_value("display", "resolution", 1)), 0, RESOLUTIONS.size() - 1)
		fullscreen = bool(cfg.get_value("display", "fullscreen", false))
		ui_scale = float(cfg.get_value("display", "ui_scale", ui_scale))
		unlimited = bool(cfg.get_value("game", "unlimited", false))
		zen = bool(cfg.get_value("game", "zen", false))
		if not UI_SCALES.has(ui_scale):
			ui_scale = 1.0


func _auto_scale() -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
	var sc := DisplayServer.screen_get_scale()
	var best := 1.0
	for k in UI_SCALES:
		if absf(k - sc) < absf(best - sc):
			best = k
	return best


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("display", "resolution", res_idx)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "ui_scale", ui_scale)
	cfg.set_value("game", "unlimited", unlimited)
	cfg.set_value("game", "zen", zen)
	cfg.save("user://settings.cfg")


func open_modal(m: Control) -> void:
	close_modals()
	m.visible = true
	_fit_modal(m)


func close_modals() -> void:
	help_modal.visible = false
	menu_modal.visible = false
	if goals_modal:
		goals_modal.visible = false
	if celebrate_modal:
		celebrate_modal.visible = false
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
	lbl_coin_rate.text = tr("+%.1f/с") % world.income
	lbl_food.text = "%s/%s" % [_fmt(world.food), _fmt(world.stats.food_cap)]
	lbl_food.add_theme_color_override("font_color", Color("c08a1a") if world.food >= world.stats.food_cap - 0.5 else INK)
	var net: float = world.stats.food_prod - world.eat_rate
	lbl_food_rate.text = tr("%s%.1f/с") % ["+" if net >= 0.0 else "", net]
	lbl_food_rate.add_theme_color_override("font_color", Color("c24a5a") if net < 0.0 else Color("4f8a4f"))
	lbl_cats.text = "%d/%d" % [world.cats.size(), world.stats.cap]
	lbl_jobs.text = "%d/%d" % [world.employed_count(), world.stats.jobs]
	happy_bar.value = world.happy
	lbl_happy.text = "%d%%" % int(world.happy)
	var h: float = world.hour()
	var hh := int(h)
	var mm := int((h - hh) * 6.0) * 10
	lbl_clock.text = tr("День %d · %02d:%02d") % [world.day, hh, mm]
	hint.text = _hint_text()
	lbl_brand.text = tr(world.city_name)
	_update_goal_panel()
	# верхняя строка может переноситься на два ряда — ставим панель цели под её реальным низом
	var bottom_y := 0.0
	for ch in top_bar.get_children():
		var cc := ch as Control
		if cc != null and cc.visible:
			bottom_y = maxf(bottom_y, cc.position.y + cc.size.y)
	left_col.position.y = top_bar.position.y + bottom_y + 8.0
	# если между верхней строкой и панелью построек нет места — панель цели прячется сама
	if not zen and not title_open():
		var room: float = (bottom_box.position.y if bottom_box.visible else root.size.y) - left_col.position.y
		left_col.visible = left_col.get_combined_minimum_size().y + 8.0 < room
	refresh_tools()


func _hint_text() -> String:
	var st: Dictionary = world.stats
	if st.houses.is_empty() and st.constructing.is_empty():
		return tr("Начнём! Во вкладке «Жильё» постройте Домик, а во вкладке «Рельеф» можно бесплатно расширять остров.")
	if world.cats.is_empty():
		return tr("Котик уже собирает чемодан и скоро приедет…")
	var homeless: int = world.homeless_count()
	if homeless > 0:
		return tr("Котиков без дома: %d. Постройте жильё — они сразу переедут!") % homeless
	if st.workplaces.is_empty():
		return tr("Подсказка: котикам нужна работа! Поставьте Рыбный причал у воды (вкладка «Еда»).")
	if world.hungry:
		return tr("Еда закончилась! Нужен ещё один рыбный причал или пекарня.")
	var roads := 0
	for o in world.objs:
		if o != null and o.t == "road":
			roads += 1
			if roads >= 3:
				break
	if roads < 3:
		return tr("Подсказка: проложите Дорогу мимо домов и работы — котики поедут на машинах!")
	if world.cats.size() >= st.cap:
		return tr("Все дома заняты — постройте ещё жильё, чтобы приехали новые котики.")
	var employed: int = world.employed_count()
	if employed < world.cats.size() and st.jobs <= employed:
		return tr("Не всем хватает работы — постройте магазин, пекарню или городские службы.")
	if world.coins >= st.coin_cap - 0.5 and not world.unlimited:
		return tr("Хранилище монет заполнено! Потратьте монетки или постройте Банк (вкладка «Бизнес»).")
	if world.food >= st.food_cap - 0.5 and world.stats.food_prod > world.eat_rate:
		return tr("Склады еды полны — постройте Склад или Супермаркет, чтобы запасать больше.")
	if world.street_parked.size() >= 3:
		return tr("Машины стоят прямо на дорогах — бывают пробки! Постройте Парковку рядом с работой и магазинами.")
	if world.happy < 45.0:
		return tr("Котикам скучновато: украсьте город клумбами и деревьями рядом с домами.")
	return ""


# ---------- стартовый экран ----------

func title_open() -> bool:
	return title != null and title.visible


func show_title(has_city: bool) -> void:
	close_modals()
	world.info_target = null
	world.select_tool("hand")
	set_hud(false)
	title.open(has_city)


func hide_title() -> void:
	title.visible = false
	set_hud(true)


func set_hud(v: bool) -> void:
	top_bar.visible = v
	bottom_box.visible = v
	left_col.visible = v and not zen
	hint.visible = not zen
	toasts_box.visible = v
	if not v:
		info_panel.visible = false


# ---------- цели ----------

func _build_left() -> void:
	left_col = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left_col.position = Vector2(10, 64)
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left_col)

	goal_panel = PanelContainer.new()
	goal_panel.add_theme_stylebox_override("panel", _sb(PAPER, INK, 3, 8, 10.0))
	goal_panel.custom_minimum_size = Vector2(250, 0)
	goal_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	goal_panel.tooltip_text = "Нажмите, чтобы увидеть все цели и достижения"
	goal_panel.gui_input.connect(_on_goal_panel_input)
	left_col.add_child(goal_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	goal_panel.add_child(vb)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hb)
	hb.add_child(_icon(spr.icons.heart, 14))
	goal_name = Label.new()
	goal_name.add_theme_font_size_override("font_size", 15)
	hb.add_child(goal_name)
	goal_desc = Label.new()
	goal_desc.add_theme_font_size_override("font_size", 13)
	goal_desc.add_theme_color_override("font_color", Color(INK, 0.8))
	goal_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_desc.custom_minimum_size = Vector2(230, 0)
	vb.add_child(goal_desc)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 6)
	vb.add_child(pr)
	goal_bar = ProgressBar.new()
	goal_bar.show_percentage = false
	goal_bar.custom_minimum_size = Vector2(150, 12)
	goal_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	goal_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pr.add_child(goal_bar)
	goal_count = Label.new()
	goal_count.add_theme_font_size_override("font_size", 13)
	pr.add_child(goal_count)

	event_panel = PanelContainer.new()
	event_panel.add_theme_stylebox_override("panel", _sb(GOLD, INK, 3, 8, 10.0))
	event_panel.visible = false
	left_col.add_child(event_panel)
	var eh := HBoxContainer.new()
	eh.add_theme_constant_override("separation", 8)
	event_panel.add_child(eh)
	event_lbl = Label.new()
	event_lbl.add_theme_font_size_override("font_size", 14)
	event_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_lbl.custom_minimum_size = Vector2(150, 0)
	event_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eh.add_child(event_lbl)
	eh.add_child(_btn("Показать", func(): world.center_cam(_ev_pos.x, _ev_pos.y), "Перенести камеру к празднику"))


func _on_goal_panel_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_open_goals()


func _update_goal_panel() -> void:
	var q: Dictionary = world.goals.quest()
	if q.is_empty():
		goal_name.text = "Все задания выполнены!"
		goal_desc.text = "Город стал легендой. Стройте дальше в своё удовольствие."
		goal_bar.value = 100
		goal_count.text = ""
	else:
		var m: Dictionary = world.goals.metrics()
		var p: int = world.goals.progress(q, m)
		goal_name.text = tr(q.name)
		goal_desc.text = tr(q.desc)
		goal_bar.max_value = float(q.n)
		goal_bar.value = float(p)
		goal_count.text = "%d/%d" % [p, q.n]
	# на маленьком экране — компактно, чтобы не закрывать карту
	goal_desc.visible = root.size.y >= 620.0
	var ev = world.events.active
	event_panel.visible = ev != null
	if ev != null:
		event_lbl.text = tr("Праздник: %s\nещё %d ч.") % [tr(ev.name), maxi(1, ceili(ev.left))]


## Несколько целей сразу (например, после загрузки) — одним сообщением.
func goals_done(list: Array) -> void:
	if list.size() <= 2:
		for g in list:
			goal_done(g)
		return
	var reward := 0
	for g in list:
		if g.id == "legend":
			goal_done(g)
		else:
			reward += int(g.get("r", 0))
	if reward > 0 and not world.unlimited:
		world.coins += reward
	if zen:
		return
	sound.play("fanfare", 1.0, -6.0)
	toast(tr("Выполнено целей и достижений: %d!%s") % [list.size(), (tr("  +%d мон.") % reward) if reward > 0 and not world.unlimited else ""], true, true)
	_confetti(40)


func goal_done(g: Dictionary) -> void:
	var reward := int(g.get("r", 0))
	var is_quest := g.has("r")
	if reward > 0 and not world.unlimited:
		world.coins += reward
	if zen and g.id != "legend":
		return
	sound.play("fanfare", 1.0, -6.0)
	if is_quest:
		toast(tr("Цель выполнена: «%s»%s") % [tr(g.name), (tr("  +%d мон.") % reward) if reward > 0 and not world.unlimited else ""], true, true)
	else:
		toast(tr("Достижение: «%s» — %s") % [tr(g.name), tr(g.desc)], true, true)
	_confetti(40 if is_quest else 24)
	if g.id == "legend":
		open_modal(celebrate_modal)
		world.events.force("fireworks")


## Конфетти над экраном.
func _confetti(n: int) -> void:
	var vs: Vector2 = world.view_size()
	var tl: Vector2 = world.cam.position - vs / 2.0
	for k in n:
		world.add_p({"type": "confetti", "x": tl.x + randf() * vs.x, "y": tl.y - randf() * 10.0, "vx": randf_range(-8, 8), "vy": randf_range(10, 30), "g": 25.0, "life": randf_range(2.5, 4.0), "col": ["ff6b8b", "ffd75e", "7fc4e8", "c8a8ff", "9ed8c8"].pick_random(), "ph": randf() * 6.0})


func _build_goals() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(_label("Цели и достижения", 24, false))
	goals_list = VBoxContainer.new()
	goals_list.add_theme_constant_override("separation", 4)
	vb.add_child(goals_list)
	var done_b := _btn("Закрыть", func(): close_modals())
	done_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(done_b)
	goals_modal = _modal(vb)


func _goal_row(g: Dictionary, m: Dictionary, current: bool) -> Control:
	var done: bool = world.goals.done.has(g.id)
	var p := PanelContainer.new()
	var bg := GOLD if done else (PINK if current else PAPER2)
	p.add_theme_stylebox_override("panel", _sb(bg, Color(0, 0, 0, 0), 0, 6, 8.0))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	var mark := Label.new()
	mark.text = "✓" if done else ("→" if current else "·")
	mark.custom_minimum_size = Vector2(18, 0)
	mark.add_theme_font_size_override("font_size", 18)
	hb.add_child(mark)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(tv)
	var n := Label.new()
	n.text = tr(g.name)
	n.add_theme_font_size_override("font_size", 15)
	tv.add_child(n)
	var d := Label.new()
	d.text = tr(g.desc)
	d.add_theme_font_size_override("font_size", 13)
	d.add_theme_color_override("font_color", Color(INK, 0.75))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(380, 0)
	tv.add_child(d)
	var r := Label.new()
	r.add_theme_font_size_override("font_size", 13)
	if done:
		r.text = tr("готово")
	else:
		r.text = "%d/%d" % [world.goals.progress(g, m), g.n]
	if g.has("r"):
		r.text += tr("\n+%d мон.") % g.r
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.custom_minimum_size = Vector2(80, 0)
	hb.add_child(r)
	return p


func _open_goals() -> void:
	for c in goals_list.get_children():
		c.queue_free()
	var m: Dictionary = world.goals.metrics()
	var cur: Dictionary = world.goals.quest()
	var nq := 0
	for q in Goals.QUESTS:
		if world.goals.done.has(q.id):
			nq += 1
	goals_list.add_child(_label(tr("Задания: %d из %d") % [nq, Goals.QUESTS.size()], 18, false))
	for q in Goals.QUESTS:
		goals_list.add_child(_goal_row(q, m, not cur.is_empty() and q.id == cur.id))
	var na := 0
	for a in Goals.ACHIEVEMENTS:
		if world.goals.done.has(a.id):
			na += 1
	goals_list.add_child(_label(tr("Достижения: %d из %d") % [na, Goals.ACHIEVEMENTS.size()], 18, false))
	for a in Goals.ACHIEVEMENTS:
		goals_list.add_child(_goal_row(a, m, false))
	open_modal(goals_modal)


func _build_celebrate() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := _label("Город-легенда!", 30, false)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var cats := HBoxContainer.new()
	cats.alignment = BoxContainer.ALIGNMENT_CENTER
	cats.add_theme_constant_override("separation", 14)
	for pair in [["ginger", "builder"], ["white", "doctor"], ["calico", "blogger"], ["cream", "actor"], ["siamese", "lifeguard"]]:
		var r := TextureRect.new()
		r.texture = Spr.scaled(spr.cat_set(pair[0], pair[1]).stand[0], 4)
		cats.add_child(r)
	vb.add_child(cats)
	var txt := _label("Все чудеса света построены, и о вашем городе знает всё побережье. Котики устраивают в вашу честь большой салют!\n\nВсе задания выполнены, но город можно строить и дальше: ищите новые достижения и праздники.")
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(txt)
	var ok := _btn("Ура!", func(): close_modals())
	ok.add_theme_font_size_override("font_size", 20)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(ok)
	celebrate_modal = _modal(vb)


# ---------- события ----------

func event_started(ev: Dictionary, desc: String) -> void:
	_ev_pos = ev.pos
	toast("%s! %s" % [tr(ev.name), tr(desc)], true, true)


func event_finished(ev: Dictionary) -> void:
	toast(tr("%s закончился — котики довольны!") % tr(ev.name) if ev.kind == "game" or ev.kind == "fireworks" else tr("Праздник «%s» закончился — котики довольны!") % tr(ev.name), false, true)


# ---------- режим «Дзен» ----------

func set_zen(on: bool, announce := true) -> void:
	zen = on
	btn_zen.set_pressed_no_signal(on)
	if chk_zen:
		chk_zen.set_pressed_no_signal(on)
	if not title_open():
		left_col.visible = not on
	hint.visible = not on
	if announce:
		_save_settings()
		toast(tr("Режим «Дзен»: только город, музыка и стройка") if on else tr("Режим «Дзен» выключен: цели и подсказки снова на месте"), true)


func _on_track(i: int) -> void:
	sound.set_track(sound.TRACKS[i].id)
	toast(tr("Сейчас играет: %s") % tr(sound.TRACKS[i].name), true)


# ---------- любоваться городом ----------

func set_build_hidden(on: bool) -> void:
	build_hidden = on
	toolbar_panel.visible = not on
	show_build_btn.visible = on
	if on:
		world.select_tool("hand")
		hide_tooltip()


# ---------- язык ----------

func _on_lang(i: int) -> void:
	I18n.set_lang(I18n.LANGS[i][0])
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("game", "lang", I18n.LANGS[i][0])
	cfg.save("user://settings.cfg")
	# подписи Godot переводит сам, составные тексты пересобираем
	set_tab(tab)
	refresh_speed()
	_update_music_btn()
	_update_hud()
	new_game_btn.text = "Новый город"
	if title_open():
		title.open(title._btn_continue.visible)

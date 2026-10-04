extends Control
## Стартовый экран: логотип, котики и меню. Позади медленно проплывает ваш город.

const Spr = preload("res://scripts/sprites.gd")
const INK := Color("3b2a3a")
const NAMES := ["Котоград", "Санта-Мурика", "Мурбелла-Бич", "Лос-Котос", "Мяу-Бэй", "Мурлибу", "Кошачья Бухта", "Санта-Кэтлина", "Пальм-Котингс", "Котосвилл", "Мурсайд", "Лапа-Верде"]
const SHOWCASE := [["ginger", "surfer"], ["gray", "developer"], ["white", "doctor"], ["calico", "blogger"], ["black", "police"], ["cream", "actor"], ["tabby", "builder"], ["siamese", "lifeguard"]]

var ui
var world
var _cats: Array = []
var _menu_box: VBoxContainer
var _name_box: VBoxContainer
var _btn_continue: Button
var _name_edit: LineEdit
var _warn: Label
var _island := "sa"
var _isl_btns := {}
var _isl_desc: Label
var _t := 0.0
var _drift := 1.0


func setup(user_interface, w, spr) -> void:
	ui = user_interface
	world = w
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# закатная дымка поверх города
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.29, 0.16, 0.42, 0.62), Color(1.0, 0.45, 0.55, 0.28), Color(1.0, 0.62, 0.32, 0.6)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	bg.texture = gt
	add_child(bg)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)
	vb.add_child(make_logo())

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for pair in SHOWCASE:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(40, 72)
		var r := TextureRect.new()
		r.texture = Spr.scaled(spr.cat_set(pair[0], pair[1]).stand[0], 4)
		holder.add_child(r)
		row.add_child(holder)
		_cats.append(r)
	vb.add_child(row)

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 10)
	_menu_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(_menu_box)
	_btn_continue = _big("Продолжить", _on_continue, true)
	_menu_box.add_child(_btn_continue)
	_menu_box.add_child(_big("Новый город", _on_new))
	_menu_box.add_child(_big("Настройки", func(): ui.open_modal(ui.settings_modal)))
	_menu_box.add_child(_big("Как играть", func(): ui.open_modal(ui.help_modal)))
	if not OS.has_feature("web"):
		_menu_box.add_child(_big("Выйти", _quit))

	# выбор названия нового города
	_name_box = VBoxContainer.new()
	_name_box.add_theme_constant_override("separation", 10)
	_name_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_name_box.visible = false
	vb.add_child(_name_box)
	var panel := PanelContainer.new()
	_name_box.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	panel.add_child(pv)
	var q := Label.new()
	q.text = "Как назовём город?"
	q.add_theme_font_size_override("font_size", 22)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(q)
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 8)
	pv.add_child(nr)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(260, 0)
	_name_edit.max_length = 24
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.text_submitted.connect(func(_t): _on_found())
	nr.add_child(_name_edit)
	nr.add_child(ui._btn("Другое", func(): _name_edit.text = _random_name(), "Придумать другое название"))
	# выбор острова: три карточки с картинкой
	var iq := Label.new()
	iq.text = "Какой остров?"
	iq.add_theme_font_size_override("font_size", 18)
	iq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(iq)
	var ir := HBoxContainer.new()
	ir.alignment = BoxContainer.ALIGNMENT_CENTER
	ir.add_theme_constant_override("separation", 8)
	pv.add_child(ir)
	for it in world.ISLANDS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.icon = _island_preview(it[0])
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.text = it[1]
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_pick_island.bind(it[0]))
		ir.add_child(b)
		_isl_btns[it[0]] = b
	_isl_desc = Label.new()
	_isl_desc.add_theme_font_size_override("font_size", 13)
	_isl_desc.add_theme_color_override("font_color", Color(INK, 0.75))
	_isl_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_isl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_isl_desc.custom_minimum_size = Vector2(340, 0)
	pv.add_child(_isl_desc)
	_pick_island("sa")
	_warn = Label.new()
	_warn.add_theme_color_override("font_color", Color("c24a5a"))
	_warn.add_theme_font_size_override("font_size", 14)
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.custom_minimum_size = Vector2(340, 0)
	pv.add_child(_warn)
	var br := HBoxContainer.new()
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.add_theme_constant_override("separation", 10)
	pv.add_child(br)
	br.add_child(ui._btn("Назад", _show_menu))
	var found: Button = ui._btn("Основать город!", _on_found)
	found.add_theme_stylebox_override("normal", ui._sb(ui.PINK, INK, 3, 8, 10.0))
	br.add_child(found)

	var foot := Label.new()
	foot.text = "Вся графика и музыка нарисованы кодом · сделано с любовью к котикам"
	foot.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	foot.add_theme_color_override("font_outline_color", Color(INK, 0.8))
	foot.add_theme_constant_override("outline_size", 5)
	foot.add_theme_font_size_override("font_size", 13)
	foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	foot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_bottom = -12
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(foot)


## Логотип — тот же, что на загрузочной картинке.
static func make_logo() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	var l := Label.new()
	l.text = "Котоград"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 84)
	l.add_theme_color_override("font_color", Color("fff6ea"))
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 22)
	l.add_theme_color_override("font_shadow_color", Color("ff8fab"))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 7)
	l.add_theme_constant_override("shadow_outline_size", 22)
	vb.add_child(l)
	var sub := Label.new()
	sub.text = "уютный город для котиков у океана"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color.WHITE)
	sub.add_theme_color_override("font_outline_color", INK)
	sub.add_theme_constant_override("outline_size", 9)
	vb.add_child(sub)
	return vb


func _quit() -> void:
	world.save_game()
	get_tree().quit()


func _big(text: String, cb: Callable, primary := false) -> Button:
	var b: Button = ui._btn(text, cb)
	b.custom_minimum_size = Vector2(300, 0)
	b.add_theme_font_size_override("font_size", 20)
	if primary:
		b.add_theme_stylebox_override("normal", ui._sb(ui.PINK, INK, 3, 8, 12.0))
	return b


func open(has_city: bool) -> void:
	visible = true
	_btn_continue.visible = has_city
	_btn_continue.text = tr("Продолжить: %s") % tr(world.city_name)
	_show_menu()


func _show_menu() -> void:
	_menu_box.visible = true
	_name_box.visible = false


func _random_name() -> String:
	var n: String = tr(NAMES.pick_random())
	while n == _name_edit.text and NAMES.size() > 1:
		n = tr(NAMES.pick_random())
	return n


## Маленькая карта острова для карточки выбора.
func _island_preview(kind: String) -> Texture2D:
	var cols := [Color("9bd67f"), Color("6cc1e0"), Color("f1dfa6"), Color("b4e294"), Color("b4a48c"), Color("d4c88a"), Color("c8e8a0")]
	var t: PackedByteArray = world.gen_terrain(kind, 4242)
	var img := Image.create_empty(world.W, world.H, false, Image.FORMAT_RGBA8)
	for y in world.H:
		for x in world.W:
			img.set_pixel(x, y, cols[t[y * world.W + x]])
	return ImageTexture.create_from_image(img)


func _pick_island(kind: String) -> void:
	_island = kind
	for k in _isl_btns:
		_isl_btns[k].add_theme_stylebox_override("normal", ui._sb(ui.PINK, INK, 3, 8, 6.0) if k == kind else ui._sb(ui.PAPER, Color(INK, 0.4), 2, 8, 6.0))
	for it in world.ISLANDS:
		if it[0] == kind:
			_isl_desc.text = tr(it[2])


func _on_continue() -> void:
	ui.hide_title()


func _on_new() -> void:
	_menu_box.visible = false
	_name_box.visible = true
	_name_edit.text = _random_name()
	_warn.text = (tr("Город «%s» будет заменён новым островом.") % tr(world.city_name)) if _btn_continue.visible else ""
	_warn.visible = _btn_continue.visible
	_name_edit.grab_focus()


func _on_found() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "":
		n = "Котоград"
	world.island = _island
	world.new_game()
	world.city_name = n
	world.save_game()
	ui.refresh_tools()
	ui.hide_title()
	ui.toast(tr("Добро пожаловать в %s!") % tr(n), true)
	ui.open_modal(ui.help_modal)
	ui.start_tutorial()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	for k in _cats.size():
		var r: TextureRect = _cats[k]
		r.position.y = 6.0 + roundf(sin(_t * 3.0 + k * 0.8) * 3.0)
	# город медленно проплывает позади
	var cam: Camera2D = world.cam
	cam.position.x += _drift * 9.0 * delta
	var before: Vector2 = cam.position
	world.clamp_cam()
	if absf(cam.position.x - before.x) > 0.01:
		_drift = -_drift

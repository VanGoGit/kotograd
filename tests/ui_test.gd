extends SceneTree
## Дымовой тест интерфейса без окна:
##   godot --headless --path . -s res://tests/ui_test.gd
## Проходит титульный экран и выбор острова, открывает все вкладки, окна, карточки
## построек и котиков на обоих языках. Ловит ошибки скриптов — интерфейс обращается
## к миру через нетипизированные ссылки, и опечатку видно только при выполнении.

const City = preload("res://tests/city.gd")
const I18n = preload("res://scripts/i18n.gd")
const SimTest = preload("res://tests/sim_test.gd")
const SETTINGS := "user://settings.cfg"

var fails := 0
var errors


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.set_environment("KOTO_TEST", "1")
	OS.set_environment("KOTO_SAVE", "user://ui_test/save.json")
	DirAccess.make_dir_recursive_absolute("user://ui_test")
	for f in DirAccess.get_files_at("user://ui_test"):
		DirAccess.remove_absolute("user://ui_test/" + f)
	# настройки игрока: интерфейс их сохраняет, после теста вернём как было
	var had_settings := FileAccess.file_exists(SETTINGS)
	var settings := FileAccess.get_file_as_string(SETTINGS) if had_settings else ""
	errors = SimTest.ErrorCatcher.new()
	OS.add_logger(errors)

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var w = main.world
	var ui = main.get_node("UI")
	var title = ui.title

	print("— Титульный экран и новый город")
	_check(ui.title_open(), "титульный экран открыт")
	for it in w.ISLANDS:
		_check(title._island_preview(it[0]) != null, "превью острова %s" % it[0])
		title._pick_island(it[0])
	title._pick_island("bay")
	title._on_new()
	title._name_edit.text = "Тестоград"
	title._on_found()
	_check(not ui.title_open() and w.city_name == "Тестоград" and w.mapgen.island == "bay", "город основан на выбранном острове")
	ui.finish_tutorial()

	print("— Город, вкладки и карточки")
	seed(7)
	w.unlimited = true
	City.build(w)
	w.speed = 10
	for k in 600:
		w._process(0.1)
	w.speed = 1  # 10 — только для теста, в интерфейсе такой скорости нет
	await _frames(10)
	for lang in ["ru", "en"]:
		I18n.set_lang(lang)
		for k in w.D.TABS.size():
			ui.set_tab(k)
			for t in ui._visible_tools(k):
				w.select_tool(t)
				ui._tooltip(t)
		w.select_tool("hand")
		var shown := 0
		for i in w.W * w.H:
			var o = w.objs[i]
			if o != null and o.i == i and o.t != "road" and o.t != "path":
				w.info_target = {"tile": i}
				ui._render_info()
				ui._toggle_info_more()
				ui._render_info()
				ui._toggle_info_more()
				shown += 1
		for c in w.cats.slice(0, 20):
			w.info_target = {"cat": c}
			ui._render_info()
			ui._pet_selected()
			w.cats_ai.activity_text(c)
		w.info_target = null
		ui._render_info()
		_check(shown > 50, "карточки построек (%s): %d" % [lang, shown])
		ui._update_hud()
		ui._hint_text()
		ui._update_goal_panel()
		ui.refresh_speed()
		for m in [ui.help_modal, ui.menu_modal, ui.settings_modal]:
			ui.open_modal(m)
			await _frames(2)
			ui.close_modals()
		ui._open_goals()
		await _frames(2)
		ui.close_modals()
		ui.set_zen(true, false)
		ui.set_zen(false, false)
		ui.set_build_hidden(true)
		ui.set_build_hidden(false)
		title.open(true)
		title._on_new()
		title._show_menu()
		ui.hide_title()
		await _frames(30)
	I18n.set_lang("ru")
	_check(errors.count == 0, "ошибок скриптов нет" + ("" if errors.count == 0 else " (%d, первая: %s)" % [errors.count, errors.first]))

	main.free()
	if had_settings:
		var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
		f.store_string(settings)
		f.close()
	else:
		DirAccess.remove_absolute(SETTINGS)
	print("ИТОГ: %s" % ("всё в порядке" if fails == 0 else "ошибок: %d" % fails))
	quit(1 if fails > 0 else 0)


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

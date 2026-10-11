extends SceneTree
## Замер кадра в окне (не headless): тестовый город, ночь и полная карта на экране.
##   godot --path . -s res://tests/bench_draw.gd
## Печатает среднее и 95-й процентиль времени кадра. KOTO_SHOT=файл.png — ещё и снимок экрана
## (KOTO_SHOT_UI=1 — с интерфейсом, KOTO_ZOOM — масштаб).

const City = preload("res://tests/city.gd")
const FRAMES := 600


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.set_environment("KOTO_TEST", "1")
	OS.set_environment("KOTO_SAVE", "user://bench/save.json")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var w = main.world
	seed(12345)
	w.new_game()
	w.unlimited = true
	City.build(w)
	main.get_node("UI").visible = false
	w.speed = 10
	for k in 720:
		w._process(0.1)
	w.speed = 1
	var st: Vector2 = w.mapgen.start_spot()
	w.set_zoom(int(OS.get_environment("KOTO_ZOOM")) if OS.has_environment("KOTO_ZOOM") else 2)
	w.center_cam(st.x, st.y)
	for k in 60:
		await process_frame
	var times := []
	var t := Time.get_ticks_usec()
	for k in FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - t) / 1000.0)
		t = now
	times.sort()
	var sum := 0.0
	for v in times:
		sum += v
	print("кадр: среднее %.2f мс, 95%% — %.2f мс, котиков %d" % [sum / times.size(), times[int(times.size() * 0.95)], w.cats.size()])
	if OS.has_environment("KOTO_SHOT"):
		var ui = main.get_node("UI")
		ui.visible = OS.get_environment("KOTO_SHOT_UI") != ""
		ui.hide_title()
		ui.finish_tutorial()
		for k in 3:
			await process_frame
		root.get_texture().get_image().save_png(OS.get_environment("KOTO_SHOT"))
	main.free()
	quit()

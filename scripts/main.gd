extends Node2D
## Точка входа: собирает мир, камеру, ночь, эффекты, интерфейс и звук.

const Sprites = preload("res://scripts/sprites.gd")
const Sound = preload("res://scripts/sound.gd")
const World = preload("res://scripts/world.gd")
const UI = preload("res://scripts/ui.gd")
const Fx = preload("res://scripts/fx.gd")
const NIGHT_SHADER = preload("res://scripts/night.gdshader")
const MAX_LIGHTS := 128

var world
var sound
var night: ColorRect
var night_mat: ShaderMaterial


func _ready() -> void:
	randomize()
	var spr = Sprites.new()

	sound = Sound.new()
	sound.name = "Sound"
	add_child(sound)

	world = World.new()
	world.name = "World"
	add_child(world)
	var cam := Camera2D.new()
	world.add_child(cam)
	cam.make_current()

	var night_layer := CanvasLayer.new()
	night_layer.layer = 1
	add_child(night_layer)
	night = ColorRect.new()
	night.set_anchors_preset(Control.PRESET_FULL_RECT)
	night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	night_mat = ShaderMaterial.new()
	night_mat.shader = NIGHT_SHADER
	night.material = night_mat
	night_layer.add_child(night)

	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 2
	add_child(fx_layer)
	var fx = Fx.new()
	fx.world = world
	fx_layer.add_child(fx)

	var ui = UI.new()
	ui.name = "UI"
	add_child(ui)

	var loaded: bool = world.setup(spr, sound, ui, cam)
	ui.build(world, spr, sound)
	ui.show_title(loaded)


func _process(_delta: float) -> void:
	var h: float = world.hour()
	sound.hour = h
	# Лос-Анджелес: длинный «золотой час», яркий закат, розовый рассвет, солнце весь день
	var dusk := 0.0
	if h > 16.6 and h < 20.6:
		dusk = 0.3 * pow(sin((h - 16.6) / 4.0 * PI), 1.5)
	var dawn := 0.0
	if h > 5.0 and h < 7.6:
		dawn = 0.2 * sin((h - 5.0) / 2.6 * PI)
	var sun := smoothstep(6.5, 8.5, h) * (1.0 - smoothstep(16.0, 18.0, h))
	night_mat.set_shader_parameter("dark", world.dark)
	night_mat.set_shader_parameter("dusk", dusk)
	night_mat.set_shader_parameter("dawn", dawn)
	night_mat.set_shader_parameter("sun", sun)
	night_mat.set_shader_parameter("size", night.size)
	var ct: Transform2D = get_viewport().get_canvas_transform()
	var sc: float = ct.get_scale().x
	var arr := PackedVector3Array()
	arr.resize(MAX_LIGHTS)
	var n := mini(world.lights.size(), MAX_LIGHTS)
	for i in n:
		var l: Vector3 = world.lights[i]
		var s: Vector2 = ct * Vector2(l.x, l.y)
		arr[i] = Vector3(s.x, s.y, l.z * sc)
	night_mat.set_shader_parameter("lights", arr)
	night_mat.set_shader_parameter("count", n)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and world != null:
		world.save_game()

extends SceneTree
## Проверка английского перевода без окна:
##   godot --headless --path . -s res://tests/tr_test.gd
## Русские строки в коде — ключи перевода. Если строку поменяли, а в lang_en.gd
## её нет, английская версия молча покажет русский текст. Этот тест ловит такие строки
## и строки, где в переводе потерялись %d / %s.

const LangEN = preload("res://scripts/lang_en.gd")
## Файлы, где русские строки — не текст интерфейса.
const SKIP_FILES := ["lang_en.gd", "i18n.gd"]
## Имена котиков переводятся транслитом (i18n.cat), их в таблице нет.
const SKIP_BLOCKS := ["const CAT_NAMES"]

var fails := 0


func _initialize() -> void:
	var str_re := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var ru_re := RegEx.create_from_string("[А-Яа-яЁё]")
	var missing := {}
	for f in DirAccess.get_files_at("res://scripts"):
		if not f.ends_with(".gd") or SKIP_FILES.has(f):
			continue
		var path := "res://scripts/" + f
		var skipping := false
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			if not skipping:
				for b in SKIP_BLOCKS:
					if line.begins_with(b):
						skipping = true
			if skipping:
				if line.rstrip(" \t\r").ends_with("]"):
					skipping = false
				continue
			if line.strip_edges().begins_with("#"):
				continue
			for m in str_re.search_all(line):
				var s := m.get_string(1).c_unescape()
				if ru_re.search(s) != null and not LangEN.EN.has(s) and not missing.has(s):
					missing[s] = "%s:%d" % [f, n]
	for s in missing:
		_fail("нет перевода (%s): %s" % [missing[s], s])

	var ph_re := RegEx.create_from_string("%[-+0-9.]*[dsfxXc]")
	for k in LangEN.EN:
		if _placeholders(ph_re, k) != _placeholders(ph_re, LangEN.EN[k]):
			_fail("разные %%-подстановки: %s → %s" % [k, LangEN.EN[k]])

	print("строк в переводе: %d" % LangEN.EN.size())
	print("ИТОГ: " + ("всё в порядке" if fails == 0 else "ошибок: %d" % fails))
	quit(1 if fails > 0 else 0)


func _placeholders(re: RegEx, s: String) -> Array:
	var out := []
	for m in re.search_all(s.replace("%%", "")):
		out.append(m.get_string().right(1))
	return out


func _fail(msg: String) -> void:
	fails += 1
	print("  FAIL " + msg)

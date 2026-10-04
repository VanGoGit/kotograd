extends RefCounted
## Языки игры. Русские строки в коде — ключи; английский перевод лежит в lang_en.gd.
## Подписи на кнопках и в текстах Godot переводит сам, составные строки — через tr().

const LangEN = preload("res://scripts/lang_en.gd")
const LANGS := [["ru", "Русский"], ["en", "English"]]
const TRANSLIT := {
	"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "zh", "з": "z", "и": "i", "й": "y",
	"к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
	"х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
}

static var _ready := false


static func set_lang(code: String) -> void:
	# русские строки — это ключи, поэтому запасной язык — русский (иначе Godot подставит английский)
	ProjectSettings.set_setting("internationalization/locale/fallback", "ru")
	if not _ready:
		_ready = true
		var t := Translation.new()
		t.locale = "en"
		for k in LangEN.EN:
			t.add_message(k, LangEN.EN[k])
		TranslationServer.add_translation(t)
	TranslationServer.set_locale(code)


static func lang() -> String:
	return "en" if TranslationServer.get_locale().begins_with("en") else "ru"


## Имена котиков: в английской версии — латиницей (Мурка → Murka).
static func cat(name: String) -> String:
	if lang() == "ru":
		return name
	var out := ""
	var cap := true
	for ch in name:
		var low := ch.to_lower()
		if TRANSLIT.has(low):
			var r: String = TRANSLIT[low]
			if ch != low and r != "":
				r = r[0].to_upper() + r.substr(1)
			out += r
		else:
			out += ch
	return out

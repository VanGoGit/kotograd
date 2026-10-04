extends Node
## Генеративный лос-анджелесский пиксельный саундтрек и милые звуки.
## Музыка сочиняется на ходу: аккорды сити-попа, чиптюн-мелодии, лоу-фай ритмы.
## Настроение меняется со временем суток: утро — лёгкий бриз, день — грув,
## закат — синтвейв на побережье, ночь — лоу-фай с треском пластинки.
## Все звуки синтезируются в коде — внешних файлов нет.

const RATE := 22050          # частота коротких звуков интерфейса
const SR := 32000            # частота музыки
const BPM := 92.0
const BARS := 8              # тактов в одной части
const MASTER := 0.62

# Аккорды: [бас (MIDI), качество]. Тональность ре мажор.
const Q := {
	"maj7": [0, 4, 7, 11], "maj9": [4, 7, 11, 14], "m7": [0, 3, 7, 10], "m9": [3, 7, 10, 14],
	"7": [0, 4, 7, 10], "13": [4, 10, 14, 21], "6": [0, 4, 7, 9], "sus": [0, 5, 7, 10],
}
const MOODS := {
	"morning": {
		"progs": [
			[[38, "maj9"], [43, "maj9"], [47, "m7"], [45, "sus"]],
			[[43, "maj7"], [38, "maj7"], [40, "m9"], [45, "sus"]],
		],
		"swing": 0.08, "drums": "light", "bass": "simple", "keys": "pulse", "pad": false,
		"lead": "pulse25", "arp": true, "dense": 0.8, "lp": 9000.0, "crackle": false,
	},
	"day": {
		"progs": [
			[[43, "maj9"], [42, "m7"], [40, "m9"], [45, "13"]],
			[[38, "maj9"], [47, "m9"], [40, "m9"], [45, "7"]],
			[[43, "maj7"], [45, "6"], [42, "m7"], [47, "m7"]],
			[[43, "maj7"], [42, "7"], [47, "m9"], [45, "m7"]],
		],
		"swing": 0.14, "drums": "groove", "bass": "funk", "keys": "comp", "pad": false,
		"lead": "pulse25", "arp": false, "dense": 1.0, "lp": 14000.0, "crackle": false,
	},
	"sunset": {
		"progs": [
			[[47, "m7"], [43, "maj7"], [38, "maj7"], [45, "sus"]],
			[[38, "maj7"], [45, "6"], [47, "m7"], [43, "maj7"]],
			[[43, "maj9"], [45, "6"], [47, "m9"], [47, "m7"]],
		],
		"swing": 0.0, "drums": "synth", "bass": "eighths", "keys": "none", "pad": true,
		"lead": "square", "arp": true, "dense": 0.7, "lp": 7500.0, "crackle": false,
	},
	"night": {
		"progs": [
			[[47, "m9"], [43, "maj9"], [40, "m9"], [42, "m7"]],
			[[40, "m9"], [45, "13"], [38, "maj9"], [47, "m9"]],
		],
		"swing": 0.2, "drums": "lofi", "bass": "slow", "keys": "long", "pad": true,
		"lead": "tri", "arp": false, "dense": 0.55, "lp": 3400.0, "crackle": true,
	},
	# --- отдельные треки ---
	"beach": {
		"progs": [
			[[38, "6"], [43, "6"], [45, "7"], [43, "6"]],
			[[38, "maj7"], [47, "m7"], [43, "maj7"], [45, "7"]],
			[[43, "6"], [45, "7"], [42, "m7"], [47, "m7"]],
		],
		"swing": 0.1, "drums": "light", "bass": "simple", "keys": "pulse", "pad": false, "bpm": 86.0, "tr": 2,
		"lead": "surf", "arp": false, "dense": 0.55, "lp": 9000.0, "crackle": false,
	},
	"boulevard": {
		"progs": [
			[[47, "m9"], [43, "maj7"], [38, "maj7"], [45, "sus"]],
			[[47, "m7"], [40, "m7"], [43, "maj9"], [45, "6"]],
		],
		"swing": 0.12, "drums": "lofi", "bass": "slow", "keys": "long", "pad": true, "bpm": 84.0, "tr": -2,
		"lead": "tri", "arp": true, "dense": 0.5, "lp": 5500.0, "crackle": false,
	},
	"lazy": {
		"progs": [
			[[40, "m9"], [45, "13"], [38, "maj9"], [38, "maj9"]],
			[[43, "maj9"], [42, "m7"], [40, "m9"], [45, "13"]],
		],
		"swing": 0.22, "drums": "lofi", "bass": "slow", "keys": "long", "pad": false, "bpm": 74.0, "tr": 3,
		"lead": "tri", "arp": false, "dense": 0.4, "lp": 3800.0, "crackle": true,
	},
	"dawn": {
		"progs": [
			[[38, "maj9"], [43, "maj9"], [40, "m9"], [43, "6"]],
			[[43, "maj9"], [38, "maj9"], [47, "m9"], [45, "sus"]],
		],
		"swing": 0.0, "drums": "none", "bass": "simple", "keys": "none", "pad": true, "bpm": 72.0, "tr": 5,
		"lead": "bell", "arp": true, "dense": 0.5, "lp": 9000.0, "crackle": false,
	},
}
## Треки для выбора в настройках. auto — музыка меняется вместе со временем суток.
const TRACKS := [
	{"id": "auto", "name": "Авто: по времени суток"},
	{"id": "day", "name": "Котоград — дневной грув"},
	{"id": "beach", "name": "Санта-Мурика Бич"},
	{"id": "boulevard", "name": "Сансет-бульвар"},
	{"id": "lazy", "name": "Ленивое воскресенье"},
	{"id": "dawn", "name": "Мурлибу на рассвете"},
	{"id": "shuffle", "name": "Все треки по кругу"},
]
const SHUFFLE := ["day", "beach", "boulevard", "lazy", "dawn", "morning", "night", "sunset"]
# Ударные: 16 шагов (шестнадцатые), число — громкость
const DRUMS := {
	"groove": {
		"kick": [1, 0, 0, 0, 0, 0, 0, .5, 0, 0, .9, 0, 0, 0, 0, 0],
		"snare": [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, .25],
		"hat": [.55, .2, .5, .2, .55, .2, .5, .25, .55, .2, .5, .2, .55, .2, .5, .3],
	},
	"lofi": {
		"kick": [1, 0, 0, 0, 0, 0, 0, .6, 0, 0, .8, 0, 0, 0, 0, 0],
		"snare": [0, 0, 0, 0, .75, 0, 0, 0, 0, 0, 0, 0, .75, 0, 0, 0],
		"hat": [.4, 0, .3, .15, .4, 0, .3, 0, .4, 0, .3, .15, .4, 0, .3, 0],
	},
	"light": {
		"kick": [.9, 0, 0, 0, 0, 0, 0, 0, 0, 0, .7, 0, 0, 0, 0, 0],
		"rim": [0, 0, 0, 0, .7, 0, 0, 0, 0, 0, 0, 0, .7, 0, 0, 0],
		"shaker": [.35, .2, .3, .2, .35, .2, .3, .2, .35, .2, .3, .2, .35, .2, .3, .2],
	},
	"surf": {
		"kick": [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, .7, 0, 0, 0, 0, 0],
		"snare": [0, 0, 0, 0, .85, 0, 0, 0, 0, 0, 0, 0, .85, 0, 0, .3],
		"hat": [.35, .2, .3, .2, .35, .2, .3, .2, .35, .2, .3, .2, .35, .2, .3, .2],
		"shaker": [0, .25, 0, .25, 0, .25, 0, .25, 0, .25, 0, .25, 0, .25, 0, .25],
	},
	"none": {},
	"synth": {
		"kick": [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, .6, 0, 0, 0, 0, 0],
		"snare": [0, 0, 0, 0, .9, 0, 0, 0, 0, 0, 0, 0, .9, 0, 0, 0],
		"clap": [0, 0, 0, 0, .6, 0, 0, 0, 0, 0, 0, 0, .6, 0, 0, 0],
		"hat": [.2, .15, 0, .15, .2, .15, 0, .15, .2, .15, 0, .15, .2, .15, 0, .15],
		"ohat": [0, 0, .35, 0, 0, 0, .35, 0, 0, 0, .35, 0, 0, 0, .35, 0],
	},
}
const BASS := {
	"funk": [[0, "r", 3], [3, "r", 1], [6, "o", 1], [8, "r", 2], [10, "5", 2], [13, "o", 1], [14, "a", 2]],
	"simple": [[0, "r", 6], [8, "5", 4], [12, "r", 2], [14, "a", 2]],
	"eighths": [[0, "r", 2], [2, "r", 2], [4, "r", 2], [6, "o", 2], [8, "r", 2], [10, "r", 2], [12, "r", 2], [14, "o", 2]],
	"slow": [[0, "r", 10], [10, "5", 4], [14, "a", 2]],
	"walk": [[0, "r", 4], [4, "3", 4], [8, "5", 4], [12, "a", 4]],
}
const KEYS := {
	"comp": [[[0, 5], [6, 2], [10, 5]], [[0, 3], [3, 3], [8, 2], [11, 4]]],
	"pulse": [[[0, 6], [6, 4], [10, 6]], [[0, 4], [4, 4], [8, 4], [12, 4]]],
	"long": [[[0, 14]], [[0, 10], [10, 6]]],
	"stab": [[[2, 1], [6, 1], [10, 1], [14, 1]], [[2, 1], [6, 2], [10, 1], [13, 2]]],
}
const SCALE_PCS := [2, 4, 6, 7, 9, 11, 1]
const FORM := ["A", "A", "B", "break", "A", "lite", "B"]

var music_on := true
var music_vol := 0.8         # громкость: музыка, звуки, окружение (0..1)
var sfx_vol := 0.8
var amb_vol := 0.7
var amb := {"waves": 0.0, "birds": 0.0, "crickets": 0.0, "traffic": 0.0}  # уровни окружения, выставляет мир
var night := false           # выставляет мир; оставлено для совместимости
var hour := 12.0             # игровое время, выставляет main.gd

var _sfx := {}
var _sfx_players: Array = []
var _sp := 0
var _music_bus := 0
var _lp: AudioEffectLowPassFilter
var _lp_cut := 9000.0
var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback

# секвенсор
var _step_len: float = SR * 60.0 / BPM / 4.0
var _t := 0                  # номер следующего сэмпла на выход
var _events: Array = []      # [сэмпл, ключ звука, громкость, панорама]
var _ev_i := 0
var _voices: Array = []      # [буфер, позиция, задержка, гл, гп]
var _sec_sample := 0.0       # сэмпл, с которого начинается следующая часть
var _tr := 0                 # транспонирование текущего трека
var track := "auto"          # выбранный трек (см. TRACKS)
var _shuffle_i := 0
var _sec_n := 0
var _new: Array = []
var _cache := {}
var _warm: Array = []
var _themes := {}
var _prev_kind := "intro"
var _mood := "day"

# Браузер: звук там считается в том же потоке, что и игра, и живой поток
# прерывается при малейшей подтормозке. Поэтому в вебе музыка заранее
# сводится в готовые фрагменты, а браузер играет их в своём аудиопотоке.
const CHUNK := 6 * SR        # длина фрагмента
const OV := 1600             # 50 мс общего хвоста для плавного стыка
const DLY := 3520            # задержка «эха комнаты» (110 мс)
var _web := OS.has_feature("web")
var _chunk := PackedVector2Array()
var _ov_head := PackedVector2Array()
var _chunks: Array = []      # готовые к игре AudioStreamWAV
var _wplayers: Array = []
var _wp := 0
var _due := -1.0             # когда (по часам) должен начаться следующий фрагмент
var _lpa := 1.0
var _lpl := 0.0
var _lpr := 0.0
var _dly_l := PackedFloat32Array()
var _dly_r := PackedFloat32Array()
var _dly_i := 0
var _dml := 0.0
var _dmr := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	# В браузере шины, созданные при запуске, сцепляются в кольцо, и Web Audio глушит весь звук.
	# Поэтому там всё играет через главную шину, а громкость задаётся каждому звуку отдельно.
	if not _web:
		_music_bus = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_music_bus, "Music")
		AudioServer.set_bus_send(_music_bus, "Master")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.5
	rev.damping = 0.55
	rev.spread = 1.0
	rev.dry = 1.0
	rev.wet = 0.13
	rev.hipass = 0.25
	if not _web:
		AudioServer.add_bus_effect(_music_bus, rev)
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = _lp_cut
	_lp.resonance = 0.6
	if not _web:
		AudioServer.add_bus_effect(_music_bus, _lp)
	for bn in ([] if _web else ["Sfx", "Ambient"]):
		var bi := AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(bi, bn)
		AudioServer.set_bus_send(bi, "Master")
	apply_volumes()

	_sfx["pop"] = _wav(_synth_pop())
	_sfx["dig"] = _wav(_synth_dig())
	_sfx["mew"] = _wav(_synth_mew())
	_sfx["chime"] = _wav(_synth_chime())
	_sfx["fanfare"] = _wav(_synth_fanfare())
	_sfx["boom"] = _wav(_synth_boom())
	_sfx["cheer"] = _wav(_synth_cheer())
	_sfx["honk"] = _wav(_synth_honk())
	_sfx["horn"] = _wav(_synth_horn())
	_sfx["ding"] = _wav(_synth_ding())
	_sfx["whoosh"] = _wav(_synth_whoosh())
	_sfx["click"] = _wav(_synth_click())
	_sfx["tab"] = _wav(_synth_tab())
	_sfx["build"] = _wav(_synth_build())
	for k in 3:
		_birds.append(_wav(_synth_bird(k)))
	_build_ambience()
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = _b("Sfx")
		add_child(p)
		_sfx_players.append(p)

	if _web:
		_dly_l.resize(DLY)
		_dly_r.resize(DLY)
		for i in 3:
			var wp := AudioStreamPlayer.new()
			wp.bus = _b("Music")
			wp.volume_db = -3.0 + _lin(music_vol)
			add_child(wp)
			_wplayers.append(wp)
		_gen_section()
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SR
	gen.buffer_length = 0.4
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.bus = "Music"
	_player.volume_db = -3.0
	# в браузере звук по умолчанию идёт через Web Audio «сэмплами», а живой генератор — только потоком
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_player)
	_gen_section()


func _process(delta: float) -> void:
	_update_ambience(delta)
	_warm_up(3000)
	var target: float = MOODS[_mood].lp
	_lp_cut = lerpf(_lp_cut, target, 0.01)
	_lp.cutoff_hz = _lp_cut
	if _web:
		_process_web()
		return
	if not music_on:
		if _player.playing:
			_player.stop()
			_pb = null
		return
	# ждём, пока подготовятся звуки первой части, чтобы не было рывка
	if not _player.playing:
		if _warm.size() > 0:
			return
		_player.play()
		_pb = _player.get_stream_playback()
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n > 0:
		_pb.push_buffer(render(n))


func _process_web() -> void:
	if not music_on:
		for p in _wplayers:
			p.stop()
		_due = -1.0
		return
	_lpa = 1.0 - exp(-TAU * _lp_cut / SR)
	_render_chunks(4000)
	var now := Time.get_ticks_usec() / 1000000.0
	if _chunks.is_empty() or (_due >= 0.0 and now < _due):
		return
	# опоздали сильнее хвоста (вкладка была скрыта) — начинаем заново с этого момента
	if _due < 0.0 or now - _due > float(OV) / SR:
		_due = now
	var p: AudioStreamPlayer = _wplayers[_wp]
	_wp = (_wp + 1) % _wplayers.size()
	p.stream = _chunks.pop_front()
	# пропускаем ровно столько, на сколько опоздал кадр, — стык остаётся точным
	p.play(now - _due)
	_due += float(CHUNK) / SR


## Сводит музыку фрагментами в фоне, понемногу за кадр.
func _render_chunks(budget_usec: int) -> void:
	var t0 := Time.get_ticks_usec()
	while _chunks.size() < 2 and Time.get_ticks_usec() - t0 < budget_usec:
		if _chunk.is_empty():
			_chunk = _ov_head.duplicate()
		var n := mini(2048, CHUNK + OV - _chunk.size())
		_chunk.append_array(render(n))
		if _chunk.size() < CHUNK + OV:
			continue
		# хвост этого фрагмента — начало следующего; на стыке они плавно перетекают
		_ov_head = _chunk.slice(CHUNK)
		for k in OV:
			var a := float(k) / OV
			_chunk[k] *= a
			_chunk[CHUNK + k] *= 1.0 - a
		_chunks.append(_to_wav(_chunk))
		_chunk = PackedVector2Array()


func _to_wav(buf: PackedVector2Array) -> AudioStreamWAV:
	var ints := PackedInt32Array()
	ints.resize(buf.size())
	for k in buf.size():
		var v := buf[k]
		ints[k] = (int(v.x * 32000.0) & 0xFFFF) | (int(v.y * 32000.0) << 16)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = true
	w.data = ints.to_byte_array()
	return w


# ---------- микшер ----------

## Сводит n кадров стерео. Используется и в игре, и в тестах.
func render(n: int) -> PackedVector2Array:
	_schedule(n)
	var L := PackedFloat32Array()
	L.resize(n)
	var R := PackedFloat32Array()
	R.resize(n)
	var keep: Array = []
	for v in _voices:
		var b: PackedFloat32Array = v[0]
		var pos: int = v[1]
		var d: int = v[2]
		var gl: float = v[3]
		var gr: float = v[4]
		var cnt := mini(n - d, b.size() - pos)
		for k in cnt:
			var s := b[pos + k]
			L[d + k] += s * gl
			R[d + k] += s * gr
		pos += cnt
		if pos < b.size():
			v[1] = pos
			v[2] = 0
			keep.append(v)
	_voices = keep
	var out := PackedVector2Array()
	out.resize(n)
	if not _web:
		for k in n:
			out[k] = Vector2(tanh(L[k] * MASTER), tanh(R[k] * MASTER))
	else:
		# в браузере эффекты шины не действуют на готовые фрагменты — эхо и фильтр прямо здесь
		var lpa := _lpa
		var lpl := _lpl
		var lpr := _lpr
		var dml := _dml
		var dmr := _dmr
		var di := _dly_i
		for k in n:
			dml += (_dly_l[di] - dml) * 0.4
			dmr += (_dly_r[di] - dmr) * 0.4
			var l := L[k] + dml * 0.16
			var r := R[k] + dmr * 0.16
			_dly_l[di] = L[k] + dmr * 0.32
			_dly_r[di] = R[k] + dml * 0.32
			di += 1
			if di == DLY:
				di = 0
			lpl += (l - lpl) * lpa
			lpr += (r - lpr) * lpa
			out[k] = Vector2(tanh(lpl * MASTER), tanh(lpr * MASTER))
		_lpl = lpl
		_lpr = lpr
		_dml = dml
		_dmr = dmr
		_dly_i = di
	_t += n
	return out


func _schedule(n: int) -> void:
	var end := _t + n
	# всегда держим сочинённой минимум одну часть вперёд
	while _sec_sample < float(end) + _step_len * 16.0 * BARS:
		_gen_section()
	while _ev_i < _events.size():
		var e: Array = _events[_ev_i]
		if e[0] >= end:
			break
		_ev_i += 1
		var buf := _sample(e[1])
		var pan: float = e[3]
		var vel: float = e[2]
		_voices.append([buf, 0, maxi(0, e[0] - _t), vel * minf(1.0, 1.0 - pan), vel * minf(1.0, 1.0 + pan)])


func _sample(key: String) -> PackedFloat32Array:
	if not _cache.has(key):
		_cache[key] = _synth(key)
	return _cache[key]


func _warm_up(budget_usec: int) -> void:
	var t0 := Time.get_ticks_usec()
	while _warm.size() > 0 and Time.get_ticks_usec() - t0 < budget_usec:
		_sample(_warm.pop_back())


# ---------- композитор ----------

func _mood_for(h: float) -> String:
	if h >= 5.5 and h < 11.0:
		return "morning"
	if h >= 11.0 and h < 17.0:
		return "day"
	if h >= 17.0 and h < 21.0:
		return "sunset"
	return "night"


func _ev(step: float, inst: String, midi: int, dur: int, vel: float, pan: float) -> void:
	# длительность — в миллисекундах: у треков разный темп
	var key := "%s|%d|%d" % [inst, midi, int(dur * _step_len / SR * 1000.0)]
	if not _cache.has(key) and not _warm.has(key):
		_warm.append(key)
	var at := int(round(_sec_sample + step * _step_len))
	_new.append([at, key, vel * randf_range(0.9, 1.05), pan])


func _pick_mood() -> String:
	match track:
		"auto":
			return _mood_for(hour)
		"shuffle":
			# каждые три части — следующий трек
			var m: String = SHUFFLE[(_shuffle_i / 3) % SHUFFLE.size()]
			_shuffle_i += 1
			return m
	return track if MOODS.has(track) else _mood_for(hour)


func _gen_section() -> void:
	var mood: String = _pick_mood()
	var M: Dictionary = MOODS[mood]
	_step_len = SR * 60.0 / float(M.get("bpm", BPM)) / 4.0
	_tr = int(M.get("tr", 0))
	var kind: String = "intro" if _sec_n == 0 else FORM[(_sec_n - 1) % FORM.size()]
	_sec_n += 1
	# темы повторяются — так мелодии запоминаются
	var tk := mood + ("B" if kind == "B" else "A")
	var theme: Dictionary = _themes.get(tk, {})
	if theme.is_empty() or (kind == "B" and randf() < 0.5):
		var pr: Array = []
		for ch in M.progs.pick_random():
			var r: int = (ch[0] as int) + _tr
			if r > 49:
				r -= 12
			pr.append([r, ch[1]])
		theme = {"prog": pr, "mel": _gen_melody(pr, M.dense)}
		_themes[tk] = theme
	var prog: Array = theme.prog
	var swing: float = M.swing
	var lead_on: bool = kind == "A" or kind == "B" or kind == "break"
	var drums_on: bool = kind != "break"
	var arp_on: bool = M.arp or kind == "lite"
	_new = []
	var kpat: Array = KEYS[M.keys].pick_random() if M["keys"] != "none" else []
	for bar in BARS:
		var ch: Array = prog[bar % 4]
		var nxt: Array = prog[(bar + 1) % 4]
		var b0 := bar * 16
		var voicing := _voicing(ch)
		# ударные
		if drums_on and not (kind == "intro" and bar < 4):
			var pat: Dictionary = DRUMS[M.drums]
			var fill: bool = bar == BARS - 1 and kind != "intro"
			for inst in pat:
				var row: Array = pat[inst]
				if kind == "intro" and (inst == "kick" or inst == "snare" or inst == "clap"):
					continue
				for s in 16:
					var v: float = row[s]
					if fill and inst == "snare" and s >= 12:
						v = [0.5, 0.45, 0.65, 0.85][s - 12]
					if fill and inst == "kick" and s > 8:
						v = 0.0
					if v <= 0.0:
						continue
					var pan := 0.0
					if inst == "hat" or inst == "ohat":
						pan = 0.3
					elif inst == "shaker":
						pan = -0.35
					_ev(b0 + s + (swing if s % 2 == 1 else 0.0), inst, 0, 0, v, pan)
			if bar == 0 and (_prev_kind == "break" or _prev_kind == "intro") and mood != "night":
				_ev(b0, "crash", 0, 0, 0.6, -0.2)
		elif kind == "break":
			for s in range(0, 16, 4):
				_ev(b0 + s + 2, "hat", 0, 0, 0.25, 0.3)
		# бас
		if not (kind == "intro" and bar < 4):
			var root: int = ch[0]
			for nb in BASS[M.bass]:
				if kind == "break" and nb[0] != 0:
					continue
				var m := root
				match nb[1]:
					"o": m = root + 12
					"5": m = root + 7
					"a": m = (nxt[0] as int) - 1 if randf() < 0.6 else (nxt[0] as int) + 2
					"3": m = root + (3 if Q[ch[1]].has(3) else 4)
				var dur: int = nb[2] if kind != "break" else 14
				_ev(b0 + nb[0] + (swing if int(nb[0]) % 2 == 1 else 0.0), "bass", m, dur, 0.9, 0.0)
		# клавиши (электропиано)
		for kh in kpat:
			var vel := 0.5 if kind != "break" else 0.4
			for j in voicing.size():
				_ev(b0 + kh[0] + j * 0.06 + (swing if int(kh[0]) % 2 == 1 else 0.0), "keys", voicing[j], kh[1], vel, -0.35 + 0.7 * j / maxf(1.0, voicing.size() - 1))
		# пэд
		if M.pad or kind == "break" or kind == "intro":
			for j in voicing.size():
				_ev(b0, "pad", voicing[j], 16, 0.55 if mood == "sunset" or mood == "boulevard" or mood == "dawn" else 0.38, -0.5 if j % 2 == 0 else 0.5)
		# арпеджио
		if arp_on and kind != "intro":
			var tones: Array = []
			for m in voicing:
				tones.append(m + 12)
			var order := [0, 1, 2, 3, 2, 1, 0, 1] if tones.size() >= 4 else [0, 1, 2, 1]
			var stride := 1 if mood == "sunset" or M.get("arp16", false) else 2
			var av := 0.28 if lead_on else 0.45
			for s in range(0, 16, stride):
				var m: int = tones[order[(s / stride) % order.size()] % tones.size()]
				_ev(b0 + s, "bellarp" if M.lead == "bell" else "arp", m, 1, av * (1.2 if s % 4 == 0 else 1.0), -0.25)
				if s % 4 == 0:
					_ev(b0 + s + 3, "arp", m, 1, av * 0.35, 0.4)
		# треск пластинки
		if M.crackle:
			_ev(b0, "crackle", 0, 16, 0.8, 0.0)
	# мелодия с пинг-понг эхом
	if lead_on:
		var lvel := 0.8 if kind != "break" else 0.6
		for nt in theme.mel:
			var st: float = nt[0] + (swing if int(nt[0]) % 2 == 1 else 0.0)
			_ev(st, M.lead, nt[2], nt[1], lvel, 0.1)
			_ev(st + 3, M.lead, nt[2], nt[1], lvel * 0.3, -0.6)
			_ev(st + 6, M.lead, nt[2], nt[1], lvel * 0.13, 0.6)
	_prev_kind = kind
	_mood = mood
	_events = _events.slice(_ev_i)
	_ev_i = 0
	_events.append_array(_new)
	_events.sort_custom(_ev_less)
	_sec_sample += BARS * 16 * _step_len


func _ev_less(a: Array, b: Array) -> bool:
	return a[0] < b[0]


func _chord_pcs(ch: Array) -> Array:
	var pcs: Array = [(ch[0] as int) % 12]
	for iv in Q[ch[1]]:
		pcs.append(((ch[0] as int) + iv) % 12)
	return pcs


func _voicing(ch: Array) -> Array:
	var out: Array = []
	for iv in Q[ch[1]]:
		var m: int = (ch[0] as int) + iv + 12
		while m < 55:
			m += 12
		while m > 69:
			m -= 12
		if not out.has(m):
			out.append(m)
	out.sort()
	return out


## Мелодия на 8 тактов в форме A A' A B: мотив, ответ, мотив, финал.
func _gen_melody(prog: Array, dense: float) -> Array:
	var rh := _gen_rhythm(dense)
	var out: Array = []
	var p := 74
	var motif: Array = []
	for half in 4:
		var base := half * 32
		if half == 2:
			for nt in motif:
				out.append([nt[0] + 64, nt[1], nt[2]])
			continue
		var rr: Array = rh if half != 3 or randf() < 0.5 else _gen_rhythm(dense)
		for idx in rr.size():
			var s: int = rr[idx][0]
			var dur: int = rr[idx][1]
			var bar := (base + s) / 16
			var ch: Array = prog[bar % 4]
			var pcs := _chord_pcs(ch)
			var last := idx == rr.size() - 1
			if last and (half == 1 or half == 3):
				# фраза заканчивается на опорном звуке аккорда
				p = _nearest(p, [pcs[0], pcs[2]] if half == 3 else pcs)
				dur = maxi(dur, 4)
			elif s % 4 == 0 or dur >= 4:
				p = _nearest(p + randi_range(-3, 3), pcs)
			else:
				p = _scale_step(p, [-2, -1, -1, 1, 1, 2].pick_random())
			p = clampi(p, 66, 86)
			out.append([base + s, dur, p])
			if half == 0:
				motif.append([base + s, dur, p])
	return out


func _gen_rhythm(dense: float) -> Array:
	var on: Array = []
	for s in 27:
		var pr: float
		if s % 8 == 0:
			pr = 0.75
		elif s % 4 == 0:
			pr = 0.5
		elif s % 2 == 0:
			pr = 0.32
		else:
			pr = 0.1
		if randf() < pr * dense:
			on.append(s)
	if on.size() < 3:
		on = [0, 6, 12, 16]
	var out: Array = []
	for i in on.size():
		var nx: int = on[i + 1] if i + 1 < on.size() else 28
		var dur := mini(nx - (on[i] as int), 6)
		if dur > 1 and randf() < 0.25:
			dur -= 1
		out.append([on[i], dur])
	return out


func _nearest(target: int, pcs: Array) -> int:
	var best := target
	var bd := 99
	for m in range(62, 90):
		if pcs.has(m % 12) and absi(m - target) < bd:
			bd = absi(m - target)
			best = m
	return best


func _scale_step(m: int, d: int) -> int:
	var x := m
	var moved := 0
	while moved < absi(d):
		x += signi(d)
		if SCALE_PCS.has(posmod(x - _tr, 12)):
			moved += 1
	return x


# ---------- инструменты ----------

static func _mtof(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


func _synth(key: String) -> PackedFloat32Array:
	var parts := key.split("|")
	var inst := parts[0]
	var m := int(parts[1])
	var dur := float(int(parts[2])) / 1000.0
	match inst:
		"kick": return _s_kick()
		"snare": return _s_snare()
		"clap": return _s_clap()
		"rim": return _s_rim()
		"hat": return _s_noise(0.07, 90.0, 0.0, 0.32)
		"ohat": return _s_noise(0.35, 10.0, 0.0, 0.2)
		"shaker": return _s_noise(0.1, 40.0, 0.02, 0.22)
		"crash": return _s_noise(1.6, 2.6, 0.0, 0.18)
		"crackle": return _s_crackle(dur)
		"bass": return _s_bass(m, dur)
		"keys": return _s_keys(m, dur)
		"pad": return _s_pad(m, dur)
		"arp": return _s_lead(m, 0.12, 0.125, true)
		"pulse25": return _s_lead(m, dur, 0.25, false)
		"square": return _s_lead(m, dur, 0.5, false)
		"tri": return _s_lead(m, dur, -1.0, false)
		"bell": return _s_bell(m, dur, 0.22)
		"bellarp": return _s_bell(m, 0.6, 0.12)
		"surf": return _s_surf(m, dur)
	return PackedFloat32Array()


## Музыкальная шкатулка: чистый тон и звонкий обертон.
func _s_bell(m: int, dur: float, vol: float) -> PackedFloat32Array:
	var out := _buf(maxf(dur, 0.5) + 0.6)
	var f := _mtof(m)
	for i in out.size():
		var t := float(i) / SR
		var env := minf(1.0, t / 0.002) * exp(-t * 2.6)
		out[i] = (sin(TAU * f * t) + sin(TAU * f * 2.76 * t) * 0.35 * exp(-t * 6.0) + sin(TAU * f * 5.4 * t) * 0.1 * exp(-t * 12.0)) * env * vol
	return out


## Сёрф-гитара в пиксельном стиле: квадрат с быстрым тремоло и «пружинным» затуханием.
func _s_surf(m: int, dur: float) -> PackedFloat32Array:
	var out := _buf(dur + 0.08)
	var f := _mtof(m)
	var ph := 0.0
	var lp := 0.0
	for i in out.size():
		var t := float(i) / SR
		ph += f * (1.0 + 0.012 * sin(TAU * 6.5 * t) * minf(1.0, t * 3.0)) / SR
		var x := 1.0 if fposmod(ph, 1.0) < 0.4 else -1.0
		lp += (x - lp) * 0.3
		var trem := 0.85 + 0.15 * sin(TAU * 7.0 * t)
		var env := minf(1.0, t / 0.003) * (0.55 + 0.45 * exp(-t * 7.0)) * trem
		if t > dur:
			env *= maxf(0.0, 1.0 - (t - dur) / 0.08)
		out[i] = lp * env * 0.11
	return out


func _buf(sec: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * SR))
	return a


func _s_kick() -> PackedFloat32Array:
	var out := _buf(0.32)
	var ph := 0.0
	for i in out.size():
		var t := float(i) / SR
		ph += (48.0 + 110.0 * exp(-t * 30.0)) / SR
		var click := (randf() * 2.0 - 1.0) * 0.25 * maxf(0.0, 1.0 - i / 50.0)
		out[i] = sin(TAU * ph) * exp(-t * 7.5) * 0.95 + click
	return out


func _s_snare() -> PackedFloat32Array:
	var out := _buf(0.28)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / SR
		lp += (randf() * 2.0 - 1.0 - lp) * 0.45
		out[i] = sin(TAU * 190.0 * t) * exp(-t * 25.0) * 0.45 + lp * exp(-t * 15.0) * 0.6
	return out


func _s_clap() -> PackedFloat32Array:
	var out := _buf(0.3)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / SR
		var x := randf() * 2.0 - 1.0
		lp += (x - lp) * 0.3
		var bp := x - lp
		var env := exp(-t * 18.0) * 0.6
		for b in [0.0, 0.011, 0.022]:
			if t >= b:
				env += exp(-(t - b) * 180.0) * 0.5
		out[i] = bp * env * 0.5
	return out


func _s_rim() -> PackedFloat32Array:
	var out := _buf(0.06)
	for i in out.size():
		var t := float(i) / SR
		out[i] = (sin(TAU * 1700.0 * t) * 0.5 + sin(TAU * 820.0 * t) * 0.4) * exp(-t * 85.0) * 0.6
	return out


## Шумовые: хэт, открытый хэт, шейкер, тарелка
func _s_noise(sec: float, decay: float, attack: float, vol: float) -> PackedFloat32Array:
	var out := _buf(sec)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / SR
		var x := randf() * 2.0 - 1.0
		lp += (x - lp) * 0.5
		var env := exp(-t * decay)
		if attack > 0.0:
			env *= minf(1.0, t / attack)
		out[i] = (x - lp) * env * vol
	return out


func _s_crackle(sec: float) -> PackedFloat32Array:
	var out := _buf(sec)
	var lp := 0.0
	var pop := 0.0
	for i in out.size():
		lp += (randf() * 2.0 - 1.0 - lp) * 0.08
		if randf() < 0.0006:
			pop = randf_range(0.08, 0.3) * (1.0 if randf() < 0.5 else -1.0)
		out[i] = lp * 0.035 + pop
		pop *= 0.75
	return out


## Пиксельный бас: ступенчатый треугольник как у NES + мягкий саб
func _s_bass(m: int, dur: float) -> PackedFloat32Array:
	var out := _buf(dur + 0.06)
	var f := _mtof(m)
	var ph := 0.0
	for i in out.size():
		var t := float(i) / SR
		ph += f / SR
		var tri := 1.0 - 4.0 * absf(fposmod(ph, 1.0) - 0.5)
		var q := roundf(tri * 7.5) / 7.5
		var env := minf(1.0, t / 0.004) * (0.75 + 0.25 * exp(-t * 8.0))
		if t > dur:
			env *= maxf(0.0, 1.0 - (t - dur) / 0.06)
		out[i] = (q * 0.5 + sin(TAU * ph) * 0.6) * env * 0.5
	return out


## Электропиано (как Rhodes): FM-синтез с затухающим колокольчиком
func _s_keys(m: int, dur: float) -> PackedFloat32Array:
	var out := _buf(dur + 0.15)
	var f := _mtof(m)
	for i in out.size():
		var t := float(i) / SR
		var idx := 1.3 * exp(-t * 5.0) + 0.15
		var a := sin(TAU * f * t + idx * sin(TAU * f * t))
		var b := sin(TAU * f * 1.003 * t + idx * sin(TAU * f * 1.003 * t))
		var bell := sin(TAU * f * 4.0 * t) * exp(-t * 9.0) * 0.12
		var env := minf(1.0, t / 0.003) * exp(-t * 1.1)
		if t > dur:
			env *= maxf(0.0, 1.0 - (t - dur) / 0.15)
		out[i] = ((a + b) * 0.5 + bell) * env * 0.3
	return out


## Тёплый синтвейв-пэд: две расстроенные пилы через мягкий фильтр
func _s_pad(m: int, dur: float) -> PackedFloat32Array:
	var out := _buf(dur + 0.5)
	var f := _mtof(m)
	var p1 := 0.0
	var p2 := 0.0
	var l1 := 0.0
	var l2 := 0.0
	for i in out.size():
		var t := float(i) / SR
		p1 += f * 1.004 / SR
		p2 += f * 0.996 / SR
		var x := (fposmod(p1, 1.0) + fposmod(p2, 1.0)) - 1.0
		l1 += (x - l1) * 0.12
		l2 += (l1 - l2) * 0.12
		var env := minf(1.0, t / 0.35)
		if t > dur:
			env *= maxf(0.0, 1.0 - (t - dur) / 0.5)
		out[i] = l2 * env * 0.3
	return out


## Чиптюн-лид: импульсная волна (duty) или треугольник, с вибрато
func _s_lead(m: int, dur: float, duty: float, blip: bool) -> PackedFloat32Array:
	var out := _buf(dur + 0.05)
	var f := _mtof(m)
	var ph := 0.0
	var lp := 0.0
	for i in out.size():
		var t := float(i) / SR
		var vib := 1.0 + 0.01 * sin(TAU * 5.5 * t) * clampf((t - 0.18) / 0.2, 0.0, 1.0)
		ph += f * vib / SR
		var x: float
		if duty < 0.0:
			var tri := 1.0 - 4.0 * absf(fposmod(ph, 1.0) - 0.5)
			x = roundf(tri * 7.5) / 7.5 * 1.6
		else:
			x = (1.0 if fposmod(ph, 1.0) < duty else -1.0) - (2.0 * duty - 1.0)
		lp += (x - lp) * 0.35
		var env: float
		if blip:
			env = minf(1.0, t / 0.002) * exp(-t * 18.0)
		else:
			env = minf(1.0, t / 0.005) * (0.8 + 0.2 * exp(-t * 10.0))
			if t > dur:
				env *= maxf(0.0, 1.0 - (t - dur) / 0.05)
		out[i] = lp * env * 0.16
	return out


# ---------- звуки интерфейса ----------

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _synth_pop() -> PackedFloat32Array:
	var n := int(0.15 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 420.0 * pow(900.0 / 420.0, minf(1.0, t / 0.08))
		ph += f / RATE
		out[i] = sin(TAU * ph) * exp(-t * 30.0) * 0.7
	return out


## Мягкий деревянный щелчок кнопки.
func _synth_click() -> PackedFloat32Array:
	var n := int(0.06 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 1180.0 * t) * 0.6 + sin(TAU * 590.0 * t) * 0.4) * exp(-t * 85.0) * 0.45
	return out


## Короткое «плип» при смене вкладки: тон чуть поднимается.
func _synth_tab() -> PackedFloat32Array:
	var n := int(0.14 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 620.0 + 380.0 * minf(1.0, t / 0.05)
		ph += f / RATE
		out[i] = sin(TAU * ph) * exp(-t * 32.0) * 0.4
	return out


## Тёплое арпеджио, когда ставим большое здание.
func _synth_build() -> PackedFloat32Array:
	var n := int(0.9 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes := [[523.25, 0.0], [659.25, 0.07], [783.99, 0.14], [1046.5, 0.21]]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for nt in notes:
			var tt: float = t - nt[1]
			if tt > 0.0:
				v += (sin(TAU * nt[0] * tt) + 0.3 * sin(TAU * nt[0] * 2.0 * tt)) * exp(-tt * 5.5)
		out[i] = v * 0.16
	return out


func _synth_dig() -> PackedFloat32Array:
	var n := int(0.18 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var noise := randf() * 2.0 - 1.0
		prev = prev + (noise - prev) * 0.18
		out[i] = prev * (1.0 - float(i) / n) * 1.6
	return out


func _synth_mew() -> PackedFloat32Array:
	var n := int(0.42 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f: float
		if t < 0.1:
			f = lerpf(620.0, 1050.0, t / 0.1)
		else:
			f = lerpf(1050.0, 700.0, minf(1.0, (t - 0.1) / 0.28))
		f *= 1.0 + sin(t * 40.0) * 0.01
		ph += f / RATE
		var env: float
		if t < 0.04:
			env = t / 0.04
		elif t < 0.2:
			env = lerpf(1.0, 0.75, (t - 0.04) / 0.16)
		else:
			env = maxf(0.0, lerpf(0.75, 0.0, (t - 0.2) / 0.2))
		var s := 0.0
		for k in range(1, 6):
			# форманта около 1500 Гц делает звук похожим на «мяу»
			var hf := f * k
			var w := exp(-pow((hf - 1500.0) / 900.0, 2.0)) + 0.15
			s += sin(TAU * ph * k) * w / k
		out[i] = s * env * 0.5
	return out


func _synth_chime() -> PackedFloat32Array:
	var n := int(1.3 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for nt in [[880.0, 0.0, 0.5], [1320.0, 0.1, 0.45], [1760.0, 0.2, 0.3]]:
			var tt: float = t - nt[1]
			if tt > 0.0:
				s += sin(TAU * nt[0] * tt) * exp(-tt * 4.0) * nt[2]
		out[i] = s * 0.6
	return out


func play(name: String, pitch := 1.0, db := -4.0) -> void:
	if not _sfx.has(name):
		return
	var p: AudioStreamPlayer = _sfx_players[_sp]
	_sp = (_sp + 1) % _sfx_players.size()
	p.stream = _sfx[name]
	p.pitch_scale = pitch
	p.volume_db = db + (_lin(sfx_vol) if _web else 0.0)
	p.play()


func set_music(on: bool) -> void:
	music_on = on
	apply_volumes()
	_save_audio()


## kind: "music", "sfx" или "amb"; v от 0 до 1
func set_volume(kind: String, v: float) -> void:
	match kind:
		"music": music_vol = v
		"sfx": sfx_vol = v
		"amb": amb_vol = v
	apply_volumes()
	_save_audio()


func set_track(id: String) -> void:
	if id == track:
		return
	track = id
	_save_audio()
	# новая музыка — со следующего такта: отбрасываем сочинённое наперёд
	_events = _events.slice(0, _ev_i)
	_ev_i = _events.size()
	_sec_sample = float(_t) + SR * 0.3
	_sec_n = 0
	_gen_section()


func track_name() -> String:
	for tk in TRACKS:
		if tk.id == track:
			return tk.name
	return ""


## Шина для звука: в браузере — всегда главная.
func _b(bus_name: String) -> String:
	return "Master" if _web else bus_name


func _lin(v: float) -> float:
	return linear_to_db(maxf(v, 0.0001))


func apply_volumes() -> void:
	if _web:
		for wp in _wplayers:
			wp.volume_db = -3.0 + _lin(music_vol)
		return
	var mv := music_vol if music_on else 0.0
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(mv, 0.0001)))
	AudioServer.set_bus_mute(_music_bus, mv <= 0.001)
	var sb := AudioServer.get_bus_index("Sfx")
	var ab := AudioServer.get_bus_index("Ambient")
	if sb >= 0:
		AudioServer.set_bus_volume_db(sb, linear_to_db(maxf(sfx_vol, 0.0001)))
		AudioServer.set_bus_mute(sb, sfx_vol <= 0.001)
	if ab >= 0:
		AudioServer.set_bus_volume_db(ab, linear_to_db(maxf(amb_vol, 0.0001)))
		AudioServer.set_bus_mute(ab, amb_vol <= 0.001)


func _save_audio() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("audio", "music", music_on)
	cfg.set_value("audio", "music_vol", music_vol)
	cfg.set_value("audio", "sfx_vol", sfx_vol)
	cfg.set_value("audio", "amb_vol", amb_vol)
	cfg.set_value("audio", "track", track)
	cfg.save("user://settings.cfg")


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		music_on = cfg.get_value("audio", "music", true)
		music_vol = float(cfg.get_value("audio", "music_vol", 0.8))
		sfx_vol = float(cfg.get_value("audio", "sfx_vol", 0.8))
		amb_vol = float(cfg.get_value("audio", "amb_vol", 0.7))
		track = str(cfg.get_value("audio", "track", "auto"))


# ---------- звуки окружения ----------
# Волны, птицы, сверчки и гул города. Громкость каждого зависит от того,
# что сейчас видно на экране, — её выставляет мир через словарь amb.

var _amb_players := {}
var _birds: Array = []
var _bird_t := 0.0
var _bird_player: AudioStreamPlayer
const AMB_BASE := {"waves": -9.0, "crickets": -16.0, "traffic": -14.0}


func _build_ambience() -> void:
	var loops := {"waves": _loop(_synth_waves(12.0), 0.6), "crickets": _wav(_synth_crickets(4.0)), "traffic": _loop(_synth_traffic(3.0), 0.4)}
	for k in loops:
		var w: AudioStreamWAV = loops[k]
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2
		var p := AudioStreamPlayer.new()
		p.bus = _b("Ambient")
		p.stream = w
		p.volume_db = -80.0
		add_child(p)
		_amb_players[k] = p
	_bird_player = AudioStreamPlayer.new()
	_bird_player.bus = _b("Ambient")
	add_child(_bird_player)


func _update_ambience(dt: float) -> void:
	for k in _amb_players:
		var p: AudioStreamPlayer = _amb_players[k]
		var lv: float = amb.get(k, 0.0)
		var target: float = AMB_BASE[k] + linear_to_db(maxf(lv, 0.001)) + (_lin(amb_vol) if _web else 0.0)
		var cur := p.volume_db
		p.volume_db = move_toward(cur, target, dt * 12.0)
		if lv > 0.01 and not p.playing:
			p.volume_db = -60.0
			p.play()
		elif lv <= 0.01 and p.volume_db < -50.0 and p.playing:
			p.stop()
	# птички щебечут сами по себе, чаще — где много зелени
	_bird_t -= dt
	if _bird_t <= 0.0:
		_bird_t = randf_range(1.5, 5.0)
		if randf() < amb.birds:
			_bird_player.stream = _birds.pick_random()
			_bird_player.pitch_scale = randf_range(0.9, 1.15)
			_bird_player.volume_db = -15.0 + (_lin(amb_vol) if _web else 0.0)
			_bird_player.play()


## Плавная склейка конца с началом, чтобы шумовая петля не щёлкала.
func _loop(samples: PackedFloat32Array, fade_sec: float) -> AudioStreamWAV:
	var f := int(fade_sec * RATE)
	var n := samples.size() - f
	var out := samples.slice(0, n)
	for k in f:
		var a := float(k) / f
		out[k] = out[k] * a + samples[n + k] * (1.0 - a)
	return _wav(out)


func _synth_waves(sec: float) -> PackedFloat32Array:
	var n := int((sec + 0.6) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := randf() * 2.0 - 1.0
		l1 += (x - l1) * 0.04
		l2 += (l1 - l2) * 0.04
		hp += (x - hp) * 0.3
		# накат волны каждые 6 секунд: нарастает, разбивается пеной и отступает
		var ph := fposmod(t / 6.0, 1.0)
		var swell := pow(sin(ph * PI), 2.0)
		var foam := exp(-pow((ph - 0.55) * 7.0, 2.0))
		out[i] = l2 * (2.2 + 4.0 * swell) + (x - hp) * 0.12 * foam
	return out


func _synth_crickets(sec: float) -> PackedFloat32Array:
	var n := int(sec * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# два сверчка с разным тоном и ритмом; сетка выбрана так, чтобы петля сходилась
	for cr in [[4300.0, 0.5, 0.0, 0.22], [3800.0, 0.8, 0.27, 0.15]]:
		var period: float = cr[1]
		var start: float = cr[2]
		while start < sec:
			for pulse in 3:
				var t0: float = start + pulse * 0.035
				for k in int(0.022 * RATE):
					var t := float(k) / RATE
					var idx := int((t0 + t) * RATE) % n
					out[idx] += sin(TAU * cr[0] * t) * sin(PI * t / 0.022) * cr[3]
			start += period
	return out


func _synth_traffic(sec: float) -> PackedFloat32Array:
	var n := int((sec + 0.4) * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := randf() * 2.0 - 1.0
		l1 += (x - l1) * 0.02
		l2 += (l1 - l2) * 0.05
		out[i] = l2 * 5.0 + sin(TAU * 62.0 * t) * 0.05 * (0.6 + 0.4 * sin(TAU * 0.5 * t))
	return out


func _synth_bird(kind: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(0.6 * RATE))
	var notes: Array = [[[2600.0, 3900.0], [3000.0, 4200.0]], [[4200.0, 3200.0], [4200.0, 3200.0], [4400.0, 3000.0]], [[3200.0, 3600.0], [2800.0, 4600.0]]][kind]
	var pos := 0
	for nt in notes:
		var len := int(0.07 * RATE)
		var ph := 0.0
		for k in len:
			var a := float(k) / len
			ph += lerpf(nt[0], nt[1], a) / RATE
			if pos + k < out.size():
				out[pos + k] += sin(TAU * ph) * sin(PI * a) * 0.35
		pos += len + int(0.05 * RATE)
	return out


func _synth_fanfare() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(1.3 * RATE))
	# весёлое чиптюн-арпеджио: до-ми-соль-до
	var seq := [[72, 0.0, 0.12], [76, 0.11, 0.12], [79, 0.22, 0.12], [84, 0.33, 0.7]]
	for nt in seq:
		var f := _mtof(nt[0])
		var st := int(nt[1] * RATE)
		var len := int((nt[2] + 0.25) * RATE)
		var ph := 0.0
		for k in len:
			var t := float(k) / RATE
			ph += f * (1.0 + 0.008 * sin(TAU * 6.0 * t) * minf(1.0, t * 4.0)) / RATE
			var sq := 1.0 if fposmod(ph, 1.0) < 0.25 else -1.0
			var env := minf(1.0, t / 0.004) * (exp(-t * 3.0) if t < nt[2] else exp(-nt[2] * 3.0) * exp(-(t - nt[2]) * 18.0))
			if st + k < out.size():
				out[st + k] += (sq * 0.12 + sin(TAU * ph) * 0.2) * env
	return out


func _synth_boom() -> PackedFloat32Array:
	var n := int(1.6 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := randf() * 2.0 - 1.0
		lp += (x - lp) * 0.08
		ph += (60.0 + 80.0 * exp(-t * 20.0)) / RATE
		var crackle := 0.0
		if t > 0.25 and randf() < 0.004 * exp(-(t - 0.25) * 2.0):
			crackle = randf_range(-0.5, 0.5)
		out[i] = (lp * 1.6 + sin(TAU * ph) * 0.5) * exp(-t * 5.0) + crackle
	return out


func _synth_cheer() -> PackedFloat32Array:
	var n := int(2.2 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := randf() * 2.0 - 1.0
		l1 += (x - l1) * 0.25
		l2 += (l1 - l2) * 0.25
		var bp := l1 - l2
		var env := minf(1.0, t / 0.3) * clampf((2.2 - t) / 1.2, 0.0, 1.0)
		var wob := 0.75 + 0.25 * sin(TAU * 5.0 * t + sin(TAU * 1.3 * t) * 2.0)
		out[i] = bp * env * wob * 1.4
	return out


## Гудок поезда: два мягких аккордовых «ту-ту».
func _synth_horn() -> PackedFloat32Array:
	var n := int(1.1 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phs := [0.0, 0.0, 0.0]
	for i in n:
		var t := float(i) / RATE
		var on := t < 0.38 or (t > 0.5 and t < 1.0)
		var env := 0.0
		if on:
			var tt := t if t < 0.38 else t - 0.5
			var ln := 0.38 if t < 0.38 else 0.5
			env = minf(1.0, tt / 0.03) * minf(1.0, (ln - tt) / 0.06)
		var s := 0.0
		var fr := [311.0, 370.0, 466.0]
		for k in 3:
			phs[k] += fr[k] / RATE
			s += (2.0 * fposmod(phs[k], 1.0) - 1.0) * 0.12
		out[i] = s * env
	var lp := 0.0
	for i in n:
		lp += (out[i] - lp) * 0.25
		out[i] = lp * 1.6
	return out


func _synth_ding() -> PackedFloat32Array:
	var n := int(0.9 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for st in [0.0, 0.42]:
			var tt: float = t - st
			if tt > 0.0:
				s += (sin(TAU * 1250.0 * tt) * 0.5 + sin(TAU * 3100.0 * tt) * 0.2) * exp(-tt * 9.0)
		out[i] = s * 0.35
	return out


func _synth_whoosh() -> PackedFloat32Array:
	var n := int(2.2 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var a := 0.03 + 0.12 * minf(1.0, t / 1.2)
		lp += (randf() * 2.0 - 1.0 - lp) * a
		var env := minf(1.0, t / 0.8) * clampf((2.2 - t) / 0.9, 0.0, 1.0)
		out[i] = lp * env * 1.2
	return out


func _synth_honk() -> PackedFloat32Array:
	var n := int(0.32 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 520.0 if t < 0.14 else 440.0
		var env := 1.0 if fposmod(t, 0.16) < 0.12 else 0.0
		var sq := 1.0 if fposmod(f * t, 1.0) < 0.5 else -1.0
		out[i] = sq * env * 0.16
	return out

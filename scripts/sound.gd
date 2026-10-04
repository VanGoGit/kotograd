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
}
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
}
const KEYS := {
	"comp": [[[0, 5], [6, 2], [10, 5]], [[0, 3], [3, 3], [8, 2], [11, 4]]],
	"pulse": [[[0, 6], [6, 4], [10, 6]], [[0, 4], [4, 4], [8, 4], [12, 4]]],
	"long": [[[0, 14]], [[0, 10], [10, 6]]],
}
const SCALE_PCS := [2, 4, 6, 7, 9, 11, 1]
const FORM := ["A", "A", "B", "break", "A", "lite", "B"]

var music_on := true
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
var _sec_step := 0           # первый шаг следующей части
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
	AudioServer.add_bus_effect(_music_bus, rev)
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = _lp_cut
	_lp.resonance = 0.6
	AudioServer.add_bus_effect(_music_bus, _lp)
	AudioServer.set_bus_volume_db(_music_bus, 0.0 if music_on else -80.0)

	_sfx["pop"] = _wav(_synth_pop())
	_sfx["dig"] = _wav(_synth_dig())
	_sfx["mew"] = _wav(_synth_mew())
	_sfx["chime"] = _wav(_synth_chime())
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)

	if _web:
		_dly_l.resize(DLY)
		_dly_r.resize(DLY)
		for i in 3:
			var wp := AudioStreamPlayer.new()
			wp.bus = "Music"
			wp.volume_db = -3.0
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


func _process(_delta: float) -> void:
	_warm_up(3000)
	var target: float = MOODS[_mood_for(hour)].lp
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
	while float(_sec_step) * _step_len < float(end) + _step_len * 16.0 * BARS:
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
	var key := "%s|%d|%d" % [inst, midi, dur]
	if not _cache.has(key) and not _warm.has(key):
		_warm.append(key)
	var at := int(round((_sec_step + step) * _step_len))
	_new.append([at, key, vel * randf_range(0.9, 1.05), pan])


func _gen_section() -> void:
	var mood: String = _mood_for(hour)
	var M: Dictionary = MOODS[mood]
	var kind: String = "intro" if _sec_n == 0 else FORM[(_sec_n - 1) % FORM.size()]
	_sec_n += 1
	# темы повторяются — так мелодии запоминаются
	var tk := mood + ("B" if kind == "B" else "A")
	var theme: Dictionary = _themes.get(tk, {})
	if theme.is_empty() or (kind == "B" and randf() < 0.5):
		var pr: Array = M.progs.pick_random()
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
				_ev(b0, "pad", voicing[j], 16, 0.55 if mood == "sunset" else 0.38, -0.5 if j % 2 == 0 else 0.5)
		# арпеджио
		if arp_on and kind != "intro":
			var tones: Array = []
			for m in voicing:
				tones.append(m + 12)
			var order := [0, 1, 2, 3, 2, 1, 0, 1] if tones.size() >= 4 else [0, 1, 2, 1]
			var stride := 1 if mood == "sunset" else 2
			var av := 0.28 if lead_on else 0.45
			for s in range(0, 16, stride):
				var m: int = tones[order[(s / stride) % order.size()] % tones.size()]
				_ev(b0 + s, "arp", m, 1, av * (1.2 if s % 4 == 0 else 1.0), -0.25)
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
	_sec_step += BARS * 16


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
		if SCALE_PCS.has(x % 12):
			moved += 1
	return x


# ---------- инструменты ----------

static func _mtof(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


func _synth(key: String) -> PackedFloat32Array:
	var parts := key.split("|")
	var inst := parts[0]
	var m := int(parts[1])
	var dur := float(int(parts[2])) * _step_len / SR
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
	return PackedFloat32Array()


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


func play(name: String, pitch := 1.0) -> void:
	if not _sfx.has(name):
		return
	var p: AudioStreamPlayer = _sfx_players[_sp]
	_sp = (_sp + 1) % _sfx_players.size()
	p.stream = _sfx[name]
	p.pitch_scale = pitch
	p.volume_db = -4.0
	p.play()


func set_music(on: bool) -> void:
	music_on = on
	AudioServer.set_bus_volume_db(_music_bus, 0.0 if on else -80.0)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("audio", "music", on)
	cfg.save("user://settings.cfg")


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		music_on = cfg.get_value("audio", "music", true)

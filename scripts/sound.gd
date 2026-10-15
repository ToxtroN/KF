class_name Sound
## Звук: музыка и эффекты на отдельных шинах (Music / SFX) с громкостью из настроек.
## Файлы — в res://assets/sounds/. Писки тараканов: roach_hit_1..20.mp3 (подхватываются сами).

const DIR := "res://assets/sounds/"
const MUSIC_DB := -10.0             # базовая громкость музыки
const HIT_DB := -2.0                # базовая громкость писка
const SETTINGS := "user://settings.cfg"

static var music_volume := 0.8      # 0..1
static var sfx_volume := 0.9        # 0..1
static var shake := 1.0             # сила тряски экрана 0..1 (0 — выключена)
static var _loaded := false
static var _hits: Array = []


## Шины Music и SFX создаются при первом обращении.
static func _ensure_buses() -> void:
	for name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, name)
			AudioServer.set_bus_send(i, "Master")


static func load_settings() -> void:
	_ensure_buses()
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		music_volume = cf.get_value("audio", "music_volume", 0.8)
		sfx_volume = cf.get_value("audio", "sfx_volume", 0.9)
		shake = cf.get_value("video", "shake", 1.0)
	apply()


## Применить громкость к шинам (сразу слышно, без сохранения).
static func apply() -> void:
	_ensure_buses()
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)


static func _set_bus(name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "music_volume", music_volume)
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("video", "shake", shake)
	cf.save(SETTINGS)


## Плеер эффектов (шина SFX).
static func sfx_player(owner: Node) -> AudioStreamPlayer:
	load_settings()
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	owner.add_child(p)
	return p


## Запустить музыку по кругу (шина Music).
static func music(owner: Node, file: String) -> AudioStreamPlayer:
	load_settings()
	var p := AudioStreamPlayer.new()
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.volume_db = MUSIC_DB
	p.bus = "Music"
	owner.add_child(p)
	var path := DIR + file
	if ResourceLoader.exists(path):
		var s = load(path)
		if s is AudioStreamMP3 or s is AudioStreamOggVorbis:
			s.loop = true
		p.stream = s
		p.play()
	return p


## Таракан пищит, когда по нему попали. Случайный звук из roach_hit_*.
static func roach_hit(owner: Node, pitch := 1.0) -> void:
	if _hits.is_empty():
		for i in range(1, 21):
			for ext in ["mp3", "ogg", "wav"]:
				var path := "%sroach_hit_%d.%s" % [DIR, i, ext]
				if ResourceLoader.exists(path):
					_hits.append(load(path))
	if _hits.is_empty():
		return
	var p := sfx_player(owner)
	p.stream = _hits.pick_random()
	p.volume_db = HIT_DB
	p.pitch_scale = randf_range(0.9, 1.15) * pitch
	p.finished.connect(p.queue_free)
	p.play()

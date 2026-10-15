extends Node2D
## Главная сцена: стол, тараканы, мухобойка, очки, волны, босс.

const VIEW_CENTER := Vector2(640, 380)
const SAVE_PATH := "user://save.cfg"
const SPAWN_TYPES := ["normal", "fast", "big", "flying"]
const OS_HEAD := "STUDENT OS 98"

enum Mode { MENU, PLAY, END }

var mode := Mode.MENU
var world: Node2D
var items_layer: Node2D
var decals_layer: Node2D
var roach_layer: Node2D
var fx_layer: Node2D
var hand: Hand
var hud: Hud

var foods: Array[Food] = []
var breakables: Array[Breakable] = []
var props: Array[Prop] = []
var obstacles: Array[Rect2] = []   # по ним нельзя бегать и тащить еду (монитор, клавиатура)
var pc_label: Label                # текст на экране монитора
var pc_head: Label                 # шапка «STUDENT OS 98»

enum Phase { COUNTDOWN, WAVE }
var phase := Phase.COUNTDOWN
var wave := 0                      # индекс текущей волны
var _queue: Array[String] = []     # кто ещё не вышел в этой волне
var _count_t := 0.0
var _last_digit := -1
var _rush_t := 20.0
var _rushing := false
var _pending := 0                  # тараканы, которые вот-вот выйдут (вспышка, подкрепление)
var _boss_due := false             # босс объявлен, но ещё не вышел
var _boss: Roach
var _round_id := 0                 # отложенные вызовы от прошлого раунда игнорируются
var _last_done := false            # «последний таракан» уже отыгран в этой волне

var score := 0
var best := 0
var elapsed := 0.0
var streak := 0
var kills := 0
var _spawn_t := 1.0
var _shake := 0.0
var _sfx: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer

# комбо
var _combo_max := false
# STUDENT OS 98
var _pc_hold := 0.0
var _seen_flying := false
# время: стоп-кадр и замедление
var _ts_scale := 1.0
var _ts_until := 0
var time_fx_on := true             # тесты выключают: в них время идёт не в реальном темпе
# кофе
var _puddles: Array = []           # {node, c, rx, ry, t}
# вилка на столе
var _fallen_fork: Sprite2D
var _fork_food: Food


func _ready() -> void:
	randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

	var table := Sprite2D.new()
	table.texture = Cfg.tex(Cfg.TABLE_TEXTURE)
	table.centered = false
	table.position = Vector2(0, Cfg.TABLE_OFFSET_Y)
	world.add_child(table)

	items_layer = _layer()
	decals_layer = _layer()
	roach_layer = _layer()
	fx_layer = _layer()
	fx_layer.z_index = 10

	hand = Hand.new()
	hand.z_index = 20
	world.add_child(hand)
	hand.slammed.connect(_on_slam)
	hand.aim(VIEW_CENTER)

	hud = Hud.new()
	add_child(hud)
	hud.start_pressed.connect(start_round)
	hud.pause_pressed.connect(func(): _set_paused(true))
	hud.resume_pressed.connect(func(): _set_paused(false))

	for i in 8:
		_players.append(Sound.sfx_player(self))

	_music = Sound.music(self, "music_student.mp3")
	_load_best()
	_build_table()
	start_round()   # «Начать игру» в меню — сразу в бой


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _layer() -> Node2D:
	var n := Node2D.new()
	world.add_child(n)
	return n


func _build_table() -> void:
	for c in items_layer.get_children():
		c.queue_free()
	for c in decals_layer.get_children():
		c.queue_free()
	foods.clear()
	breakables.clear()
	props.clear()
	obstacles.clear()
	_puddles.clear()
	_fallen_fork = null
	_fork_food = null
	pc_label = null
	pc_head = null
	for d in Cfg.TABLE_ITEMS:
		_add_blocks(d)
		match d.kind:
			"decor":
				var s := Sprite2D.new()
				s.texture = Cfg.tex(d.tex)
				s.position = d.pos
				s.rotation = d.get("rot", 0.0)
				if s.texture and d.has("w"):
					s.scale = Vector2.ONE * (float(d.w) / s.texture.get_width())
				items_layer.add_child(s)
			"prop":
				var pr := Prop.new()
				items_layer.add_child(pr)
				pr.setup(d)
				props.append(pr)
			"food":
				var f := Food.new()
				items_layer.add_child(f)
				f.setup(d, self)
				f.lost.connect(_on_food_lost)
				foods.append(f)
			"breakable":
				var b := Breakable.new()
				items_layer.add_child(b)
				b.setup(d)
				breakables.append(b)
				if d.has("screen"):
					_make_pc_screen(b, d)


## Переводит прямоугольник из пикселей спрайта предмета в координаты экрана.
func _item_rect(d: Dictionary, r: Rect2) -> Rect2:
	var t := Cfg.tex(d.tex)
	if t == null:
		return Rect2()
	var s: float = float(d.get("w", t.get_width())) / t.get_width()
	var top_left: Vector2 = d.pos - t.get_size() * s * 0.5
	return Rect2(top_left + r.position * s, r.size * s)


func _add_blocks(d: Dictionary) -> void:
	for r in d.get("blocks", []):
		obstacles.append(_item_rect(d, r))


func _make_pc_screen(b: Breakable, d: Dictionary) -> void:
	var r := _item_rect(d, d.screen)
	pc_label = Label.new()
	pc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc_label.position = r.position
	pc_label.size = r.size
	pc_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	pc_label.add_theme_color_override("font_shadow_color", Color(0.2, 1.0, 0.3, 0.45))
	pc_label.add_theme_constant_override("shadow_offset_x", 0)
	pc_label.add_theme_constant_override("shadow_offset_y", 0)
	pc_label.add_theme_constant_override("shadow_outline_size", 10)
	pc_label.add_theme_constant_override("line_spacing", -6)
	pc_label.add_theme_font_size_override("font_size", 26)
	pc_label.clip_text = true
	items_layer.add_child(pc_label)
	items_layer.move_child(pc_label, b.get_index() + 1)
	# шапка «операционной системы» — видна, когда компьютер что-то сообщает
	pc_head = Label.new()
	pc_head.text = OS_HEAD
	pc_head.position = r.position + Vector2(4, 1)
	pc_head.size = Vector2(r.size.x - 8, 16)
	pc_head.add_theme_font_size_override("font_size", 12)
	pc_head.add_theme_color_override("font_color", Color(0.05, 0.15, 0.05))
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0.55, 1.0, 0.6)
	pc_head.add_theme_stylebox_override("normal", hb)
	pc_head.visible = false
	items_layer.add_child(pc_head)
	items_layer.move_child(pc_head, pc_label.get_index() + 1)


func _pc_text(text: String, size: int) -> void:
	if pc_label == null or _pc_hold > 0.0:
		return
	pc_label.text = text
	pc_label.add_theme_font_size_override("font_size", size)
	pc_head.visible = false


## Сообщение «STUDENT OS 98» на мониторе: держится dur секунд, счётчик волны его не перебивает.
func _pc_say(text: String, dur := 2.5) -> void:
	if pc_label == null:
		return
	_pc_hold = dur
	pc_label.text = "\n" + text
	pc_label.add_theme_font_size_override("font_size", 22)
	pc_head.visible = true
	_blink_pc()


# ------------------------------------------------------------ препятствия

func _grown(r: Rect2, pad: Vector2) -> Rect2:
	return Rect2(r.position - pad, r.size + pad * 2.0)


func blocked_at(p: Vector2, pad: Vector2) -> bool:
	for r in obstacles:
		if _grown(r, pad).has_point(p):
			return true
	return false


## Выталкивает точку из препятствий к ближайшему краю.
func push_out(p: Vector2, pad: Vector2) -> Vector2:
	for r in obstacles:
		var g := _grown(r, pad)
		if g.has_point(p):
			var dl := p.x - g.position.x
			var dr := g.end.x - p.x
			var dt := p.y - g.position.y
			var db := g.end.y - p.y
			var m := minf(minf(dl, dr), minf(dt, db))
			if m == dl: p.x = g.position.x - 0.5
			elif m == dr: p.x = g.end.x + 0.5
			elif m == dt: p.y = g.position.y - 0.5
			else: p.y = g.end.y + 0.5
	return p


func _segment_hits(a: Vector2, b: Vector2, g: Rect2) -> bool:
	# отсечение Лианга — Барски: пересекает ли отрезок ab прямоугольник g
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var ps := [-d.x, d.x, -d.y, d.y]
	var qs := [a.x - g.position.x, g.end.x - a.x, a.y - g.position.y, g.end.y - a.y]
	for i in 4:
		var p: float = ps[i]
		var q: float = qs[i]
		if absf(p) < 0.0001:
			if q < 0.0:
				return false
		else:
			var r := q / p
			if p < 0.0:
				t0 = maxf(t0, r)
			else:
				t1 = minf(t1, r)
			if t0 > t1:
				return false
	return true


func path_clear(a: Vector2, b: Vector2, pad: Vector2) -> bool:
	for r in obstacles:
		if _segment_hits(a, b, _grown(r, pad)):
			return false
	return true


## Куда идти сейчас, чтобы попасть в to в обход препятствий: сама цель или угол препятствия.
func route(from: Vector2, to: Vector2, pad: Vector2) -> Vector2:
	# с запасом 0.85: таракан, прижатый к краю препятствия, не считается «внутри»
	if path_clear(from, to, pad * 0.85):
		return to
	var best_p := to
	var best_d := INF
	for r in obstacles:
		var g := _grown(r, pad + Vector2(16, 16))
		for c in [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]:
			if blocked_at(c, pad) or not path_clear(from, c, pad * 0.85):
				continue
			if from.distance_to(c) < 20.0:   # уже стоим в этом углу — он не цель, иначе застрянем
				continue
			var dd: float = from.distance_to(c) + c.distance_to(to)
			if dd < best_d:
				best_d = dd
				best_p = c
	return best_p


# ------------------------------------------------------------ раунд

func start_round() -> void:
	_round_id += 1
	for c in roach_layer.get_children():
		c.queue_free()
	for c in fx_layer.get_children():
		c.queue_free()
	_build_table()
	_rushing = false
	_pending = 0
	_boss_due = false
	_boss = null
	score = 0
	elapsed = 0.0
	streak = 0
	kills = 0
	_combo_max = false
	_pc_hold = 0.0
	_seen_flying = false
	wave = 0
	mode = Mode.PLAY
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	hud.show_game()
	_start_countdown()
	_update_hud()


func end_round(win: bool) -> void:
	if mode != Mode.PLAY:
		return
	mode = Mode.END
	Engine.time_scale = 1.0
	var left := food_left()
	if win:
		score += left * Cfg.FOOD_KEPT_BONUS
	var new_record := score > best
	if new_record:
		best = score
		_save_best()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true   # замораживаем стол под экраном итогов
	_play("win" if win else "lose")
	hud.waves_done = wave
	hud.show_boss(false)
	hud.show_end(win, score, best, new_record, kills, left)


func food_left() -> int:
	return foods.size()


func food_max() -> int:
	var n := 0
	for d in Cfg.TABLE_ITEMS:
		if d.kind == "food":
			n += 1
	return n


func roaches() -> Array:
	return get_tree().get_nodes_in_group("roaches")


func _wave_left() -> int:
	return _queue.size() + roaches().size() + _pending + (1 if _boss_due else 0)


func _process(delta: float) -> void:
	# стоп-кадр и замедление считаются по реальному времени
	if mode == Mode.PLAY and not get_tree().paused:
		Engine.time_scale = _ts_scale if Time.get_ticks_msec() < _ts_until else 1.0
	else:
		Engine.time_scale = 1.0
	_shake = maxf(_shake - delta * 40.0, 0.0)
	world.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * Sound.shake
	_update_music(delta)
	if mode != Mode.PLAY or get_tree().paused:
		return
	elapsed += delta
	_pc_hold -= delta
	_tick_puddles(delta)
	_pulse_fork()
	if _boss and is_instance_valid(_boss) and _boss.is_alive():
		hud.set_boss(_boss.hp, _boss.max_hp)
	if phase == Phase.COUNTDOWN:
		_tick_countdown(delta)
		return
	# волна: выпускаем тараканов из очереди
	_spawn_t -= delta
	if _spawn_t <= 0.0 and not _queue.is_empty() and roaches().size() < Cfg.MAX_ROACHES:
		# между вспышками — размеренно; вспышки идут отдельно
		var calm: float = Cfg.RUSH_CALM if not wave_def(wave).rushes.is_empty() else 1.0
		_spawn_t = float(wave_def(wave).interval) * calm * randf_range(0.6, 1.4)
		_spawn_roach(_queue.pop_back())
	_tick_rush(delta)
	var left := _wave_left()
	_pc_text("ВОЛНА %d\nтараканов: %d" % [wave + 1, left], 30)
	if left == 0 and not _rushing:
		_wave_cleared()


# ------------------------------------------------------------ время

## Engine.time_scale = s на dur реальных секунд (стоп-кадр удара, замедление).
func _time_fx(s: float, dur: float) -> void:
	if not time_fx_on:
		return
	var now := Time.get_ticks_msec()
	if now >= _ts_until or s <= _ts_scale:
		_ts_scale = s
	_ts_until = maxi(_ts_until, now + int(dur * 1000.0))


func _add_shake(v: float) -> void:
	_shake = maxf(_shake, v)


# ------------------------------------------------------------ волны

## Волна по номеру (после последней — повторяется последняя).
func wave_def(i: int) -> Dictionary:
	return Cfg.WAVES[clampi(i, 0, Cfg.WAVES.size() - 1)]


func _start_countdown() -> void:
	phase = Phase.COUNTDOWN
	_count_t = float(Cfg.COUNTDOWN)
	_last_digit = -1
	var w := wave_def(wave)
	hud.set_wave(wave + 1, Cfg.TOTAL_WAVES, w.name)
	_banner("Волна %d: %s" % [wave + 1, w.name], w.get("sub", ""), Color(1, 0.85, 0.3), -1, Cfg.COUNTDOWN - 1.0)


func _tick_countdown(delta: float) -> void:
	_count_t -= delta
	var digit := ceili(_count_t)
	if digit != _last_digit:
		_last_digit = digit
		if digit > 0:
			_pc_text("ВОЛНА %d\n%d" % [wave + 1, digit], 44)
			_play("beep")
			_blink_pc()
	if _count_t <= 0.0:
		_start_wave()


func _blink_pc() -> void:
	if pc_label == null:
		return
	pc_label.modulate = Color(1.6, 1.6, 1.6)
	pc_label.create_tween().tween_property(pc_label, "modulate", Color.WHITE, 0.4)


func _start_wave() -> void:
	phase = Phase.WAVE
	_last_done = false
	_queue.clear()
	var w: Dictionary = wave_def(wave)
	for t in SPAWN_TYPES:
		for i in int(w.get(t, 0)):
			_queue.append(t)
	_queue.shuffle()
	_spawn_t = 0.3
	var re: Vector2 = w.get("rush_every", Vector2(16, 24))
	_rush_t = randf_range(re.x * 0.6, re.y * 0.8)
	for f in foods:
		f.set_light(w.get("light_food", false))
	_pc_say(w.name.to_upper() if w.name.length() <= 18 else w.name, 2.0)
	_play("wave_start")
	if w.get("tips", false):
		_tips()
	if w.get("boss", false):
		_boss_due = true
		_later(2.5, _spawn_boss)


## Подсказки новичку на мониторе (первая волна).
func _tips() -> void:
	_later(2.2, func(): _pc_say("Кликни\nпо таракану!", 3.5))
	_later(8.0, func(): _pc_say("Не дай утащить\nеду со стола!", 3.5))
	_later(14.0, func(): _pc_say("Промах пугает\nтараканов", 3.5))


## Отложенный вызов в рамках текущего раунда (на паузе стоит).
func _later(t: float, cb: Callable) -> void:
	var id := _round_id
	get_tree().create_timer(t, false).timeout.connect(func():
		if id == _round_id and mode == Mode.PLAY:
			cb.call())


func _wave_cleared() -> void:
	var bonus: int = Cfg.WAVE_CLEAR_BONUS * (wave + 1)
	score += bonus
	_popup(Vector2(640, 420), "Волна %d отбита!\n+%d" % [wave + 1, bonus], Color(0.6, 1, 0.6))
	_update_hud()
	wave += 1
	if wave >= Cfg.TOTAL_WAVES:
		_pc_text("ПОБЕДА!", 44)
		end_round(true)
	else:
		_start_countdown()


func _spawn_roach(pick: String, at := Vector2.INF) -> Roach:
	var roach := Roach.new()
	roach_layer.add_child(roach)
	roach.setup(pick, _edge_point() if at == Vector2.INF else at, self)
	if pick == "flying" and not _seen_flying:
		_seen_flying = true
		_pc_say("ОНИ НАУЧИЛИСЬ\nЛЕТАТЬ?!", 3.0)
	return roach


## Группа тараканов с одной стороны (вспышка, подкрепление разведчика).
func _spawn_group(type: String, n: int, side: int, gap: float, delay: float, done := Callable()) -> void:
	_pending += n
	var id := _round_id
	get_tree().create_timer(delay, false).timeout.connect(func():
		if id != _round_id:
			return
		if mode != Mode.PLAY:
			_pending = 0
			return
		_add_shake(10.0)
		var tw := world.create_tween()
		for i in n:
			tw.tween_callback(func():
				if id != _round_id:
					return
				_pending = maxi(_pending - 1, 0)
				_spawn_roach(type, _side_point(side)))
			tw.tween_interval(gap)
		tw.tween_callback(func():
			if id == _round_id and done.is_valid():
				done.call()))


# ------------------------------------------------------------ вспышки

func _tick_rush(delta: float) -> void:
	if _rushing or wave_def(wave).rushes.is_empty():
		return
	if wave_def(wave).get("boss", false) and not _boss_due and (_boss == null or not is_instance_valid(_boss)):
		return   # король повержен — новых атак нет, добиваем остатки
	_rush_t -= delta
	if _rush_t <= 0.0:
		_start_rush()


## Предупреждение → толпа тараканов с одной стороны.
func _start_rush() -> void:
	var w := wave_def(wave)
	var pool: Array = Cfg.RUSHES.filter(func(r): return w.rushes.has(r.type))
	if pool.is_empty():
		return
	_rushing = true
	var r: Dictionary = pool.pick_random()
	var side := randi() % 3          # 0 — слева, 1 — справа, 2 — сверху
	var n: int = int(r.count + r.count_per_wave * maxi(wave - 1, 0))
	_rush_banner(r.name, side)
	_play("rush")
	var re: Vector2 = w.get("rush_every", Vector2(16, 24))
	_spawn_group(r.type, n, side, r.gap, Cfg.RUSH_WARN, func():
		_rushing = false
		_rush_t = randf_range(re.x, re.y))


func _side_point(side: int) -> Vector2:
	var m := 40.0
	for i in 20:
		var p: Vector2
		match side:
			0: p = Vector2(-m, randf_range(80, Cfg.TABLE_NEAR_EDGE - 80))
			1: p = Vector2(Cfg.VIEW.x + m, randf_range(80, Cfg.TABLE_NEAR_EDGE - 80))
			_: p = Vector2(randf_range(60, Cfg.VIEW.x - 60), -m)
		if not blocked_at(p + Vector2(0, 60), Vector2(30, 30)):
			return p
	return _edge_point()


## Надпись по центру и мигающая красная полоса у края, откуда полезут.
func _rush_banner(text: String, side: int) -> void:
	_banner(text, "", Color(1, 0.25, 0.15), side, Cfg.RUSH_WARN + 0.6)


## Крупная надпись по центру экрана (и, если side >= 0, мигающий край).
func _banner(text: String, sub: String, color: Color, side: int, dur: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	if side >= 0:
		var strip := ColorRect.new()
		strip.color = Color(1, 0.1, 0.05, 0.0)
		match side:
			0: strip.position = Vector2(0, 0); strip.size = Vector2(70, Cfg.VIEW.y)
			1: strip.position = Vector2(Cfg.VIEW.x - 70, 0); strip.size = Vector2(70, Cfg.VIEW.y)
			_: strip.position = Vector2(0, 0); strip.size = Vector2(Cfg.VIEW.x, 60)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(strip)
		var st := strip.create_tween().set_loops(4)
		st.tween_property(strip, "color:a", 0.55, 0.2)
		st.tween_property(strip, "color:a", 0.0, 0.2)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(Cfg.VIEW.x, 100)
	l.position = Vector2(0, 230)
	l.add_theme_font_size_override("font_size", 64 if text.length() < 22 else 52)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 14)
	l.pivot_offset = l.size / 2.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(l)
	if sub != "":
		var s := Label.new()
		s.text = sub
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.size = Vector2(Cfg.VIEW.x, 50)
		s.position = Vector2(0, 325)
		s.add_theme_font_size_override("font_size", 32)
		s.add_theme_color_override("font_outline_color", Color.BLACK)
		s.add_theme_constant_override("outline_size", 10)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_child(s)
		s.position = Vector2(0, 95)
	l.scale = Vector2.ONE * 2.2
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var end := layer.create_tween()
	end.tween_interval(dur)
	end.tween_property(l, "modulate:a", 0.0, 0.4)
	end.tween_callback(layer.queue_free)


func _edge_point() -> Vector2:
	var m := 40.0
	for i in 30:
		var p: Vector2
		match randi() % 4:
			0: p = Vector2(-m, randf_range(60, Cfg.TABLE_NEAR_EDGE - 60))
			1: p = Vector2(Cfg.VIEW.x + m, randf_range(60, Cfg.TABLE_NEAR_EDGE - 60))
			_: p = Vector2(randf_range(60, Cfg.VIEW.x - 60), -m)
		# за монитором не появляемся: сверху вылезают только сбоку от него
		if not blocked_at(p + Vector2(0, 60), Vector2(30, 30)):
			return p
	return Vector2(-m, 300)


## Ближайшая точка за краем стола (слева, справа или сверху — снизу сидит студент).
func exit_point(from: Vector2, m := 90.0, pad := Vector2.ZERO) -> Vector2:
	var c := [Vector2(-m, from.y), Vector2(Cfg.VIEW.x + m, from.y), Vector2(from.x, -m)]
	var best_p: Vector2 = c[0]
	var best_d := INF
	for p in c:
		# путь, перегороженный компьютером, считаем вдвое длиннее — обходить долго
		var d: float = from.distance_to(p) * (1.0 if path_clear(from, p, pad) else 2.5)
		if d < best_d:
			best_d = d
			best_p = p
	return best_p


## Таракан выбирает блюдо: ближнее, то, под которым уже компания, и цель волны («Операция …»).
func pick_food(from: Vector2) -> Food:
	var target_id: String = wave_def(wave).get("target", "")
	var best_f: Food = null
	var best_s := INF
	for f in foods:
		if f.gone or not f.has_free_slot():
			continue
		var s := from.distance_to(f.global_position) - 120.0 * f.carriers.size() + randf() * 150.0
		if target_id != "" and f.id == target_id:
			s -= 900.0
		if s < best_s:
			best_s = s
			best_f = f
	return best_f


# ------------------------------------------------------------ босс

func _spawn_boss() -> void:
	_boss_due = false
	var side := randi() % 2
	_boss = _spawn_roach("boss", _side_point(side))
	_boss.hp = randi_range(Cfg.BOSS_HP.x, Cfg.BOSS_HP.y)
	_boss.max_hp = _boss.hp
	hud.show_boss(true)
	hud.set_boss(_boss.hp, _boss.max_hp)
	_banner("КОРОЛЬ ОБЩАГИ!", "Бей его %d раз — и берегись его свиты" % _boss.hp, Color(1, 0.55, 0.2), side, 2.4)
	_pc_say("ВНИМАНИЕ!\nОбнаружен\nКОРОЛЬ ОБЩАГИ", 3.5)
	_add_shake(14.0)
	_play("boss")


## Босс зовёт мелких: они вылезают прямо из-под него.
func boss_summon(boss: Roach) -> void:
	if mode != Mode.PLAY or roaches().size() >= Cfg.MAX_ROACHES:
		return
	for i in Cfg.BOSS_SUMMON_COUNT:
		var at: Vector2 = push_out(boss.global_position + Vector2.from_angle(randf() * TAU) * 50.0, Vector2(20, 20))
		_spawn_roach("normal", at)
	_popup(boss.global_position + Vector2(0, -110), ["Ко мне, братва!", "Взять его!", "Свита, вперёд!"].pick_random(), Color(1, 0.6, 0.3))


func boss_panic(boss: Roach) -> void:
	_popup(boss.global_position + Vector2(0, -120), "Король в панике!", Color(1, 0.4, 0.3))


func _boss_killed(boss: Roach) -> void:
	_time_fx(0.2, 1.1)
	_add_shake(22.0)
	_splat(boss.global_position, 3.0)
	_big_text("КОРОЛЬ ПОВЕРЖЕН!", boss.global_position + Vector2(0, -60), Color(1, 0.85, 0.3), 54)
	_pc_say("Общага очищена.\nПока что…", 5.0)
	hud.show_boss(false)
	_boss = null


# ------------------------------------------------------------ ввод

func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.PLAY:
		return
	if event is InputEventMouseMotion:
		hand.aim(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_tree().paused:
			_set_paused(false)
			return
		hand.aim(event.position)
		hand.swing()
	elif event.is_action_pressed("ui_cancel"):
		_set_paused(not get_tree().paused)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == Mode.PLAY:
		_set_paused(true)


func _set_paused(v: bool) -> void:
	get_tree().paused = v
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if v else Input.MOUSE_MODE_HIDDEN
	hud.show_pause(v)


# ------------------------------------------------------------ удар

func _on_slam(p: Vector2, r: float) -> void:
	if mode != Mode.PLAY:
		return
	_add_shake(6.0)
	_play("slap")
	_impact(p, r)
	var hit_roach := false
	var hit_boss := false
	var killed: Array[Roach] = []
	for c in roaches():
		var roach := c as Roach
		if roach and roach.hit_test(p, r):
			hit_roach = true
			if roach.type == "boss":
				hit_boss = true
			Sound.roach_hit(self, 0.6 if roach.type == "boss" else 1.0)
			if roach.damage(p):
				killed.append(roach)

	if hit_roach:
		_time_fx(0.05, Cfg.HITSTOP)   # микропауза — удар «чувствуется»
		if hit_boss:
			_add_shake(12.0)
		if not killed.is_empty():
			streak += 1
		_score_kills(killed, p)
		return

	# мимо тараканов — но некоторые промахи полезны
	if _try_fork(p):
		return
	for pr in props:
		if pr.is_ready() and pr.contains(p):
			_prop_action(pr, p)
			_update_hud()
			return
	for f in foods:
		if f.lid and f.contains(p) and _close_lid(f):
			_update_hud()
			return

	# настоящий промах
	_reset_streak()
	for c in roaches():
		var roach := c as Roach
		if roach and roach.global_position.distance_to(p) <= Cfg.SCARE_RADIUS:
			roach.scare(p)
	for f in foods:
		if f.splash_hit(p):
			_noodle_splash(f, p)
			_update_hud()
			return
	for b in breakables:
		if b.contains(p):
			b.smash(p)
			_add_shake(12.0)
			score = maxi(score - b.penalty, 0)
			_popup(p, "-%d" % b.penalty, Color(1, 0.3, 0.3))
			_play("break")
			if b.effect == "spill":
				_make_puddle(b.global_position + Vector2(-115, 75))
				_pc_say("Кофе пролит.\nСкользко!", 3.0)
			elif b.hit_offset.y < 0.0 and b.penalty >= 50:
				_pc_say("СИНИЙ ЭКРАН…\nшутка. -%d" % b.penalty, 3.0)
			break
	_update_hud()


func _reset_streak() -> void:
	streak = 0
	if _combo_max:
		_combo_max = false
		hud.set_combo_glow(false)


func _score_kills(killed: Array[Roach], at: Vector2) -> void:
	if killed.is_empty():
		_update_hud()
		return
	var mult := combo_mult()
	var gained := 0
	for roach in killed:
		gained += int(roach.data.score) * mult
		if roach.type == "boss":
			_boss_killed(roach)
		elif not roach.flung:
			_splat(roach.global_position, roach.data.scale / 0.55)
		else:
			_popup(roach.global_position + Vector2(0, -40), "В полёт!", Color(1, 0.8, 0.5))
	var n := killed.size()
	if n > 1:
		gained += Cfg.MULTIKILL_BONUS * (n - 1) * mult
	kills += n
	score += gained
	var txt := "+%d" % gained
	if mult > 1:
		txt += "  x%d" % mult
	_popup(at, txt, Color(1, 0.95, 0.4))
	if n >= 2:
		var names := {2: "ДВОЙНОЙ!", 3: "ТРОЙНОЙ!"}
		_big_text(names.get(n, "МЕГА-ШЛЕПОК!"), at + Vector2(0, -70), Color(1, 0.6, 0.2), 44 + mini(n, 5) * 4)
		_add_shake(8.0 + n * 2.0)
	if combo_mult() >= Cfg.COMBO_MAX and not _combo_max:
		_combo_max = true
		hud.set_combo_glow(true)
		_pc_say("Мама бы\nгордилась!", 3.0)
		_big_text("КОМБО x%d!" % Cfg.COMBO_MAX, Vector2(640, 200), Color(1, 0.85, 0.2), 48)
	_play("splat")
	# последний таракан волны — замедление и сочный финальный шлепок
	if phase == Phase.WAVE and not _last_done and _wave_left() == 0 and not _rushing:
		_last_done = true
		_time_fx(0.25, Cfg.LAST_ROACH_SLOWMO)
		_add_shake(18.0)
		_impact(at, 140.0)
		_big_text("ПОСЛЕДНИЙ!", at + Vector2(0, -110), Color(1, 1, 0.6), 56)
	_update_hud()


func combo_mult() -> int:
	return mini(1 + streak / Cfg.COMBO_STEP, Cfg.COMBO_MAX)


func _update_music(delta: float) -> void:
	if _music == null:
		return
	var vol := Sound.MUSIC_DB + (2.0 if _combo_max else 0.0)
	_music.volume_db = move_toward(_music.volume_db, vol, delta * 8.0)


# ------------------------------------------------------------ предметы

func _prop_action(pr: Prop, p: Vector2) -> void:
	match pr.kind:
		"keyboard":
			pr.cooldown = 6.0
			_keys_fly(pr.global_position)
			_scare_ring(pr.global_position, Cfg.KEYBOARD_SCARE)
			_popup(p + Vector2(0, -50), "Клац!", Color(0.8, 0.9, 1))
			_add_shake(8.0)
	_play("prop")


## Вокруг точки: волна-кольцо, тараканы в радиусе бросаются бежать.
func _scare_ring(at: Vector2, radius: float) -> void:
	_ring(at, radius, Color(1, 1, 1, 0.7))
	for c in roaches():
		if c.global_position.distance_to(at) <= radius:
			c.scare(at, c.type != "boss")


func _ring(at: Vector2, radius: float, color: Color) -> void:
	var l := Line2D.new()
	l.width = 5.0
	l.default_color = color
	l.closed = true
	for k in 36:
		l.add_point(Vector2.from_angle(TAU * k / 36.0) * radius)
	l.position = at
	l.scale = Vector2.ONE * 0.2
	fx_layer.add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(l.queue_free)


## Клавиши разлетаются с клавиатуры.
func _keys_fly(at: Vector2) -> void:
	var letters := "QWERTYASDFGHZXCV"
	for i in 7:
		var key := Polygon2D.new()
		key.polygon = PackedVector2Array([Vector2(-15, -15), Vector2(15, -15), Vector2(15, 15), Vector2(-15, 15)])
		key.color = Color(0.85, 0.85, 0.8)
		var ol := Line2D.new()
		ol.points = key.polygon
		ol.closed = true
		ol.width = 2.5
		ol.default_color = Color(0.2, 0.2, 0.2)
		key.add_child(ol)
		var l := Label.new()
		l.text = letters[randi() % letters.length()]
		l.position = Vector2(-10, -16)
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
		key.add_child(l)
		key.position = at + Vector2(randf_range(-150, 150), randf_range(-40, 40))
		fx_layer.add_child(key)
		var dest := key.position + Vector2(randf_range(-260, 260), randf_range(60, 260))
		var tw := key.create_tween().set_parallel()
		tw.tween_property(key, "position", dest, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(key, "rotation", randf_range(-9, 9), 0.7)
		tw.tween_property(key, "scale", Vector2.ONE * 1.6, 0.25).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(key, "scale", Vector2.ONE, 0.4)
		tw.chain().tween_interval(1.0)
		tw.chain().tween_property(key, "modulate:a", 0.0, 0.5)
		tw.chain().tween_callback(key.queue_free)


## Крышка коробки пиццы захлопывается: всё рядом поймано, удар по крышке достаёт пойманных.
func _close_lid(f: Food) -> bool:
	if not f.close_lid(Cfg.PIZZA_LID_TIME):
		return false
	_add_shake(10.0)
	_play("lid")
	var n := 0
	for c in roaches():
		if c.alt < 0.3 and (f.carriers.has(c) or c.global_position.distance_to(f.global_position) <= f.radius + 20.0):
			c.trap(f)
			n += 1
	_popup(f.global_position + Vector2(0, -110), "Крышка! Попались: %d" % n if n > 0 else "Хлоп!", Color(1, 0.85, 0.5))
	return true


## Клик по упавшей вилке — она возвращается в лапшу.
func _try_fork(p: Vector2) -> bool:
	if _fallen_fork == null or not is_instance_valid(_fallen_fork):
		return false
	if p.distance_to(_fallen_fork.global_position) > 75.0:
		return false
	if _fork_food == null or not is_instance_valid(_fork_food) or _fork_food.gone or _fork_food.fork != null:
		return false
	var s := _fallen_fork
	var f := _fork_food
	_fallen_fork = null
	_fork_food = null
	var dest := f.to_global(Cfg.FORK_OFFSET)
	var tw := s.create_tween().set_parallel()
	tw.tween_property(s, "global_position", dest, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "rotation", f.rotation, 0.35)
	tw.chain().tween_callback(func():
		if is_instance_valid(f) and not f.gone:
			f.put_fork(s)
		else:
			s.queue_free())
	score += Cfg.FORK_BACK_BONUS
	_popup(dest + Vector2(0, -60), "Вилка на месте! +%d" % Cfg.FORK_BACK_BONUS, Color(0.7, 1, 0.7))
	_update_hud()
	return true


func _pulse_fork() -> void:
	if _fallen_fork and is_instance_valid(_fallen_fork):
		var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
		_fallen_fork.modulate = Color(1, 1, 1).lerp(Color(1.6, 1.5, 0.9), k)


# ------------------------------------------------------------ кофе

func _make_puddle(c: Vector2) -> void:
	c = c.clamp(Vector2(100, 120), Vector2(Cfg.VIEW.x - 60, Cfg.TABLE_NEAR_EDGE - 40))
	var rx := 155.0
	var ry := 85.0
	var node := Node2D.new()
	node.position = c
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	var ph1 := randf() * TAU
	var ph2 := randf() * TAU
	for k in 48:
		var a := TAU * k / 48.0
		var r := 1.0 + 0.12 * sin(a * 3.0 + ph1) + 0.07 * sin(a * 5.0 + ph2)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry) * r)
	poly.polygon = pts
	poly.color = Color(0.3, 0.16, 0.06, 0.62)
	node.add_child(poly)
	var shine := Polygon2D.new()
	var sp := PackedVector2Array()
	for k in 20:
		var a := TAU * k / 20.0
		sp.append(Vector2(cos(a) * rx * 0.35 - rx * 0.25, sin(a) * ry * 0.18 - ry * 0.35))
	shine.polygon = sp
	shine.color = Color(1, 0.9, 0.7, 0.18)
	node.add_child(shine)
	decals_layer.add_child(node)
	node.scale = Vector2.ONE * 0.15
	node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.7).set_ease(Tween.EASE_OUT)
	_puddles.append({"node": node, "c": c, "rx": rx, "ry": ry, "t": Cfg.PUDDLE_TIME})


func _tick_puddles(delta: float) -> void:
	for pd in _puddles.duplicate():
		pd.t -= delta
		var n: Node2D = pd.node
		if pd.t < 6.0:
			# высыхает: сжимается и бледнеет
			n.scale = Vector2.ONE * lerpf(0.4, 1.0, maxf(pd.t, 0.0) / 6.0)
			n.modulate.a = maxf(pd.t, 0.0) / 6.0
		if pd.t <= 0.0:
			n.queue_free()
			_puddles.erase(pd)


func in_puddle(p: Vector2) -> bool:
	for pd in _puddles:
		var k: float = pd.node.scale.x
		if k < 0.3:
			continue
		var q: Vector2 = p - pd.c
		var e: float = pow(q.x / (pd.rx * k), 2) + pow(q.y / (pd.ry * k), 2)
		if e <= 1.0:
			return true
	return false


# ------------------------------------------------------------ эффекты

## Вспышка удара: звезда и разлёт линий, как на раскадровке.
func _impact(at: Vector2, r: float) -> void:
	var star := Polygon2D.new()
	var pts := PackedVector2Array()
	var n := 14
	for i in n * 2:
		var a := TAU * i / (n * 2)
		var rad := r * (1.25 if i % 2 == 0 else 0.75) * randf_range(0.85, 1.15)
		pts.append(Vector2.from_angle(a) * rad)
	star.polygon = pts
	star.color = Color(1, 1, 1, 0.85)
	var outline := Line2D.new()
	outline.points = pts
	outline.closed = true
	outline.width = 3.0
	outline.default_color = Color(0.1, 0.05, 0.05)
	star.add_child(outline)
	star.position = at
	star.rotation = randf() * TAU
	star.scale = Vector2.ONE * 0.5
	fx_layer.add_child(star)
	var tw := star.create_tween().set_parallel()
	tw.tween_property(star, "scale", Vector2.ONE * 1.1, 0.12)
	tw.tween_property(star, "modulate:a", 0.0, 0.18).set_delay(0.06)
	tw.chain().tween_callback(star.queue_free)


## Удар по лапше: вилка вылетает, лапша разлетается по столу.
func _noodle_splash(f: Food, p: Vector2) -> void:
	_add_shake(11.0)
	score = maxi(score - Cfg.NOODLE_PENALTY, 0)
	_popup(f.global_position + Vector2(0, -80), "Лапша по всему столу! -%d" % Cfg.NOODLE_PENALTY, Color(1, 0.8, 0.3))
	_play("splash")
	var c := f.global_position
	# клякса лапши вокруг лотка
	var sc := Sprite2D.new()
	sc.texture = Cfg.tex("noodles_scatter.png")
	sc.position = c + Vector2(randf_range(-20, 20), randf_range(-10, 10))
	sc.rotation = randf() * TAU
	sc.scale = Vector2.ONE * 0.2
	decals_layer.add_child(sc)
	var tw := sc.create_tween()
	tw.tween_property(sc, "scale", Vector2.ONE * 0.55, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_interval(9.0)
	tw.tween_property(sc, "modulate:a", 0.0, 2.0)
	tw.tween_callback(sc.queue_free)
	# отдельные лапшины разлетаются
	for i in 8:
		var bit := Sprite2D.new()
		bit.texture = Cfg.tex("noodle_bit_%d.png" % (i % 6 + 1))
		bit.scale = Vector2.ONE * randf_range(0.45, 0.7)
		bit.position = c
		bit.rotation = randf() * TAU
		decals_layer.add_child(bit)
		var dir := Vector2.from_angle(randf() * TAU)
		var dest := (c + dir * randf_range(110, 260)).clamp(Vector2(20, 20), Vector2(Cfg.VIEW.x - 20, Cfg.TABLE_NEAR_EDGE))
		var bt := bit.create_tween().set_parallel()
		bt.tween_property(bit, "position", dest, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		bt.tween_property(bit, "rotation", bit.rotation + randf_range(-6, 6), 0.35)
		bt.chain().tween_interval(10.0)
		bt.chain().tween_property(bit, "modulate:a", 0.0, 2.0)
		bt.chain().tween_callback(bit.queue_free)
	# вилка вылетает и падает на стол рядом — её можно вернуть кликом
	var fork := f.pop_fork()
	if fork:
		decals_layer.add_child(fork)
		var away := (fork.global_position - p).normalized()
		if away.length() < 0.1:
			away = Vector2(1, -1).normalized()
		var land := fork.global_position
		for k in 24:   # ищем свободное место на столе: не на еду, кружку и компьютер
			var dir := away.rotated(randf_range(-1.2, 1.2)) if k < 12 else Vector2.from_angle(randf() * TAU)
			land = (fork.global_position + dir * randf_range(180, 300)).clamp(Vector2(60, 60), Vector2(Cfg.VIEW.x - 60, Cfg.TABLE_NEAR_EDGE - 40))
			var ok := not blocked_at(land, Vector2(40, 40))
			for other in foods:
				if land.distance_to(other.global_position) < other.radius + 90.0:
					ok = false
			for b in breakables:
				if land.distance_to(b.global_position) < b.radius + 60.0:
					ok = false
			if ok:
				break
		var ft := fork.create_tween()
		ft.set_parallel()
		ft.tween_property(fork, "global_position", land, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ft.tween_property(fork, "rotation", fork.rotation + randf_range(8, 14) * (1 if randf() < 0.5 else -1), 0.5)
		# «подлёт» — вилка увеличивается в воздухе и опускается на стол
		ft.tween_property(fork, "scale", fork.scale * 1.5, 0.22).set_ease(Tween.EASE_OUT)
		ft.chain().tween_property(fork, "scale", fork.scale, 0.25).set_ease(Tween.EASE_IN)
		_fallen_fork = fork
		_fork_food = f


func _splat(at: Vector2, s: float) -> void:
	var sp := Sprite2D.new()
	sp.texture = Cfg.tex("splat.png")
	sp.position = at
	sp.rotation = randf() * TAU
	sp.scale = Vector2.ONE * s * randf_range(0.5, 0.65)
	sp.modulate = Color(1, 1, 1, 0.7)
	decals_layer.add_child(sp)
	var tw := sp.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(sp, "modulate:a", 0.0, 2.0)
	tw.tween_callback(sp.queue_free)


func _popup(at: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.size = Vector2(360, 80)
	l.position = (at - Vector2(180, 40)).clamp(Vector2(0, 0), Cfg.VIEW - Vector2(360, 80))
	fx_layer.add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 70.0, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


## Крупная надпись с «пружинкой»: ДВОЙНОЙ!, ПОСЛЕДНИЙ!
func _big_text(text: String, at: Vector2, color: Color, size := 48) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 14)
	l.size = Vector2(700, size * 1.5)
	l.pivot_offset = l.size / 2.0
	l.position = (at - l.size / 2.0).clamp(Vector2(-100, 0), Cfg.VIEW - l.size + Vector2(100, 0))
	l.rotation = randf_range(-0.08, 0.08)
	l.scale = Vector2.ONE * 2.4
	fx_layer.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------ события

## Тараканы утащили блюдо за край стола.
func _on_food_lost(f: Food) -> void:
	foods.erase(f)
	var at := f.global_position.clamp(Vector2(140, 80), Cfg.VIEW - Vector2(140, 120))
	_popup(at, "Утащили!", Color(1, 0.45, 0.35))
	_add_shake(8.0)
	_play("escape")
	if f.id == "noodles":
		_pc_say("Ошибка 404:\nлапша\nне найдена.", 4.0)
	else:
		_pc_say("ВНИМАНИЕ!\nТАРАКАНЫ\nУКРАЛИ УЖИН!", 4.0)
	_update_hud()
	if mode == Mode.PLAY and foods.is_empty():
		end_round(false)


func _update_hud() -> void:
	hud.set_score(score, best, combo_mult())
	hud.set_food(food_left(), food_max())


# ------------------------------------------------------------ рекорд и звук

func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best = cf.get_value("score", "best", 0)


func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("score", "best", best)
	cf.save(SAVE_PATH)


## Звуки необязательны: положите res://assets/sounds/<имя>.ogg (или .wav/.mp3).
## Имена: slap, splat, break, escape, win, lose, beep, wave_start, rush, splash, boss, lid, prop.
func _play(name: String) -> bool:
	if not _sfx.has(name):
		_sfx[name] = null
		for ext in ["ogg", "wav", "mp3"]:
			var path := "%s%s.%s" % [Cfg.SOUNDS, name, ext]
			if ResourceLoader.exists(path):
				_sfx[name] = load(path)
				break
	var stream: AudioStream = _sfx[name]
	if stream == null:
		return false
	for pl in _players:
		if not pl.playing:
			pl.stream = stream
			pl.pitch_scale = randf_range(0.92, 1.08)
			pl.play()
			return true
	return true

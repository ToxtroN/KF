class_name Food
extends Node2D
## Блюдо на столе. Тараканы подлезают под него и тащат к краю стола, как муравьи.
## Чем больше тараканов под блюдом, тем быстрее оно едет. Уехало за край — потеряно.

signal lost(food: Food)

var id := ""
var weight := 3                   # сколько тараканов нужно для полной скорости (с учётом волны и улучшений)
var base_weight := 3
var light := false                # волна «Последний кусочек»: еда лёгкая
var lid := false                  # у коробки пиццы есть крышка
var radius := 80.0
var sprite: Sprite2D
var pips: Node2D
var carriers: Array = []          # тараканы под блюдом
var drag_dir := Vector2.ZERO
var moving := false
var gone := false
var game: Node
var fork: Sprite2D                # вилка в лапше (если есть)
var splashable := false

var _slots: Array[Vector2] = []   # точки под блюдом (локально)
var _slot_owner: Array = []
var _shake_t := 0.0
var _last_n := -1
var _lid_t := 0.0
var _lid_cd := 0.0
var _lid_sprite: Sprite2D
var _full_tex: Texture2D
var _base_tex: Texture2D


func setup(data: Dictionary, g: Node) -> void:
	game = g
	position = data.pos
	rotation = data.get("rot", 0.0)
	id = data.get("id", "")
	base_weight = data.get("weight", 3)
	weight = base_weight
	lid = data.get("lid", false)
	radius = data.get("radius", 80.0)
	sprite = Sprite2D.new()
	sprite.texture = Cfg.tex(data.tex)
	add_child(sprite)
	if sprite.texture and data.has("w"):
		sprite.scale = Vector2.ONE * (float(data.w) / sprite.texture.get_width())
	if data.get("fork", false):
		splashable = true
		fork = Sprite2D.new()
		fork.texture = Cfg.tex("fork.png")
		if fork.texture:
			fork.scale = Vector2.ONE * (float(Cfg.FORK_W) / fork.texture.get_width())
		fork.position = Cfg.FORK_OFFSET
		add_child(fork)
	# места для тараканов — по краю блюда: таракан наполовину под ним, наполовину торчит
	var half := Vector2(radius, radius)
	if sprite.texture:
		half = sprite.texture.get_size() * sprite.scale * 0.5
	half *= Cfg.SLOT_EDGE
	var n := weight + 2
	for i in n:
		var a := TAU * i / n + 0.4
		var d := Vector2(cos(a), sin(a))
		# точка на границе прямоугольника блюда в направлении d
		var k := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
		_slots.append(d * k)
		_slot_owner.append(null)
	z_index = 1   # бегущие мимо тараканы проползают под блюдом, а не по нему
	pips = Node2D.new()
	pips.top_level = true
	pips.z_as_relative = false
	pips.z_index = 6
	add_child(pips)
	_build_pips()
	_refresh()


func _build_pips() -> void:
	for c in pips.get_children():
		c.free()
	var size := 12.0
	var gap := 6.0
	var total := weight * size + (weight - 1) * gap
	for i in weight:
		var p := Polygon2D.new()
		var pts := PackedVector2Array()
		for k in 12:
			var a := TAU * k / 12.0
			pts.append(Vector2(cos(a), sin(a)) * size * 0.5)
		p.polygon = pts
		p.position = Vector2(-total * 0.5 + size * 0.5 + i * (size + gap), 0)
		pips.add_child(p)


func _pips_pos() -> Vector2:
	var top := radius + 18.0
	if sprite.texture:
		top = sprite.texture.get_height() * sprite.scale.y * 0.5 + 14.0
	return global_position + Vector2(0, -top)


# ---------- места под блюдом ----------

## Таракан бронирует место. Возвращает индекс или -1, если всё занято.
func claim_slot(roach: Node) -> int:
	if lid_closed():
		return -1
	var i := _slot_owner.find(roach)
	if i >= 0:
		return i
	var best := -1
	var best_d := INF
	for k in _slots.size():
		if _slot_owner[k] == null or not is_instance_valid(_slot_owner[k]):
			if game.blocked_at(to_global(_slots[k]), Vector2(16, 16)):
				continue
			var d: float = roach.global_position.distance_to(to_global(_slots[k]))
			if d < best_d:
				best_d = d
				best = k
	if best >= 0:
		_slot_owner[best] = roach
	return best


func release_slot(roach: Node) -> void:
	var i := _slot_owner.find(roach)
	if i >= 0:
		_slot_owner[i] = null
	carriers.erase(roach)
	_refresh()


func has_free_slot() -> bool:
	if lid_closed():
		return false
	for o in _slot_owner:
		if o == null or not is_instance_valid(o):
			return true
	return false


func slot_global(i: int) -> Vector2:
	return to_global(_slots[i])


func slot_local(i: int) -> Vector2:
	return _slots[i]


func attach(roach: Node) -> void:
	if not carriers.has(roach):
		carriers.append(roach)
	_refresh()


# ---------- движение ----------

func _process(delta: float) -> void:
	if gone:
		return
	carriers = carriers.filter(func(r): return is_instance_valid(r) and r.is_alive())
	_lid_cd -= delta
	if _lid_t > 0.0:
		_lid_t -= delta
		if _lid_t <= 0.0:
			_open_lid()
	# сила носильщиков: босс тянет за троих
	var n := 0
	for r in carriers:
		n += r.power()
	var need := maxi(1, ceili(weight * Cfg.MIN_CARRY_PART))
	moving = n >= need and not lid_closed()
	if moving:
		var pad := _half() * 0.85
		var exit: Vector2 = game.exit_point(global_position, radius + 80.0, pad)
		# тащат в обход компьютера: сначала к углу препятствия, потом к краю
		var way: Vector2 = game.route(global_position, exit, pad)
		var want := (way - global_position).normalized()
		drag_dir = want if drag_dir == Vector2.ZERO else drag_dir.lerp(want, delta * 2.0).normalized()
		var mult := minf(float(n) / weight, Cfg.DRAG_MAX_MULT)
		if light:
			mult *= 1.5
		if game.in_puddle(global_position):
			mult *= Cfg.PUDDLE_SLOW   # по разлитому кофе тащить тяжело
		# муравьиная походка: блюдо едет рывками и чуть покачивается
		var t := Time.get_ticks_msec() / 1000.0
		var pulse := 0.6 + 0.4 * absf(sin(t * 7.0))
		global_position += drag_dir * Cfg.DRAG_SPEED * mult * pulse * delta
		global_position = game.push_out(global_position, pad)
		sprite.rotation = sin(t * 5.0) * 0.03
		if _offscreen():
			_lose()
	elif n > 0 and not lid_closed():
		# сил не хватает — блюдо только подрагивает
		_shake_t += delta
		sprite.position = Vector2(sin(_shake_t * 40.0), cos(_shake_t * 33.0)) * 1.5
		sprite.rotation = 0.0
	else:
		sprite.position = Vector2.ZERO
		sprite.rotation = 0.0
	pips.global_position = _pips_pos()
	if n != _last_n:
		_last_n = n
		_refresh()


## Волна «Последний кусочек»: еда лёгкая — тащит меньшая толпа и быстрее.
func set_light(is_light: bool) -> void:
	light = is_light
	weight = maxi(2, base_weight - (2 if light else 0))
	_build_pips()
	_refresh()


func contains(p: Vector2) -> bool:
	var lp := to_local(p)
	var h := _half()
	return absf(lp.x) <= h.x and absf(lp.y) <= h.y


# ---------- крышка коробки пиццы ----------

func lid_closed() -> bool:
	return _lid_t > 0.0


## Захлопнуть крышку на t секунд. Возвращает false, если крышки нет или она уже закрыта.
func close_lid(t: float) -> bool:
	if not lid or lid_closed() or _lid_cd > 0.0 or sprite.texture == null:
		return false
	_lid_cd = t + 2.5
	if _lid_sprite == null:
		_make_lid()
	_lid_t = t
	sprite.texture = _base_tex
	_lid_sprite.visible = true
	_lid_sprite.scale = Vector2(1, -1)
	create_tween().tween_property(_lid_sprite, "scale:y", 1.0, 0.12).set_ease(Tween.EASE_IN)
	pips.visible = false
	return true


func _open_lid() -> void:
	var tw := create_tween()
	tw.tween_property(_lid_sprite, "scale:y", -1.0, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_lid_sprite.visible = false
		sprite.texture = _full_tex)
	for c in get_children():
		if c is Roach and c.trapped_by == self:
			c.release()
	_refresh()


## Картинки «закрытая крышка» и «коробка без крышки» собираются из pizza_box.png.
func _make_lid() -> void:
	_full_tex = sprite.texture
	var img := _full_tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var hinge := int(h * 0.34)
	# крышка на картинке открыта вверх: отражаем её вниз, на саму коробку
	var lid_img := img.get_region(Rect2i(int(w * 0.06), int(h * 0.055), int(w * 0.88), hinge - int(h * 0.055)))
	lid_img.flip_y()
	lid_img.resize(int(w * 0.79), int(h * 0.62))
	var closed := Image.create(w, h, false, Image.FORMAT_RGBA8)
	closed.blit_rect(lid_img, Rect2i(Vector2i.ZERO, lid_img.get_size()), Vector2i(int(w * 0.15), hinge))
	var base := img.duplicate()
	base.fill_rect(Rect2i(0, 0, w, hinge - 6), Color(0, 0, 0, 0))
	_base_tex = ImageTexture.create_from_image(base)
	_lid_sprite = Sprite2D.new()
	_lid_sprite.texture = ImageTexture.create_from_image(closed)
	_lid_sprite.centered = false
	_lid_sprite.offset = Vector2(-w * 0.5, -hinge)
	_lid_sprite.position = Vector2(0, hinge - h * 0.5)
	_lid_sprite.visible = false
	sprite.add_child(_lid_sprite)


func _half() -> Vector2:
	if sprite.texture:
		return sprite.texture.get_size() * sprite.scale * 0.5
	return Vector2(radius, radius)


## Попал ли удар по лапше или вилке.
func splash_hit(p: Vector2) -> bool:
	if not splashable or gone:
		return false
	var lp := to_local(p)
	var half := sprite.texture.get_size() * sprite.scale * 0.5 if sprite.texture else Vector2(radius, radius)
	if absf(lp.x) <= half.x and absf(lp.y) <= half.y:
		return true
	return fork != null and lp.distance_to(fork.position) <= Cfg.FORK_W * 0.4


## Вилка вылетает из лапши. Возвращает спрайт вилки (уже без родителя) или null.
func pop_fork() -> Sprite2D:
	if fork == null:
		return null
	var s := fork
	fork = null
	s.set_meta("home_scale", s.scale)
	var gp := s.global_position
	var gr := s.global_rotation
	remove_child(s)
	s.global_position = gp
	s.rotation = gr
	return s


## Вернуть вилку в лапшу (кликом по упавшей вилке).
func put_fork(s: Sprite2D) -> void:
	s.reparent(self, true)
	s.position = Cfg.FORK_OFFSET
	s.rotation = 0.0
	s.scale = s.get_meta("home_scale", s.scale)
	s.modulate = Color.WHITE
	fork = s


func _offscreen() -> bool:
	var m := radius * 1.3
	var p := global_position
	return p.x < -m or p.x > Cfg.VIEW.x + m or p.y < -m


func _lose() -> void:
	gone = true
	lost.emit(self)
	for r in carriers:
		if is_instance_valid(r):
			r.queue_free()
	queue_free()


func _refresh() -> void:
	var n := 0
	for r in carriers:
		if is_instance_valid(r):
			n += r.power()
	for i in pips.get_child_count():
		var p: Polygon2D = pips.get_child(i)
		p.color = Color(0.9, 0.25, 0.15) if i < n else Color(1, 1, 1, 0.35)
	pips.visible = n > 0 and not lid_closed()

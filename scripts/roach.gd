class_name Roach
extends Node2D
## Таракан: бежит к блюду, подлезает под него и вместе с остальными тащит к краю стола.

enum State { TO_FOOD, CARRY, STUNNED, FLEE, WANDER, DEAD, STUCK, TRAPPED }

var type := "normal"
var data: Dictionary
var game: Node                    # main.gd: pick_food(), exit_point(), roach_layer
var state := State.TO_FOOD
var hp := 1
var speed := 100.0
var radius := 24.0
var heading := 0.0
var target: Food
var slot := -1

var body: AnimatedSprite2D
var shadow: AnimatedSprite2D
var wings: Array[Polygon2D] = []
var _state_t := 0.0
var _wiggle_seed := 0.0
var _pause_t := 0.0
var _panic := 1.0
var _scared_t := 0.0
var _goal := Vector2.ZERO
var alt := 0.0                    # высота полёта (летающие), 0 = на столе
var _waypoint := Vector2.ZERO
var _route_t := 0.0
var _stuck_t := 0.0               # сколько времени упирается под блюдом, а оно не едет
var _off_t := 0.0                 # сколько времени за краем экрана (страховка от застревания)
var max_hp := 1
var trapped_by: Food = null       # пойман под крышкой коробки пиццы
var flung := false                # большой таракан улетел от удара (без кляксы)
var panic := false                # босс в панике
var _in_puddle := false
var _summon_t := 0.0              # босс: до вызова подмоги


func setup(t: String, start: Vector2, g: Node) -> void:
	type = t
	data = Cfg.ROACHES[t]
	game = g
	position = start
	hp = data.hp
	max_hp = hp
	_summon_t = Cfg.BOSS_SUMMON.x
	speed = data.speed * randf_range(0.9, 1.1)
	radius = data.radius
	_wiggle_seed = randf() * 100.0
	add_to_group("roaches")
	var frames := Cfg.roach_frames()
	var off := Vector2(0, -Cfg.ROACH_CELL.y * 0.05)

	shadow = AnimatedSprite2D.new()
	shadow.sprite_frames = frames
	shadow.offset = off
	shadow.modulate = Color(0, 0, 0, 0.3)
	shadow.scale = Vector2.ONE * data.scale
	add_child(shadow)

	body = AnimatedSprite2D.new()
	body.sprite_frames = frames
	body.offset = off
	body.scale = Vector2.ONE * data.scale
	body.modulate = data.tint
	add_child(body)

	if data.get("wings", false):
		_make_wings()
		alt = 1.0
	heading = (Cfg.VIEW * 0.5 - position).angle()
	rotation = heading + PI / 2.0
	_play(data.move)
	_retarget()


func _make_wings() -> void:
	for side in [-1.0, 1.0]:
		var w := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 16:
			var a := TAU * i / 16.0
			pts.append(Vector2(cos(a) * 26.0, sin(a) * 52.0))
		w.polygon = pts
		w.color = Color(0.85, 0.9, 1.0, 0.45)
		w.position = Vector2(side * 24.0, 0)
		w.rotation = side * 0.35
		w.set_meta("side", side)
		body.add_child(w)
		wings.append(w)


func _play(anim: String) -> void:
	if body.animation != anim or not body.is_playing():
		body.play(anim)
		shadow.play(anim)


func is_alive() -> bool:
	return state != State.DEAD


func is_carrying() -> bool:
	return state == State.CARRY


func hit_test(p: Vector2, r: float) -> bool:
	if not is_alive():
		return false
	# под захлопнутой крышкой: удар по крышке достаёт всех пойманных
	if trapped_by and is_instance_valid(trapped_by) and trapped_by.lid_closed():
		if trapped_by.contains(p):
			return true
	return p.distance_to(global_position) <= r + radius


## Сколько «тараканьих сил» он даёт, когда тащит еду.
func power() -> int:
	return Cfg.BOSS_POWER if type == "boss" else 1


## Возвращает true, если таракан погиб от этого удара. from — куда пришёлся удар.
func damage(from := Vector2.INF) -> bool:
	hp -= 1
	if hp > 0:
		body.modulate = Color(1.6, 0.6, 0.6)
		create_tween().tween_property(body, "modulate", data.tint, 0.35)
		if type == "boss":
			_boss_hurt()
			return false
		trapped_by = null
		_detach()
		state = State.STUNNED
		_state_t = 0.35
		_panic = 1.5
		_play("idle")
		if type == "big":
			# первый удар — большой таракан крутится волчком
			_state_t = 0.6
			var tw := create_tween()
			tw.tween_property(body, "rotation", TAU * 2.0 * (1.0 if randf() < 0.5 else -1.0), 0.55).from(0.0).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func(): body.rotation = 0.0)
		return false
	_die(from)
	return true


func _boss_hurt() -> void:
	_detach()
	if not panic and hp <= ceili(max_hp * Cfg.BOSS_PANIC_HP):
		panic = true
		speed *= 1.9
		_summon_t = minf(_summon_t, 1.0)
		game.boss_panic(self)
	if panic:
		# в панике король мечется по столу
		state = State.FLEE
		_state_t = randf_range(0.9, 1.5)
		_scared_t = _state_t
		_goal = game.push_out(Vector2(randf_range(200, Cfg.VIEW.x - 200), randf_range(180, Cfg.TABLE_NEAR_EDGE - 90)), _pad())
	else:
		state = State.STUNNED
		_state_t = 0.25
		_play("idle")


## Промах рядом: таракан пугается, вылезает из-под блюда и отбегает.
## force — испуг без шансов (клавиатура).
func scare(from: Vector2, force := false) -> void:
	if not is_alive() or state == State.TRAPPED or state == State.STUCK:
		return
	if type == "boss" and not force:
		return
	# часть носильщиков держится за еду и не бросает её
	if state == State.CARRY and not force and randf() < 0.4:
		return
	_detach()
	state = State.FLEE
	_state_t = randf_range(0.8, 1.3)
	_scared_t = _state_t
	_panic = 1.7
	_pause_t = -1.0
	var away := (global_position - from)
	if away.length() < 1.0:
		away = Vector2.from_angle(randf() * TAU)
	_goal = game.push_out(global_position + away.normalized() * 260.0, _pad())


## Вылезти из-под блюда обратно на стол.
func _detach() -> void:
	if target and is_instance_valid(target):
		target.release_slot(self)
	slot = -1
	if get_parent() != game.roach_layer:
		reparent(game.roach_layer, true)
		heading = rotation - PI / 2.0
	z_index = 0


## Захлопнулась крышка коробки — пойман под ней.
func trap(f: Food) -> void:
	if not is_alive():
		return
	trapped_by = f
	if not (state == State.CARRY and target == f):
		_detach()
		reparent(f, true)
		f.move_child(self, 0)
	state = State.TRAPPED
	_play("idle")
	body.speed_scale = 3.0   # отчаянно барахтается


## Крышка открылась: носильщики продолжают тащить, остальные оглушены и разбегаются.
func release() -> void:
	if not is_alive():
		return
	var f := trapped_by
	trapped_by = null
	if f and target == f and f.carriers.has(self):
		state = State.CARRY
		return
	_detach()
	state = State.STUNNED
	_state_t = 0.8
	_panic = 1.6


func _stick() -> void:
	_detach()
	state = State.STUCK
	_state_t = Cfg.PUDDLE_STUCK_TIME


func _die(from := Vector2.INF) -> void:
	_detach()
	state = State.DEAD
	trapped_by = null
	alt = 0.0
	shadow.visible = false
	remove_from_group("roaches")
	for w in wings:
		w.queue_free()
	wings.clear()
	body.rotation = 0.0
	body.modulate = data.tint
	if type == "big":
		_fling(from)
		return
	body.speed_scale = 1.0
	body.play("die")
	get_parent().move_child(self, 0)   # мёртвые — под живыми
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(self, "modulate:a", 0.0, 1.0)
	tw.tween_callback(queue_free)


## Большой таракан от добивающего удара улетает с экрана кувырком.
func _fling(from: Vector2) -> void:
	flung = true
	var dir := Vector2.from_angle(randf() * TAU)
	if from != Vector2.INF and global_position.distance_to(from) > 1.0:
		dir = (global_position - from).normalized()
	dir = (dir + Vector2(0, -0.9)).normalized()   # от студента — вверх по столу
	z_index = 10
	body.play("run")
	body.speed_scale = 3.0
	var dest := global_position + dir * 760.0
	var s0 := body.scale
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "global_position", dest, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation", rotation + randf_range(10.0, 16.0) * (1.0 if randf() < 0.5 else -1.0), 0.95)
	tw.tween_property(body, "scale", s0 * 1.9, 0.35).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(body, "scale", s0 * 0.5, 0.6).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.3).set_delay(0.3)
	tw.chain().tween_callback(queue_free)


func _retarget() -> void:
	if target and is_instance_valid(target):
		target.release_slot(self)
	target = game.pick_food(global_position)
	slot = -1
	if target:
		slot = target.claim_slot(self)
		if slot < 0:
			target = null
	if target == null:
		# все места заняты — побродить рядом и попробовать снова
		state = State.WANDER
		_state_t = randf_range(1.0, 2.0)
		_goal = game.push_out(Vector2(randf_range(150, Cfg.VIEW.x - 150), randf_range(120, Cfg.TABLE_NEAR_EDGE - 80)), _pad())
	else:
		state = State.TO_FOOD


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	_scared_t -= delta
	# страховка: застрял за краем экрана — возвращаем на стол у ближайшего края
	var gp := global_position
	if state != State.CARRY and state != State.TRAPPED and (gp.x < -20 or gp.x > Cfg.VIEW.x + 20 or gp.y < -20):
		_off_t += delta
		if _off_t > 6.0:
			_off_t = 0.0
			global_position = game.push_out(gp.clamp(Vector2(30, 30), Cfg.VIEW - Vector2(30, Cfg.VIEW.y - Cfg.TABLE_NEAR_EDGE + 30)), _pad())
			_route_t = 0.0
			_retarget()
	else:
		_off_t = 0.0
	# кофейная лужа: скользко; при входе можно застрять
	var in_p: bool = alt < 0.3 and state != State.CARRY and state != State.TRAPPED and game.in_puddle(global_position)
	if in_p and not _in_puddle and type != "boss" and (state == State.TO_FOOD or state == State.WANDER or state == State.FLEE) and randf() < Cfg.PUDDLE_STUCK:
		_stick()
	_in_puddle = in_p
	if type == "boss":
		_summon_t -= delta
		if _summon_t <= 0.0:
			_summon_t = Cfg.BOSS_SUMMON.y if panic else Cfg.BOSS_SUMMON.x
			game.boss_summon(self)
	match state:
		State.TRAPPED:
			pass
		State.STUCK:
			# лапки скользят по кофе, таракан крутится на месте
			_state_t -= delta
			_play("run")
			body.speed_scale = 2.4
			var t := Time.get_ticks_msec() / 1000.0 + _wiggle_seed
			rotation = heading + PI / 2.0 + sin(t * 22.0) * 0.4
			if _state_t <= 0.0:
				_retarget()
		State.STUNNED:
			_state_t -= delta
			if _state_t <= 0.0:
				_retarget()
		State.FLEE:
			_state_t -= delta
			_steer_to(_goal, delta)
			if _state_t <= 0.0:
				_retarget()
		State.WANDER:
			_state_t -= delta
			_steer_to(_goal, delta, 0.6)
			if _state_t <= 0.0:
				_retarget()
		State.TO_FOOD:
			if target == null or not is_instance_valid(target) or target.gone:
				_retarget()
				return
			var p := target.slot_global(slot)
			if game.blocked_at(p, _pad()):
				_retarget()   # место упёрлось в компьютер — ищем другое
				return
			var dist := global_position.distance_to(p)
			if wings.size() > 0:
				alt = clampf(dist / 220.0, 0.0, 1.0)
			if dist <= 16.0:
				_attach()
			else:
				_steer_to(p, delta)
		State.CARRY:
			_carry(delta)
	_update_visuals()


## Залезаем под блюдо: становимся дочерним узлом еды, под её спрайтом.
func _attach() -> void:
	state = State.CARRY
	alt = 0.0
	reparent(target, true)
	target.move_child(self, 0)
	position = target.slot_local(slot)
	target.attach(self)



func _carry(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.lid_closed():
		return
	# смотрим туда, куда тащим блюдо; если блюдо стоит — к его центру
	var dir: Vector2 = target.drag_dir if target.moving else -position
	var want := dir.angle() + PI / 2.0 - target.rotation
	rotation = lerp_angle(rotation, want, 0.15)
	if target.moving:
		_play(data.move)
		body.speed_scale = 0.8
	else:
		_play("idle")
		body.speed_scale = 1.6   # упирается изо всех сил
	shadow.speed_scale = body.speed_scale
	# сил не хватает слишком долго — вылезает и бежит за подмогой (потом вернётся)
	_stuck_t = 0.0 if target.moving else _stuck_t + _delta
	if _stuck_t > Cfg.GIVE_UP_TIME:
		_stuck_t = 0.0
		_detach()
		state = State.WANDER
		_state_t = randf_range(1.2, 2.2)
		_goal = game.push_out(Vector2(randf_range(250, Cfg.VIEW.x - 250), randf_range(200, Cfg.TABLE_NEAR_EDGE - 100)), _pad())


func _steer_to(p: Vector2, delta: float, mult := 1.0) -> void:
	# быстрые бегут рывками: пауза — рывок (испуганные не останавливаются)
	if type == "fast" and _scared_t <= 0.0:
		_pause_t -= delta
		if _pause_t < -1.2:
			_pause_t = randf_range(0.15, 0.35)
		if _pause_t > 0.0:
			_play("idle")
			return
	_play("run" if _scared_t > 0.0 or _panic > 1.2 or panic else data.move)
	var flying := alt > 0.3
	# обход компьютера: путь пересчитываем пару раз в секунду
	if not flying:
		_route_t -= delta
		if _route_t <= 0.0 or global_position.distance_to(_waypoint) < 14.0:
			_route_t = 0.8
			_waypoint = game.route(global_position, p, _pad())
		p = _waypoint
	var t := Time.get_ticks_msec() / 1000.0 + _wiggle_seed
	var want := (p - global_position).angle()
	var wiggle := sin(t * 3.1) * 0.6 + sin(t * 7.3) * 0.25
	if _in_puddle:
		wiggle = sin(t * 9.0) * 1.4   # скользит и виляет на кофе
	if wings.size() > 0:
		wiggle = sin(t * 2.0) * 0.9
	if global_position.distance_to(p) < 80.0:
		wiggle *= 0.15   # у цели идёт ровнее
	want += wiggle * 0.5
	var dist := global_position.distance_to(p)
	var turn := 6.0 if dist > 70.0 else 18.0   # у цели — резко, чтобы не кружить
	heading = lerp_angle(heading, want, clampf(delta * turn, 0.0, 1.0))
	mult *= _speed_mod()
	var step := speed * mult * _panic * delta
	if dist < 70.0:
		step = minf(step, dist)
	position += Vector2.from_angle(heading) * step
	if not flying:
		var fixed: Vector2 = game.push_out(global_position, _pad())
		if fixed != global_position:
			# упёрся в монитор/клавиатуру — скользим вдоль края
			global_position = fixed
			_route_t = 0.0
	_panic = move_toward(_panic, 1.0, delta * 0.4)
	rotation = heading + PI / 2.0
	var k: float = speed * mult * _panic / data.speed
	body.speed_scale = k
	shadow.speed_scale = k


func _speed_mod() -> float:
	var m := 1.0
	if _in_puddle:
		m *= Cfg.PUDDLE_SLOW
	return m


func _pad() -> Vector2:
	return Vector2.ONE * radius * 0.7


func _update_visuals() -> void:
	if get_parent() == game.roach_layer:
		z_index = 3 if alt > 0.3 else 0   # летящий — над блюдами, ползущий — под ними
	shadow.visible = alt > 0.02
	body.scale = Vector2.ONE * data.scale * (1.0 + 0.35 * alt)
	shadow.global_position = global_position + Vector2(18, 28) * alt
	shadow.frame = body.frame
	var t := Time.get_ticks_msec() / 1000.0
	for w in wings:
		var side: float = w.get_meta("side")
		var flap := absf(sin(t * 40.0 + _wiggle_seed)) if alt > 0.05 else 0.0
		w.scale = Vector2(0.4 + 0.6 * flap, 1.0)
		w.visible = alt > 0.05
		w.rotation = side * (0.35 + 0.4 * flap)

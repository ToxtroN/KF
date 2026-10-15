class_name Hand
extends Node2D
## Рука с мухобойкой. Центр мухобойки всегда под курсором/пальцем,
## рука направлена от «плеча» за нижним краем экрана и сдвигается вдоль своей оси,
## поэтому у дальних краёв стола она выглядит вытянутой, а пустого места под ней нет.

signal slammed(point: Vector2, radius: float)

var sprite: Sprite2D
var shadow: Sprite2D
var _cooldown := 0.0
var _lift := 1.0                  # 1 = мухобойка приподнята, 0 = прижата к столу
var _swinging := false
var _hand_tex: Texture2D
var _warned := false


func _ready() -> void:
	_hand_tex = Cfg.tex(Cfg.HAND_TEXTURE)
	shadow = Sprite2D.new()
	shadow.centered = false
	shadow.modulate = Color(0, 0, 0, 0.3)
	add_child(shadow)
	sprite = Sprite2D.new()
	sprite.centered = false
	add_child(sprite)
	_apply_texture()


func _apply_texture() -> void:
	var t := _hand_tex
	var hp := Cfg.HAND_HEAD_POINT
	sprite.texture = t
	shadow.texture = t
	sprite.offset = -hp
	shadow.offset = -hp
	_check_length(t, hp)


## Подсказка в консоль, если рука короче, чем нужно до края экрана.
func _check_length(t: Texture2D, hp: Vector2) -> void:
	if t == null or _warned:
		return
	var available := (t.get_height() - hp.y) * Cfg.HAND_SCALE
	var need := 0.0
	for c in [Vector2.ZERO, Vector2(Cfg.VIEW.x, 0)]:
		var d: Vector2 = Cfg.SHOULDER - c
		# длина от угла до нижнего края экрана вдоль руки
		var k: float = (Cfg.VIEW.y - c.y) / d.y
		need = maxf(need, d.length() * k)
	if available < need:
		_warned = true
		push_warning("Рука короче нужного: %d px из %d. Удлините спрайт или сдвиньте SHOULDER выше." % [available, need])


func hit_radius() -> float:
	return Cfg.HIT_RADIUS


func aim(p: Vector2) -> void:
	global_position = p
	var dir := p - Cfg.SHOULDER
	rotation = dir.angle() + PI / 2.0


func swing() -> void:
	if _cooldown > 0.0 or _swinging:
		return
	_swinging = true
	_cooldown = Cfg.SWING_COOLDOWN
	var tw := create_tween()
	# короткий замах вверх и резкий шлепок
	tw.tween_property(self, "_lift", 1.25, 0.04)
	tw.tween_property(self, "_lift", 0.0, 0.05).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): slammed.emit(global_position, hit_radius()))
	tw.tween_interval(0.06)
	tw.tween_property(self, "_lift", 1.0, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _swinging = false)


func _process(delta: float) -> void:
	_cooldown -= delta
	var s := Cfg.HAND_SCALE * (1.0 + (Cfg.SWING_UP_SCALE - 1.0) * _lift)
	sprite.scale = Vector2.ONE * s
	shadow.scale = Vector2.ONE * Cfg.HAND_SCALE
	# тень смещаем в мировых координатах (свет сверху-слева), независимо от поворота руки
	shadow.position = (Vector2(14, 20) * _lift).rotated(-rotation)

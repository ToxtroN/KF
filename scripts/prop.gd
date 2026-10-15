class_name Prop
extends Node2D
## Предмет на столе, по которому выгодно промахнуться: клавиатура, мышь, лампа, листки.
## Что именно происходит при ударе — в main.gd (_prop_action). Здесь — зона удара и перезарядка.

var kind := ""
var radius := 50.0
var size := Vector2.ZERO          # прямоугольная зона (клавиатура); иначе круг radius
var hit_offset := Vector2.ZERO
var sprite: Sprite2D
var cooldown := 0.0
var home := Vector2.ZERO


func setup(d: Dictionary) -> void:
	kind = d.prop
	position = d.pos
	home = position
	rotation = d.get("rot", 0.0)
	radius = d.get("radius", 50.0)
	size = d.get("size", Vector2.ZERO)
	hit_offset = d.get("hit_offset", Vector2.ZERO)
	if d.has("tex"):
		sprite = Sprite2D.new()
		sprite.texture = Cfg.tex(d.tex)
		add_child(sprite)
		if sprite.texture and d.has("w"):
			sprite.scale = Vector2.ONE * (float(d.w) / sprite.texture.get_width())


func _process(delta: float) -> void:
	cooldown -= delta


func is_ready() -> bool:
	return cooldown <= 0.0


func hit_center() -> Vector2:
	return global_position + hit_offset


func contains(p: Vector2) -> bool:
	if size != Vector2.ZERO:
		return Rect2(global_position - size * 0.5, size).has_point(p)
	return p.distance_to(hit_center()) <= radius

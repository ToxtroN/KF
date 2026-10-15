class_name Breakable
extends Node2D
## Предмет, который портится при промахе: компьютер, лампа, кружка.
## Если есть свой спрайт <имя>_broken.png — подставится он, иначе рисуется эффект:
## crack — трещины, spill — кружка опрокидывается и разливается кофе.

var radius := 40.0
var penalty := 30
var broken := false
var effect := "crack"
var hit_offset := Vector2.ZERO
var sprite: Sprite2D
var _broken_tex: Texture2D


func setup(data: Dictionary) -> void:
	position = data.pos
	rotation = data.get("rot", 0.0)
	radius = data.get("radius", 40.0)
	penalty = data.get("penalty", 30)
	effect = data.get("effect", "crack")
	hit_offset = data.get("hit_offset", Vector2.ZERO)
	sprite = Sprite2D.new()
	sprite.texture = Cfg.tex(data.tex)
	add_child(sprite)
	if sprite.texture and data.has("w"):
		sprite.scale = Vector2.ONE * (float(data.w) / sprite.texture.get_width())
	_broken_tex = Cfg.tex(String(data.tex).replace(".png", "_broken.png"))


func hit_center() -> Vector2:
	return global_position + hit_offset


func contains(p: Vector2) -> bool:
	return not broken and p.distance_to(hit_center()) <= radius


func smash(at: Vector2) -> void:
	broken = true
	if _broken_tex:
		sprite.texture = _broken_tex
	elif effect == "spill":
		_spill()
	else:
		_cracks(to_local(at))
	var tw := create_tween()
	sprite.scale *= 1.08
	tw.tween_property(sprite, "scale", sprite.scale / 1.08, 0.15)


func _cracks(local_at: Vector2) -> void:
	for i in 7:
		var line := Line2D.new()
		line.width = 3.0
		line.default_color = Color(0.95, 0.95, 1.0, 0.9)
		var p := local_at
		line.add_point(p)
		var dir := Vector2.from_angle(TAU * i / 7.0 + randf_range(-0.3, 0.3))
		for s in 4:
			p += dir.rotated(randf_range(-0.6, 0.6)) * randf_range(15, 35)
			line.add_point(p)
		add_child(line)
	modulate = Color(0.85, 0.85, 0.85)


## Кружка опрокидывается. Саму лужу кофе (игровую механику) создаёт main.gd.
func _spill() -> void:
	create_tween().tween_property(sprite, "rotation", 1.4, 0.2)
	sprite.modulate = Color(0.9, 0.9, 0.9)

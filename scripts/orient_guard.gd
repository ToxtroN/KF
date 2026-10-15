extends CanvasLayer
## Автозагрузка «Orient»: если телефон держат вертикально — затемняем экран,
## просим повернуть телефон и ставим игру на паузу. Повернули — всё продолжается.

var _box: Control
var _icon: Node2D
var _paused_by_us := false
var _t := 0.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = Control.new()
	_box.size = Vector2(1280, 720)
	_box.mouse_filter = Control.MOUSE_FILTER_STOP   # тапы под заставку не проходят
	_box.visible = false
	add_child(_box)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.04)
	bg.size = Vector2(1280, 720)
	_box.add_child(bg)
	_icon = PhoneIcon.new()
	_icon.position = Vector2(640, 250)
	_box.add_child(_icon)
	var l := Label.new()
	l.text = "Поверните телефон"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 450)
	l.size = Vector2(1280, 140)
	l.add_theme_font_size_override("font_size", 96)
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 16)
	_box.add_child(l)
	var s := Label.new()
	s.text = "Игра идёт в альбомной ориентации"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.position = Vector2(0, 580)
	s.size = Vector2(1280, 90)
	s.add_theme_font_size_override("font_size", 56)
	s.add_theme_color_override("font_color", Color(1, 0.95, 0.88))
	_box.add_child(s)


func _process(delta: float) -> void:
	var ws := DisplayServer.window_get_size()
	var portrait := ws.y > ws.x * 1.05
	if portrait != _box.visible:
		_box.visible = portrait
		if portrait:
			if not get_tree().paused:
				get_tree().paused = true
				_paused_by_us = true
		elif _paused_by_us:
			_paused_by_us = false
			get_tree().paused = false
	if portrait:
		# телефон «поворачивается» туда-обратно
		_t += delta
		var k := clampf(sin(_t * 2.2) * 1.4, -1.0, 1.0)
		_icon.rotation = -PI / 4.0 + k * PI / 4.0


class PhoneIcon extends Node2D:
	func _draw() -> void:
		var r := Rect2(-70, -125, 140, 250)
		draw_rect(r, Color(1, 0.95, 0.88))
		draw_rect(r.grow(-12), Color(0.2, 0.45, 0.75))
		draw_circle(Vector2(0, 108), 7, Color(0.3, 0.3, 0.3))
		draw_rect(r, Color.BLACK, false, 6.0)

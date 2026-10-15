extends Node2D
## Главное меню Kitchen Fighter:
## 1) фон и «Нажмите, чтобы продолжить»; 2) сверху падает логотип;
## 3) по экрану начинают ползать тараканы; 4) снизу выезжают кнопки.
## По тараканам в меню можно кликать — они пищат и расплющиваются.

const SPR := "res://assets/sprites/menu/"
static var intro_done := false      # при возврате из игры заставку не повторяем

var logo: Sprite2D
var hint: Label
var buttons: Array[TextureButton] = []
var roaches: Node2D
var settings: SoundPanel
var _stage := 0                      # 0 — ждём нажатия, 1 — меню
var _roach_t := 0.0
var _t := 0.0


func _ready() -> void:
	var bg := Sprite2D.new()
	bg.texture = load(SPR + "menu_bg.png")
	bg.centered = false
	add_child(bg)
	roaches = Node2D.new()
	add_child(roaches)

	logo = Sprite2D.new()
	logo.position = Vector2(640, -260)
	add_child(logo)
	if ResourceLoader.exists(SPR + "logo.png"):
		logo.texture = load(SPR + "logo.png")
	else:
		_text_logo()   # своей картинки названия нет — рисуем надпись

	var ui := CanvasLayer.new()
	add_child(ui)
	hint = Label.new()
	hint.text = "Нажмите, чтобы продолжить"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(1280, 80)
	hint.position = Vector2(0, 600)
	hint.add_theme_font_size_override("font_size", 40)
	hint.add_theme_color_override("font_color", Color(1, 0.92, 0.4))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 14)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hint)

	var ys := [400, 520, 625]
	var files := ["btn_start.png", "btn_music.png", "btn_exit.png"]
	var sizes := [Vector2(330, 150), Vector2(270, 80), Vector2(250, 95)]   # «Начать игру» — крупнее
	for i in 3:
		var b := TextureButton.new()
		b.texture_normal = load(SPR + files[i])
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.size = sizes[i]
		b.pivot_offset = b.size / 2.0
		b.position = Vector2(640 - b.size.x / 2.0, ys[i] - b.size.y / 2.0 + 400)
		b.visible = false
		b.mouse_entered.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE * 1.08, 0.1))
		b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))
		ui.add_child(b)
		buttons.append(b)
	buttons[0].pressed.connect(func():
		_fullscreen()
		get_tree().change_scene_to_file("res://scenes/endless.tscn"))
	buttons[1].pressed.connect(_open_settings)
	buttons[2].pressed.connect(func(): get_tree().quit())
	# на вебе (Yandex Games) выйти нельзя — кнопку «Выход» прячем
	if OS.has_feature("web"):
		buttons.pop_back().queue_free()
	settings = SoundPanel.new()
	ui.add_child(settings)

	Sound.music(self, "music_menu.mp3")   # музыка заставки и меню
	if intro_done:
		_show_menu(true)


## Название игры надписью в стиле кнопок (если нет assets/sprites/menu/logo.png).
func _text_logo() -> void:
	var l := Label.new()
	l.text = "ОБЕД\nПОД УГРОЗОЙ"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 78)
	l.add_theme_constant_override("line_spacing", -18)
	l.add_theme_color_override("font_color", Color(1, 0.88, 0.62))
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02))
	l.add_theme_constant_override("outline_size", 26)
	l.add_theme_color_override("font_shadow_color", Color(1, 0.55, 0.05))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 7)
	l.size = Vector2(900, 220)
	l.position = -l.size / 2.0
	logo.add_child(l)


func _open_settings() -> void:
	settings.open()


## На телефоне в браузере — во весь экран, без адресной строки.
## Браузер разрешает это только по нажатию, поэтому вызываем на первом тапе.
## (iPhone так не умеет — там игру добавляют на экран «Домой».)
func _fullscreen() -> void:
	var mobile := OS.has_feature("web_android") or OS.has_feature("web_ios")
	if mobile and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _unhandled_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventMouseButton and e.pressed) or (e is InputEventKey and e.pressed and not e.echo)
	if not tap:
		return
	if settings.visible:
		return
	if _stage == 0:
		_fullscreen()
		_show_menu(false)
	elif e is InputEventMouseButton:
		_squash_at(e.position)


## Логотип падает сверху с отскоком, потом выезжают кнопки.
func _show_menu(instant: bool) -> void:
	_stage = 1
	intro_done = true
	hint.visible = false
	if instant:
		logo.position = Vector2(640, 170)
		for i in buttons.size():
			buttons[i].visible = true
			buttons[i].position.y -= 400
		return
	var tw := create_tween()
	tw.tween_property(logo, "position", Vector2(640, 170), 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): Sound.roach_hit(self))
	for i in buttons.size():
		var b := buttons[i]
		tw.tween_callback(func(): b.visible = true)
		tw.tween_property(b, "position:y", b.position.y - 400, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	if _stage == 0:
		hint.modulate.a = 0.55 + 0.45 * sin(_t * 4.0)
		return
	logo.rotation = sin(_t * 1.6) * 0.02
	logo.scale = Vector2.ONE * (1.0 + 0.015 * sin(_t * 3.0))
	# тараканы понемногу начинают ползать
	_roach_t -= delta
	if _roach_t <= 0.0:
		_roach_t = randf_range(1.0, 2.6)
		if roaches.get_child_count() < 7:
			var r := MenuRoach.new()
			roaches.add_child(r)
			r.setup()


func _squash_at(p: Vector2) -> void:
	for r in roaches.get_children():
		if r is MenuRoach and r.alive and r.position.distance_to(p) < 40.0:
			r.squash()
			Sound.roach_hit(self)
			return


## Таракан в меню: выползает из-за края, бродит по экрану и уходит.
class MenuRoach extends Node2D:
	var alive := true
	var body: AnimatedSprite2D
	var heading := 0.0
	var target := Vector2.ZERO
	var legs := 0
	var speed := 120.0

	func setup() -> void:
		body = AnimatedSprite2D.new()
		body.sprite_frames = Cfg.roach_frames()
		body.scale = Vector2.ONE * randf_range(0.45, 0.6)
		add_child(body)
		var side := randi() % 4
		match side:
			0: position = Vector2(-50, randf_range(50, 670))
			1: position = Vector2(1330, randf_range(50, 670))
			2: position = Vector2(randf_range(50, 1230), -50)
			_: position = Vector2(randf_range(50, 1230), 770)
		speed = randf_range(90, 170)
		legs = randi_range(2, 4)
		_new_target()
		heading = (target - position).angle()
		body.play("walk" if speed < 130 else "run")

	func _new_target() -> void:
		if legs <= 0:
			# уходим за край
			var d := Vector2.from_angle(randf() * TAU) * 1600.0
			target = Vector2(640, 360) + d
		else:
			target = Vector2(randf_range(80, 1200), randf_range(80, 640))
		legs -= 1

	func squash() -> void:
		alive = false
		body.play("die")
		var tw := create_tween()
		tw.tween_interval(1.5)
		tw.tween_property(self, "modulate:a", 0.0, 0.6)
		tw.tween_callback(queue_free)

	func _process(delta: float) -> void:
		if not alive:
			return
		var d := position.distance_to(target)
		if d < 20.0:
			_new_target()
		var want := (target - position).angle()
		var turn := 4.0 if d > 70.0 else 16.0
		heading = lerp_angle(heading, want, clampf(delta * turn, 0.0, 1.0))
		position += Vector2.from_angle(heading) * minf(speed * delta, maxf(d, 1.0))
		rotation = heading + PI / 2.0
		if position.x < -150 or position.x > 1430 or position.y < -150 or position.y > 870:
			queue_free()


## Окно «Музыка»: ползунки музыки и эффектов, «Сохранить» и «Выйти» (без сохранения).
class SoundPanel extends Control:
	var music_s: HSlider
	var sfx_s: HSlider
	var shake_s: HSlider
	var _old := Vector3.ONE

	func _ready() -> void:
		position = Vector2.ZERO
		size = Cfg.VIEW
		visible = false
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.6)
		dim.size = Cfg.VIEW
		add_child(dim)
		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.82, 0.25)
		sb.border_color = Color(0.1, 0.05, 0.02)
		sb.set_border_width_all(6)
		sb.set_corner_radius_all(26)
		sb.set_content_margin_all(28)
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 12
		panel.add_theme_stylebox_override("panel", sb)
		panel.position = Vector2(390, 60)
		panel.custom_minimum_size = Vector2(500, 0)
		add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 16)
		panel.add_child(box)
		box.add_child(_title("НАСТРОЙКИ", 48))
		music_s = _slider(box, "Музыка", Sound.music_volume)
		music_s.value_changed.connect(func(v):
			Sound.music_volume = v / 100.0
			Sound.apply())
		sfx_s = _slider(box, "Эффекты", Sound.sfx_volume)
		sfx_s.value_changed.connect(func(v):
			Sound.sfx_volume = v / 100.0
			Sound.apply())
		sfx_s.drag_ended.connect(func(_c): Sound.roach_hit(self))   # пробный писк
		# тряска экрана: 0 — выключена (удобно на телефоне)
		shake_s = _slider(box, "Тряска экрана", Sound.shake)
		shake_s.value_changed.connect(func(v): Sound.shake = v / 100.0)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 20)
		box.add_child(row)
		row.add_child(_btn("Сохранить", Color(0.25, 0.65, 0.25), func():
			Sound.save_settings()
			visible = false))
		row.add_child(_btn("Выйти", Color(0.8, 0.25, 0.15), func():
			Sound.music_volume = _old.x
			Sound.sfx_volume = _old.y
			Sound.apply()
			visible = false))

	func open() -> void:
		Sound.load_settings()
		_old = Vector3(Sound.music_volume, Sound.sfx_volume, Sound.shake)
		music_s.set_value_no_signal(Sound.music_volume * 100.0)
		sfx_s.set_value_no_signal(Sound.sfx_volume * 100.0)
		shake_s.set_value_no_signal(Sound.shake * 100.0)
		visible = true

	func _title(t: String, size: int) -> Label:
		var l := Label.new()
		l.text = t
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", Color(0.95, 0.2, 0.1))
		l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
		l.add_theme_constant_override("outline_size", 12)
		return l

	func _slider(box: Node, name: String, v: float) -> HSlider:
		var l := _title(name, 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(l)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 100
		s.step = 1
		s.value = v * 100.0
		s.custom_minimum_size = Vector2(440, 36)
		var knob := Image.create(34, 34, false, Image.FORMAT_RGBA8)   # круглый «бегунок»
		for y in 34:
			for x in 34:
				var d := Vector2(x - 16.5, y - 16.5).length()
				if d <= 16.5:
					knob.set_pixel(x, y, Color(0.1, 0.05, 0.02) if d > 13.0 else Color(1, 0.95, 0.85))
		var kt := ImageTexture.create_from_image(knob)
		s.add_theme_icon_override("grabber", kt)
		s.add_theme_icon_override("grabber_highlight", kt)
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(0.95, 0.25, 0.1)
		grab.set_corner_radius_all(8)
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0.3, 0.15, 0.05)
		track.set_corner_radius_all(8)
		track.content_margin_top = 8
		track.content_margin_bottom = 8
		s.add_theme_stylebox_override("slider", track)
		s.add_theme_stylebox_override("grabber_area", grab)
		s.add_theme_stylebox_override("grabber_area_highlight", grab)
		s.add_theme_constant_override("grabber_offset", 0)
		box.add_child(s)
		return s

	func _btn(text: String, c: Color, cb: Callable) -> Button:
		var b := Button.new()
		b.text = text
		b.custom_minimum_size = Vector2(200, 60)
		b.add_theme_font_size_override("font_size", 28)
		for st in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = c.lightened(0.15) if st == "hover" else (c.darkened(0.2) if st == "pressed" else c)
			sb.border_color = Color(0.1, 0.05, 0.02)
			sb.set_border_width_all(4)
			sb.set_corner_radius_all(16)
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
		b.add_theme_constant_override("outline_size", 8)
		b.pressed.connect(cb)
		return b

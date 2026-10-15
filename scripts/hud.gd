class_name Hud
extends CanvasLayer
## Интерфейс: очки, комбо, таймер, остаток еды, меню, пауза и итоги.

signal start_pressed
signal pause_pressed
signal resume_pressed

const TITLE := "Обед под угрозой"
const STORY := "Студент вернулся с пар и наконец сел пообедать…\nНо на столе уже хозяйничают тараканы!\n\nТараканы подлезают под еду и утаскивают её со стола.\nБей их мухобойкой и продержись %d волн.\nМимо — по вещам лучше не попадать."

var score_l: Label
var combo_l: Label
var time_l: Label
var food_l: Label
var food_bar: ProgressBar
var top: Control

var overlay: ColorRect
var title_l: Label
var text_l: Label
var button: Button
var pause_l: Label
var pause_btn: Button
var menu_b: Button
var waves_done := 0

var boss_box: Control
var boss_bar: ProgressBar
var _glow := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top = Control.new()
	top.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	score_l = _label(top, 34, Vector2(20, 10), Vector2(400, 50))
	combo_l = _label(top, 26, Vector2(20, 52), Vector2(400, 40))
	combo_l.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	time_l = _label(top, 28, Vector2(20, 88), Vector2(700, 40))
	time_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	food_l = _label(top, 26, Vector2(960, 10), Vector2(300, 40))
	food_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	food_bar = ProgressBar.new()
	food_bar.position = Vector2(1000, 50)
	food_bar.size = Vector2(260, 22)
	food_bar.show_percentage = false
	food_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.65, 0.2)
	food_bar.add_theme_stylebox_override("fill", fill)
	top.add_child(food_bar)

	# здоровье босса
	boss_box = Control.new()
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.visible = false
	top.add_child(boss_box)
	# внизу по центру, чтобы не закрывать монитор с сообщениями
	var bl := _label(boss_box, 24, Vector2(390, 636), Vector2(500, 34))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.text = "КОРОЛЬ ОБЩАГИ"
	bl.add_theme_color_override("font_color", Color(1, 0.75, 0.3))
	boss_bar = _bar(Vector2(440, 672), Vector2(400, 24), Color(0.8, 0.15, 0.1))
	boss_box.add_child(boss_bar)

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.62)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(820, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)
	title_l = _label(box, 64, Vector2.ZERO, Vector2.ZERO)
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_l = _label(box, 26, Vector2.ZERO, Vector2.ZERO)
	text_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button = Button.new()
	button.custom_minimum_size = Vector2(320, 72)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 32)
	button.pressed.connect(func(): start_pressed.emit())
	box.add_child(button)
	menu_b = Button.new()
	menu_b.text = "В меню"
	menu_b.custom_minimum_size = Vector2(220, 52)
	menu_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu_b.add_theme_font_size_override("font_size", 24)
	menu_b.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	box.add_child(menu_b)

	# кнопка паузы — на телефоне нет клавиши Esc
	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.position = Vector2(1192, 84)
	pause_btn.size = Vector2(70, 70)
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.add_theme_font_size_override("font_size", 32)
	pause_btn.pressed.connect(func(): pause_pressed.emit())
	top.add_child(pause_btn)

	pause_l = _label(self, 48, Vector2(0, 0), Cfg.VIEW)
	pause_l.text = ""
	pause_l.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Cfg.VIEW
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_l.add_child(dim)
	var pb := VBoxContainer.new()
	pb.position = Vector2(440, 200)
	pb.size = Vector2(400, 300)
	pb.alignment = BoxContainer.ALIGNMENT_CENTER
	pb.add_theme_constant_override("separation", 22)
	pause_l.add_child(pb)
	var pt := _label(pb, 64, Vector2.ZERO, Vector2.ZERO)
	pt.text = "Пауза"
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var items := [["Продолжить", func(): resume_pressed.emit(), Color(0.25, 0.62, 0.25)],
		["В меню", func():
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/menu.tscn"), Color(0.78, 0.27, 0.15)]]
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.custom_minimum_size = Vector2(400, 76)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 34)
		b.add_theme_color_override("font_color", Color.WHITE)
		for st in ["normal", "hover", "pressed"]:
			var c: Color = it[2]
			var bs := StyleBoxFlat.new()
			bs.bg_color = c.lightened(0.12) if st == "hover" else (c.darkened(0.2) if st == "pressed" else c)
			bs.border_color = Color(0.08, 0.05, 0.02)
			bs.set_border_width_all(4)
			bs.set_corner_radius_all(16)
			b.add_theme_stylebox_override(st, bs)
		b.pressed.connect(it[1])
		pb.add_child(b)


func _label(parent: Node, size: int, pos: Vector2, sz: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent is Container:
		parent.add_child(l)
	else:
		l.position = pos
		l.size = sz
		parent.add_child(l)
	return l


func _bar(pos: Vector2, sz: Vector2, c: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = pos
	b.size = sz
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = c
	fill.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.border_color = Color(0, 0, 0)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	return b


func show_boss(v: bool) -> void:
	boss_box.visible = v


func set_boss(hp: int, max_hp: int) -> void:
	boss_bar.max_value = max_hp
	boss_bar.value = hp


## Комбо ×5: очки светятся и пульсируют.
func set_combo_glow(v: bool) -> void:
	_glow = v
	if not v:
		score_l.add_theme_color_override("font_color", Color.WHITE)
		score_l.scale = Vector2.ONE


func _process(_delta: float) -> void:
	if _glow:
		var t := Time.get_ticks_msec() / 1000.0
		score_l.add_theme_color_override("font_color", Color(1, 0.85, 0.2).lerp(Color(1, 1, 0.7), 0.5 + 0.5 * sin(t * 8.0)))
		score_l.pivot_offset = Vector2(0, 25)
		score_l.scale = Vector2.ONE * (1.0 + 0.06 * absf(sin(t * 8.0)))


func show_menu(best: int) -> void:
	top.visible = false
	overlay.visible = true
	title_l.text = TITLE
	text_l.text = STORY % Cfg.TOTAL_WAVES
	if best > 0:
		text_l.text += "\n\nРекорд: %d" % best
	button.text = "Играть"
	menu_b.visible = false


func show_game() -> void:
	top.visible = true
	overlay.visible = false
	boss_box.visible = false
	set_combo_glow(false)
	pause_l.visible = false


func show_pause(v: bool) -> void:
	pause_l.visible = v
	pause_btn.visible = not v


func show_end(win: bool, score: int, best: int, record: bool, kills: int, food_left: int) -> void:
	overlay.visible = true
	title_l.text = "Обед спасён! Все %d волн отбиты" % Cfg.TOTAL_WAVES if win else "Обед украли…"
	var t := "Волн отбито: %d\nТараканов прихлопнуто: %d\n" % [waves_done, kills]
	if win:
		t += "Блюд отстояли: %d (+%d)\n" % [food_left, food_left * Cfg.FOOD_KEPT_BONUS]
	t += "\nОчки: %d\n" % score
	t += "Новый рекорд!" if record else "Рекорд: %d" % best
	text_l.text = t
	button.text = "Ещё раз"
	menu_b.visible = true


func set_score(score: int, best: int, mult: int) -> void:
	score_l.text = "Очки: %d" % score
	combo_l.text = ("Комбо x%d" % mult) if mult > 1 else ""


func set_wave(n: int, total: int, title := "") -> void:
	time_l.text = "Волна %d/%d" % [n, total]
	if title != "":
		time_l.text += ": " + title


func set_food(left: int, total: int) -> void:
	food_l.text = "Обед: %d / %d" % [left, total]
	food_bar.max_value = total
	food_bar.value = left

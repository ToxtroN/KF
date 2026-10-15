extends Node
## Все настройки игры в одном месте (автозагрузка «Cfg»).

const VIEW := Vector2(1280, 720)
const SPRITES := "res://assets/sprites/"
const SOUNDS := "res://assets/sounds/"

# ---------- Стол ----------
# table.png растянут по ширине экрана (1280×960), видна полоса высотой 720.
# TABLE_OFFSET_Y сдвигает картинку вверх: чем больше по модулю, тем ближе к краю со стулом.
const TABLE_TEXTURE := "table.png"
const TABLE_OFFSET_Y := -120.0
const TABLE_NEAR_EDGE := 650.0    # экранная Y ближнего края столешницы — ниже предметы не ставим

# ---------- Волны ----------
# 10 волн, у каждой своё имя и событие. Перед волной на мониторе — отсчёт COUNTDOWN..1.
# Поля волны: name/sub — название и подзаголовок; normal/fast/big/flying — сколько тараканов;
# interval — пауза между появлениями; rushes — какие вспышки бывают (типы из RUSHES), [] — без вспышек;
# rush_every — затишье между вспышками; target — все идут на это блюдо ("pizza"/"noodles");
# light_food — блюда лёгкие (тащат меньшей толпой и быстрее); boss — выходит Король общаги;
# tips — подсказки новичку на мониторе.
# Вспышки только в 2-й, 6-й, 8-й и 10-й волнах — остальные спокойнее и отличаются составом.
const COUNTDOWN := 4
const WAVES := [
	{"name": "Незваные гости", "sub": "Бей их мухобойкой!", "normal": 7, "interval": 1.6, "rushes": [], "tips": true},
	{"name": "Они зовут друзей", "sub": "Берегись — нападут толпой!", "normal": 9, "interval": 1.4,
		"rushes": ["normal"], "rush_every": Vector2(10, 14)},
	{"name": "Быстрее, чем Wi-Fi", "sub": "Появились быстрые!", "normal": 6, "fast": 8, "interval": 1.0, "rushes": []},
	{"name": "Тяжёлый ужин", "sub": "Большие — бей дважды", "normal": 7, "fast": 3, "big": 6, "interval": 1.0, "rushes": []},
	{"name": "Воздушная тревога", "sub": "Они научились летать!", "normal": 6, "fast": 3, "flying": 9, "interval": 0.9, "rushes": []},
	{"name": "Операция «Пицца»", "sub": "Все на пиццу — защищай её!", "normal": 10, "fast": 5, "big": 2, "interval": 0.9,
		"rushes": ["normal", "fast"], "rush_every": Vector2(12, 17), "target": "pizza"},
	{"name": "Операция «Доширак»", "sub": "Охота на лапшу!", "normal": 12, "fast": 6, "flying": 4, "interval": 0.8,
		"rushes": [], "target": "noodles"},
	{"name": "Полный хаос", "sub": "Атаки одна за другой", "normal": 8, "fast": 6, "big": 3, "flying": 4, "interval": 0.8,
		"rushes": ["normal", "fast", "big", "flying"], "rush_every": Vector2(7, 11)},
	{"name": "Последний кусочек", "sub": "Еда лёгкая — её утащат мигом!", "normal": 12, "fast": 8, "big": 3, "flying": 5, "interval": 0.75,
		"rushes": [], "light_food": true},
	{"name": "Король общаги", "sub": "БОСС", "normal": 6, "fast": 4, "interval": 1.2,
		"rushes": ["normal", "fast"], "rush_every": Vector2(14, 20), "boss": true},
]
const TOTAL_WAVES := 10
# ---------- Вспышки (контратаки) ----------
# Посреди волны, после затишья, тараканы внезапно атакуют толпой с одной стороны.
# Какие вспышки бывают — в поле rushes у волны. count растёт с номером волны.
const RUSHES := [
	{"name": "КОНТРАТАКА!", "type": "fast", "count": 5, "count_per_wave": 0.8, "gap": 0.12},
	{"name": "ТОЛПА!", "type": "normal", "count": 7, "count_per_wave": 1.2, "gap": 0.1},
	{"name": "ТЯЖЁЛАЯ ПЕХОТА!", "type": "big", "count": 3, "count_per_wave": 0.4, "gap": 0.35},
	{"name": "ДЕСАНТ С ВОЗДУХА!", "type": "flying", "count": 4, "count_per_wave": 0.5, "gap": 0.2},
]
const RUSH_WARN := 1.6
const RUSH_CALM := 1.4               # во сколько раз реже идут обычные тараканы между вспышками
# ---------- Босс «Король общаги» ----------
const BOSS_HP := Vector2i(8, 12)
const BOSS_SUMMON := Vector2(6.0, 3.5)   # интервал вызова мелких: спокойный / в панике
const BOSS_SUMMON_COUNT := 2
const BOSS_PANIC_HP := 0.35          # ниже этой доли здоровья — паника и бег
const BOSS_POWER := 3                # тащит еду как 3 таракана
# ---------- Лапша и вилка ----------
# Удар мимо тараканов по лапше: вилка вылетает, лапша разлетается. Вилку можно вернуть кликом.
const NOODLE_PENALTY := 15
const FORK_W := 150
const FORK_OFFSET := Vector2(62, -30)   # где вилка воткнута относительно центра лапши
const FORK_BACK_BONUS := 20
# ---------- Кофе ----------
const PUDDLE_TIME := 30.0            # сколько живёт лужа
const PUDDLE_SLOW := 0.55            # скорость тараканов в луже
const PUDDLE_STUCK := 0.35           # шанс застрять при входе в лужу
const PUDDLE_STUCK_TIME := 2.2
# ---------- Предметы ----------
# Удачные промахи: клавиатура пугает тараканов, крышка пиццы ловит их, вилку можно вернуть.
const KEYBOARD_SCARE := 260.0
const PIZZA_LID_TIME := 4.0          # крышка коробки захлопнута, тараканы под ней пойманы
# ---------- Ощущения удара ----------
const HITSTOP := 0.055               # микропауза при попадании, сек
const LAST_ROACH_SLOWMO := 0.6       # замедление на последнем таракане волны
const WAVE_CLEAR_BONUS := 100     # за каждую пройденную волну (× номер волны)
const MAX_ROACHES := 26           # одновременно на столе, остальные ждут своей очереди

# ---------- Рука с мухобойкой ----------
# hand.png — вертикально: мухобойка сверху, рукав уходит вниз.
# HAND_HEAD_POINT — пиксель в hand.png, который совпадает с курсором (центр мухобойки).
const HAND_TEXTURE := "hand.png"
const HAND_HEAD_POINT := Vector2(348, 92)
const HAND_SCALE := 0.72
# «Плечо» за нижним краем экрана: рука всегда направлена от него к курсору и сдвигается вдоль оси.
const SHOULDER := Vector2(700, 900)
const HIT_RADIUS := 60.0
const SWING_COOLDOWN := 0.2
const SWING_UP_SCALE := 1.12
const SCARE_RADIUS := 170.0       # промах рядом пугает тараканов — они бросаются бежать

# ---------- Анимации таракана ----------
# Листы кадров по горизонтали, голова ВВЕРХ, ячейка ROACH_CELL.
const ROACH_CELL := Vector2(150, 190)
const ROACH_ANIMS := {
	"walk": {"tex": "roach_walk.png", "frames": 8, "fps": 14.0, "loop": true},
	"run": {"tex": "roach_run.png", "frames": 8, "fps": 22.0, "loop": true},
	"idle": {"tex": "roach_idle.png", "frames": 8, "fps": 10.0, "loop": true},
	"startle": {"tex": "roach_startle.png", "frames": 6, "fps": 18.0, "loop": false},
	"die": {"tex": "roach_die.png", "frames": 8, "fps": 16.0, "loop": false},
}

# ---------- Виды тараканов ----------
# move — анимация бега; tint — оттенок; wings — летающий (крылья рисуются кодом).
const ROACHES := {
	"normal": {"move": "walk", "scale": 0.62, "tint": Color(1, 1, 1),
		"speed": 105.0, "hp": 1, "score": 10, "radius": 24.0},
	"fast": {"move": "run", "scale": 0.52, "tint": Color(1.15, 1.0, 0.8),
		"speed": 190.0, "hp": 1, "score": 20, "radius": 20.0},
	"big": {"move": "walk", "scale": 0.9, "tint": Color(0.65, 0.55, 0.5),
		"speed": 70.0, "hp": 2, "score": 35, "radius": 34.0},
	"flying": {"move": "run", "scale": 0.62, "tint": Color(1, 0.9, 0.85), "wings": true,
		"speed": 150.0, "hp": 1, "score": 40, "radius": 26.0},
	"boss": {"move": "walk", "scale": 2.0, "tint": Color(0.8, 0.5, 0.42),
		"speed": 55.0, "hp": 10, "score": 600, "radius": 66.0},
}
# ---------- Перетаскивание еды ----------
# Тараканы подлезают под блюдо и тащат его к ближайшему краю стола, как муравьи.
# weight — сколько тараканов нужно для полной скорости; MIN_CARRY_PART — какая доля от weight
# нужна, чтобы блюдо вообще сдвинулось (меньше — только дёргается на месте).
const DRAG_SPEED := 34.0          # px/сек при weight тараканах
const DRAG_MAX_MULT := 1.6        # больше тараканов — быстрее, но не больше этого множителя
const MIN_CARRY_PART := 0.5
const GIVE_UP_TIME := 5.0        # столько секунд одиночка упирается в неподвижное блюдо, потом уходит
const SLOT_EDGE := 0.9            # насколько глубоко под блюдо залезают (1 — ровно по краю)
const FOOD_KEPT_BONUS := 150      # очков за каждое блюдо, оставшееся на столе к концу раунда

# ---------- Предметы на столе ----------
# Расставлены по референсу. w — ширина на экране (масштаб считается сам), rot — поворот, рад.
# blocks — непроходимые прямоугольники (в пикселях спрайта): по ним не бегают и не тащат еду.
# kind: decor — картинка; food — еда (weight — сколько тараканов нужно, чтобы утащить);
#       breakable — портится при промахе (radius/hit_offset — зона попадания, penalty — штраф).
# Предметы с референса, которых пока нет (стакан с карандашами, банка, блокнот, кассета,
# ручка, плеер, скомканная бумага), добавляются сюда же строчкой decor.
const TABLE_ITEMS := [
	{"kind": "decor", "tex": "papers.png", "pos": Vector2(140, 420), "w": 310},
	{"kind": "breakable", "tex": "computer.png", "pos": Vector2(650, 92), "w": 620,
		"radius": 125.0, "penalty": 60, "effect": "crack", "hit_offset": Vector2(-4, -30),
		# blocks — непроходимые зоны в пикселях спрайта: монитор с колонками и клавиатура с мышью
		"blocks": [Rect2(3, 0, 584, 400), Rect2(75, 400, 516, 175)],
		# screen — где на спрайте экран монитора (там отсчёт волн и сообщения STUDENT OS 98)
		"screen": Rect2(160, 232, 270, 103)},
	# клавиатура и мышь — часть картинки компьютера, тут только зоны удара
	{"kind": "prop", "prop": "keyboard", "pos": Vector2(637, 290), "size": Vector2(420, 150)},
	# лампа: тараканы обходят её основание (абажур висит над столом)
	{"kind": "decor", "tex": "lamp.png", "pos": Vector2(1195, 95), "w": 260,
		"blocks": [Rect2(55, 190, 180, 180), Rect2(235, 190, 220, 180)]},
	{"kind": "breakable", "tex": "mug.png", "pos": Vector2(1200, 325), "w": 150,
		"radius": 60.0, "penalty": 15, "effect": "spill",
		# кружку обходят; зона тянется до правого края экрана, чтобы не было узкой щели, где тараканы застревают
		"blocks": [Rect2(10, 25, 225, 265), Rect2(225, 25, 330, 265)]},
	{"kind": "food", "id": "pizza", "tex": "pizza_box.png", "pos": Vector2(1010, 522), "w": 260, "rot": -0.08,
		"weight": 4, "radius": 110.0, "lid": true},
	{"kind": "food", "id": "noodles", "tex": "noodles.png", "pos": Vector2(620, 540), "w": 230, "rot": 0.04, "fork": true,
		"weight": 3, "radius": 85.0},
]

# ---------- Комбо ----------
const COMBO_STEP := 3
const COMBO_MAX := 5
const MULTIKILL_BONUS := 25


var _roach_frames: SpriteFrames


func tex(file: String) -> Texture2D:
	var path := SPRITES + file
	if ResourceLoader.exists(path):
		return load(path)
	return null


## Общие кадры тараканов (собираются один раз из листов).
func roach_frames() -> SpriteFrames:
	if _roach_frames:
		return _roach_frames
	_roach_frames = SpriteFrames.new()
	_roach_frames.remove_animation("default")
	for anim_name in ROACH_ANIMS:
		var d: Dictionary = ROACH_ANIMS[anim_name]
		var t := tex(d.tex)
		_roach_frames.add_animation(anim_name)
		_roach_frames.set_animation_speed(anim_name, d.fps)
		_roach_frames.set_animation_loop(anim_name, d.loop)
		if t == null:
			continue
		for i in d.frames:
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = Rect2(Vector2(i * ROACH_CELL.x, 0), ROACH_CELL)
			_roach_frames.add_frame(anim_name, at)
	return _roach_frames

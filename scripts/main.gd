extends Control
## Overclocked - lo-fi prototype.
## One screen: click the PC case to earn money, buy parts in the shop,
## keep power (PSU watts) and heat (cooling limit) in balance.
## All visuals are placeholders built in code (grey boxes, plain buttons, bars).

const SLOT_ORDER := ["CPU", "GPU", "RAM", "Storage", "Cooling", "PSU"]

## Each slot has 2 tiers. Stats are absolute for that tier (tier 2 replaces tier 1).
## click = money per click, ps = money per second, watts = power draw, heat = degrees added.
## Cooling uses "limit" (max safe temperature), PSU uses "capacity" (max watts).
const PARTS := {
	"CPU": [
		{"name": "Ryzon 3 1200", "cost": 25, "click": 1.0, "ps": 0.5, "watts": 65, "heat": 8},
		{"name": "Ryzon 7 5800", "cost": 1500, "click": 6.0, "ps": 4.5, "watts": 125, "heat": 22},
	],
	"GPU": [
		{"name": "GForce RTZ 1050", "cost": 100, "click": 0.0, "ps": 2.0, "watts": 120, "heat": 12},
		{"name": "GForce RTZ 4080", "cost": 3500, "click": 0.0, "ps": 17.0, "watts": 250, "heat": 35},
	],
	"RAM": [
		{"name": "Kingstun 8 GB", "cost": 15, "click": 1.0, "ps": 0.0, "watts": 5, "heat": 1},
		{"name": "Kingstun 32 GB", "cost": 600, "click": 4.0, "ps": 1.0, "watts": 10, "heat": 3},
	],
	"Storage": [
		{"name": "Samsong 256 GB SSD", "cost": 40, "click": 0.0, "ps": 1.0, "watts": 5, "heat": 0},
		{"name": "Samsong 2 TB NVMe", "cost": 900, "click": 0.0, "ps": 6.0, "watts": 8, "heat": 1},
	],
	"Cooling": [
		{"name": "Tower air cooler", "cost": 60, "watts": 5, "limit": 80},
		{"name": "Liquid Freezr 360", "cost": 1200, "watts": 15, "limit": 105},
	],
	"PSU": [
		{"name": "Seasonik 450 W", "cost": 80, "capacity": 450},
		{"name": "Seasonik 750 W", "cost": 1000, "capacity": 750},
	],
}

const BASE_WATTS := 120        # motherboard, fans, drives of the old office PC
const BASE_PSU := 250          # stock office PSU
const BASE_HEAT := 35.0        # idle temperature
const BASE_COOL_LIMIT := 65.0  # stock cooler
const OVERCLOCK_TIME := 10.0
const OVERCLOCK_COOLDOWN := 20.0
const OVERCLOCK_HEAT := 15.0

var money := 0.0
var tiers := {}                # slot -> installed tier (0 = empty/stock)
var heat := BASE_HEAT          # shown temperature, moves toward the target
var overclock_left := 0.0
var overclock_cooldown := 0.0
var elapsed := 0.0
var won := false
var message_time := 0.0

# UI references
var money_label: Label
var rate_label: Label
var power_bar: ProgressBar
var power_label: Label
var heat_bar: ProgressBar
var heat_label: Label
var heat_fill: StyleBoxFlat
var status_label: Label
var oc_button: Button
var message_label: Label
var case_button: Button
var slot_boxes := {}
var slot_labels := {}
var shop_buttons := {}
var win_panel: PanelContainer
var win_label: Label


func _ready() -> void:
	for slot in SLOT_ORDER:
		tiers[slot] = 0
	_build_ui()
	_update_ui()


func _process(delta: float) -> void:
	if won:
		return
	elapsed += delta
	if overclock_left > 0.0:
		overclock_left = max(0.0, overclock_left - delta)
	elif overclock_cooldown > 0.0:
		overclock_cooldown = max(0.0, overclock_cooldown - delta)
	heat = move_toward(heat, target_heat(), 8.0 * delta)
	money += per_second() * multiplier() * delta
	if message_time > 0.0:
		message_time -= delta
		if message_time <= 0.0:
			message_label.text = ""
	_update_ui()


# ---------- game rules ----------

func part(slot: String) -> Dictionary:
	var t: int = tiers[slot]
	if t == 0:
		return {}
	return PARTS[slot][t - 1]


func per_click() -> float:
	var total := 1.0
	for slot in SLOT_ORDER:
		total += part(slot).get("click", 0.0)
	return total


func per_second() -> float:
	var total := 0.0
	for slot in SLOT_ORDER:
		total += part(slot).get("ps", 0.0)
	return total


func total_watts() -> int:
	var total := BASE_WATTS
	for slot in SLOT_ORDER:
		total += int(part(slot).get("watts", 0))
	return total


func psu_capacity() -> int:
	return int(part("PSU").get("capacity", BASE_PSU))


func cool_limit() -> float:
	return float(part("Cooling").get("limit", BASE_COOL_LIMIT))


func target_heat() -> float:
	var total := BASE_HEAT
	for slot in SLOT_ORDER:
		total += float(part(slot).get("heat", 0))
	if overclock_left > 0.0:
		total += OVERCLOCK_HEAT
	return total


func is_throttled() -> bool:
	return heat > cool_limit()


func multiplier() -> float:
	var m := 1.0
	if overclock_left > 0.0:
		m *= 2.0
	if is_throttled():
		m *= 0.5
	return m


## Returns "" if the next tier of this slot can be bought, otherwise the reason.
func buy_block_reason(slot: String) -> String:
	var t: int = tiers[slot]
	if t >= 2:
		return "maxed"
	var next: Dictionary = PARTS[slot][t]
	if slot != "PSU":
		var new_watts := total_watts() - int(part(slot).get("watts", 0)) + int(next.get("watts", 0))
		if new_watts > psu_capacity():
			return "power"
	if money < next["cost"]:
		return "money"
	return ""


func buy(slot: String) -> void:
	var reason := buy_block_reason(slot)
	if reason == "power":
		var next: Dictionary = PARTS[slot][tiers[slot]]
		var new_watts := total_watts() - int(part(slot).get("watts", 0)) + int(next["watts"])
		_show_message("Not enough power: %s needs %d W total, PSU gives %d W. Upgrade the PSU first." % [next["name"], new_watts, psu_capacity()])
		return
	if reason != "":
		return
	var next_part: Dictionary = PARTS[slot][tiers[slot]]
	money -= next_part["cost"]
	tiers[slot] += 1
	_show_message("Installed %s!" % next_part["name"])
	_check_win()


func click_pc() -> void:
	if won:
		return
	var gain := per_click() * multiplier()
	money += gain
	_spawn_float_text("+$%s" % _fmt(gain), get_global_mouse_position())


func overclock() -> void:
	if overclock_left > 0.0 or overclock_cooldown > 0.0 or won:
		return
	overclock_left = OVERCLOCK_TIME
	overclock_cooldown = OVERCLOCK_COOLDOWN
	_show_message("Overclocked! x2 earnings for 10 s, but heat goes up.")


func _check_win() -> void:
	for slot in SLOT_ORDER:
		if tiers[slot] < 2:
			return
	won = true
	var mins := int(elapsed) / 60
	var secs := int(elapsed) % 60
	win_label.text = "RIG MAXED OUT!\n\nTime: %d:%02d\n\nIn the full game you would now do a New Build\n(sell the rig, start the next generation with bonuses)." % [mins, secs]
	win_panel.visible = true
	_update_ui()


# ---------- UI ----------

func _box_style(color: Color, border := Color(0.15, 0.15, 0.15)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(3)
	s.set_content_margin_all(12)
	return s


func _label(text: String, size := 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _build_ui() -> void:
	var t := Theme.new()
	t.default_font_size = 24
	var ink := Color(0.1, 0.1, 0.1)
	t.set_color("font_color", "Label", ink)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "Button", ink)
	t.set_color("font_disabled_color", "Button", Color(0.42, 0.42, 0.42))
	t.set_stylebox("normal", "Button", _box_style(Color(0.97, 0.97, 0.97), Color(0.3, 0.3, 0.3)))
	t.set_stylebox("hover", "Button", _box_style(Color(1.0, 1.0, 0.85), Color(0.3, 0.3, 0.3)))
	t.set_stylebox("pressed", "Button", _box_style(Color(0.85, 0.85, 0.7), Color(0.3, 0.3, 0.3)))
	t.set_stylebox("disabled", "Button", _box_style(Color(0.78, 0.78, 0.78), Color(0.6, 0.6, 0.6)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.7, 0.7, 0.7)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.25, 0.45, 0.8)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	theme = t

	var bg := ColorRect.new()
	bg.color = Color(0.82, 0.82, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# --- top bar ---
	money_label = _label("", 48)
	money_label.position = Vector2(640, 20)
	add_child(money_label)
	rate_label = _label("", 26)
	rate_label.position = Vector2(640, 85)
	add_child(rate_label)
	var title := _label("OVERCLOCKED  (lo-fi prototype)", 28)
	title.position = Vector2(40, 30)
	add_child(title)

	# --- left panel: gauges + overclock ---
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _box_style(Color(0.9, 0.9, 0.9)))
	left.position = Vector2(40, 140)
	left.size = Vector2(420, 560)
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 14)
	left.add_child(lv)

	lv.add_child(_label("POWER", 28))
	power_bar = ProgressBar.new()
	power_bar.custom_minimum_size = Vector2(380, 36)
	power_bar.show_percentage = false
	lv.add_child(power_bar)
	power_label = _label("")
	lv.add_child(power_label)

	lv.add_child(_label("HEAT", 28))
	heat_bar = ProgressBar.new()
	heat_bar.custom_minimum_size = Vector2(380, 36)
	heat_bar.show_percentage = false
	heat_bar.max_value = 120
	heat_fill = StyleBoxFlat.new()
	heat_bar.add_theme_stylebox_override("fill", heat_fill)
	lv.add_child(heat_bar)
	heat_label = _label("")
	lv.add_child(heat_label)
	status_label = _label("", 26)
	lv.add_child(status_label)

	oc_button = Button.new()
	oc_button.custom_minimum_size = Vector2(380, 90)
	oc_button.add_theme_font_size_override("font_size", 30)
	oc_button.pressed.connect(overclock)
	lv.add_child(oc_button)

	# --- center: clickable PC case with part slots ---
	case_button = Button.new()
	case_button.position = Vector2(520, 140)
	case_button.size = Vector2(860, 820)
	case_button.add_theme_stylebox_override("normal", _box_style(Color(0.55, 0.55, 0.55)))
	case_button.add_theme_stylebox_override("hover", _box_style(Color(0.6, 0.6, 0.6)))
	case_button.add_theme_stylebox_override("pressed", _box_style(Color(0.5, 0.5, 0.5)))
	case_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	case_button.pressed.connect(click_pc)
	add_child(case_button)

	var hint := _label("CLICK THE CASE TO RUN JOBS", 26)
	hint.position = Vector2(250, 20)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	case_button.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(40, 80)
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 30)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	case_button.add_child(grid)
	for slot in SLOT_ORDER:
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(375, 200)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := _label("", 24)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
		grid.add_child(box)
		slot_boxes[slot] = box
		slot_labels[slot] = l

	# --- right: shop ---
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", _box_style(Color(0.9, 0.9, 0.9)))
	right.position = Vector2(1420, 140)
	right.size = Vector2(460, 820)
	add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	rv.add_child(_label("PARTS SHOP", 28))
	for slot in SLOT_ORDER:
		var b := Button.new()
		b.custom_minimum_size = Vector2(430, 118)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(buy.bind(slot))
		rv.add_child(b)
		shop_buttons[slot] = b

	# --- message line ---
	message_label = _label("", 26)
	message_label.position = Vector2(40, 990)
	message_label.size = Vector2(1840, 60)
	add_child(message_label)

	# --- win panel ---
	win_panel = PanelContainer.new()
	win_panel.add_theme_stylebox_override("panel", _box_style(Color(1, 1, 0.75)))
	win_panel.position = Vector2(560, 330)
	win_panel.size = Vector2(800, 420)
	win_panel.visible = false
	add_child(win_panel)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 20)
	win_panel.add_child(wv)
	win_label = _label("", 30)
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wv.add_child(win_label)
	var restart := Button.new()
	restart.text = "Play again"
	restart.custom_minimum_size = Vector2(300, 70)
	restart.pressed.connect(func(): get_tree().reload_current_scene())
	wv.add_child(restart)


func _update_ui() -> void:
	var m := multiplier()
	money_label.text = "$%s" % _fmt(money)
	rate_label.text = "$%s per click   |   $%s per second" % [_fmt(per_click() * m), _fmt(per_second() * m)]

	var w := total_watts()
	var cap := psu_capacity()
	power_bar.max_value = cap
	power_bar.value = w
	power_label.text = "%d / %d W" % [w, cap]

	heat_bar.value = heat
	heat_label.text = "%d / %d °C limit" % [int(round(heat)), int(cool_limit())]
	if is_throttled():
		status_label.text = "THROTTLING: earnings x0.5"
		heat_fill.bg_color = Color(0.85, 0.15, 0.1)
		status_label.modulate = Color(0.8, 0, 0)
	elif heat > cool_limit() - 10.0:
		status_label.text = "Getting hot..."
		heat_fill.bg_color = Color(0.95, 0.55, 0.1)
		status_label.modulate = Color(0.8, 0.4, 0)
	else:
		status_label.text = "Temperature OK"
		heat_fill.bg_color = Color(0.3, 0.7, 0.3)
		status_label.modulate = Color(0, 0.5, 0)

	if overclock_left > 0.0:
		oc_button.text = "OVERCLOCK ACTIVE  %ds" % int(ceil(overclock_left))
		oc_button.disabled = true
	elif overclock_cooldown > 0.0:
		oc_button.text = "Overclock cooldown  %ds" % int(ceil(overclock_cooldown))
		oc_button.disabled = true
	else:
		oc_button.text = "OVERCLOCK (x2, +heat)"
		oc_button.disabled = won

	for slot in SLOT_ORDER:
		var t: int = tiers[slot]
		var shade: float = [0.35, 0.7, 0.92][t]
		slot_boxes[slot].add_theme_stylebox_override("panel", _box_style(Color(shade, shade, shade)))
		if t == 0:
			slot_labels[slot].text = "%s\n(stock / empty)" % slot
		else:
			slot_labels[slot].text = "%s  T%d\n%s" % [slot, t, part(slot)["name"]]

		var b: Button = shop_buttons[slot]
		if t >= 2:
			b.text = "%s: MAXED" % slot
			b.disabled = true
			b.modulate = Color(1, 1, 1)
			continue
		var next: Dictionary = PARTS[slot][t]
		var stats := ""
		if next.has("click") and next["click"] > 0:
			stats += "+%s/click  " % _fmt(next["click"])
		if next.has("ps") and next["ps"] > 0:
			stats += "+%s/s  " % _fmt(next["ps"])
		if next.has("watts"):
			stats += "%d W  " % next["watts"]
		if next.has("heat") and next["heat"] > 0:
			stats += "+%d °C" % next["heat"]
		if next.has("limit"):
			stats += "limit %d °C" % next["limit"]
		if next.has("capacity"):
			stats += "capacity %d W" % next["capacity"]
		var reason := buy_block_reason(slot)
		b.text = "%s T%d: %s\n$%s\n%s" % [slot, t + 1, next["name"], _fmt(next["cost"]), stats]
		if reason == "power":
			b.text += "\nNEEDS BIGGER PSU"
			b.modulate = Color(1, 0.6, 0.6)
			b.disabled = false   # clickable so the player gets the explanation
		else:
			b.modulate = Color(1, 1, 1)
			b.disabled = reason != "" or won


func _show_message(text: String) -> void:
	message_label.text = text
	message_time = 4.0


func _spawn_float_text(text: String, pos: Vector2) -> void:
	var l := _label(text, 30)
	l.position = pos - Vector2(30, 40)
	l.modulate = Color(0, 0.45, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 80, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(l.queue_free)


func _fmt(n: float) -> String:
	if n >= 1000000.0:
		return "%.2fM" % (n / 1000000.0)
	if n >= 10000.0:
		return "%.1fk" % (n / 1000.0)
	if abs(n - round(n)) < 0.05:
		return str(int(round(n)))
	return "%.1f" % n

extends Control
## Overclocked - prototype.
## One screen: click the PC case to earn money, buy parts in the shop,
## keep power (PSU watts) and heat (cooling limit) in balance, pick jobs,
## react to random events and finish the rig to unlock a New Build.
## All visuals are placeholders built in code (boxes, plain buttons, bars).
## Full rules: docs/game-design-document.md

const SLOT_ORDER := ["CPU", "GPU", "RAM", "Storage", "Cooling", "PSU"]
const MAX_TIER := 3

## Each slot has 3 tiers. Stats are absolute for that tier (a new tier replaces the old one).
## click = money per click, ps = money per second, watts = power draw, heat = degrees added.
## Cooling uses "limit" (max safe temperature), PSU uses "capacity" (max watts).
const PARTS := {
	"CPU": [
		{"name": "Ryzon 3 1200", "cost": 25, "click": 1.0, "ps": 0.5, "watts": 65, "heat": 8},
		{"name": "Ryzon 7 5800", "cost": 1500, "click": 6.0, "ps": 4.5, "watts": 125, "heat": 22},
		{"name": "Ryzon 9 9950", "cost": 15000, "click": 15.0, "ps": 14.0, "watts": 170, "heat": 30},
	],
	"GPU": [
		{"name": "GForce RTZ 1050", "cost": 100, "click": 0.0, "ps": 2.0, "watts": 120, "heat": 12},
		{"name": "GForce RTZ 4080", "cost": 3500, "click": 0.0, "ps": 17.0, "watts": 250, "heat": 35},
		{"name": "GForce RTZ 5090", "cost": 18000, "click": 0.0, "ps": 55.0, "watts": 450, "heat": 45},
	],
	"RAM": [
		{"name": "Kingstun 8 GB", "cost": 15, "click": 1.0, "ps": 0.0, "watts": 5, "heat": 1},
		{"name": "Kingstun 32 GB", "cost": 600, "click": 4.0, "ps": 1.0, "watts": 10, "heat": 3},
		{"name": "Kingstun 128 GB", "cost": 9000, "click": 10.0, "ps": 4.0, "watts": 15, "heat": 4},
	],
	"Storage": [
		{"name": "Samsong 256 GB SSD", "cost": 40, "click": 0.0, "ps": 1.0, "watts": 5, "heat": 0},
		{"name": "Samsong 2 TB NVMe", "cost": 900, "click": 0.0, "ps": 6.0, "watts": 8, "heat": 1},
		{"name": "Samsong 8 TB RAID", "cost": 12000, "click": 0.0, "ps": 18.0, "watts": 15, "heat": 2},
	],
	"Cooling": [
		{"name": "Tower air cooler", "cost": 60, "watts": 5, "limit": 80},
		{"name": "Liquid Freezr 360", "cost": 1200, "watts": 15, "limit": 105},
		{"name": "Cryo Phase X", "cost": 12000, "watts": 40, "limit": 145},
	],
	"PSU": [
		{"name": "Seasonik 450 W", "cost": 80, "capacity": 450},
		{"name": "Seasonik 750 W", "cost": 1000, "capacity": 750},
		{"name": "Seasonik 1600 W", "cost": 9000, "capacity": 1600},
	],
}

## Jobs: the active job multiplies all earnings but adds heat.
## "req" = minimum installed tier per slot needed to unlock the job.
const JOBS := [
	{"name": "Office tasks", "mult": 1.0, "heat": 0, "req": {}},
	{"name": "Game streaming", "mult": 1.5, "heat": 5, "req": {"CPU": 1, "GPU": 1}},
	{"name": "3D rendering", "mult": 2.5, "heat": 10, "req": {"CPU": 2, "GPU": 2}},
	{"name": "AI training", "mult": 4.0, "heat": 20, "req": {"GPU": 3, "RAM": 2}},
]

## Permanent New Build bonuses. Each New Build lets the player pick one; they stack.
const PERKS := {
	"earn": {"name": "Silicon Lottery", "desc": "+50% all earnings"},
	"discount": {"name": "Bulk Discount", "desc": "parts cost 20% less"},
	"cool": {"name": "Better Thermal Paste", "desc": "+10 °C cooling limit"},
}

const BASE_WATTS := 120        # motherboard, fans, drives of the old office PC
const BASE_PSU := 250          # stock office PSU
const BASE_HEAT := 35.0        # idle temperature
const BASE_COOL_LIMIT := 65.0  # stock cooler
const CRASH_MARGIN := 15.0     # heat this far above the limit crashes the PC
const CRASH_TIME := 6.0
const OVERCLOCK_TIME := 10.0
const OVERCLOCK_COOLDOWN := 20.0
const OVERCLOCK_HEAT := 15.0
const RUSH_TIME := 15.0
const DUST_HEAT := 12.0
const SURGE_LOAD := 0.85       # power surge crashes the PC above this PSU load
const SAVE_PATH := "user://overclocked_save.json"
const SAVE_INTERVAL := 5.0

var money := 0.0
var tiers := {}                # slot -> installed tier (0 = empty/stock)
var job := 0                   # index into JOBS
var heat := BASE_HEAT          # shown temperature, moves toward the target
var overclock_left := 0.0
var overclock_cooldown := 0.0
var rush_left := 0.0
var crash_left := 0.0
var dusty := false
var event_timer := 45.0
var elapsed := 0.0
var generation := 1
var perks := {"earn": 0, "discount": 0, "cool": 0}
var best_time := 0.0
var won := false
var message_time := 0.0
var save_timer := 0.0

# UI references
var money_label: Label
var rate_label: Label
var gen_label: Label
var power_bar: ProgressBar
var power_label: Label
var heat_bar: ProgressBar
var heat_label: Label
var heat_fill: StyleBoxFlat
var status_label: Label
var effects_label: Label
var oc_button: Button
var job_buttons := []
var message_label: Label
var case_button: Button
var case_hint: Label
var dust_button: Button
var slot_boxes := {}
var slot_labels := {}
var shop_buttons := {}
var win_panel: PanelContainer
var win_label: Label


func _ready() -> void:
	randomize()
	_reset_run()
	_build_ui()
	_load_game()
	_update_ui()


func _reset_run() -> void:
	money = 0.0
	for slot in SLOT_ORDER:
		tiers[slot] = 0
	job = 0
	heat = BASE_HEAT
	overclock_left = 0.0
	overclock_cooldown = 0.0
	rush_left = 0.0
	crash_left = 0.0
	dusty = false
	event_timer = 45.0
	elapsed = 0.0
	won = false


func _process(delta: float) -> void:
	if won:
		return
	elapsed += delta
	if overclock_left > 0.0:
		overclock_left = max(0.0, overclock_left - delta)
	elif overclock_cooldown > 0.0:
		overclock_cooldown = max(0.0, overclock_cooldown - delta)
	rush_left = max(0.0, rush_left - delta)
	if crash_left > 0.0:
		crash_left = max(0.0, crash_left - delta)
		if crash_left == 0.0:
			_show_message("PC rebooted. Back to work!")

	heat = move_toward(heat, target_heat(), 8.0 * delta)
	if crash_left == 0.0 and heat >= cool_limit() + CRASH_MARGIN:
		_crash("OVERHEAT! The PC shut down to protect itself. Get better cooling or pick a cooler job.")

	event_timer -= delta
	if event_timer <= 0.0:
		_random_event()
		event_timer = randf_range(40.0, 70.0)

	money += per_second() * multiplier() * delta

	if message_time > 0.0:
		message_time -= delta
		if message_time <= 0.0:
			message_label.text = ""
	save_timer += delta
	if save_timer >= SAVE_INTERVAL:
		_save_game()
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
	return float(part("Cooling").get("limit", BASE_COOL_LIMIT)) + 10.0 * perks["cool"]


func target_heat() -> float:
	if crash_left > 0.0:
		return BASE_HEAT   # PC is off and cools down
	var total := BASE_HEAT + float(JOBS[job]["heat"])
	for slot in SLOT_ORDER:
		total += float(part(slot).get("heat", 0))
	if overclock_left > 0.0:
		total += OVERCLOCK_HEAT
	if dusty:
		total += DUST_HEAT
	return total


func is_throttled() -> bool:
	return heat > cool_limit()


func multiplier() -> float:
	if crash_left > 0.0:
		return 0.0
	var m: float = JOBS[job]["mult"] * (1.0 + 0.5 * perks["earn"])
	if overclock_left > 0.0:
		m *= 2.0
	if rush_left > 0.0:
		m *= 3.0
	if is_throttled():
		m *= 0.5
	return m


func part_cost(slot: String, tier_index: int) -> float:
	return float(PARTS[slot][tier_index]["cost"]) * pow(0.8, perks["discount"])


func overclock_unlocked() -> bool:
	return tiers["Cooling"] >= 1


func job_unlocked(i: int) -> bool:
	var req: Dictionary = JOBS[i]["req"]
	for slot in req:
		if tiers[slot] < req[slot]:
			return false
	return true


func job_req_text(i: int) -> String:
	var req: Dictionary = JOBS[i]["req"]
	var parts_txt := PackedStringArray()
	for slot in req:
		parts_txt.append("%s T%d" % [slot, req[slot]])
	return ", ".join(parts_txt)


## Returns "" if the next tier of this slot can be bought, otherwise the reason.
func buy_block_reason(slot: String) -> String:
	var t: int = tiers[slot]
	if t >= MAX_TIER:
		return "maxed"
	var next: Dictionary = PARTS[slot][t]
	if slot != "PSU":
		var new_watts := total_watts() - int(part(slot).get("watts", 0)) + int(next.get("watts", 0))
		if new_watts > psu_capacity():
			return "power"
	if money < part_cost(slot, t):
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
	var t: int = tiers[slot]
	var next_part: Dictionary = PARTS[slot][t]
	money -= part_cost(slot, t)
	tiers[slot] = t + 1
	var msg := "Installed %s!" % next_part["name"]
	if slot == "Cooling" and t == 0:
		msg += " OVERCLOCK unlocked."
	for i in range(1, JOBS.size()):
		if job_unlocked(i) and not _job_unlocked_with(i, slot, t):
			msg += " New job unlocked: %s." % JOBS[i]["name"]
	_show_message(msg)
	_check_win()
	_save_game()


## Was job i unlocked before `slot` went from tier `old_tier` up by one?
func _job_unlocked_with(i: int, slot: String, old_tier: int) -> bool:
	var req: Dictionary = JOBS[i]["req"]
	for s in req:
		var have: int = old_tier if s == slot else tiers[s]
		if have < req[s]:
			return false
	return true


func choose_job(i: int) -> void:
	if not job_unlocked(i) or won:
		return
	job = i
	_show_message("Now running: %s (x%s earnings, +%d °C)." % [JOBS[i]["name"], _fmt(JOBS[i]["mult"]), JOBS[i]["heat"]])


func click_pc() -> void:
	if won:
		return
	if crash_left > 0.0:
		_spawn_float_text("rebooting...", get_global_mouse_position(), Color(0.7, 0, 0))
		return
	var gain := per_click() * multiplier()
	money += gain
	_spawn_float_text("+$%s" % _fmt(gain), get_global_mouse_position(), Color(0, 0.45, 0))


func overclock() -> void:
	if not overclock_unlocked() or overclock_left > 0.0 or overclock_cooldown > 0.0 or crash_left > 0.0 or won:
		return
	overclock_left = OVERCLOCK_TIME
	overclock_cooldown = OVERCLOCK_COOLDOWN
	_show_message("Overclocked! x2 earnings for 10 s, but heat goes up.")


func clean_dust() -> void:
	dusty = false
	_show_message("Dust cleaned. Temperatures back to normal.")


func _crash(text: String) -> void:
	crash_left = CRASH_TIME
	overclock_left = 0.0
	_show_message(text)


func _random_event() -> void:
	var options := ["rush", "surge"]
	if not dusty:
		options.append("dust")
	match options[randi() % options.size()]:
		"rush":
			rush_left = RUSH_TIME
			_show_message("RUSH ORDER! A client pays triple for the next 15 s. Click fast!")
		"dust":
			dusty = true
			_show_message("Dust build-up! The PC runs +12 °C hotter until you clean it.")
		"surge":
			if total_watts() > SURGE_LOAD * psu_capacity():
				_crash("POWER SURGE! Your PSU was running near its limit and the PC crashed.")
			else:
				_show_message("Power surge - your PSU had enough headroom. No damage.")


func _check_win() -> void:
	for slot in SLOT_ORDER:
		if tiers[slot] < MAX_TIER:
			return
	won = true
	if best_time == 0.0 or elapsed < best_time:
		best_time = elapsed
	win_label.text = "RIG MAXED OUT!  (Generation %d)\n\nTime: %s    Best: %s\n\nNEW BUILD: sell this rig and start the next generation.\nYou keep one permanent bonus - pick it:" % [generation, _fmt_time(elapsed), _fmt_time(best_time)]
	win_panel.visible = true
	_update_ui()


func new_build(perk: String) -> void:
	perks[perk] += 1
	generation += 1
	_reset_run()
	win_panel.visible = false
	_show_message("Generation %d started with %s. Back to the old office PC!" % [generation, PERKS[perk]["name"]])
	_save_game()
	_update_ui()


# ---------- save / load ----------

func _save_game() -> void:
	save_timer = 0.0
	var data := {
		"money": money, "tiers": tiers, "job": job, "elapsed": elapsed,
		"generation": generation, "perks": perks, "best_time": best_time,
		"dusty": dusty, "won": won,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	money = float(data.get("money", 0.0))
	var saved_tiers: Dictionary = data.get("tiers", {})
	for slot in SLOT_ORDER:
		tiers[slot] = clampi(int(saved_tiers.get(slot, 0)), 0, MAX_TIER)
	var saved_perks: Dictionary = data.get("perks", {})
	for p in perks:
		perks[p] = int(saved_perks.get(p, 0))
	job = clampi(int(data.get("job", 0)), 0, JOBS.size() - 1)
	if not job_unlocked(job):
		job = 0
	elapsed = float(data.get("elapsed", 0.0))
	generation = int(data.get("generation", 1))
	best_time = float(data.get("best_time", 0.0))
	dusty = bool(data.get("dusty", false))
	heat = BASE_HEAT
	_show_message("Save loaded - welcome back! (Generation %d)" % generation)
	if bool(data.get("won", false)):
		_check_win()


func reset_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	generation = 1
	best_time = 0.0
	for p in perks:
		perks[p] = 0
	save_timer = -1000.0
	get_tree().reload_current_scene()


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
	var title := _label("OVERCLOCKED  (prototype)", 28)
	title.position = Vector2(40, 30)
	add_child(title)
	var reset := Button.new()
	reset.text = "Reset save"
	reset.add_theme_font_size_override("font_size", 18)
	reset.position = Vector2(40, 80)
	reset.pressed.connect(reset_save)
	add_child(reset)
	money_label = _label("", 48)
	money_label.position = Vector2(640, 20)
	add_child(money_label)
	rate_label = _label("", 26)
	rate_label.position = Vector2(640, 85)
	add_child(rate_label)
	gen_label = _label("", 22)
	gen_label.position = Vector2(1420, 30)
	add_child(gen_label)

	# --- left panel: gauges, overclock, jobs ---
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _box_style(Color(0.9, 0.9, 0.9)))
	left.position = Vector2(40, 140)
	left.size = Vector2(440, 820)
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)

	lv.add_child(_label("POWER", 26))
	power_bar = ProgressBar.new()
	power_bar.custom_minimum_size = Vector2(400, 30)
	power_bar.show_percentage = false
	lv.add_child(power_bar)
	power_label = _label("", 24)
	lv.add_child(power_label)

	lv.add_child(_label("HEAT", 26))
	heat_bar = ProgressBar.new()
	heat_bar.custom_minimum_size = Vector2(400, 30)
	heat_bar.show_percentage = false
	heat_bar.max_value = 180
	heat_fill = StyleBoxFlat.new()
	heat_bar.add_theme_stylebox_override("fill", heat_fill)
	lv.add_child(heat_bar)
	heat_label = _label("", 24)
	lv.add_child(heat_label)
	status_label = _label("", 24)
	lv.add_child(status_label)
	effects_label = _label("", 20)
	effects_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	effects_label.custom_minimum_size = Vector2(400, 56)
	lv.add_child(effects_label)

	oc_button = Button.new()
	oc_button.custom_minimum_size = Vector2(400, 66)
	oc_button.add_theme_font_size_override("font_size", 24)
	oc_button.pressed.connect(overclock)
	lv.add_child(oc_button)

	lv.add_child(_label("JOBS", 26))
	for i in JOBS.size():
		var jb := Button.new()
		jb.custom_minimum_size = Vector2(400, 62)
		jb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		jb.add_theme_font_size_override("font_size", 18)
		jb.pressed.connect(choose_job.bind(i))
		lv.add_child(jb)
		job_buttons.append(jb)

	# --- center: clickable PC case with part slots ---
	case_button = Button.new()
	case_button.position = Vector2(520, 140)
	case_button.size = Vector2(860, 820)
	case_button.add_theme_stylebox_override("normal", _box_style(Color(0.42, 0.42, 0.42)))
	case_button.add_theme_stylebox_override("hover", _box_style(Color(0.47, 0.47, 0.47)))
	case_button.add_theme_stylebox_override("pressed", _box_style(Color(0.38, 0.38, 0.38)))
	case_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	case_button.pressed.connect(click_pc)
	add_child(case_button)

	case_hint = _label("CLICK THE CASE TO RUN JOBS", 26)
	case_hint.add_theme_color_override("font_color", Color(1, 1, 1))
	case_hint.position = Vector2(40, 20)
	case_hint.size = Vector2(780, 40)
	case_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	case_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	case_button.add_child(case_hint)

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

	dust_button = Button.new()
	dust_button.text = "DUST BUILD-UP (+12 °C)  -  click here to clean"
	dust_button.add_theme_stylebox_override("normal", _box_style(Color(0.75, 0.6, 0.4), Color(0.4, 0.3, 0.1)))
	dust_button.add_theme_stylebox_override("hover", _box_style(Color(0.85, 0.7, 0.5), Color(0.4, 0.3, 0.1)))
	dust_button.position = Vector2(130, 740)
	dust_button.size = Vector2(600, 60)
	dust_button.pressed.connect(clean_dust)
	case_button.add_child(dust_button)

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

	# --- win / New Build panel ---
	win_panel = PanelContainer.new()
	win_panel.add_theme_stylebox_override("panel", _box_style(Color(1, 1, 0.75)))
	win_panel.position = Vector2(510, 260)
	win_panel.size = Vector2(900, 560)
	win_panel.visible = false
	add_child(win_panel)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 16)
	win_panel.add_child(wv)
	win_label = _label("", 28)
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wv.add_child(win_label)
	for key in PERKS:
		var pb := Button.new()
		pb.text = "%s  -  %s" % [PERKS[key]["name"], PERKS[key]["desc"]]
		pb.custom_minimum_size = Vector2(860, 64)
		pb.pressed.connect(new_build.bind(key))
		wv.add_child(pb)


const TIER_COLORS := [Color(0.66, 0.66, 0.66), Color(0.78, 0.9, 0.78), Color(0.72, 0.84, 1.0), Color(1.0, 0.86, 0.45)]


func _update_ui() -> void:
	var m := multiplier()
	money_label.text = "$%s" % _fmt(money)
	rate_label.text = "$%s per click   |   $%s per second" % [_fmt(per_click() * m), _fmt(per_second() * m)]
	var perk_txt := PackedStringArray()
	for key in PERKS:
		if perks[key] > 0:
			perk_txt.append("%s x%d" % [PERKS[key]["name"], perks[key]])
	gen_label.text = "Generation %d   Time %s\n%s" % [generation, _fmt_time(elapsed), "Bonuses: " + ", ".join(perk_txt) if perk_txt.size() > 0 else "No New Build bonuses yet"]

	var w := total_watts()
	var cap := psu_capacity()
	power_bar.max_value = cap
	power_bar.value = w
	power_label.text = "%d / %d W  (%d%% load)" % [w, cap, int(100.0 * w / cap)]

	heat_bar.value = heat
	heat_label.text = "%d / %d °C limit (crash at %d)" % [int(round(heat)), int(cool_limit()), int(cool_limit() + CRASH_MARGIN)]
	if crash_left > 0.0:
		status_label.text = "CRASHED - rebooting %ds" % int(ceil(crash_left))
		heat_fill.bg_color = Color(0.5, 0.5, 0.5)
		status_label.modulate = Color(0.8, 0, 0)
	elif is_throttled():
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

	var effects := PackedStringArray(["Job: %s x%s" % [JOBS[job]["name"], _fmt(JOBS[job]["mult"])]])
	if rush_left > 0.0:
		effects.append("RUSH ORDER x3 %ds" % int(ceil(rush_left)))
	if dusty:
		effects.append("Dusty +12 °C")
	effects_label.text = "   ".join(effects)

	if not overclock_unlocked():
		oc_button.text = "OVERCLOCK (locked: buy a cooler)"
		oc_button.disabled = true
	elif overclock_left > 0.0:
		oc_button.text = "OVERCLOCK ACTIVE  %ds" % int(ceil(overclock_left))
		oc_button.disabled = true
	elif overclock_cooldown > 0.0:
		oc_button.text = "Overclock cooldown  %ds" % int(ceil(overclock_cooldown))
		oc_button.disabled = true
	else:
		oc_button.text = "OVERCLOCK (x2 for 10 s, +15 °C)"
		oc_button.disabled = won or crash_left > 0.0

	for i in JOBS.size():
		var jb: Button = job_buttons[i]
		var j: Dictionary = JOBS[i]
		if not job_unlocked(i):
			jb.text = "LOCKED: %s\nneeds %s" % [j["name"], job_req_text(i)]
			jb.disabled = true
		else:
			jb.text = "%s%s\nx%s earnings, +%d °C" % ["> " if i == job else "", j["name"], _fmt(j["mult"]), j["heat"]]
			jb.disabled = won
		jb.modulate = Color(0.75, 1.0, 0.75) if i == job else Color(1, 1, 1)

	if crash_left > 0.0:
		case_hint.text = "CRASHED - REBOOTING %ds" % int(ceil(crash_left))
	else:
		case_hint.text = "CLICK THE CASE TO RUN JOBS"
	dust_button.visible = dusty and not won

	for slot in SLOT_ORDER:
		var t: int = tiers[slot]
		slot_boxes[slot].add_theme_stylebox_override("panel", _box_style(TIER_COLORS[t]))
		if t == 0:
			slot_labels[slot].text = "%s\n(stock / empty)" % slot
		else:
			slot_labels[slot].text = "%s  T%d\n%s" % [slot, t, part(slot)["name"]]

		var b: Button = shop_buttons[slot]
		if t >= MAX_TIER:
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
		b.text = "%s T%d: %s\n$%s\n%s" % [slot, t + 1, next["name"], _fmt(part_cost(slot, t)), stats]
		if reason == "power":
			b.text += "\nNEEDS BIGGER PSU"
			b.modulate = Color(1, 0.6, 0.6)
			b.disabled = false   # clickable so the player gets the explanation
		else:
			b.modulate = Color(1, 1, 1)
			b.disabled = reason != "" or won


func _show_message(text: String) -> void:
	message_label.text = text
	message_time = 5.0


func _spawn_float_text(text: String, pos: Vector2, color: Color) -> void:
	var l := _label(text, 30)
	l.position = pos - Vector2(30, 40)
	l.modulate = color
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 80, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(l.queue_free)


func _fmt_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func _fmt(n: float) -> String:
	if n >= 1000000.0:
		return "%.2fM" % (n / 1000000.0)
	if n >= 10000.0:
		return "%.1fk" % (n / 1000.0)
	if abs(n - round(n)) < 0.05:
		return str(int(round(n)))
	return "%.1f" % n

extends CanvasLayer
## Built-in PICO-8 cheat sheet: the API at a glance, grouped the way the
## well-known community cheat sheets are (text only; nothing is copied from
## them). Tap an entry for its description. Function entries come from
## physkb_api_docs.gd, so the two never disagree.

const Docs = preload("res://physkb/physkb_api_docs.gd")
const A = preload("res://physkb/physkb_actions.gd")

const COL_USAGE := Color(1.0, 0.925, 0.153)
const COL_TEXT := Color(0.8, 0.8, 0.8)
const COL_HEADER := Color(1.0, 0.467, 0.659) # PICO-8 pink
const COL_HINT := Color(0.5, 0.5, 0.5)

## The 16 standard colours.
const PALETTE := [
	["black", "000000"], ["dark-blue", "1d2b53"], ["dark-purple", "7e2553"], ["dark-green", "008751"],
	["brown", "ab5236"], ["dark-grey", "5f574f"], ["light-grey", "c2c3c7"], ["white", "fff1e8"],
	["red", "ff004d"], ["orange", "ffa300"], ["yellow", "ffec27"], ["green", "00e436"],
	["blue", "29adff"], ["lavender", "83769c"], ["pink", "ff77a8"], ["light-peach", "ffccaa"],
]

## [title, entries]. An entry is a name from Docs.DOCS, or [text, description].
const SECTIONS := [
	["PROGRAM", ["_init", "_update", "_update60", "_draw"]],
	["GRAPHICS", ["cls", "pset", "pget", "line", "rect", "rectfill", "rrect", "rrectfill", "circ", "circfill",
		"oval", "ovalfill", "spr", "sspr", "sget", "sset", "fget", "fset", "print", "cursor", "color",
		"pal", "palt", "fillp", "camera", "clip", "tline", "flip"]],
	["MAP", ["map", "mget", "mset", "fget"]],
	["INPUT", ["btn", "btnp",
		["0 left  1 right  2 up  3 down  4 O  5 X", "Button numbers. Player is 0 (default) to 7."],
		["stat(34) buttons  stat(32),stat(33) x,y", "Mouse, after poke(0x5f2d, 1)."],
		["stat(30) key pressed?  stat(31) which", "Keyboard, after poke(0x5f2d, 1)."]]],
	["SOUND", ["sfx", "music"]],
	["TABLES", ["add", "del", "deli", "count", "all", "foreach", "pairs", "ipairs", "pack", "unpack", "select",
		["t = {1, 2, x=3}   #t   t[1]   t.x", "Tables start at index 1. #t is the length of the sequence."],
		"setmetatable", "getmetatable", "rawget", "rawset"]],
	["MATH", ["max", "min", "mid", "flr", "ceil", "abs", "sgn", "sqrt", "sin", "cos", "atan2", "rnd", "srand",
		["numbers: -32768 .. 32767.9999", "16:16 fixed point. Overflow wraps around."]]],
	["STRINGS", ["sub", "tostr", "tonum", "chr", "ord", "split", "type",
		["\"a\"..\"b\"   #s   s[i]", "Join strings with .. ; #s is the length; s[i] is one character."]]],
	["OPERATORS", [
		["+  -  *  /  \\  %  ^", "\\ is integer division, % the remainder, ^ power."],
		["<  >  <=  >=  ==  !=  ~=", "Comparisons. != and ~= both mean not equal."],
		["and  or  not", "Logic. Only false and nil count as false."],
		["&  |  ^^  ~  <<  >>  >>>  <<>  >><", "Bitwise and, or, xor, not, shifts and rotates."],
		["+=  -=  *=  /=  \\=  %=  ^=  ..=", "Update a variable in place."],
		["@addr  %addr  $addr", "peek, peek2 and peek4 shorthands."],
		["?\"text\"", "Shorthand for print."],
		["-- comment   --[[ block ]]", "Comments."]]],
	["FLOW", ["if", "for", "while", "repeat", "function", "local", "return", "break", "goto",
		["if (cond) statement", "One-line if without then/end. Also works for while."],
		["for i=10,1,-1 do ... end", "Counting down needs a negative step."]]],
	["MEMORY", ["peek", "poke", "peek2", "poke2", "peek4", "poke4", "memcpy", "memset", "reload", "cstore",
		["0x0000 sprites   0x1000 shared", "Sprite sheet; its lower half is shared with the map."],
		["0x2000 map       0x3000 flags", "Map (upper half) and sprite flags."],
		["0x3100 music     0x3200 sfx", "Music patterns and sound effects."],
		["0x4300 user      0x5600 font", "General use, and the custom font."],
		["0x5e00 cartdata  0x5f00 draw state", "Persistent data, and draw state (camera, palette, ...)."],
		["0x5f40 hardware  0x5f80 gpio", "Hardware state and GPIO pins."],
		["0x6000 screen    0x8000 user", "Screen (8k), then 32k more for general use."]]],
	["CART DATA", ["cartdata", "dget", "dset", "menuitem", "stat", "time", "extcmd", "printh", "assert", "stop", "trace"]],
	["COROUTINES", ["cocreate", "coresume", "costatus", "yield"]],
	["CONSOLE", [
		["load name    save name", "Load or save a cart. save name.p8.png saves a picture cart."],
		["run    resume    reboot", "Run the cart, continue after stop, or restart PICO-8."],
		["ls    cd dir    mkdir dir", "Browse the carts folder."],
		["folder    splore    help", "Open the carts folder, the cart browser, or the help."],
		["export name.html / .bin / .png / .wav", "Export the cart, sprite sheet or sounds."],
		["import name.png / .wav", "Import a sprite sheet or sound."],
		["info    keyconfig    install_demos", "Cart statistics, key setup, demo carts."]]],
]

var _font: int = 12
var _margin: MarginContainer
var _flow: HFlowContainer
var _title: Label
var _detail: Label
var _btn_close: Button

func _ready() -> void:
	layer = 16
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 1)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(_margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_margin.add_child(vbox)

	_title = Label.new()
	_title.text = "📖 PICO-8 Cheat Sheet"
	vbox.add_child(_title)
	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_flow)

	vbox.add_child(HSeparator.new())
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.text = "Tap an entry for details."
	_detail.add_theme_color_override("font_color", COL_TEXT)
	vbox.add_child(_detail)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(footer)
	_btn_close = Button.new()
	_btn_close.text = "✖ Close"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.15, 0.15)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.45, 0.45, 0.45)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(10)
	_btn_close.add_theme_stylebox_override("normal", sb)
	_btn_close.pressed.connect(queue_free)
	footer.add_child(_btn_close)

	_rebuild()
	get_tree().root.size_changed.connect(_rebuild)
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.set_input_blocked(true)

func _exit_tree() -> void:
	# Leave input blocked if the keyboard screen underneath is still open.
	if is_instance_valid(PicoVideoStreamer.instance) and not get_tree().root.has_node("PhysKbEditor"):
		PicoVideoStreamer.instance.set_input_blocked(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		queue_free()

func _rebuild() -> void:
	var vp := get_viewport().get_visible_rect().size
	_font = int(max(12, min(vp.x, vp.y) * 0.03))
	for side in ["margin_top", "margin_bottom"]:
		_margin.add_theme_constant_override(side, int(vp.y * 0.04))
	for side in ["margin_left", "margin_right"]:
		_margin.add_theme_constant_override(side, int(vp.x * 0.04))
	_title.add_theme_font_size_override("font_size", int(_font * 1.1))
	_detail.add_theme_font_size_override("font_size", int(_font * 0.75))
	_detail.custom_minimum_size.y = _font * 2.6
	_btn_close.add_theme_font_size_override("font_size", _font)

	for c in _flow.get_children():
		_flow.remove_child(c)
		c.queue_free()
	# As many columns as fit comfortably: one on a phone held upright.
	var avail: float = vp.x * 0.92
	var cols: int = clamp(int(avail / (_font * 26.0)), 1, 3)
	var gap := int(_font * 0.8)
	_flow.add_theme_constant_override("h_separation", gap)
	_flow.add_theme_constant_override("v_separation", gap)
	var col_w: float = (avail - gap * (cols - 1)) / cols - 4

	_flow.add_child(_palette_card(col_w))
	for sec in SECTIONS:
		_flow.add_child(_card(sec[0], sec[1], col_w))
	_flow.add_child(_shortcut_card(col_w))

func _card_box(title: String, width: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = width
	box.add_theme_constant_override("separation", int(_font * 0.15))
	var h := Label.new()
	h.text = title
	h.add_theme_font_size_override("font_size", int(_font * 0.9))
	h.add_theme_color_override("font_color", COL_HEADER)
	box.add_child(h)
	return box

func _entry(text: String, detail: String, color: Color) -> Button:
	var b := Button.new()
	b.flat = true
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(_font * 0.62))
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	var none := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, none)
	b.pressed.connect(func(): _detail.text = text + "\n" + detail)
	return b

func _card(title: String, entries: Array, width: float) -> Control:
	var box := _card_box(title, width)
	for e in entries:
		if e is String:
			if Docs.DOCS.has(e):
				box.add_child(_entry(Docs.DOCS[e][0], Docs.DOCS[e][1], COL_USAGE))
		else:
			box.add_child(_entry(e[0], e[1], COL_TEXT))
	return box

func _palette_card(width: float) -> Control:
	var box := _card_box("COLOURS", width)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(_font * 0.5))
	box.add_child(grid)
	for i in PALETTE.size():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sw := ColorRect.new()
		sw.color = Color(PALETTE[i][1])
		sw.custom_minimum_size = Vector2(_font * 1.1, _font * 0.9)
		row.add_child(sw)
		var l := Label.new()
		l.text = "%d %s" % [i, PALETTE[i][0]]
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", int(_font * 0.62))
		l.add_theme_color_override("font_color", COL_TEXT)
		row.add_child(l)
		grid.add_child(row)
	return box

## PICO-8's shortcuts with the combinations currently assigned to them.
func _shortcut_card(width: float) -> Control:
	var box := _card_box("SHORTCUTS", width)
	for a in PhysKb.actions:
		if a.group != A.G_SHORTCUTS and a.id != "esc":
			continue
		var c: int = PhysKb.get_binding(a.id)
		var detail := "Not assigned." if c == 0 else "Change it in Keyboard Mapping."
		if a.has("native"):
			detail = "PICO-8's own combination is %s. %s" % [A.combo_text(a.native), detail]
		box.add_child(_entry("%s: %s" % [a.label, A.combo_text(c)], detail, COL_TEXT))
	return box

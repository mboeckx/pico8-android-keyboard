extends CanvasLayer
## Built-in PICO-8 cheat sheet. A text version that follows the sections of
## the community "PICO-8 Cheat Sheet" poster, kept up to date with the current
## API. Tap an entry for its description. Function entries come from
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

## [title, entries], in the order of the community "PICO-8 Cheat Sheet".
## An entry is a name from Docs.DOCS, or [text, description].
const SECTIONS := [
	["COMMANDLINE", [
		["help", "List the console commands."],
		["save <file_name>.p8", "Save the cart. Use .p8.png for a picture cart."],
		["load <file_name>.p8", "Load a cart. In code: load(\"name\")."],
		["run", "Run the loaded cart."],
		["splore", "Open the cart browser."],
		["folder", "Open the carts folder on the host."],
		["ls() / dir", "List the files in the current folder."],
		["cd <dir_name>   mkdir <dir_name>", "Change folder; create a folder."],
		["import x.png   export x.bin / x.html", "Import a sprite sheet; export the cart as a binary or web page."],
		["cls   info", "Clear the console; show cart statistics (tokens, size)."],
		["shutdown   reboot", "Quit PICO-8; restart it."]]],
	["VARS AND TYPES", [
		["a=nil", "nil is 'no value'. Unassigned variables are nil."],
		["x=23", "Numbers are 16:16 fixed point: -32768 to 32767.9999."],
		["local x=\"text\"", "local limits the variable to the current block."],
		["t={name=\"joe\",age=\"32\"}", "A table with named fields: t.name, t.age."]]],
	["OPERATORS", [
		["+ - * / ^ % =", "Arithmetic and assignment. \\ is integer division."],
		["+= -= *= /= %= ^=", "Update a variable in place."],
		["< > <= >= ~= == !=", "Comparisons. ~= and != both mean not equal."],
		["#list   \"a\"..\"b\"", "Length of a table or string; join strings."],
		["and  or  not", "Logic. Only false and nil count as false."],
		["&  |  ^^  ~  <<  >>  >>>  <<>  >><", "Bitwise and, or, xor, not, shifts and rotates."]]],
	["FUNCTIONS", [
		["function add(a,b)", "Define a function with two parameters."],
		[" return a+b", "Hand a value back to the caller."],
		["end", ""]]],
	["IF STATEMENT", [
		["if (x==33) then", "Brackets are optional when 'then' is used."],
		[" print(\"well done\")", ""],
		["elseif (x>33) then", "Another condition to try."],
		[" print(\"please try again\")", ""],
		["else break end", "else runs when nothing matched; break leaves a loop."]]],
	["TABLES", [
		["t={a=\"x\",b=1}   t={1,2,3,4}", "Named fields, or a list."],
		"add", "del",
		["count(t) or #t", "Number of items in the list."],
		["print(t[1]) --1 based!!", "Lists start at index 1."],
		"all", "foreach", "pairs"]],
	["LOOPS", [
		["for i=1,10 do --count up", "i runs from 1 to 10."],
		[" print(i)", ""],
		["end", ""],
		["for a=10,0,-2 do --count down", "The third number is the step."],
		["for s in all(ships) do --array", "Every item of a list, in order."],
		[" print(s.name)", ""],
		["for k,v in pairs(m) do --table", "Every key and value of a table."],
		[" print(\"k:\"..k..\",v:\"..v)", ""],
		["repeat ... until <condition>", "Runs the block at least once."],
		["while <condition> do ... end", "Runs the block while the condition holds."]]],
	["SHRINK CODE", [
		["--limits: token 8192", "A cart may use at most 8192 tokens."],
		["--character 65535", "And at most 65535 characters of code."],
		["if (value) do_thing()", "One-line if: no then/end needed."],
		["foreach(enemies,t_damage)", "One-line version of a for-in-all loop."],
		["size=#table", "# costs fewer tokens than count()."],
		["a=3 --short var name", "Shorter names save characters, not tokens."],
		["a+=3 --shorter operation", "Fewer tokens than a=a+3."],
		["--remove spaces, comments", "They count towards the character limit."],
		["t=true f=false --constants", "Reuse constants through short variables."],
		["function md(a,b) return a*b,a/b end", "A function can return several values."],
		["a,b=md(8,4)", "Take more than one value."]]],
	["SHORTCUTS", [
		["save: ctrl+s", ""],
		["change mode: esc", "Switch between the console and the editor."],
		["reload and run: ctrl+r", ""],
		["fullscreen: alt+enter", ""],
		["screenshot: f6   cart image: f7", "The cart image is the label of a .p8.png cart."],
		["start video: f8   save video: f9", "Saves a GIF."],
		["pause/resume: p / enter", ""],
		["undo: ctrl+z   redo: ctrl+y", "Text editor."],
		["search: ctrl+f   next: ctrl+g", "Text editor."],
		["next/prev func: alt+up/down", "Text editor."],
		["jump to start/end: ctrl+up/down", "Text editor."],
		["indent selection: tab", "Shift+Tab removes the indent."]]],
	["CARTRIDGE DATA", ["cartdata", "dget", "dset"]],
	["RAM MEMORY LAYOUT", [
		["0x0000 gfx", "Sprite sheet, sprites 0-127."],
		["0x1000 gfx2/map2 (shared)", "Sprites 128-255, shared with the lower half of the map."],
		["0x2000 map", "Upper half of the map."],
		["0x3000 gfx_props", "Sprite flags."],
		["0x3100 song", "Music patterns."],
		["0x3200 sfx", "Sound effects."],
		["0x4300 userdata", "General use."],
		["0x5e00 persistent cart data (256 bytes)", "What dget/dset read and write."],
		["0x5f00 draw state", "Camera, clip, palette, cursor and so on."],
		["0x5f40 hardware state", "Sound and input hardware settings."],
		["0x5f80 gpio pins (128 bytes)", ""],
		["0x6000 screen (8k)", "One nibble per pixel."]]],
	["MEMORY MANIPULATION", ["cstore", "memcpy", "memset", "reload", "peek", "poke", "peek4", "poke4"]],
	["COROUTINES", ["cocreate", "coresume", "costatus", "yield"]],
	["SPECIAL CALLBACKS", ["_init", "_update", "_update60", "_draw"]],
	["SPRITES", ["spr", "sspr", "sget", "sset"]],
	["COLORS", ["pal", "palt"]],
	["PIXELS", ["pget", "pset"]],
	["SPRITE FLAG", ["fget", "fset"]],
	["SHAPES", ["rect", "rectfill", "circ", "circfill", "oval", "ovalfill", "line"]],
	["SCREEN", ["camera", "clip", "color", "cls",
		["x: 0..127 right   y: 0..127 down", "The screen is 128x128. (0,0) is the top-left corner."]]],
	["MAP", ["mget", "mset", "map"]],
	["MATH", ["band", "bnot", "bor", "bxor", "shl", "shr", "lshr", "cos", "sin", "atan2",
		"flr", "ceil", "abs", "sgn", "max", "mid", "min", "sqrt", "rnd", "srand"]],
	["CONTROLS", [
		["0 left  1 right  2 up  3 down  4 O  5 X", "Button numbers for btn and btnp."],
		["player 1: arrows, z/x, c/v, n/m", "Keyboard keys PICO-8 reads for player 1."],
		["player 2: s f e d, lshift/a, tab/q", "Keyboard keys for player 2."],
		["pause: p / enter", ""],
		"btn", "btnp"]],
	["STRING MANIPULATION", [
		["#string --length", ""],
		["\"ten\"..4 --concatenation", "Numbers are converted when joined."],
		"sub",
		["\"123.45\"+0 --cast to number", ""]]],
	["TYPES", ["type", "tostr", "tonum"]],
	["SOUND", ["sfx", "music"]],
	["TRACKER", [
		["z s x d c v g b h n j m  (octave)", "Piano layout on the keyboard, lower row."],
		["q 2 w 3 e r 5 t 6 y 7 u  (octave+1)", "Piano layout, upper row."],
		["note: tone octave instrument volume effect", "The five columns of a tracker note."],
		["effects: 0 none  1 slide  2 vibrato", ""],
		["3 drop (drum kick)  4 fade in  5 fade out", ""],
		["6 fast arpeggio  7 slow arpeggio (4 notes)", ""]]],
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
	b.pressed.connect(func(): _detail.text = text.strip_edges() + ("\n" + detail if not detail.is_empty() else ""))
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
	var box := _card_box("COLOR NUMBERS", width)
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
	var box := _card_box("YOUR KEY BINDINGS", width)
	for a in PhysKb.actions:
		if a.group != A.G_SHORTCUTS and a.id != "esc":
			continue
		var c: int = PhysKb.get_binding(a.id)
		var detail := "Not assigned." if c == 0 else "Change it in Keyboard Mapping."
		if a.has("native"):
			detail = "PICO-8's own combination is %s. %s" % [A.combo_text(a.native), detail]
		box.add_child(_entry("%s: %s" % [a.label, A.combo_text(c)], detail, COL_TEXT))
	return box

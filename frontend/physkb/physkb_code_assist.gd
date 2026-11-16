extends CanvasLayer
## Code editor helpers, drawn over the PICO-8 display:
##  - touch and hold a word in the code editor -> short documentation
##  - while typing -> name suggestions (tap one, or use the "Accept
##    suggestion" binding) and a one-line usage hint
##
## PICO-8 only gives us a 128x128 picture, so "the word under the finger" is
## read back from the frame by matching the 3x5 font. What is being typed is
## followed from the key events PhysKb sees.

const Docs = preload("res://physkb/physkb_api_docs.gd")
const Glyphs = preload("res://physkb/physkb_font.gd")

const HOLD_MS := 450
const HINT_MS := 6000
const DOC_MS := 5000
const TOAST_MS := 1200
const UNKNOWN := "\u0001" # a cell that is not a recognisable glyph
const COL_USAGE := Color(1.0, 0.925, 0.153) # PICO-8 yellow
const COL_TEXT := Color(0.9, 0.9, 0.9)

enum Mode {NONE, HINT, USAGE, DOC}

var _panel: PanelContainer
var _chips: HFlowContainer
var _usage: Label
var _desc: Label
var _toast: Label
var _mode: int = Mode.NONE
var _hide_at: int = 0
var _toast_hide_at: int = 0
var _at_top: bool = false
var _font_size: int = 0

var _word: String = ""
var _cands: Array = []

var _touching: bool = false
var _touch_pos: Vector2 = Vector2.ZERO
var _touch_time: int = 0
var _hold_fired: bool = false
var _touch_frame: PackedByteArray # the picture at touch-down, before PICO-8's pointer moves there

func _ready() -> void:
	layer = 5

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)

	_chips = HFlowContainer.new()
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_chips)

	_usage = Label.new()
	_usage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_usage.add_theme_color_override("font_color", COL_USAGE)
	box.add_child(_usage)

	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_color_override("font_color", COL_TEXT)
	box.add_child(_desc)

	_toast = Label.new()
	_toast.visible = false
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_toast)

	_apply_style()
	get_tree().root.size_changed.connect(_apply_style)

func _apply_style() -> void:
	var vp := get_viewport().get_visible_rect().size
	# The app's usual text size, but never too big for the PICO-8 display.
	_font_size = int(max(12, min(vp.x, vp.y) * 0.03))
	var width := _display_rect().size.x
	if width > 0:
		_font_size = int(clamp(width * 0.04, 10, _font_size))
	var pad := int(_font_size * 0.5)
	# Same look as the options menu tooltips.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(pad)
	_panel.add_theme_stylebox_override("panel", style)
	_usage.add_theme_font_size_override("font_size", _font_size)
	_desc.add_theme_font_size_override("font_size", int(_font_size * 0.85))
	_toast.add_theme_font_size_override("font_size", int(_font_size * 1.2))
	_toast.add_theme_constant_override("outline_size", int(_font_size * 0.6))

# ---------------------------------------------------------------- geometry

func _display_rect() -> Rect2:
	var dc: Sprite2D = get_parent().displayContainer
	if dc == null:
		return Rect2()
	var size := Vector2(128, 128) * dc.global_scale
	var pos := dc.global_position
	if dc.centered:
		pos -= size / 2.0
	return Rect2(pos, size)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()

	if _touching and not _hold_fired and now - _touch_time >= HOLD_MS:
		_hold_fired = true
		if PhysKb.hold_docs and PhysKb.in_code_context():
			_show_doc_at(_touch_pos)

	if _mode != Mode.NONE and _hide_at > 0 and now > _hide_at:
		if not (_mode == Mode.DOC and _touching):
			_hide()

	if _toast.visible and now > _toast_hide_at:
		_toast.visible = false

	if _panel.visible:
		var rect := _display_rect()
		_panel.custom_minimum_size.x = rect.size.x
		_panel.size = Vector2(rect.size.x, 0)
		_panel.position = rect.position if _at_top else Vector2(rect.position.x, rect.end.y - _panel.size.y)

func _unhandled_input(event: InputEvent) -> void:
	# Only watches; never consumes, so PICO-8 still gets the touch as a click.
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_touching = true
			_hold_fired = false
			_touch_pos = event.position
			_touch_time = Time.get_ticks_msec()
			_touch_frame = _frame() if PhysKb.hold_docs else PackedByteArray()
			if _mode == Mode.DOC:
				_hide()
			note_break() # a tap moves the editor cursor
		else:
			_touching = false
			if _mode == Mode.DOC:
				_hide_at = Time.get_ticks_msec() + DOC_MS
	elif event is InputEventScreenDrag and event.index == 0:
		var vp := get_viewport().get_visible_rect().size
		if event.position.distance_to(_touch_pos) > min(vp.x, vp.y) * 0.02:
			_touching = false

func _hide() -> void:
	_mode = Mode.NONE
	_panel.visible = false
	_hide_at = 0

func _show(mode: int, usage: String, desc: String, chips: Array, ttl_ms: int) -> void:
	_mode = mode
	_apply_style()
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	for name in chips:
		var b := UIUtils.create_pixel_button(name, int(_font_size * 0.85))
		b.focus_mode = Control.FOCUS_NONE # must never take key focus
		b.pressed.connect(_accept_name.bind(name))
		_chips.add_child(b)
	_chips.visible = not chips.is_empty()
	_usage.text = usage
	_usage.visible = not usage.is_empty()
	_desc.text = desc
	_desc.visible = not desc.is_empty()
	_hide_at = Time.get_ticks_msec() + ttl_ms if ttl_ms > 0 else 0
	_panel.visible = true

func toast(text: String) -> void:
	var rect := _display_rect()
	_toast.text = text
	_toast.size = Vector2(rect.size.x, 0)
	_toast.position = rect.position + Vector2(0, rect.size.y * 0.45)
	_toast.visible = true
	_toast_hide_at = Time.get_ticks_msec() + TOAST_MS

# ------------------------------------------------------- reading the frame

func _frame() -> PackedByteArray:
	var s = get_parent()
	if s._read_index < 0:
		return PackedByteArray()
	return s._buffer_images[s._read_index].get_data()

## Decodes one text row whose top-left cell corner is at (ox, y0).
## Returns [score, text]; unrecognised cells come back as UNKNOWN.
func _decode_row(d: PackedByteArray, y0: int, ox: int) -> Array:
	if y0 < 0 or y0 + 5 > 127:
		return [-999, ""]
	var text := ""
	var score := 0
	var x := ox
	while x + 3 <= 127:
		# The bottom-right pixel of a 4x6 cell is always spacing: that is the
		# cell's background (works on selections and under the cursor too).
		var bi := (y0 + 5) * 512 + (x + 3) * 4
		var b0 := d[bi]
		var b1 := d[bi + 1]
		var b2 := d[bi + 2]
		var ok := true
		var mask := 0
		for r in 6:
			var ri := (y0 + r) * 512 + x * 4
			for c in 4:
				var i := ri + c * 4
				if d[i] != b0 or d[i + 1] != b1 or d[i + 2] != b2:
					if r == 5 or c == 3:
						ok = false
					else:
						mask |= 1 << (r * 3 + c)
		if not ok:
			text += UNKNOWN
			score -= 1
		elif mask == 0:
			text += " "
		elif Glyphs.GLYPHS.has(mask):
			text += Glyphs.GLYPHS[mask]
			score += 2
		else:
			text += UNKNOWN
			score -= 1
		x += 4
	return [score, text]

static func _is_ident(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"

## Documented name for a token that may contain unreadable cells.
func _resolve_token(tok: String) -> String:
	for cand in [tok, tok.trim_prefix(UNKNOWN).trim_suffix(UNKNOWN)]:
		if cand.is_empty():
			continue
		if not cand.contains(UNKNOWN):
			if Docs.DOCS.has(cand):
				return cand
			continue
		var found := ""
		var pattern: String = cand.replace(UNKNOWN, "?")
		for k in Docs.DOCS:
			if k.length() == cand.length() and k.match(pattern):
				if not found.is_empty():
					found = ""
					break
				found = k
		if not found.is_empty():
			return found
	return ""

## The documented word closest to text cell `cell` (within a few cells).
func _nearest_word(text: String, cell: float) -> String:
	var lower := text.to_lower()
	var best := ""
	var best_dist := 2.6
	var i := 0
	while i < lower.length():
		if not (_is_ident(lower[i]) or lower[i] == UNKNOWN):
			i += 1
			continue
		var start := i
		while i < lower.length() and (_is_ident(lower[i]) or lower[i] == UNKNOWN):
			i += 1
		var dist := 0.0
		if cell < start:
			dist = start - cell
		elif cell >= i:
			dist = cell - (i - 1)
		if dist < best_dist:
			var name := _resolve_token(lower.substr(start, i - start))
			if not name.is_empty():
				best = name
				best_dist = dist
	return best

func word_at(d: PackedByteArray, px: int, py: int) -> String:
	if d.size() < 128 * 128 * 4:
		return ""
	# The text grid offset is not known, so try them all and keep the one
	# that reads the most glyphs on the touched line.
	var best_score := 0
	var best_text := ""
	var best_y := 0
	var best_x := 0
	for dy in 6:
		for ox in 4:
			var r := _decode_row(d, py - dy, ox)
			if r[0] > best_score:
				best_score = r[0]
				best_text = r[1]
				best_y = py - dy
				best_x = ox
	if best_score <= 0:
		return ""
	var cell := (px - best_x) / 4.0
	# A finger hides what it points at: also look one line up, then down.
	for off in [0, -6, 6]:
		var text := best_text if off == 0 else String(_decode_row(d, best_y + off, best_x)[1])
		var w := _nearest_word(text, cell)
		if not w.is_empty():
			return w
	return ""

## Row of the editor cursor (a solid red block), or -1.
func _cursor_row(d: PackedByteArray) -> int:
	if d.size() < 128 * 128 * 4:
		return -1
	for y in range(8, 116):
		for x in range(0, 125):
			if not _is_red(d, x, y):
				continue
			if (x > 0 and _is_red(d, x - 1, y)) or _is_red(d, x, y - 1):
				continue
			var solid := true
			for r in 5:
				for c in 3:
					if not _is_red(d, x + c, y + r):
						solid = false
						break
				if not solid:
					break
			if solid:
				return y
	return -1

static func _is_red(d: PackedByteArray, x: int, y: int) -> bool:
	var i := y * 512 + x * 4
	return d[i] == 255 and d[i + 1] == 0 and d[i + 2] == 77

# --------------------------------------------------------------- hold docs

func _show_doc_at(pos: Vector2) -> void:
	var rect := _display_rect()
	if not rect.has_point(pos) or rect.size.x <= 0:
		return
	var p := (pos - rect.position) * 128.0 / rect.size
	var word := word_at(_touch_frame, int(p.x), int(p.y))
	if word.is_empty():
		word = word_at(_frame(), int(p.x), int(p.y))
	if word.is_empty():
		return
	_at_top = p.y > 64 # keep the panel away from the finger
	var doc: Array = Docs.DOCS[word]
	_show(Mode.DOC, doc[0], doc[1], [], 0)

# ------------------------------------------------------------ typing hints

func _typing_enabled() -> bool:
	return (PhysKb.suggestions or PhysKb.usage_hints) and PhysKb.in_code_context()

func note_event(ev: InputEventKey) -> void:
	if not ev.pressed:
		return
	if ev.ctrl_pressed:
		note_break()
	elif (ev.keycode & KEY_CODE_MASK) == KEY_BACKSPACE:
		note_backspace()
	elif ev.unicode >= 32 and ev.unicode < 127:
		note_char(String.chr(ev.unicode))
	else:
		note_break()

func note_char(ch: String) -> void:
	if not _typing_enabled():
		_word = ""
		return
	var c := ch.to_lower()
	if _is_ident(c):
		_word += c
		_update_hint()
	elif ch == "(":
		var w := _word
		_word = ""
		if PhysKb.usage_hints and Docs.DOCS.has(w) and String(Docs.DOCS[w][0]).contains("("):
			_place_by_cursor()
			_show(Mode.USAGE, Docs.DOCS[w][0], "", [], HINT_MS)
		elif _mode == Mode.HINT:
			_hide()
	else:
		note_break()

func note_backspace() -> void:
	if _word.is_empty():
		return
	_word = _word.left(-1)
	_update_hint()

func note_break() -> void:
	_word = ""
	if _mode == Mode.HINT:
		_hide()

func _place_by_cursor() -> void:
	var row := _cursor_row(_frame())
	if row >= 0:
		_at_top = row > 64

func _update_hint() -> void:
	_cands = []
	var usage := ""
	if _word.length() >= 2:
		if PhysKb.suggestions:
			for name in Docs.complete(_word, 5):
				if name != _word:
					_cands.append(name)
		if PhysKb.usage_hints and Docs.DOCS.has(_word):
			usage = Docs.DOCS[_word][0]
	if _cands.is_empty() and usage.is_empty():
		if _mode == Mode.HINT:
			_hide()
		return
	_place_by_cursor()
	_show(Mode.HINT, usage, "", _cands.slice(0, 4), HINT_MS)

func accept_suggestion(index: int) -> void:
	if _mode == Mode.HINT and index < _cands.size():
		_accept_name(_cands[index])

func _accept_name(name: String) -> void:
	if not name.begins_with(_word):
		return
	PhysKb.type_text(name.substr(_word.length()))
	_word = name
	_update_hint()

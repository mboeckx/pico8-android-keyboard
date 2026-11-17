extends CanvasLayer
## Code editor helpers, drawn over the PICO-8 display:
##  - touch and hold a word in the code editor -> short documentation
##    (with a pin to keep it on screen)
##  - while typing -> name suggestions (tap one, or use the "Accept
##    suggestion" binding) and a one-line usage hint
##
## PICO-8 only gives us a 128x128 picture, so "the word under the finger" is
## read back from the frame by matching the 3x5 font. What is being typed is
## followed from the key events PhysKb sees; when that trail is lost (cursor
## moved, text deleted past what was typed) the word before the cursor is
## read from the picture instead.

const Docs = preload("res://physkb/physkb_api_docs.gd")
const Glyphs = preload("res://physkb/physkb_font.gd")

const HOLD_MS := 450
const HINT_MS := 6000
const DOC_MS := 5000
const TOAST_MS := 1200
const REREAD_MS := 150 # PICO-8 needs a moment to redraw after a key
const UNKNOWN := "\u0001" # a cell that is not a recognisable glyph
const COL_USAGE := Color(1.0, 0.925, 0.153) # PICO-8 yellow
const COL_TEXT := Color(0.9, 0.9, 0.9)

var _doc: PanelContainer
var _doc_usage: Label
var _doc_desc: Label
var _pin: Button
var _pinned: bool = false
var _doc_hide_at: int = 0
var _doc_top: bool = false

var _hint: PanelContainer
var _chips: HFlowContainer
var _hint_usage: Label
var _hint_hide_at: int = 0
var _hint_top: bool = false
var _hint_has_chips: bool = false

var _toast: Label
var _toast_hide_at: int = 0
var _font_size: int = 0

## Text typed since the cursor last jumped; the word being typed is its tail.
var _line: String = ""
## False when the text left of the cursor is not known from typing.
var _line_known: bool = false
var _reread_at: int = 0
var _cands: Array = []

var _touching: bool = false
var _touch_pos: Vector2 = Vector2.ZERO
var _touch_time: int = 0
var _hold_fired: bool = false
var _touch_frame: PackedByteArray # the picture at touch-down, before PICO-8's pointer moves there

func _ready() -> void:
	layer = 5

	_doc = _make_panel()
	var doc_box := VBoxContainer.new()
	doc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doc.add_child(doc_box)
	var doc_head := HBoxContainer.new()
	doc_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	doc_box.add_child(doc_head)
	_doc_usage = _make_label(COL_USAGE)
	_doc_usage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doc_head.add_child(_doc_usage)
	_pin = Button.new()
	_pin.text = "📌"
	_pin.toggle_mode = true
	_pin.focus_mode = Control.FOCUS_NONE
	_pin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_pin.tooltip_text = "Keep this on screen"
	_pin.toggled.connect(_on_pin_toggled)
	doc_head.add_child(_pin)
	_doc_desc = _make_label(COL_TEXT)
	doc_box.add_child(_doc_desc)

	_hint = _make_panel()
	var hint_box := VBoxContainer.new()
	hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(hint_box)
	_chips = HFlowContainer.new()
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_box.add_child(_chips)
	_hint_usage = _make_label(COL_USAGE)
	hint_box.add_child(_hint_usage)

	_toast = Label.new()
	_toast.visible = false
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_toast)

	_apply_style()
	get_tree().root.size_changed.connect(_apply_style)

func _make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	add_child(p)
	return p

func _make_label(color: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	return l

func _apply_style() -> void:
	var vp := get_viewport().get_visible_rect().size
	# The app's usual text size, but never too big for the PICO-8 display.
	_font_size = int(max(12, min(vp.x, vp.y) * 0.03))
	var width := _display_rect().size.x
	if width > 0:
		_font_size = int(clamp(width * 0.04, 10, _font_size))
	# Same look as the options menu tooltips.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(int(_font_size * 0.5))
	_doc.add_theme_stylebox_override("panel", style)
	_hint.add_theme_stylebox_override("panel", style)
	_doc_usage.add_theme_font_size_override("font_size", _font_size)
	_hint_usage.add_theme_font_size_override("font_size", _font_size)
	_doc_desc.add_theme_font_size_override("font_size", int(_font_size * 0.85))
	_pin.add_theme_font_size_override("font_size", _font_size)
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

func _place(panel: Control, rect: Rect2, at_top: bool) -> void:
	panel.custom_minimum_size.x = rect.size.x
	panel.size = Vector2(rect.size.x, 0)
	panel.position = rect.position if at_top else Vector2(rect.position.x, rect.end.y - panel.size.y)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()

	if _touching and not _hold_fired and now - _touch_time >= HOLD_MS:
		_hold_fired = true
		if PhysKb.hold_docs and PhysKb.in_code_context():
			_show_doc_at(_touch_pos)

	if _doc.visible and not _pinned and not _touching and _doc_hide_at > 0 and now > _doc_hide_at:
		_doc.visible = false
	if _hint.visible and _hint_hide_at > 0 and now > _hint_hide_at:
		_hint.visible = false
	if _toast.visible and now > _toast_hide_at:
		_toast.visible = false

	if _reread_at > 0 and now >= _reread_at:
		_reread_at = 0
		_reread_line()

	var rect := _display_rect()
	if _doc.visible:
		_place(_doc, rect, _doc_top)
	if _hint.visible:
		# Never on top of the documentation box.
		_place(_hint, rect, (not _doc_top) if _doc.visible else _hint_top)

func _unhandled_input(event: InputEvent) -> void:
	# Only watches; never consumes, so PICO-8 still gets the touch as a click.
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_touching = true
			_hold_fired = false
			_touch_pos = event.position
			_touch_time = Time.get_ticks_msec()
			_touch_frame = _frame() if PhysKb.hold_docs else PackedByteArray()
			if _doc.visible and not _pinned:
				_doc.visible = false
			note_break() # a tap moves the editor cursor
		else:
			_touching = false
			_doc_hide_at = Time.get_ticks_msec() + DOC_MS
	elif event is InputEventScreenDrag and event.index == 0:
		var vp := get_viewport().get_visible_rect().size
		if event.position.distance_to(_touch_pos) > min(vp.x, vp.y) * 0.02:
			_touching = false

func _on_pin_toggled(on: bool) -> void:
	_pinned = on
	_pin.modulate = Color(1, 1, 1, 1.0 if on else 0.5)
	if not on:
		_doc.visible = false

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

## Top-left pixel of the editor cursor (a solid red block), or (-1, -1).
func _cursor_pos(d: PackedByteArray) -> Vector2i:
	if d.size() < 128 * 128 * 4:
		return Vector2i(-1, -1)
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
				return Vector2i(x, y)
	return Vector2i(-1, -1)

static func _is_red(d: PackedByteArray, x: int, y: int) -> bool:
	var i := y * 512 + x * 4
	return d[i] == 255 and d[i + 1] == 0 and d[i + 2] == 77

## The identifier that ends right before the editor cursor, read off the frame.
func word_before_cursor(d: PackedByteArray) -> String:
	var cur := _cursor_pos(d)
	if cur.x < 0:
		return ""
	var ox := cur.x % 4
	var text: String = String(_decode_row(d, cur.y, ox)[1]).to_lower()
	var i := (cur.x - ox) / 4 - 1
	var word := ""
	while i >= 0 and i < text.length() and _is_ident(text[i]):
		word = text[i] + word
		i -= 1
	return word

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
	if not _pinned:
		_doc_top = p.y > 64 # keep the box away from the finger
	show_doc(word)

func show_doc(word: String) -> void:
	if not Docs.DOCS.has(word):
		return
	_apply_style()
	var doc: Array = Docs.DOCS[word]
	_doc_usage.text = doc[0]
	_doc_desc.text = doc[1]
	_pin.set_pressed_no_signal(_pinned)
	_pin.modulate = Color(1, 1, 1, 1.0 if _pinned else 0.5)
	_doc_hide_at = 0
	_doc.visible = true

# ------------------------------------------------------------ typing hints

func _typing_enabled() -> bool:
	return (PhysKb.suggestions or PhysKb.usage_hints) and PhysKb.in_code_context()

func _word() -> String:
	var i := _line.length()
	while i > 0 and _is_ident(_line[i - 1]):
		i -= 1
	return _line.substr(i)

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
		_line = ""
		_line_known = false
		return
	if ch == "(":
		var w := _word()
		if w.is_empty() and not _line_known:
			w = word_before_cursor(_frame())
		_line += ch
		if PhysKb.usage_hints and Docs.DOCS.has(w) and String(Docs.DOCS[w][0]).contains("("):
			_show_hint(Docs.DOCS[w][0], [])
		elif _hint_has_chips:
			_hint.visible = false
		return
	_line += ch.to_lower()
	if not _line_known and _word() == _line:
		# Typing into text we did not see being typed: the word may have
		# started earlier, so look at the screen once PICO-8 has drawn it.
		_reread_at = Time.get_ticks_msec() + REREAD_MS
	_update_hint()

func note_backspace() -> void:
	if not _typing_enabled():
		return
	if _line.is_empty():
		# Deleting text we did not see being typed.
		_line_known = false
		_reread_at = Time.get_ticks_msec() + REREAD_MS
		return
	_line = _line.left(-1)
	if _line.is_empty() and not _line_known:
		_reread_at = Time.get_ticks_msec() + REREAD_MS
	_update_hint()

## The cursor went somewhere else (tap, arrows, Enter, a shortcut).
func note_break() -> void:
	_line = ""
	_line_known = false
	_reread_at = 0
	if _hint_has_chips:
		_hint.visible = false

func _reread_line() -> void:
	if not _typing_enabled():
		return
	var w := word_before_cursor(_frame())
	if w.is_empty():
		return
	_line = w
	_update_hint()

func _show_hint(usage: String, chips: Array) -> void:
	_apply_style()
	var cur := _cursor_pos(_frame())
	if cur.y >= 0:
		_hint_top = cur.y > 64 # stay clear of the line being typed
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	for name in chips:
		var b := UIUtils.create_pixel_button(name, int(_font_size * 0.85))
		b.focus_mode = Control.FOCUS_NONE # must never take key focus
		b.pressed.connect(_accept_name.bind(name))
		_chips.add_child(b)
	_hint_has_chips = not chips.is_empty()
	_chips.visible = _hint_has_chips
	_hint_usage.text = usage
	_hint_usage.visible = not usage.is_empty()
	_hint_hide_at = Time.get_ticks_msec() + HINT_MS
	_hint.visible = true

func _update_hint() -> void:
	_cands = []
	var usage := ""
	var word := _word()
	if word.length() >= 2:
		if PhysKb.suggestions:
			for name in Docs.complete(word, 5):
				if name != word:
					_cands.append(name)
		if PhysKb.usage_hints and Docs.DOCS.has(word):
			usage = Docs.DOCS[word][0]
	if _cands.is_empty() and usage.is_empty():
		if _hint_has_chips:
			_hint.visible = false
		return
	_show_hint(usage, _cands.slice(0, 4))

func accept_suggestion(index: int) -> void:
	if _hint.visible and _hint_has_chips and index < _cands.size():
		_accept_name(_cands[index])

func _accept_name(name: String) -> void:
	var word := _word()
	if not name.begins_with(word):
		return
	PhysKb.type_text(name.substr(word.length()))
	_line += name.substr(word.length())
	_update_hint()

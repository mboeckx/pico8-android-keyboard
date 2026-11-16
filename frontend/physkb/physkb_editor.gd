extends CanvasLayer
## Keyboard settings screen (Options > Controls > Keyboard Mapping).
## Built in code so the module stays a single folder; the look follows the
## other full-screen editors (Favourites, Play Stats) and the options rows.

const A = preload("res://physkb/physkb_actions.gd")
const BG_ART = preload("res://icons/adaptive_top.png")

const COL_ROW := Color(0.7, 0.7, 0.7)
const COL_HEADER := Color(0.9, 0.9, 0.9)
const COL_HINT := Color(0.5, 0.5, 0.5)
const COL_WARN := Color(1.0, 0.64, 0.0) # PICO-8 orange
const COL_RED := Color(0.679, 0.0, 0.0)

var _font: int = 12
var _scale: float = 1.2
var _list: VBoxContainer
var _scroll: ScrollContainer
var _margin: MarginContainer
var _title: Label
var _btn_close: Button
var _btn_reset: Button
var _rows: Dictionary = {} # action id -> {bind, clear, vkey, warn, def}
var _collapsed: Dictionary = {A.G_CHARS: true, A.G_SHORTCUTS: true, A.G_APP: true}
var _capturing: String = ""

func _ready() -> void:
	layer = 15
	_build_frame()
	_rebuild()
	get_tree().root.size_changed.connect(_rebuild)
	PhysKb.changed.connect(_refresh)
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.set_input_blocked(true)

func _exit_tree() -> void:
	if is_instance_valid(PicoVideoStreamer.instance):
		PicoVideoStreamer.instance.set_input_blocked(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_close()

func _close() -> void:
	queue_free()

# ------------------------------------------------------------------- frame

func _flat_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(10)
	return sb

func _build_frame() -> void:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 1)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	var art := TextureRect.new()
	art.texture = BG_ART
	art.modulate = Color(1, 1, 1, 0.12)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	panel.add_child(art)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	_margin.add_child(vbox)

	_title = Label.new()
	_title.text = "⌨ Keyboard Mapping"
	vbox.add_child(_title)
	vbox.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

	vbox.add_child(HSeparator.new())

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(footer)

	_btn_close = Button.new()
	_btn_close.text = "✖ Close"
	_btn_close.add_theme_stylebox_override("normal", _flat_box(Color(0.15, 0.15, 0.15), Color(0.45, 0.45, 0.45)))
	_btn_close.pressed.connect(_close)
	footer.add_child(_btn_close)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(20, 0)
	footer.add_child(gap)

	_btn_reset = Button.new()
	_btn_reset.text = "🔄 Reset"
	var reset_box := _flat_box(Color(0, 0, 0, 0.5), Color(0.388, 0, 0))
	_btn_reset.add_theme_stylebox_override("normal", reset_box)
	_btn_reset.add_theme_stylebox_override("hover", reset_box)
	_btn_reset.add_theme_color_override("font_color", COL_RED)
	_btn_reset.add_theme_color_override("font_hover_color", COL_RED)
	_btn_reset.add_theme_color_override("font_focus_color", Color(0.855, 0, 0))
	_btn_reset.pressed.connect(_on_reset_pressed)
	footer.add_child(_btn_reset)

# -------------------------------------------------------------------- list

func _rebuild() -> void:
	var vp := get_viewport().get_visible_rect().size
	_font = int(max(12, min(vp.x, vp.y) * 0.03))
	_scale = clamp(_font / 10.0, 1.2, 3.0)
	for side in ["margin_top", "margin_bottom"]:
		_margin.add_theme_constant_override(side, int(vp.y * 0.08))
	for side in ["margin_left", "margin_right"]:
		_margin.add_theme_constant_override(side, int(vp.x * 0.06))
	_title.add_theme_font_size_override("font_size", int(_font * 1.1))
	_btn_close.add_theme_font_size_override("font_size", _font)
	_btn_reset.add_theme_font_size_override("font_size", _font)

	var keep_scroll := _scroll.scroll_vertical
	_capturing = ""
	_rows.clear()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	_add_toggle("Remap keys", "enabled", "Master switch for everything below except the code helpers")
	_add_select("Game keys", "game_keys_mode", ["Auto", "Always", "Off"],
		"Auto: in Splore and in game (needs PICO-8 0.2.7 to detect them)")
	_add_toggle("Hold word for docs", "hold_docs", "Touch and hold a PICO-8 keyword in the code editor")
	_add_toggle("Suggest names", "suggestions", "Show matching PICO-8 names while typing")
	_add_toggle("Usage hints", "usage_hints", "Show how to call the function being typed")
	_add_hint("Tap a key box, then press the keys. ✖ clears it. 📱 adds an on-screen button; place it with Customize Layout.")

	for g in A.GROUPS:
		_add_group(g[0], g[1], g[2])

	_refresh()
	_scroll.set_deferred("scroll_vertical", keep_scroll)

func _row_label(text: String, tip: String) -> Button:
	# Same flat, left-aligned label buttons the options menu rows use.
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.add_theme_font_size_override("font_size", _font)
	b.add_theme_color_override("font_color", COL_ROW)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.8, 0.8, 0.8))
	return b

func _wrap_scaled(ctrl: Control, width: float, factor: float) -> Control:
	# Options-menu trick: scale the widget inside a wrapper that reserves room.
	var wrapper := Control.new()
	var natural := ctrl.get_combined_minimum_size()
	var h: float = max(30.0, natural.y) * _scale
	wrapper.custom_minimum_size = Vector2(width * _scale, h)
	ctrl.scale = Vector2(factor, factor)
	ctrl.position.y = (h - natural.y * factor) / 2.0
	wrapper.add_child(ctrl)
	return wrapper

func _add_toggle(text: String, key: String, tip: String) -> void:
	var row := HBoxContainer.new()
	var label := _row_label(text, tip)
	var toggle := CheckButton.new()
	toggle.button_pressed = PhysKb.get(key)
	toggle.toggled.connect(func(on): PhysKb.set_option(key, on))
	label.pressed.connect(func(): toggle.button_pressed = not toggle.button_pressed)
	row.add_child(label)
	row.add_child(_wrap_scaled(toggle, 70.0, _scale))
	_list.add_child(row)

func _add_select(text: String, key: String, items: Array, tip: String) -> void:
	var row := HBoxContainer.new()
	var label := _row_label(text, tip)
	var opt := OptionButton.new()
	for it in items:
		opt.add_item(it)
	opt.select(PhysKb.get(key))
	opt.add_theme_font_size_override("font_size", int(_font * 0.5))
	opt.item_selected.connect(func(i): PhysKb.set_option(key, i))
	label.pressed.connect(func():
		opt.select((opt.selected + 1) % opt.item_count)
		PhysKb.set_option(key, opt.selected))
	row.add_child(label)
	row.add_child(_wrap_scaled(opt, 120.0, _scale * 0.6))
	_list.add_child(row)

func _add_hint(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", int(_font * 0.7))
	l.add_theme_color_override("font_color", COL_HINT)
	_list.add_child(l)

func _add_group(id: String, title: String, hint: String) -> void:
	var collapsed: bool = _collapsed.get(id, false)
	var header := Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.text = ("▶️ " if collapsed else "🔽 ") + title
	header.add_theme_font_size_override("font_size", int(_font * 1.1))
	header.add_theme_color_override("font_color", COL_HEADER)
	header.add_theme_color_override("font_focus_color", Color.WHITE)
	header.add_theme_color_override("font_hover_color", Color.WHITE)
	_list.add_child(header)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", int(15 * _scale))
	body.visible = not collapsed
	_list.add_child(body)
	header.pressed.connect(func():
		body.visible = not body.visible
		_collapsed[id] = not body.visible
		header.text = ("🔽 " if body.visible else "▶️ ") + title)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(_font * 0.3))
	body.add_child(box)
	if not hint.is_empty():
		var l := Label.new()
		l.text = hint
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", int(_font * 0.7))
		l.add_theme_color_override("font_color", COL_HINT)
		box.add_child(l)
	for a in PhysKb.actions:
		if a.group == id:
			box.add_child(_make_row(a))

func _small_button(text: String, tip: String) -> Button:
	var b := UIUtils.create_pixel_button(text, int(_font * 0.8))
	b.tooltip_text = tip
	return b

func _make_row(a: Dictionary) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_font * 0.4))
	wrap.add_child(row)

	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.add_theme_constant_override("separation", 0)
	row.add_child(names)
	var name := Label.new()
	name.text = a.label
	name.clip_text = true
	name.add_theme_font_size_override("font_size", int(_font * 0.8))
	name.add_theme_color_override("font_color", COL_ROW)
	names.add_child(name)
	if a.has("native"):
		# What PICO-8 itself listens for, so a moved shortcut stays recognisable.
		var native := Label.new()
		native.text = "PICO-8: " + A.combo_text(a.native)
		native.clip_text = true
		native.add_theme_font_size_override("font_size", int(_font * 0.6))
		native.add_theme_color_override("font_color", COL_HINT)
		names.add_child(native)

	var refs := {}
	if not a.get("modifier", false):
		var def := _small_button("↺", "Back to the default")
		def.pressed.connect(func(): PhysKb.set_binding(a.id, int(a.def)))
		row.add_child(def)
		refs["def"] = def

		var bind := _small_button("-", "Tap, then press the key combination")
		bind.toggle_mode = true
		bind.custom_minimum_size.x = _font * 7.5
		bind.toggled.connect(_on_bind_toggled.bind(a.id))
		row.add_child(bind)
		refs["bind"] = bind

		var clear := _small_button("✖", "Clear this binding")
		clear.pressed.connect(func(): PhysKb.set_binding(a.id, 0))
		row.add_child(clear)
		refs["clear"] = clear

	var vkey := _small_button("📱", "Show an on-screen button")
	vkey.toggle_mode = true
	vkey.toggled.connect(func(on): PhysKb.set_vkey(a.id, on))
	row.add_child(vkey)
	refs["vkey"] = vkey

	var warn := Label.new()
	warn.visible = false
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.add_theme_font_size_override("font_size", int(_font * 0.7))
	warn.add_theme_color_override("font_color", COL_WARN)
	wrap.add_child(warn)
	refs["warn"] = warn

	_rows[a.id] = refs
	return wrap

## Updates every row from PhysKb's state (texts, conflict warnings).
func _refresh() -> void:
	for id in _rows:
		var r: Dictionary = _rows[id]
		r.vkey.set_pressed_no_signal(PhysKb.has_vkey(id))
		r.vkey.modulate.a = 1.0 if PhysKb.has_vkey(id) else 0.7
		if not r.has("bind"):
			continue
		var capturing: bool = (_capturing == id)
		r.bind.set_pressed_no_signal(capturing)
		r.bind.text = "press…" if capturing else A.combo_text(PhysKb.get_binding(id))
		r.def.visible = not PhysKb.is_default(id)
		r.clear.disabled = PhysKb.get_binding(id) == 0
		var others: PackedStringArray = PhysKb.conflicts(id)
		var clash := not others.is_empty()
		for col in ["font_color", "font_hover_color", "font_focus_color"]:
			if clash:
				r.bind.add_theme_color_override(col, COL_WARN)
			else:
				r.bind.remove_theme_color_override(col)
		r.warn.visible = clash
		if clash:
			r.warn.text = "⚠ also used by: " + ", ".join(others)

# ----------------------------------------------------------------- capture

func _on_bind_toggled(on: bool, id: String) -> void:
	_capturing = id if on else ""
	_refresh()

func _input(event: InputEvent) -> void:
	if _capturing.is_empty() or not (event is InputEventKey):
		return
	get_viewport().set_input_as_handled()
	var key := PhysKb.event_key(event)
	if not event.pressed or event.echo or key == KEY_NONE or PhysKb.is_modifier_key(key):
		return
	var id := _capturing
	_capturing = ""
	PhysKb.set_binding(id, A.combo(PhysKb.event_mods(event), key))
	_refresh()

func _on_reset_pressed() -> void:
	if has_node("CustomConfirmDialog"):
		return
	var close_dialog := func():
		var d = get_node_or_null("CustomConfirmDialog")
		if d: d.queue_free()
	UIUtils.create_confirm_dialog(self, "Reset", "RESET ALL KEY BINDINGS?", "YES", "NO", false,
		func():
			close_dialog.call()
			PhysKb.reset_all(),
		close_dialog)

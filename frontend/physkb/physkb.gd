extends Node
## Physical keyboard support, autoloaded as "PhysKb".
##
## Self-contained: it attaches a few helper nodes to the main scene at runtime
## and talks to PicoVideoStreamer only through its existing public methods
## (send_key / send_input / vkb_setstate). Nothing else in the project depends
## on it; removing the autoload line and the options-menu button disables it.
##
## Key flow: physkb_input.gd sees a key event before PicoVideoStreamer does and
## calls handle_key(). Returning true means "consumed" (we sent something else,
## or deliberately nothing); false lets the event continue unchanged.

const A = preload("res://physkb/physkb_actions.gd")
const InputNode = preload("res://physkb/physkb_input.gd")
const VKey = preload("res://physkb/physkb_vkey.gd")
const Assist = preload("res://physkb/physkb_code_assist.gd")
const Editor = preload("res://physkb/physkb_editor.gd")
const Bar = preload("res://physkb/physkb_bar.gd")
const CheatSheet = preload("res://physkb/physkb_cheatsheet.gd")
const KEY_SCENE = preload("res://key.tscn")
const TEX_KEY = preload("res://assets/key.png")
const TEX_KEY_PRESSED = preload("res://assets/key_pressed.png")

const SECTION := "physkb"
const ONCE_GUARD_MS := 300 # one-shot actions fire at most once per this interval
const SNAP_UNITS := 3.0 # snap-to-grid step for freely placed buttons
const VKEY_SCALE := 1.5 # on-screen keys start a bit larger than keyboard keys
const VKEY_ROW_UNITS := 80.0 # default row width before wrapping

const SC_LCTRL := 224
const SC_LSHIFT := 225
const SC_LALT := 226
const SDL_SHIFT := 0x0001
const SDL_CTRL := 0x0040
const SDL_ALT := 0x0100

# NavState bits reported by the shim (only meaningful on PICO-8 0.2.7).
const NAV_EDITOR := 0x01
const NAV_GAME := 0x02
const NAV_SPLORE := 0x08
const NAV_CONSOLE := 0x10
const NAV_SCREEN_MASK := 0x1B

enum GameKeys {AUTO, ALWAYS, OFF}
enum VKeyLayout {FREE, GRID}

signal changed

var enabled: bool = true
var game_keys_mode: int = GameKeys.AUTO
var hold_docs: bool = true
var suggestions: bool = true
var usage_hints: bool = true
var vkey_layout: int = VKeyLayout.FREE
var vkey_snap: bool = false
var bindings: Dictionary = {} # action id -> combo (0 = cleared); absent = default
var vkeys: Array = [] # action ids shown as on-screen buttons

var actions: Array = []
var assist: Node = null

var _by_id: Dictionary = {}
var _game_lookup: Dictionary = {} # combo -> action
var _main_lookup: Dictionary = {} # combo -> action
var _blocked: Dictionary = {} # native combos of shortcuts that were moved/cleared
var _users: Dictionary = {} # combo -> [action ids]
var _active: Dictionary = {} # token -> state of an output being held
var _swallowed: Dictionary = {} # physical keys whose release must be eaten
var _lifted: int = 0 # modifiers the user holds that we released in PICO-8
var _forced: int = 0 # modifiers we pressed in PICO-8 that the user does not hold
var _last_fired: Dictionary = {} # action id -> msec, for one-shot actions
var _game_override = null
var _last_screen: int = -1
var _streamer: Node = null
var _holders: Array = []
var _portrait_holder: Control = null

func _ready() -> void:
	actions = A.build()
	for a in actions:
		_by_id[a.id] = a
	_load()
	_rebuild()

func _process(_delta: float) -> void:
	var s = PicoVideoStreamer.instance
	if not is_instance_valid(s):
		return
	if s != _streamer:
		_attach(s)
	# Forget a manual game-keys toggle when PICO-8 moves to another screen.
	var screen: int = s.current_navstate & NAV_SCREEN_MASK
	if screen != _last_screen:
		_last_screen = screen
		_game_override = null
	# LandscapeUI hides itself in portrait; the Arranger is always visible, so
	# its buttons are hidden here when the landscape set is showing.
	if is_instance_valid(_portrait_holder):
		_portrait_holder.visible = not PicoVideoStreamer.is_system_landscape()
	if PicoVideoStreamer.display_drag_enabled:
		_dodge_layout_controls(s)

# ---------------------------------------------------------------- settings

func _load() -> void:
	enabled = PicoBootManager.get_setting(SECTION, "enabled", true)
	game_keys_mode = PicoBootManager.get_setting(SECTION, "game_keys_mode", GameKeys.AUTO)
	hold_docs = PicoBootManager.get_setting(SECTION, "hold_docs", true)
	suggestions = PicoBootManager.get_setting(SECTION, "suggestions", true)
	usage_hints = PicoBootManager.get_setting(SECTION, "usage_hints", true)
	vkey_layout = PicoBootManager.get_setting(SECTION, "vkey_layout", VKeyLayout.FREE)
	vkey_snap = PicoBootManager.get_setting(SECTION, "vkey_snap", false)
	var b = PicoBootManager.get_setting(SECTION, "bindings", {})
	bindings = b if b is Dictionary else {}
	var v = PicoBootManager.get_setting(SECTION, "vkeys", [])
	vkeys = v if v is Array else []

func set_option(key: String, value) -> void:
	set(key, value)
	PicoBootManager.set_setting(SECTION, key, value)
	if key == "game_keys_mode":
		_game_override = null
	if key == "vkey_layout":
		_build_vkeys()
	changed.emit()

func get_binding(id: String) -> int:
	if bindings.has(id):
		return int(bindings[id])
	return int(_by_id[id].def)

func is_default(id: String) -> bool:
	return get_binding(id) == int(_by_id[id].def)

func set_binding(id: String, combo: int) -> void:
	if combo == int(_by_id[id].def):
		bindings.erase(id)
	else:
		bindings[id] = combo
	_save_bindings()

func reset_all() -> void:
	bindings.clear()
	_save_bindings()

func _save_bindings() -> void:
	PicoBootManager.set_setting(SECTION, "bindings", bindings)
	_rebuild()
	changed.emit()

func has_vkey(id: String) -> bool:
	return vkeys.has(id)

func set_vkey(id: String, on: bool) -> void:
	if on and not vkeys.has(id):
		vkeys.append(id)
	elif not on:
		vkeys.erase(id)
	PicoBootManager.set_setting(SECTION, "vkeys", vkeys)
	_build_vkeys()
	changed.emit()

## Labels of the other actions bound to the same combination as `id`.
func conflicts(id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var c := get_binding(id)
	if c == 0:
		return out
	for other in _users.get(c, []):
		if other != id:
			out.append(_by_id[other].label)
	return out

func _rebuild() -> void:
	_game_lookup.clear()
	_main_lookup.clear()
	_blocked.clear()
	_users.clear()
	for a in actions:
		if a.get("modifier", false):
			continue
		var c := get_binding(a.id)
		if c == 0:
			continue
		if not _users.has(c):
			_users[c] = []
		_users[c].append(a.id)
		var table := _game_lookup if a.group == A.G_GAME else _main_lookup
		if not table.has(c):
			table[c] = []
		table[c].append(a)
	# A shortcut alone on PICO-8's own combination needs no translation at all.
	for c in _main_lookup.keys():
		var list: Array = _main_lookup[c]
		if list.size() == 1 and list[0].has("native") and c == int(list[0].native):
			_main_lookup.erase(c)
	for a in actions:
		if a.has("native") and get_binding(a.id) != int(a.native):
			_blocked[int(a.native)] = true

# ------------------------------------------------------------------- state

static func event_key(ev: InputEventKey) -> int:
	var k: int = ev.physical_keycode & KEY_CODE_MASK
	if k == KEY_NONE or k == KEY_UNKNOWN:
		k = ev.keycode & KEY_CODE_MASK
	return k

static func is_modifier_key(k: int) -> bool:
	return k == KEY_SHIFT or k == KEY_CTRL or k == KEY_ALT or k == KEY_META

func event_mods(ev: InputEventKey) -> int:
	var m := 0
	if ev.shift_pressed: m |= A.M_SHIFT
	if ev.ctrl_pressed: m |= A.M_CTRL
	if ev.alt_pressed: m |= A.M_ALT
	if ev.meta_pressed: m |= A.M_META
	return m | _virtual_mods()

func _virtual_mods() -> int:
	var m := 0
	if is_instance_valid(_streamer):
		if "Shift" in _streamer.held_keys: m |= A.M_SHIFT
		if "Ctrl" in _streamer.held_keys: m |= A.M_CTRL
		if "Alt" in _streamer.held_keys: m |= A.M_ALT
	return m

func screen() -> int:
	return _streamer.current_navstate & NAV_SCREEN_MASK if is_instance_valid(_streamer) else 0

func game_keys_active() -> bool:
	if _game_override != null:
		return _game_override
	match game_keys_mode:
		GameKeys.ALWAYS: return true
		GameKeys.OFF: return false
	return (screen() & (NAV_GAME | NAV_SPLORE)) != 0

## True where code is being typed (or when the screen cannot be detected).
func in_code_context() -> bool:
	var sc := screen()
	return sc == 0 or (sc & NAV_EDITOR) != 0

static func _sdl_mods(m: int) -> int:
	var r := 0
	if m & A.M_SHIFT: r |= SDL_SHIFT
	if m & A.M_CTRL: r |= SDL_CTRL
	if m & A.M_ALT: r |= SDL_ALT
	return r

# -------------------------------------------------------------- key events

func handle_key(ev: InputEventKey) -> bool:
	var key := event_key(ev)
	if key == KEY_NONE:
		return false
	# Modifier state always comes from the event itself, never from memory, so
	# a missed key-up can not leave a modifier "stuck".
	var held := event_mods(ev)
	if is_modifier_key(key):
		if key == KEY_CTRL: _lifted &= ~A.M_CTRL
		if key == KEY_SHIFT: _lifted &= ~A.M_SHIFT
		return false

	if not ev.pressed:
		if _active.has(key):
			_release(key, held)
			return true
		if _swallowed.erase(key):
			return true
		return false

	if _active.has(key) or _swallowed.has(key):
		if ev.echo:
			_repeat(key)
			return true
		# A new press without having seen the release: drop the stale state.
		_release(key, held)
		_swallowed.erase(key)

	if enabled:
		var combo := A.combo(held, key)
		var extra := 0
		var acts: Array = _resolve(combo)
		if acts.is_empty() and (held & A.M_SHIFT):
			# Let Shift ride along (e.g. Shift + an arrow binding selects text).
			acts = _resolve(combo & ~(A.M_SHIFT << 24)).filter(func(a): return a.kind == "key")
			extra = A.M_SHIFT
		if not acts.is_empty():
			_press(key, acts, extra, held)
			return true
		if _blocked.has(combo):
			_swallowed[key] = true
			return true

	_sync_mods(held)
	if assist:
		assist.note_event(ev)
	return false

## All actions bound to `combo` (a shared combination fires every one of them).
func _resolve(combo: int) -> Array:
	if game_keys_active() and _game_lookup.has(combo):
		return _game_lookup[combo]
	return _main_lookup.get(combo, [])

## Before a key goes to PICO-8 untranslated: make PICO-8's idea of Ctrl/Shift
## match what the user is really holding, undoing anything we changed.
func _sync_mods(held: int) -> void:
	var s := _streamer
	if not is_instance_valid(s):
		return
	for pair in [[A.M_CTRL, SC_LCTRL], [A.M_SHIFT, SC_LSHIFT]]:
		var bit: int = pair[0]
		if (_lifted & bit) and (held & bit):
			s.send_key(pair[1], true, false, _sdl_mods(held)) # still held: put it back
		elif (_forced & bit) and not (held & bit):
			s.send_key(pair[1], false, false, _sdl_mods(held)) # ours and stale: let go
	_lifted = 0
	_forced = 0

## On-screen button events (from physkb_vkey.gd).
func vkey_event(id: String, down: bool, echo: bool) -> void:
	var s := _streamer
	if not is_instance_valid(s) or s.input_blocked or not _by_id.has(id):
		return
	var a: Dictionary = _by_id[id]
	if a.get("modifier", false):
		s.vkb_setstate(a.key, down, 0, echo)
		return
	var token := "vk:" + id
	var held := _virtual_mods()
	if down:
		if echo:
			_repeat(token)
		else:
			if PicoVideoStreamer.get_haptic_enabled():
				Input.vibrate_handheld(35, 1)
			_press(token, [a], 0, held)
	else:
		_release(token, held)

# ------------------------------------------------------------------ output

func _press(token, acts: Array, extra_mods: int, held: int) -> void:
	var s := _streamer
	if not is_instance_valid(s):
		return
	var states: Array = []
	for a in acts:
		if a.kind == "host":
			_host(a.id)
			continue
		# One-shot actions (Esc, shortcuts) ignore bouncing or auto-repeating keys.
		var once: bool = a.has("native") or a.get("key", "") == "Escape"
		var now := Time.get_ticks_msec()
		if once and now - int(_last_fired.get(a.id, -ONCE_GUARD_MS)) < ONCE_GUARD_MS:
			continue
		_last_fired[a.id] = now

		var sc := -1
		var mods := 0
		var flags := 0
		var text := 0
		if a.kind == "char":
			var info: Array = A.CHAR_KEYS.get(a.ch, [])
			if info.is_empty():
				continue
			sc = int(s.SDL_KEYMAP.get(info[0], -1))
			flags = SDL_SHIFT if info[1] else 0
			text = a.ch.unicode_at(0)
		else:
			sc = int(s.SDL_KEYMAP.get(a.key, -1))
			mods = int(a.mods) | extra_mods
			flags = _sdl_mods(mods)
		if sc < 0:
			continue

		# Make PICO-8 see exactly the output's modifiers: lift the ones the user
		# is holding for the combination, press the ones the output needs.
		var down := (held & ~_lifted) | _forced # what PICO-8 currently has down
		for pair in [[A.M_CTRL, SC_LCTRL], [A.M_SHIFT, SC_LSHIFT]]:
			var bit: int = pair[0]
			if (down & bit) and not (mods & bit):
				s.send_key(pair[1], false, false, flags)
				if held & bit: _lifted |= bit
				_forced &= ~bit
			elif (mods & bit) and not (down & bit):
				s.send_key(pair[1], true, false, flags)
				if held & bit: _lifted &= ~bit
				else: _forced |= bit
		if mods & A.M_ALT:
			s.send_key(SC_LALT, true, false, flags)

		s.send_key(sc, true, false, flags)
		if text:
			s.send_input(text)
		states.append({"sc": sc, "mods": mods, "flags": flags, "text": text, "once": once})

		if assist:
			if a.kind == "char":
				assist.note_char(a.ch)
			elif a.get("key", "") == "Backspace" and mods == 0:
				assist.note_backspace()
			else:
				assist.note_break()
	if states.is_empty():
		_swallowed[token] = true
	else:
		_active[token] = states

func _repeat(token) -> void:
	var s := _streamer
	if not is_instance_valid(s) or not _active.has(token):
		return
	for st in _active[token]:
		if st.once or (st.mods & (A.M_CTRL | A.M_ALT)):
			continue
		s.send_key(st.sc, true, true, st.flags)
		if st.text:
			s.send_input(st.text)
			if assist:
				assist.note_char(String.chr(st.text))

func _release(token, held: int) -> void:
	_swallowed.erase(token)
	if not _active.has(token):
		return
	var states: Array = _active[token]
	_active.erase(token)
	var s := _streamer
	if not is_instance_valid(s):
		return
	var real := held & ~_lifted
	var forced := _forced
	_forced = 0
	# Modifiers we pressed for the output go up again right away. Modifiers we
	# lifted are only put back when the user next types with them still held
	# (see _sync_mods), so nothing is ever pressed on a guess.
	var tail: Array = []
	for st in states:
		if st.mods & A.M_ALT:
			tail.append(SC_LALT)
	for pair in [[A.M_CTRL, SC_LCTRL], [A.M_SHIFT, SC_LSHIFT]]:
		if forced & pair[0]:
			tail.append(pair[1])
	# The last packet must leave PICO-8 with the modifier flags that are true.
	var after := _sdl_mods(real & ~A.M_ALT)
	for i in states.size():
		var last: bool = tail.is_empty() and i == states.size() - 1
		s.send_key(states[i].sc, false, false, after if last else states[i].flags)
	for sc in tail:
		s.send_key(sc, false, false, after)

## Types plain text into PICO-8 (used to complete a suggestion).
func type_text(text: String) -> void:
	var s := _streamer
	if not is_instance_valid(s):
		return
	# The accept combination may still be held; PICO-8 must not read the
	# letters as Ctrl/Shift shortcuts. _sync_mods puts them back if needed.
	var held := _virtual_mods()
	if Input.is_key_pressed(KEY_CTRL): held |= A.M_CTRL
	if Input.is_key_pressed(KEY_SHIFT): held |= A.M_SHIFT
	for pair in [[A.M_CTRL, SC_LCTRL], [A.M_SHIFT, SC_LSHIFT]]:
		if (held & pair[0]) and not (_lifted & pair[0]):
			s.send_key(pair[1], false, false, 0)
			_lifted |= pair[0]
	for i in text.length():
		var ch := text[i]
		var code := ch.unicode_at(0)
		var name := ch.to_upper()
		var flags := 0
		if A.CHAR_KEYS.has(ch):
			name = A.CHAR_KEYS[ch][0]
			flags = SDL_SHIFT if A.CHAR_KEYS[ch][1] else 0
		var sc := int(s.SDL_KEYMAP.get(name, -1))
		if sc >= 0:
			s.send_key(sc, true, false, flags)
		if code < 256:
			s.send_input(code)
		if sc >= 0:
			s.send_key(sc, false, false, 0)

func _host(id: String) -> void:
	var s := _streamer
	match id:
		"toggle_game_keys":
			_game_override = not game_keys_active()
			if assist:
				assist.toast("GAME KEYS " + ("ON" if _game_override else "OFF"))
		"accept_suggestion":
			if assist:
				assist.accept_suggestion(0)
		"options_menu":
			s._toggle_options_menu()
		"cheat_sheet":
			open_cheat_sheet()

# ------------------------------------------------------------------- nodes

func _attach(s: Node) -> void:
	_streamer = s
	_active.clear()
	_swallowed.clear()
	_lifted = 0
	_forced = 0

	var input_node := InputNode.new()
	input_node.name = "PhysKbInput"
	s.add_child(input_node)

	assist = Assist.new()
	assist.name = "PhysKbAssist"
	s.add_child(assist)

	_holders.clear()
	for path in ["Arranger", "LandscapeUI"]:
		var parent = s.get_node_or_null(path)
		if parent == null:
			continue
		var holder := Control.new()
		holder.name = "PhysKbKeys"
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(holder)
		_holders.append(holder)
		if path == "Arranger":
			_portrait_holder = holder
	_build_vkeys()

func _build_vkeys() -> void:
	for holder in _holders:
		if not is_instance_valid(holder):
			continue
		for child in holder.get_children():
			holder.remove_child(child)
			child.queue_free()
		var keys: Array = []
		for id in vkeys:
			if _by_id.has(id):
				keys.append(_make_vkey(_by_id[id]))
		if keys.is_empty():
			continue
		if vkey_layout == VKeyLayout.GRID:
			var bar := Bar.new()
			bar.setup(keys)
			holder.add_child(bar)
			continue
		# Free layout. Default slots: rows growing up from the bottom-right
		# corner (the layout zoom/reset controls live bottom-left).
		var slot := Vector2.ZERO
		for key in keys:
			if slot.x > 0 and slot.x + key.size.x > VKEY_ROW_UNITS:
				slot = Vector2(0, slot.y + 1)
			key.slot = slot
			slot.x += key.size.x + 2
			holder.add_child(key)

func _make_vkey(a: Dictionary) -> Control:
	var key: Control = make_tile(a.cap, a.font)
	key.name = "pk_" + a.id
	key.action_id = a.id
	key.can_lock = a.get("modifier", false)
	return key

## A key.tscn instance running physkb_vkey.gd, styled like the keyboard keys.
func make_tile(cap: String, font: int = A.F_SYMBOL) -> Control:
	var key: Control = KEY_SCENE.instantiate()
	key.set_script(VKey)
	key.texture_normal = TEX_KEY
	key.texture_pressed = TEX_KEY_PRESSED
	key.cap_text = cap
	key.cap_type_shift = 2 # KeycapType.NONE: same cap with Shift
	key.font_type = font
	key.unicode = false
	if font != A.F_NORMAL:
		key.font_color = Color(0.5176471, 0.47058824, 0.63529414, 1)
	var w := 12.0
	if font == A.F_SMALL:
		w = 22.0 if cap.length() > 3 else (16.0 if cap.length() > 2 else 12.0)
	# Placed and resized with Options > Customize Layout, exactly like the
	# built-in buttons; physkb_vkey.gd parks them in a default slot until then.
	key.size = Vector2(w, 11)
	key.scale = Vector2(VKEY_SCALE, VKEY_SCALE)
	key.z_index = 150
	return key

## Moves an on-screen button to another place in the order (grid layout).
func move_vkey(id: String, index: int) -> void:
	if not vkeys.has(id) or index < 0:
		return
	vkeys.erase(id)
	vkeys.insert(min(index, vkeys.size()), id)
	PicoBootManager.set_setting(SECTION, "vkeys", vkeys)
	_build_vkeys.call_deferred()

## Customize Layout: keep the zoom / reset controls off the selected item.
func _dodge_layout_controls(s: Node) -> void:
	var lc: Control = s.get_node_or_null("OverlayUI/LayoutControls")
	if lc == null or not lc.visible:
		return
	var sel = s.selected_control
	var h: float = lc.size.y * lc.scale.y
	var w: float = lc.size.x * lc.scale.x
	var vp: Vector2 = lc.get_viewport_rect().size
	# Home is the bottom-left corner; the box is scaled around its own
	# bottom-left (see arranger.gd), so its unscaled bottom edge is the anchor.
	var bottom: float = vp.y - 20.0
	if is_instance_valid(sel) and sel is Control:
		var home := Rect2(0, bottom - h, w, h).grow(20)
		if home.intersects(sel.get_global_rect()):
			bottom = 20.0 + h # move to the top-left corner instead
	lc.position.y = bottom - lc.size.y

func open_editor() -> void:
	var root := get_tree().root
	if root.has_node("PhysKbEditor"):
		return
	var ed := Editor.new()
	ed.name = "PhysKbEditor"
	root.add_child(ed)

func open_cheat_sheet() -> void:
	var root := get_tree().root
	if root.has_node("PhysKbCheatSheet"):
		root.get_node("PhysKbCheatSheet").queue_free()
		return
	var sheet := CheatSheet.new()
	sheet.name = "PhysKbCheatSheet"
	root.add_child(sheet)

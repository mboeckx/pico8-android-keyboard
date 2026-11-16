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
const KEY_SCENE = preload("res://key.tscn")
const TEX_KEY = preload("res://assets/key.png")
const TEX_KEY_PRESSED = preload("res://assets/key_pressed.png")

const SECTION := "physkb"
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

signal changed

var enabled: bool = true
var game_keys_mode: int = GameKeys.AUTO
var hold_docs: bool = true
var suggestions: bool = true
var usage_hints: bool = true
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
var _phys_mods: int = 0
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

# ---------------------------------------------------------------- settings

func _load() -> void:
	enabled = PicoBootManager.get_setting(SECTION, "enabled", true)
	game_keys_mode = PicoBootManager.get_setting(SECTION, "game_keys_mode", GameKeys.AUTO)
	hold_docs = PicoBootManager.get_setting(SECTION, "hold_docs", true)
	suggestions = PicoBootManager.get_setting(SECTION, "suggestions", true)
	usage_hints = PicoBootManager.get_setting(SECTION, "usage_hints", true)
	var b = PicoBootManager.get_setting(SECTION, "bindings", {})
	bindings = b if b is Dictionary else {}
	var v = PicoBootManager.get_setting(SECTION, "vkeys", [])
	vkeys = v if v is Array else []

func set_option(key: String, value) -> void:
	set(key, value)
	PicoBootManager.set_setting(SECTION, key, value)
	if key == "game_keys_mode":
		_game_override = null
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
		# A shortcut still on PICO-8's own combination needs no translation.
		if a.has("native") and c == int(a.native):
			continue
		var table := _game_lookup if a.group == A.G_GAME else _main_lookup
		if not table.has(c):
			table[c] = a
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

## Modifiers PICO-8 currently believes are down (physical + on-screen).
func _held_mods() -> int:
	return _phys_mods | _virtual_mods()

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
	if is_modifier_key(key):
		var bit := 0
		match key:
			KEY_SHIFT: bit = A.M_SHIFT
			KEY_CTRL: bit = A.M_CTRL
		if ev.pressed: _phys_mods |= bit
		else: _phys_mods &= ~bit
		return false

	if not ev.pressed:
		if _active.has(key):
			_release(key)
			return true
		if _swallowed.erase(key):
			return true
		return false

	if _active.has(key):
		_repeat(key)
		return true
	if _swallowed.has(key):
		return true

	if enabled:
		var combo := A.combo(event_mods(ev), key)
		var extra := 0
		var act = _resolve(combo)
		if act == null and (combo >> 24) & A.M_SHIFT:
			# Let Shift ride along (e.g. Shift + an arrow binding selects text).
			act = _resolve(combo & ~(A.M_SHIFT << 24))
			if act != null and act.kind != "key":
				act = null
			extra = A.M_SHIFT
		if act != null:
			_press(key, act, extra)
			return true
		if _blocked.has(combo):
			_swallowed[key] = true
			return true

	if assist:
		assist.note_event(ev)
	return false

func _resolve(combo: int):
	if game_keys_active() and _game_lookup.has(combo):
		return _game_lookup[combo]
	return _main_lookup.get(combo)

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
	if down:
		if echo:
			_repeat(token)
		else:
			if PicoVideoStreamer.get_haptic_enabled():
				Input.vibrate_handheld(35, 1)
			_press(token, a, 0)
	else:
		_release(token)

# ------------------------------------------------------------------ output

func _press(token, a: Dictionary, extra_mods: int) -> void:
	var s := _streamer
	if not is_instance_valid(s):
		return
	if a.kind == "host":
		_swallowed[token] = true
		_host(a.id)
		return

	var sc := -1
	var mods := 0
	var flags := 0
	var text := 0
	if a.kind == "char":
		var info: Array = A.CHAR_KEYS.get(a.ch, [])
		if info.is_empty():
			return
		sc = int(s.SDL_KEYMAP.get(info[0], -1))
		flags = SDL_SHIFT if info[1] else 0
		text = a.ch.unicode_at(0)
	else:
		sc = int(s.SDL_KEYMAP.get(a.key, -1))
		mods = int(a.mods) | extra_mods
		flags = _sdl_mods(mods)
	if sc < 0:
		return

	# Make PICO-8 see exactly the output's modifiers: lift the ones the user is
	# holding for the combination, press the ones the output needs.
	var held := _held_mods()
	var lifted := 0
	for pair in [[A.M_CTRL, SC_LCTRL], [A.M_SHIFT, SC_LSHIFT]]:
		var bit: int = pair[0]
		if (held & bit) and not (mods & bit):
			s.send_key(pair[1], false, false, flags)
			lifted |= bit
		elif (mods & bit) and not (held & bit):
			s.send_key(pair[1], true, false, flags)
	if mods & A.M_ALT:
		s.send_key(SC_LALT, true, false, flags)

	s.send_key(sc, true, false, flags)
	if text:
		s.send_input(text)
	_active[token] = {"sc": sc, "mods": mods, "flags": flags, "text": text, "lifted": lifted}

	if assist:
		if a.kind == "char":
			assist.note_char(a.ch)
		elif a.get("key", "") == "Backspace" and mods == 0:
			assist.note_backspace()
		else:
			assist.note_break()

func _repeat(token) -> void:
	var s := _streamer
	if not is_instance_valid(s) or not _active.has(token):
		return
	var st: Dictionary = _active[token]
	if st.mods & (A.M_CTRL | A.M_ALT):
		return # chords fire once
	s.send_key(st.sc, true, true, st.flags)
	if st.text:
		s.send_input(st.text)
		if assist:
			assist.note_char(String.chr(st.text))

func _release(token) -> void:
	if _swallowed.erase(token):
		return
	if not _active.has(token):
		return
	var st: Dictionary = _active[token]
	_active.erase(token)
	var s := _streamer
	if not is_instance_valid(s):
		return
	var held := _held_mods()
	var after := _sdl_mods(held)
	var follow: Array = [] # [scancode, down]
	if st.mods & A.M_ALT:
		follow.append([SC_LALT, false])
	for pair in [[A.M_CTRL, SC_LCTRL], [A.M_SHIFT, SC_LSHIFT]]:
		var bit: int = pair[0]
		if (st.mods & bit) and not (held & bit):
			follow.append([pair[1], false])
		elif (st.lifted & bit) and (held & bit):
			follow.append([pair[1], true]) # user still holds it: put it back
	# The last packet must carry the modifier state PICO-8 is left in.
	s.send_key(st.sc, false, false, st.flags if not follow.is_empty() else after)
	for f in follow:
		s.send_key(f[0], f[1], false, after)

## Types plain text into PICO-8 (used to complete a suggestion).
func type_text(text: String) -> void:
	var s := _streamer
	if not is_instance_valid(s):
		return
	# The accept combination may still be held; PICO-8 must not read the
	# letters as Ctrl/Shift shortcuts.
	var held := _held_mods()
	if held & A.M_CTRL: s.send_key(SC_LCTRL, false, false, 0)
	if held & A.M_SHIFT: s.send_key(SC_LSHIFT, false, false, 0)
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
	if held & A.M_CTRL: s.send_key(SC_LCTRL, true, false, _sdl_mods(held))
	if held & A.M_SHIFT: s.send_key(SC_LSHIFT, true, false, _sdl_mods(held))

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

# ------------------------------------------------------------------- nodes

func _attach(s: Node) -> void:
	_streamer = s
	_active.clear()
	_swallowed.clear()
	_phys_mods = 0

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
		# Default slots: rows growing up from the bottom-left corner.
		var slot := Vector2.ZERO
		for id in vkeys:
			if not _by_id.has(id):
				continue
			var key = _make_vkey(_by_id[id])
			if slot.x > 0 and slot.x + key.size.x > VKEY_ROW_UNITS:
				slot = Vector2(0, slot.y + 1)
			key.slot = slot
			slot.x += key.size.x + 2
			holder.add_child(key)

func _make_vkey(a: Dictionary) -> Control:
	var key: Control = KEY_SCENE.instantiate()
	key.set_script(VKey)
	key.name = "pk_" + a.id
	key.action_id = a.id
	key.texture_normal = TEX_KEY
	key.texture_pressed = TEX_KEY_PRESSED
	key.cap_text = a.cap
	key.cap_type_shift = 2 # KeycapType.NONE: same cap with Shift
	key.font_type = a.font
	key.unicode = false
	key.can_lock = a.get("modifier", false)
	if a.font != A.F_NORMAL:
		key.font_color = Color(0.5176471, 0.47058824, 0.63529414, 1)
	var w := 12.0
	if a.font == A.F_SMALL:
		w = 22.0 if a.cap.length() > 3 else (16.0 if a.cap.length() > 2 else 12.0)
	# Placed and resized with Options > Customize Layout, exactly like the
	# built-in buttons; physkb_vkey.gd parks them in a default slot until then.
	key.size = Vector2(w, 11)
	key.scale = Vector2(VKEY_SCALE, VKEY_SCALE)
	key.z_index = 150
	return key

func open_editor() -> void:
	var root := get_tree().root
	if root.has_node("PhysKbEditor"):
		return
	var ed := Editor.new()
	ed.name = "PhysKbEditor"
	root.add_child(ed)

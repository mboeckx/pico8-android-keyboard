extends RefCounted
## Action table for the physical keyboard module.
##
## Every action can be triggered by a physical key combination (rebindable,
## clearable) and/or by an on-screen button. What an action *does* is fixed:
##   kind "key"  -> sends an SDL key (+ modifiers) to PICO-8
##   kind "char" -> types a character
##   kind "host" -> does something in the Android frontend
##
## A combo is stored as one int: (modifier bits << 24) | Godot Key value.

const M_SHIFT := 1
const M_CTRL := 2
const M_ALT := 4
const M_META := 8

const G_GAME := "game"
const G_KEYS := "keys"
const G_CHARS := "chars"
const G_SHORTCUTS := "shortcuts"
const G_APP := "app"

## [id, title, hint]
const GROUPS := [
	[G_GAME, "🎮 GAME KEYS", "Used in Splore and while a cart runs."],
	[G_KEYS, "⌨ MISSING KEYS", "Keys your keyboard may not have."],
	[G_CHARS, "🔣 CHARACTERS", "Type a character with a key combination."],
	[G_SHORTCUTS, "🛠 PICO-8 SHORTCUTS", "Move a shortcut, or clear it to disable it."],
	[G_APP, "📱 APP", ""],
]

# key.gd FontType values used for on-screen caps
const F_NORMAL := 0
const F_SMALL := 3
const F_SYMBOL := 5

## US layout: character -> [SDL key name, needs shift]
const CHAR_KEYS := {
	"[": ["BracketLeft", false], "]": ["BracketRight", false],
	"{": ["BracketLeft", true], "}": ["BracketRight", true],
	"(": ["9", true], ")": ["0", true],
	"<": ["Comma", true], ">": ["Period", true],
	"=": ["Equal", false], "+": ["Equal", true],
	"-": ["Minus", false], "_": ["Minus", true],
	"*": ["8", true], "/": ["Slash", false], "?": ["Slash", true],
	"\\": ["BackSlash", false], "|": ["BackSlash", true],
	"^": ["6", true], "~": ["QuoteLeft", true], "`": ["QuoteLeft", false],
	"#": ["3", true], "%": ["5", true], "&": ["7", true],
	"\"": ["Apostrophe", true], "'": ["Apostrophe", false],
	":": ["Semicolon", true], ";": ["Semicolon", false],
	"!": ["1", true], "@": ["2", true], "$": ["4", true],
	",": ["Comma", false], ".": ["Period", false],
	"0": ["0", false], "1": ["1", false], "2": ["2", false], "3": ["3", false],
	"4": ["4", false], "5": ["5", false], "6": ["6", false], "7": ["7", false],
	"8": ["8", false], "9": ["9", false],
}

static func combo(mods: int, key: int) -> int:
	return (mods << 24) | (key & 0xFFFFFF)

static func combo_mods(c: int) -> int:
	return (c >> 24) & 0xF

static func combo_key(c: int) -> int:
	return c & 0xFFFFFF

static func combo_text(c: int) -> String:
	if c == 0:
		return "-"
	var parts: PackedStringArray = []
	var m := combo_mods(c)
	if m & M_CTRL: parts.append("Ctrl")
	if m & M_ALT: parts.append("Alt")
	if m & M_SHIFT: parts.append("Shift")
	if m & M_META: parts.append("Meta")
	var k := OS.get_keycode_string(combo_key(c))
	parts.append(k if not k.is_empty() else "Key%d" % combo_key(c))
	return "+".join(parts)

static func _key(id: String, group: String, label: String, sdl_key: String, mods: int, def: int, cap: String, font: int = F_SMALL, extra: Dictionary = {}) -> Dictionary:
	var a := {
		"id": id, "group": group, "label": label, "kind": "key",
		"key": sdl_key, "mods": mods, "def": def, "cap": cap, "font": font,
	}
	a.merge(extra)
	return a

## A PICO-8 shortcut. Its default binding is the combination PICO-8 itself
## listens for, so nothing changes until the user rebinds or clears it.
static func _shortcut(id: String, label: String, sdl_key: String, mods: int, cap: String, def: int = -1) -> Dictionary:
	var native := combo(mods, OS.find_keycode_from_string(sdl_key))
	return _key(id, G_SHORTCUTS, label, sdl_key, mods, native if def == -1 else def, cap, F_SMALL, {"native": native})

static func _char(ch: String) -> Dictionary:
	return {
		"id": "ch_%d" % ch.unicode_at(0), "group": G_CHARS, "label": ch, "kind": "char",
		"ch": ch, "def": 0, "cap": ch, "font": F_NORMAL,
	}

static func _host(id: String, label: String, def: int, cap: String) -> Dictionary:
	return {"id": id, "group": G_APP, "label": label, "kind": "host", "def": def, "cap": cap, "font": F_SMALL}

static func build() -> Array:
	var C := M_CTRL
	var A := M_ALT
	var S := M_SHIFT
	var list: Array = []

	# --- Game keys (only active in Splore / in game) ---
	list.append(_key("game_left", G_GAME, "Left", "Left", 0, combo(0, KEY_A), "⬅︎", F_SYMBOL))
	list.append(_key("game_right", G_GAME, "Right", "Right", 0, combo(0, KEY_D), "➡︎", F_SYMBOL))
	list.append(_key("game_up", G_GAME, "Up", "Up", 0, combo(0, KEY_W), "⬆︎", F_SYMBOL))
	list.append(_key("game_down", G_GAME, "Down", "Down", 0, combo(0, KEY_S), "⬇︎", F_SYMBOL))
	list.append(_key("game_o", G_GAME, "O button", "Z", 0, combo(0, KEY_O), "o", F_NORMAL))
	list.append(_key("game_x", G_GAME, "X button", "X", 0, combo(0, KEY_P), "x", F_NORMAL))
	list.append(_key("game_pause", G_GAME, "Pause menu", "P", 0, 0, "pse"))
	list.append(_key("game_esc", G_GAME, "Esc / exit", "Escape", 0, combo(0, KEY_Q), "esc"))

	# --- Keys that small keyboards lack ---
	list.append(_key("esc", G_KEYS, "Esc", "Escape", 0, combo(C, KEY_Q), "esc"))
	list.append(_key("up", G_KEYS, "Arrow up", "Up", 0, 0, "⬆︎", F_SYMBOL))
	list.append(_key("down", G_KEYS, "Arrow down", "Down", 0, 0, "⬇︎", F_SYMBOL))
	list.append(_key("left", G_KEYS, "Arrow left", "Left", 0, 0, "⬅︎", F_SYMBOL))
	list.append(_key("right", G_KEYS, "Arrow right", "Right", 0, 0, "➡︎", F_SYMBOL))
	list.append(_key("tab", G_KEYS, "Tab", "Tab", 0, 0, "tab"))
	list.append(_key("enter", G_KEYS, "Enter", "Enter", 0, 0, "ret"))
	list.append(_key("backspace", G_KEYS, "Backspace", "Backspace", 0, 0, "bsp"))
	list.append(_key("delete", G_KEYS, "Delete", "Delete", 0, 0, "del"))
	list.append(_key("home", G_KEYS, "Home", "Home", 0, 0, "hom"))
	list.append(_key("end", G_KEYS, "End", "End", 0, 0, "end"))
	list.append(_key("pgup", G_KEYS, "Page up", "SDL_PAGEUP", 0, 0, "pgu"))
	list.append(_key("pgdn", G_KEYS, "Page down", "SDL_PAGEDOWN", 0, 0, "pgd"))
	# Modifiers are on-screen only (a modifier cannot be the target of a combo).
	list.append(_key("mod_ctrl", G_KEYS, "Ctrl", "Ctrl", 0, 0, "ctrl", F_SMALL, {"modifier": true}))
	list.append(_key("mod_shift", G_KEYS, "Shift", "Shift", 0, 0, "🔼", F_SYMBOL, {"modifier": true}))
	list.append(_key("mod_alt", G_KEYS, "Alt", "Alt", 0, 0, "alt", F_SMALL, {"modifier": true}))

	# --- Characters ---
	for ch in ["[", "]", "{", "}", "(", ")", "<", ">", "=", "+", "-", "_", "*", "/",
			"\\", "|", "^", "~", "#", "%", "&", "\"", "'", ":", ";", "!", "?", "@", "$",
			",", ".", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		list.append(_char(ch))

	# --- PICO-8 shortcuts ---
	# Ctrl+Q is taken by "Esc" above, so "Quit" starts out disabled.
	list.append(_shortcut("sc_quit", "Quit PICO-8", "Q", C, "quit", 0))
	list.append(_shortcut("sc_run", "Run cart", "R", C, "run"))
	list.append(_shortcut("sc_save", "Save", "S", C, "save"))
	list.append(_shortcut("sc_mute", "Mute", "M", C, "mute"))
	list.append(_shortcut("sc_screenshot", "Screenshot", "F6", 0, "shot"))
	list.append(_shortcut("sc_label", "Capture cart label", "F7", 0, "lbl"))
	list.append(_shortcut("sc_video", "Start video", "F8", 0, "vid"))
	list.append(_shortcut("sc_gif", "Save GIF", "F9", 0, "gif"))
	list.append(_shortcut("sc_cut", "Cut", "X", C, "cut"))
	list.append(_shortcut("sc_copy", "Copy", "C", C, "copy"))
	list.append(_shortcut("sc_paste", "Paste", "V", C, "pst"))
	list.append(_shortcut("sc_undo", "Undo", "Z", C, "undo"))
	list.append(_shortcut("sc_redo", "Redo", "Y", C, "redo"))
	list.append(_shortcut("sc_select_all", "Select all", "A", C, "all"))
	list.append(_shortcut("sc_find", "Find", "F", C, "find"))
	list.append(_shortcut("sc_find_next", "Find next", "G", C, "next"))
	list.append(_shortcut("sc_goto", "Go to line", "L", C, "goto"))
	list.append(_shortcut("sc_dup", "Duplicate line", "D", C, "dup"))
	list.append(_shortcut("sc_comment", "Comment block", "B", C, "--"))
	list.append(_shortcut("sc_line_start", "Line start", "W", C, "bol"))
	list.append(_shortcut("sc_line_end", "Line end", "E", C, "eol"))
	list.append(_shortcut("sc_file_start", "Top of file", "Up", C, "top"))
	list.append(_shortcut("sc_file_end", "End of file", "Down", C, "bot"))
	list.append(_shortcut("sc_word_left", "Previous word", "Left", C, "wl"))
	list.append(_shortcut("sc_word_right", "Next word", "Right", C, "wr"))
	list.append(_shortcut("sc_func_up", "Previous function", "Up", A, "fnu"))
	list.append(_shortcut("sc_func_down", "Next function", "Down", A, "fnd"))
	list.append(_shortcut("sc_editor_prev", "Previous editor", "Left", A, "edl"))
	list.append(_shortcut("sc_editor_next", "Next editor", "Right", A, "edr"))
	list.append(_shortcut("sc_tab_prev", "Previous code tab", "Tab", C | S, "tbl"))
	list.append(_shortcut("sc_tab_next", "Next code tab", "Tab", C, "tbr"))
	list.append(_shortcut("sc_puny", "Puny font / CPU meter", "P", C, "puny"))

	# --- App ---
	list.append(_host("toggle_game_keys", "Game keys on/off", combo(C | S, KEY_G), "gkey"))
	list.append(_host("accept_suggestion", "Accept suggestion", combo(C, KEY_SPACE), "ok"))
	list.append(_host("options_menu", "Options menu", 0, "opt"))
	return list

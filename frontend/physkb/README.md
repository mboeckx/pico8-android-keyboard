# physkb – physical keyboard support

A self-contained module. Removing it means deleting this folder, the `PhysKb`
autoload line in `project.godot` and the *Keyboard Mapping* button in
`options_menu.tscn` / `options_menu.gd` (3 short additions).

| File | Role |
| --- | --- |
| `physkb.gd` | Autoload `PhysKb`: settings, binding lookup, translating key events into what PICO-8 receives. |
| `physkb_actions.gd` | The list of actions (game keys, keys, characters, PICO-8 shortcuts, app actions) and their defaults. |
| `physkb_input.gd` | Node added under `Main` at runtime; sees key events before `PicoVideoStreamer` and consumes the translated ones. |
| `physkb_vkey.gd` | On-screen button for an action; extends `key.gd`, so layout customisation works unchanged. |
| `physkb_bar.gd` | "Grid" layout: the on-screen buttons as equal tiles in rows across the screen. |
| `physkb_cheatsheet.gd` | The built-in PICO-8 cheat sheet screen. |
| `physkb_editor.gd` | The *Keyboard Mapping* screen. |
| `physkb_code_assist.gd` | Hold-for-docs, suggestions and usage hints over the code editor. |
| `physkb_api_docs.gd` | The PICO-8 reference texts. |
| `physkb_font.gd` | PICO-8 font bitmaps (generated from `assets/font/pico-8.ttf`) used to read words off the screen. |

## How it hooks in

Nothing in `video_streamer.gd` is changed. `PhysKb` waits for
`PicoVideoStreamer.instance`, then adds its helper nodes as children of the
main scene. A child node gets `_unhandled_input` before its parent, so
`physkb_input.gd` can call `set_input_as_handled()` for keys it translates;
everything else reaches `PicoVideoStreamer` untouched. Output goes through the
streamer's existing `send_key()` / `send_input()` / `vkb_setstate()`.

Settings are stored in the `[physkb]` section of `user://settings.cfg`.

## Behaviour notes

*   A binding is a physical key plus Ctrl/Alt/Shift, so it is independent of
    what character the key would type.
*   A PICO-8 shortcut left on its own combination is not touched at all. Once it
    is moved or cleared, its original combination is swallowed.
*   A combination shared by several actions is allowed: the editor marks it
    and pressing it fires all of them.
*   Esc and the PICO-8 shortcuts fire once per press (no auto-repeat).
*   Modifier state is read from each key event. Ctrl/Shift lifted for a
    translated key are only pressed again when a later key event shows them
    still held.
*   Shift may be added to a key binding and is passed on (Shift + an arrow
    binding selects text).
*   The current screen (Splore / game / editor) comes from the shim's NavState,
    which is only available with PICO-8 0.2.7. Without it "Auto" game keys stay
    off and the code helpers are always available.
*   Suggestions follow the keys typed on a physical or Android keyboard; when
    that trail is lost (cursor moved, deleting older text) the word before the
    cursor is read from the screen instead. The built-in on-screen keyboard is
    not tracked.
*   In Customize Layout the zoom/reset box moves to the top-left while the
    selected item is underneath its usual corner (`_dodge_layout_controls`).

extends "res://key.gd"
## On-screen button for a PhysKb action. Reuses key.gd for everything visual
## (textures, press/lock states, drag + zoom in Customize Layout, saved
## positions) and only changes what a press sends.

var action_id: String = ""
## Default spot, set by PhysKb: x offset in key units and row, counted from
## the bottom-right corner of the screen.
var slot: Vector2 = Vector2.ZERO
## True when this button is a tile of the grid bar (physkb_bar.gd places it).
var docked: bool = false

func _ready() -> void:
	super._ready()
	_show_cap()

func reload_textures() -> void:
	super.reload_textures()
	_show_cap()

func _show_cap() -> void:
	# key.gd hides caps outside the full keyboard; these buttons need theirs.
	%Label.visible = true
	_update_visuals()

func _update_visuals() -> void:
	super._update_visuals()
	# key.gd sizes the cap from get_rect(), which includes this node's scale;
	# these buttons are scaled, so size it from the unscaled key instead.
	%Label.size = size / %Label.scale

func _process(delta: float) -> void:
	super._process(delta)
	# Until the user has placed this button (Customize Layout saves a position
	# for it) keep it parked in its default slot, whatever the screen does.
	if docked or not active_touches.is_empty():
		return
	if PicoVideoStreamer.get_control_pos(name, _is_in_landscape_ui()) == null:
		var xf: Transform2D = get_parent().get_global_transform()
		var px := xf.get_scale().x * scale.x # screen pixels per key unit
		var vp := get_viewport_rect().size
		var at := Vector2(vp.x - (2 + slot.x + size.x) * px, vp.y - (2 + (slot.y + 1) * 13) * px)
		position = xf.affine_inverse() * at

func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)
	# Optional snap: when a drag ends, settle on the nearest grid point.
	if docked or not (PicoVideoStreamer.display_drag_enabled and is_repositionable and PhysKb.vkey_snap):
		return
	var released: bool = (event is InputEventScreenTouch or event is InputEventMouseButton) and not event.pressed
	if released:
		position = position.snapped(Vector2.ONE * PhysKb.SNAP_UNITS)
		_save_layout()

func send_ev(down: bool, echo: bool = false) -> void:
	PhysKb.vkey_event(action_id, down, echo)

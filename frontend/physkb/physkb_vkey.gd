extends "res://key.gd"
## On-screen button for a PhysKb action. Reuses key.gd for everything visual
## (textures, press/lock states, drag + zoom in Customize Layout, saved
## positions) and only changes what a press sends.

var action_id: String = ""
## Default spot, set by PhysKb: x offset in key units and row, counted from
## the bottom-left corner of the screen.
var slot: Vector2 = Vector2.ZERO

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
	if active_touches.is_empty() and PicoVideoStreamer.get_control_pos(name, _is_in_landscape_ui()) == null:
		var xf: Transform2D = get_parent().get_global_transform()
		var px := xf.get_scale().x * scale.x # screen pixels per key unit
		var vp := get_viewport_rect().size
		var at := Vector2((2 + slot.x) * px, vp.y - (2 + (slot.y + 1) * 13) * px)
		position = xf.affine_inverse() * at

func send_ev(down: bool, echo: bool = false) -> void:
	PhysKb.vkey_event(action_id, down, echo)

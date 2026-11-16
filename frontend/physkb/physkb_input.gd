extends Node
## Added as a child of the main scene by PhysKb. Children receive
## _unhandled_input before their parent, so this sees key events ahead of
## PicoVideoStreamer and can consume the ones PhysKb translates.

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var streamer = get_parent()
	# Same gates PicoVideoStreamer applies (menus open, controller test, ...).
	if not streamer.is_processing_unhandled_input() or streamer.input_blocked:
		return
	if PhysKb.handle_key(event):
		get_viewport().set_input_as_handled()

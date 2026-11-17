extends Control
## "Grid" layout for the on-screen buttons: equal tiles in rows across the
## screen, like a keyboard row. The bar is one item for Customize Layout:
## zooming it changes the tile size (and so how many fit per row), the grip
## tile moves it up and down, and dragging a tile changes the order.

const TILE := Vector2(18, 11)
const GAP := 1.0
const GRIP_ID := "__grip"

var original_scale: Vector2 = Vector2.ONE
var is_repositionable: bool = true

var _keys: Array = [] # tiles in order
var _grip: Control
var _overlay: Control
var _layout_sig: Array = []
var _drag_tile: Control = null
var _drag_bar: bool = false
var _drag_from: Vector2 = Vector2.ZERO
var _drag_origin: Vector2 = Vector2.ZERO

func setup(keys: Array) -> void:
	_keys = keys
	for k in keys:
		k.is_repositionable = false
		k.docked = true
		k.size = TILE
		k.scale = Vector2.ONE
		k.z_index = 0
		add_child(k)

func _ready() -> void:
	name = "pk_bar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 150
	original_scale = Vector2.ONE * PhysKb.VKEY_SCALE
	scale = original_scale * PicoVideoStreamer.get_control_scale(name, _landscape())

	_grip = PhysKb.make_tile("↕")
	_grip.is_repositionable = false
	_grip.docked = true
	_grip.size = TILE
	_grip.scale = Vector2.ONE
	_grip.z_index = 0
	_grip.visible = false
	add_child(_grip)

	# Sits over the tiles while customising, so presses arrange instead of type.
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.gui_input.connect(_on_overlay_input)
	add_child(_overlay)

	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.layout_reset.connect(_on_layout_reset)

func _landscape() -> bool:
	return LayoutHelper.is_in_landscape_ui(self)

func _save_layout() -> void:
	LayoutHelper.save_layout(self, original_scale.x)

func _on_layout_reset(target_is_landscape: bool) -> void:
	if is_visible_in_tree() and target_is_landscape == _landscape():
		scale = original_scale

## Tiles shown, in order (the grip only while customising).
func _cells() -> Array:
	var cells: Array = []
	if PicoVideoStreamer.display_drag_enabled:
		cells.append(_grip)
	cells.append_array(_keys)
	return cells

func _process(_delta: float) -> void:
	var editing: bool = PicoVideoStreamer.display_drag_enabled
	var xf: Transform2D = get_parent().get_global_transform()
	var px: float = xf.get_scale().x * scale.x # screen pixels per unit
	var vp := get_viewport_rect().size
	var saved = PicoVideoStreamer.get_control_pos(name, _landscape())
	var sig := [editing, px, vp, _keys.size(), saved, _drag_tile, _drag_bar]
	if sig == _layout_sig and not _drag_bar and _drag_tile == null:
		return
	_layout_sig = sig

	_grip.visible = editing
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if editing else Control.MOUSE_FILTER_IGNORE
	move_child(_overlay, -1)

	var cells := _cells()
	var step := TILE + Vector2(GAP, GAP)
	var width: float = vp.x / px # bar width in units
	var cols: int = max(1, int((width + GAP) / step.x))
	var rows: int = max(1, ceili(cells.size() / float(cols)))
	var used: float = min(cols, cells.size()) * step.x - GAP
	var left: float = (width - used) / 2.0
	for i in cells.size():
		if cells[i] == _drag_tile:
			continue
		cells[i].position = Vector2(left + (i % cols) * step.x, (i / cols) * step.y)
	size = Vector2(width, rows * step.y - GAP)
	_overlay.position = Vector2.ZERO
	_overlay.size = size

	# Full width from the left screen edge; vertical spot is the saved one,
	# by default the bottom of the screen. Always kept on screen.
	if not _drag_bar:
		var y_screen: float = vp.y - size.y * px - 2.0 * px
		if saved != null:
			y_screen = (xf * Vector2(0, saved.y)).y
		y_screen = clamp(y_screen, 0.0, max(0.0, vp.y - size.y * px))
		position = xf.affine_inverse() * Vector2(0, y_screen)

func _cell_index_at(local: Vector2) -> int:
	var cells := _cells()
	var step := TILE + Vector2(GAP, GAP)
	var width: float = size.x
	var cols: int = max(1, int((width + GAP) / step.x))
	var used: float = min(cols, cells.size()) * step.x - GAP
	var left: float = (width - used) / 2.0
	var col: int = clamp(int((local.x - left) / step.x), 0, cols - 1)
	var row: int = max(0, int(local.y / step.y))
	return clamp(row * cols + col, 0, cells.size() - 1)

func _on_overlay_input(event: InputEvent) -> void:
	var is_press: bool = event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	var is_move: bool = event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT))
	if is_press and event.pressed:
		if PicoVideoStreamer.instance:
			PicoVideoStreamer.instance.selected_control = self
			PicoVideoStreamer.instance.control_selected.emit(self)
		var cell: Control = _cells()[_cell_index_at(event.position)]
		_drag_from = event.position
		if cell == _grip:
			_drag_bar = true
		else:
			_drag_tile = cell
			_drag_origin = cell.position
			cell.z_index = 10
		_overlay.accept_event()
	elif is_move:
		if _drag_bar:
			position.y += (event.position.y - _drag_from.y) * scale.y
		elif _drag_tile:
			_drag_tile.position = _drag_origin + (event.position - _drag_from)
		_overlay.accept_event()
	elif is_press and not event.pressed:
		if _drag_bar:
			_drag_bar = false
			_save_layout()
		elif _drag_tile:
			var tile := _drag_tile
			_drag_tile = null
			tile.z_index = 0
			var target: Control = _cells()[_cell_index_at(event.position)]
			if target != tile and target != _grip:
				PhysKb.move_vkey(tile.action_id, _keys.find(target))
		_layout_sig = []
		_overlay.accept_event()

extends CanvasLayer

const LOCKED_COLOR := Color(0.35, 0.35, 0.35, 0.75)
const UNLOCKED_COLOR := Color(1, 1, 1, 1)

@export var player_path: NodePath

@onready var _player: Node = get_node_or_null(player_path)

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(player_path)
		if _player == null:
			return

	_update_icon("DoubleJump", bool(_player.get("can_double_jump")))
	_update_icon("Dash", bool(_player.get("can_dash")))
	_update_icon("WallJump", bool(_player.get("can_wall_jump")))
	_update_icon("GroundPound", bool(_player.get("can_ground_pound")))

func _update_icon(node_name: String, unlocked: bool) -> void:
	var icon := get_node_or_null("Panel/%s" % node_name)
	if icon is CanvasItem:
		(icon as CanvasItem).modulate = UNLOCKED_COLOR if unlocked else LOCKED_COLOR

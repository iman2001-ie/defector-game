class_name LevelClearBanner
extends Label
## Placeholder "LEVEL CLEAR" banner (real level-clear progression arrives in
## Epic 4). Hidden until Events.level_cleared; reads nothing but Events.

const TEXT: String = "LEVEL CLEAR"


func _ready() -> void:
	text = TEXT
	visible = false
	Events.level_cleared.connect(_on_events_level_cleared)


func _on_events_level_cleared(_level_id: int) -> void:
	visible = true

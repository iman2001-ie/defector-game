class_name Playfield
## The fixed logical playfield (architecture: 1920x1080, no scrolling). It
## matches the window viewport size in project.godot; gameplay code reads it here
## instead of from ProjectSettings. test_playfield checks the two agree.

const SIZE: Vector2 = Vector2(1920, 1080)
const RECT: Rect2 = Rect2(Vector2.ZERO, SIZE)

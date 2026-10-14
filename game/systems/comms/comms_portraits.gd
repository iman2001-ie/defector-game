class_name CommsPortraits
extends RefCounted
## The comms portraits (Story 8.2): speaker id -> preloaded portrait texture
## (project-owned SVG busts in assets/portraits/). CommsPanel and CommsBox copy
## TEXTURES into their `portraits` map in _ready and show the speaker's texture
## in `Portrait/Image` when comms.speakers.<id>.portrait is true; a speaker with
## a portrait but no texture here keeps the placeholder initial. Vale and the
## system have no portrait (comms.speakers), so they have no entry.

const TEXTURES: Dictionary[StringName, Texture2D] = {
	&"isolde": preload("res://assets/portraits/portrait_isolde.svg"),
	&"tarek": preload("res://assets/portraits/portrait_tarek.svg"),
	&"ryn": preload("res://assets/portraits/portrait_ryn.svg"),
}


## The portrait texture for `speaker` (null when it has none).
static func texture_for(speaker: StringName) -> Texture2D:
	return TEXTURES.get(speaker) as Texture2D


## The Image rect inside a `size` portrait frame: the frame's rect inset by its
## border widths (a StyleBoxFlat), so the accent border stays visible around
## the picture; the whole frame for any other style.
static func image_rect(size: Vector2, frame: StyleBox) -> Rect2:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var flat: StyleBoxFlat = frame as StyleBoxFlat
	if flat == null:
		return rect
	return rect.grow_individual(
		-flat.get_border_width(SIDE_LEFT), -flat.get_border_width(SIDE_TOP),
		-flat.get_border_width(SIDE_RIGHT), -flat.get_border_width(SIDE_BOTTOM))

extends RefCounted
## The game's pixel font: Jersey 10 (SIL Open Font License, see fonts/OFL.txt).
## fonts/pixel.tres is the project's default font (Project Settings > GUI > Theme >
## Custom Font), so HUD text, 3D world labels and drawn map text all use it.
## Menus use the "bold" cut: the same letters with a little outline in their own colour.

const FILE := preload("res://fonts/Jersey10-Large.ttf")

static var _bold: FontVariation


static func pixel() -> Font:
	return preload("res://fonts/pixel.tres")


## Chunkier letters for menu text and buttons (embolden keeps the pixel grid shape).
static func bold() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = FILE
		_bold.variation_embolden = 0.6
	return _bold

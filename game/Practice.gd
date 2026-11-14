extends GameState
class_name GameStatePractice

func _ready(game: BeepSaber_Game) -> void:
	game.main_menu._hide()
	game.settings_canvas._hide()
	game.show_MapSourceDialogs(false)
	game.endscore._hide()
	game.pause_menu._hide()
	game.practice_canvas._show()
	# keep the highscores visible while practicing
	game.highscore_canvas._show()
	game.name_selector_canvas._hide()
	game.left_saber._hide()
	game.right_saber._hide()
	game.multiplier_label.visible = false
	game.point_label.visible = false
	game.percent_indicator.visible = false
	game.track.visible = false
	game.left_ui_raycast.visible = true
	game.right_ui_raycast.visible = true
	game.highscore_keyboard._hide()
	game.online_search_keyboard._hide()

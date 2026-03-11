extends "res://addons/gdUnit4/src/GdUnitTestSuite.gd"

func test_input_actions_exist():
    var actions = [
        "move_up", "move_down", "move_left", "move_right", "look", "attack", "interact",
        "crouch", "jump", "previous", "next", "sprint", "camera_switch",
        "ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel"
    ]
    for action in actions:
        assert_true(InputMap.has_action(action), "Missing input action: %s" % action)

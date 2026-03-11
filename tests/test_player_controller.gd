extends "res://addons/gdUnit4/src/GdUnitTestSuite.gd"

func test_player_controller_script_contract():
    var script = load("res://scripts/player/player_controller.gd")
    assert_not_null(script)

    var player = CharacterBody3D.new()
    player.set_script(script)
    player.set("camera_manager_path", NodePath(""))
    player._physics_process(0.016)

    assert_true(player.has_method("_physics_process"))
    assert_true(player.has_method("_camera_relative_direction"))

func test_camera_manager_has_switch_api():
    var script = load("res://scripts/player/camera_manager.gd")
    assert_not_null(script)
    var manager = Node3D.new()
    manager.set_script(script)
    assert_true(manager.has_method("switch_camera"))
    assert_true(manager.has_method("get_active_basis"))

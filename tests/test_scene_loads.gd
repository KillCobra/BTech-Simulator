extends "res://addons/gdUnit4/src/GdUnitTestSuite.gd"

func test_scenes_load_and_contain_required_nodes():
    var scenes = ["res://scenes/sample_scene.tscn", "res://scenes/initial_hostel.tscn"]
    for scene_path in scenes:
        var packed = load(scene_path)
        assert_not_null(packed, "Scene failed to load: %s" % scene_path)

        var instance = packed.instantiate()
        assert_not_null(instance, "Failed to instantiate: %s" % scene_path)
        assert_true(instance.has_node("Player"), "Missing Player node in %s" % scene_path)
        assert_true(instance.has_node("CameraRig/Camera1"), "Missing Camera1 in %s" % scene_path)
        assert_true(instance.has_node("CameraRig/Camera2"), "Missing Camera2 in %s" % scene_path)
        assert_true(instance.has_node("EnvironmentCollision"), "Missing EnvironmentCollision in %s" % scene_path)
        instance.queue_free()

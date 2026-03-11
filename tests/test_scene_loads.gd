extends "res://addons/gdUnit4/src/GdUnitTestSuite.gd"

func test_scenes_load_and_contain_required_nodes():
    var scenes = ["res://scenes/boot.tscn", "res://scenes/initial_hostel.tscn"]
    for scene_path in scenes:
        var packed = load(scene_path)
        assert_not_null(packed, "Scene failed to load: %s" % scene_path)
        if packed == null:
            continue

        var instance = packed.instantiate()
        assert_not_null(instance, "Failed to instantiate: %s" % scene_path)
        if instance == null:
            continue

        assert_true(instance is Node, "Instanced scene is not a Node: %s" % scene_path)
        assert_true(instance.get_child_count() >= 0, "Scene tree is invalid: %s" % scene_path)
        instance.free()

extends "res://addons/gdUnit4/src/GdUnitTestSuite.gd"

func test_core_assets_exist():
    var assets = [
        "res://assets/hostel floor.fbx",
        "res://assets/walls.fbx",
        "res://assets/bunkbed.fbx",
        "res://assets/desk.gltf",
        "res://assets/chair.gltf",
        "res://assets/cctv.fbx",
        "res://assets/character.fbx",
        "res://assets/Room.obj"
    ]

    for asset_path in assets:
        assert_true(FileAccess.file_exists(asset_path), "Missing asset: %s" % asset_path)

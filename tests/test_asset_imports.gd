extends "res://addons/gdUnit4/src/GdUnitTestSuite.gd"

func test_core_assets_exist():
    var assets = [
        "res://assets/imported/PLAYER.fbx",
        "res://assets/imported/full-room.fbx",
        "res://assets/imported/bunk-bed.fbx",
        "res://assets/imported/curtains.fbx",
        "res://assets/imported/mirror.fbx",
        "res://assets/imported/Goxel Import/Room.obj",
        "res://assets/imported/Test/Switch Camera/SwitchCamera.cs"
    ]

    for asset_path in assets:
        assert_true(FileAccess.file_exists(asset_path), "Missing migrated asset: %s" % asset_path)

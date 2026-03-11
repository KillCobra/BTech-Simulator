extends SceneTree

const TEST_ARG_PREFIX := "--testsuite="

var _tests_root := "tests"

func _init() -> void:
    for arg in OS.get_cmdline_args():
        if arg.begins_with(TEST_ARG_PREFIX):
            _tests_root = arg.substr(TEST_ARG_PREFIX.length())

    var exit_code := _run_tests()
    quit(exit_code)


func _run_tests() -> int:
    var tests_path := _normalize_to_res_path(_tests_root)
    var test_files: Array[String] = []
    _collect_test_files(tests_path, test_files)

    if test_files.is_empty():
        push_error("No test files found in: %s" % tests_path)
        return 1

    test_files.sort()
    var passed := 0
    var failed := 0

    for test_file in test_files:
        var script := load(test_file)
        if script == null:
            push_error("Failed to load test script: %s" % test_file)
            failed += 1
            continue

        var suite = script.new()
        if suite == null:
            push_error("Failed to instantiate test suite: %s" % test_file)
            failed += 1
            continue

        var methods = suite.get_method_list()
        for method in methods:
            var method_name: String = method.name
            if not method_name.begins_with("test_"):
                continue

            GdUnitTestSuite.reset_failures()
            print("[TEST] %s :: %s" % [test_file, method_name])

            suite.call(method_name)
            var failure_count := GdUnitTestSuite.get_failure_count()
            if failure_count > 0:
                failed += 1
                print("[FAIL] %s :: %s (%d assertion failure(s))" % [test_file, method_name, failure_count])
            else:
                passed += 1
                print("[PASS] %s :: %s" % [test_file, method_name])

        if suite is Node:
            suite.free()

    print("[SUMMARY] passed=%d failed=%d" % [passed, failed])
    return 0 if failed == 0 else 1


func _collect_test_files(dir_path: String, out_files: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return

    dir.list_dir_begin()
    while true:
        var entry := dir.get_next()
        if entry == "":
            break
        if entry.begins_with("."):
            continue

        var full_path := dir_path.path_join(entry)
        if dir.current_is_dir():
            _collect_test_files(full_path, out_files)
        elif entry.ends_with(".gd"):
            out_files.append(full_path)
    dir.list_dir_end()


func _normalize_to_res_path(path: String) -> String:
    var normalized := path.strip_edges()
    if normalized.begins_with("res://"):
        return normalized.trim_suffix("/")
    if normalized.begins_with("./"):
        normalized = normalized.substr(2)
    return ("res://" + normalized).trim_suffix("/")

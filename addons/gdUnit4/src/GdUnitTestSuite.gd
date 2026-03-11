extends Node

class_name GdUnitTestSuite

static var _failed_assertions: int = 0

static func reset_failures() -> void:
    _failed_assertions = 0

static func get_failure_count() -> int:
    return _failed_assertions

func _record_failure(message: String) -> void:
    _failed_assertions += 1
    push_error("Assertion failed: %s" % message)

func assert_true(value, message=""):
    if not value:
        _record_failure(message)

func assert_not_null(value, message=""):
    if value == null:
        _record_failure(message)

func assert_false(value, message=""):
    if value:
        _record_failure(message)

# Simple runner helper used by tests (no-op here)
func run_tests():
    pass

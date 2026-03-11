extends Node

class_name GdUnitTestSuite

func assert_true(value, message=""):
    if not value:
        push_error("Assertion failed: %s" % message)

func assert_not_null(value, message=""):
    if value == null:
        push_error("Assertion failed: %s" % message)

func assert_false(value, message=""):
    if value:
        push_error("Assertion failed: %s" % message)

# Simple runner helper used by tests (no-op here)
func run_tests():
    pass

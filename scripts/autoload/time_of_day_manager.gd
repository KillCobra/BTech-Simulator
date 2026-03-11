extends Node

signal time_changed(hour: float)

var hour_of_day := 12.0

func set_time_of_day(new_hour: float) -> void:
    hour_of_day = clampf(new_hour, 0.0, 24.0)
    time_changed.emit(hour_of_day)

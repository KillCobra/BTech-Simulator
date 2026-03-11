extends Node

signal state_changed(previous_state: int, next_state: int)

enum State {
    BOOT,
    LOADING,
    PLAYING,
    PAUSED
}

var current_state: State = State.BOOT

func transition_to(next_state: State) -> void:
    if current_state == next_state:
        return
    var prev := current_state
    current_state = next_state
    state_changed.emit(prev, next_state)

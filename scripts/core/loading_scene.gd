extends CanvasLayer

@onready var progress_bar: ProgressBar = %ProgressBar
@onready var status_label: Label = %StatusLabel

func set_progress(progress: float) -> void:
	var clamped := clampf(progress, 0.0, 1.0)
	if progress_bar:
		progress_bar.value = clamped * 100.0
	if status_label:
		status_label.text = "Loading... %d%%" % int(clamped * 100.0)

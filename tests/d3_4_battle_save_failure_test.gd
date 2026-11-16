extends "res://tests/d3_4_task_loop_test.gd"

func force_battle_save_failure() -> bool:
	return TaskCatalog.selected(main.profile_progress, "main") == "tutorial" and main.maze_controller.run.day == 4

package main

import rl "vendor:raylib"

VSCREEN_SIZE :: [2]i32{1600, 900}

main :: proc() {


	rl.InitWindow(**VSCREEN_SIZE, "game")
	rl.SetWindowState({.WINDOW_RESIZABLE})

	rl.SetTargetFPS(60)

	virtual_screen_init(**VSCREEN_SIZE)

	for !rl.WindowShouldClose() {

		// drawing on virtual_screen
		if virtual_screen_draw() {
			rl.DrawText("Hello world", 0, 0, 69, rl.RED)
		}

		// rendering
		{
			rl.BeginDrawing()
			defer rl.EndDrawing()
			rl.ClearBackground(rl.BLACK)
			virtual_screen_render()
		}
	}

}

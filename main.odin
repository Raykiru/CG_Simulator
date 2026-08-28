package main

import "base:runtime"
import cl "clay-odin"
import "core:c"
import "core:fmt"
import "core:net"
import "core:os"
import rl "vendor:raylib"

audex_font_data := #load("./assets/fonts/Inter_24pt-Bold.ttf")
no_texture_texture_image := #load("./assets/textures/notex.png")

ON_EXIT_CLEANUP :: #config(ON_EXIT_CLEANUP, false)

/*
@ - specific global sections
$ - broad global sections
# - local sections
*/

// $main loop
SCREEN_WIDTH :: 1600
SCREEN_HEIGHT :: 900

AppState :: enum {
	startup,
	mainmenu,
	gameplay,
	exit,
}
Game :: struct {
	app_state:       AppState,
	debug_mode:      bool,
	running:         bool,
	players:         [dynamic; 4]Player,
	loaded_textures: [dynamic; 200]rl.Texture,
}

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "AppState")
	rl.SetTargetFPS(60)
	when ON_EXIT_CLEANUP {
		defer rl.CloseWindow()
	}


	setup_clay()
	game: Game
	game.running = true
	cl.SetDebugModeEnabled(true)

	for !rl.WindowShouldClose() && game.running {
		// #ui prelude
		{
			cl.SetPointerState(cast([2]f32)rl.GetMousePosition(), rl.IsMouseButtonDown(.LEFT))
			cl.SetLayoutDimensions({SCREEN_WIDTH, SCREEN_HEIGHT})
			cl.BeginLayout()

			if rl.IsKeyPressed(.D) {
				@(static) prev: bool
				prev = cl.IsDebugModeEnabled()
				prev = !prev
				cl.SetDebugModeEnabled(prev)
			}
		}

		// #progress game
		{
			window_container := cl.ElementDeclaration {
				id = cl.ID("WindowContainer"),
				layout = {
					sizing = {cl.SizingGrow({}), cl.SizingGrow({})},
					childAlignment = {x = .Center, y = .Center},
				},
			}
			screen_container := cl.ElementDeclaration {
				id = cl.ID("ScreenContainer"),
				layout = {
					layoutDirection = .TopToBottom,
					sizing = {cl.SizingGrow({0, 0}), cl.SizingGrow({0, 0})},
					childAlignment = {x = .Center, y = .Center},
					padding = cl.PaddingAll(3),
					childGap = 3,
				},
			}


			if cl.UI()(window_container) {

				switch game.app_state {
				case .startup:
					// #init game
					{
						img := rl.LoadImageFromMemory(
							".png",
							raw_data(no_texture_texture_image),
							auto_cast len(no_texture_texture_image),
						)
						defer rl.UnloadImage(img)
						tex := rl.LoadTextureFromImage(img)
						if !rl.IsTextureValid(tex) {
							fmt.panicf("Invalid texture for no-tex")
						}

						for !rl.IsTextureReady(tex) {}

						append(&game.loaded_textures, tex)
					}
					game.app_state = .mainmenu
				case .mainmenu:
					cl.UI()(screen_container)

					hovered_play := static_button_elem("Play", {})
					hovered_exit := static_button_elem("Exit", {})
					if hovered_play && rl.IsMouseButtonDown(.LEFT) {
						game.app_state = .gameplay
					}
					if hovered_exit && rl.IsMouseButtonDown(.LEFT) {
						game.app_state = .exit
					}
				case .gameplay:
					TODO("Implement gameplay")
				case .exit:
					game.running = false
					when ON_EXIT_CLEANUP {
						for tex in game.loaded_textures {
							rl.UnloadTexture(tex)
						}
					}
				}
			}
		}


		// #render game on the screen
		{
			local_comms := cl.EndLayout()

			rl.BeginDrawing()
			rl.ClearBackground(rl.BLACK)

			rl.DrawFPS(0, 0)

			switch game.app_state {
			case .startup:
			case .mainmenu:
			case .gameplay:
			case .exit:
			}

			clay_raylib_render(&local_comms)

			rl.EndDrawing()
		}
	}
}

// $multiplayer system
// player must first host a game(over relay server or local network). Another player on the same network can both see the host and join their game

// $[de]serialisation system
// when the game is saved, the current snapshot(and maybe past snapshots) are saved to disc. When the game is loaded, the gamestate gets fully recovered

Serialize_and_save_game :: proc(state: Gamestate, file: string) -> (io_err: os.Error) {
	TODO("Implement serialization and saving to file")

	data: []byte
	os.write_entire_file_from_bytes(file, data) or_return
	return
}

// $assets system
Load_cards_from_dir :: proc() {
}


// $gameplay system

// the representation of a player
Player_kind :: enum {
	Local,
	Network,
}
Player :: struct {
	kind: Player_kind,
	addr: net.Address,
}

Take_player_input :: proc(player: ^Player) {
	switch player.kind {
	case .Local:
		// take input from a player on the same device
		TODO("implement local input")
	case .Network:
		// take input from a player via the network
		TODO("implement input via network")
	case:
		fmt.panicf("Unreachable. State %v is illegal", player.kind)
	}
}

Send_gs_update :: proc(gs: Gamestate, player: Player) {
	switch player.kind {
	case .Local:
		{}
	case .Network:
		TODO("implement Send_gs_update by network")
	case:
		fmt.panicf("Unreachable. State %v is illegal", player.kind)
	}
}
// the current state of the gameplay
Gamestate :: struct {}


// $sound system


// $input system


// $ui system
errorHandler :: proc "c" (errorData: cl.ErrorData) {
	context = runtime.default_context()

	if (errorData.errorType == cl.ErrorType.DuplicateId) {
		// etc
		panic("TODO")
	}
}
setup_clay :: #force_inline proc() {
	minMemorySize: c.size_t = cast(c.size_t)cl.MinMemorySize()
	memory := make([^]u8, minMemorySize)
	arena: cl.Arena = cl.CreateArenaWithCapacityAndMemory(minMemorySize, memory)
	cl.Initialize(
		arena,
		{cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()},
		{handler = errorHandler},
	)
	cl.SetMeasureTextFunction(measure_text, nil)


	// audex_font := rl.LoadFont("./assets/fonts/audex/Audex-Regular.ttf")
	audex_font := rl.LoadFontFromMemory(
		".ttf",
		raw_data(audex_font_data),
		auto_cast len(audex_font_data),
		72,
		nil,
		95,
	)

	if !rl.IsFontReady(audex_font) {
		panic("font isn't ready")
	}
	if !rl.IsFontValid(audex_font) {
		panic("invalid font")
	}
	append(&raylib_fonts, Raylib_Font{0, audex_font})
}

color_rl_to_cl :: #force_inline proc "c" (color: rl.Color) -> [4]f32 {
	return cast([4]f32)transmute([4]u8)color
}

static_button_elem :: #force_inline proc($text: string, sizing: [2]f32) -> (hovered: bool) {

	button_box := cl.ElementDeclaration {
		id = cl.ID("ButtonBox" + text),
		layout = {
			sizing = {cl.SizingFixed(sizing.x), cl.SizingFixed(sizing.y)},
			childAlignment = {x = .Center, y = .Center},
		},
		backgroundColor = color_rl_to_cl(rl.GRAY) if !cl.PointerOver(cl.ID("ButtonBox" + text)) else color_rl_to_cl(rl.BLUE), // change color when hovered
		cornerRadius = cl.CornerRadiusAll(8),
	}


	if cl.UI()(button_box) {
		hovered = cl.Hovered()

		cl.Text(text, &button_text_config)
	}

	return
}

title_text_config := cl.TextElementConfig {
	fontSize      = 60,
	textColor     = color_rl_to_cl(rl.RED),
	letterSpacing = 10,
}
button_text_config := cl.TextElementConfig {
	fontSize      = 52,
	textColor     = color_rl_to_cl(rl.WHITE),
	letterSpacing = 4,
}

// $misc

TODO :: proc($msg: string, loc := #caller_location) {
	panic(msg, loc = loc)
}

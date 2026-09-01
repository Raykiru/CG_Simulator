package main

import "base:runtime"
import cl "clay-odin"
import "core:bytes"
import "core:c"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import win32 "core:sys/windows"
import "core:unicode/utf16"

import rl "vendor:raylib"

audex_font_data := #load("./assets/fonts/Inter_24pt-Bold.ttf")
no_texture_texture_image := #load("./assets/textures/notex.png")

ON_EXIT_CLEANUP :: #config(ON_EXIT_CLEANUP, false)

/*
@ - specific global sections
$ - broad global sections
# - local sections
*/

MAX_CARDS :: 500
MAX_PLAYERS :: 4

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
	gamestate:       Gamestate,
	players:         [dynamic; MAX_PLAYERS]Player,
	loaded_textures: [dynamic; MAX_CARDS]rl.Texture,
}

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "AppState")
	rl.SetTargetFPS(60)
	when ON_EXIT_CLEANUP do defer {
		rl.CloseWindow()
	}


	setup_clay()
	game: Game
	game.running = true
	cl.SetDebugModeEnabled(true)

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
			padding = cl.PaddingAll(30),
			childGap = 30,
		},
	}

	app_loop: for {
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
			// initialisation
			{
			}

			// state loop
			for !rl.WindowShouldClose() && game.running && game.app_state == .mainmenu {
				cl.SetPointerState(cast([2]f32)rl.GetMousePosition(), rl.IsMouseButtonDown(.LEFT))
				cl.SetLayoutDimensions({SCREEN_WIDTH, SCREEN_HEIGHT})
				cl.BeginLayout()

				if rl.IsKeyPressed(.D) {
					@(static) prev: bool
					prev = cl.IsDebugModeEnabled()
					prev = !prev
					cl.SetDebugModeEnabled(prev)
				}

				if cl.UI()(window_container) {
					cl.UI()(screen_container)

					hovered_play := static_button_elem("Play", BUTTON_SIZE)
					hovered_exit := static_button_elem("Exit", BUTTON_SIZE)
					if hovered_play && rl.IsMouseButtonDown(.LEFT) {
						game.app_state = .gameplay
					}
					if hovered_exit && rl.IsMouseButtonDown(.LEFT) {
						game.app_state = .exit
					}
				}

				// #render on the screen
				{
					local_comms := cl.EndLayout()

					rl.BeginDrawing()
					rl.ClearBackground(rl.BLACK)

					rl.DrawFPS(0, 0)

					clay_raylib_render(&local_comms)

					rl.EndDrawing()
				}

			}

			// deinitialisation
			{

			}
			// after the app_state loop
			TODO("After the appstate of mainmenu")

		case .gameplay:
			// when moving to this state
			files: []string
			when ON_EXIT_CLEANUP do defer {
				for path_string in files {
					free(string)
				}
				delete(files)
			}

			// initialisation
			{
				fmt.println("gameplay initialised")
				err: os.Error
				files, err = open_file_dialog()
				if err == nil {
					fmt.println(files)
				}
			}

			// app_state loop
			for !rl.WindowShouldClose() && game.running {
				// free temp per frame
				defer free_all(context.temp_allocator)

				switched: bool
				cl.SetPointerState(cast([2]f32)rl.GetMousePosition(), rl.IsMouseButtonDown(.LEFT))
				cl.SetLayoutDimensions({SCREEN_WIDTH, SCREEN_HEIGHT})
				cl.BeginLayout()

				if rl.IsKeyPressed(.D) {
					@(static) prev: bool
					prev = cl.IsDebugModeEnabled()
					prev = !prev
					cl.SetDebugModeEnabled(prev)
				}

				// #render on the screen
				{
					local_comms := cl.EndLayout()

					rl.BeginDrawing()
					rl.ClearBackground(rl.BLACK)

					rl.DrawFPS(0, 0)

					clay_raylib_render(&local_comms)

					rl.EndDrawing()
				}
				// if it was changed, go back to the outermost loop
				if game.app_state != .gameplay {continue app_loop}
			}

			// deinitialisation
			{
			}
			TODO("implement gameplay")

		case .exit:
			when ON_EXIT_CLEANUP {
				for tex in game.loaded_textures {
					rl.UnloadTexture(tex)
				}
			}
			break app_loop
		case:
			panic("Unreachable")
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
Card_info :: struct {
	texture: rl.Texture,
	// text
	// stats
}

Player_kind :: enum {
	Local,
	Network,
}
Player :: struct {
	kind:       Player_kind,
	name:       string,
	addr:       net.Address,
	card_infos: [dynamic; MAX_CARDS]Card_info,
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
Card_data :: struct {
	uid:       int,
	pos, size: rl.Vector2,
	flipped:   bool,
	angle:     f32,
}

Gamestate :: struct {
	cards: [dynamic; MAX_CARDS]Card_data,
}


// $sound system


// $input system


// $ui system
BUTTON_SIZE :: [2]f32{100, 50}

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

open_file_dialog :: proc(allocator := context.allocator) -> (paths: []string, err: os.Error) {
	// Needs to be large enough to hold many filenames.
	// Bump this up further if you expect very large selections.
	buf := make([]u16, 32768, context.temp_allocator) or_return

	ofn := win32.OPENFILENAMEW {
		lStructSize  = size_of(win32.OPENFILENAMEW),
		lpstrFile    = cast(cstring16)raw_data(buf),
		nMaxFile     = u32(len(buf)),
		lpstrFilter  = win32.utf8_to_wstring("All Files\x00*.*\x00"),
		nFilterIndex = 1,
		Flags        = win32.OFN_PATHMUSTEXIST | win32.OFN_FILEMUSTEXIST | win32.OFN_ALLOWMULTISELECT | win32.OFN_EXPLORER,
	}

	if !win32.GetOpenFileNameW(&ofn) {
		err = .Unknown
		return
	}

	// parse the outputed bytes to utf8 format
	strings_data := make([]u8, (len(buf)), context.temp_allocator)
	utf16.decode_to_utf8(strings_data, buf)
	trimmed_str_bytes := bytes.trim(strings_data, {0})

	str_builder, str_builder_reset: strings.Builder
	strings.builder_init(&str_builder, context.temp_allocator)

	// first string from GetOpenFileNameW is the root path
	root_path, _ := bytes.split_iterator(&trimmed_str_bytes, []u8{0})
	strings.write_bytes(&str_builder, root_path)
	str_builder_reset = str_builder // save the reset point

	dyn_paths := make([dynamic]string)

	for file_name in bytes.split_iterator(&trimmed_str_bytes, []u8{0}) {
		file_name := cast(string)file_name
		strings.write_string(&str_builder, file_name)
		append(&dyn_paths, strings.clone(strings.to_string(str_builder), allocator)) or_return
		// cannot leak memory as it uses the temp allocator
		str_builder_reset = str_builder
	}
	// if no other strings were read from the byte stream, the root_path is the sole file path
	if len(dyn_paths) == 0 {
		append(&dyn_paths, strings.clone(strings.to_string(str_builder), allocator)) or_return
	}


	paths = dyn_paths[:]
	return
}

TODO :: proc($msg: string, loc := #caller_location) {
	panic(msg, loc = loc)
}

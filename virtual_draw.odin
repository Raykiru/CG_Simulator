package main// can be changed

import "core:fmt"

import rl "vendor:raylib"

TS_GRAY :: [4]u8{18, 18, 18, 255}

virtual_screen: rl.RenderTexture2D
int_virtual_width, int_virtual_height: f32

// togle off exports when used as a file to avoid collisions
when false {
	init :: virtual_screen_init
	render :: virtual_screen_render
	mouse_pos :: virtual_screen_mouse_pos
	draw :: virtual_screen_draw
}


@(private = "package")
virtual_screen_init :: proc(virtual_width, virtual_height: i32) {
	int_virtual_height = cast(f32)virtual_height
	int_virtual_width = cast(f32)virtual_width
	virtual_screen = rl.LoadRenderTexture(virtual_width, virtual_height)
}

@(private = "package", deferred_none = rl.EndTextureMode)
virtual_screen_draw :: proc() -> bool {
	rl.BeginTextureMode(virtual_screen)
	rl.ClearBackground(auto_cast TS_GRAY)

	return true
}

@(private = "package")
virtual_screen_mouse_pos :: proc() -> (x: f32, y: f32) {
	x, y = **rl.GetMousePosition()
	target_rect := virtual_screen_get_target_rect()

	x = (x - target_rect.x) / target_rect.width * f32(virtual_screen.texture.width)
	y = (y - target_rect.y) / target_rect.height * f32(virtual_screen.texture.height)
	return
}

@(private = "package")
virtual_screen_get_target_rect :: proc() -> (target_rect: rl.Rectangle) {

	width := cast(f32)rl.GetScreenWidth()
	height := cast(f32)rl.GetScreenHeight()
	if width / height >= int_virtual_width / int_virtual_height {
		target_rect.height = height
		target_rect.width = height * (int_virtual_width / int_virtual_height)
		target_rect.x = (width - target_rect.width) / 2
	} else {
		target_rect.width = width
		target_rect.height = width * (int_virtual_height / int_virtual_width)
		target_rect.y = (height - target_rect.height) / 2
	}

	return
}

@(private = "package")
virtual_screen_render :: proc() {
	target_rect := virtual_screen_get_target_rect()

	rl.DrawTexturePro(
		virtual_screen.texture,
		{0, 0, auto_cast virtual_screen.texture.width, auto_cast -virtual_screen.texture.height},
		target_rect,
		{},
		0,
		rl.WHITE,
	)
}

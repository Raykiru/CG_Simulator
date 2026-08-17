package main

import "core:fmt"
import "core:math/rand"
import "core:strings"
import rl "vendor:raylib"

// constants
VSCREEN_SIZE :: [2]i32{1600, 900}
MAX_ENTITIES :: 1024
CARD_SIZE :: [2]f32{121, 170}
PLAYER_HAND_SIZE :: [2]f32{10 * CARD_SIZE.x, CARD_SIZE.y}

// Types
Thing_traits :: enum {
	Rectangular,
	Textured,
	Flippable,
	Static,
	Capturable,
	Capturing,
	Is_Mouse,
}
Thing_tags :: enum {
	Deleted,
	Captured,
	Highlighted,
	Hidden,
}
Thing_idx :: int // index into things array, not gen
Thing :: struct {
	// generic fields
	gen:              int,
	pos, size, pivot: rl.Vector2,
	angle:            f32,
	color:            rl.Color,
	traits:           bit_set[Thing_traits], // permanent properties of the thing
	tags:             bit_set[Thing_tags], // transient properties of the thing

	// Trait specific fields
	//	// Textured
	texture:          rl.Texture,
	crop:             rl.Rectangle,

	//	// Flippable
	back_texture:     rl.Texture,
	flipped:          bool,

	//	// Capturable
	parent_id:        Thing_idx,

	//	//Static

	//	// Capturing
	captures:         [dynamic]Thing_idx,
}


// Global state
input: struct {
	left_click, right_click, left_hold, r_click, f_click, space_click: bool,
	mouse_pos, vmouse_pos, mouse_delta:                                rl.Vector2,
	numeric_in:                                                        int,
	num_click:                                                         bool,
}
things: [dynamic; MAX_ENTITIES]Thing

// global data
card_images := #load_directory("./playing-cards/")
loaded_textures: [dynamic]rl.Texture
back_texture: rl.Texture
gen_source := 0

mouse_thing_id: Thing_idx

// helper functions
append_thing :: #force_inline proc(things: ^[dynamic; MAX_ENTITIES]Thing, new_thing: Thing) {
	for maybe_deleted, i in things {
		if .Deleted in maybe_deleted.tags {
			things[i] = new_thing
			return
		}
	}

	append(things, new_thing)
}
delete_thing :: #force_inline proc(
	things: ^[dynamic; MAX_ENTITIES]Thing,
	thing_idx: int,
) -> Thing {
	old_thing := &things[thing_idx]
	if .Static not_in old_thing.traits && .Deleted not_in old_thing.tags {
		old_thing.tags += {.Deleted}
		gen_source -= 1
	}

	return old_thing^
}

get_digit_pressed :: proc() -> (digit: int, ok: bool) {
	key := rl.GetKeyPressed()
	if key >= .ZERO && key <= .NINE {
		return int(key - rl.KeyboardKey.ZERO), true
	}
	if key >= .KP_0 && key <= .KP_9 {
		return int(key - rl.KeyboardKey.KP_0), true
	}
	return
}

rectangle_collision_check :: #force_inline proc(rect1, rect2: rl.Rectangle) -> bool {

	// check if too far right
	if rect1.x > rect2.width + rect2.x {return false}
	// check if too far left
	if rect1.x + rect1.width < rect2.x {return false}

	// check if too far down
	if rect1.y > rect2.height + rect2.y {return false}
	// check if too far left
	if rect1.y + rect1.height < rect2.y {return false}

	return true
}

NewThing :: #force_inline proc(
	_gen: int = 0,
	pos: rl.Vector2 = {},
	size: rl.Vector2 = {},
	pivot: rl.Vector2 = {},
	angle: f32 = 0,
	color: rl.Color = {},
	traits: bit_set[Thing_traits],
	tags: bit_set[Thing_tags] = {},

	// Trait specific fields
	//	// Textured
	texture: rl.Texture = {},
	crop: rl.Rectangle = {},

	//	// Flippable
	back_texture: rl.Texture = {},
	flipped: bool = {},

	//	// Capturable
	parent_id: Thing_idx = 0,

	//	// Capturing
	captures: [dynamic]Thing_idx = nil,
) -> Thing {
	gen := gen_source
	gen_source += 1

	return Thing {
		gen,
		pos,
		size,
		pivot,
		angle,
		color,
		traits,
		tags,
		texture,
		crop,
		back_texture,
		flipped,
		parent_id,
		captures,
	}
}

NewCard :: #force_inline proc(
	pos: rl.Vector2,
	texture, back_texture: rl.Texture,
	color: rl.Color,
) -> Thing {
	return NewThing(
		pos = pos,
		size = CARD_SIZE,
		crop = {0, 0, **cast([2]f32)[2]i32{texture.width, texture.height}},
		traits = {.Textured, .Flippable, .Capturable},
		texture = texture,
		back_texture = back_texture,
		color = rl.WHITE,
		pivot = CARD_SIZE / 2,
	)
}


main :: proc() {

	// setup game
	{
		// setup raylib
		rl.InitWindow((**VSCREEN_SIZE), "game")
		rl.SetWindowState({.WINDOW_RESIZABLE})

		rl.SetTargetFPS(60)

		// setup virtual draw
		virtual_screen_init((**VSCREEN_SIZE))

		// load assets
		for file_entry in card_images {
			curr := rl.LoadImageFromMemory(
				".png",
				raw_data(file_entry.data),
				auto_cast len(file_entry.data),
			)
			defer rl.UnloadImage(curr)

			if strings.contains(file_entry.name, "back") {
				back_texture = rl.LoadTextureFromImage(curr)
				continue
			}
			if !rl.IsImageValid(curr) {
				fmt.eprintf("Loaded image is invalid, %v", file_entry.name)
				continue
			}
			curr_texture := rl.LoadTextureFromImage(curr)


			append_elem(&loaded_textures, curr_texture)
			fmt.println(
				file_entry.name,
				"Texture succesfully loaded at",
				len(loaded_textures[:]) - 1,
			)

		}

		// sentinel thing
		append(&things, NewThing(traits = {}))

		mouse_thing := NewThing(traits = {.Is_Mouse, .Static})
		assert(mouse_thing.gen == 1)
		// add player hand zone
		hand_thing := NewThing(
			pos = {
				(f32(VSCREEN_SIZE.x) - PLAYER_HAND_SIZE.x) / 2,
				+f32(VSCREEN_SIZE.y) - PLAYER_HAND_SIZE.y,
			},
			size = PLAYER_HAND_SIZE,
			color = rl.DARKBLUE,
			traits = {.Rectangular, .Static, .Capturing},
		)
		mouse_thing_id = len(things)
		append_thing(&things, mouse_thing)
		append_thing(&things, hand_thing)


	}

	for !rl.WindowShouldClose() {
		// collect input
		{
			input.vmouse_pos = rl.Vector2{virtual_screen_mouse_pos()}
			input.mouse_delta = rl.GetMouseDelta()
			input.left_hold = rl.IsMouseButtonDown(.LEFT)
			input.left_click = rl.IsMouseButtonPressed(.LEFT)
			input.right_click = rl.IsMouseButtonPressed(.RIGHT)

			input.r_click = rl.IsKeyPressed(.R)
			input.f_click = rl.IsKeyPressed(.F)
			input.space_click = rl.IsKeyPressed(.SPACE)

			input.numeric_in, input.num_click = get_digit_pressed()
		}


		// update state by input
		{
			// draw a card from "deck"
			if input.space_click {
				new_texture := rand.choice(loaded_textures[:])

				new_thing := NewCard(
					pos = input.vmouse_pos,
					texture = new_texture,
					back_texture = back_texture,
					color = rl.WHITE,
				)
				new_thing.pivot = CARD_SIZE / 2

				append_thing(&things, new_thing)
				fmt.println("new thing added")
			}

			if input.num_click {
				for i in 0 ..< input.numeric_in {
					new_texture := rand.choice(loaded_textures[:])

					new_thing := NewCard(
						pos = input.vmouse_pos,
						texture = new_texture,
						back_texture = back_texture,
						color = rl.WHITE,
					)
					new_thing.pivot = CARD_SIZE / 2

					append_thing(&things, new_thing)
				}
				fmt.println(input.numeric_in, "new things added")
			}

			// update each thing by input
			mouse := &things[1]
			#reverse for &thing, id in things {
				if .Deleted in thing.tags {continue}

				// reset tags
				thing.tags = {}

				// check mouse collision
				if rl.CheckCollisionPointRec(input.vmouse_pos, {**thing.pos, **thing.size}) {
					if input.left_click && .Capturable in thing.traits {
						if len(mouse.captures) == 0 {
							thing.parent_id = mouse_thing_id
							append(&mouse.captures, id)
						} else if id == mouse.captures[0] {
							// un-capture it
							captured_id := mouse.captures[0]
							things[captured_id].parent_id = 0
							clear(&mouse.captures)
						}
					}
					if input.right_click {
						delete_thing(&things, id)
					}

					if .Flippable in thing.traits && input.f_click {
						thing.flipped = !thing.flipped
					}

					thing.tags += {.Highlighted}
				}
			}
		}

		// progress the state
		{
			// update mouse in particular
			{
				thing := things[mouse_thing_id]
				if len(thing.captures) == 1 {
					moused_thing_id := thing.captures[0]
					moused_thing := &things[moused_thing_id]
					moused_thing.pos = input.vmouse_pos - moused_thing.pivot
					moused_thing.tags += {.Captured}
				}
			}
			// for collisions
			@(static) capturing_things: [dynamic]Thing_idx
			@(static) capturable_things: [dynamic]Thing_idx
			defer clear(&capturing_things)
			defer clear(&capturable_things)
			#reverse for &thing, idx in things {
				if .Capturable in thing.traits do if .Captured not_in thing.tags {
					append(&capturable_things, idx)
				}
				if .Capturing in thing.traits {
					append(&capturing_things, idx)
				}
			}

			for thing_id in capturable_things {
				for capt_id in capturing_things {
					capt := &things[capt_id]
					thing := &things[thing_id]


					if rectangle_collision_check(
						{**capt.pos, **capt.size},
						{**thing.pos, **thing.size},
					) {
						thing.tags += {.Hidden}
						append(&capt.captures, thing_id)
					}

				}
			}
		}


		// drawing on virtual_screen
		if virtual_screen_draw() {
			rl.DrawText("Hello world", 0, 0, 69, rl.RED)

			for thing in things {
				if .Deleted in thing.tags {continue}

				if .Hidden in thing.tags {continue}

				if .Textured in thing.traits {
					dest_rect := rl.Rectangle{(**(thing.pos + thing.pivot)), (**thing.size)}
					crop_rect: rl.Rectangle
					color: rl.Color = thing.color

					if thing.crop == {} {crop_rect = rl.Rectangle{0, 0, (**(thing.size / 2))}
					} else {crop_rect = thing.crop}

					texture := thing.texture

					if .Flippable in thing.traits && thing.flipped {
						texture = thing.back_texture
					}

					// TODO: implement Mouse as a Thing
					if .Capturable in thing.traits && thing.parent_id == mouse_thing_id {
						color = rl.RED
					}

					rl.DrawTexturePro(
						texture = texture,
						source = crop_rect,
						dest = dest_rect,
						origin = thing.pivot,
						rotation = thing.angle,
						tint = color,
					)
					dest_rect = rl.Rectangle{(**(thing.pos)), (**thing.size)}

				}

				if .Rectangular in thing.traits {
					rl.DrawRectangle(
						(**cast([2]i32)thing.pos),
						(**cast([2]i32)thing.size),
						thing.color,
					)
				}

				if .Highlighted in thing.tags {
					dest_rect := rl.Rectangle{(**(thing.pos)), (**thing.size)}
					rl.DrawRectangleLinesEx(rec = dest_rect, lineThick = 5, color = rl.BLUE)
				}

			}
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

package main

import "core:fmt"
import "core:math/rand"
import "core:strings"
import rl "vendor:raylib"

// constants
VSCREEN_SIZE :: [2]i32{1600, 900}
MAX_ENTITIES :: 1024
CARD_SIZE :: [2]f32{121, 170}

// Types
Thing_traits :: enum {
	Textured,
	Flippable,
	Dragable,
}
Thing_tags :: enum {
	Deleted,
	Highlighted,
}
Thing :: struct {
	// generic fields
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

	//	// Dragable
	clicked:          bool,
}


// Global state
input: struct {
	left_click, right_click, left_hold, r_click, f_click, space_click: bool,
	mouse_pos, vmouse_pos, mouse_delta:                                rl.Vector2,
}
things: [dynamic; MAX_ENTITIES]Thing
holding: bool // holding something with mouse

// global data
card_images := #load_directory("./playing-cards/")
loaded_images: [dynamic]rl.Image
back_texture: rl.Texture


// helper functions
append_thing :: #force_inline proc(things: ^[dynamic; MAX_ENTITIES]Thing, thing: Thing) {
	for maybe_deleted, i in things {
		if .Deleted in maybe_deleted.tags {
			things[i] = thing
			return
		}
	}

	append(things, thing)
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

			if strings.contains(file_entry.name, "back") {
				back_texture = rl.LoadTextureFromImage(curr)
				continue
			}

			if !rl.IsImageValid(curr) {
				fmt.eprintf("Loaded image is invalid, %v", file_entry.name)
				continue
			}
			append(&loaded_images, curr)
			fmt.println(file_entry.name, "Image succesfully loaded at", len(loaded_images[:]) - 1)

		}

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
		}


		// update state by input
		{
			// draw a card from "deck"
			if input.space_click {
				new_image := rand.choice(loaded_images[:])
				new_texture := rl.LoadTextureFromImage(new_image)

				new_thing := Thing {
					pos          = input.vmouse_pos,
					size         = CARD_SIZE,
					crop         = {0, 0, **cast([2]f32)[2]i32{new_image.width, new_image.height}},
					traits       = {.Textured, .Flippable, .Dragable},
					texture      = new_texture,
					back_texture = back_texture,
					color        = rl.WHITE,
				}
				new_thing.pivot = CARD_SIZE / 2

				fmt.println(new_thing.crop)

				append_thing(&things, new_thing)
				fmt.println("new thing added")
			}


			// update each thing by input
			for &thing, id in things {
				if .Deleted in thing.tags {continue}

				// reset tags
				thing.tags = {}

				// check mouse collision
				if rl.CheckCollisionPointRec(input.vmouse_pos, {**thing.pos, **thing.size}) {
					if input.left_click {
						if !holding {
							thing.clicked = !thing.clicked
							holding = !holding
						} else do if thing.clicked {
							thing.clicked = false
							holding = false
						}
					}

					if input.right_click {
						thing.tags += {.Deleted}
					}

					if .Flippable in thing.traits && input.f_click {
						fmt.println("Flipped ")
						thing.flipped = !thing.flipped
					}

					thing.tags += {.Highlighted}
				}
			}
		}

		// progress the state
		{
			for &thing, id in things {
				if .Dragable in thing.traits && thing.clicked {
					thing.pos = input.vmouse_pos - thing.pivot
				}

			}
		}


		// drawing on virtual_screen
		if virtual_screen_draw() {
			rl.DrawText("Hello world", 0, 0, 69, rl.RED)

			for thing in things {

				if .Deleted in thing.tags {continue}


				if .Textured in thing.traits {
					dest_rect := rl.Rectangle{(**(thing.pos + thing.pivot)), (**thing.size)}
					crop_rect: rl.Rectangle
					color: rl.Color = thing.color

					if thing.crop == {} {crop_rect = rl.Rectangle{0, 0, **(thing.size / 2)}
					} else {crop_rect = thing.crop}

					texture := thing.texture

					if .Flippable in thing.traits && thing.flipped {
						texture = thing.back_texture
					}

					if .Dragable in thing.traits && thing.clicked {
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
					dest_rect = rl.Rectangle{**(thing.pos), **thing.size}

					if .Highlighted in thing.tags {
						rl.DrawRectangleLinesEx(rec = dest_rect, lineThick = 5, color = rl.BLUE)
					}

					continue
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

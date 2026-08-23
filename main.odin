package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:slice"
import "core:sort"
import "core:strings"
import rl "vendor:raylib"

// constants
VSCREEN_SIZE :: [2]i32{1600, 900}
MAX_ENTITIES :: 1024
CARD_SIZE :: [2]f32{121, 170}
PLAYER_HAND_SIZE :: [2]f32{10 * CARD_SIZE.x, CARD_SIZE.y}

Thing_types :: enum {
	None,
	Mouse,
	Rectangle,
}
// @Types
Thing_traits :: enum {
	Textured,
	Flippable,
	Static,
	Capturable,
	Capturing,
	Gage_like,
}
Thing_tags :: enum {
	Deleted,
	Captured,
	Highlighted,
	Hidden,
}
Thing_handle :: struct {
	gen: int,
	idx: int,
}
Thing :: struct {
	// generic fields
	gen:              int,
	type:             Thing_types,
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

	//	//Static

	//	// Capturable
	parent_handle:    Thing_handle,

	//	// Capturing
	captures:         [dynamic]Thing_handle,

	//	// Gage-like
	gage_zone:        rl.Rectangle,
}


// @Global state
input: struct {
	left_click, right_click, left_hold, r_click, f_click, space_click: bool,
	mouse_pos, vmouse_pos, mouse_delta:                                rl.Vector2,
	numeric_in:                                                        int,
	num_click:                                                         bool,
}
things: [dynamic; MAX_ENTITIES]Thing
mouse_thing_handle: Thing_handle

// @assets
card_images := #load_directory("./playing-cards/")
loaded_textures: [dynamic]rl.Texture
back_texture: rl.Texture

// @helper functions
get_thing :: #force_inline proc(handle: Thing_handle) -> (t: ^Thing) #no_bounds_check {
	t = &things[0]
	if things[handle.idx].gen == handle.gen {t = &things[handle.idx]} else {
		fmt.println("Returned 0 lol")
	}

	return
}

cleanup_thing :: proc(handle: Thing_handle) {
	thing := get_thing(handle)

	if thing.captures != nil {
		delete(thing.captures)
		thing.captures = nil
	}

}

reverse_iter_handles :: proc(arr: []Thing) -> (h: Thing_handle, ok: bool) {
	@(static) counter: int
	counter += 1
	if counter > len(arr) {
		counter = 0
		return
	}
	ok = true
	h.idx = len(arr) - counter
	h.gen = arr[h.idx].gen

	return
}

iter_handles :: proc(arr: []Thing) -> (h: Thing_handle, ok: bool) {
	@(static) counter: int
	counter += 1
	if counter > len(arr) {
		counter = 0
		return
	}
	ok = true
	h.idx = counter - 1
	h.gen = arr[h.idx].gen

	return
}

ordered_remove_sorted_indexes_dynamic_array :: #force_inline proc(
	#no_alias arr: ^$T/[dynamic]$E,
	sorted_ids: []int,
	loc := #caller_location,
) #no_bounds_check {
	progress := 0
	initial_len := len(arr)
	ids_len := len(sorted_ids)
	prev_id := -1

	//
	if ids_len == 0 do return

	// manual bounds checks
	assert(sorted_ids[len(sorted_ids) - 1] < len(arr), loc = loc)
	assert(sorted_ids[0] >= 0, loc = loc)

	for el, el_i in arr {
		// assure no duplicates
		// calculate how far back the empty slot is
		if el_i - 1 == sorted_ids[progress] {
			progress += 1

			// this covers both duplicates and unsorted arrays
			fmt.assertf(
				prev_id < sorted_ids[progress],
				"sorted_ids must be strictly ascending: %v",
				sorted_ids,
			)
			prev_id = sorted_ids[progress] // using a value rather then sorted_ids[progress +- 1] sidesteps the case where len ==1
		}

		// pull back the element to the now empty slot
		arr[el_i - progress] = el
	}
	// handle removing last element
	if sorted_ids[len(sorted_ids) - 1] == len(arr) - 1 {progress += 1}
	// shrink the length of the array manually
	(^runtime.Raw_Dynamic_Array)(arr).len -= progress
}

append_thing :: #force_inline proc(
	things: ^[dynamic; MAX_ENTITIES]Thing,
	new_thing: Thing,
) -> (
	new_handle: Thing_handle,
) {
	for maybe_handle in iter_handles(things[:]) {
		if .Deleted in get_thing(maybe_handle).tags {
			delete_thing(maybe_handle)
			new_handle = maybe_handle
			things[maybe_handle.idx] = new_thing
			things[maybe_handle.idx].gen += 1
			new_handle.gen += 1
			return
		}
	}

	new_handle.idx = len(things)
	append(things, new_thing)

	return
}
delete_thing :: #force_inline proc(thing_handle: Thing_handle) -> Thing {
	old_thing := get_thing(thing_handle)

	if .Static not_in old_thing.traits && .Deleted not_in old_thing.tags {
		old_thing.tags += {.Deleted}
	} else {
		fmt.println("Deleted deleted or static thing")
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
	$type: Thing_types,
	pos: rl.Vector2 = {},
	size: rl.Vector2 = {},
	pivot: rl.Vector2 = {},
	angle: f32 = 0,
	color: rl.Color = {},
	$traits: bit_set[Thing_traits],
	tags: bit_set[Thing_tags] = {},

	// Trait specific fields
	//	// Textured
	texture: rl.Texture = {},
	crop: rl.Rectangle = {},

	//	// Flippable
	back_texture: rl.Texture = {},
	flipped: bool = {},

	//	// Capturable
	parent_handle: Thing_handle = {},

	//	// Capturing
	captures: [dynamic]Thing_handle = nil,

	//	// Gage-like
	gage_zone: rl.Rectangle = {}, // it's relative to pos
	loc := #caller_location,
) -> Thing {

	when .Gage_like in traits {fmt.assertf(gage_zone != {}, "Gage zone must be non-zero", loc = loc)}

	return Thing {
		0,
		type,
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
		parent_handle,
		captures,
		gage_zone,
	}
}

NewCard :: #force_inline proc(
	pos: rl.Vector2,
	texture, back_texture: rl.Texture,
	color: rl.Color,
	loc := #caller_location,
) -> Thing {
	return NewThing(
		type = .Rectangle,
		pos = pos,
		size = CARD_SIZE,
		crop = {0, 0, **cast([2]f32)[2]i32{texture.width, texture.height}},
		traits = {.Textured, .Flippable, .Capturable},
		texture = texture,
		back_texture = back_texture,
		color = rl.WHITE,
		pivot = CARD_SIZE / 2,
		loc = loc,
	)
}


main :: proc() {

	// #setup game
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

		}

		// sentinel thing
		append(&things, NewThing(type = .None, traits = {.Static}))

		mouse_thing := NewThing(type = .Mouse, traits = {.Static})
		// add player hand zone
		hand_pos := rl.Vector2 {
			(f32(VSCREEN_SIZE.x) - PLAYER_HAND_SIZE.x) / 2,
			+f32(VSCREEN_SIZE.y) - PLAYER_HAND_SIZE.y,
		}
		hand_thing := NewThing(
			type = .Rectangle,
			pos = hand_pos,
			size = PLAYER_HAND_SIZE,
			color = rl.DARKBLUE,
			traits = {.Static, .Capturing, .Gage_like},
			gage_zone = {(**hand_pos), (**PLAYER_HAND_SIZE)},
		)
		mouse_thing_handle.idx = len(things)
		mouse_thing_handle.gen = mouse_thing.gen
		append_thing(&things, mouse_thing)
		append_thing(&things, hand_thing)

	}


	for !rl.WindowShouldClose() {
		// #collect input
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

		// #progress the state
		{
			// update mouse in particular
			{
				thing := get_thing(mouse_thing_handle)
				if len(thing.captures) == 1 {
					moused_thing_handle := thing.captures[0]
					moused_thing := get_thing(moused_thing_handle)
					moused_thing.pos = input.vmouse_pos - moused_thing.pivot
					moused_thing.tags += {.Captured}
					if .Deleted in moused_thing.tags {
						cleanup_thing(moused_thing_handle)
						ordered_remove(&thing.captures, 0)
					}
				}
			}

			// for collisions
			@(static) capturing_things: [dynamic]Thing_handle
			@(static) capturable_things: [dynamic]Thing_handle
			defer clear(&capturing_things)
			defer clear(&capturable_things)

			for thing_handle in reverse_iter_handles(things[:]) {
				thing := get_thing(thing_handle)
				if .Deleted in thing.tags {
					cleanup_thing(thing_handle)
					continue
				}


				if .Capturable in thing.traits &&
				   .Captured not_in thing.tags {append(&capturable_things, thing_handle)}

				if .Capturing in thing.traits {append(&capturing_things, thing_handle)}
			}

			// Iterate and update the state of the things captured by capturables
			for capt_handle in capturing_things {
				capt_thing := get_thing(capt_handle)

				tbr: [dynamic]int // list of things to be removed from captures
				for thing_handle, i in capt_thing.captures {
					thing := get_thing(thing_handle)
					if thing.parent_handle != capt_handle {
						append(&tbr, i)
						continue
					}
					if .Deleted in thing.tags {
						append(&tbr, i)
						continue
					}
					// check if it's still coliding
					if rectangle_collision_check(
						{**capt_thing.pos, **capt_thing.size},
						{**thing.pos, **thing.size},
					) {
						thing.tags += {.Hidden, .Captured}
					} else {
						// it's possible it's captured by something else
						append(&tbr, i)
					}

				}

				if len(tbr) >
				   0 {ordered_remove_sorted_indexes_dynamic_array(&capt_thing.captures, tbr[:])}
			}

			for thing_handle in capturable_things {
				for capt_handle in capturing_things {
					capt := get_thing(capt_handle)
					thing := get_thing(thing_handle)

					if .Captured in thing.tags {continue}

					if rectangle_collision_check(
						{**capt.pos, **capt.size},
						{**thing.pos, **thing.size},
					) {
						thing.tags += {.Hidden, .Captured}
						thing.parent_handle = capt_handle
						append(&capt.captures, thing_handle)
					}

				}
			}

		}


		// #update state by input
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

					append_thing(&things, new_thing)
				}
				fmt.println(input.numeric_in, "new things added")
			}

			// update each thing by input
			mouse := &things[1]
			assert(mouse.type == .Mouse)
			for thing_handle in reverse_iter_handles(things[:]) {
				thing := get_thing(thing_handle)
				if .Deleted in thing.tags {continue}

				thing.tags = {}

				// reset tags

				// check mouse collision
				if rl.CheckCollisionPointRec(input.vmouse_pos, {**thing.pos, **thing.size}) {
					if input.left_click && .Capturable in thing.traits {
						if len(mouse.captures) == 0 {
							thing.parent_handle = mouse_thing_handle
							append(&mouse.captures, thing_handle)
						} else if thing_handle == mouse.captures[0] {
							// un-capture it
							captured_handle := mouse.captures[0]
							get_thing(captured_handle).parent_handle = {}
							clear(&mouse.captures)
						}
					}
					if input.right_click {
						fmt.println("delete it")
						delete_thing(thing_handle)
					}

					if .Flippable in thing.traits && input.f_click {
						thing.flipped = !thing.flipped
					}

					thing.tags += {.Highlighted}
				}
			}
		}


		// #drawing on virtual_screen
		if virtual_screen_draw() {
			rl.DrawText("Hello world", 0, 0, 69, rl.RED)

			for thing_handle in iter_handles(things[:]) {
				thing := get_thing(thing_handle)

				if .Deleted in thing.tags {continue}
				if .Hidden in thing.tags {continue}

				draw_thing(thing_handle)
			}
		}

		// #rendering
		{
			rl.BeginDrawing()
			defer rl.EndDrawing()
			rl.ClearBackground(rl.BLACK)

			virtual_screen_render()
		}
	}

}

draw_thing :: proc(handle: Thing_handle) {
	thing := things[handle.idx]
	switch thing.type {
	case .None:
	case .Mouse:
	case .Rectangle:
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

			if .Capturable in thing.traits && thing.parent_handle == mouse_thing_handle {
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
			// dest_rect = rl.Rectangle{(**(thing.pos)), (**thing.size)}

		} else {
			rl.DrawRectangle((**cast([2]i32)thing.pos), (**cast([2]i32)thing.size), thing.color)
		}

		if .Highlighted in thing.tags {
			dest_rect := rl.Rectangle{(**(thing.pos)), (**thing.size)}
			rl.DrawRectangleLinesEx(rec = dest_rect, lineThick = 5, color = rl.BLUE)
		}

		if .Capturing in thing.traits {
			if .Gage_like in thing.traits {
				for captured_thing_handle in thing.captures {
					captured_thing := get_thing(captured_thing_handle)
					if captured_thing.parent_handle != handle {continue}
					draw_thing(captured_thing_handle)
				}

				return
			}
			// else idk, don't draw the thing
		}
	}

}

local autorotate = require('lib.autorotate')
local mallet = require('lib.mallet')
local structure_items = require('lib.structure_items')
local door = require('lib.door')

local add_structure_item = structure_items.add_structure_item
local add_attachment_item = structure_items.add_attachment_item
local mallet_cycle = mallet.mallet_cycle




add_structure_item('fence', 'fence/edge/horiz')
add_structure_item('fence_tee', 'fence/tee/e')
add_structure_item('fence_post', 'fence/end/fancy/e')

mallet_cycle('fence/', {
    'edge/horiz', 'edge/vert',
    'corner/nw', 'corner/ne', 'corner/se', 'corner/sw',
})
mallet_cycle('fence/', { 'tee/e', 'tee/s', 'tee/w', 'tee/n', 'cross' })
mallet_cycle('fence/end/fancy/', { 'e', 'w' })


autorotate.add_house_wall_item('house_wall/side', 'house_wall', 'edge')
autorotate.add_house_wall_item('house_wall/corner', 'house_wall', 'corner')
autorotate.add_house_wall_item('house_wall/tee', 'house_wall', 'tee')
autorotate.add_house_wall_item('house_wall/cross', 'house_wall', 'cross')
autorotate.add_house_wall_item('house_door', 'house_wall', 'door')
door.make_door('house_door', 'house_wall/door/out', 'axe')
door.make_door('house_door', 'house_wall/door/in', 'axe')

mallet_cycle('house_wall/edge/', { 'horiz/in', 'horiz/out', 'vert' })
mallet_cycle('house_wall/corner/', {
    'nw/in', 'ne/in', 'se/out', 'sw/out',
    'nw/out', 'ne/out', 'se/in', 'sw/in',
})
mallet_cycle('house_wall/tee/', {
    'n/in', 'n/out',
    'e/in', 'e/out',
    's/in_in', 's/in_out', 's/out_out', 's/out_in',
    'w/in', 'w/out',
})
mallet_cycle('house_wall/cross/', {
    'in_in', 'in_out', 'out_out', 'out_in',
})

mallet_cycle('house_wall/door/', { 'in/closed', 'out/closed' })


autorotate.add_simple_wall_item('wood_wall', 'wood_wall', false)
autorotate.add_simple_wall_item('wood_door', 'wood_wall', true)
door.make_door('wood_door', 'wood_wall/door', 'axe')
mallet_cycle('wood_wall/', {
    'edge/horiz', 'edge/vert',
    'corner/nw', 'corner/ne', 'corner/se', 'corner/sw', 
    'tee/n', 'tee/e', 'tee/s', 'tee/w',
    'cross',
})

autorotate.add_simple_wall_item('stone_wall', 'stone_wall', false)
autorotate.add_simple_wall_item('stone_door', 'stone_wall', true)
door.make_door('stone_door', 'stone_wall/door', 'pick')
mallet_cycle('stone_wall/', {
    'edge/horiz', 'window/v0', 'window/v1', 'edge/vert',
    'corner/nw', 'corner/ne', 'corner/se', 'corner/sw', 
    'tee/n', 'tee/e', 'tee/s', 'tee/w',
    'cross',
})


local terrain_cycle = {
    'center/v0',
    'edge/n', 'corner/outer/ne', 'edge/e', 'corner/outer/se',
    'edge/s', 'corner/outer/sw', 'edge/w', 'corner/outer/nw',
    'corner/inner/nw', 'corner/inner/ne', 'corner/inner/se', 'corner/inner/sw',
}

autorotate.add_floor_item('house_floor', 'wood_floor')
mallet_cycle('wood_floor/', terrain_cycle)
autorotate.add_floor_item('road', 'road')
mallet_cycle('road/', terrain_cycle)

add_structure_item('statue', 'statue/e')
mallet_cycle('statue/', { 'e', 's', 'w', 'n' })

add_structure_item('bed')
add_structure_item('table')
add_structure_item('trophy')
add_structure_item('fountain')
add_structure_item('torch')
add_structure_item('stair', 'stair/n')



local horiz_walls = {
    ['house_wall/edge/horiz/in'] = true,
    ['house_wall/edge/horiz/out'] = true,
    ['house_wall/tee/n/in'] = true,
    ['house_wall/tee/n/out'] = true,
    ['wood_wall/edge/horiz'] = true,
    ['wood_wall/tee/n'] = true,
    ['stone_wall/edge/horiz'] = true,
    ['stone_wall/tee/n'] = true,
}

-- NB: Other `cabinets` setup is in `object.chest`.
structure_items.attachment_map['cabinets'] = horiz_walls
structure_items.attachment_map['bookshelf/0'] = horiz_walls

add_attachment_item('bookshelf', 'bookshelf/0')


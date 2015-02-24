local action = require('outpost.action')
local util = require('outpost.util')

-- Main entry point for placing a structure item in the world.
local function place_structure(world, inv, pos, item_name, template_name)
    if inv:count(item_name) == 0 then
        return
    end

    s, err = world:create_structure(pos, template_name)

    if s ~= nil then
        s:attach_to_chunk()
        inv:update(item_name, -1)
    end
end

local function take_structure(s, inv, item_name)
    if inv:count(item_name) == 255 then
        return
    end

    err = s:destroy()
    if err == nil then
        inv:update(item_name, 1)
    end
end

local function use_item(c, inv, item_name, template_name)
    local pos = util.hit_tile(c:pawn())
    place_structure(c:world(), inv, pos, item_name, template_name)
end

local function use_structure(c, s, item_name)
    take_structure(s, c:pawn():inventory('main'), item_name)
end

local function add_structure_item(item_name, template_name)
    if template_name == nil then
        template_name = item_name
    end

    action.use_item[item_name] = function(c, inv)
        use_item(c, inv, item_name, template_name)
    end

    action.use[template_name] = function(c, s)
        use_structure(c, s, item_name)
    end
end

for _, side in ipairs({'n', 's', 'w', 'e', 'nw', 'ne', 'sw', 'se'}) do
    add_structure_item('house_wall/' .. side)
end
add_structure_item('house_floor')

return {
    place_structure = place_structure,
    take_structure = take_structure,
    use_item = use_item,
    use_structure = use_structure,
}
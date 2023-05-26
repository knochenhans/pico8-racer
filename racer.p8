pico-8 cartridge // http://www.pico-8.com
version 41
__lua__

-- Constants
FOV = 60 -- Field of View
HALF_WIDTH = 64 -- Half of the screen width
HALF_HEIGHT = 64 -- Half of the screen height
NEAR_PLANE = 0.1 -- Near clipping plane
FAR_PLANE = 100 -- Far clipping plane

screen_width = 128

max_speed = 0.7

player = {
    x_pos = 0,
    sprite_width = 32,
    x_velocity = 0,
    sprite_root = 97,
    current_sprite_offset = 0,
    move_speed = 0.1,
    pos = { x = 0, y = 0, z = 0 },
    speed = 0
}

race_state = "not_started"

-- Camera position
camera = { x = 0, y = -1.5, z = -1.3 }

-- Movement speed
player.move_speed = 0.07

current_z = -9
current_color_idx = 1
section_length = 4

z_pos = 0

sections = {}

function set_loop(sfx, start, end_)
  local addr = 0x3200 + 68 * sfx
  poke(addr + 66, start)
  poke(addr + 67, end_)
end

section_config = {
    colors = { 6, 13 },
    colors_landscape = { 11, 3 }
}

function add_section_pair(section_config, slope, curve, y)
    add(sections, { color = section_config.colors[1], landscape_color = section_config.colors_landscape[1], marking = false, objects = rnd() < 0.5, object_offset_x = rnd(1), slope = slope, curve = curve, y = y })
    add(sections, { color = section_config.colors[2], landscape_color = section_config.colors_landscape[2], marking = true, objects = rnd() < 0.5, object_offset_x = rnd(1), slope = slope, curve = curve, y = y })
end

function _init()
    -- Generate initial sections
    for x=0, 10 do
        add_section_pair(section_config, 0, 0, 0)
    end

    -- add(sections, { color = 6, landscape_color = 11, marking = 0, slope = 0.1, curve = 0, y = 0 })
    -- add(sections, { color = 6, landscape_color = 3, marking = 0, slope = 0.1, curve = 0, y = 0 })

    -- add(sections, { color = 6, landscape_color = 11, marking = 0, slope = 0, curve = 0, y = 0.1 })
    -- add(sections, { color = 6, landscape_color = 3, marking = 0, slope = 0, curve = 0, y = 0.1 })

    -- add(sections, { color = section_config.colors[1], landscape_color = 5, marking = 0, objects = 1, object_offset_x = rnd(1), slope = 0, curve = 0, y = 0 })


    sfx(0)

    player.x_pos = screen_width / 2 - 16
    camera_offset = player.x_pos
end

function qsort_by_sum_z(lines, compare)
    compare = compare or function(a, b) return a < b end

    local function line_sum_z(line)
        return line[1].z + line[2].z
    end

    local function partition(list, low, high)
        local pivot = list[high]
        local i = low - 1

        for j = low, high - 1 do
            if compare(line_sum_z(pivot), line_sum_z(list[j])) then
                i = i + 1
                list[i], list[j] = list[j], list[i]
            end
        end

        list[i + 1], list[high] = list[high], list[i + 1]
        return i + 1
    end

    local function quicksort(list, low, high)
        if low < high then
            local pivotIndex = partition(list, low, high)
            quicksort(list, low, pivotIndex - 1)
            quicksort(list, pivotIndex + 1, high)
        end
    end

    quicksort(lines, 1, #lines)
end

-- Perform perspective projection
function project(point)
    local dx = point.x - camera.x
    local dy = point.y - camera.y
    local dz = point.z - camera.z

    local factor = FOV / (dz + NEAR_PLANE)
    local x = dx * factor + HALF_WIDTH
    local y = dy * factor + HALF_HEIGHT

    return { x = x, y = y, dz = dz }
end

function draw_projected_filled_rect(v1, v2, v3, v4, color)
    -- Sort the vertices by y-coordinate (top to bottom)
    local vertices = { v1, v2, v3, v4 }
    -- vertices = sort_vertices(vertices)
    -- table.sort(vertices, function(a, b) return a.y < b.y end)

    -- Calculate the slopes (dx/dy) for each pair of edges
    local slope1 = (vertices[2].x - vertices[1].x) / (vertices[2].y - vertices[1].y)
    local slope2 = (vertices[4].x - vertices[1].x) / (vertices[4].y - vertices[1].y)
    local slope3 = (vertices[3].x - vertices[2].x) / (vertices[3].y - vertices[2].y)
    local slope4 = (vertices[4].x - vertices[3].x) / (vertices[4].y - vertices[3].y)

    -- Draw the filled shape
    for y = vertices[1].y, vertices[4].y do
        local x1 = vertices[1].x + (y - vertices[1].y) * slope1
        local x2 = vertices[1].x + (y - vertices[1].y) * slope2
        local x3 = vertices[2].x + (y - vertices[2].y) * slope3
        local x4 = vertices[3].x + (y - vertices[3].y) * slope4

        -- Sort the x-coordinates for each scanline
        local start_x, end_x = x1, x1
        if x2 < start_x then
            start_x = x2
        elseif x2 > end_x then
            end_x = x2
        end
        if x3 < start_x then
            start_x = x3
        elseif x3 > end_x then
            end_x = x3
        end
        if x4 < start_x then
            start_x = x4
        elseif x4 > end_x then
            end_x = x4
        end

        line(start_x, y, end_x, y, color)
    end
end

z_offset = 0

road_width = 5
road_width_half = road_width / 2
strip_length = 0.5

function generate_strip(width, z, strip_length, x_offset)
    local vertices = {}
    add(vertices, project({ x = width + x_offset, y = 0, z = z + strip_length }))
    add(vertices, project({ x = width + x_offset, y = 0, z = z }))
    add(vertices, project({ x = -1 * width + x_offset, y = 0, z = z + strip_length }))
    add(vertices, project({ x = -1 * width + x_offset, y = 0, z = z }))
    return vertices
end

-- takes in-world coordinates/sizes, returns screen coordinates
function generate_sprite(width, height, x, y, z)
    scale_factor = 1/24
    return {
        projected_corner_top_left = project({ x = x, y = y + height * scale_factor, z = z }),
        projected_corner_bottom_right = project({ x = x + width * scale_factor, y = y, z = z })
    }
end

sprite_w = 24
sprite_h = 32

function _draw()
    cls()
    rectfill(0, 0, 128, 128, 12)
    
    local z_offset = 0
    
    projected_rects = {}
    projected_mark_rects = {}
    sprites = {}

    -- Generate and collect strips
    for section in all(sections) do
        vertices = {}

        slope = section.slope * -1

        -- Calculate screen projections 
        add(vertices, project({ x = road_width_half, y = section.y + slope, z = z_pos + z_offset + strip_length }))
        add(vertices, project({ x = road_width_half, y = section.y, z = z_pos + z_offset }))
        add(vertices, project({ x = -1 * (road_width_half), y = section.y + slope, z = z_pos + z_offset + strip_length }))
        add(vertices, project({ x = -1 * (road_width_half), y = section.y, z = z_pos + z_offset }))
        
        add(projected_rects, { vertices = vertices, color = section.color, landscape_color = section.landscape_color } )
        vertices = {}
        
        if section.marking == true then         
            add(projected_mark_rects, { vertices = generate_strip(0.01, z_pos + z_offset, strip_length, 0) } )
            add(projected_mark_rects, { vertices = generate_strip(0.01, z_pos + z_offset, strip_length, -1) } )
            add(projected_mark_rects, { vertices = generate_strip(0.01, z_pos + z_offset, strip_length, 1) } )
            add(projected_mark_rects, { vertices = generate_strip(0.02, z_pos + z_offset, strip_length, road_width_half - 0.1) } )
            add(projected_mark_rects, { vertices = generate_strip(0.02, z_pos + z_offset, strip_length, (road_width_half - 0.1) - 0.2) } )
            add(projected_mark_rects, { vertices = generate_strip(0.02, z_pos + z_offset, strip_length, -1 * (road_width_half - 0.1)) } )
            add(projected_mark_rects, { vertices = generate_strip(0.02, z_pos + z_offset, strip_length, -1 * ((road_width_half - 0.1) - 0.2)) } )
        end

        if section.objects == true then
            --add(sprites, { projected_pos = project({ x = road_width_half + 2, y = section.y, z = z_pos + z_offset }), z_pos = z_pos + z_offset } ) -- Add object type/sprite here?
            
            add(sprites, generate_sprite(sprite_w, sprite_h, road_width_half + 0.5 + section.object_offset_x, section.y, z_pos + z_offset))
            add(sprites, generate_sprite(sprite_w, sprite_h, -1 * (road_width_half + 0.5 + section.object_offset_x), section.y, z_pos + z_offset))
        end

        z_offset += strip_length
    end

    -- Draw landscape strips
    for projected_rect in all(projected_rects) do
        rectfill(0, projected_rect.vertices[1].y, 128, projected_rect.vertices[2].y, projected_rect.landscape_color)
    end

    -- Draw road strips
    for projected_rect in all(projected_rects) do
        draw_projected_filled_rect(projected_rect.vertices[1], projected_rect.vertices[2], projected_rect.vertices[3], projected_rect.vertices[4], projected_rect.color)
    end
    
    -- Draw road markings
    for projected_rect in all(projected_mark_rects) do
        draw_projected_filled_rect(projected_rect.vertices[1], projected_rect.vertices[2], projected_rect.vertices[3], projected_rect.vertices[4], 7)
    end

    for sprite in all(sprites) do
        -- scale = 1 / sprite.z_pos
        
        -- w = sprite_w * scale
        -- h = sprite_h * scale
        height = sprite.projected_corner_top_left.y - sprite.projected_corner_bottom_right.y
        width = sprite.projected_corner_bottom_right.x - sprite.projected_corner_top_left.x

        -- s = generate_sprite(24, 32, sprite.)
        
        sx, sy = (1 % 16) * 8, flr(1 \ 16) * 8
        -- sspr(sx, sy, 24, 32, sprite.projected_pos.x - w, sprite.projected_pos.y - h, w, h)
        sspr(sx, sy, sprite_w, sprite_h, sprite.projected_corner_top_left.x - width / 2, sprite.projected_corner_bottom_right.y - height, width, height)
        -- printh(sprite.projected_corner_top_left.y)
        -- printh("tl.x: " .. sprite.projected_corner_top_left.x .. "/ br.x" .. sprite.projected_corner_bottom_right.x)
        -- printh("tl.y: " .. sprite.projected_corner_top_left.y .. "/ br.y" .. sprite.projected_corner_bottom_right.y)
        -- rectfill(sprite.projected_corner_top_left.x, sprite.projected_corner_top_left.y, sprite.projected_corner_bottom_right.x, sprite.projected_corner_bottom_right.y, 1)
    end


    spr(player.sprite_root + player.current_sprite_offset, project(player.pos).x - player.sprite_width / 2, 110, 4, 2)

    print(ceil(player.speed * 250) .. " kmh", 2, 2)
end

timer = 0
wait = 0.01

deleted = 0

function _update()
    player.x_velocity = 0
    player.current_sprite_offset = 0
    -- Move the camera
    if btn(0) then
        -- Left arrow button
        player.x_velocity = -1 * player.move_speed
        player.current_sprite_offset = 8
    elseif btn(1) then
        -- Right arrow button
        player.x_velocity = player.move_speed
        player.current_sprite_offset = 4
    end

    if btn(2) then
        -- Up arrow button
        player.speed += 0.01

        if race_state == "not_started" then
            race_state = "running"
        end
    elseif btn(3) then
        -- Down arrow button
        player.speed -= 0.01 

        sfx(1)
    end

    -- if abs(player.pos.x) > road_width_half then
    --     player.speed -= 0.02
    -- end

    if race_state == "running" then
        -- if player.speed < 0.05 then
        --     player.speed = 0.05
        -- end

        if player.speed > max_speed then
            player.speed = max_speed
        end
    end

    if player.x_velocity != 0 then
        player.pos.x += player.x_velocity
        camera.x = player.pos.x
    end

    -- Set engine sfx loop
    s = flr(player.speed * 45)
    set_loop(0, s, s + 3)
    
    -- Update road strips
    if time() - timer > wait then
        timer = time()
        
        z_pos -= player.speed

        -- Remove road strips leaving the camera
        if z_pos < -0.5 then
            deli(sections, 1)
            deleted += 1
            z_pos = 0
        end

        -- For every 2 removed strips, add 2 new one
        if deleted >= 2 then
            add_section_pair(section_config, 0, 0, 0)
            deleted = 0
        end
    end
end

__gfx__
76d51000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000003b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000003b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000003bb300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000003bb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000003303310300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000333b54300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000113333b333000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000100b35b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000133b15533b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000001bbb15b33b333300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000001331353553b30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000311355454333330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000100b503133b33b3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000003533333335bb0b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000503313155b3053000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000333bbbb133b33b3300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000011330b33315b333b3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000001103b0bb53b33b33000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000013333005b053b33000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000310013b513b3503000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000013113bb5311bb03000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000001111114333bb330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000011155bb3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000033544400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000544900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000002144990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000001444490000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000011111111100110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000110111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000222222222222220000000000000000002222222222222200000000000000000022222222222222000000000000000000000000000000000
0000000000000002222222222222eee220000000000000022222222222222e22200000000000000222e222222222222ef0000000000000000000000000000000
00000000000002eef000000000000000ff20000000002eef000000000000000ff22200000000222ee000000000000000eff20000000000000000000000000000
00000000000022eeeeeeeeeeeeefefffee22000000022eeeeeeeeeeeeeeefffee22222000022222eeeeeeeeeeeeeeeeeeee22000000000000000000000000000
000000000002eeeee222222222222222eef22000002eeeee222222222222222eef222e20022222eee222222222222222eeeef200000000000000000000000000
0000000000eeeeeeeeeeeeeeeeeeefffffffff000eeeeeeeeeeeeeeeeeeeeefffffffe20022eeeeeeeeeeeeeeeeeeeeeeefffff0000000000000000000000000
000000000022222222222222222222222222220002222222222222222222222222222e2002222222222222222222222222222220000000000000000000000000
000000000088288882266666666662288882880008828888226666666666228888288e20022882888822666666666622888828e0000000000000000000000000
000000000088288882266666666662288882880008828888226666666666228888288e20022882888822666666666622888828e0000000000000000000000000
000000000022222222222222222222222222220002222222222222222222222222222e1001222222222222222222222222222220000000000000000000000000
0000000000eeeeeeeeeeeeeeeeeeeeeeefefff000eeeeeeeeeeeeeeeeeeeeeeefefff200002eeeeeeeeeeeeeeeeeeeeeeeeeeff0000000000000000000000000
0000000000eeeeeeeeeeeeeeeeeeeeeeeeeeef000eeeeeeeeeeeeeeeeeeeeeeeeeeef200002eeeeeeeeeeeeeeeeeeeeeeeeeeef0000000000000000000000000
0000000000eeeeeeeeeeeeeeeeeeeeeeeeeeef000eeeeeeeeeeeeeeeeeeeeeeeeeeeed000012eeeeeeeeeeeeeeeeeeeeeeeeeef0000000000000000000000000
00000000001111122222222222222222211111000111112222222222222222221111110000111111222222222222222222111110000000000000000000000000
00000000001111110000000000000000111111000011111000000000000000011111100000011111100000000000000001111100000000000000000000000000
__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000
0000001010000010100000101000000000101010101010101010101010000000001010101010101010000000000000000010101010101010100000000000000000101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100030402004030050100605006050060500705008050090500a0500b0500b0500c0500d0500e0500f050100501105012050130501405015050160501705018050190501a0501b0501c0501e0501f0501f050
000300001f0301f0101f0301f0101f0301f010160100e010040001300010000060000000003000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00010003090200a0300b0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

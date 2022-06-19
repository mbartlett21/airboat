-- Functions

local function get_sign(i)
    if i == 0 then
        return 0
    else
        return i / math.abs(i)
    end
end


local function get_velocity(v, yaw, y)
    local x = -math.sin(yaw) * v
    local z =  math.cos(yaw) * v
    return {x = x, y = y, z = z}
end


local function get_v(v)
    return math.sqrt(v.x ^ 2 + v.z ^ 2)
end


-- Airboat entity

local airboat_entity = {
        initial_properties = {
        physical = true,
        collide_with_objects = false, -- Workaround fix for a MT engine bug
        collisionbox = {-0.85, -1.5, -0.85, 0.85, 1.5, 0.85},
        visual = "wielditem",
        visual_size = {x = 2.0, y = 2.0}, -- Scale up of nodebox is these * 1.5
        textures = {"airboat:airboat_nodebox"},
    },

    -- Custom fields
    driver = nil,
    removed = false,
    v = 0,
    vy = 0,
    rot = 0,
    auto = false,
}


function airboat_entity.on_rightclick(self, clicker)
    if not clicker or not clicker:is_player() then
        return
    end
    local name = clicker:get_player_name()
    if self.driver and name == self.driver then
        -- Detach
        self.driver = nil
        self.auto = false
        clicker:set_detach()
        default.player_attached[name] = false
        default.player_set_animation(clicker, "stand" , 30)
        local pos = clicker:getpos()
        minetest.after(0.1, function()
            clicker:setpos(pos)
        end)
    elseif not self.driver then
        -- Attach
        local attach = clicker:get_attach()
        if attach and attach:get_luaentity() then
            local luaentity = attach:get_luaentity()
            if luaentity.driver then
                luaentity.driver = nil
            end
            clicker:set_detach()
        end
        self.driver = name
        clicker:set_attach(self.object, "",
            {x = 0, y = -2, z = 0}, {x = 0, y = 0, z = 0})
        default.player_attached[name] = true
        minetest.after(0.2, function()
            default.player_set_animation(clicker, "sit" , 30)
        end)
        clicker:set_look_horizontal(self.object:getyaw())
    end
end


function airboat_entity.on_activate(self, staticdata, dtime_s)
    self.object:set_armor_groups({immortal = 1})
end


function airboat_entity.on_punch(self, puncher)
    if not puncher or not puncher:is_player() or self.removed then
        return
    end

    local name = puncher:get_player_name()
    if self.driver and name == self.driver then
        -- Detach
        self.driver = nil
        puncher:set_detach()
        default.player_attached[name] = false
    end
    if not self.driver then
        -- Move to inventory
        self.removed = true
        local inv = puncher:get_inventory()
        if not (creative and creative.is_enabled_for
                and creative.is_enabled_for(name))
                or not inv:contains_item("main", "airboat:airboat") then
            local leftover = inv:add_item("main", "airboat:airboat")
            if not leftover:is_empty() then
                minetest.add_item(self.object:getpos(), leftover)
            end
        end
        minetest.after(0.1, function()
            self.object:remove()
        end)
    end
end


function airboat_entity.on_step(self, dtime)
    self.v = get_v(self.object:getvelocity()) * get_sign(self.v)
    self.vy = self.object:getvelocity().y

    -- Controls
    if self.driver then
        local driver_objref = minetest.get_player_by_name(self.driver)
        if driver_objref then
            local ctrl = driver_objref:get_player_control()
            if ctrl.up and ctrl.down then
                if not self.auto then
                    self.auto = true
                    minetest.chat_send_player(self.driver,
                        "[airboat] Cruise on")
                end
            elseif ctrl.down then
                self.v = self.v - 0.1
                if self.auto then
                    self.auto = false
                    minetest.chat_send_player(self.driver,
                        "[airboat] Cruise off")
                end
            elseif ctrl.up or self.auto then
                self.v = self.v + 0.1
            end
            if ctrl.left then
                self.rot = self.rot + 0.001
            elseif ctrl.right then
                self.rot = self.rot - 0.001
            end
            if ctrl.jump then
                self.vy = self.vy + 0.075
            elseif ctrl.sneak then
                self.vy = self.vy - 0.075
            end
        else
            -- Player left server while driving
            -- In MT 5.0.0 use 'airboat:on_detach_child()' to do this
            self.driver = nil
            self.auto = false
            minetest.log("warning", "[airboat] Driver left server while" ..
                " driving. This may cause some 'Pushing ObjectRef to" ..
                " removed/deactivated object' warnings.")
        end
    end

    -- Early return for stationary vehicle
    if self.v == 0 and self.rot == 0 and self.vy == 0 then
        self.object:setpos(self.object:getpos())
        return
    end

    -- Reduction and limiting of linear speed
    local s = get_sign(self.v)
    self.v = self.v - 0.02 * s
    if s ~= get_sign(self.v) then
        self.v = 0
    end
    if math.abs(self.v) > 6 then
        self.v = 6 * get_sign(self.v)
    end

    -- Reduction and limiting of rotation
    local sr = get_sign(self.rot)
    self.rot = self.rot - 0.0003 * sr
    if sr ~= get_sign(self.rot) then
        self.rot = 0
    end
    if math.abs(self.rot) > 0.015 then
        self.rot = 0.015 * get_sign(self.rot)
    end

    -- Reduction and limiting of vertical speed
    local sy = get_sign(self.vy)
    self.vy = self.vy - 0.03 * sy
    if sy ~= get_sign(self.vy) then
        self.vy = 0
    end
    if math.abs(self.vy) > 4 then
        self.vy = 4 * get_sign(self.vy)
    end

    local new_acce = {x = 0, y = 0, z = 0}
    -- Bouyancy in liquids
    local p = self.object:getpos()
    p.y = p.y - 2
    local def = minetest.registered_nodes[minetest.get_node(p).name]
    if def and (def.liquidtype == "source" or def.liquidtype == "flowing") then
        new_acce = {x = 0, y = 10, z = 0}
    end

    self.object:setpos(self.object:getpos())
    self.object:setvelocity(get_velocity(self.v, self.object:getyaw(), self.vy))
    self.object:setacceleration(new_acce)
    self.object:setyaw(self.object:getyaw() + (1 + dtime) * self.rot)
end


minetest.register_entity("airboat:airboat", airboat_entity)


-- Craftitem

minetest.register_craftitem("airboat:airboat", {
    description = "Airboat",
    inventory_image = "airboat_airboat_inv.png",
    wield_scale = {x = 2, y = 2, z = 2},
    liquids_pointable = true,

    on_place = function(itemstack, placer, pointed_thing)
        local under = pointed_thing.under
        local node = minetest.get_node(under)
        local udef = minetest.registered_nodes[node.name]

        -- Run any on_rightclick function of pointed node instead
        if udef and udef.on_rightclick and
                not (placer and placer:is_player() and
                placer:get_player_control().sneak) then
            return udef.on_rightclick(under, node, placer, itemstack,
                pointed_thing) or itemstack
        end

        if pointed_thing.type ~= "node" then
            return itemstack
        end

        pointed_thing.under.y = pointed_thing.under.y + 2.5
        local airboat = minetest.add_entity(pointed_thing.under,
            "airboat:airboat")
        if airboat then
            if placer then
                airboat:setyaw(placer:get_look_horizontal())
            end
            creative.take_from_inventory(placer, itemstack)
        end
        return itemstack
    end,
    stack_max = 1,
    groups = { creative = 1 }
})


-- Nodebox for entity wielditem visual

minetest.register_node("airboat:airboat_nodebox", {
    description = "Airboat Nodebox",
    tiles = { -- Top, base, right, left, front, back
        "airboat_airboat_top.png",
        "airboat_airboat_base.png",
        "airboat_airboat_right.png",
        "airboat_airboat_left.png",
        "airboat_airboat_front.png",
        "airboat_airboat_back.png",
    },
    paramtype = "light",
    drawtype = "nodebox",
    node_box = {
        type = "fixed",
        fixed = {
            -- Wmin,  hmin,  lmin, wmax,  hmax,  lmax
            { -5/16, -1/8,  -1/2,  5/16,  3/8,   1/2 }, -- Envelope
            { -3/16, -1/2,  -1/4,  3/16, -1/8,   1/4 }, -- Gondola
            { -1/32,  3/8,  -1/2,  1/32,  1/2,  -1/4 }, -- Top fin
            { -1/32, -1/4,  -1/2,  1/32, -1/8,  -1/4 }, -- Base fin
            { -7/16,  3/32, -1/2, -5/16,  5/32, -1/4 }, -- Left fin
            {  5/16,  3/32, -1/2,  7/16,  5/32, -1/4 }, -- Right fin
        },
    },
    groups = {not_in_creative_inventory = 1},
})

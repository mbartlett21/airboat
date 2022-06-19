-- This is an edited version of Paramat's airboat mod:
--  https://github.com/paramat/airboat

local acceleration = 2

local friction = 0.1

local acceleration_y = 1

local friction_y = 0.25

local yaw_speed = 0.015

-- Functions

local function airboat_manage_attachment(player, obj, is_passenger)
    if not player then
        return
    end
    local status = obj ~= nil
    local player_name = player:get_player_name()
    if player_api.player_attached[player_name] == status then
        return
    end
    player_api.player_attached[player_name] = status

    if status then
        local attach = player:get_attach()
        if attach and attach:get_luaentity() then
            local luaentity = attach:get_luaentity()
            if luaentity.driver then
                luaentity.driver = nil
            end
            player:set_detach()
        end
        player:set_attach(obj, "", {x = is_passenger and 5 or -5, y = -3, z = 0}, {x = 0, y = 0, z = 0})
        player:set_eye_offset({x = 0, y = 6, z = 0}, {x = 0, y = 9, z = 0})
    else
        player:set_detach()
        player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
        player_api.set_animation(player, "stand" , 30)
    end
end


-- Airboat entity

local airboat_entity = {
    initial_properties = {
        physical = true,
        collide_with_objects = false, -- Workaround fix for a MT engine bug
        collisionbox = {-1.4, -2, -1.4, 1.4, 1.8, 1.4},
        visual = "wielditem",
        visual_size = {x = 2.65, y = 2.65}, -- Scale up of nodebox is these * 1.5, so 4
        textures = {"airboat:airboat_nodebox"},
    },

    -- Custom fields
    driver = nil, -- Current driver
    passenger = nil, -- Current passenger
    auto = false, -- Cruise control
}


function airboat_entity:on_rightclick(clicker)
    if not clicker or not clicker:is_player() then
        return
    end
    local name = clicker:get_player_name()

    if self.driver and name == self.driver then
        self.driver = nil
        self.auto = false
        -- Detach
        airboat_manage_attachment(clicker, nil)

    elseif self.passenger and name == self.passenger then
        self.passenger = nil
        -- Detach
        airboat_manage_attachment(clicker, nil)

    elseif not self.driver then
        self.driver = name
        airboat_manage_attachment(clicker, self.object)

        -- player_api does not update the animation
        -- when the player is attached, reset to default animation
        minetest.after(0.2, function()
          player_api.set_animation(clicker, "sit" , 30)
        end)
        clicker:set_look_horizontal(self.object:getyaw())

    elseif not self.passenger then
        self.passenger = name
        airboat_manage_attachment(clicker, self.object, true)

        -- player_api does not update the animation
        -- when the player is attached, reset to default animation
        minetest.after(0.2, function()
          player_api.set_animation(clicker, "sit" , 30)
        end)
        clicker:set_look_horizontal(self.object:getyaw())
    end
end

function airboat_entity:on_activate()
    self.object:set_armor_groups({immortal = 1})
end

function airboat_entity:on_detach_child(child)
    if child and child:get_player_name() == self.driver then
        airboat.cancel_go(self.driver)
        self.driver = nil
        self.auto = false
    end

    if child and child:get_player_name() == self.passenger then
        airboat.cancel_go(self.passenger)
        self.passenger = nil
    end
end

function airboat_entity:on_punch(puncher)
    if not puncher or not puncher:is_player() then
        return
    end

    -- Player can only pick it up if no-one is inside
    if not self.driver and not self.passenger then
        -- Move to inventory
        creative.add_to_inventory(puncher, "airboat:airboat", self.object:get_pos())
        minetest.after(0, function()
            self.object:remove()
        end)
    end
end



function airboat_entity:on_step()
    local object_v = self.object:get_velocity()

    -- local horiz_vel_sq = object_v.x * object_v.x + object_v.y * object_v.y

    local vx_acc = -object_v.x * friction
    local vz_acc = -object_v.z * friction

    local curr_yaw = self.object:getyaw()
    local new_yaw = curr_yaw

    local vx_acc_mult = -math.sin(curr_yaw)
    local vz_acc_mult =  math.cos(curr_yaw)

    local vy_acc = -object_v.y * friction_y

    local horiz_stop = math.abs(object_v.x) < 0.1 and math.abs(object_v.z) < 0.1

    -- Controls
    if self.driver then
        local driver_objref = minetest.get_player_by_name(self.driver)
        if driver_objref then
            local ctrl = driver_objref:get_player_control()

            -- Forward / backward
            if ctrl.up and ctrl.down then
                vx_acc = vx_acc + acceleration * vx_acc_mult
                vz_acc = vz_acc + acceleration * vz_acc_mult
                if not self.auto then
                    self.auto = true
                    minetest.chat_send_player(self.driver, "[airboat] Cruise on")
                end
                horiz_stop = false
            elseif ctrl.down then
                vx_acc = vx_acc - acceleration * vx_acc_mult
                vz_acc = vz_acc - acceleration * vz_acc_mult
                if self.auto then
                    self.auto = false
                    minetest.chat_send_player(self.driver, "[airboat] Cruise off")
                end
                horiz_stop = false
            elseif ctrl.up or self.auto then
                vx_acc = vx_acc + acceleration * vx_acc_mult
                vz_acc = vz_acc + acceleration * vz_acc_mult
                horiz_stop = false
            end

            if ctrl.left and ctrl.right then
                -- Do nothing
            elseif ctrl.left then
                new_yaw = new_yaw + yaw_speed
            elseif ctrl.right then
                new_yaw = new_yaw - yaw_speed
            end

            if ctrl.jump then
                vy_acc = vy_acc + acceleration_y
                horiz_stop = false
            elseif ctrl.sneak then
                vy_acc = vy_acc - acceleration_y
                horiz_stop = false
            end
        else
            -- Player left server while driving
            airboat.cancel_go(self.driver)
            self.driver = nil
            self.auto = false
            minetest.log("warning", "[airboat] Driver left server while" ..
                " driving. This may cause some 'Pushing ObjectRef to" ..
                " removed/deactivated object' warnings.")
        end
    end

    if horiz_stop then
        vx_acc = 0
        vz_acc = 0
        self.object:set_velocity({ x = 0, y = object_v.y, z = 0 })
    end

    if not self.driver then
        vy_acc = vy_acc - 0.5
        -- Slow down when there's no driver
        vx_acc = vx_acc * 3
        vz_acc = vz_acc * 3
    end

    local new_acce = { x = vx_acc, y = vy_acc, z = vz_acc }
    -- Bouyancy in liquids
    local p = self.object:get_pos()
    p.y = p.y - 2
    local def = minetest.registered_nodes[minetest.get_node(p).name]
    if def and (def.liquidtype == "source" or def.liquidtype == "flowing") then
        new_acce.y = new_acce.y + 10
    end

    self.object:set_acceleration(new_acce)
    if new_yaw ~= curr_yaw then
        self.object:set_yaw(new_yaw)
    end
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
        groups = { not_in_creative_inventory = 1 },
})

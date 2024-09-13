local modname = minetest.get_current_modname()
local S = minetest.get_translator(modname)
local mod_storage = minetest.get_mod_storage()
local completed_quests_count_key = "completed_quests_count"


local time_before_reset = 86400
local reset_hour = 3
local quest_key = "daily_quest_data"
local player_progress_key_prefix = "player_quest_progress_"

local all_quests = {
    {target = "farming:cotton", qty = 300, rewards = "atl_box:key_steel 2", rarity = 3},
    {target = "farming:wheat", qty = 300, rewards = "atl_box:key_steel 2", rarity = 3},
}

local function get_global_quest()
    local quest_data = mod_storage:get_string(quest_key)
    return quest_data ~= "" and minetest.deserialize(quest_data) or {}
end

local function set_global_quest(quest_data)
    mod_storage:set_string(quest_key, minetest.serialize(quest_data))
end

local function get_completed_quests_count()
    return tonumber(mod_storage:get_string(completed_quests_count_key)) or 0
end

local function set_completed_quests_count(count)
    mod_storage:set_string(completed_quests_count_key, tostring(count))
end

local function get_player_quest_progress(player_name)
    local progress_data = mod_storage:get_string(player_progress_key_prefix .. player_name)
    return progress_data ~= "" and minetest.deserialize(progress_data) or {completed = false, count = 0}
end

local function set_player_quest_progress(player_name, progress_data)
    mod_storage:set_string(player_progress_key_prefix .. player_name, minetest.serialize(progress_data))
end

local function choose_random_quest()
    local random_index = math.random(1, #all_quests)
    return all_quests[random_index]
end

local function init_daily_quest()
    local global_quest = get_global_quest()
    local current_time = os.time()

    if not global_quest.last_time or current_time - global_quest.last_time >= time_before_reset then
        local new_quest = choose_random_quest()
        global_quest = {
            last_time = current_time,
            quest = new_quest
        }
        set_global_quest(global_quest)

        for _, player in ipairs(minetest.get_connected_players()) do
            local player_name = player:get_player_name()
            set_player_quest_progress(player_name, {completed = false, count = 0})
        end
    end
end

local function give_rewards(player, rewards_string)
    local rewards = rewards_string:split(" ")
    local item_name = rewards[1]
    local item_count = tonumber(rewards[2])

    if item_name and item_count then
        local itemstack = ItemStack(item_name .. " " .. item_count)

        if player:get_inventory():room_for_item("main", itemstack) then
            player:get_inventory():add_item("main", itemstack)
        else
            minetest.add_item(player:get_pos(), itemstack)
            minetest.chat_send_player(player:get_player_name(), minetest.colorize("#e2e117", "[-!-] Not enough space in inventory. Dropping reward"))
        end
    end
end

local function update_quest_progress(player, amount)
    local player_name = player:get_player_name()
    local global_quest = get_global_quest()
    local quest = global_quest.quest
    local player_progress = get_player_quest_progress(player_name)

    local target_item = minetest.registered_items[quest.target]
    if not target_item then
        minetest.log("error", "[-!-] Invalid quest target: " .. quest.target)
        return
    end

    if not player_progress.completed then
        player_progress.count = player_progress.count + amount
        if player_progress.count >= quest.qty then
            player_progress.completed = true
            give_rewards(player, quest.rewards)

            local completed_count = get_completed_quests_count()
            set_completed_quests_count(completed_count + 1)
        end
        set_player_quest_progress(player_name, player_progress)
    end
end

local function get_time_remaining()
    local current_time = os.time()
    local current_date = os.date("*t", current_time)

    local next_reset_time = os.time({
        year = current_date.year,
        month = current_date.month,
        day = current_date.day + (current_date.hour >= reset_hour and 1 or 0),
        hour = reset_hour,
        min = 0,
        sec = 0
    })

    local remaining_time = next_reset_time - current_time
    return remaining_time >= 0 and remaining_time or 0
end

local function format_time(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    seconds = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function create_quest_formspec(player)
    local player_name = player:get_player_name()
    local global_quest = get_global_quest()
    local player_progress = get_player_quest_progress(player_name)
    local remaining_time = get_time_remaining()
    local formatted_time = format_time(remaining_time)


    local quest = global_quest.quest
    local progress = player_progress.count / quest.qty
    local progress_width = math.floor(progress * 3.75 * 100) / 100

    local reward_parts = quest.rewards:split(" ")
    local reward_item = reward_parts[1] or ""
    local reward_qty = tonumber(reward_parts[2]) or 1
    local completed_count = get_completed_quests_count()
    local item_description = minetest.registered_items[reward_item] and minetest.registered_items[reward_item].description or ""

    local formspec = "size[8,7]" ..
        "item_image_button[1,0.5;1,1;" .. quest.target .. ";quest_target;]" ..
        "item_image_button[5.5,0.5;1,1;" .. reward_item .. ";reward_item;]" ..
        "label[5,1.5;Rewards: x" .. reward_qty .. " " .. minetest.colorize("lightblue", item_description) .. "]" ..
        "image[2.15,0.75;3.75,0.5;backg.png]" ..
        "image[2.15,0.75;" .. progress_width .. ",0.5;back_color.png]" ..
        "tooltip[2.15,0.75;3,0.5;" .. player_progress.count .. " / " .. quest.qty .. ";#25292b;#429C0F]" ..
        "label[3.5,0.25;" .. math.floor(progress * 100) .. " %]" ..
        "label[0,2.75;Players who completed the daily quest: " .. completed_count .. "]" ..
        "label[5,-0.25;Time before reset: " .. formatted_time .. "]" ..
        "list[detached:quest_" .. player_name .. ";slot;1,1.75;1,1;]" ..
        "tabheader[0,0;daily_tabs;   Daily Quest   , Quest   ;1;false;false]" ..
        "button[2.75,1.75;2,1;submit;Submit]" ..
        "list[current_player;main;0,3.25;8,4;]"

    return formspec
end

local function show_quest_formspec(player)
    init_daily_quest()
    local formspec = create_quest_formspec(player)
    minetest.show_formspec(player:get_player_name(), "quests:form", formspec)
end

local function handle_quest_submission(player)
    local player_name = player:get_player_name()
    local detached_inv = minetest.get_inventory({type = "detached", name = "quest_" .. player_name})
    local stack = detached_inv:get_stack("slot", 1)

    if stack:is_empty() then
        return
    end

    local global_quest = get_global_quest()
    local quest = global_quest.quest

    if not quest or not quest.qty then
        minetest.log("error", "[-!-] Invalid quest data or qty not defined")
        return
    end

    local item_name = stack:get_name()
    local item_count = stack:get_count()

    local player_progress = get_player_quest_progress(player_name)
    local remaining_needed = quest.qty - player_progress.count

    if item_name == quest.target then
        if item_count <= remaining_needed then
            update_quest_progress(player, item_count)
            detached_inv:set_stack("slot", 1, ItemStack(nil))
        else
            update_quest_progress(player, remaining_needed)
            stack:set_count(item_count - remaining_needed)
            detached_inv:set_stack("slot", 1, stack)
        end
    end
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname == "quests:form" then
        if fields.submit then
            handle_quest_submission(player)
            show_quest_formspec(player)
        end
        if fields.reload then
            show_quest_formspec(player)
        end
    end
end)

minetest.register_on_joinplayer(function(player)
    local player_name = player:get_player_name()
    local inv = minetest.create_detached_inventory("quest_" .. player_name, {
        allow_put = function(inv, listname, index, stack, player)
            return stack:get_count()
        end,
        allow_take = function(inv, listname, index, stack, player)
            return stack:get_count()
        end,
        allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
            return count
        end
    })
    inv:set_size("slot", 1)
    init_daily_quest()
end)


local function reset_daily_quest(player_name)
    local current_time = os.time()
    local global_quest = {
        last_time = current_time - time_before_reset,
        quest = choose_random_quest()
    }
    set_global_quest(global_quest)

    for _, player in ipairs(minetest.get_connected_players()) do
        local player_name = player:get_player_name()
        set_player_quest_progress(player_name, {completed = false, count = 0})
    end
end

minetest.register_chatcommand("reset", {
    description = S("Reset daily quest"),
    privs = {server = true},
    func = function(name, param)
        reset_daily_quest(name)
        return true, minetest.colorize("#e2e117", S("[-!-] Daily quest reset successfully."))
    end,
})

local F = minetest.formspec_escape
local ui = unified_inventory

ui.register_button("daily", {
    type = "image",
    image = "daily_quest_icon.png",
    tooltip = S("Daily"),
    action = function(player)
        local player_name = player:get_player_name()
        minetest.show_formspec(player_name, "quests:form", create_quest_formspec(player))
    end
})

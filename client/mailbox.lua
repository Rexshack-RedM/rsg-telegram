---------------------------------
-- mailboxes (Config.Mailbox): props that open the telegram UI. Spawned around the player, removed on stop.
-- Placement uses rsg-gizmo, interaction uses rsg-target.
---------------------------------
local RSGCore = exports['rsg-core']:GetCoreObject()
local MB = Config.Mailbox or {}

local mailboxes = {} -- [id] = { id, x, y, z, heading, label }
local spawned   = {} -- [id] = entity
local blips     = {} -- [id] = blip
local isAdmin   = false
local placing   = false

local function notify(text, ntype)
    RSGCore.Functions.Notify({ title = locale('cl_title'), description = text, type = ntype or 'inform', duration = 5000 })
end

local function despawn(id)
    local obj = spawned[id]
    if obj then
        exports['rsg-target']:removeLocalEntity(obj)
        if DoesEntityExist(obj) then DeleteEntity(obj) end
        spawned[id] = nil
    end
    if blips[id] then RemoveBlip(blips[id]) blips[id] = nil end
end

local function spawn(mb)
    if spawned[mb.id] then return end
    local model = joaat(MB.Model or 'p_mailbox01x')
    if not IsModelValid(model) then return end
    if not HasModelLoaded(model) then
        RequestModel(model)
        local timeout = GetGameTimer() + 3000
        while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
        if not HasModelLoaded(model) then return end
    end
    if spawned[mb.id] or mailboxes[mb.id] ~= mb then SetModelAsNoLongerNeeded(model) return end -- removed while loading

    local obj = CreateObjectNoOffset(model, mb.x, mb.y, mb.z, false, false, false, false)
    if not obj or obj == 0 then SetModelAsNoLongerNeeded(model) return end
    FreezeEntityPosition(obj, true)
    SetEntityCoordsNoOffset(obj, mb.x, mb.y, mb.z, false, false, false)
    SetEntityHeading(obj, mb.heading or 0.0)
    SetEntityInvincible(obj, true)
    SetModelAsNoLongerNeeded(model)
    spawned[mb.id] = obj

    exports['rsg-target']:addLocalEntity(obj, {
        {
            name = 'rsg_telegram_mailbox_' .. mb.id,
            icon = 'fa-solid fa-envelope',
            label = locale('target_mailbox'),
            distance = MB.Distance or 2.0,
            canInteract = function() return not IsEntityDead(PlayerPedId()) end,
            onSelect = function()
                -- the server decides again whether the player is close enough (server/server.lua canUseUI)
                TriggerEvent('rsg-telegram:client:openAt', locale('cl_mailbox_label'), vector3(mb.x, mb.y, mb.z), (MB.Distance or 2.0) + 2.5)
            end,
        },
        {
            name = 'rsg_telegram_mailbox_remove_' .. mb.id,
            icon = 'fa-solid fa-trash',
            label = locale('target_mailbox_remove'),
            distance = MB.Distance or 2.0,
            canInteract = function() return isAdmin end,
            onSelect = function()
                CreateThread(function()
                    if RSGCore.Functions.AwaitCallback('rsg-telegram:server:removeMailbox', 5000, mb.id) then
                        notify(locale('cl_mailbox_removed'), 'success')
                    end
                end)
            end,
        },
    })

    if MB.Blip then
        local blip = BlipAddForCoords(Config.Blip.style, mb.x, mb.y, mb.z)
        SetBlipSprite(blip, Config.Blip.sprite, true)
        SetBlipScale(blip, 0.15)
        SetBlipName(blip, locale('cl_mailbox_label'))
        blips[mb.id] = blip
    end
end

-- stream the props in and out around the player
CreateThread(function()
    if MB.Enabled ~= true then return end
    local data = RSGCore.Functions.AwaitCallback('rsg-telegram:server:getMailboxes', 10000)
    if type(data) == 'table' then
        isAdmin = data.admin == true
        for _, mb in ipairs(data.list or {}) do mailboxes[mb.id] = mb end
    end
    local range = MB.SpawnDistance or 75.0
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for id, mb in pairs(mailboxes) do
            local near = #(pos - vector3(mb.x, mb.y, mb.z)) <= range
            if near and not spawned[id] then spawn(mb)
            elseif not near and spawned[id] then despawn(id) end
        end
        Wait(1500)
    end
end)

RegisterNetEvent('rsg-telegram:client:mailboxAdded', function(mb)
    if type(mb) == 'table' and mb.id then mailboxes[mb.id] = mb end
end)

RegisterNetEvent('rsg-telegram:client:mailboxRemoved', function(id)
    mailboxes[id] = nil
    despawn(id)
end)

-- /addmailbox: place with rsg-gizmo, the server validates and saves
RegisterNetEvent('rsg-telegram:client:placeMailbox', function()
    if placing or MB.Enabled ~= true then return end
    placing = true
    CreateThread(function()
        local result = exports['rsg-gizmo']:Place(MB.Model or 'p_mailbox01x', {
            title = locale('cl_place_title'),
            maxDistance = MB.PlaceDistance or 6.0,
            rotation = 'z',
        })
        if result then
            local c = result.coords
            local ok = RSGCore.Functions.AwaitCallback('rsg-telegram:server:addMailbox', 5000, {
                x = c.x, y = c.y, z = c.z, heading = result.heading or (result.rotation and result.rotation.z) or 0.0,
            })
            if ok then notify(locale('cl_mailbox_placed'), 'success') end
        end
        placing = false
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if placing then pcall(function() exports['rsg-gizmo']:Cancel() end) end
    for id in pairs(spawned) do despawn(id) end
end)

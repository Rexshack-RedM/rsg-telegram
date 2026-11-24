---------------------------------
-- mailboxes: admin-placed props that open the telegram UI (see Config.Mailbox)
-- Positions live in rsg_telegram_mailboxes and in the shared TelegramMailboxes table (server/server.lua checks it
-- when it decides whether a player may use the UI). Placement uses rsg-gizmo, interaction uses rsg-target.
---------------------------------
local RSGCore = exports['rsg-core']:GetCoreObject()
local I = TelegramInternal
local MB = Config.Mailbox or {}

local lastAdminAction = {} -- [src] = GetGameTimer()

local function enabled() return MB.Enabled == true end

local function isAdmin(src)
    return RSGCore.Functions.HasPermission(src, MB.Permission or 'admin') and true or false
end

local function count()
    local n = 0
    for _ in pairs(TelegramMailboxes) do n = n + 1 end
    return n
end

local function slow(src)
    local now = GetGameTimer()
    if lastAdminAction[src] and now - lastAdminAction[src] < 750 then return true end
    lastAdminAction[src] = now
    return false
end

local function view(mb)
    return { id = mb.id, x = mb.x, y = mb.y, z = mb.z, heading = mb.heading, label = mb.label }
end

I.onReady(function()
    if not enabled() then return end
    local ok, rows = pcall(MySQL.query.await, 'SELECT id, label, x, y, z, heading FROM rsg_telegram_mailboxes')
    if not ok then return print(('[%s]^1 could not load mailboxes: %s^7'):format(GetCurrentResourceName(), tostring(rows))) end
    for _, r in ipairs(rows or {}) do
        TelegramMailboxes[r.id] = { id = r.id, x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0, heading = (r.heading or 0) + 0.0, label = r.label }
    end
end)

-- everything the client needs to spawn the props, plus whether it may place / remove them
RSGCore.Functions.CreateCallback('rsg-telegram:server:getMailboxes', function(source, cb)
    if not enabled() or not RSGCore.Functions.GetPlayer(source) then return cb(false) end
    local list = {}
    for _, mb in pairs(TelegramMailboxes) do list[#list + 1] = view(mb) end
    cb({ list = list, admin = isAdmin(source) })
end)

-- /addmailbox (admin): the client then opens the rsg-gizmo placement
RSGCore.Commands.Add('addmailbox', locale('cmd_addmailbox'), {}, false, function(source)
    if source == 0 or not enabled() then return end
    if not isAdmin(source) then return TriggerClientEvent('RSGCore:Client:Notify', source, { title = locale('cl_title'), description = locale('sv_mailbox_denied'), type = 'error', duration = 5000 }) end
    TriggerClientEvent('rsg-telegram:client:placeMailbox', source)
end, 'admin')

local function deny(src, key)
    TriggerClientEvent('RSGCore:Client:Notify', src, { title = locale('cl_title'), description = locale(key), type = 'error', duration = 5000 })
end

-- the client sends the gizmo result; everything is re-checked here
RSGCore.Functions.CreateCallback('rsg-telegram:server:addMailbox', function(source, cb, data)
    local src = source
    if not enabled() or type(data) ~= 'table' or not RSGCore.Functions.GetPlayer(src) or slow(src) then return cb(false) end
    if not isAdmin(src) then deny(src, 'sv_mailbox_denied') return cb(false) end
    if count() >= (MB.Max or 100) then deny(src, 'sv_mailbox_limit') return cb(false) end

    local x, y, z, heading = tonumber(data.x), tonumber(data.y), tonumber(data.z), tonumber(data.heading) or 0.0
    if not x or not y or not z then return cb(false) end
    local ok = exports['rsg-gizmo']:IsPlacementValid(src, vector3(x, y, z), MB.PlaceDistance or 6.0)
    if not ok then return cb(false) end
    heading = heading % 360.0

    local Player = RSGCore.Functions.GetPlayer(src)
    local id = MySQL.insert.await('INSERT INTO rsg_telegram_mailboxes (x, y, z, heading, created_by) VALUES (?, ?, ?, ?, ?)',
        { x, y, z, heading, Player.PlayerData.citizenid })
    if not id then return cb(false) end

    local mb = { id = id, x = x + 0.0, y = y + 0.0, z = z + 0.0, heading = heading + 0.0 }
    TelegramMailboxes[id] = mb
    TriggerClientEvent('rsg-telegram:client:mailboxAdded', -1, view(mb))
    cb(true)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:removeMailbox', function(source, cb, id)
    local src = source
    if not enabled() or not I.validId(id) or not RSGCore.Functions.GetPlayer(src) or slow(src) then return cb(false) end
    local mb = TelegramMailboxes[id]
    if not mb or not isAdmin(src) then return cb(false) end
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(mb.x, mb.y, mb.z)) > (MB.Distance or 2.0) + 4.0 then return cb(false) end

    MySQL.update.await('DELETE FROM rsg_telegram_mailboxes WHERE id = ?', { id })
    TelegramMailboxes[id] = nil
    TriggerClientEvent('rsg-telegram:client:mailboxRemoved', -1, id)
    cb(true)
end)

AddEventHandler('playerDropped', function() lastAdminAction[source] = nil end)

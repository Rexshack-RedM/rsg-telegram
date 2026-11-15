local RSGCore = exports['rsg-core']:GetCoreObject()

local blips = {}
local promptGroup = GetRandomIntInRange(0, 0xffffff)
local openPrompt
local isOpen, isOpening = false, false  -- isOpen also means "the UI has NUI focus"
local openOffice                        -- office the UI was opened at
local sentLocales = false
local CLOSE_RANGE = Config.PromptDistance + 2.0 -- the server rejects actions beyond PromptDistance + 3.0

---------------------------------
-- prompt + blips
---------------------------------
CreateThread(function()
    openPrompt = PromptRegisterBegin()
    PromptSetControlAction(openPrompt, Config.PromptKey)
    PromptSetText(openPrompt, CreateVarString(10, 'LITERAL_STRING', locale('cl_prompt_open')))
    PromptSetEnabled(openPrompt, true)
    PromptSetVisible(openPrompt, true)
    PromptSetStandardMode(openPrompt, true)
    PromptSetGroup(openPrompt, promptGroup)
    PromptRegisterEnd(openPrompt)

    for _, office in ipairs(Config.PostOffices) do
        if office.showblip then
            local blip = BlipAddForCoords(Config.Blip.style, office.coords.x, office.coords.y, office.coords.z)
            SetBlipSprite(blip, Config.Blip.sprite, true)
            SetBlipScale(blip, 0.2)
            SetBlipName(blip, locale('cl_blip_name'))
            blips[#blips + 1] = blip
        end
    end
end)

---------------------------------
-- NUI focus (keeps push-to-talk working while the UI is open)
---------------------------------
local function applyNuiFocus(enable)
    if enable then
        SetNuiFocus(true, true)
        if Config.AllowPushToTalkWhileOpen then SetNuiFocusKeepInput(true) end
    else
        SetNuiFocusKeepInput(false)
        SetNuiFocus(false, false)
    end
end

-- KeepInput passes every key to the game, so block all controls except push-to-talk
local function runPttWhitelist()
    DisableAllControlActions(0)
    DisableAllControlActions(1)
    DisableAllControlActions(2)
    local list = Config.PushToTalkControls
    if list then
        for i = 1, #list do
            local c = list[i]
            EnableControlAction(0, c, true)
            EnableControlAction(1, c, true)
            EnableControlAction(2, c, true)
        end
    end
end

CreateThread(function()
    while true do
        if isOpen and Config.AllowPushToTalkWhileOpen then
            Wait(0)
            runPttWhitelist()
        else
            Wait(250)
        end
    end
end)

---------------------------------
-- NUI
---------------------------------
local function closeTelegrams()
    local wasOpen = isOpen
    isOpen = false
    openOffice = nil
    applyNuiFocus(false)
    SendNUIMessage({ action = 'close' })
    if wasOpen then TriggerServerEvent('rsg-telegram:server:closed') end -- revokes a remote-open grant
end

-- job addresses the compose dialog offers (only label + job; the server re-checks the job against its own config)
local function jobOffices()
    local list = {}
    for _, o in ipairs(Config.JobAddresses or {}) do
        if o.job and o.label then list[#list + 1] = { job = o.job, label = o.label } end
    end
    return list
end

local function attachmentSummary()
    local at = Config.Attachments
    if not at or not at.Enabled then return { enabled = false } end
    return { enabled = true, fee = at.Fee, maxCash = at.MaxCash, maxItems = at.MaxItems, maxItemAmount = at.MaxItemAmount }
end

local function openTelegrams(office)
    if isOpen or isOpening then return end
    isOpening = true
    local inbox = RSGCore.Functions.AwaitCallback('rsg-telegram:server:getInbox', 5000)
    isOpening = false
    if type(inbox) ~= 'table' then return end
    isOpen = true
    openOffice = office
    applyNuiFocus(true)
    SendNUIMessage({
        action = 'open',
        office = office.name,
        inbox = inbox,
        cost = Config.SendCost,
        offices = jobOffices(),
        attachments = attachmentSummary(),
        receipts = Config.Receipts and Config.Receipts.Enabled ~= false,
        maxSubject = Config.MaxSubject,
        maxMessage = Config.MaxMessage,
        minSearch = Config.SearchMinChars,
        locales = not sentLocales and locale() or nil,
    })
    sentLocales = true
end

local function nuiCallback(name, event, build)
    RegisterNUICallback(name, function(data, cb)
        if not isOpen then return cb(false) end
        local result = RSGCore.Functions.AwaitCallback(event, 5000, build and build(data or {}))
        if result == nil then result = false end
        cb(result)
    end)
end

RegisterNUICallback('close', function(_, cb)
    closeTelegrams()
    cb('ok')
end)

RegisterNUICallback('read', function(data, cb)
    local id = math.tointeger(tonumber(data and data.id))
    if id and isOpen then TriggerServerEvent('rsg-telegram:server:markRead', id) end
    cb('ok')
end)

nuiCallback('refresh',       'rsg-telegram:server:getInbox')
nuiCallback('getSent',       'rsg-telegram:server:getSent')
nuiCallback('markAllRead',   'rsg-telegram:server:markAllRead')
nuiCallback('deleteRead',    'rsg-telegram:server:deleteRead')
nuiCallback('collect',       'rsg-telegram:server:collect',          function(d) return math.tointeger(tonumber(d.id)) end)
nuiCallback('getBlocked',    'rsg-telegram:server:getBlocked')
nuiCallback('block',         'rsg-telegram:server:block',            function(d) return d.citizenid end)
nuiCallback('unblock',       'rsg-telegram:server:unblock',          function(d) return d.citizenid end)
nuiCallback('getAttachables','rsg-telegram:server:getAttachables')
nuiCallback('getContacts',   'rsg-telegram:server:getContacts')
nuiCallback('search',        'rsg-telegram:server:searchRecipients', function(d) return d.query end)
nuiCallback('removeContact', 'rsg-telegram:server:removeContact',    function(d) return d.citizenid end)
nuiCallback('delete',        'rsg-telegram:server:delete',           function(d) return math.tointeger(tonumber(d.id)) end)
nuiCallback('send',          'rsg-telegram:server:send',             function(d)
    return { citizenid = d.citizenid, job = d.job, subject = d.subject, message = d.message, attachment = d.attachment }
end)
nuiCallback('addContact',    'rsg-telegram:server:addContact',       function(d)
    return { citizenid = d.citizenid, nickname = d.nickname }
end)

---------------------------------
-- proximity loop
---------------------------------
CreateThread(function()
    local maxDist = Config.PromptDistance
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        if not isOpen then
            if openPrompt then
                local pos = GetEntityCoords(ped)
                local dead = IsEntityDead(ped)
                for _, office in ipairs(Config.PostOffices) do
                    local dist = #(pos - office.coords)
                    if dist <= maxDist and not dead then
                        sleep = 0
                        -- the title string must be created fresh every frame: a cached CreateVarString pointer becomes invalid and shows garbage
                        PromptSetActiveGroupThisFrame(promptGroup, CreateVarString(10, 'LITERAL_STRING', office.name), 1, 0, 0, 0)
                        if PromptHasStandardModeCompleted(openPrompt) then
                            openTelegrams(office)
                        end
                        break
                    elseif dist < 30.0 then
                        sleep = 250
                    end
                end
            end
        else
            -- close the UI if the player dies or is moved away from the post office while it is open
            sleep = 500
            if IsEntityDead(ped) or (openOffice and openOffice.coords and #(GetEntityCoords(ped) - openOffice.coords) > (openOffice.range or CLOSE_RANGE)) then
                closeTelegrams()
            end
        end
        Wait(sleep)
    end
end)

---------------------------------
-- opened remotely by another script (server export OpenTelegrams)
---------------------------------
RegisterNetEvent('rsg-telegram:client:open', function(label, coords, radius)
    if GetInvokingResource() then return end -- only the server may trigger this
    local c = type(coords) == 'table' and coords.x and vector3(coords.x, coords.y, coords.z) or nil
    openTelegrams({
        name = (type(label) == 'string' and label ~= '') and label or locale('cl_blip_name'),
        coords = c,
        range = c and (tonumber(radius) or CLOSE_RANGE) or nil,
    })
end)

---------------------------------
-- incoming telegram
---------------------------------
RegisterNetEvent('rsg-telegram:client:newTelegram', function(senderName)
    RSGCore.Functions.Notify({
        title = locale('cl_title'),
        description = locale('cl_new_telegram', senderName or locale('sv_unknown')),
        type = 'inform',
        icon = 'fa-solid fa-envelope',
        position = 'top-right',
        duration = 7000,
    })
end)

---------------------------------
-- exports
---------------------------------
exports('IsOpen', function() return isOpen end)
exports('Close', function() if isOpen then closeTelegrams() end end)

---------------------------------
-- cleanup
---------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in ipairs(blips) do RemoveBlip(b) end
    if openPrompt then PromptDelete(openPrompt) end
    if isOpen then applyNuiFocus(false) end
end)

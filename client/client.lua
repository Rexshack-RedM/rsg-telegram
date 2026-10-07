lib.locale()

local blips = {}
local promptGroup = GetRandomIntInRange(0, 0xffffff)
local openPrompt
local isOpen, isOpening = false, false
local sentLocales = false

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
        office.label = CreateVarString(10, 'LITERAL_STRING', office.name)
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
-- NUI
---------------------------------
local function closeTelegrams()
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openTelegrams(officeName)
    if isOpen or isOpening then return end
    isOpening = true
    local inbox = lib.callback.await('rsg-telegram:server:getInbox', false)
    isOpening = false
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        office = officeName,
        inbox = inbox,
        cost = Config.SendCost,
        maxSubject = Config.MaxSubject,
        maxMessage = Config.MaxMessage,
        minSearch = Config.SearchMinChars,
        locales = not sentLocales and lib.getLocales() or nil,
    })
    sentLocales = true
end

local function nuiCallback(name, event, build)
    RegisterNUICallback(name, function(data, cb)
        cb(lib.callback.await(event, false, build and build(data or {})))
    end)
end

RegisterNUICallback('close', function(_, cb)
    closeTelegrams()
    cb('ok')
end)

RegisterNUICallback('read', function(data, cb)
    local id = math.tointeger(tonumber(data and data.id))
    if id then TriggerServerEvent('rsg-telegram:server:markRead', id) end
    cb('ok')
end)

nuiCallback('refresh',       'rsg-telegram:server:getInbox')
nuiCallback('getContacts',   'rsg-telegram:server:getContacts')
nuiCallback('search',        'rsg-telegram:server:searchRecipients', function(d) return d.query end)
nuiCallback('removeContact', 'rsg-telegram:server:removeContact',    function(d) return d.citizenid end)
nuiCallback('delete',        'rsg-telegram:server:delete',           function(d) return math.tointeger(tonumber(d.id)) end)
nuiCallback('send',          'rsg-telegram:server:send',             function(d)
    return { citizenid = d.citizenid, subject = d.subject, message = d.message }
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
        if not isOpen and openPrompt then
            local pos = GetEntityCoords(cache.ped)
            for _, office in ipairs(Config.PostOffices) do
                local dist = #(pos - office.coords)
                if dist <= maxDist then
                    sleep = 0
                    PromptSetActiveGroupThisFrame(promptGroup, office.label)
                    if PromptHasStandardModeCompleted(openPrompt) then
                        openTelegrams(office.name)
                    end
                    break
                elseif dist < 30.0 then
                    sleep = 250
                end
            end
        elseif isOpen then
            -- close the UI if the player dies while it is open
            sleep = 500
            if IsEntityDead(cache.ped) then closeTelegrams() end
        end
        Wait(sleep)
    end
end)

---------------------------------
-- incoming telegram
---------------------------------
RegisterNetEvent('rsg-telegram:client:newTelegram', function(senderName)
    lib.notify({
        title = locale('cl_title'),
        description = locale('cl_new_telegram', senderName or locale('sv_unknown')),
        type = 'inform',
        icon = 'envelope',
        position = 'top-right',
        duration = 7000,
    })
end)

---------------------------------
-- cleanup
---------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in ipairs(blips) do RemoveBlip(b) end
    if openPrompt then PromptDelete(openPrompt) end
    if isOpen then SetNuiFocus(false, false) end
end)

local RSGCore = exports['rsg-core']:GetCoreObject()

local cuteBird = nil
local birdPrompt = nil
local letterPromptGroup = GetRandomIntInRange(0, 0xffffff)
local birdBlip = nil
local targetPed = nil
local targetCoords = nil
local playerCoords = nil
local notified = false
local destination = nil
local howFar = 0
local senderID = nil
local sID = nil
local tPName = nil
local isReceiving = false
local buildingNotified = false
local isBirdCanSpawn = false
local isBirdAlreadySpawned = false
local birdTime = Config.BirdTimeout
local blipEntries = {}

exports('IsBirdPostApproaching', function()
    return isReceiving
end)

-- Bird Prompt
local BirdPrompt = function()
    Citizen.CreateThread(function()
        birdPrompt = Citizen.InvokeNative(0x04F97DE45A519419)
        PromptSetControlAction(birdPrompt, RSGCore.Shared.Keybinds['ENTER'])
        local str = CreateVarString(10, 'LITERAL_STRING', Lang:t("desc.prompt_button"))
        PromptSetText(birdPrompt, str)
        PromptSetEnabled(birdPrompt, true)
        PromptSetVisible(birdPrompt, true)
        PromptSetHoldMode(birdPrompt, true)
        PromptSetGroup(birdPrompt, letterPromptGroup)
        PromptRegisterEnd(birdPrompt)
    end)
end

-- Prompts
Citizen.CreateThread(function()
    for i = 1, #Config.PostOfficeLocations do
        local pos = Config.PostOfficeLocations[i]

        exports['rsg-core']:createPrompt(pos.location, pos.coords, RSGCore.Shared.Keybinds['J'], 'Open ' .. pos.name, {
            type = 'client',
            event = 'rsg-telegram:client:TelegramMenu'
        })

        if pos.showblip == true then
            PostOfficeBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, pos.coords)
            SetBlipSprite(PostOfficeBlip, GetHashKey(Config.Blip.blipSprite), true)
            SetBlipScale(PostOfficeBlip, Config.Blip.blipScale)
            Citizen.InvokeNative(0x9CB1A1623062F402, PostOfficeBlip, pos.name)

            blipEntries[#blipEntries + 1] = { type = "BLIP", handle = PostOfficeBlip }
        end
    end
end)

-- Telegram Menu
RegisterNetEvent('rsg-telegram:client:TelegramMenu', function(data)
    exports['rsg-menu']:openMenu({
        {
            header = "| Telegram Menu |",
            isMenuHeader = true,
            icon   = 'fa-solid fa-envelope-open-text',
        },
        {
            header = "📥 | Read Messages",
            txt = "read your telegram messages",
            params = {
                event = 'rsg-telegram:client:ReadMessages',
                isServer = false
            }
        },
        {
            header = "📤 | Send Telegram",
            txt = "send a telegram to another player",
            params = {
                event = 'rsg-telegram:client:WriteMessagePostOffice',
                isServer = false
            }
        },
        {
            header = "Close Menu",
            txt = '',
            icon   = 'fa-solid fa-circle-xmark',
            params = {
                event = 'rsg-menu:closeMenu',
            }
        },
    })
end)

-- Write Message
RegisterNetEvent('rsg-telegram:client:WriteMessagePostOffice', function()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:GetPlayersPostOffice', function(players)
        local option = {}

        for i = 1, #players do
            local citizenid = players[i].citizenid
            local firstname = json.decode(players[i].charinfo).firstname
            local lastname = json.decode(players[i].charinfo).lastname
            local fullname = firstname..' '..lastname
            local content = {value = citizenid, text = '('..citizenid..') '..fullname}

            option[#option + 1] = content
        end

        local sendButton = Lang:t("desc.send_button_free")

        if Config.ChargePlayer then
            sendButton = Lang:t("desc.send_button_paid", {lPrice = tonumber(Config.CostPerLetter)})
        end

        local input = exports['rsg-input']:ShowInput({
        header = Lang:t('desc.send_message_header'),
        submitText = sendButton,
            inputs = {
                {
                    text = "Recipient",
                    name = "recipient",
                    type = "select",
                    options = option
                },
                {
                    type = 'text',
                    name = 'subject',
                    text = 'subject',
                    isRequired = true,
                },
                {
                    type = 'text',
                    name = 'message',
                    text = 'add your message here',
                    isRequired = true,
                },
            }
        })

        if input ~= nil then
            local pID =  PlayerId()
            senderID = GetPlayerServerId(pID)
            local senderfirstname = RSGCore.Functions.GetPlayerData().charinfo.firstname
            local senderlastname = RSGCore.Functions.GetPlayerData().charinfo.lastname
            local sendertelegram = RSGCore.Functions.GetPlayerData().citizenid
            local senderfullname = senderfirstname..' '..senderlastname
            TriggerServerEvent('rsg-telegram:server:SendMessagePostOffice', sendertelegram, senderfullname, input.recipient, input.subject, input.message)
        end
    end)
end)

-- Prompt Handling
local function Prompts()
    if not PromptHasHoldModeCompleted(birdPrompt) then return end

    local ped = PlayerPedId()

    if destination < 3 and IsPedOnMount(ped) or IsPedOnVehicle(ped) then
        RSGCore.Functions.Notify(Lang:t("error.player_on_horse"), 'error')

        Wait(3000)
        return
    end

    TriggerEvent("rsg-telegram:client:ReadMessages")

    TriggerServerEvent('rsg-telegram:server:DeliverySuccess', sID, tPName)

    Wait(1000)

    TaskFlyToCoord(cuteBird, 0, playerCoords.x - 100, playerCoords.y - 100, playerCoords.z + 50, 1, 0)

    if birdBlip ~= nil then
        RemoveBlip(birdBlip)
    end

    isReceiving = false
    isBirdAlreadySpawned = false
    notified = false

    Wait(10000)

    SetEntityInvincible(cuteBird, false)
    SetEntityCanBeDamaged(cuteBird, true)
    SetEntityAsMissionEntity(cuteBird, false, false)
    SetEntityAsNoLongerNeeded(cuteBird)
    DeleteEntity(cuteBird)
end

-- Place Ped on Ground Properly
local PlacePedOnGroundProperly = function(hPed, howfar)
    local playerPed = PlayerPedId()
    howFar = howfar
    local x, y, z = table.unpack(GetEntityCoords(playerPed))
    local found, groundz, normal = GetGroundZAndNormalFor_3dCoord(x - howFar, y, z)

    if found then
        SetEntityCoordsNoOffset(hPed, x - howFar, y, groundz + normal.z + howFar, true)
    end
end

-- Spawn the Bird Post
local SpawnBirdPost = function(posX, posY, posZ, heading, rfar, x)
    cuteBird = CreatePed(Config.BirdModel, posX, posY, posZ, heading, 1, 1)

    Citizen.InvokeNative(0x013A7BA5015C1372, cuteBird, true) -- SetPedIgnoreDeadBodies
    Citizen.InvokeNative(0xAEB97D84CDF3C00B, cuteBird, false) -- SetAnimalIsWild

    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(cuteBird), GetHashKey('PLAYER'))

    PlacePedOnGroundProperly(cuteBird, rfar)

    Wait(2000)

    Citizen.InvokeNative(0x283978A15512B2FE, cuteBird, true) -- SetRandomOutfitVariation
    ClearPedTasks(cuteBird)
    ClearPedSecondaryTask(cuteBird)
    ClearPedTasksImmediately(cuteBird)
    SetPedFleeAttributes(cuteBird, 0, 0)
    TaskWanderStandard(cuteBird, 0, 0)
    TaskSetBlockingOfNonTemporaryEvents(cuteBird, 1)
    SetEntityAsMissionEntity(cuteBird, true, true)
    Citizen.InvokeNative(0xA5C38736C426FCB8, cuteBird, true) -- SetEntityInvincible

    Wait(2000)

    if x == 0 then
        local blipname = Lang:t("desc.blip_name")
        local bliphash = -1749618580

        Debug("bliphash", bliphash)

        birdBlip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, bliphash, cuteBird) -- BlipAddForEntity
        Citizen.InvokeNative(0x9CB1A1623062F402, birdBlip, blipname) -- SetBlipName
        -- Citizen.InvokeNative(0x931B241409216C1F, targetPed, cuteBird, true) -- SetPedOwnsAnimal
        Citizen.InvokeNative(0x0DF2B55F717DDB10, birdBlip) -- SetBlipFlashes
        Citizen.InvokeNative(0x662D364ABF16DE2F, birdBlip, GetHashKey("BLIP_MODIFIER_DEBUG_BLUE")) -- BlipAddModifier
        SetBlipScale(birdBlip, 2.0)
    end
end

-- Prompt Thread
CreateThread(function()
    BirdPrompt()

    while true do
        Wait(1)

        if notified and destination < 3 then
            local Bird = CreateVarString(10, "LITERAL_STRING", "~pa~"..Lang:t("desc.prompt_desc").."~q~")
            PromptSetActiveGroupThisFrame(letterPromptGroup, Bird)

            if PromptHasHoldModeCompleted(birdPrompt) then
                Prompts()
            end
        end
    end
end)

-- Receive Message
RegisterNetEvent('rsg-telegram:client:ReceiveMessage')
AddEventHandler('rsg-telegram:client:ReceiveMessage', function(SsID, StPName)
    isReceiving = true
    sID = SsID
    tPName = StPName
    local ped = PlayerPedId()
    playerCoords = GetEntityCoords(ped)
    local rFar = math.random(50, 100)

    while isReceiving do
        Wait(1)
        local CurrentCoords = GetEntityCoords(ped)
        local birdCoords = GetEntityCoords(cuteBird)
        local myCoords = vector3(CurrentCoords.x, CurrentCoords.y, CurrentCoords.z)
        destination = #(birdCoords - myCoords)

        local insideBuilding = GetInteriorFromEntity(ped)

        isBirdCanSpawn = true

        if insideBuilding ~= 0 then
            if not buildingNotified then
                RSGCore.Functions.Notify(Lang:t("info.inside_building"), 'error')
                buildingNotified = true
            end

            isBirdCanSpawn = false

            goto continue
        end

        if isBirdCanSpawn and not isBirdAlreadySpawned then
            SpawnBirdPost(playerCoords.x - 100, playerCoords.y - 100, playerCoords.z + 100, 92.0, rFar, 0)
            TaskFlyToCoord(cuteBird, 0, playerCoords.x - 1, playerCoords.y - 1, playerCoords.z, 1, 0)
            isBirdCanSpawn = false
            isBirdAlreadySpawned = true
        end

        if destination < 100 and not notified then
            notified = true
            RSGCore.Functions.Notify(Lang:t("info.bird_approaching"), 'primary', 3000)
            Wait(5000)
            RSGCore.Functions.Notify(Lang:t("info.wait_for_bird"), 'primary', 3000)
        end

        local IsPedAir = IsEntityInAir(cuteBird, 1)
        local isBirdDead = Citizen.InvokeNative(0x7D5B1F88E7504BBA, cuteBird) -- IsEntityDead

        BirdCoords = GetEntityCoords(cuteBird)

        Debug("cuteBird", cuteBird)
        Debug("IsPedAir", IsPedAir)
        Debug("notified", notified)
        Debug("destination", destination)

        if cuteBird ~= nil and not IsPedAir and notified and destination > 3 then
            if Config.AutoResurrect and isBirdDead then
                Debug("isBirdDead", isBirdDead)

                ClearPedTasksImmediately(cuteBird)

                SetEntityCoords(cuteBird, BirdCoords.x, BirdCoords.y, BirdCoords.z)
                Wait(1000)
                Citizen.InvokeNative(0x71BC8E838B9C6035, cuteBird) -- ResurrectPed
                Wait(1000)
            end

            TaskFlyToCoord(cuteBird, 0, CurrentCoords.x - 1, CurrentCoords.y - 1, CurrentCoords.z, 1, 0)
        end

        if birdTime > 0 then
            birdTime = birdTime - 1
            Wait(1000)
        end

        if birdTime == 0 and cuteBird ~= nil and notified then
            RSGCore.Functions.Notify(Lang:t("error.delivery_fail1"), 'error', 5000)
            Wait(8000)
            RSGCore.Functions.Notify(Lang:t("error.delivery_fail2"), 'error', 5000)
            Wait(8000)
            RSGCore.Functions.Notify(Lang:t("error.delivery_fail3"), 'error', 5000)

            SetEntityInvincible(cuteBird, false)
            SetEntityAsMissionEntity(cuteBird, false, false)
            SetEntityAsNoLongerNeeded(cuteBird)
            DeleteEntity(cuteBird)
            RemoveBlip(birdBlip)

            notified = false
            isReceiving = false

            return
        end

        ::continue::
    end
end)

-- Write the Message
RegisterNetEvent('rsg-telegram:client:WriteMessage', function()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:GetPlayers', function(players)
        local citizenid = 0
        local name = 0
        local sourceplayer = 0
        local option = {}

        if isReceiving then
            RSGCore.Functions.Notify(Lang:t("error.send_receiving"), 'error', 8000)
            return
        end

        local ped = PlayerPedId()
        local pID =  PlayerId()
        senderID = GetPlayerServerId(pID)

        if IsPedOnMount(ped) or IsPedOnVehicle(ped) then
            RSGCore.Functions.Notify(Lang:t("error.player_on_horse"), 'error')
            return
        end

        ClearPedTasks(ped)
        ClearPedSecondaryTask(ped)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)

        playerCoords = GetEntityCoords(ped)
        targetCoords = GetEntityCoords(targetPed)
        local coordsOffset = math.random(200, 300)

        local heading = GetEntityHeading(ped)
        local rFar = 30

        TaskWhistleAnim(ped, GetHashKey('WHISTLEHORSELONG'))

        SpawnBirdPost(playerCoords.x, playerCoords.y, playerCoords.z + 50, heading, rFar, 1)

        if cuteBird == nil then
            RSGCore.Functions.Notify('The bird got away!', 'error')
        end

        TaskFlyToCoord(cuteBird, 0, playerCoords.x, playerCoords.y, playerCoords.z, 1, 0)

        TaskStartScenarioInPlace(PlayerPedId(), GetHashKey('WORLD_HUMAN_WRITE_NOTEBOOK'), -1, true, false, false, false)
        Wait(5000)

        local sendButton = Lang:t("desc.send_button_free")

        if Config.ChargePlayer then
            sendButton = Lang:t("desc.send_button_paid", {lPrice = tonumber(Config.CostPerLetter)})
        end

        for i = 1, #players do
            local targetPlayer = players[i]

            sourceplayer = targetPlayer.sourceplayer
            citizenid = targetPlayer.citizenid
            name = targetPlayer.name
            local content = {value = sourceplayer, text = '('..citizenid..') '..name}

            option[#option + 1] = content
        end

        local input = exports['rsg-input']:ShowInput
        ({
            header = Lang:t('desc.send_message_header'),
            submitText = sendButton,
            inputs =
            {
                --[[
                {
                    type = 'select',
                    name = 'recipient',
                    text = Lang:t('desc.recipient'),
                    isRequired = true
                },
                ]]--
                {
                    text = Lang:t('desc.recipient'),
                    name = "recipient",
                    type = "select",
                    options = option
                },
                {
                    type = 'text',
                    name = 'subject',
                    text = Lang:t('desc.subject'),
                    isRequired = true
                },
                {
                    type = 'text',
                    name = 'message',
                    text = Lang:t('desc.message'),
                    isRequired = true
                }
            }
        })

        if input == nil then
            FreezeEntityPosition(PlayerPedId(), false)
            SetEntityInvincible(PlayerPedId(), false)
            ClearPedTasks(PlayerPedId())
            ClearPedSecondaryTask(PlayerPedId())

            SetEntityInvincible(cuteBird, false)
            SetEntityCanBeDamaged(cuteBird, true)
            SetEntityAsMissionEntity(cuteBird, false, false)
            SetEntityAsNoLongerNeeded(cuteBird)
            DeleteEntity(cuteBird)

            if birdBlip ~= nil then
                RemoveBlip(birdBlip)
            end

            RSGCore.Functions.Notify(Lang:t('error.cancel_send'), 'error')

            return
        end

        Debug("input.recipient", input.recipient)
        Debug("input.subject", input.subject)
        Debug("input.message", input.message)

        local senderfirstname = RSGCore.Functions.GetPlayerData().charinfo.firstname
        local senderlastname = RSGCore.Functions.GetPlayerData().charinfo.lastname
        local sendertelegram = RSGCore.Functions.GetPlayerData().citizenid
        local senderfullname = senderfirstname..' '..senderlastname

        Debug("sendertelegram:", sendertelegram)
        Debug("senderfullname:", senderfullname)
        Debug("input.recipient:", input.recipient)
        Debug("input.subject:", input.subject)
        Debug("input.message:", input.message)

        Debug("targetPed:", targetPed)

        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, false)
        ClearPedTasks(ped)
        ClearPedSecondaryTask(ped)

        Wait(3000)

        TaskFlyToCoord(cuteBird, 0, targetCoords.x - coordsOffset, targetCoords.y - coordsOffset, targetCoords.z + 75, 1, 0)

        Wait(Config.BirdArrivalDelay)

        SetEntityInvincible(cuteBird, false)
        SetEntityCanBeDamaged(cuteBird, true)
        SetEntityAsMissionEntity(cuteBird, false, false)
        SetEntityAsNoLongerNeeded(cuteBird)
        DeleteEntity(cuteBird)
        RemoveBlip(birdBlip)

        TriggerServerEvent('rsg-telegram:server:SendMessage', senderID, sendertelegram, senderfullname, input.recipient, Lang:t('desc.message_prefix')..': '..input.subject, input.message)
    end)
end)

-- Read the Message
RegisterNetEvent('rsg-telegram:client:ReadMessages')
AddEventHandler('rsg-telegram:client:ReadMessages', function()
    InMenu = true
    SetNuiFocus(true, true)

    SendNUIMessage
    ({
        type = 'openGeneral'
    })

    TriggerServerEvent('rsg-telegram:server:CheckInbox')
end)

-- Show Messages List
RegisterNetEvent('rsg-telegram:client:InboxList')
AddEventHandler('rsg-telegram:client:InboxList', function(data)
    SendNUIMessage
    ({
        type = 'inboxlist', response = data
    })
end)

-- Get the Message
RegisterNUICallback('getview', function(data)
    TriggerServerEvent('rsg-telegram:server:GetMessages', tonumber(data.id))
end)

-- Message Data
RegisterNetEvent('rsg-telegram:client:MessageData')
AddEventHandler('rsg-telegram:client:MessageData', function(tele)
    SendNUIMessage
    ({
        type = 'view',
        telegram = tele
    })
end)

-- Delete Message
RegisterNUICallback('delete', function(data)
    TriggerServerEvent('rsg-telegram:server:DeleteMessage', tonumber(data.id))
end)

-- Close Mailbox
RegisterNUICallback('NUIFocusOff', function()
    InMenu = false
    SetNuiFocus(false, false)

    SendNUIMessage
    ({
        type = 'closeAll'
    })
end)

-- Cleanup
AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    if birdBlip ~= nil then
        RemoveBlip(birdBlip)
    end

    SetEntityAsMissionEntity(cuteBird, false)
    FreezeEntityPosition(cuteBird, false)
    DeleteEntity(cuteBird)
    PromptDelete(birdPrompt)

    for i = 1, #Config.PostOfficeLocations do
        local pos = Config.PostOfficeLocations[i]

        exports['rsg-core']:deletePrompt(pos.location)
    end

    for i = 1, #blipEntries do
        if blipEntries[i].type == "BLIP" then
            RemoveBlip(blipEntries[i].handle)
        end
    end
end)
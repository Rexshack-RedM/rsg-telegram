local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

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
local buildingNotified = false
local isBirdCanSpawn = false
local isBirdAlreadySpawned = false
local birdTime = Config.BirdTimeout
local blipEntries = {}
local isAtPostOffice = false

-- Check if player is at post office
local function IsPlayerAtPostOffice()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    for _, location in pairs(Config.PostOfficeLocations) do
        local distance = #(playerCoords - location.coords)
        if distance < 5.0 then -- Within 5 units of post office
            return true
        end
    end
    
    return false
end

---@deprecated use state LocalPlayer.state.telegramIsBirdPostApproaching
exports('IsBirdPostApproaching', function()
    return LocalPlayer.state.telegramIsBirdPostApproaching
end)

CreateThread(function() 
    LocalPlayer.state.telegramIsBirdPostApproaching = false
    repeat Wait(100) until LocalPlayer.state.isLoggedIn

    RSGCore.Functions.TriggerCallback('rsg-telegram:server:getTelegramsAmount', function(amount)
        LocalPlayer.state:set('telegramUnreadMessages', amount or 0, true)
    end)
end)

-- Bird Prompt
local BirdPrompt = function()
    Citizen.CreateThread(function()
        birdPrompt = Citizen.InvokeNative(0x04F97DE45A519419)
        PromptSetControlAction(birdPrompt, RSGCore.Shared.Keybinds['ENTER'])
        local str = CreateVarString(10, 'LITERAL_STRING', locale("cl_prompt_button"))
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

        -- Prompt to open telegram
        exports['rsg-core']:createPrompt(pos.location, pos.coords, RSGCore.Shared.Keybinds['J'], locale("cl_prompt") ..' '.. pos.name, {
            type = 'client',
            event = 'rsg-telegram:client:OpenTelegram'
        })
        
        -- Prompt to pick up waiting messages
        exports['rsg-core']:createPrompt(pos.location .. '_pickup', pos.coords, RSGCore.Shared.Keybinds['G'], 'Pick Up Telegrams', {
            type = 'client',
            event = 'rsg-telegram:client:PickupMessages'
        })

        if pos.showblip == true then
            PostOfficeBlip = BlipAddForCoords(1664425300, pos.coords)
            SetBlipSprite(PostOfficeBlip, joaat(pos.blipsprite), true)
            SetBlipScale(PostOfficeBlip, pos.blipscale)
            SetBlipName(PostOfficeBlip, pos.name)

            blipEntries[#blipEntries + 1] = { type = "BLIP", handle = PostOfficeBlip }
        end
    end
end)

-- Open Telegram UI
RegisterNetEvent('rsg-telegram:client:OpenTelegram', function()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openUI'
    })
end)

-- Pick up messages from post office
RegisterNetEvent('rsg-telegram:client:PickupMessages', function()
    -- Check if player is at post office
    if not IsPlayerAtPostOffice() then
        lib.notify({
            title = locale("cl_title_11"),
            description = 'You must be at a Post Office to pick up telegrams.',
            type = 'error',
            duration = 5000
        })
        return
    end
    
    -- Check for waiting messages
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:checkWaitingMessages', function(count)
        if count > 0 then
            -- Show confirmation with count
            lib.notify({
                title = 'Post Office',
                description = 'You have ' .. count .. ' telegram(s) waiting. Picking up...',
                type = 'info',
                duration = 5000
            })
            
            -- Pick up messages
            TriggerServerEvent('rsg-telegram:server:pickupMessages')
        else
            lib.notify({
                title = locale("cl_title_11"),
                description = 'No telegrams waiting for pickup.',
                type = 'info',
                duration = 5000
            })
        end
    end)
end)

-- Prompt Handling
local function Prompts()
    if not PromptHasHoldModeCompleted(birdPrompt) then return end

    local ped = PlayerPedId()

    if destination < Config.BirdPromptDistance and IsPedOnMount(ped) or IsPedOnVehicle(ped) then
        lib.notify({ title = locale("title_11"), description = locale('cl_player_on_horse'), type = 'error', duration = 7000 })

        Wait(3000)
        return
    end

    TriggerEvent("rsg-telegram:client:OpenTelegram")

    TriggerServerEvent('rsg-telegram:server:DeliverySuccess', sID, tPName)

    Wait(1000)

    TaskFlyToCoord(cuteBird, 0, playerCoords.x - 100, playerCoords.y - 100, playerCoords.z + 50, 1, 0)

    if birdBlip ~= nil then
        RemoveBlip(birdBlip)
    end

    LocalPlayer.state.telegramIsBirdPostApproaching = false
    isBirdAlreadySpawned = false
    notified = false

    Wait(10000)

    SetEntityInvincible(cuteBird, false)
    SetEntityCanBeDamaged(cuteBird, true)
    SetEntityAsMissionEntity(cuteBird, false, false)
    SetEntityAsNoLongerNeeded(cuteBird)
    DeleteEntity(cuteBird)
end

-- Set Bird Attribute
local SetPetAttributes = function(entity)
    -- SET_ATTRIBUTE_POINTS
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 0, 1100)
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 1, 1100)
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 2, 1100)

    -- ADD_ATTRIBUTE_POINTS
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 0, 1100)
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 1, 1100)
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 2, 1100)

    -- SET_ATTRIBUTE_BASE_RANK
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 0, 10)
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 1, 10)
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 2, 10)

    -- SET_ATTRIBUTE_BONUS_RANK
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 0, 10)
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 1, 10)
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 2, 10)

    -- SET_ATTRIBUTE_OVERPOWER_AMOUNT
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 0, 5000.0, false)
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 1, 5000.0, false)
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 2, 5000.0, false)
end

local function SetPetBehavior(entity)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), GetHashKey('PLAYER'))
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 143493179)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -2040077242)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1222652248)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1077299173)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -887307738)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1998572072)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -661858713)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1232372459)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1836932466)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1878159675)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1078461828)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1535431934)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1862763509)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1663301869)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1448293989)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1201903818)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -886193798)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1996978098)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 555364152)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -2020052692)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 707888648)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 378397108)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -350651841)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1538724068)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1030835986)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1919885972)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1976316465)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 841021282)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 889541022)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1329647920)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -319516747)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -767591988)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -989642646)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), 1986610512)
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(entity), -1683752762)
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
    local birdHash = joaat(Config.BirdModel)
    cuteBird = CreatePed(birdHash, posX, posY, posZ, heading, true, true, false)

    SetPetAttributes(cuteBird)

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
        local blipname = locale("cl_blip_name")
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

        if notified and destination < Config.BirdPromptDistance then
            local Bird = CreateVarString(10, "LITERAL_STRING", locale("cl_prompt_desc"))
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
    LocalPlayer.state.telegramIsBirdPostApproaching = true
    sID = SsID
    tPName = StPName
    local ped = PlayerPedId()
    local rFar = math.random(50, 100)
    buildingNotified = false
    notified = false
    isBirdAlreadySpawned = false
    birdTime = Config.BirdDeliveryTimeout or 300

    while LocalPlayer.state.telegramIsBirdPostApproaching do
        Wait(1)
        playerCoords = GetEntityCoords(ped)
        local myCoords = vector3(playerCoords.x, playerCoords.y, playerCoords.z)
        local insideBuilding = GetInteriorFromEntity(ped)
        isBirdCanSpawn = true

        -- Check if player is inside building
        if insideBuilding ~= 0 then
            if not buildingNotified then
                lib.notify({ title = locale("cl_title_11"), description = locale('cl_inside_building'), type = 'error', duration = 7000 })
                buildingNotified = true
            end
            isBirdCanSpawn = false
            goto continue
        end

        -- Initial bird spawn
        if isBirdCanSpawn and not isBirdAlreadySpawned then
            SpawnBirdPost(playerCoords.x - Config.BirdSpawnDeliveryDistance,
            playerCoords.y - Config.BirdSpawnDeliveryDistance, playerCoords.z + 100,
            92.0, rFar, 0)
            if cuteBird then
                TaskFlyToCoord(cuteBird, 0, playerCoords.x, playerCoords.y, playerCoords.z + 0.8, 1, 0) -- Make bird fly closer to the player
                isBirdCanSpawn = false
                isBirdAlreadySpawned = true
            end
        end

        if cuteBird then
            local birdCoords = GetEntityCoords(cuteBird)
            destination = #(birdCoords - myCoords)

            -- Notify player of approaching bird
            if destination < 100 and not notified then
                notified = true
                lib.notify({ title = locale("cl_title_13"), description = locale('cl_bird_approaching'), type = 'info', duration = 7000 })
                Wait(5000)
                lib.notify({ title = locale("cl_title_13"), description = locale('cl_wait_for_bird'), type = 'info', duration = 7000 })
            end

            -- Freeze the player as the bird approaches (within configured meters)
            if destination <= Config.BirdFreezeDistance and not freezedPlayer then
                FreezeEntityPosition(ped, true)  -- Freeze player
                SetEntityInvincible(ped, true)  -- Make player invincible
                freezedPlayer = true
            end

            -- Bird landing and message delivery logic
            if destination <= Config.BirdDeliveryDistance then
                -- Prepare player for message
                ClearPedTasks(ped)
                ClearPedSecondaryTask(ped)
                FreezeEntityPosition(ped, false)  -- Keep player frozen
                SetEntityInvincible(ped, true)
                TaskStartScenarioInPlace(ped, GetHashKey('WORLD_HUMAN_WRITE_NOTEBOOK'), -1, true, false, false, false)
				SetEntityCollision(cuteBird, false, false)
                -- Attach bird to player once it's close enough
                local AttachConfig = Config.BirdAttach["A_C_Hawk_01"]
                local Attach = IsPedMale(PlayerPedId()) and AttachConfig.Male or AttachConfig.Female

                AttachEntityToEntity(
                    cuteBird,
                    PlayerPedId(),
                    Attach[1], -- Bone Index
                    Attach[2], -- xOffset
                    Attach[3], -- yOffset
                    Attach[4], -- zOffset
                    Attach[5], -- xRot
                    Attach[6], -- yRot
                    Attach[7], -- zRot
                    false, false, true, false, 0, true, false, false
                )

                -- Freeze bird in place and clear its tasks
                FreezeEntityPosition(cuteBird, true)
                ClearPedTasksImmediately(cuteBird)
                SetBlockingOfNonTemporaryEvents(cuteBird, true)

                -- Wait for message delivery to complete
                --Wait(10000)  -- Allow time for the player to read the message (optional)

                -- Detach and prepare bird for departure
                DetachEntity(cuteBird, true, true)
                SetEntityCollision(cuteBird, false, false)
                FreezeEntityPosition(cuteBird, false)
                SetEntityInvincible(cuteBird, false)

                Wait(100)

                -- Make bird fly away
                local coordsOffset = math.random(200, 300)
                TaskFlyToCoord(cuteBird, 0, playerCoords.x - coordsOffset, playerCoords.y - coordsOffset, playerCoords.z + 75, 1, 0)

                Wait(Config.BirdArrivalDelay)

                -- Cleanup bird
                SetEntityInvincible(cuteBird, false)
                SetEntityCanBeDamaged(cuteBird, true)
                SetEntityAsMissionEntity(cuteBird, false, false)
                SetEntityAsNoLongerNeeded(cuteBird)
                DeleteEntity(cuteBird)

                if birdBlip ~= nil then
                    RemoveBlip(birdBlip)
                end

                -- Reset player state
                FreezeEntityPosition(ped, false)
                SetEntityInvincible(ped, false)
                ClearPedTasks(ped)
                ClearPedSecondaryTask(ped)

                -- Trigger server event and end receiving state
                TriggerServerEvent('rsg-telegram:server:ReadMessage', sID)
                LocalPlayer.state.telegramIsBirdPostApproaching = false
                return
            end
        end

        -- Handle bird movement and resurrection
        local IsPedAir = IsEntityInAir(cuteBird, 1)
        local isBirdDead = Citizen.InvokeNative(0x7D5B1F88E7504BBA, cuteBird)
        BirdCoords = GetEntityCoords(cuteBird)

        Debug("cuteBird", cuteBird)
        Debug("IsPedAir", IsPedAir)
        Debug("notified", notified)
        Debug("destination", destination)

        if cuteBird ~= nil and not IsPedAir and notified and destination > Config.BirdPromptDistance then
            if Config.AutoResurrect and isBirdDead then
                Debug("isBirdDead", isBirdDead)
                ClearPedTasksImmediately(cuteBird)
                SetEntityCoords(cuteBird, BirdCoords.x, BirdCoords.y, BirdCoords.z)
                Wait(1000)
                Citizen.InvokeNative(0x71BC8E838B9C6035, cuteBird) -- ResurrectPed
                Wait(1000)
            end
            TaskFlyToCoord(cuteBird, 0, myCoords.x - 1, myCoords.y - 1, myCoords.z, 1, 0)
        end

        -- Handle delivery timeout
        if birdTime > 0 then
            birdTime = birdTime - 1
            Wait(1000)
        end

        if birdTime == 0 and cuteBird ~= nil and notified then
            lib.notify({ title = locale("cl_title_11"), description = locale('cl_delivery_fail1'), type = 'error', duration = 7000 })
            Wait(8000)
            lib.notify({ title = locale("cl_title_11"), description = locale('cl_delivery_fail2'), type = 'error', duration = 7000 })
            Wait(8000)
            lib.notify({ title = locale("cl_title_11"), description = locale('cl_delivery_fail3'), type = 'error', duration = 7000 })
            SetEntityInvincible(cuteBird, false)
            SetEntityAsMissionEntity(cuteBird, false, false)
            SetEntityAsNoLongerNeeded(cuteBird)
            DeleteEntity(cuteBird)
            RemoveBlip(birdBlip)
            notified = false
            LocalPlayer.state.telegramIsBirdPostApproaching = false
            return
        end

        ::continue::
    end
end)




-- Write the Message (when using bird post item)
RegisterNetEvent('rsg-telegram:client:WriteMessage', function()
    -- Open custom UI to new message tab
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openUI',
        defaultTab = 'new-message',
        usingBirdPost = true
    })
end)

-- Spawn Bird for Sending Message
RegisterNetEvent('rsg-telegram:client:SpawnBirdForSend', function()
    local ped = PlayerPedId()
    
    if IsPedOnMount(ped) or IsPedOnVehicle(ped) then
        lib.notify({ title = locale("cl_title_11"), description = locale('cl_player_on_horse'), type = 'error', duration = 7000 })
        return
    end
    
    -- Request validation from server (will check item and send callback if valid)
    TriggerServerEvent('rsg-telegram:server:ValidateBirdPostSend', messageData.sender, messageData.sendername, messageData.recipient, messageData.subject, messageData.message)
end)

-- Server validated bird post send, spawn the bird
RegisterNetEvent('rsg-telegram:client:StartBirdDelivery', function(targetCoords)
    local ped = PlayerPedId()
    local pID = PlayerId()
    local playerCoords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    
    -- Freeze player
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    
    -- Step 1: Take out notebook for 2 seconds
    Citizen.InvokeNative(0x524B54361229154F, ped, joaat('WORLD_HUMAN_WRITE_NOTEBOOK'), -1, true) -- TaskStartScenarioInPlace
    Wait(2000)
    
    -- Step 2: Clear notebook animation and sit down
    ClearPedTasks(ped)
    Wait(100)
    
    -- Make player sit/kneel down (using crouch or a sitting scenario)
    Citizen.InvokeNative(0x524B54361229154F, ped, joaat('WORLD_HUMAN_CROUCH_INSPECT'), -1, true) -- TaskStartScenarioInPlace
    Wait(500)
    
    -- Step 3: Spawn bird in front of player's feet (0.5 distance)
    local forwardX = playerCoords.x + (math.sin(math.rad(heading)) * 0.5)
    local forwardY = playerCoords.y + (math.cos(math.rad(heading)) * 0.5)
    local groundZ = playerCoords.z
    
    -- Spawn bird at ground level in front of player
    SpawnBirdPost(forwardX, forwardY, groundZ, heading, 0.5, 0)
    
    if cuteBird == nil then
        lib.notify({ title = locale("cl_title_11"), description = locale("cl_title_14"), type = 'error', duration = 7000 })
        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, false)
        ClearPedTasks(ped)
        return
    end
    
    -- Make bird face same direction as player
    SetEntityHeading(cuteBird, heading)
    SetEntityCollision(cuteBird, true, true)
    FreezeEntityPosition(cuteBird, true)
    SetBlockingOfNonTemporaryEvents(cuteBird, true)
    
    -- Wait for bird to "pick up" the letter (3 seconds)
    Wait(3000)
    
    lib.notify({ title = locale("cl_title_13"), description = 'Bird is picking up the letter...', type = 'info', duration = 3000 })
    
    -- Step 4: Bird flies away
    FreezeEntityPosition(cuteBird, false)
    SetEntityInvincible(cuteBird, false)
    SetBlockingOfNonTemporaryEvents(cuteBird, false)
    
    -- First make bird hop/fly up a bit
    local flyUpCoords = GetEntityCoords(cuteBird)
    Citizen.InvokeNative(0xD1C8F216, cuteBird, 1, flyUpCoords.x, flyUpCoords.y, flyUpCoords.z + 5.0, 1, 0) -- TaskFlyToCoord - fly up
    Wait(2000)
    
    -- Make bird fly to target destination
    local coordsOffset = math.random(200, 300)
    Citizen.InvokeNative(0xD1C8F216, cuteBird, 1, targetCoords.x - coordsOffset, targetCoords.y - coordsOffset, targetCoords.z + 75, 1, 0) -- TaskFlyToCoord
    
    -- Unfreeze player
    Wait(1000)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
    
    -- Wait for bird arrival delay
    Wait(Config.BirdArrivalDelay or 5000)
    
    -- Cleanup bird
    SetEntityInvincible(cuteBird, false)
    FreezeEntityPosition(cuteBird, false)
    SetEntityCanBeDamaged(cuteBird, true)
    SetEntityAsMissionEntity(cuteBird, false, false)
    SetEntityAsNoLongerNeeded(cuteBird)
    DeleteEntity(cuteBird)
    
    if birdBlip ~= nil then
        RemoveBlip(birdBlip)
    end
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
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
end)

-- Get the Message all 
RegisterNUICallback('getviewall', function(data, cb)
    local ids = data.ids
    for _, id in ipairs(ids) do
        TriggerServerEvent('rsg-telegram:server:GetMessages', tonumber(id))
    end
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
    cb('ok')
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
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
end)

-- Delete Message all
RegisterNUICallback('deleteall', function(data, cb)
    local ids = data.ids  -- Un array de IDs
    for _, id in ipairs(ids) do
        TriggerServerEvent('rsg-telegram:server:DeleteMessage', tonumber(id))
    end
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
    cb('ok')
end)

RegisterNUICallback('copymsg', function(data, cb)
    local id = data.id
    local message = data.message

    cb({ success = true, message = message })
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

-- ================================
-- NUI Callbacks for Custom UI
-- ================================

-- Close UI
RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Check if player is at post office
RegisterNUICallback('checkLocation', function(data, cb)
    local atPostOffice = IsPlayerAtPostOffice()
    cb({
        atPostOffice = atPostOffice,
        chargePlayer = Config.ChargePlayer,
        cost = Config.CostPerLetter
    })
end)

-- Get Inbox Messages
RegisterNUICallback('getInbox', function(data, cb)
    local atPostOffice = IsPlayerAtPostOffice()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:getInbox', function(messages)
        cb(messages or {})
    end, atPostOffice)
end)

-- Get Addressbook
RegisterNUICallback('getAddressbook', function(data, cb)
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:getAddressbook', function(contacts)
        cb(contacts or {})
    end)
end)

-- Get All Players for Recipient List
RegisterNUICallback('getPlayers', function(data, cb)
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:getAddressbook', function(contacts)
        cb(contacts or {})
    end)
end)

-- Send Message
RegisterNUICallback('sendMessage', function(data, cb)
    -- Close UI first
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'closeUI'
    })
    
    local atPostOffice = IsPlayerAtPostOffice()
    
    -- Get sender info
    local pID = PlayerId()
    local senderID = GetPlayerServerId(pID)
    local senderfirstname = RSGCore.Functions.GetPlayerData().charinfo.firstname
    local senderlastname = RSGCore.Functions.GetPlayerData().charinfo.lastname
    local sendertelegram = RSGCore.Functions.GetPlayerData().citizenid
    local senderfullname = senderfirstname..' '..senderlastname
    
    -- If not at post office, trigger bird spawn flow
    if not atPostOffice then
        -- Store message data for bird delivery
        messageData = {
            sender = sendertelegram,
            sendername = senderfullname,
            recipient = data.recipient,
            subject = data.subject,
            message = data.message
        }
        
        -- Trigger bird spawn event (will check item and spawn bird)
        TriggerEvent('rsg-telegram:client:SpawnBirdForSend')
    else
        -- At post office, send normally without bird
        TriggerServerEvent('rsg-telegram:server:SendMessagePostOffice', sendertelegram, senderfullname, data.recipient, data.subject, data.message)
    end
    
    cb('ok')
end)

-- Mark Message as Read
RegisterNUICallback('markAsRead', function(data, cb)
    TriggerServerEvent('rsg-telegram:server:MarkAsRead', tonumber(data.id))
    cb('ok')
end)

-- Delete Message
RegisterNUICallback('deleteMessage', function(data, cb)
    TriggerServerEvent('rsg-telegram:server:DeleteMessage', tonumber(data.id))
    cb('ok')
end)

-- Add Contact to Addressbook
RegisterNUICallback('addContact', function(data, cb)
    TriggerServerEvent('rsg-telegram:server:SavePerson', data.name, data.citizenid)
    cb('ok')
end)

-- Remove Contact from Addressbook
RegisterNUICallback('removeContact', function(data, cb)
    TriggerServerEvent('rsg-telegram:server:RemovePerson', data.citizenid)
    cb('ok')
end)

-- ================================
-- Legacy NUI Callbacks (for bird delivery system)
-- ================================

RegisterNUICallback('getview', function(data)
    TriggerServerEvent('rsg-telegram:server:GetMessages', tonumber(data.id))
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
end)

RegisterNUICallback('getviewall', function(data, cb)
    local ids = data.ids
    for _, id in ipairs(ids) do
        TriggerServerEvent('rsg-telegram:server:GetMessages', tonumber(id))
    end
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
    cb('ok')
end)

RegisterNUICallback('delete', function(data)
    TriggerServerEvent('rsg-telegram:server:DeleteMessage', tonumber(data.id))
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
end)

RegisterNUICallback('deleteall', function(data, cb)
    local ids = data.ids
    for _, id in ipairs(ids) do
        TriggerServerEvent('rsg-telegram:server:DeleteMessage', tonumber(id))
    end
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
    cb('ok')
end)

RegisterNUICallback('copymsg', function(data, cb)
    cb(data.value)
end)

RegisterNUICallback('NUIFocusOff', function()
    SetNuiFocus(false, false)
    SendNUIMessage
    ({
        type = 'closeAll'
    })
end)

-- Legacy Events (kept for compatibility)
RegisterNetEvent('rsg-telegram:client:ReadMessages')
AddEventHandler('rsg-telegram:client:ReadMessages', function()
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'openGeneral' })
    TriggerServerEvent('rsg-telegram:server:CheckInbox')
end)

RegisterNetEvent('rsg-telegram:client:InboxList')
AddEventHandler('rsg-telegram:client:InboxList', function(data)
    SendNUIMessage({ type = 'inboxlist', response = data })
end)

RegisterNetEvent('rsg-telegram:client:MessageData')
AddEventHandler('rsg-telegram:client:MessageData', function(tele)
    SendNUIMessage({ type = 'view', telegram = tele })
end)

-- AddressBook (Legacy - kept for backward compatibility)
RegisterNetEvent('rsg-telegram:client:OpenAddressbook', function()
    -- Open custom UI to addressbook tab
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openUI',
        defaultTab = 'addressbook'
    })
end)


RegisterNetEvent('rsg-telegram:client:AddPersonMenu', function()
    local input = lib.inputDialog(locale("cl_title_24"), {
        { type = 'input', label = locale("cl_title_25"),      required = true },
        { type = 'input', label = locale("cl_title_26"), required = true },
    })
    if not input then return end

    local name = input[1]
    local cid = input[2]
    if name and cid then
        TriggerServerEvent('rsg-telegram:server:SavePerson', name, cid)
    end
end)

RegisterNetEvent('rsg-telegram:client:ViewAddressBook', function()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:GetPlayers', function(players)
        if players ~= nil then
            local options = {
                {
                    title = locale("cl_title_27"),
                    description = locale("cl_title_28"),
                    icon = 'fa-solid fa-envelope-open-text',
                    isMenuHeader = true,
                },
            }
            for i = 1, #players do
                local player = players[i]
                options[#options + 1] = {
                    title = player.name,
                    description = locale("cl_title_29") .. player.citizenid,
                    disabled = true
                }
            end
            options[#options + 1] = {
                title = locale("cl_title_30"),
                description = locale("cl_title_31"),
                icon = 'fa-solid fa-circle-xmark',
                event = 'rsg-telegram:client:OpenAddressbook',
                args = {
                    isServer = false
                }
            }
            lib.registerContext({
                id = 'addressbook_view',  -- Corrected the context ID here
                title = locale("cl_title_32"),
                position = 'top-right',
                options = options
            })
            lib.showContext('addressbook_view')  -- Use the correct context ID here
        else
            lib.notify({ title = locale("cl_title_33"), description = locale("cl_title_34"), type = 'error', duration = 7000 })
        end
    end)
end)

RegisterNetEvent('rsg-telegram:client:RemovePersonMenu', function()
    RSGCore.Functions.TriggerCallback('rsg-telegram:server:GetPlayers', function(players)
        if players ~= nil then
            local option = {}
            for i = 1, #players do
                local citizenid = players[i].citizenid
                local fullname = players[i].name
                local content = { value = citizenid, label = fullname .. ' (' .. citizenid .. ')' }
                option[#option + 1] = content
            end

            local input = lib.inputDialog(locale("cl_title_35"), {
                { type = 'select', options = option, required = true, default = 'Recipient' }
            })
            if not input then return end

            local citizenid = input[1]
            if citizenid then
                TriggerServerEvent('rsg-telegram:server:RemovePerson', citizenid)
            end
        else
            lib.notify({ title = locale("cl_title_36"), description = locale("cl_title_37"), type = 'error', duration = 7000 })
        end
    end)
end)

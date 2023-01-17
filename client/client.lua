local RSGCore = exports['rsg-core']:GetCoreObject()
local telegram

-- prompts
Citizen.CreateThread(function()
    for telegram, v in pairs(Config.PostOfficeLocations) do
        exports['rsg-core']:createPrompt(v.location, v.coords, RSGCore.Shared.Keybinds['J'],  Lang:t('menu.open') .. v.name, {
            type = 'client',
            event = 'rsg-telegram:client:menu',
            args = {},
        })
        if v.showblip == true then
            local PostOfficeBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, v.coords)
            SetBlipSprite(PostOfficeBlip, GetHashKey(Config.Blip.blipSprite), true)
            SetBlipScale(PostOfficeBlip, Config.Blip.blipScale)
            Citizen.InvokeNative(0x9CB1A1623062F402, PostOfficeBlip, Config.Blip.blipName)
        end
    end
end)

-- telegram menu
RegisterNetEvent('rsg-telegram:client:menu', function(data)
    exports['rsg-menu']:openMenu({
        {
            header =  Lang:t('menu.telegram_menu'),
            isMenuHeader = true,
        },
        {
            header =  Lang:t('menu.read_messages'),
            txt = Lang:t('text.read_your_telegram_messages'),
            params = {
                event = 'rsg-telegram:client:readmessages',
                isServer = false,
                args = {}
            }
        },
        {
            header =  Lang:t('menu.send_telegram'),
            txt =  Lang:t('text.send_telegram_to_another_player'),
            params = {
                event = 'rsg-telegram:client:writemessage',
                isServer = false,
                args = {}
            }
        },
        {
            header = Lang:t('menu.close_menu'),
            txt = '',
            params = {
                event = 'rsg-menu:closeMenu',
            }
        },
    })
end)

-- write message
RegisterNetEvent('rsg-telegram:client:writemessage', function()

    RSGCore.Functions.TriggerCallback('rsg-telegram:server:getplayers', function(players)
        local option = {}
        
        for k,v in pairs(players) do
            local citizenid = v.citizenid
            local firstname = json.decode(v.charinfo).firstname
            local lastname = json.decode(v.charinfo).lastname
            local fullname = firstname..' '..lastname
            table.insert(option, {
                value = citizenid, text = citizenid..' : '..firstname..' '..lastname
            })
        end
        
        local input = exports['rsg-input']:ShowInput({
        header = Lang:t('inputs.telegram')..RSGCore.Functions.GetPlayerData().citizenid,
        submitText = Lang:t('inputs.send_for')..tonumber(Config.CostPerTelegram),
            inputs = {
                {
                    text = Lang:t('inputs.recipient'),
                    name = "recipient",
                    type = "select",
                    options = option
                },
                {
                    type = 'text',
                    name = 'subject',
                    text = Lang:t('inputs.subject'),
                    isRequired = true,
                },
                {
                    type = 'text',
                    name = 'message',
                    text = Lang:t('inputs.add_your_message_here'),
                    isRequired = true,
                },
            }
        })
        if input ~= nil then
            local senderfirstname = RSGCore.Functions.GetPlayerData().charinfo.firstname
            local senderlastname = RSGCore.Functions.GetPlayerData().charinfo.lastname
            local sendertelegram = RSGCore.Functions.GetPlayerData().citizenid
            local senderfullname = senderfirstname..' '..senderlastname
            TriggerServerEvent('rsg-telegram:server:sendmessage', sendertelegram, senderfullname, input.recipient, input.subject, input.message)
        end
    end)
end)

-- read messages
RegisterNetEvent('rsg-telegram:client:readmessages')
AddEventHandler('rsg-telegram:client:readmessages', function(location)
    InMenu = true
    translations = translates()
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'openGeneral', translations = translations })
    TriggerServerEvent('rsg-telegram:server:checkinbox')
end)

RegisterNetEvent('rsg-telegram:client:inboxlist')
AddEventHandler('rsg-telegram:client:inboxlist', function(data)
    SendNUIMessage({ type = 'inboxlist', response = data })
end)

-- get the telegram
RegisterNUICallback('getview', function(data)
    TriggerServerEvent('rsg-telegram:server:getTelegrams', tonumber(data.id))
end)

-- telegram message
RegisterNetEvent('rsg-telegram:client:messageData')
AddEventHandler('rsg-telegram:client:messageData', function(tele)
    translations = translates()

    SendNUIMessage({ type = 'view', telegram = tele, translations = translations })
end)

-- delete message
RegisterNUICallback('delete', function(data)
    TriggerServerEvent('rsg-telegram:server:DeleteTelegram', tonumber(data.id))
end)

-- close mailbox
RegisterNUICallback('NUIFocusOff', function()
    InMenu = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'closeAll' })
end)

function translates() 
    local translations = {}
    for k in pairs(Lang.fallback and Lang.fallback.phrases or Lang.phrases) do
       if k:sub(0, ('showUi.'):len()) then
           translations[k:sub(('showUi.'):len() + 1)] = Lang:t(k)
       end
   end
   return translations
end

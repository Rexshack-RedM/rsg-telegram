local RSGCore = exports['rsg-core']:GetCoreObject()

lib.locale()

-- Make Bird Post as a Usable Item
RSGCore.Functions.CreateUseableItem('birdpost', function(source)
    TriggerClientEvent('rsg-telegram:client:WriteMessage', source)
end)

-- Delivery Success
RegisterNetEvent('rsg-telegram:server:DeliverySuccess')
AddEventHandler('rsg-telegram:server:DeliverySuccess', function(sID, tPName)
    TriggerClientEvent('ox_lib:notify', sID, {title = locale("sv_title_38"), description = locale('sv_letter_delivered')..' '..tPName..' '..locale('sv_letter_delivered_suc'), type = 'success', duration = 5000 })
end)

-- Add Message to the Database
RegisterServerEvent('rsg-telegram:server:SendMessage')
AddEventHandler('rsg-telegram:server:SendMessage', function(senderID, sender, sendername, tgtid, subject, message)
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)

    if RSGPlayer == nil then return end
    -- local _tgtid = tonumber(tgtid)
    local targetPlayer = RSGCore.Functions.GetPlayerByCitizenId(tgtid)
    if targetPlayer == nil then
        TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale('sv_player_unavailable'), type = 'error', duration = 5000 })
        return
    end

    if not Config.AllowSendToSelf and RSGPlayer.PlayerData.citizenid == tgtid then
        TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale('sv_send_to_self'), type = 'error', duration = 5000 })
        return
    end

    local _citizenid = targetPlayer.PlayerData.citizenid
    local targetPlayerName = targetPlayer.PlayerData.charinfo.firstname..' '..targetPlayer.PlayerData.charinfo.lastname
    local cost = Config.CostPerLetter
    local cashBalance = RSGPlayer.PlayerData.money['cash']
    local sentDate = os.date('%x')

    if Config.ChargePlayer and cashBalance < cost then
        TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale('sv_insufficient_balance'), type = 'error', duration = 5000 })
        return
    end

    exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`) VALUES (?, ?, ?, ?, ?, ?, ?)',{_citizenid, targetPlayerName, sender, sendername, subject, sentDate, message})
    local state = Player(targetPlayer.PlayerData.source).state
    state.telegramUnreadMessages = (state.telegramUnreadMessages or 0) + 1
    
    TriggerClientEvent('rsg-telegram:client:ReceiveMessage', targetPlayer.PlayerData.source, senderID, targetPlayerName)

    if Config.ChargePlayer then
        RSGPlayer.Functions.RemoveMoney('cash', cost, 'send-post')
    end
end)

RegisterServerEvent('rsg-telegram:server:SendMessagePostOffice')
AddEventHandler('rsg-telegram:server:SendMessagePostOffice', function(sender, sendername, citizenid, subject, message)
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)
    local cost = Config.CostPerLetter
    local cashBalance = RSGPlayer.PlayerData.money['cash']
    local sentDate = os.date('%x')

    if Config.ChargePlayer and cashBalance < cost then
        TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale('sv_insufficient_balance'), type = 'error', duration = 5000 })
        return
    end

    local result = MySQL.Sync.fetchAll('SELECT * FROM players WHERE citizenid = @citizenid', {citizenid = citizenid})

    if result[1] == nil then return end

    local tFirstName = json.decode(result[1].charinfo).firstname
    local tLastName = json.decode(result[1].charinfo).lastname
    local tFullName = tFirstName..' '..tLastName

    exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`) VALUES (?, ?, ?, ?, ?, ?, ?);', {citizenid, tFullName, sender, sendername, subject, sentDate, message})
    local targetPlayer = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
    if (targetPlayer) then 
        local state = Player(targetPlayer.PlayerData.source).state
        state.telegramUnreadMessages = (state.telegramUnreadMessages or 0) + 1
    end

    TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_38"), description = locale("sv_letter_delivered", {pName = tFullName}), type = 'success', duration = 5000 })

    if Config.ChargePlayer then
        RSGPlayer.Functions.RemoveMoney('cash', cost, 'send telegram')
    end
end)

-- Check for Inbox
RegisterServerEvent('rsg-telegram:server:CheckInbox')
AddEventHandler('rsg-telegram:server:CheckInbox', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)

    if Player == nil then return end

    local citizenid = Player.PlayerData.citizenid

    exports.oxmysql:execute('SELECT * FROM telegrams WHERE citizenid = ? AND (birdstatus = 0 OR birdstatus = 1) ORDER BY id DESC',{citizenid}, function(result)
        local res = {}

        res['list'] = result or {}

        TriggerClientEvent('rsg-telegram:client:InboxList', src, res)
    end)
end)

-- Get Messages from the Database
RegisterServerEvent('rsg-telegram:server:GetMessages')
AddEventHandler('rsg-telegram:server:GetMessages', function(tid)
    local src = source
    local telegram = {}

    local result = MySQL.query.await('SELECT * FROM telegrams WHERE id = @id AND (birdstatus = 0 OR birdstatus = 1)',
    {
        ['@id'] = tid
    })

    if result[1] == nil then
        TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale('sv_no_message'), type = 'error', duration = 5000 })
        return
    end

    telegram['citizenid'] = result[1]['citizenid']
    telegram['recipient'] = result[1]['recipient']
    telegram['sender'] = result[1]['sender']
    telegram['sendername'] = result[1]['sendername']
    telegram['subject'] = result[1]['subject']
    telegram['sentDate'] = result[1]['sentDate']
    telegram['message'] = result[1]['message']

    MySQL.Async.execute('UPDATE `telegrams` SET `status` = 1, `birdstatus` = 1 WHERE id = @id',
    {
        ['@id'] = tid
    })
    local state = Player(src).state
    state.telegramUnreadMessages = (state.telegramUnreadMessages or 0) - 1

    TriggerClientEvent('rsg-telegram:client:MessageData', src, telegram)
end)

-- Delete Message
RegisterServerEvent('rsg-telegram:server:DeleteMessage')
AddEventHandler('rsg-telegram:server:DeleteMessage', function(tid)
    local src = source

    local result = MySQL.query.await('SELECT * FROM telegrams WHERE id = @id',
    {
        ['@id'] = tid
    })

    if result[1] == nil then
        TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale('sv_delete_fail'), type = 'error', duration = 5000 })
        return
    end

    if result[1].status == 0 or result[1].birdstatus == 0 then
        local state = Player(src).state
        state.telegramUnreadMessages = (state.telegramUnreadMessages or 0) - 1
    end

    MySQL.Async.execute('DELETE FROM telegrams WHERE id = @id',
    {
        ['@id'] = tid
    })

    TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_38"), description = locale('sv_delete_success'), type = 'success', duration = 5000 })
    TriggerClientEvent('rsg-telegram:client:ReadMessages', src)
end)

-- Get Players
RSGCore.Functions.CreateCallback('rsg-telegram:server:GetPlayers', function(source, cb)
    local players = {}
    local src = source
    local xPlayer = RSGCore.Functions.GetPlayer(src)
    exports.oxmysql:execute('SELECT * FROM `address_book` WHERE owner = @owner  ORDER BY name ASC', {
        ['@owner'] = xPlayer.PlayerData.citizenid
    }, function(result)
        if result[1] then
            cb(result)
        else
            cb(nil)
        end
    end)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:GetPlayersPostOffice', function(source, cb)
    local src = source
    local xPlayer = RSGCore.Functions.GetPlayer(src)
    exports.oxmysql:execute('SELECT * FROM `address_book` WHERE owner = @owner  ORDER BY name ASC', {
        ['@owner'] = xPlayer.PlayerData.citizenid
    }, function(result)
        if result[1] then
            cb(result)
        else
            cb(nil)
        end
    end)
end)

RegisterServerEvent('rsg-telegram:server:SavePerson')
AddEventHandler('rsg-telegram:server:SavePerson', function(name,cid)
    local src = source
    local xPlayer = RSGCore.Functions.GetPlayer(src)
    while xPlayer == nil do Wait(0) end
    
    -- Check if person already exists in address book
    local existing = MySQL.query.await('SELECT * FROM address_book WHERE owner = ? AND citizenid = ?', {
        xPlayer.PlayerData.citizenid,
        cid
    })

    if existing and existing[1] then
        TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale("sv_already_exists"), type = 'error', duration = 5000 })
        return
    end

    exports.oxmysql:execute('INSERT INTO address_book (`citizenid`, `name`, `owner`) VALUES (?, ?, ?);', {cid, name, xPlayer.PlayerData.citizenid})
    TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_38"), description = locale("sv_title_40"), type = 'success', duration = 5000 })
end)

RegisterServerEvent('rsg-telegram:server:RemovePerson')
AddEventHandler('rsg-telegram:server:RemovePerson', function(cid)
    local src = source
    local xPlayer = RSGCore.Functions.GetPlayer(src)
    while xPlayer == nil do Wait(0) end
    MySQL.Async.execute('DELETE FROM address_book WHERE owner like @owner AND citizenid like @citizenid',
    {
        ['@owner'] = xPlayer.PlayerData.citizenid,
        ['citizenid'] = cid
    })

    TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_38"), description = locale('sv_delete_success'), type = 'success', duration = 5000 })
end)

-- Command
RSGCore.Commands.Add('addressbook', locale("sv_command"), {}, false, function(source)
    local src = source
    TriggerClientEvent('rsg-telegram:client:OpenAddressbook', src)
end)

-- count telegrams for player
RSGCore.Functions.CreateCallback('rsg-telegram:server:getTelegramsAmount', function(source, cb)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if Player ~= nil then
        local result = MySQL.prepare.await('SELECT COUNT(*) FROM telegrams WHERE citizenid = ? AND (status = ? OR birdstatus = ?)', {Player.PlayerData.citizenid, 0, 0})
        if result > 0 then
            cb(result)
        else
            cb(0)
        end
    end
end)

local RSGCore = exports['rsg-core']:GetCoreObject()

lib.locale()

-- Job mailbox constants keep the new feature isolated from the existing personal inbox flow.
local PERSONAL_MAILBOX = 'personal'
local JOB_MAILBOX = 'job'

-- Normalizes configured aliases so "Sheriff", " sheriff ", and "sheriff" resolve the same way.
local function NormalizeJobAlias(value)
    if type(value) ~= 'string' then return nil end
    return value:lower():gsub('^%s+', ''):gsub('%s+$', '')
end

-- Returns the configured job recipient for an alias entered instead of a citizen id.
local function GetJobRecipient(alias)
    if not Config.EnableJobMailboxes then return nil, nil end

    local normalizedAlias = NormalizeJobAlias(alias)
    if not normalizedAlias or not Config.JobRecipients then return nil, nil end

    for recipientAlias, recipientConfig in pairs(Config.JobRecipients) do
        if NormalizeJobAlias(recipientAlias) == normalizedAlias then
            return recipientAlias, recipientConfig
        end
    end

    return nil, nil
end

-- Looks up a job type from either the player's saved job data or the shared job definition.
local function GetJobType(jobData)
    if not jobData or not jobData.name then return nil end

    if jobData.type then
        return jobData.type
    end

    local sharedJob = RSGCore.Shared.Jobs[jobData.name]
    return sharedJob and sharedJob.type or nil
end

-- Checks whether a saved or online player job matches a job recipient rule.
local function DoesJobMatchJobRecipient(jobData, recipientConfig)
    if not jobData or not recipientConfig then return false end

    if recipientConfig.jobType and GetJobType(jobData) == recipientConfig.jobType then
        return true
    end

    if recipientConfig.jobs then
        for _, jobName in ipairs(recipientConfig.jobs) do
            if jobData.name == jobName then
                return true
            end
        end
    end

    return false
end

-- Validates that the sending player can send as the selected job mailbox.
local function GetJobSenderForPlayer(player, alias)
    local normalizedAlias = NormalizeJobAlias(alias)
    if not player or not normalizedAlias or not Config.EnableJobMailboxes or not Config.JobRecipients then return nil, nil end

    for recipientAlias, recipientConfig in pairs(Config.JobRecipients) do
        if NormalizeJobAlias(recipientAlias) == normalizedAlias and DoesJobMatchJobRecipient(player.PlayerData.job, recipientConfig) then
            return recipientAlias, recipientConfig
        end
    end

    return nil, nil
end

-- Resolves the stored sender identity, allowing eligible players to send from their job mailbox.
local function ResolveSenderIdentity(src, player, sender, sendername, jobSenderAlias)
    if not jobSenderAlias or jobSenderAlias == '' then
        return sender, sendername
    end

    local alias, senderConfig = GetJobSenderForPlayer(player, jobSenderAlias)
    if not alias then
        TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale('sv_cannot_send_from_job'), type = 'error', duration = 5000 })
        return nil, nil
    end

    return alias, senderConfig.label or alias
end

-- Finds all current characters whose job matches the configured job recipient.
local function GetJobRecipientPlayers(recipientConfig)
    local recipients = {}
    local seenCitizenIds = {}
    local savedPlayers = MySQL.query.await('SELECT citizenid, charinfo, job FROM players') or {}

    for _, row in ipairs(savedPlayers) do
        local jobData = row.job and json.decode(row.job) or nil

        if DoesJobMatchJobRecipient(jobData, recipientConfig) then
            local charinfo = row.charinfo and json.decode(row.charinfo) or {}
            local fullName = ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')

            recipients[#recipients + 1] = {
                citizenid = row.citizenid,
                name = fullName ~= '' and fullName or row.citizenid
            }
            seenCitizenIds[row.citizenid] = true
        end
    end

    -- Online PlayerData is treated as authoritative in case the job changed after the last database save.
    for _, playerId in ipairs(RSGCore.Functions.GetPlayers()) do
        local onlinePlayer = RSGCore.Functions.GetPlayer(playerId)

        if onlinePlayer and DoesJobMatchJobRecipient(onlinePlayer.PlayerData.job, recipientConfig) then
            local citizenid = onlinePlayer.PlayerData.citizenid

            if not seenCitizenIds[citizenid] then
                recipients[#recipients + 1] = {
                    citizenid = citizenid,
                    name = onlinePlayer.PlayerData.charinfo.firstname .. ' ' .. onlinePlayer.PlayerData.charinfo.lastname
                }
                seenCitizenIds[citizenid] = true
            end
        end
    end

    return recipients
end

-- Notifies currently online recipients and updates their unread count after a job telegram is created.
local function NotifyJobRecipients(recipients)
    for _, recipient in ipairs(recipients) do
        local targetPlayer = RSGCore.Functions.GetPlayerByCitizenId(recipient.citizenid)

        if targetPlayer then
            local state = Player(targetPlayer.PlayerData.source).state
            state.telegramUnreadMessages = (state.telegramUnreadMessages or 0) + 1

            TriggerClientEvent('ox_lib:notify', targetPlayer.PlayerData.source, {
                title = locale('sv_job_mail_title'),
                description = locale('sv_job_mail_received'),
                type = 'info',
                duration = 10000
            })
        end
    end
end

-- Inserts one job telegram per matching character so read/delete state remains personal per recipient.
local function SendJobTelegram(src, sender, sendername, alias, recipientConfig, subject, message, fromPostOffice, pickedUp)
    local recipients = GetJobRecipientPlayers(recipientConfig)

    if #recipients == 0 then
        TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale('sv_no_job_recipients'), type = 'error', duration = 5000 })
        return false
    end

    local sentDate = os.date('%x')
    local recipientLabel = recipientConfig.label or alias

    for _, recipient in ipairs(recipients) do
        exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`, `fromPostOffice`, `pickedUp`, `mailbox`, `jobTarget`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
            {recipient.citizenid, recipientLabel, sender, sendername, subject, sentDate, message, fromPostOffice, pickedUp, JOB_MAILBOX, alias})
    end

    NotifyJobRecipients(recipients)
    TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_38"), description = locale('sv_job_telegram_sent', recipientLabel), type = 'success', duration = 5000 })

    return true, recipientLabel, recipients
end

-- Make Bird Post as a Usable Item
RSGCore.Functions.CreateUseableItem(Config.BirdPostItem, function(source)
    TriggerClientEvent('rsg-telegram:client:WriteMessage', source)
end)

-- Delivery Success
RegisterNetEvent('rsg-telegram:server:DeliverySuccess')
AddEventHandler('rsg-telegram:server:DeliverySuccess', function(sID, tPName)
    TriggerClientEvent('ox_lib:notify', sID, {title = locale("sv_title_38"), description = locale('sv_letter_delivered')..' '..tPName..' '..locale('sv_letter_delivered_suc'), type = 'success', duration = 5000 })
end)

-- Add Message to the Database
RegisterServerEvent('rsg-telegram:server:SendMessage')
AddEventHandler('rsg-telegram:server:SendMessage', function(senderID, sender, sendername, tgtid, subject, message, jobSenderAlias)
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)

    if RSGPlayer == nil then return end

    sender, sendername = ResolveSenderIdentity(src, RSGPlayer, sender, sendername, jobSenderAlias)
    if not sender then return end

    local jobAlias, jobRecipient = GetJobRecipient(tgtid)
    if jobRecipient then
        local cost = Config.CostPerLetter
        local cashBalance = RSGPlayer.PlayerData.money['cash']

        -- Legacy send support keeps older menus compatible with configured job aliases.
        if Config.ChargePlayer and cashBalance < cost then
            TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale('sv_insufficient_balance'), type = 'error', duration = 5000 })
            return
        end

        local sent = SendJobTelegram(src, sender, sendername, jobAlias, jobRecipient, subject, message, 0, 1)

        if sent and Config.ChargePlayer then
            RSGPlayer.Functions.RemoveMoney('cash', cost, 'send job telegram')
        end

        return
    end

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
AddEventHandler('rsg-telegram:server:SendMessagePostOffice', function(sender, sendername, citizenid, subject, message, jobSenderAlias)
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)
    local cost = Config.CostPerLetter
    local cashBalance = RSGPlayer.PlayerData.money['cash']
    local sentDate = os.date('%x')
    local jobAlias, jobRecipient = GetJobRecipient(citizenid)

    sender, sendername = ResolveSenderIdentity(src, RSGPlayer, sender, sendername, jobSenderAlias)
    if not sender then return end

    -- Check if trying to send to self (unless allowed in config)
    if not jobRecipient and sender == citizenid and not Config.AllowSendToSelf then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale('sv_send_to_self'), 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    if Config.ChargePlayer and cashBalance < cost then
        TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale('sv_insufficient_balance'), type = 'error', duration = 5000 })
        return
    end

    -- Job aliases are handled before citizen-id validation so values like "sheriff" can be used as recipients.
    if jobRecipient then
        local sent = SendJobTelegram(src, sender, sendername, jobAlias, jobRecipient, subject, message, 1, 0)

        if sent and Config.ChargePlayer then
            RSGPlayer.Functions.RemoveMoney('cash', cost, 'send job telegram')
        end

        return
    end

    local result = MySQL.Sync.fetchAll('SELECT * FROM players WHERE citizenid = @citizenid', {citizenid = citizenid})

    if result[1] == nil then 
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale('sv_invalid_recipient'), 
            type = 'error', 
            duration = 5000 
        })
        return 
    end

    local tFirstName = json.decode(result[1].charinfo).firstname
    local tLastName = json.decode(result[1].charinfo).lastname
    local tFullName = tFirstName..' '..tLastName

    -- Insert telegram with fromPostOffice = 1, pickedUp = 0 (needs to be picked up at post office)
    exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`, `fromPostOffice`, `pickedUp`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);', {citizenid, tFullName, sender, sendername, subject, sentDate, message, 1, 0})
    
    -- Notify recipient and update their unread count (for envelope icon)
    local targetPlayer = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
    if targetPlayer then
        -- Update unread count to include unpicked message
        local state = Player(targetPlayer.PlayerData.source).state
        state.telegramUnreadMessages = (state.telegramUnreadMessages or 0) + 1
        
        TriggerClientEvent('ox_lib:notify', targetPlayer.PlayerData.source, {
            title = locale('sv_new_mail_title'),
            description = locale('sv_post_office_waiting_mail'),
            type = 'info',
            duration = 10000
        })
    end
    
    TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_38"), description = locale('sv_letter_delivered')..' '..tFullName, type = 'success', duration = 5000 })

    if Config.ChargePlayer then
        RSGPlayer.Functions.RemoveMoney('cash', cost, 'send telegram')
    end
end)

-- SEND MESSAGE WITH BIRD POST ITEM (outside post office)
RegisterServerEvent('rsg-telegram:server:SendMessageWithBirdPost')
AddEventHandler('rsg-telegram:server:SendMessageWithBirdPost', function(sender, sendername, citizenid, subject, message, jobSenderAlias)
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)
    local sentDate = os.date('%x')
    local jobAlias, jobRecipient = GetJobRecipient(citizenid)

    sender, sendername = ResolveSenderIdentity(src, RSGPlayer, sender, sendername, jobSenderAlias)
    if not sender then return end

    -- Check if trying to send to self (unless allowed in config)
    if not jobRecipient and sender == citizenid and not Config.AllowSendToSelf then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale('sv_send_to_self'), 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    -- Check if player has bird post item
    local hasBirdPost = RSGPlayer.Functions.GetItemByName(Config.BirdPostItem)
    
    if not hasBirdPost or hasBirdPost.amount < 1 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("cl_title_11"), 
            description = locale('cl_no_birdpost_item'), 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    -- Job telegrams sent by bird consume one bird post item and are copied to each matching recipient.
    if jobRecipient then
        RSGPlayer.Functions.RemoveItem(Config.BirdPostItem, 1)
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[Config.BirdPostItem], 'remove', 1)

        Wait(Config.BirdArrivalDelay)
        SendJobTelegram(src, sender, sendername, jobAlias, jobRecipient, subject, message, 0, 1)
        return
    end

    -- Get recipient info
    local result = MySQL.Sync.fetchAll('SELECT * FROM players WHERE citizenid = @citizenid', {citizenid = citizenid})

    if result[1] == nil then 
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale('sv_invalid_recipient'), 
            type = 'error', 
            duration = 5000 
        })
        return 
    end

    local tFirstName = json.decode(result[1].charinfo).firstname
    local tLastName = json.decode(result[1].charinfo).lastname
    local tFullName = tFirstName..' '..tLastName

    -- Remove bird post item
    RSGPlayer.Functions.RemoveItem(Config.BirdPostItem, 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[Config.BirdPostItem], 'remove', 1)

    -- Wait for bird arrival delay, then insert telegram
    Wait(Config.BirdArrivalDelay)
    
    -- Insert telegram with fromPostOffice = 0, pickedUp = 1 (bird delivers directly)
    exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`, `fromPostOffice`, `pickedUp`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);', {citizenid, tFullName, sender, sendername, subject, sentDate, message, 0, 1})
    
    -- Increment unread count after bird delivers
    local targetPlayer = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
    if (targetPlayer) then 
        local state = Player(targetPlayer.PlayerData.source).state
        state.telegramUnreadMessages = (state.telegramUnreadMessages or 0) + 1
    end

    TriggerClientEvent('ox_lib:notify', src, {
        title = locale("sv_title_38"), 
        description = locale('sv_letter_delivered')..' '..tFullName, 
        type = 'success', 
        duration = 5000 
    })
end)

-- VALIDATE BIRD POST SEND (checks item, then triggers bird spawn)
RegisterServerEvent('rsg-telegram:server:ValidateBirdPostSend')
AddEventHandler('rsg-telegram:server:ValidateBirdPostSend', function(sender, sendername, citizenid, subject, message, jobSenderAlias)
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)
    local sentDate = os.date('%x')
    local jobAlias, jobRecipient = GetJobRecipient(citizenid)

    sender, sendername = ResolveSenderIdentity(src, RSGPlayer, sender, sendername, jobSenderAlias)
    if not sender then return end

    -- Check if trying to send to self (unless allowed in config)
    if not jobRecipient and sender == citizenid and not Config.AllowSendToSelf then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale('sv_send_to_self'), 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    -- Check if player has bird post item
    local hasBirdPost = RSGPlayer.Functions.GetItemByName(Config.BirdPostItem)
    
    if not hasBirdPost or hasBirdPost.amount < 1 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("cl_title_11"), 
            description = locale('cl_no_birdpost_item'), 
            type = 'error', 
            duration = 5000 
        })
        return
    end

    -- Job bird delivery uses the sender animation, then delivers copies to all matching workers.
    if jobRecipient then
        local recipients = GetJobRecipientPlayers(jobRecipient)

        if #recipients == 0 then
            TriggerClientEvent('ox_lib:notify', src, {title = locale("sv_title_39"), description = locale('sv_no_job_recipients'), type = 'error', duration = 5000 })
            return
        end

        local targetCoords = vector3(-175.0, 628.0, 114.0)
        for _, recipient in ipairs(recipients) do
            local targetPlayer = RSGCore.Functions.GetPlayerByCitizenId(recipient.citizenid)
            if targetPlayer then
                local targetPed = GetPlayerPed(targetPlayer.PlayerData.source)
                targetCoords = GetEntityCoords(targetPed)
                break
            end
        end

        RSGPlayer.Functions.RemoveItem(Config.BirdPostItem, 1)
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[Config.BirdPostItem], 'remove', 1)
        TriggerClientEvent('rsg-telegram:client:StartBirdDelivery', src, targetCoords)

        Wait(8000)
        Wait(Config.BirdArrivalDelay)
        SendJobTelegram(src, sender, sendername, jobAlias, jobRecipient, subject, message, 0, 1)
        return
    end

    -- Get recipient info
    local result = MySQL.Sync.fetchAll('SELECT * FROM players WHERE citizenid = @citizenid', {citizenid = citizenid})

    if result[1] == nil then 
        TriggerClientEvent('ox_lib:notify', src, {
            title = locale("sv_title_39"), 
            description = locale('sv_invalid_recipient'), 
            type = 'error', 
            duration = 5000 
        })
        return 
    end

    local tFirstName = json.decode(result[1].charinfo).firstname
    local tLastName = json.decode(result[1].charinfo).lastname
    local tFullName = tFirstName..' '..tLastName
    
    -- Get target coords (if online, use their coords; if offline use a default location)
    local targetCoords = vector3(-175.0, 628.0, 114.0) -- Valentine default
    local targetPlayer = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
    if targetPlayer then
        local targetPed = GetPlayerPed(targetPlayer.PlayerData.source)
        targetCoords = GetEntityCoords(targetPed)
    end

    -- Remove bird post item FIRST
    RSGPlayer.Functions.RemoveItem(Config.BirdPostItem, 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[Config.BirdPostItem], 'remove', 1)

    -- Trigger client bird spawn and delivery animation
    TriggerClientEvent('rsg-telegram:client:StartBirdDelivery', src, targetCoords)

    -- Wait for bird to fly away + arrival delay, then insert telegram
    Wait(8000) -- Wait for bird to fly away
    Wait(Config.BirdArrivalDelay) -- Wait for arrival delay
    
    -- Insert telegram with fromPostOffice = 0, pickedUp = 1 (bird delivers directly to player)
    exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `recipient`, `sender`, `sendername`, `subject`, `sentDate`, `message`, `fromPostOffice`, `pickedUp`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);', {citizenid, tFullName, sender, sendername, subject, sentDate, message, 0, 1})
    
    -- Increment unread count after bird delivers
    if targetPlayer then 
        local state = Player(targetPlayer.PlayerData.source).state
        state.telegramUnreadMessages = (state.telegramUnreadMessages or 0) + 1
    end

    -- Notify success
    TriggerClientEvent('ox_lib:notify', src, {
        title = locale("sv_title_38"), 
        description = locale('sv_letter_delivered')..' '..tFullName, 
        type = 'success', 
        duration = 5000 
    })
end)

-- Check for Inbox
RegisterServerEvent('rsg-telegram:server:CheckInbox')
AddEventHandler('rsg-telegram:server:CheckInbox', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)

    if Player == nil then return end

    local citizenid = Player.PlayerData.citizenid

    exports.oxmysql:execute('SELECT * FROM telegrams WHERE citizenid = ? AND mailbox = ? AND (birdstatus = 0 OR birdstatus = 1) ORDER BY id DESC',{citizenid, PERSONAL_MAILBOX}, function(result)
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

-- Commands
RSGCore.Commands.Add('telegram', locale("sv_command_telegram"), {}, false, function(source)
    local src = source
    TriggerClientEvent('rsg-telegram:client:OpenTelegram', src)
end)

RSGCore.Commands.Add('addressbook', locale("sv_command"), {}, false, function(source)
    local src = source
    TriggerClientEvent('rsg-telegram:client:OpenAddressbook', src)
end)

-- ================================
-- Callbacks for Custom UI
-- ================================

-- Get Inbox Messages
RSGCore.Functions.CreateCallback('rsg-telegram:server:getInbox', function(source, cb, atPostOffice)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if Player == nil then
        cb({})
        return
    end

    local citizenid = Player.PlayerData.citizenid
    
    -- If at post office, show ALL messages (including unpicked)
    -- Otherwise, only show picked up messages
    local query = ''
    if atPostOffice then
        query = 'SELECT * FROM telegrams WHERE citizenid = ? AND mailbox = ? AND (birdstatus = 0 OR birdstatus = 1) ORDER BY id DESC'
    else
        query = 'SELECT * FROM telegrams WHERE citizenid = ? AND mailbox = ? AND pickedUp = 1 AND (birdstatus = 0 OR birdstatus = 1) ORDER BY id DESC'
    end
    
    exports.oxmysql:execute(query, {citizenid, PERSONAL_MAILBOX}, function(result)
        cb(result or {})
    end)
end)

-- Get Job Inbox Messages
RSGCore.Functions.CreateCallback('rsg-telegram:server:getJobInbox', function(source, cb, atPostOffice)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)

    -- When job mailboxes are disabled, the UI receives an empty mailbox and aliases are ignored.
    if not Config.EnableJobMailboxes then
        cb({})
        return
    end
    
    if Player == nil then
        cb({})
        return
    end

    local citizenid = Player.PlayerData.citizenid
    
    -- Job messages use their own mailbox but keep the same post-office pickup behavior.
    local query = ''
    if atPostOffice then
        query = 'SELECT * FROM telegrams WHERE citizenid = ? AND mailbox = ? AND (birdstatus = 0 OR birdstatus = 1) ORDER BY id DESC'
    else
        query = 'SELECT * FROM telegrams WHERE citizenid = ? AND mailbox = ? AND pickedUp = 1 AND (birdstatus = 0 OR birdstatus = 1) ORDER BY id DESC'
    end
    
    exports.oxmysql:execute(query, {citizenid, JOB_MAILBOX}, function(result)
        cb(result or {})
    end)
end)

-- Get configured job recipients for the compose dropdown.
RSGCore.Functions.CreateCallback('rsg-telegram:server:getJobRecipients', function(source, cb)
    local recipients = {}

    if Config.EnableJobMailboxes and Config.JobRecipients then
        for alias, recipientConfig in pairs(Config.JobRecipients) do
            -- Only expose job aliases in the compose dropdown when the config explicitly allows it.
            if recipientConfig.showInRecipientList then
                recipients[#recipients + 1] = {
                    citizenid = alias,
                    name = recipientConfig.label or alias,
                    job = true
                }
            end
        end
    end

    table.sort(recipients, function(a, b)
        return a.name < b.name
    end)

    cb(recipients)
end)

-- Get job mailboxes the current player is allowed to send from.
RSGCore.Functions.CreateCallback('rsg-telegram:server:getJobSenders', function(source, cb)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    local senders = {}

    if not Player or not Config.EnableJobMailboxes or not Config.JobRecipients then
        cb(senders)
        return
    end

    for alias, recipientConfig in pairs(Config.JobRecipients) do
        -- A player may send as a job mailbox only when the config exposes it and their current job matches that mailbox rule.
        if recipientConfig.showInSenderList and DoesJobMatchJobRecipient(Player.PlayerData.job, recipientConfig) then
            senders[#senders + 1] = {
                alias = alias,
                label = recipientConfig.label or alias
            }
        end
    end

    table.sort(senders, function(a, b)
        return a.label < b.label
    end)

    cb(senders)
end)

-- Check for waiting messages at post office
RSGCore.Functions.CreateCallback('rsg-telegram:server:checkWaitingMessages', function(source, cb)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if Player == nil then
        cb(0)
        return
    end

    local citizenid = Player.PlayerData.citizenid
    
    -- Count messages that are waiting to be picked up at post office
    exports.oxmysql:execute('SELECT COUNT(*) as count FROM telegrams WHERE citizenid = ? AND fromPostOffice = 1 AND pickedUp = 0', {citizenid}, function(result)
        cb(result[1].count or 0)
    end)
end)

-- Pick up messages from post office
RegisterServerEvent('rsg-telegram:server:pickupMessages')
AddEventHandler('rsg-telegram:server:pickupMessages', function()
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)
    
    if not RSGPlayer then return end
    
    local citizenid = RSGPlayer.PlayerData.citizenid
    
    -- Get waiting messages
    exports.oxmysql:execute('SELECT * FROM telegrams WHERE citizenid = ? AND fromPostOffice = 1 AND pickedUp = 0', {citizenid}, function(messages)
        if messages and #messages > 0 then
            -- Mark all as picked up
            exports.oxmysql:execute('UPDATE telegrams SET pickedUp = 1 WHERE citizenid = ? AND fromPostOffice = 1 AND pickedUp = 0', {citizenid})
            
            -- Don't increment state here - messages were already counted when they arrived
            -- State will remain the same because they're still unread (status=0)
            -- The state will only decrease when messages are actually read (status=1)
            
            -- Notify player
            lib.notify({
                id = src,
                title = locale("sv_title_38"),
                description = locale('sv_picked_up_mail', #messages),
                type = 'success',
                duration = 5000
            })
        else
            lib.notify({
                id = src,
                title = locale("sv_title_39"),
                description = locale('sv_no_waiting_mail'),
                type = 'info',
                duration = 5000
            })
        end
    end)
end)

-- Get Addressbook Contacts
RSGCore.Functions.CreateCallback('rsg-telegram:server:getAddressbook', function(source, cb)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if Player == nil then
        cb({})
        return
    end

    exports.oxmysql:execute('SELECT * FROM address_book WHERE owner = ? ORDER BY name ASC', {Player.PlayerData.citizenid}, function(result)
        cb(result or {})
    end)
end)

-- Mark Message as Read
RegisterServerEvent('rsg-telegram:server:MarkAsRead')
AddEventHandler('rsg-telegram:server:MarkAsRead', function(tid)
    local src = source
    local RSGPlayer = RSGCore.Functions.GetPlayer(src)
    
    if RSGPlayer == nil then return end

    local result = MySQL.query.await('SELECT * FROM telegrams WHERE id = @id', {['@id'] = tid})
    
    if result[1] == nil then return end

    -- Check if message was unread (status = 0 or birdstatus = 0)
    local wasUnread = (tonumber(result[1].status) == 0 or tonumber(result[1].birdstatus) == 0)
    
    -- Update status to read
    -- Also mark post office messages as picked up when read (since you can only read them at post office)
    if tonumber(result[1].fromPostOffice) == 1 then
        MySQL.Async.execute('UPDATE telegrams SET status = 1, birdstatus = 1, pickedUp = 1 WHERE id = @id', {['@id'] = tid})
    else
        MySQL.Async.execute('UPDATE telegrams SET status = 1, birdstatus = 1 WHERE id = @id', {['@id'] = tid})
    end
    
    -- Decrease unread count if message was unread
    if wasUnread then
        local state = Player(src).state
        state.telegramUnreadMessages = math.max(0, (state.telegramUnreadMessages or 0) - 1)
    end
end)

-- Legacy Callbacks (kept for compatibility)
RSGCore.Functions.CreateCallback('rsg-telegram:server:GetPlayers', function(source, cb)
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

-- Count telegrams for player
RSGCore.Functions.CreateCallback('rsg-telegram:server:getTelegramsAmount', function(source, cb)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if Player ~= nil then
        -- Count both: unread messages (picked up) AND unpicked post office messages
        local result = MySQL.prepare.await('SELECT COUNT(*) FROM telegrams WHERE citizenid = ? AND ((status = ? OR birdstatus = ?) OR (fromPostOffice = 1 AND pickedUp = 0))', {Player.PlayerData.citizenid, 0, 0})
        if result > 0 then
            cb(result)
        else
            cb(0)
        end
    end
end)

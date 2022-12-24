local RSGCore = exports['rsg-core']:GetCoreObject()

RSGCore.Functions.CreateCallback('rsg-telegram:server:getplayers', function(source, cb)
    exports.oxmysql:execute('SELECT * FROM players', {}, function(result)
        if result[1] then
            cb(result)
        else
            cb(nil)
        end
    end)
end)

-- add message to the database
RegisterServerEvent('rsg-telegram:server:sendmessage')
AddEventHandler('rsg-telegram:server:sendmessage', function(sender, sendername, citizenid, subject, message)
	local src = source
	local sentDate = os.date("%x")
	exports.oxmysql:execute('INSERT INTO telegrams (`citizenid`, `sender`, `sendername`, `subject`, `sentDate`, `message`) VALUES (?, ?, ?, ?, ?, ?);',{citizenid, sender, sendername, subject, sentDate, message})
	TriggerClientEvent('RSGCore:Notify', src, "telegram sent to : "..citizenid, 'primary')  
end)

-- check inbox
RegisterServerEvent('rsg-telegram:server:checkinbox')
AddEventHandler('rsg-telegram:server:checkinbox', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
	local citizenid = Player.PlayerData.citizenid
	local telenumber = Player.PlayerData.charinfo.telegram
	exports.oxmysql:execute('SELECT * FROM telegrams WHERE citizenid = ? ORDER BY id DESC', { citizenid }, function(result)
		local res = {}
		res['list'] = result or {}
		TriggerClientEvent('rsg-telegram:client:inboxlist', src, res)
	end)
end)

-- get messages from the database
RegisterServerEvent('rsg-telegram:server:getTelegrams')
AddEventHandler('rsg-telegram:server:getTelegrams', function(tid)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    local telegram = {}
    local result = MySQL.query.await('SELECT * FROM telegrams WHERE id = @id', { ['@id'] = tid })
	if result[1] ~= nil then
		telegram['citizenid'] = result[1]['citizenid']
		telegram['sender'] = result[1]['sender']
		telegram['sendername'] = result[1]['sendername']
		telegram['subject'] = result[1]['subject']
		telegram['sentDate'] = result[1]['sentDate']
		telegram['message'] = result[1]['message']
		MySQL.Async.execute('UPDATE telegrams SET status = 1 WHERE id = @id', { ['@id'] = tid })
		TriggerClientEvent('rsg-telegram:client:messageData', src, telegram)
	end
end)

-- delete message
RegisterServerEvent('rsg-telegram:server:DeleteTelegram')
AddEventHandler('rsg-telegram:server:DeleteTelegram', function(tid)
	local src = source
    local result = MySQL.query.await("SELECT * FROM telegrams WHERE id = @id", { ['@id'] = tid })
	if result[1] ~= nil then
		MySQL.Async.execute("DELETE FROM telegrams WHERE id = @id", { ["@id"] = tid })
		TriggerClientEvent('RSGCore:Notify', src, "telegram deleted!", 'primary')
		TriggerClientEvent('rsg-telegram:client:readmessages', src)
	else
		TriggerClientEvent('RSGCore:Notify', src, "failed to delete your message!", 'error')  
	end
end)

local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local sendCooldowns   = {} -- [citizenid] = os.time() of last send (survives relog)
local searchCooldowns = {} -- [src] = GetGameTimer() of last search
local SEARCH_THROTTLE = 750 -- ms between directory searches per player

---------------------------------
-- auto database setup
---------------------------------
local tables = {
    rsg_telegrams = {
        legacy = { 'rex_telegrams', 'telegrams' },
        columns = {
            { name = 'id',               def = 'INT(11) NOT NULL AUTO_INCREMENT' },
            { name = 'citizenid',        def = 'VARCHAR(50) NOT NULL' },
            { name = 'recipient_name',   def = 'VARCHAR(100) NOT NULL' },
            { name = 'sender_citizenid', def = 'VARCHAR(50) NOT NULL' },
            { name = 'sender_name',      def = 'VARCHAR(100) NOT NULL' },
            { name = 'subject',          def = 'VARCHAR(100) NOT NULL' },
            { name = 'message',          def = 'TEXT NOT NULL' },
            { name = 'is_read',          def = 'TINYINT(1) NOT NULL DEFAULT 0' },
            { name = 'sent_at',          def = 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP' },
        },
        extra = { 'PRIMARY KEY (`id`)', 'INDEX `idx_citizenid` (`citizenid`)' },
    },
    rsg_telegram_contacts = {
        legacy = { 'rex_telegram_contacts', 'telegram_contacts' },
        columns = {
            { name = 'id',                def = 'INT(11) NOT NULL AUTO_INCREMENT' },
            { name = 'citizenid',         def = 'VARCHAR(50) NOT NULL' },
            { name = 'contact_citizenid', def = 'VARCHAR(50) NOT NULL' },
            { name = 'contact_name',      def = 'VARCHAR(100) NOT NULL' },
            { name = 'nickname',          def = 'VARCHAR(50) NULL DEFAULT NULL' },
            { name = 'added_at',          def = 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP' },
        },
        extra = { 'PRIMARY KEY (`id`)', 'UNIQUE KEY `uniq_contact` (`citizenid`, `contact_citizenid`)' },
    },
}

local function dbLog(msg, colour)
    print(('[%s]%s %s^7'):format(GetCurrentResourceName(), colour or '^2', msg))
end

local function SetupTable(name, def)
    local exists = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { name })

    -- migrate data from the old table name if it exists
    if (not exists or exists == 0) and def.legacy then
        local legacy = type(def.legacy) == 'table' and def.legacy or { def.legacy }
        for _, oldName in ipairs(legacy) do
            local old = MySQL.scalar.await(
                'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { oldName })
            if old and old > 0 then
                MySQL.query.await(('RENAME TABLE `%s` TO `%s`'):format(oldName, name))
                dbLog(('Renamed table `%s` to `%s`'):format(oldName, name), '^3')
                exists = 1
                break
            end
        end
    end

    if not exists or exists == 0 then
        local cols = {}
        for _, c in ipairs(def.columns) do cols[#cols + 1] = ('`%s` %s'):format(c.name, c.def) end
        for _, e in ipairs(def.extra) do cols[#cols + 1] = e end
        MySQL.query.await(('CREATE TABLE `%s` (%s) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'):format(name, table.concat(cols, ', ')))
        dbLog(('Database table `%s` created'):format(name))
        return
    end

    local known = {}
    for _, c in ipairs(def.columns) do known[c.name] = true end

    local rows = MySQL.query.await([[
        SELECT column_name AS name, column_type AS ctype, is_nullable AS nullable,
               column_default AS dflt, extra AS extra
        FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ?
    ]], { name }) or {}

    local have = {}
    for _, r in ipairs(rows) do
        local cname = r.name or r.COLUMN_NAME
        if cname then
            have[cname:lower()] = true
            -- legacy NOT NULL columns without a default (from older telegram scripts) block inserts
            local nullable, extra = r.nullable or r.IS_NULLABLE, r.extra or r.EXTRA or ''
            local dflt = r.dflt or r.COLUMN_DEFAULT
            if not known[cname:lower()] and nullable == 'NO' and dflt == nil and not extra:find('auto_increment') then
                MySQL.query.await(('ALTER TABLE `%s` MODIFY `%s` %s NULL DEFAULT NULL'):format(name, cname, r.ctype or r.COLUMN_TYPE))
                dbLog(('Legacy column `%s`.`%s` made optional'):format(name, cname), '^3')
            end
        end
    end

    for _, c in ipairs(def.columns) do
        if not have[c.name] then
            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(name, c.name, c.def))
            dbLog(('Added missing column `%s`.`%s`'):format(name, c.name), '^3')
        end
    end

    if Config.Debug then dbLog(('Database table `%s` verified'):format(name)) end
end

MySQL.ready(function()
    if Config.AutoDatabase then
        for name, def in pairs(tables) do
            local ok, err = pcall(SetupTable, name, def)
            if not ok then dbLog(('Database setup failed for `%s`: %s'):format(name, tostring(err)), '^1') end
        end
    end
    if Config.PurgeReadAfterDays and Config.PurgeReadAfterDays > 0 then
        local removed = MySQL.update.await('DELETE FROM rsg_telegrams WHERE is_read = 1 AND sent_at < (NOW() - INTERVAL ? DAY)', { Config.PurgeReadAfterDays })
        if removed and removed > 0 then dbLog(('Purged %d old read telegrams'):format(removed)) end
    end
end)

---------------------------------
-- helpers
---------------------------------
local function fullName(charinfo)
    if type(charinfo) == 'string' then charinfo = json.decode(charinfo) end
    if type(charinfo) ~= 'table' then return locale('sv_unknown') end
    local name = ('%s %s'):format(charinfo.firstname or '', charinfo.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
    return name ~= '' and name or locale('sv_unknown')
end

local function notify(src, desc, ntype)
    TriggerClientEvent('ox_lib:notify', src, { title = locale('cl_title'), description = desc, type = ntype or 'inform', duration = 5000 })
end

-- trims, strips control chars (keeps newlines/tabs) and angle brackets, enforces length
local function sanitize(str, max)
    if type(str) ~= 'string' then return nil end
    str = str:gsub('[%z\1-\8\11\12\14-\31\127<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #str == 0 or utf8.len(str) == nil or utf8.len(str) > max then return nil end
    return str
end

local function validCid(cid)
    return type(cid) == 'string' and #cid > 0 and #cid <= 50 and cid:match('^[%w_%-]+$') ~= nil
end

local function isNearPostOffice(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    local range = Config.PromptDistance + 3.0
    for _, office in ipairs(Config.PostOffices) do
        if #(pos - office.coords) <= range then return true end
    end
    return false
end

---------------------------------
-- inbox
---------------------------------
lib.callback.register('rsg-telegram:server:getInbox', function(source)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not isNearPostOffice(source) then return {} end
    return MySQL.query.await(
        'SELECT id, sender_citizenid, sender_name, subject, message, is_read, UNIX_TIMESTAMP(sent_at) AS sent_at FROM rsg_telegrams WHERE citizenid = ? ORDER BY sent_at DESC, id DESC LIMIT ?',
        { Player.PlayerData.citizenid, Config.MaxInbox }
    ) or {}
end)

---------------------------------
-- recipient search (by name)
---------------------------------
lib.callback.register('rsg-telegram:server:searchRecipients', function(source, query)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or type(query) ~= 'string' then return {} end

    local now = GetGameTimer()
    if searchCooldowns[source] and now - searchCooldowns[source] < SEARCH_THROTTLE then return {} end
    searchCooldowns[source] = now

    query = query:gsub('[%%_<>\\]', ''):sub(1, 40)
    if #query < Config.SearchMinChars then return {} end

    local like = '%' .. query .. '%'
    local rows = MySQL.query.await([[
        SELECT citizenid, charinfo FROM players
        WHERE citizenid <> ?
          AND ( CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) LIKE ?
                OR citizenid = ? )
        LIMIT 10
    ]], { Player.PlayerData.citizenid, like, query }) or {}

    local results = {}
    for i = 1, #rows do
        results[i] = { citizenid = rows[i].citizenid, name = fullName(rows[i].charinfo) }
    end
    return results
end)

---------------------------------
-- send
---------------------------------
lib.callback.register('rsg-telegram:server:send', function(source, data)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or type(data) ~= 'table' then return false end
    if not isNearPostOffice(src) then return false end

    local senderCid = Player.PlayerData.citizenid
    local now = os.time()
    local last = sendCooldowns[senderCid]
    if last and now - last < Config.SendCooldown then
        notify(src, locale('sv_cooldown', Config.SendCooldown - (now - last)), 'error')
        return false
    end

    local subject = sanitize(data.subject, Config.MaxSubject)
    local message = sanitize(data.message, Config.MaxMessage)
    local target  = validCid(data.citizenid) and data.citizenid or nil
    if not subject or not message or not target then
        notify(src, locale('sv_invalid'), 'error')
        return false
    end

    if target == senderCid then
        notify(src, locale('sv_self'), 'error')
        return false
    end

    -- claim the cooldown slot before yielding on the DB, so parallel requests can't slip through
    sendCooldowns[senderCid] = now

    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { target })
    if not row then
        sendCooldowns[senderCid] = last
        notify(src, locale('sv_no_recipient'), 'error')
        return false
    end

    if Config.SendCost > 0 and not Player.Functions.RemoveMoney(Config.MoneyType, Config.SendCost, 'telegram-sent') then
        sendCooldowns[senderCid] = last
        notify(src, locale('sv_no_money', Config.SendCost), 'error')
        return false
    end

    local senderName    = fullName(Player.PlayerData.charinfo)
    local recipientName = fullName(row.charinfo)

    local function deliver()
        MySQL.insert.await(
            'INSERT INTO rsg_telegrams (citizenid, recipient_name, sender_citizenid, sender_name, subject, message) VALUES (?, ?, ?, ?, ?, ?)',
            { target, recipientName, senderCid, senderName, subject, message }
        )
        local Target = RSGCore.Functions.GetPlayerByCitizenId(target)
        if Target then
            TriggerClientEvent('rsg-telegram:client:newTelegram', Target.PlayerData.source, senderName)
        end
    end

    if Config.DeliveryDelay > 0 then
        SetTimeout(Config.DeliveryDelay * 1000, deliver)
    else
        deliver()
    end

    notify(src, locale('sv_sent'), 'success')
    return true
end)

---------------------------------
-- address book
---------------------------------
lib.callback.register('rsg-telegram:server:getContacts', function(source)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return {} end
    return MySQL.query.await(
        'SELECT contact_citizenid AS citizenid, contact_name AS name, nickname FROM rsg_telegram_contacts WHERE citizenid = ? ORDER BY COALESCE(nickname, contact_name) ASC',
        { Player.PlayerData.citizenid }
    ) or {}
end)

lib.callback.register('rsg-telegram:server:addContact', function(source, data)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or type(data) ~= 'table' or not validCid(data.citizenid) then return false end
    local owner = Player.PlayerData.citizenid
    if data.citizenid == owner then
        notify(source, locale('sv_self_contact'), 'error')
        return false
    end

    local existing = MySQL.scalar.await('SELECT 1 FROM rsg_telegram_contacts WHERE citizenid = ? AND contact_citizenid = ?', { owner, data.citizenid })
    if not existing then
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM rsg_telegram_contacts WHERE citizenid = ?', { owner }) or 0
        if count >= Config.MaxContacts then
            notify(source, locale('sv_contacts_full', Config.MaxContacts), 'error')
            return false
        end
    end

    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { data.citizenid })
    if not row then
        notify(source, locale('sv_no_recipient'), 'error')
        return false
    end

    local nickname = sanitize(data.nickname, 50)
    MySQL.insert.await(
        'INSERT INTO rsg_telegram_contacts (citizenid, contact_citizenid, contact_name, nickname) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE contact_name = VALUES(contact_name), nickname = VALUES(nickname)',
        { owner, data.citizenid, fullName(row.charinfo), nickname }
    )
    notify(source, locale(existing and 'sv_contact_updated' or 'sv_contact_added'), 'success')
    return true
end)

lib.callback.register('rsg-telegram:server:removeContact', function(source, citizenid)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not validCid(citizenid) then return false end
    local affected = MySQL.update.await('DELETE FROM rsg_telegram_contacts WHERE citizenid = ? AND contact_citizenid = ?', { Player.PlayerData.citizenid, citizenid })
    if affected and affected > 0 then
        notify(source, locale('sv_contact_removed'), 'inform')
        return true
    end
    return false
end)

---------------------------------
-- read / delete
---------------------------------
local function validId(id)
    return math.type(id) == 'integer' and id > 0
end

RegisterNetEvent('rsg-telegram:server:markRead', function(id)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not validId(id) then return end
    MySQL.update('UPDATE rsg_telegrams SET is_read = 1 WHERE id = ? AND citizenid = ? AND is_read = 0', { id, Player.PlayerData.citizenid })
end)

lib.callback.register('rsg-telegram:server:delete', function(source, id)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not validId(id) then return false end
    local affected = MySQL.update.await('DELETE FROM rsg_telegrams WHERE id = ? AND citizenid = ?', { id, Player.PlayerData.citizenid })
    if affected and affected > 0 then
        notify(source, locale('sv_deleted'), 'inform')
        return true
    end
    return false
end)

---------------------------------
-- unread reminder on login (server-side core event, not client-triggerable)
---------------------------------
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    if not Player or not Player.PlayerData then return end
    local src, cid = Player.PlayerData.source, Player.PlayerData.citizenid
    SetTimeout(5000, function()
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM rsg_telegrams WHERE citizenid = ? AND is_read = 0', { cid })
        if count and count > 0 and GetPlayerName(src) then
            notify(src, locale('sv_unread', count), 'inform')
        end
    end)
end)

AddEventHandler('playerDropped', function()
    searchCooldowns[source] = nil
end)

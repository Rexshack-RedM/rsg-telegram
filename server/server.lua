local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local sendCooldowns   = {} -- [citizenid] = os.time() of last send (survives relog)
local throttles       = {} -- [src] = { [action] = GetGameTimer() }
local SEARCH_THROTTLE = 500 -- ms between directory searches per player
local ACTION_THROTTLE = 750 -- ms between address book / delete actions per player

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
    TriggerClientEvent('RSGCore:Client:Notify', src, { title = locale('cl_title'), description = desc, type = ntype or 'inform', duration = 5000 })
end

-- per-player, per-action rate limit (true = allowed)
local function throttle(src, action, ms)
    local now = GetGameTimer()
    local t = throttles[src]
    if not t then t = {}; throttles[src] = t end
    if t[action] and now - t[action] < ms then return false end
    t[action] = now
    return true
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
-- inbox (telegrams with a future sent_at are still "in transit")
---------------------------------
RSGCore.Functions.CreateCallback('rsg-telegram:server:getInbox', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not isNearPostOffice(source) then return cb({}) end
    cb(MySQL.query.await(
        'SELECT id, sender_citizenid, sender_name, subject, message, is_read, UNIX_TIMESTAMP(sent_at) AS sent_at FROM rsg_telegrams WHERE citizenid = ? AND sent_at <= NOW() ORDER BY sent_at DESC, id DESC LIMIT ?',
        { Player.PlayerData.citizenid, Config.MaxInbox }
    ) or {})
end)

---------------------------------
-- recipient search (by name or citizen id)
---------------------------------
RSGCore.Functions.CreateCallback('rsg-telegram:server:searchRecipients', function(source, cb, query)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or type(query) ~= 'string' or not isNearPostOffice(source) then return cb({}) end
    -- false tells the UI "throttled, keep what you have" instead of "no results"
    if not throttle(source, 'search', SEARCH_THROTTLE) then return cb(false) end

    query = query:gsub('[%%_<>\\]', ''):sub(1, 40)
    if #query < Config.SearchMinChars then return cb({}) end

    local rows = MySQL.query.await([[
        SELECT citizenid, charinfo FROM players
        WHERE citizenid <> ?
          AND ( CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) LIKE ?
                OR citizenid = ? )
        LIMIT 10
    ]], { Player.PlayerData.citizenid, '%' .. query .. '%', query }) or {}

    local results = {}
    for i = 1, #rows do
        results[i] = { citizenid = rows[i].citizenid, name = fullName(rows[i].charinfo) }
    end
    cb(results)
end)

---------------------------------
-- send
---------------------------------
RSGCore.Functions.CreateCallback('rsg-telegram:server:send', function(source, cb, data)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or type(data) ~= 'table' or not isNearPostOffice(src) then return cb(false) end

    local senderCid = Player.PlayerData.citizenid
    local now = os.time()
    local last = sendCooldowns[senderCid]
    if last and now - last < Config.SendCooldown then
        notify(src, locale('sv_cooldown', Config.SendCooldown - (now - last)), 'error')
        return cb(false)
    end

    local subject = sanitize(data.subject, Config.MaxSubject)
    local message = sanitize(data.message, Config.MaxMessage)
    local target  = validCid(data.citizenid) and data.citizenid or nil
    if not subject or not message or not target then
        notify(src, locale('sv_invalid'), 'error')
        return cb(false)
    end
    if target == senderCid then
        notify(src, locale('sv_self'), 'error')
        return cb(false)
    end

    -- claim the cooldown slot before yielding on the DB, so parallel requests can't slip through
    sendCooldowns[senderCid] = now

    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { target })
    if not row then
        sendCooldowns[senderCid] = last
        notify(src, locale('sv_no_recipient'), 'error')
        return cb(false)
    end

    if Config.SendCost > 0 and not Player.Functions.RemoveMoney(Config.MoneyType, Config.SendCost, 'telegram-sent') then
        sendCooldowns[senderCid] = last
        notify(src, locale('sv_no_money', Config.SendCost), 'error')
        return cb(false)
    end

    local senderName = fullName(Player.PlayerData.charinfo)
    local delay = math.max(0, math.floor(Config.DeliveryDelay or 0))

    -- stored immediately (paid telegrams survive restarts); a future sent_at hides it until it "arrives"
    local id = MySQL.insert.await(
        'INSERT INTO rsg_telegrams (citizenid, recipient_name, sender_citizenid, sender_name, subject, message, sent_at) VALUES (?, ?, ?, ?, ?, ?, NOW() + INTERVAL ? SECOND)',
        { target, fullName(row.charinfo), senderCid, senderName, subject, message, delay }
    )
    if not id then
        if Config.SendCost > 0 then Player.Functions.AddMoney(Config.MoneyType, Config.SendCost, 'telegram-refund') end
        sendCooldowns[senderCid] = last
        notify(src, locale('sv_invalid'), 'error')
        return cb(false)
    end

    SetTimeout(delay * 1000, function()
        local Target = RSGCore.Functions.GetPlayerByCitizenId(target)
        if Target then TriggerClientEvent('rsg-telegram:client:newTelegram', Target.PlayerData.source, senderName) end
    end)

    notify(src, locale('sv_sent'), 'success')
    cb(true)
end)

---------------------------------
-- address book
---------------------------------
RSGCore.Functions.CreateCallback('rsg-telegram:server:getContacts', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not isNearPostOffice(source) then return cb({}) end
    cb(MySQL.query.await(
        'SELECT contact_citizenid AS citizenid, contact_name AS name, nickname FROM rsg_telegram_contacts WHERE citizenid = ? ORDER BY COALESCE(nickname, contact_name) ASC',
        { Player.PlayerData.citizenid }
    ) or {})
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:addContact', function(source, cb, data)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or type(data) ~= 'table' or not validCid(data.citizenid) or not isNearPostOffice(source) then return cb(false) end
    if not throttle(source, 'contact', ACTION_THROTTLE) then return cb(false) end

    local owner, contact = Player.PlayerData.citizenid, data.citizenid
    if contact == owner then
        notify(source, locale('sv_self_contact'), 'error')
        return cb(false)
    end

    local existing = MySQL.scalar.await('SELECT 1 FROM rsg_telegram_contacts WHERE citizenid = ? AND contact_citizenid = ?', { owner, contact })
    if not existing then
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM rsg_telegram_contacts WHERE citizenid = ?', { owner }) or 0
        if count >= Config.MaxContacts then
            notify(source, locale('sv_contacts_full', Config.MaxContacts), 'error')
            return cb(false)
        end
    end

    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { contact })
    if not row then
        notify(source, locale('sv_no_recipient'), 'error')
        return cb(false)
    end

    MySQL.insert.await(
        'INSERT INTO rsg_telegram_contacts (citizenid, contact_citizenid, contact_name, nickname) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE contact_name = VALUES(contact_name), nickname = VALUES(nickname)',
        { owner, contact, fullName(row.charinfo), sanitize(data.nickname, 50) }
    )
    notify(source, locale(existing and 'sv_contact_updated' or 'sv_contact_added'), 'success')
    cb(true)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:removeContact', function(source, cb, citizenid)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not validCid(citizenid) or not throttle(source, 'contact', ACTION_THROTTLE) then return cb(false) end
    local affected = MySQL.update.await('DELETE FROM rsg_telegram_contacts WHERE citizenid = ? AND contact_citizenid = ?', { Player.PlayerData.citizenid, citizenid })
    if affected and affected > 0 then
        notify(source, locale('sv_contact_removed'), 'inform')
        return cb(true)
    end
    cb(false)
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

RSGCore.Functions.CreateCallback('rsg-telegram:server:delete', function(source, cb, id)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not validId(id) or not throttle(source, 'delete', ACTION_THROTTLE) then return cb(false) end
    local affected = MySQL.update.await('DELETE FROM rsg_telegrams WHERE id = ? AND citizenid = ? AND sent_at <= NOW()', { id, Player.PlayerData.citizenid })
    if affected and affected > 0 then
        notify(source, locale('sv_deleted'), 'inform')
        return cb(true)
    end
    cb(false)
end)

---------------------------------
-- unread reminder on login (server-side core event, not client-triggerable)
---------------------------------
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    if not Player or not Player.PlayerData then return end
    local src, cid = Player.PlayerData.source, Player.PlayerData.citizenid
    SetTimeout(5000, function()
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM rsg_telegrams WHERE citizenid = ? AND is_read = 0 AND sent_at <= NOW()', { cid })
        if count and count > 0 and GetPlayerName(src) then
            notify(src, locale('sv_unread', count), 'inform')
        end
    end)
end)

AddEventHandler('playerDropped', function()
    throttles[source] = nil
end)

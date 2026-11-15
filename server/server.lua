local RSGCore = exports['rsg-core']:GetCoreObject()

local sendCooldowns   = {} -- [citizenid] = os.time() of last send (survives relog)
local throttles       = {} -- [src] = { [action] = GetGameTimer() }
local SEARCH_THROTTLE = 500 -- ms between directory searches per player
local ACTION_THROTTLE = 750 -- ms between address book / delete actions per player
local READ_THROTTLE   = 400 -- ms between inbox / address book loads per player

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
            { name = 'batch',            def = 'VARCHAR(40) NULL DEFAULT NULL' },
            { name = 'has_attachment',   def = 'TINYINT(1) NOT NULL DEFAULT 0' },
            { name = 'attachment',       def = 'TEXT NULL DEFAULT NULL' },
        },
        extra = { 'PRIMARY KEY (`id`)', 'INDEX `idx_citizenid` (`citizenid`)' },
        indexes = { { name = 'idx_sender', def = 'INDEX `idx_sender` (`sender_citizenid`)' } }, -- Sent tab
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
    rsg_telegram_blocks = {
        columns = {
            { name = 'id',                def = 'INT(11) NOT NULL AUTO_INCREMENT' },
            { name = 'citizenid',         def = 'VARCHAR(50) NOT NULL' },
            { name = 'blocked_citizenid', def = 'VARCHAR(50) NOT NULL' },
            { name = 'blocked_name',      def = 'VARCHAR(100) NOT NULL' },
            { name = 'added_at',          def = 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP' },
        },
        extra = { 'PRIMARY KEY (`id`)', 'UNIQUE KEY `uniq_block` (`citizenid`, `blocked_citizenid`)' },
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
        for _, ix in ipairs(def.indexes or {}) do cols[#cols + 1] = ix.def end
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

    for _, ix in ipairs(def.indexes or {}) do
        local hasIndex = MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ?', { name, ix.name })
        if not hasIndex or hasIndex == 0 then
            MySQL.query.await(('ALTER TABLE `%s` ADD %s'):format(name, ix.def))
            dbLog(('Added missing index `%s`.`%s`'):format(name, ix.name), '^3')
        end
    end

    if Config.Debug then dbLog(('Database table `%s` verified'):format(name)) end
end

local PURGE_INTERVAL = 6 * 60 * 60 * 1000 -- ms between old-telegram purges while the server is running
local SYSTEM_CID     = 'SYSTEM'           -- sender id of telegrams sent by scripts without a character
local AT             = Config.Attachments or { Enabled = false }

local jobColumnOk = false -- players.job exists (needed for job addresses)
local access = {}         -- [src] = os.time() until which the UI may be used away from a post office (OpenTelegrams export)

local function purgeOld()
    -- telegrams that still carry an unclaimed attachment are never purged
    local readDays   = Config.PurgeReadAfterDays or 0
    local unreadDays = Config.PurgeUnreadAfterDays or 0
    if readDays > 0 then
        local removed = MySQL.update.await('DELETE FROM rsg_telegrams WHERE is_read = 1 AND attachment IS NULL AND sent_at < (NOW() - INTERVAL ? DAY)', { readDays })
        if removed and removed > 0 then dbLog(('Purged %d old read telegrams'):format(removed)) end
    end
    if unreadDays > 0 then
        local removed = MySQL.update.await('DELETE FROM rsg_telegrams WHERE is_read = 0 AND attachment IS NULL AND sent_at < (NOW() - INTERVAL ? DAY)', { unreadDays })
        if removed and removed > 0 then dbLog(('Purged %d old unread telegrams'):format(removed)) end
    end
end

MySQL.ready(function()
    if Config.AutoDatabase then
        for name, def in pairs(tables) do
            local ok, err = pcall(SetupTable, name, def)
            if not ok then dbLog(('Database setup failed for `%s`: %s'):format(name, tostring(err)), '^1') end
        end
    end

    local ok, count = pcall(MySQL.scalar.await,
        "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = 'players' AND column_name = 'job'")
    jobColumnOk = ok and (count or 0) > 0
    if #(Config.JobAddresses or {}) > 0 and not jobColumnOk then
        dbLog('Config.JobAddresses is set but the players table has no `job` column - job addresses are disabled', '^3')
    end

    local purged, err = pcall(purgeOld)
    if not purged then dbLog(('Purge failed: %s'):format(tostring(err)), '^1') end
end)

-- keep purging on long-running servers (it used to only run on resource start)
CreateThread(function()
    while true do
        Wait(PURGE_INTERVAL)
        local ok, err = pcall(purgeOld)
        if not ok then dbLog(('Purge failed: %s'):format(tostring(err)), '^1') end
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

-- trims, strips control chars (keeps newlines/tabs), angle brackets, zero-width and bidi-override
-- characters (text spoofing), and enforces length
local function sanitize(str, max)
    if type(str) ~= 'string' then return nil end
    str = str:gsub('[%z\1-\8\11\12\14-\31\127<>]', '')
             :gsub('\226\128[\139-\143\170-\174]', '') -- U+200B-200F, U+202A-202E
             :gsub('\226\129[\166-\169]', '')          -- U+2066-2069
             :gsub('^%s+', ''):gsub('%s+$', '')
    if #str == 0 or utf8.len(str) == nil or utf8.len(str) > max then return nil end
    return str
end

local function validCid(cid)
    return type(cid) == 'string' and #cid > 0 and #cid <= 50 and cid:match('^[%w_%-]+$') ~= nil
end

local function validId(id)
    return math.type(id) == 'integer' and id > 0
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

-- at a post office, or opened remotely by another script through the OpenTelegrams export
local function canUseUI(src)
    if isNearPostOffice(src) then return true end
    local untilTime = access[src]
    return untilTime ~= nil and untilTime > os.time()
end

local function grantAccess(src, seconds)
    access[src] = os.time() + math.max(1, math.floor(tonumber(seconds) or 900))
end

local function receipts()
    return Config.Receipts or {}
end

-- job addresses by job name
local jobAddresses = {}
for _, a in ipairs(Config.JobAddresses or {}) do
    if type(a) == 'table' and type(a.job) == 'string' and type(a.label) == 'string' then jobAddresses[a.job] = a end
end

---------------------------------
-- attachments (cash + items travel with a telegram; taken from the sender at send time, collected by the recipient)
---------------------------------
local blockedItems, allowedItems = {}, nil
for _, n in ipairs(AT.BlockedItems or {}) do blockedItems[n] = true end
if AT.AllowedItems and #AT.AllowedItems > 0 then
    allowedItems = {}
    for _, n in ipairs(AT.AllowedItems) do allowedItems[n] = true end
end

local function itemAttachable(name)
    local def = RSGCore.Shared.Items[name]
    if not def or def.unique or def.type == 'weapon' or blockedItems[name] then return false end
    if allowedItems and not allowedItems[name] then return false end
    return true
end

-- Validates the shape of an attachment table. Returns the cleaned table, nil (nothing attached) or false (invalid).
-- enforce = apply the configured limits (players); scripts using the API are trusted with the limits but not the shape.
local function normaliseAttachment(raw, enforce)
    if raw == nil then return nil end
    if type(raw) ~= 'table' then return false end
    local att = { items = {} }

    if raw.cash ~= nil then
        local cash = tonumber(raw.cash)
        if not cash or cash ~= cash or cash == math.huge or cash < 0 then return false end
        cash = math.floor(cash * 100 + 0.5) / 100
        if enforce and cash > (AT.MaxCash or 0) then return false end
        if cash > 0 then att.cash = cash end
    end

    if raw.items ~= nil then
        if type(raw.items) ~= 'table' then return false end
        local seen = {}
        for i = 1, #raw.items do
            local it = raw.items[i]
            if type(it) ~= 'table' or type(it.name) ~= 'string' or seen[it.name] then return false end
            local amount = math.tointeger(tonumber(it.amount))
            if not amount or amount < 1 or not RSGCore.Shared.Items[it.name] then return false end
            if enforce and (amount > (AT.MaxItemAmount or 0) or not itemAttachable(it.name)) then return false end
            seen[it.name] = true
            att.items[#att.items + 1] = { name = it.name, amount = amount }
        end
        if enforce and #att.items > (AT.MaxItems or 0) then return false end
    end

    if not att.cash and #att.items == 0 then return nil end
    return att
end

-- player attachment: validates shape, limits, and that the player actually has everything. Returns att, errorLocaleKey
local function checkAttachment(src, Player, raw)
    if raw == nil then return nil end
    if not AT.Enabled then return nil, 'sv_attach_invalid' end
    local att = normaliseAttachment(raw, true)
    if att == false then return nil, 'sv_attach_invalid' end
    if att == nil then return nil end
    if att.cash and Player.Functions.GetMoney('cash') < att.cash then return nil, 'sv_attach_no_cash' end
    for _, it in ipairs(att.items) do
        if not exports['rsg-inventory']:HasItem(src, it.name, it.amount) then return nil, 'sv_attach_no_item' end
    end
    return att
end

local function giveBack(src, Player, att)
    if att.cash then Player.Functions.AddMoney('cash', att.cash, 'telegram-attachment-refund') end
    for _, it in ipairs(att.items) do
        exports['rsg-inventory']:AddItem(src, it.name, it.amount, nil, nil, 'telegram-attachment-refund')
    end
end

-- takes everything out of the player's hands; puts it back and returns false if any part fails
local function takeAttachment(src, Player, att)
    local taken = { items = {} }
    if att.cash then
        if not Player.Functions.RemoveMoney('cash', att.cash, 'telegram-attachment') then return false end
        taken.cash = att.cash
    end
    for _, it in ipairs(att.items) do
        if exports['rsg-inventory']:RemoveItem(src, it.name, it.amount, nil, 'telegram-attachment') then
            taken.items[#taken.items + 1] = it
        else
            giveBack(src, Player, taken)
            return false
        end
    end
    return true
end

local function decodeAttachment(raw)
    if type(raw) ~= 'string' or raw == '' then return nil end
    local ok, att = pcall(json.decode, raw)
    if not ok or type(att) ~= 'table' then return nil end
    att.items = type(att.items) == 'table' and att.items or {}
    for _, it in ipairs(att.items) do
        local def = RSGCore.Shared.Items[it.name]
        it.label = def and def.label or it.name
    end
    return att
end

---------------------------------
-- data layer (used by the UI callbacks below and by the public API in server/api.lua)
---------------------------------
local function getCharName(cid)
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { cid })
    return row and fullName(row.charinfo) or nil
end

-- telegrams with a future sent_at are still "in transit" and never listed
local function getInbox(cid, limit, unreadOnly)
    local sql = 'SELECT id, sender_citizenid, sender_name, subject, message, is_read, has_attachment, attachment, UNIX_TIMESTAMP(sent_at) AS sent_at FROM rsg_telegrams WHERE citizenid = ? AND sent_at <= NOW()'
        .. (unreadOnly and ' AND is_read = 0' or '')
        .. ' ORDER BY sent_at DESC, id DESC LIMIT ?'
    local rows = MySQL.query.await(sql, { cid, limit }) or {}
    for i = 1, #rows do rows[i].attachment = decodeAttachment(rows[i].attachment) end
    return rows
end

-- telegrams this character sent, one row per send (a job-address send is one row), with delivery/read counts
local function getSent(cid, limit)
    local showRead = receipts().Enabled ~= false
    local rows = MySQL.query.await([[
        SELECT MIN(id) AS id, MAX(subject) AS subject, MAX(message) AS message, MAX(recipient_name) AS recipient_name,
               UNIX_TIMESTAMP(MIN(sent_at)) AS sent_at, COUNT(*) AS recipients,
               CAST(SUM(sent_at <= NOW()) AS UNSIGNED) AS delivered,
               CAST(SUM(is_read) AS UNSIGNED) AS read_count,
               MAX(has_attachment) AS has_attachment,
               CAST(SUM(attachment IS NOT NULL) AS UNSIGNED) AS unclaimed
        FROM rsg_telegrams WHERE sender_citizenid = ?
        GROUP BY COALESCE(batch, CAST(id AS CHAR))
        ORDER BY MIN(sent_at) DESC, MIN(id) DESC LIMIT ?
    ]], { cid, limit }) or {}
    if not showRead then
        for i = 1, #rows do rows[i].read_count = 0 end
    end
    return rows
end

local function getUnreadCount(cid)
    return MySQL.scalar.await('SELECT COUNT(*) FROM rsg_telegrams WHERE citizenid = ? AND is_read = 0 AND sent_at <= NOW()', { cid }) or 0
end

-- id = nil marks everything read; returns how many rows changed
local function markRead(cid, id)
    if id then
        return MySQL.update.await('UPDATE rsg_telegrams SET is_read = 1 WHERE id = ? AND citizenid = ? AND is_read = 0', { id, cid }) or 0
    end
    return MySQL.update.await('UPDATE rsg_telegrams SET is_read = 1 WHERE citizenid = ? AND is_read = 0', { cid }) or 0
end

-- returns true, or false + 'attachment' when it still carries something to collect
local function deleteTelegram(cid, id)
    local affected = MySQL.update.await('DELETE FROM rsg_telegrams WHERE id = ? AND citizenid = ? AND sent_at <= NOW() AND attachment IS NULL', { id, cid })
    if affected and affected > 0 then return true end
    local held = MySQL.scalar.await('SELECT 1 FROM rsg_telegrams WHERE id = ? AND citizenid = ? AND attachment IS NOT NULL', { id, cid })
    return false, held and 'attachment' or nil
end

-- destroys every delivered, read telegram that has nothing left to collect; returns the count
local function deleteRead(cid)
    return MySQL.update.await('DELETE FROM rsg_telegrams WHERE citizenid = ? AND is_read = 1 AND sent_at <= NOW() AND attachment IS NULL', { cid }) or 0
end

local function getContacts(cid)
    return MySQL.query.await(
        'SELECT contact_citizenid AS citizenid, contact_name AS name, nickname FROM rsg_telegram_contacts WHERE citizenid = ? ORDER BY COALESCE(nickname, contact_name) ASC',
        { cid }
    ) or {}
end

-- returns true, 'added' | 'updated'   or   false, 'self' | 'contacts_full' | 'not_found'
local function addContact(owner, contact, nickname)
    if contact == owner then return false, 'self' end

    local existing = MySQL.scalar.await('SELECT 1 FROM rsg_telegram_contacts WHERE citizenid = ? AND contact_citizenid = ?', { owner, contact })
    if not existing then
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM rsg_telegram_contacts WHERE citizenid = ?', { owner }) or 0
        if count >= Config.MaxContacts then return false, 'contacts_full' end
    end

    local name = getCharName(contact)
    if not name then return false, 'not_found' end

    nickname = sanitize(nickname, 50)
    if nickname then
        MySQL.insert.await(
            'INSERT INTO rsg_telegram_contacts (citizenid, contact_citizenid, contact_name, nickname) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE contact_name = VALUES(contact_name), nickname = VALUES(nickname)',
            { owner, contact, name, nickname }
        )
    else
        MySQL.insert.await(
            'INSERT INTO rsg_telegram_contacts (citizenid, contact_citizenid, contact_name, nickname) VALUES (?, ?, ?, NULL) ON DUPLICATE KEY UPDATE contact_name = VALUES(contact_name), nickname = NULL',
            { owner, contact, name }
        )
    end
    return true, existing and 'updated' or 'added'
end

local function removeContact(owner, contact)
    local affected = MySQL.update.await('DELETE FROM rsg_telegram_contacts WHERE citizenid = ? AND contact_citizenid = ?', { owner, contact })
    return affected ~= nil and affected > 0
end

-- block list: `owner` no longer receives telegrams from `blocked` (the sender is never told)
local function isBlocked(owner, sender)
    return MySQL.scalar.await('SELECT 1 FROM rsg_telegram_blocks WHERE citizenid = ? AND blocked_citizenid = ?', { owner, sender }) ~= nil
end

local function getBlocked(cid)
    return MySQL.query.await('SELECT blocked_citizenid AS citizenid, blocked_name AS name FROM rsg_telegram_blocks WHERE citizenid = ? ORDER BY blocked_name ASC', { cid }) or {}
end

-- returns true, 'added' | 'already'   or   false, 'self' | 'blocks_full' | 'not_found'
local function addBlock(owner, target)
    if target == owner then return false, 'self' end
    if isBlocked(owner, target) then return true, 'already' end
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM rsg_telegram_blocks WHERE citizenid = ?', { owner }) or 0
    if count >= (Config.MaxBlocked or 100) then return false, 'blocks_full' end
    local name = getCharName(target)
    if not name then return false, 'not_found' end
    MySQL.insert.await('INSERT INTO rsg_telegram_blocks (citizenid, blocked_citizenid, blocked_name) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE blocked_name = VALUES(blocked_name)', { owner, target, name })
    return true, 'added'
end

local function removeBlock(owner, target)
    local affected = MySQL.update.await('DELETE FROM rsg_telegram_blocks WHERE citizenid = ? AND blocked_citizenid = ?', { owner, target })
    return affected ~= nil and affected > 0
end

-- characters that currently hold `job`: online players (including secondary multi-job jobs) plus
-- everyone whose active job is `job` in the database. Never includes `excludeCid`.
local function getJobMembers(job, excludeCid)
    local members, seen = {}, { [excludeCid] = true }
    local limit = Config.MaxJobRecipients or 25

    for _, P in pairs(RSGCore.Functions.GetRSGPlayers()) do
        local cid = P.PlayerData and P.PlayerData.citizenid
        if cid and not seen[cid] and #members < limit then
            local ok, held = pcall(function() return exports['rsg-core']:HasPlayerJob(P.PlayerData.source, job) end)
            if (ok and held) or (P.PlayerData.job and P.PlayerData.job.name == job) then
                seen[cid] = true
                members[#members + 1] = { citizenid = cid, name = fullName(P.PlayerData.charinfo) }
            end
        end
    end

    if jobColumnOk and #members < limit then
        local rows = MySQL.query.await(
            "SELECT citizenid, charinfo FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ? AND citizenid <> ? LIMIT ?",
            { job, excludeCid, limit }
        ) or {}
        for i = 1, #rows do
            if not seen[rows[i].citizenid] and #members < limit then
                seen[rows[i].citizenid] = true
                members[#members + 1] = { citizenid = rows[i].citizenid, name = fullName(rows[i].charinfo) }
            end
        end
    end
    return members
end

-- stores a telegram and schedules its arrival. Returns the new id, or nil if the insert failed.
-- Stored immediately (paid telegrams survive restarts); a future sent_at hides it until it "arrives".
-- extra = { batch = 'id shared by every copy of one send', attachment = '<json>' }
local function storeTelegram(senderCid, senderName, target, targetName, subject, message, delay, silent, extra)
    delay = math.max(0, math.floor(tonumber(delay) or 0))
    extra = extra or {}

    local cols = { 'citizenid', 'recipient_name', 'sender_citizenid', 'sender_name', 'subject', 'message' }
    local vals = { target, targetName, senderCid, senderName, subject, message }
    if extra.batch then
        cols[#cols + 1] = 'batch';          vals[#vals + 1] = extra.batch
    end
    if extra.attachment then
        cols[#cols + 1] = 'has_attachment'; vals[#vals + 1] = 1
        cols[#cols + 1] = 'attachment';     vals[#vals + 1] = extra.attachment
    end
    vals[#vals + 1] = delay
    local id = MySQL.insert.await(
        ('INSERT INTO rsg_telegrams (%s, sent_at) VALUES (%sNOW() + INTERVAL ? SECOND)'):format(table.concat(cols, ', '), ('?, '):rep(#cols)),
        vals
    )
    if not id then return nil end

    -- cap what a single character can hold (stops inbox flooding / table bloat); oldest go first,
    -- telegrams with something left to collect are never trimmed
    local cap = Config.MaxStoredPerPlayer or 0
    if cap > 0 then
        MySQL.update(
            'DELETE FROM rsg_telegrams WHERE citizenid = ? AND attachment IS NULL AND id NOT IN (SELECT id FROM (SELECT id FROM rsg_telegrams WHERE citizenid = ? ORDER BY sent_at DESC, id DESC LIMIT ?) AS keep)',
            { target, target, cap }
        )
    end

    local info = {
        id = id, recipient = target, recipientName = targetName,
        sender = senderCid, senderName = senderName, subject = subject, delay = delay,
        hasAttachment = extra.attachment ~= nil,
    }
    TriggerEvent('rsg-telegram:server:telegramSent', info)

    SetTimeout(delay * 1000, function()
        if not silent then
            local Target = RSGCore.Functions.GetPlayerByCitizenId(target)
            if Target then TriggerClientEvent('rsg-telegram:client:newTelegram', Target.PlayerData.source, senderName) end
        end
        if receipts().Enabled and receipts().NotifyDelivered and not extra.batch and senderCid ~= SYSTEM_CID then
            local Sender = RSGCore.Functions.GetPlayerByCitizenId(senderCid)
            if Sender then notify(Sender.PlayerData.source, locale('sv_receipt_delivered', targetName)) end
        end
        TriggerEvent('rsg-telegram:server:telegramDelivered', info)
    end)

    return id
end

-- moves the attachment of one of the player's own telegrams into their pockets.
-- returns true + the part that did not fit (or nil)   /   false + 'none' | 'full'
local function claimAttachment(src, Player, id)
    local cid = Player.PlayerData.citizenid
    local row = MySQL.single.await('SELECT attachment FROM rsg_telegrams WHERE id = ? AND citizenid = ? AND sent_at <= NOW() AND attachment IS NOT NULL', { id, cid })
    local att = row and decodeAttachment(row.attachment)
    if not att then return false, 'none' end

    for _, it in ipairs(att.items) do
        if not exports['rsg-inventory']:CanAddItem(src, it.name, it.amount) then return false, 'full' end
    end

    -- claim atomically first, so a double click / parallel request can never hand it out twice
    local claimed = MySQL.update.await('UPDATE rsg_telegrams SET attachment = NULL WHERE id = ? AND citizenid = ? AND attachment IS NOT NULL', { id, cid })
    if not claimed or claimed < 1 then return false, 'none' end

    if att.cash and att.cash > 0 then Player.Functions.AddMoney('cash', att.cash, 'telegram-attachment') end
    local leftover = { items = {} }
    for _, it in ipairs(att.items) do
        if not exports['rsg-inventory']:AddItem(src, it.name, it.amount, nil, nil, 'telegram-attachment') then
            leftover.items[#leftover.items + 1] = { name = it.name, amount = it.amount }
        end
    end
    if #leftover.items > 0 then
        -- whatever did not fit stays on the telegram to collect later
        local encoded = json.encode(leftover)
        MySQL.update('UPDATE rsg_telegrams SET attachment = ? WHERE id = ? AND citizenid = ?', { encoded, id, cid })
        return true, decodeAttachment(encoded)
    end
    return true, nil
end

-- shared with server/api.lua (loaded after this file)
TelegramInternal = {
    SYSTEM_CID = SYSTEM_CID,
    fullName = fullName, sanitize = sanitize, validCid = validCid, validId = validId,
    getCharName = getCharName, getInbox = getInbox, getSent = getSent, getUnreadCount = getUnreadCount,
    markRead = markRead, deleteTelegram = deleteTelegram, deleteRead = deleteRead,
    getContacts = getContacts, addContact = addContact, removeContact = removeContact,
    isBlocked = isBlocked, getBlocked = getBlocked, addBlock = addBlock, removeBlock = removeBlock,
    normaliseAttachment = normaliseAttachment,
    grantAccess = grantAccess,
    store = storeTelegram,
}

---------------------------------
-- inbox / sent
---------------------------------
-- callbacks answer `false` when throttled so the UI keeps what it already shows
RSGCore.Functions.CreateCallback('rsg-telegram:server:getInbox', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not canUseUI(source) then return cb({}) end
    if not throttle(source, 'inbox', READ_THROTTLE) then return cb(false) end
    cb(getInbox(Player.PlayerData.citizenid, Config.MaxInbox))
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:getSent', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not canUseUI(source) then return cb({}) end
    if not throttle(source, 'sent', READ_THROTTLE) then return cb(false) end
    cb(getSent(Player.PlayerData.citizenid, Config.MaxSent or 50))
end)

---------------------------------
-- recipient search (by name, optionally by citizen id)
---------------------------------
RSGCore.Functions.CreateCallback('rsg-telegram:server:searchRecipients', function(source, cb, query)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or type(query) ~= 'string' or not Config.DirectorySearch or not canUseUI(source) then return cb({}) end
    if not throttle(source, 'search', SEARCH_THROTTLE) then return cb(false) end

    query = query:gsub('[%%_<>\\]', ''):sub(1, 40)
    if #query < Config.SearchMinChars then return cb({}) end

    local sql = [[
        SELECT citizenid, charinfo FROM players
        WHERE citizenid <> ?
          AND ( CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) LIKE ?%s )
        LIMIT 10
    ]]
    local params = { Player.PlayerData.citizenid, '%' .. query .. '%' }
    if Config.SearchByCitizenId then
        sql = sql:format(' OR citizenid = ?')
        params[#params + 1] = query
    else
        sql = sql:format('')
    end

    local rows = MySQL.query.await(sql, params) or {}
    local results = {}
    for i = 1, #rows do
        results[i] = { citizenid = rows[i].citizenid, name = fullName(rows[i].charinfo) }
    end
    cb(results)
end)

---------------------------------
-- what the player could attach (UI convenience only - everything is re-checked when sending)
---------------------------------
RSGCore.Functions.CreateCallback('rsg-telegram:server:getAttachables', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not AT.Enabled or not canUseUI(source) then return cb({ cash = 0, items = {} }) end
    if not throttle(source, 'attach', READ_THROTTLE) then return cb(false) end

    local totals, order = {}, {}
    for _, item in pairs(Player.PlayerData.items or {}) do
        if type(item) == 'table' and item.name and itemAttachable(item.name) then
            if not totals[item.name] then
                totals[item.name] = 0
                order[#order + 1] = item.name
            end
            totals[item.name] = totals[item.name] + (tonumber(item.amount) or 0)
        end
    end
    local items = {}
    for _, name in ipairs(order) do
        if totals[name] > 0 then
            items[#items + 1] = { name = name, label = RSGCore.Shared.Items[name].label or name, amount = totals[name] }
        end
    end
    table.sort(items, function(a, b) return a.label < b.label end)
    cb({ cash = Player.Functions.GetMoney('cash'), items = items })
end)

---------------------------------
-- send
---------------------------------
local function newBatch()
    return ('%d%d'):format(os.time(), math.random(100000, 999999))
end

RSGCore.Functions.CreateCallback('rsg-telegram:server:send', function(source, cb, data)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or type(data) ~= 'table' or not canUseUI(src) then return cb(false) end

    local senderCid = Player.PlayerData.citizenid
    local now = os.time()
    local last = sendCooldowns[senderCid]
    if last and now - last < Config.SendCooldown then
        notify(src, locale('sv_cooldown', Config.SendCooldown - (now - last)), 'error')
        return cb(false)
    end

    local subject = sanitize(data.subject, Config.MaxSubject)
    local message = sanitize(data.message, Config.MaxMessage)
    -- addressed to a job office (from config only, never a client-chosen job) or to one character
    local office = data.job ~= nil and jobColumnOk and jobAddresses[data.job] or nil
    local target = data.job == nil and validCid(data.citizenid) and data.citizenid or nil
    if not subject or not message or (not office and not target) then
        notify(src, locale('sv_invalid'), 'error')
        return cb(false)
    end
    if target == senderCid then
        notify(src, locale('sv_self'), 'error')
        return cb(false)
    end

    local att, attError = checkAttachment(src, Player, data.attachment)
    if not attError and att and office then attError = 'sv_attach_invalid' end -- parcels go to people, not offices
    if attError then
        notify(src, locale(attError), 'error')
        return cb(false)
    end

    -- claim the cooldown slot before yielding on the DB, so parallel requests can't slip through
    sendCooldowns[senderCid] = now

    local recipients
    if office then
        recipients = getJobMembers(office.job, senderCid)
        if #recipients == 0 then
            sendCooldowns[senderCid] = last
            notify(src, locale('sv_job_none'), 'error')
            return cb(false)
        end
    else
        local targetName = getCharName(target)
        if not targetName then
            sendCooldowns[senderCid] = last
            notify(src, locale('sv_no_recipient'), 'error')
            return cb(false)
        end
        recipients = { { citizenid = target, name = targetName } }
    end

    -- recipients who blocked the sender are skipped without telling anyone
    local deliverable = {}
    for _, r in ipairs(recipients) do
        if not isBlocked(r.citizenid, senderCid) then deliverable[#deliverable + 1] = r end
    end
    if #deliverable == 0 then
        -- looks sent, but nothing is stored, charged or taken
        notify(src, locale('sv_sent'), 'success')
        return cb(true)
    end

    local fee = Config.SendCost + (att and (AT.Fee or 0) or 0)
    if fee > 0 and not Player.Functions.RemoveMoney(Config.MoneyType, fee, 'telegram-sent') then
        sendCooldowns[senderCid] = last
        notify(src, locale('sv_no_money', ('%.2f'):format(fee)), 'error')
        return cb(false)
    end

    local function refundAll()
        if fee > 0 then Player.Functions.AddMoney(Config.MoneyType, fee, 'telegram-refund') end
        sendCooldowns[senderCid] = last
    end

    if att and not takeAttachment(src, Player, att) then
        refundAll()
        notify(src, locale('sv_attach_no_item'), 'error')
        return cb(false)
    end

    local senderName = fullName(Player.PlayerData.charinfo)
    local extra = { batch = office and newBatch() or nil, attachment = att and json.encode(att) or nil }
    local stored = 0
    for _, r in ipairs(deliverable) do
        if storeTelegram(senderCid, senderName, r.citizenid, office and office.label or r.name, subject, message, Config.DeliveryDelay, false, extra) then
            stored = stored + 1
        end
    end

    if stored == 0 then
        if att then giveBack(src, Player, att) end
        refundAll()
        notify(src, locale('sv_invalid'), 'error')
        return cb(false)
    end

    notify(src, locale('sv_sent'), 'success')
    cb(true)
end)

---------------------------------
-- attachments: collect
---------------------------------
RSGCore.Functions.CreateCallback('rsg-telegram:server:collect', function(source, cb, id)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not validId(id) or not canUseUI(source) or not throttle(source, 'collect', ACTION_THROTTLE) then return cb(false) end
    local ok, result = claimAttachment(source, Player, id)
    if not ok then
        notify(source, locale(result == 'full' and 'sv_collect_full' or 'sv_collect_none'), 'error')
        return cb(false)
    end
    notify(source, locale(result and 'sv_collect_full' or 'sv_collected'), result and 'warning' or 'success')
    cb({ ok = true, attachment = result })
end)

---------------------------------
-- address book
---------------------------------
RSGCore.Functions.CreateCallback('rsg-telegram:server:getContacts', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not canUseUI(source) then return cb({}) end
    if not throttle(source, 'contacts', READ_THROTTLE) then return cb(false) end
    cb(getContacts(Player.PlayerData.citizenid))
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:addContact', function(source, cb, data)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or type(data) ~= 'table' or not validCid(data.citizenid) or not canUseUI(source) then return cb(false) end
    if not throttle(source, 'contact', ACTION_THROTTLE) then return cb(false) end

    local ok, reason = addContact(Player.PlayerData.citizenid, data.citizenid, data.nickname)
    if not ok then
        if reason == 'self' then notify(source, locale('sv_self_contact'), 'error')
        elseif reason == 'contacts_full' then notify(source, locale('sv_contacts_full', Config.MaxContacts), 'error')
        else notify(source, locale('sv_no_recipient'), 'error') end
        return cb(false)
    end
    notify(source, locale(reason == 'updated' and 'sv_contact_updated' or 'sv_contact_added'), 'success')
    cb(true)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:removeContact', function(source, cb, citizenid)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not validCid(citizenid) or not canUseUI(source) or not throttle(source, 'contact', ACTION_THROTTLE) then return cb(false) end
    if removeContact(Player.PlayerData.citizenid, citizenid) then
        notify(source, locale('sv_contact_removed'), 'inform')
        return cb(true)
    end
    cb(false)
end)

---------------------------------
-- block list
---------------------------------
RSGCore.Functions.CreateCallback('rsg-telegram:server:getBlocked', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not canUseUI(source) then return cb({}) end
    if not throttle(source, 'blocks', READ_THROTTLE) then return cb(false) end
    cb(getBlocked(Player.PlayerData.citizenid))
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:block', function(source, cb, citizenid)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not validCid(citizenid) or not canUseUI(source) or not throttle(source, 'block', ACTION_THROTTLE) then return cb(false) end
    local ok, reason = addBlock(Player.PlayerData.citizenid, citizenid)
    if not ok then
        if reason == 'self' then notify(source, locale('sv_self_block'), 'error')
        elseif reason == 'blocks_full' then notify(source, locale('sv_blocks_full', Config.MaxBlocked or 100), 'error')
        else notify(source, locale('sv_no_recipient'), 'error') end
        return cb(false)
    end
    notify(source, locale('sv_block_added'), 'inform')
    cb(true)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:unblock', function(source, cb, citizenid)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not validCid(citizenid) or not canUseUI(source) or not throttle(source, 'block', ACTION_THROTTLE) then return cb(false) end
    if removeBlock(Player.PlayerData.citizenid, citizenid) then
        notify(source, locale('sv_unblocked'), 'inform')
        return cb(true)
    end
    cb(false)
end)

---------------------------------
-- read / delete / bulk
---------------------------------
RegisterNetEvent('rsg-telegram:server:markRead', function(id)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not validId(id) or not canUseUI(src) or not throttle(src, 'read', 150) then return end
    local cid = Player.PlayerData.citizenid

    -- who to tell, if the sender wants a read receipt (looked up before the row flips to read)
    local sender
    if receipts().Enabled and receipts().NotifyRead then
        local row = MySQL.single.await('SELECT sender_citizenid FROM rsg_telegrams WHERE id = ? AND citizenid = ? AND is_read = 0', { id, cid })
        sender = row and row.sender_citizenid
    end

    if markRead(cid, id) > 0 and sender and sender ~= SYSTEM_CID then
        local Sender = RSGCore.Functions.GetPlayerByCitizenId(sender)
        if Sender then notify(Sender.PlayerData.source, locale('sv_receipt_read', fullName(Player.PlayerData.charinfo))) end
    end
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:delete', function(source, cb, id)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not validId(id) or not canUseUI(source) or not throttle(source, 'delete', ACTION_THROTTLE) then return cb(false) end
    local ok, reason = deleteTelegram(Player.PlayerData.citizenid, id)
    if ok then
        notify(source, locale('sv_deleted'), 'inform')
        return cb(true)
    end
    if reason == 'attachment' then notify(source, locale('sv_delete_attachment'), 'error') end
    cb(false)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:markAllRead', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not canUseUI(source) or not throttle(source, 'bulk', 1500) then return cb(false) end
    local count = markRead(Player.PlayerData.citizenid)
    if count > 0 then notify(source, locale('sv_marked_all', count), 'success') end
    cb(true)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:deleteRead', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not canUseUI(source) or not throttle(source, 'bulk', 1500) then return cb(false) end
    local count = deleteRead(Player.PlayerData.citizenid)
    if count > 0 then notify(source, locale('sv_deleted_read', count), 'inform') end
    cb(true)
end)

-- the client tells us when its UI closed, so a remote-open grant does not outlive the session
RegisterNetEvent('rsg-telegram:server:closed', function()
    access[source] = nil
end)

---------------------------------
-- unread reminder on login (server-side core event, not client-triggerable)
---------------------------------
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    if not Player or not Player.PlayerData then return end
    local src, cid = Player.PlayerData.source, Player.PlayerData.citizenid
    SetTimeout(5000, function()
        local count = getUnreadCount(cid)
        if count > 0 and GetPlayerName(src) then
            notify(src, locale('sv_unread', count), 'inform')
        end
    end)
end)

AddEventHandler('playerDropped', function()
    throttles[source] = nil
    access[source] = nil
end)

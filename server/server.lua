local RSGCore = exports['rsg-core']:GetCoreObject()

TelegramMailboxes = {}   -- [id] = { id, x, y, z, heading, label } (filled by server/mailbox.lua)
local unlisted        = {} -- [citizenid] = true: hidden from the directory search
local noticeCooldowns = {} -- [citizenid] = os.time() of the last /notice
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
            { name = 'anonymous',        def = 'TINYINT(1) NOT NULL DEFAULT 0' },
            { name = 'silenced',         def = 'TINYINT(1) NOT NULL DEFAULT 0' }, -- copy for a recipient who blocked the sender: kept for the Sent tab only
            { name = 'kind',             def = 'VARCHAR(20) NULL DEFAULT NULL' },  -- notice | broadcast
        },
        extra = { 'PRIMARY KEY (`id`)', 'INDEX `idx_citizenid` (`citizenid`)' },
        indexes = {
            { name = 'idx_sender', def = 'INDEX `idx_sender` (`sender_citizenid`)' },        -- Sent tab
            { name = 'idx_inbox',  def = 'INDEX `idx_inbox` (`citizenid`, `sent_at`)' },             -- inbox, trimming
        },
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
            { name = 'anonymous',         def = 'TINYINT(1) NOT NULL DEFAULT 0' }, -- blocked through an anonymous telegram: identity stays hidden
        },
        extra = { 'PRIMARY KEY (`id`)', 'UNIQUE KEY `uniq_block` (`citizenid`, `blocked_citizenid`)' },
    },
    rsg_telegram_settings = {
        columns = {
            { name = 'citizenid', def = 'VARCHAR(50) NOT NULL' },
            { name = 'unlisted',  def = 'TINYINT(1) NOT NULL DEFAULT 0' },
        },
        extra = { 'PRIMARY KEY (`citizenid`)' },
    },
    rsg_telegram_mailboxes = {
        columns = {
            { name = 'id',         def = 'INT(11) NOT NULL AUTO_INCREMENT' },
            { name = 'label',      def = 'VARCHAR(64) NULL DEFAULT NULL' },
            { name = 'x',          def = 'DOUBLE NOT NULL' },
            { name = 'y',          def = 'DOUBLE NOT NULL' },
            { name = 'z',          def = 'DOUBLE NOT NULL' },
            { name = 'heading',    def = 'DOUBLE NOT NULL DEFAULT 0' },
            { name = 'created_by', def = 'VARCHAR(50) NULL DEFAULT NULL' },
            { name = 'created_at', def = 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP' },
        },
        extra = { 'PRIMARY KEY (`id`)' },
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
local ANON_CID       = 'ANON'             -- what the client sees instead of an anonymous sender's citizen id
local AT             = Config.Attachments or { Enabled = false }

local jobColumnOk = false -- players.job exists (needed for job addresses)
local jobTableOk  = false -- player_jobs exists (rsg-core multi-job; lets job addresses reach offline secondary-job holders)
local dbReady     = false
local readyHooks  = {}
local access = {}         -- [src] = os.time() until which the UI may be used away from a post office (OpenTelegrams export)

local function purgeOld()
    -- telegrams that still carry an unclaimed attachment are never purged
    local readDays   = Config.PurgeReadAfterDays or 0
    local unreadDays = Config.PurgeUnreadAfterDays or 0
    if readDays > 0 then -- silenced copies (is_read = 1) age out with the read ones
        local removed = MySQL.update.await('DELETE FROM rsg_telegrams WHERE is_read = 1 AND attachment IS NULL AND sent_at < (NOW() - INTERVAL ? DAY)', { readDays })
        if removed and removed > 0 then dbLog(('Purged %d old read telegrams'):format(removed)) end
    end
    if unreadDays > 0 then
        local removed = MySQL.update.await('DELETE FROM rsg_telegrams WHERE is_read = 0 AND silenced = 0 AND attachment IS NULL AND sent_at < (NOW() - INTERVAL ? DAY)', { unreadDays })
        if removed and removed > 0 then dbLog(('Purged %d old unread telegrams'):format(removed)) end
    end
    -- everything that belongs to characters that were deleted from the players table
    if Config.PurgeDeletedCharacters then
        local days = math.max(1, Config.PurgeDeletedAfterDays or 7)
        local gone = "NOT EXISTS (SELECT 1 FROM players p WHERE p.citizenid COLLATE utf8mb4_general_ci = %s.citizenid COLLATE utf8mb4_general_ci)"
        local removed = MySQL.update.await(('DELETE FROM rsg_telegrams WHERE sent_at < (NOW() - INTERVAL ? DAY) AND %s'):format(gone:format('rsg_telegrams')), { days })
        if removed and removed > 0 then dbLog(('Purged %d telegrams of deleted characters'):format(removed)) end
        for _, t in ipairs({ 'rsg_telegram_contacts', 'rsg_telegram_blocks', 'rsg_telegram_settings' }) do
            MySQL.update.await(('DELETE FROM %s WHERE %s'):format(t, gone:format(t)))
        end
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

    local okT, countT = pcall(MySQL.scalar.await,
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'player_jobs'")
    jobTableOk = okT and (countT or 0) > 0

    local okU, rowsU = pcall(MySQL.query.await, 'SELECT citizenid FROM rsg_telegram_settings WHERE unlisted = 1')
    if okU then for _, r in ipairs(rowsU or {}) do unlisted[r.citizenid] = true end end

    local purged, err = pcall(purgeOld)
    if not purged then dbLog(('Purge failed: %s'):format(tostring(err)), '^1') end

    dbReady = true
    for _, fn in ipairs(readyHooks) do fn() end
end)

-- keep purging on long-running servers (it used to only run on resource start)
CreateThread(function()
    while true do
        Wait(PURGE_INTERVAL)
        local ok, err = pcall(purgeOld)
        if not ok then dbLog(('Purge failed: %s'):format(tostring(err)), '^1') end
        -- forget expired send cooldowns (they are keyed by citizen id and would otherwise only grow)
        local now = os.time()
        for cid, at in pairs(sendCooldowns) do
            if now - at >= (Config.SendCooldown or 0) then sendCooldowns[cid] = nil end
        end
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
             :gsub('\226\128[\139-\143\168-\174]', '') -- U+200B-200F, U+2028-202E
             :gsub('\239\187\191', '')                 -- U+FEFF (zero-width no-break space)
             :gsub('\194[\128-\159]', '')              -- C1 control characters
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

-- the post office the player is standing at (nil at a mailbox / elsewhere)
local function nearestOffice(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local pos = GetEntityCoords(ped)
    local range = Config.PromptDistance + 3.0
    for _, office in ipairs(Config.PostOffices) do
        if #(pos - office.coords) <= range then return office end
    end
    return nil
end

local function isNearPostOffice(src)
    if nearestOffice(src) then return true end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    local range = ((Config.Mailbox and Config.Mailbox.Distance) or 2.0) + 3.0
    for _, mb in pairs(TelegramMailboxes) do
        if #(pos - vector3(mb.x, mb.y, mb.z)) <= range then return true end
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

-- attaching would reset the item's decay (it is re-added as a fresh stack), so partly decayed stacks are refused
local function hasDecayedStack(Player, name)
    for _, item in pairs(Player.PlayerData.items or {}) do
        if type(item) == 'table' and item.name == name and type(item.info) == 'table' then
            local q = tonumber(item.info.quality)
            if q and q < 100 then return true end
        end
    end
    return false
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
        if hasDecayedStack(Player, it.name) then return nil, 'sv_attach_invalid' end
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
-- offset / query are optional (UI paging and search). Anonymous senders are never revealed to the client.
local function getInbox(cid, limit, unreadOnly, offset, query)
    local params = { cid }
    local sql = 'SELECT id, sender_citizenid, sender_name, subject, message, is_read, has_attachment, attachment, anonymous, kind, UNIX_TIMESTAMP(sent_at) AS sent_at FROM rsg_telegrams WHERE citizenid = ? AND silenced = 0 AND sent_at <= NOW()'
        .. (unreadOnly and ' AND is_read = 0' or '')
    if query and query ~= '' then
        sql = sql .. ' AND (subject LIKE ? OR sender_name LIKE ? OR message LIKE ?)'
        local like = '%' .. query .. '%'
        params[#params + 1] = like; params[#params + 1] = like; params[#params + 1] = like
    end
    sql = sql .. ' ORDER BY sent_at DESC, id DESC LIMIT ? OFFSET ?'
    params[#params + 1] = limit; params[#params + 1] = offset or 0
    local rows = MySQL.query.await(sql, params) or {}
    for i = 1, #rows do
        rows[i].attachment = decodeAttachment(rows[i].attachment)
        if rows[i].anonymous == 1 then rows[i].sender_citizenid = ANON_CID end
    end
    return rows
end

-- telegrams this character sent, one row per send (a job-address send is one row), with delivery/read counts
local function getSent(cid, limit)
    local showRead = receipts().Enabled ~= false
    local rows = MySQL.query.await([[
        SELECT MIN(id) AS id, MAX(subject) AS subject, MAX(message) AS message, MAX(recipient_name) AS recipient_name,
               UNIX_TIMESTAMP(MIN(sent_at)) AS sent_at, COUNT(*) AS recipients,
               CAST(SUM(sent_at <= NOW()) AS UNSIGNED) AS delivered,
               CAST(SUM(IF(silenced = 0, is_read, 0)) AS UNSIGNED) AS read_count,
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
    return MySQL.scalar.await('SELECT COUNT(*) FROM rsg_telegrams WHERE citizenid = ? AND is_read = 0 AND silenced = 0 AND sent_at <= NOW()', { cid }) or 0
end

-- tells an online character how many unread telegrams they have (drives the on-screen badge)
local function pushUnread(cid)
    local P = RSGCore.Functions.GetPlayerByCitizenId(cid)
    if P then TriggerClientEvent('rsg-telegram:client:unread', P.PlayerData.source, getUnreadCount(cid)) end
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
    local affected = MySQL.update.await('DELETE FROM rsg_telegrams WHERE id = ? AND citizenid = ? AND silenced = 0 AND sent_at <= NOW() AND attachment IS NULL', { id, cid })
    if affected and affected > 0 then return true end
    local held = MySQL.scalar.await('SELECT 1 FROM rsg_telegrams WHERE id = ? AND citizenid = ? AND attachment IS NOT NULL', { id, cid })
    return false, held and 'attachment' or nil
end

-- destroys every delivered, read telegram that has nothing left to collect; returns the count
local function deleteRead(cid)
    return MySQL.update.await('DELETE FROM rsg_telegrams WHERE citizenid = ? AND is_read = 1 AND silenced = 0 AND sent_at <= NOW() AND attachment IS NULL', { cid }) or 0
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

-- anonymous blocks hide the citizen id (the client unblocks them by row id instead)
local function getBlocked(cid)
    return MySQL.query.await('SELECT id, IF(anonymous = 1, NULL, blocked_citizenid) AS citizenid, blocked_name AS name, anonymous FROM rsg_telegram_blocks WHERE citizenid = ? ORDER BY blocked_name ASC', { cid }) or {}
end

-- returns true, 'added' | 'already'   or   false, 'self' | 'blocks_full' | 'not_found'
local function addBlock(owner, target, anonymous)
    if target == owner then return false, 'self' end
    if isBlocked(owner, target) then return true, 'already' end
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM rsg_telegram_blocks WHERE citizenid = ?', { owner }) or 0
    if count >= (Config.MaxBlocked or 100) then return false, 'blocks_full' end
    local name = getCharName(target)
    if not name then return false, 'not_found' end
    if anonymous then name = locale('sv_anonymous') end
    MySQL.insert.await('INSERT INTO rsg_telegram_blocks (citizenid, blocked_citizenid, blocked_name, anonymous) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE blocked_name = VALUES(blocked_name)', { owner, target, name, anonymous and 1 or 0 })
    return true, 'added'
end

-- blocks the real sender of one of the owner's telegrams (used for anonymous senders; the client never learns who it is)
local function blockFromTelegram(owner, telegramId)
    local row = MySQL.single.await('SELECT sender_citizenid, anonymous FROM rsg_telegrams WHERE id = ? AND citizenid = ? AND silenced = 0', { telegramId, owner })
    if not row or row.sender_citizenid == SYSTEM_CID then return false, 'not_found' end
    return addBlock(owner, row.sender_citizenid, row.anonymous == 1)
end

-- target is a citizen id (string) or the id of the block row (number, used for anonymous blocks)
local function removeBlock(owner, target)
    local affected
    if math.type(target) == 'integer' then
        affected = MySQL.update.await('DELETE FROM rsg_telegram_blocks WHERE citizenid = ? AND id = ?', { owner, target })
    else
        affected = MySQL.update.await('DELETE FROM rsg_telegram_blocks WHERE citizenid = ? AND blocked_citizenid = ? AND anonymous = 0', { owner, target })
    end
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
    -- offline characters who hold the job as a secondary job (rsg-core multi-job)
    if jobTableOk and #members < limit then
        local ok, rows = pcall(MySQL.query.await,
            [[SELECT p.citizenid, p.charinfo FROM player_jobs pj JOIN players p ON p.citizenid = pj.citizenid
              WHERE pj.job = ? AND pj.citizenid <> ? LIMIT ?]], { job, excludeCid, limit })
        for _, r in ipairs(ok and rows or {}) do
            if not seen[r.citizenid] and #members < limit then
                seen[r.citizenid] = true
                members[#members + 1] = { citizenid = r.citizenid, name = fullName(r.charinfo) }
            end
        end
    end
    return members
end

-- stores a telegram and schedules its arrival. Returns the new id, or nil if the insert failed.
-- Stored immediately (paid telegrams survive restarts); a future sent_at hides it until it "arrives".
-- extra = { batch = 'id shared by every copy of one send', attachment = '<json>', anonymous = bool,
--           kind = 'notice' | 'broadcast', silenced = bool (recipient blocked the sender: stored for the Sent tab only),
--           claimed = bool (silenced copy that pretends its attachment was already collected) }
local function storeTelegram(senderCid, senderName, target, targetName, subject, message, delay, silent, extra)
    delay = math.max(0, math.floor(tonumber(delay) or 0))
    extra = extra or {}

    local cols = { 'citizenid', 'recipient_name', 'sender_citizenid', 'sender_name', 'subject', 'message' }
    local vals = { target, targetName, senderCid, senderName, subject, message }
    local function add(col, val) cols[#cols + 1] = col; vals[#vals + 1] = val end
    if extra.batch then add('batch', extra.batch) end
    if extra.attachment then
        add('has_attachment', 1)
        add('attachment', extra.attachment)
    elseif extra.claimed then
        add('has_attachment', 1)
    end
    if extra.anonymous then add('anonymous', 1) end
    if extra.kind then add('kind', extra.kind) end
    if extra.silenced then
        add('silenced', 1)
        add('is_read', 1) -- never counted as unread, purged with the read ones
    end
    vals[#vals + 1] = delay
    local id = MySQL.insert.await(
        ('INSERT INTO rsg_telegrams (%s, sent_at) VALUES (%sNOW() + INTERVAL ? SECOND)'):format(table.concat(cols, ', '), ('?, '):rep(#cols)),
        vals
    )
    if not id then return nil end

    local info = {
        id = id, recipient = target, recipientName = targetName,
        sender = senderCid, senderName = senderName, subject = subject, delay = delay,
        hasAttachment = extra.attachment ~= nil,
    }

    -- cap what a single character can hold (stops inbox flooding / table bloat). Unread telegrams are kept
    -- first, then the newest; telegrams with something left to collect are never trimmed
    local cap = Config.MaxStoredPerPlayer or 0
    if cap > 0 and not extra.silenced then
        MySQL.update(
            'DELETE FROM rsg_telegrams WHERE citizenid = ? AND silenced = 0 AND attachment IS NULL AND id NOT IN (SELECT id FROM (SELECT id FROM rsg_telegrams WHERE citizenid = ? AND silenced = 0 ORDER BY is_read ASC, sent_at DESC, id DESC LIMIT ?) AS keep)',
            { target, target, cap }
        )
    end

    if not extra.silenced then TriggerEvent('rsg-telegram:server:telegramSent', info) end

    SetTimeout(delay * 1000, function()
        if not extra.silenced then
            local Target = RSGCore.Functions.GetPlayerByCitizenId(target)
            if Target and not silent then TriggerClientEvent('rsg-telegram:client:newTelegram', Target.PlayerData.source, senderName) end
            if Target then pushUnread(target) end
        end
        -- silenced copies report delivery too, so a blocked sender sees exactly what an unblocked one would
        if receipts().Enabled and receipts().NotifyDelivered and not extra.batch and senderCid ~= SYSTEM_CID then
            local Sender = RSGCore.Functions.GetPlayerByCitizenId(senderCid)
            if Sender then notify(Sender.PlayerData.source, locale('sv_receipt_delivered', targetName)) end
        end
        if not extra.silenced then TriggerEvent('rsg-telegram:server:telegramDelivered', info) end
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
    grantAccess = grantAccess, pushUnread = pushUnread,
    store = storeTelegram,
    onReady = function(fn) if dbReady then fn() else readyHooks[#readyHooks + 1] = fn end end,
}

---------------------------------
-- inbox / sent
---------------------------------
-- callbacks answer `false` when throttled so the UI keeps what it already shows

-- cuts a search text to `max` characters (never in the middle of one) and removes LIKE wildcards.
-- Returns the text and its length in characters, or nil when it is unusable.
local function cleanQuery(query, max)
    if type(query) ~= 'string' then return nil end
    query = query:gsub('[%%_<>\\]', '')
    local chars = utf8.len(query)
    if not chars then return nil end
    if chars > max then query = query:sub(1, utf8.offset(query, max + 1) - 1) end
    return query, math.min(chars, max)
end

-- data (optional) = { offset = n, query = 'text' } for paging and searching the inbox
RSGCore.Functions.CreateCallback('rsg-telegram:server:getInbox', function(source, cb, data)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not canUseUI(source) then return cb(false) end -- false: the client does not open the UI
    if not throttle(source, 'inbox', READ_THROTTLE) then return cb(false) end
    data = type(data) == 'table' and data or {}
    local offset = math.max(0, math.min(5000, math.tointeger(tonumber(data.offset)) or 0))
    local query = data.query ~= nil and cleanQuery(data.query, 40) or nil
    cb(getInbox(Player.PlayerData.citizenid, math.max(1, math.min(Config.InboxPageSize or 25, 100)), false, offset, query))
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

    local chars
    query, chars = cleanQuery(query, 40)
    if not query or chars < Config.SearchMinChars then return cb({}) end

    local sql = [[
        SELECT citizenid, charinfo FROM players
        WHERE citizenid <> ?
          AND ( CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) LIKE ?%s )
        LIMIT 25
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
        -- characters that chose to be unlisted never show up, even by exact citizen id
        if not unlisted[rows[i].citizenid] and #results < 10 then
            results[#results + 1] = { citizenid = rows[i].citizenid, name = fullName(rows[i].charinfo) }
        end
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
        if type(item) == 'table' and item.name and itemAttachable(item.name) and not hasDecayedStack(Player, item.name) then
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

-- seconds a telegram to `targetCid` takes: Config.DeliveryDelay, plus the distance between sender and recipient
-- when Config.DeliveryDistance is on (only for recipients who are online)
local function deliveryDelay(src, targetCid)
    local delay = Config.DeliveryDelay or 0
    local D = Config.DeliveryDistance
    if D and D.Enabled then
        local Target = RSGCore.Functions.GetPlayerByCitizenId(targetCid)
        if Target then
            local from, to = GetPlayerPed(src), GetPlayerPed(Target.PlayerData.source)
            if from ~= 0 and to ~= 0 then
                local km = #(GetEntityCoords(from) - GetEntityCoords(to)) / 1000.0
                delay = delay + math.min(D.Max or 180, km * (D.SecondsPerKm or 20))
            end
        end
    end
    return math.floor(delay)
end

local function round2(n) return math.floor(n * 100 + 0.5) / 100 end

-- price of this send: the base fee, or an rsg-economy quote (tax + treasury) at a post office with a region
local function priceFor(src, fee)
    local E, office = Config.Economy, nearestOffice(src)
    if E and E.Enabled and fee > 0 and office and office.region and GetResourceState('rsg-economy') == 'started' then
        local ok, quote = pcall(function()
            return exports['rsg-economy']:Quote(src, { region = office.region, mode = 'buy', base = fee, qty = 1, category = E.Category or 'sales', market = false })
        end)
        if ok and type(quote) == 'table' and tonumber(quote.total) then return round2(quote.total), quote, office end
    end
    return fee, nil, office
end

-- bookkeeping after a successful send: tax into the town treasury, standing in the post office's region
local function afterSend(src, quote, office)
    if quote then pcall(function() exports['rsg-economy']:Record(src, quote) end) end
    local R = Config.Reputation
    if R and R.Enabled and (R.StandingPerSend or 0) > 0 and office and office.region and GetResourceState('rsg-reputation') == 'started' then
        pcall(function() exports['rsg-reputation']:AddStanding(src, office.region, R.StandingPerSend, 'telegram-sent', true) end)
    end
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

    -- anonymous telegrams go to people, not offices
    local ANON = Config.Anonymous or {}
    local anonymous = data.anonymous == true and ANON.Enabled and not office or false

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

    -- a recipient who blocked the sender gets a hidden copy: it is charged, shown in the Sent tab and "delivered"
    -- exactly like any other, but never reaches that inbox, so blocking cannot be probed
    local deliverable, blocked = {}, {}
    for _, r in ipairs(recipients) do
        if isBlocked(r.citizenid, senderCid) then blocked[#blocked + 1] = r else deliverable[#deliverable + 1] = r end
    end

    local fee = Config.SendCost + (att and (AT.Fee or 0) or 0) + (anonymous and (ANON.Fee or 0) or 0)
    local charge, quote, postOffice = priceFor(src, fee)
    if charge > 0 and not Player.Functions.RemoveMoney(Config.MoneyType, charge, 'telegram-sent') then
        sendCooldowns[senderCid] = last
        notify(src, locale('sv_no_money', ('%.2f'):format(charge)), 'error')
        return cb(false)
    end

    local function refundAll()
        if charge > 0 then Player.Functions.AddMoney(Config.MoneyType, charge, 'telegram-refund') end
        sendCooldowns[senderCid] = last
    end

    -- the attachment only leaves the sender when somebody will actually receive it
    local taken = att and #deliverable > 0
    if taken and not takeAttachment(src, Player, att) then
        refundAll()
        notify(src, locale('sv_attach_no_item'), 'error')
        return cb(false)
    end

    local senderName = fullName(Player.PlayerData.charinfo)
    local shownName = anonymous and locale('sv_anonymous') or senderName
    local batch = office and newBatch() or nil
    local stored = 0
    for _, r in ipairs(deliverable) do
        local to = office and office.label or r.name
        if storeTelegram(senderCid, shownName, r.citizenid, to, subject, message, deliveryDelay(src, r.citizenid), false,
            { batch = batch, attachment = att and json.encode(att) or nil, anonymous = anonymous }) then
            stored = stored + 1
        end
    end
    for _, r in ipairs(blocked) do
        storeTelegram(senderCid, shownName, r.citizenid, office and office.label or r.name, subject, message, deliveryDelay(src, r.citizenid), true,
            { batch = batch, anonymous = anonymous, silenced = true, claimed = att ~= nil })
    end

    if #deliverable > 0 and stored == 0 then
        if taken then giveBack(src, Player, att) end
        refundAll()
        notify(src, locale('sv_invalid'), 'error')
        return cb(false)
    end

    afterSend(src, quote, postOffice)
    notify(src, locale('sv_sent'), 'success')
    cb(true)
end)

---------------------------------
-- notices and broadcasts: one telegram to many characters
---------------------------------
-- scope 'online' = everyone connected now (capped at maxN), 'all' = every character (capped at maxN, one SQL statement).
-- Returns how many characters it reaches. sender: { cid, name }. Nothing is charged here; callers check who may send.
local function broadcast(sender, subject, message, kind, scope, delay, maxN, excludeCid)
    delay = math.max(0, math.floor(tonumber(delay) or 0))
    maxN = math.max(1, math.floor(tonumber(maxN) or 100))

    if scope == 'all' then
        local reached = MySQL.update.await(
            [[INSERT INTO rsg_telegrams (citizenid, recipient_name, sender_citizenid, sender_name, subject, message, kind, batch, sent_at)
              SELECT citizenid, '', ?, ?, ?, ?, ?, ?, NOW() + INTERVAL ? SECOND FROM players LIMIT ?]],
            { sender.cid, sender.name, subject, message, kind, newBatch(), delay, maxN }) or 0
        SetTimeout(delay * 1000, function()
            for _, P in pairs(RSGCore.Functions.GetRSGPlayers()) do
                TriggerClientEvent('rsg-telegram:client:newTelegram', P.PlayerData.source, sender.name)
                pushUnread(P.PlayerData.citizenid)
            end
        end)
        return reached
    end

    local batch, reached = newBatch(), 0
    for _, P in pairs(RSGCore.Functions.GetRSGPlayers()) do
        local cid = P.PlayerData and P.PlayerData.citizenid
        if cid and cid ~= excludeCid and reached < maxN then
            if storeTelegram(sender.cid, sender.name, cid, fullName(P.PlayerData.charinfo), subject, message, delay, false, { batch = batch, kind = kind }) then
                reached = reached + 1
            end
        end
    end
    return reached
end

local function say(src, text, ntype)
    if src == 0 then print(('[%s] %s'):format(GetCurrentResourceName(), text)) else notify(src, text, ntype) end
end

-- "subject | message" -> sanitised subject, message (or nil)
local function splitText(text)
    local subj, msg = tostring(text or ''):match('^(.-)%s*|%s*(.+)$')
    return sanitize(subj, Config.MaxSubject), sanitize(msg, Config.MaxMessage)
end

-- /telegrambroadcast <online|all> <delay minutes> <subject | message>   (admin / console)
RSGCore.Commands.Add('telegrambroadcast', locale('cmd_broadcast'), {
    { name = 'scope', help = 'online | all' }, { name = 'minutes', help = '0 = now' }, { name = 'text', help = 'subject | message' },
}, false, function(source, args)
    local scope = (args[1] or ''):lower()
    local minutes = tonumber(args[2])
    local subject, message = splitText(table.concat(args, ' ', 3))
    if (scope ~= 'online' and scope ~= 'all') or not minutes or not subject or not message then
        return say(source, locale('sv_broadcast_usage'), 'error')
    end
    minutes = math.max(0, math.min(10080, minutes))
    local name = (Config.API and Config.API.SystemSenderName) or 'Telegraph Office'
    local count = broadcast({ cid = SYSTEM_CID, name = name }, subject, message, 'broadcast', scope, minutes * 60,
        scope == 'all' and (Config.Broadcast and Config.Broadcast.MaxAll) or 1000)
    say(source, locale('sv_broadcast_sent', count), 'success')
end, 'admin')

-- /notice <subject | message>: an official notice from a job (law, ...) to everyone online
RSGCore.Commands.Add('notice', locale('cmd_notice'), { { name = 'text', help = 'subject | message' } }, false, function(source, args)
    local N = Config.Notices or {}
    local Player = RSGCore.Functions.GetPlayer(source)
    if source == 0 or not Player or not N.Enabled then return end
    local job = Player.PlayerData.job or {}
    local allowed = false
    for _, j in ipairs(N.Jobs or {}) do if j == job.name then allowed = true break end end
    if not allowed or (N.RequireOnDuty and not job.onduty) then return notify(source, locale('sv_notice_denied'), 'error') end

    local cid = Player.PlayerData.citizenid
    local wait = (N.Cooldown or 0) - (os.time() - (noticeCooldowns[cid] or 0))
    if wait > 0 then return notify(source, locale('sv_notice_cooldown', wait), 'error') end

    local subject, message = splitText(table.concat(args, ' '))
    if not subject or not message then return notify(source, locale('sv_notice_usage'), 'error') end

    noticeCooldowns[cid] = os.time()
    local office = jobAddresses[job.name]
    local name = (office and office.label) or job.label or fullName(Player.PlayerData.charinfo)
    local count = broadcast({ cid = cid, name = name }, subject, message, 'notice', 'online', 0, N.MaxRecipients or 300, cid)
    notify(source, locale('sv_notice_sent', count), 'success')
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

-- arg: a citizen id, or { id = telegram id } to block the sender of one of your telegrams without learning who it is
RSGCore.Functions.CreateCallback('rsg-telegram:server:block', function(source, cb, arg)
    local Player = RSGCore.Functions.GetPlayer(source)
    local byTelegram = type(arg) == 'table' and validId(arg.id)
    if not Player or not (byTelegram or validCid(arg)) or not canUseUI(source) or not throttle(source, 'block', ACTION_THROTTLE) then return cb(false) end
    local ok, reason
    if byTelegram then ok, reason = blockFromTelegram(Player.PlayerData.citizenid, arg.id)
    else ok, reason = addBlock(Player.PlayerData.citizenid, arg) end
    if not ok then
        if reason == 'self' then notify(source, locale('sv_self_block'), 'error')
        elseif reason == 'blocks_full' then notify(source, locale('sv_blocks_full', Config.MaxBlocked or 100), 'error')
        else notify(source, locale('sv_no_recipient'), 'error') end
        return cb(false)
    end
    notify(source, locale('sv_block_added'), 'inform')
    cb(true)
end)

-- arg: a citizen id, or { id = block row id } for anonymous blocks
RSGCore.Functions.CreateCallback('rsg-telegram:server:unblock', function(source, cb, arg)
    local Player = RSGCore.Functions.GetPlayer(source)
    local target = type(arg) == 'table' and validId(arg.id) and arg.id or (validCid(arg) and arg or nil)
    if not Player or not target or not canUseUI(source) or not throttle(source, 'block', ACTION_THROTTLE) then return cb(false) end
    if removeBlock(Player.PlayerData.citizenid, target) then
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

    local changed = markRead(cid, id)
    if changed > 0 then pushUnread(cid) end
    if changed > 0 and sender and sender ~= SYSTEM_CID then
        local Sender = RSGCore.Functions.GetPlayerByCitizenId(sender)
        if Sender then notify(Sender.PlayerData.source, locale('sv_receipt_read', fullName(Player.PlayerData.charinfo))) end
    end
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:delete', function(source, cb, id)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not validId(id) or not canUseUI(source) or not throttle(source, 'delete', ACTION_THROTTLE) then return cb(false) end
    local ok, reason = deleteTelegram(Player.PlayerData.citizenid, id)
    if ok then
        pushUnread(Player.PlayerData.citizenid)
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
    if count > 0 then
        pushUnread(Player.PlayerData.citizenid)
        notify(source, locale('sv_marked_all', count), 'success')
    end
    cb(true)
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:deleteRead', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not canUseUI(source) or not throttle(source, 'bulk', 1500) then return cb(false) end
    local count = deleteRead(Player.PlayerData.citizenid)
    if count > 0 then
        pushUnread(Player.PlayerData.citizenid)
        notify(source, locale('sv_deleted_read', count), 'inform')
    end
    cb(true)
end)

---------------------------------
-- settings: listed in the directory search or not
---------------------------------
RSGCore.Functions.CreateCallback('rsg-telegram:server:getSettings', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not canUseUI(source) then return cb(false) end
    cb({ unlisted = unlisted[Player.PlayerData.citizenid] == true })
end)

RSGCore.Functions.CreateCallback('rsg-telegram:server:toggleListed', function(source, cb)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player or not canUseUI(source) or not throttle(source, 'settings', ACTION_THROTTLE) then return cb(false) end
    local cid = Player.PlayerData.citizenid
    if unlisted[cid] then
        unlisted[cid] = nil
        MySQL.update('DELETE FROM rsg_telegram_settings WHERE citizenid = ?', { cid })
        notify(source, locale('sv_listed'), 'inform')
    else
        unlisted[cid] = true
        MySQL.update('INSERT INTO rsg_telegram_settings (citizenid, unlisted) VALUES (?, 1) ON DUPLICATE KEY UPDATE unlisted = 1', { cid })
        notify(source, locale('sv_unlisted'), 'inform')
    end
    cb({ unlisted = unlisted[cid] == true })
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
        if not GetPlayerName(src) then return end
        local count = getUnreadCount(cid)
        TriggerClientEvent('rsg-telegram:client:unread', src, count)
        if count > 0 then notify(src, locale('sv_unread', count), 'inform') end
    end)
end)

-- after a resource restart, bring the badge of everyone already online up to date
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetTimeout(4000, function()
        for _, P in pairs(RSGCore.Functions.GetRSGPlayers()) do pushUnread(P.PlayerData.citizenid) end
    end)
end)

AddEventHandler('playerDropped', function()
    throttles[source] = nil
    access[source] = nil
end)

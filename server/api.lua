---------------------------------
-- rsg-telegram public API (server exports)
-- Other resources call these with exports['rsg-telegram']:Name(...)
-- Anywhere a citizen is expected you can pass either a citizenid string or an online player's server id.
-- Server-side only: these calls are trusted and skip the post office, fee and cooldown checks that
-- apply to players using the UI. Never expose them to the client without your own validation.
---------------------------------
local RSGCore = exports['rsg-core']:GetCoreObject()
local I = TelegramInternal -- data layer from server/server.lua

local SYSTEM_CID = I.SYSTEM_CID -- sender id for telegrams sent without a character (the UI hides Reply for these)
local MAX_LIMIT  = 200

local function enabled()
    return Config.API and Config.API.Enabled
end

-- accepts a citizenid string or an online server id, returns a valid citizenid or nil
local function toCid(v)
    if math.type(v) == 'integer' then
        local Player = RSGCore.Functions.GetPlayer(v)
        return Player and Player.PlayerData.citizenid or nil
    end
    return I.validCid(v) and v or nil
end

---------------------------------
-- SendTelegram(recipient, subject, message, opts?) -> ok, idOrReason
-- recipient : citizenid or server id (works for offline characters)
-- opts.sender     : citizenid or server id of a real character to send as (default: system sender)
-- opts.senderName : display name (default Config.API.SystemSenderName, or the character's name)
-- opts.delay      : seconds before it arrives (default 0, instant)
-- opts.silent     : true = no "new telegram" toast for the recipient
-- opts.attachment : { cash = 25.5, items = { { name = 'bread', amount = 2 } } } the recipient can collect.
--                   Created out of thin air (nothing is taken from anyone): you decide what is fair.
-- reasons: disabled | invalid_recipient | invalid_subject | invalid_message | invalid_sender | invalid_attachment
--          recipient_not_found | blocked (only when opts.sender is a character the recipient blocked) | db_error
---------------------------------
exports('SendTelegram', function(recipient, subject, message, opts)
    if not enabled() then return false, 'disabled' end
    opts = type(opts) == 'table' and opts or {}

    local target = toCid(recipient)
    if not target then return false, 'invalid_recipient' end
    subject = I.sanitize(subject, Config.MaxSubject)
    if not subject then return false, 'invalid_subject' end
    message = I.sanitize(message, Config.MaxMessage)
    if not message then return false, 'invalid_message' end

    local attachment
    if opts.attachment ~= nil then
        local att = I.normaliseAttachment(opts.attachment, false)
        if att == false then return false, 'invalid_attachment' end
        attachment = att and json.encode(att) or nil
    end

    local targetName = I.getCharName(target)
    if not targetName then return false, 'recipient_not_found' end

    local senderCid, senderName = SYSTEM_CID, nil
    if opts.sender ~= nil then
        senderCid = toCid(opts.sender)
        senderName = senderCid and I.getCharName(senderCid)
        if not senderName then return false, 'invalid_sender' end
        if I.isBlocked(target, senderCid) then return false, 'blocked' end
    end
    if opts.senderName ~= nil then
        senderName = I.sanitize(opts.senderName, 100)
        if not senderName then return false, 'invalid_sender' end
    end
    senderName = senderName or Config.API.SystemSenderName or 'Telegraph Office'

    local id = I.store(senderCid, senderName, target, targetName, subject, message, opts.delay, opts.silent == true, { attachment = attachment })
    if not id then return false, 'db_error' end
    return true, id
end)

---------------------------------
-- GetTelegrams(citizen, opts?) -> table[]
-- rows: { id, sender_citizenid, sender_name, subject, message, is_read (0/1), has_attachment (0/1),
--         attachment ({ cash?, items = { {name, label, amount} } } or nil once collected), sent_at (unix) }, newest first
-- opts.unreadOnly : true = only unread
-- opts.limit      : max rows (default Config.MaxInbox, capped at 200)
-- Telegrams still "in transit" (delivery delay) are never returned.
---------------------------------
exports('GetTelegrams', function(citizen, opts)
    local cid = toCid(citizen)
    if not enabled() or not cid then return {} end
    opts = type(opts) == 'table' and opts or {}
    local limit = math.min(MAX_LIMIT, math.max(1, math.floor(tonumber(opts.limit) or Config.MaxInbox)))
    return I.getInbox(cid, limit, opts.unreadOnly)
end)

-- GetSentTelegrams(citizen, limit?) -> rows { id, subject, message, recipient_name, sent_at, recipients,
--   delivered, read_count, has_attachment, unclaimed } (one row per send; read_count is 0 when Config.Receipts.Enabled = false)
exports('GetSentTelegrams', function(citizen, limit)
    local cid = toCid(citizen)
    if not enabled() or not cid then return {} end
    return I.getSent(cid, math.min(MAX_LIMIT, math.max(1, math.floor(tonumber(limit) or Config.MaxSent or 50))))
end)

-- GetUnreadCount(citizen) -> number
exports('GetUnreadCount', function(citizen)
    local cid = toCid(citizen)
    if not enabled() or not cid then return 0 end
    return I.getUnreadCount(cid)
end)

-- MarkRead(citizen, id?) -> number of telegrams marked (omit id to mark everything read)
exports('MarkRead', function(citizen, id)
    local cid = toCid(citizen)
    if not enabled() or not cid or (id ~= nil and not I.validId(id)) then return 0 end
    return I.markRead(cid, id)
end)

-- DeleteTelegram(citizen, id) -> ok, reason
-- Only deletes delivered telegrams addressed to that citizen. Refuses (false, 'attachment') while an attachment is uncollected.
exports('DeleteTelegram', function(citizen, id)
    local cid = toCid(citizen)
    if not enabled() or not cid or not I.validId(id) then return false end
    return I.deleteTelegram(cid, id)
end)

-- DeleteReadTelegrams(citizen) -> number destroyed (read telegrams with nothing left to collect)
exports('DeleteReadTelegrams', function(citizen)
    local cid = toCid(citizen)
    if not enabled() or not cid then return 0 end
    return I.deleteRead(cid)
end)

---------------------------------
-- address book
---------------------------------
-- GetContacts(citizen) -> { { citizenid, name, nickname }, ... }
exports('GetContacts', function(citizen)
    local cid = toCid(citizen)
    if not enabled() or not cid then return {} end
    return I.getContacts(cid)
end)

-- AddContact(citizen, contact, nickname?) -> ok, reason
-- ok reasons: added | updated      failure reasons: disabled | invalid | self | contacts_full | not_found
exports('AddContact', function(citizen, contact, nickname)
    if not enabled() then return false, 'disabled' end
    local owner, contactCid = toCid(citizen), toCid(contact)
    if not owner or not contactCid then return false, 'invalid' end
    return I.addContact(owner, contactCid, nickname)
end)

-- RemoveContact(citizen, contact) -> boolean
exports('RemoveContact', function(citizen, contact)
    local owner, contactCid = toCid(citizen), toCid(contact)
    if not enabled() or not owner or not contactCid then return false end
    return I.removeContact(owner, contactCid)
end)

---------------------------------
-- block list
---------------------------------
-- GetBlocked(citizen) -> { { citizenid, name }, ... }
exports('GetBlocked', function(citizen)
    local cid = toCid(citizen)
    if not enabled() or not cid then return {} end
    return I.getBlocked(cid)
end)

-- IsBlocked(citizen, sender) -> boolean (has `citizen` blocked `sender`?)
exports('IsBlocked', function(citizen, sender)
    local owner, senderCid = toCid(citizen), toCid(sender)
    if not enabled() or not owner or not senderCid then return false end
    return I.isBlocked(owner, senderCid)
end)

-- BlockCitizen(citizen, target) -> ok, reason
-- ok reasons: added | already      failure reasons: disabled | invalid | self | blocks_full | not_found
exports('BlockCitizen', function(citizen, target)
    if not enabled() then return false, 'disabled' end
    local owner, targetCid = toCid(citizen), toCid(target)
    if not owner or not targetCid then return false, 'invalid' end
    return I.addBlock(owner, targetCid)
end)

-- UnblockCitizen(citizen, target) -> boolean
exports('UnblockCitizen', function(citizen, target)
    local owner, targetCid = toCid(citizen), toCid(target)
    if not enabled() or not owner or not targetCid then return false end
    return I.removeBlock(owner, targetCid)
end)

---------------------------------
-- OpenTelegrams(src, opts?) -> boolean
-- Opens the telegram UI for a player away from a post office (a house mailbox, a phone, ...).
-- The calling script is responsible for checking that the player may use that place.
-- opts.label   : title shown under "Telegram Office" (default "Post Office")
-- opts.seconds : how long the player may keep using it (default Config.API.AccessSeconds); ends when the UI closes
-- opts.coords / opts.radius : optional - the UI closes by itself when the player walks further than radius from coords
---------------------------------
exports('OpenTelegrams', function(src, opts)
    if not enabled() or math.type(src) ~= 'integer' or not RSGCore.Functions.GetPlayer(src) then return false end
    opts = type(opts) == 'table' and opts or {}
    I.grantAccess(src, opts.seconds or Config.API.AccessSeconds)
    local label = I.sanitize(opts.label, 60)
    local coords = (type(opts.coords) == 'vector3' or (type(opts.coords) == 'table' and opts.coords.x)) and opts.coords or nil
    TriggerClientEvent('rsg-telegram:client:open', src, label, coords, coords and tonumber(opts.radius) or nil)
    return true
end)

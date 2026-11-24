Config = {}

---------------------------------
-- general
---------------------------------
Config.Debug          = false
Config.AutoDatabase   = true        -- create / update the rsg_telegrams tables automatically on start
Config.PromptKey      = 0xF3830D8E  -- [J]
Config.PromptDistance = 2.0
Config.SendCost       = 0.50        -- cash cost to send a telegram (0 = free)
Config.MoneyType      = 'cash'
Config.MaxSubject     = 50
Config.MaxMessage     = 1000
Config.MaxInbox       = 50          -- max telegrams the API returns per call
Config.InboxPageSize  = 25          -- telegrams the inbox loads at a time ('Load more' fetches the next page)
Config.SendCooldown   = 30          -- seconds between telegrams per player
Config.DeliveryDelay  = 0           -- seconds before the telegram arrives (0 = instant)
Config.SearchMinChars = 2
Config.MaxContacts    = 50          -- max entries in a player's address book
Config.PurgeReadAfterDays   = 30    -- delete READ telegrams older than this days (0 = keep forever); runs on start and every 6 hours
Config.PurgeUnreadAfterDays = 0     -- delete UNREAD telegrams older than this many days (0 = keep forever)
Config.MaxStoredPerPlayer   = 200   -- most telegrams one character can hold; oldest are removed beyond this (0 = unlimited)
Config.DirectorySearch      = true  -- let players search all characters by name when writing / adding contacts
Config.SearchByCitizenId    = true  -- directory search also matches an exact citizen ID (set false to avoid exposing IDs)
Config.ShowCitizenIds       = true  -- show citizen IDs next to names in the UI (false = names only; IDs are still used internally)
Config.PurgeDeletedCharacters = true -- remove telegrams, contacts, blocks and settings of characters that no longer exist in the players table
Config.PurgeDeletedAfterDays  = 7    -- ...once the telegram is at least this many days old

---------------------------------
-- push-to-talk while the UI is open
---------------------------------
-- The telegram UI keeps game input so voice keeps working; all other controls are blocked while it is open
Config.AllowPushToTalkWhileOpen = true
Config.PushToTalkControls = {
    0x4BC9DABB, -- INPUT_PUSH_TO_TALK
}

---------------------------------
-- API (exports other resources can call, see DOCS.md)
---------------------------------
Config.API = {
    Enabled          = true,              -- false disables every export below (they return false / empty)
    SystemSenderName = 'Telegraph Office', -- sender name shown when a script sends without a character
    AccessSeconds    = 900,               -- how long OpenTelegrams() lets a player use the UI away from a post office
}

---------------------------------
-- sent folder, receipts and block list
---------------------------------
Config.MaxSent    = 50   -- sent telegrams listed in the Sent tab
Config.MaxBlocked = 100  -- block list size per character

Config.Receipts = {
    Enabled         = true,  -- sender sees In transit / Delivered / Read in the Sent tab (false = never show read status)
    NotifyDelivered = false, -- toast to the sender when a delayed telegram arrives
    NotifyRead      = false, -- toast to the sender when the recipient reads it (needs Enabled = true)
}

---------------------------------
-- attachments (cash and items travel with a telegram and are collected by the recipient)
---------------------------------
Config.Attachments = {
    Enabled       = true,
    Fee           = 0.50,   -- extra fee on top of SendCost when a telegram carries an attachment
    MaxCash       = 500,    -- most cash one telegram can carry
    MaxItems      = 3,      -- different item types per telegram
    MaxItemAmount = 20,     -- most of one item per telegram
    -- unique items (items with their own data) and weapons can never be attached; these are blocked on top of that
    BlockedItems  = { 'dollar', 'cent', 'blood_dollar', 'blood_cent' },
    AllowedItems  = {},     -- if you list items here, ONLY these can be attached
}

---------------------------------
-- offices: telegrams addressed to a job instead of a person
-- Every character whose job is `job` receives a copy (online or offline, max MaxJobRecipients).
-- Needs the `job` column on the players table. Leave empty to turn the feature off.
---------------------------------
Config.JobAddresses = {
    -- { job = 'vallaw', label = 'Valentine Sheriff Office' },
    -- { job = 'valmedic', label = 'Valentine Doctor' },
}
Config.MaxJobRecipients = 25

---------------------------------
-- post offices (region = rsg-economy region id, used by Config.Economy)
---------------------------------
Config.PostOffices = {
    { name = 'Valentine Post Office',   coords = vector3(-178.90, 626.71, 114.09),   showblip = true, region = 'valentine' },
    { name = 'Rhodes Post Office',      coords = vector3(1225.57, -1293.87, 76.91),  showblip = true, region = 'rhodes' },
    { name = 'Saint Denis Post Office', coords = vector3(2731.55, -1402.37, 46.18),  showblip = true, region = 'saint_denis' },
    { name = 'Blackwater Post Office',  coords = vector3(-875.08, -1328.75, 43.96),  showblip = true, region = 'blackwater' },
    { name = 'Strawberry Post Office',  coords = vector3(-1765.07, -384.22, 157.74), showblip = true, region = 'strawberry' },
    { name = 'Annesburg Post Office',   coords = vector3(2939.47, 1288.21, 44.65),   showblip = true, region = 'annesburg' },
    { name = 'Tumbleweed Post Office',  coords = vector3(-5487.28, -2936.25, -0.40), showblip = true, region = 'tumbleweed' },
    { name = 'Armadillo Post Office',   coords = vector3(-3733.94, -2597.94, -12.93),showblip = true, region = 'armadillo' },
}

Config.Blip = {
    sprite = 1861010125, -- post office
    style  = 1664425300,
}

---------------------------------
-- unread badge: a small envelope with the unread count on screen while you have unread telegrams
---------------------------------
Config.UnreadBadge = {
    Enabled = true,
    Corner  = 'top-right', -- 'top-right' | 'top-left' | 'bottom-right' | 'bottom-left'
}

---------------------------------
-- delivery time by distance: the further the recipient is from the sender, the longer it takes
-- (added to Config.DeliveryDelay; only for recipients who are online when the telegram is sent)
---------------------------------
Config.DeliveryDistance = {
    Enabled     = false,
    SecondsPerKm = 20,
    Max         = 180, -- most seconds the distance can add
}

---------------------------------
-- anonymous telegrams: the recipient sees the sender as "Anonymous" and can block, but not reply to, them.
-- The sender is still stored in the database so staff can trace abuse.
---------------------------------
Config.Anonymous = {
    Enabled = true,
    Fee     = 2.00, -- extra fee for an anonymous telegram
}

---------------------------------
-- notices (/notice) and broadcasts (/telegrambroadcast)
---------------------------------
Config.Notices = {
    Enabled       = true,
    Jobs          = { 'vallaw', 'rholaw', 'stdenlaw', 'strlaw', 'blklaw' }, -- jobs that may send an official notice to everyone online
    RequireOnDuty = true,
    Cooldown      = 600,  -- seconds between notices per character
    MaxRecipients = 300,
}
Config.Broadcast = {
    MaxAll = 5000, -- most characters an admin broadcast to "all" can reach
}

---------------------------------
-- mailboxes: admin-placed mailbox props (rsg-gizmo + rsg-target) that open the telegram UI
-- /addmailbox places one; target a mailbox as an admin to remove it
---------------------------------
Config.Mailbox = {
    Enabled       = true,
    Model         = 'p_mailbox01x', -- confirmed in rdr3_discoveries objects/object_list.lua
    Permission    = 'admin',        -- rsg-core permission that may place / remove mailboxes
    Max           = 100,
    Distance      = 2.0,            -- rsg-target interaction distance
    SpawnDistance = 75.0,           -- props stream in / out around the player
    PlaceDistance = 6.0,            -- rsg-gizmo placement range
    Blip          = false,          -- map blip on every mailbox
}

---------------------------------
-- rsg-economy: post office fees go through Quote / Record (tax + town treasury) when started
-- (uses the `region` of the post office the player is standing at; mailboxes have none)
---------------------------------
Config.Economy = {
    Enabled  = false,
    Category = 'sales', -- rsg-economy tax category
}

---------------------------------
-- rsg-reputation: standing gained in the post office's region for every telegram sent
---------------------------------
Config.Reputation = {
    Enabled         = false,
    StandingPerSend = 1,
}

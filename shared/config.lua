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
Config.MaxInbox       = 50          -- max telegrams returned in the inbox
Config.SendCooldown   = 30          -- seconds between telegrams per player
Config.DeliveryDelay  = 0           -- seconds before the telegram arrives (0 = instant)
Config.SearchMinChars = 2
Config.MaxContacts    = 50          -- max entries in a player's address book
Config.PurgeReadAfterDays   = 30    -- delete READ telegrams older than this days (0 = keep forever); runs on start and every 6 hours
Config.PurgeUnreadAfterDays = 0     -- delete UNREAD telegrams older than this many days (0 = keep forever)
Config.MaxStoredPerPlayer   = 200   -- most telegrams one character can hold; oldest are removed beyond this (0 = unlimited)
Config.DirectorySearch      = true  -- let players search all characters by name when writing / adding contacts
Config.SearchByCitizenId    = true  -- directory search also matches an exact citizen ID (set false to avoid exposing IDs)

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
-- post offices
---------------------------------
Config.PostOffices = {
    { name = 'Valentine Post Office',   coords = vector3(-178.90, 626.71, 114.09),   showblip = true },
    { name = 'Rhodes Post Office',      coords = vector3(1225.57, -1293.87, 76.91),  showblip = true },
    { name = 'Saint Denis Post Office', coords = vector3(2731.55, -1402.37, 46.18),  showblip = true },
    { name = 'Blackwater Post Office',  coords = vector3(-875.08, -1328.75, 43.96),  showblip = true },
    { name = 'Strawberry Post Office',  coords = vector3(-1765.07, -384.22, 157.74), showblip = true },
    { name = 'Annesburg Post Office',   coords = vector3(2939.47, 1288.21, 44.65),   showblip = true },
    { name = 'Tumbleweed Post Office',  coords = vector3(-5487.28, -2936.25, -0.40), showblip = true },
    { name = 'Armadillo Post Office',   coords = vector3(-3733.94, -2597.94, -12.93),showblip = true },
}

Config.Blip = {
    sprite = 1861010125, -- post office
    style  = 1664425300,
}

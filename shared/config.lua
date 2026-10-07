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
Config.PurgeReadAfterDays = 30      -- delete READ telegrams older than this on resource start (0 = keep forever)

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

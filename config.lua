Config = {}

-- settings
Config.CostPerTelegram = 0.50 -- cost associated with sending a telegram

Config.Blip = {
    blipName =  Lang:t('primary.post_office'), -- Config.Blip.blipName
    blipSprite = 'blip_post_office', -- Config.Blip.blipSprite
    blipScale = 0.2 -- Config.Blip.blipScale
}

-- prompt locations
Config.PostOfficeLocations = {

    {name = Lang:t('primary.post_office'), location = 'valentine-postoffice',  coords = vector3(-178.9489, 626.83941, 114.08961), showblip = true}, -- valentine
    {name = Lang:t('primary.post_office'), location = 'rhodes-postoffice',     coords = vector3(1225.57, -1293.87, 76.91),        showblip = true}, -- rhodes
    {name = Lang:t('primary.post_office'), location = 'saintdenis-postoffice', coords = vector3(2731.55, -1402.37, 46.18),        showblip = true}, -- saintdenis
    {name = Lang:t('primary.post_office'), location = 'vanhorn-postoffice',    coords = vector3(2986.1557, 568.51599, 44.627922), showblip = true}, -- vanhorn
    {name = Lang:t('primary.post_office'), location = 'annsburg-postoffice',   coords = vector3(2939.5173, 1288.5345, 44.652824), showblip = true}, -- annsburg
    {name = Lang:t('primary.post_office'), location = 'wallace-postoffice',    coords = vector3(-1299.277, 401.93942, 95.383865), showblip = true}, -- wallace
    {name = Lang:t('primary.post_office'), location = 'riggs-postoffice',      coords = vector3(-1094.87, -575.608, 82.410873),   showblip = true}, -- riggs
    {name = Lang:t('primary.post_office'), location = 'flatneck-postoffice',   coords = vector3(-875.054, -1328.753, 43.958003),  showblip = true}, -- flatneck
    {name = Lang:t('primary.post_office'), location = 'armadillo-postoffice',  coords = vector3(-3733.965, -2597.86, -12.92674),  showblip = true}, -- armadillo
    {name = Lang:t('primary.post_office'), location = 'tumbleweed-postoffice', coords = vector3(-5487.083, -2936.11, -0.402813),  showblip = true}, -- tumbleweed
    {name = Lang:t('primary.post_office'), location = 'strawberry-postoffice', coords = vector3(-1765.084, -384.1582, 157.74119), showblip = true}, -- strawberry
    
}

fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

author 'RexShack#3041'
description 'rsg-telegram'

ui_page('client/html/ui.html')

shared_scripts {
    '@rsg-core/shared/locale.lua',
    'locales/en.lua',
    'locales/*.lua',
    'config.lua',
}

client_scripts {
    'client/client.lua'
}

server_scripts {
    'server/server.lua',
    '@oxmysql/lib/MySQL.lua',
}

files {
    'client/html/ui.html', 
    'client/html/style.css',
    'client/html/script.js',
    'client/html/bg.png'
}

dependencies {
    'rsg-core',
    'rsg-input',
    'rsg-menu'
}

lua54 'yes'

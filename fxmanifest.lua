fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

description 'rsg-telegram'
version '3.3.0'

shared_scripts {
    '@rsg-core/shared/locale.lua',
    'shared/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua',
    'server/mailbox.lua',
    'server/api.lua',
    'server/versionchecker.lua'
}

client_scripts {
    'client/client.lua',
    'client/mailbox.lua'
}

ui_page 'html/index.html'

files {
    'locales/*.json',
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

dependencies {
    'rsg-core',
    'rsg-inventory',
    'rsg-target',
    'rsg-gizmo',
    'oxmysql',
}

lua54 'yes'

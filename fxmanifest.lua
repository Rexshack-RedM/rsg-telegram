fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

description 'rsg-telegram'
version '1.0.7'

ui_page('html/ui.html')

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/functions.lua',
    '@rsg-core/shared/locale.lua',
    'locales/en.lua',
    'locales/*.lua'
}

client_scripts {
    'client/client.lua'
}

files {
    'html/ui.html',
    'html/style.css',
    'html/script.js',
    'html/*.png'
}

dependencies {
   'ox_lib'
}

lua54 'yes'

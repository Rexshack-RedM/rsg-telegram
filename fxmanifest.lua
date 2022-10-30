fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

author 'RexShack#3041'
description 'rsg-telegram'

ui_page('client/html/ui.html')

client_scripts {
    'client/client.lua'
}

server_scripts {
    'server/server.lua',
	'@oxmysql/lib/MySQL.lua',
}

shared_scripts {
    'config.lua'
}

files {
	'client/html/ui.html', 
    'client/html/style.css',
    'client/html/script.js',
    'client/html/bg.png'
}

dependencies {
    'qr-core',
	'qr-input',
	'qr-menu'
}

lua54 'yes'

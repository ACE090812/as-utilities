fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'as-utilities'
description 'LS Energy Networks - gas & electric meter engineer job'
author 'UK Central'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/util.lua',
}

client_scripts {
    'client/main.lua',
    'client/screen.lua',
    'client/minigames.lua',
    'client/meters.lua',
    'client/board.lua',
    'client/leaks.lua',
    'client/admin.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/dispatch.lua',
    'server/main.lua',
    'server/jobs.lua',
    'server/events.lua',
    'server/admin.lua',
}

files {
    'web/screen.html',
}

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'oxmysql',
    'qbx_core',
}

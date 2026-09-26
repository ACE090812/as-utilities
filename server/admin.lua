-- meter placement tool (staff)
local function isAdmin(src)
    return IsPlayerAceAllowed(src, 'command.utilmeter')
end

lib.addCommand('utilmeter', { help = 'LSEN: place utility meters', restricted = Config.AdminGroup }, function(src)
    TriggerClientEvent('as-utilities:admin:place', src)
end)

lib.addCommand('utilmeterdel', { help = 'LSEN: delete the nearest meter', restricted = Config.AdminGroup }, function(src)
    local pos = GetEntityCoords(GetPlayerPed(src))
    local best, bestD
    for id, m in pairs(Meters) do
        local d = #(m.coords - pos)
        if d < 5.0 and (not bestD or d < bestD) then best, bestD = id, d end
    end
    if not best then return Notify(src, 'No meter within 5m', 'error') end
    RemoveMeter(best)
    Notify(src, 'Meter #' .. best .. ' deleted', 'success')
end)

lib.addCommand('utilleak', { help = 'LSEN: start a gas leak at the nearest gas meter (testing)', restricted = Config.AdminGroup }, function(src)
    local pos = GetEntityCoords(GetPlayerPed(src))
    local best, bestD
    for _, m in pairs(Meters) do
        local d = #(m.coords - pos)
        if m.type == 'gas' and (not bestD or d < bestD) then best, bestD = m, d end
    end
    if not best then return Notify(src, 'No gas meters placed', 'error') end
    StartLeak(best)
end)

lib.callback.register('as-utilities:admin:add', function(src, mtype, coords, heading)
    if not isAdmin(src) then return false end
    if mtype ~= 'gas' and mtype ~= 'electric' then return false end
    if type(coords) ~= 'vector3' or not NearCoords(src, coords, 25.0) then return false end
    local p = GetQbxPlayer(src)
    local m = AddMeter(mtype, coords, (heading or 0.0) % 360.0, p and p.PlayerData.citizenid or tostring(src))
    return true, m.id
end)

-- core state, duty, engineers, meters, stores, vans, crews
Meters, Jobs, Duty, Crews, CrewOf, Vans, Sessions = {}, {}, {}, {}, {}, {}, {}
local Engineers = {}  -- citizenid -> { xp, jobs_done, earned }

local function getPlayer(src) return exports.qbx_core:GetPlayer(src) end
GetQbxPlayer = getPlayer

function Notify(src, msg, typ, dur)
    TriggerClientEvent('ox_lib:notify', src, { title = Config.Company, description = msg, type = typ or 'inform', duration = dur or 5000 })
end

function IsEngineer(src)
    local p = getPlayer(src)
    return p and p.PlayerData.job.name == Config.JobName
end

function OnDuty(src) return Duty[src] ~= nil end

function PlayerName(src)
    local p = getPlayer(src)
    if not p then return 'Unknown' end
    local ci = p.PlayerData.charinfo or {}
    return ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', '')
end

function NearCoords(src, coords, dist)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - coords) <= (dist or Config.InteractDistance)
end

function HasItem(src, item, count)
    return (exports.ox_inventory:GetItemCount(src, item) or 0) >= (count or 1)
end

---------------------------------------------------------------------
-- engineers (xp)
---------------------------------------------------------------------
function GetEngineer(cid)
    if Engineers[cid] then return Engineers[cid] end
    local row = MySQL.single.await('SELECT xp, jobs_done, earned FROM as_util_engineers WHERE citizenid = ?', { cid })
    if not row then
        MySQL.insert.await('INSERT INTO as_util_engineers (citizenid) VALUES (?)', { cid })
        row = { xp = 0, jobs_done = 0, earned = 0 }
    end
    Engineers[cid] = row
    return row
end

function AddXp(src, xp, pay)
    local p = getPlayer(src)
    if not p then return end
    local cid = p.PlayerData.citizenid
    local e = GetEngineer(cid)
    e.xp = e.xp + xp
    e.jobs_done = e.jobs_done + 1
    e.earned = e.earned + (pay or 0)
    MySQL.update('UPDATE as_util_engineers SET xp = ?, jobs_done = ?, earned = ? WHERE citizenid = ?', { e.xp, e.jobs_done, e.earned, cid })

    local target = Util.gradeForXp(e.xp)
    local current = p.PlayerData.job.grade.level
    if target > current then
        p.Functions.SetJob(Config.JobName, target)
        if Duty[src] then Duty[src].grade = target end
        Notify(src, ('Promoted to %s!'):format(Util.gradeLabel(target)), 'success', 8000)
    end
end

---------------------------------------------------------------------
-- meters
---------------------------------------------------------------------
local function publicMeter(m)
    return { id = m.id, type = m.type, coords = m.coords, heading = m.heading, smart = m.smart, state = m.state }
end

function SyncMeter(m)
    TriggerClientEvent('as-utilities:meterUpdate', -1, publicMeter(m))
end

function SaveMeter(m)
    MySQL.update('UPDATE as_util_meters SET smart = ?, state = ?, fault = ?, reading = ?, tampered_at = ? WHERE id = ?',
        { m.smart and 1 or 0, m.state, m.fault, m.reading, m.tamperedAt, m.id })
end

function SetMeterState(m, state, fault)
    m.state = state
    m.fault = fault
    if state ~= 'tampered' then m.tamperedAt = nil end
    SaveMeter(m)
    SyncMeter(m)
end

function AddMeter(mtype, coords, heading, by)
    local reading = math.random(1000, 60000) + 0.0
    local id = MySQL.insert.await('INSERT INTO as_util_meters (type, x, y, z, heading, reading, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { mtype, coords.x, coords.y, coords.z, heading, reading, by })
    local m = { id = id, type = mtype, coords = coords, heading = heading, smart = false, state = 'ok', reading = reading }
    Meters[id] = m
    SyncMeter(m)
    return m
end

function RemoveMeter(id)
    local m = Meters[id]
    if not m then return end
    if m.jobId then CancelJob(m.jobId, 'meter removed') end
    Meters[id] = nil
    MySQL.update('DELETE FROM as_util_meters WHERE id = ?', { id })
    TriggerClientEvent('as-utilities:meterRemoved', -1, id)
end

MySQL.ready(function()
    local rows = MySQL.query.await('SELECT * FROM as_util_meters') or {}
    for _, r in ipairs(rows) do
        Meters[r.id] = {
            id = r.id, type = r.type, coords = vec3(r.x, r.y, r.z), heading = r.heading,
            smart = r.smart == 1 or r.smart == true, state = r.state or 'ok', fault = r.fault,
            reading = r.reading or 0, tamperedAt = r.tampered_at,
        }
    end
    print(('[as-utilities] loaded %d meters'):format(#rows))
    RebuildJobsFromMeters()
    TriggerClientEvent('as-utilities:meters', -1, GetPublicMeters())
end)

function GetPublicMeters()
    local list = {}
    for _, m in pairs(Meters) do list[#list + 1] = publicMeter(m) end
    return list
end

lib.callback.register('as-utilities:getMeters', function() return GetPublicMeters() end)

-- readings tick every minute; tampered meters stop moving
CreateThread(function()
    local mins = 0
    while true do
        Wait(60000)
        mins = mins + 1
        for _, m in pairs(Meters) do
            if m.state ~= 'tampered' and m.state ~= 'leak' then
                m.reading = m.reading + (Config.ReadingRate[m.type] or 0.5) * (0.6 + math.random() * 0.8)
                if m.reading >= 99999 then m.reading = 0 end
            end
        end
        if mins % Config.ReadingPersistEvery == 0 then
            for _, m in pairs(Meters) do
                MySQL.update('UPDATE as_util_meters SET reading = ? WHERE id = ?', { m.reading, m.id })
            end
        end
    end
end)

-- public status for the idle panel (engineers only)
lib.callback.register('as-utilities:meterStatus', function(src, id)
    local m = Meters[id]
    if not m or not OnDuty(src) or not NearCoords(src, m.coords, Config.ScreenShowDistance + 2.0) then return nil end
    return { id = m.id, type = m.type, smart = m.smart, state = m.state, reading = math.floor(m.reading),
        serial = Util.serial(m.id, m.type), busy = m.jobId ~= nil }
end)

---------------------------------------------------------------------
-- duty
---------------------------------------------------------------------
lib.callback.register('as-utilities:clockOn', function(src, trade)
    local p = getPlayer(src)
    if not IsEngineer(src) then return false, 'You don\'t work for ' .. Config.Company end
    if not NearCoords(src, Config.Depot.clockOn.coords, 5.0) then return false, 'Too far from the depot' end
    local grade = p.PlayerData.job.grade.level
    if trade == 'dual' and grade < 3 then return false, 'You need Dual Fuel qualification' end
    if trade ~= 'gas' and trade ~= 'electric' and trade ~= 'dual' then return false, 'Invalid trade' end
    GetEngineer(p.PlayerData.citizenid)
    Duty[src] = { trade = trade, grade = grade, cid = p.PlayerData.citizenid }
    p.Functions.SetJobDuty(true)
    Player(src).state:set('utilDuty', trade, true)
    return true
end)

function ClockOff(src, silent)
    if not Duty[src] then return end
    LeaveCrew(src, true)
    AbandonJobsOf(src)
    ReturnVan(src, true)
    Duty[src] = nil
    Sessions[src] = nil
    Player(src).state:set('utilDuty', nil, true)
    local p = getPlayer(src)
    if p then
        p.Functions.SetJobDuty(false)
        if Config.RemoveItemsOnClockOff then
            for item in pairs(Config.Stores) do
                local c = exports.ox_inventory:GetItemCount(src, item)
                if c and c > 0 then exports.ox_inventory:RemoveItem(src, item, c) end
            end
        end
    end
    if not silent then Notify(src, 'Clocked off', 'inform') end
end

lib.callback.register('as-utilities:clockOff', function(src)
    ClockOff(src)
    return true
end)

AddEventHandler('playerDropped', function() ClockOff(source, true) end)
AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
    if Duty[src] and job.name ~= Config.JobName then ClockOff(src) end
end)

---------------------------------------------------------------------
-- stores
---------------------------------------------------------------------
lib.callback.register('as-utilities:restock', function(src)
    if not OnDuty(src) then return false end
    if not NearCoords(src, Config.Depot.stores.coords, 4.0) then return false end
    local given = 0
    for item, target in pairs(Config.Stores) do
        local have = exports.ox_inventory:GetItemCount(src, item) or 0
        if have < target and exports.ox_inventory:CanCarryItem(src, item, target - have) then
            exports.ox_inventory:AddItem(src, item, target - have)
            given = given + (target - have)
        end
    end
    return true, given
end)

---------------------------------------------------------------------
-- vans
---------------------------------------------------------------------
lib.callback.register('as-utilities:rentVan', function(src, index)
    if not OnDuty(src) then return false, 'Not on duty' end
    if Vans[src] then return false, 'You already have a van out' end
    local van = Config.Vans[index]
    if not van then return false end
    if Duty[src].grade < van.minGrade then return false, 'Your grade can\'t take this van' end
    if not NearCoords(src, Config.Depot.vanDesk.coords, 5.0) then return false, 'Too far' end
    local p = getPlayer(src)
    if not p.Functions.RemoveMoney(Config.DepositAccount, van.deposit, 'lsen-van-deposit') then
        return false, ('You need £%d for the deposit'):format(van.deposit)
    end
    local s = Config.Depot.vanSpawn
    local veh = CreateVehicleServerSetter(joaat(van.model), 'automobile', s.x, s.y, s.z, s.w)
    local t = GetGameTimer()
    while not DoesEntityExist(veh) and GetGameTimer() - t < 5000 do Wait(50) end
    if not DoesEntityExist(veh) then
        p.Functions.AddMoney(Config.DepositAccount, van.deposit, 'lsen-van-refund')
        return false, 'Van failed to spawn'
    end
    local plate = (Config.VanPlatePrefix .. math.random(1000, 9999)):sub(1, 8)
    SetVehicleNumberPlateText(veh, plate)
    Entity(veh).state:set('fuel', 100.0, true)
    Entity(veh).state:set('lsenVan', src, true)
    Vans[src] = { entity = veh, deposit = van.deposit, plate = plate }
    Config.GiveVanKeys(src, veh, plate)
    TaskWarpPedIntoVehicle(GetPlayerPed(src), veh, -1)
    return true, NetworkGetNetworkIdFromEntity(veh), plate, Config.VanLivery
end)

function ReturnVan(src, forfeit)
    local v = Vans[src]
    if not v then return false end
    Vans[src] = nil
    local refund = 0
    if DoesEntityExist(v.entity) then
        if not forfeit then
            local lost = (1000 - math.max(0, GetVehicleBodyHealth(v.entity))) + (1000 - math.max(0, GetVehicleEngineHealth(v.entity)))
            lost = math.min(2000, math.max(0, lost))
            refund = math.max(0, math.floor(v.deposit - lost * Config.DamageCostPerPoint))
        end
        DeleteEntity(v.entity)
    end
    if refund > 0 then
        local p = getPlayer(src)
        if p then p.Functions.AddMoney(Config.DepositAccount, refund, 'lsen-van-refund') end
    end
    return true, refund, v.deposit
end

lib.callback.register('as-utilities:returnVan', function(src)
    local v = Vans[src]
    if not v then return false, 'No van out' end
    if not DoesEntityExist(v.entity) then
        Vans[src] = nil
        return false, 'Your van is gone - deposit forfeited'
    end
    if #(GetEntityCoords(v.entity) - Config.Depot.vanReturn.coords) > Config.Depot.vanReturn.radius + 4.0 then
        return false, 'Bring the van to the return bay'
    end
    local ok, refund, deposit = ReturnVan(src, false)
    return ok, ('Van returned. Refunded £%d of £%d deposit'):format(refund, deposit)
end)

---------------------------------------------------------------------
-- crews
---------------------------------------------------------------------
function CrewMembers(src)
    local leader = CrewOf[src] or src
    local c = Crews[leader]
    if not c then return { src }, src end
    local list = {}
    for m in pairs(c.members) do list[#list + 1] = m end
    return list, leader
end

function LeaveCrew(src, silent)
    local leader = CrewOf[src]
    if not leader then return end
    local c = Crews[leader]
    CrewOf[src] = nil
    if not c then return end
    c.members[src] = nil
    if leader == src then
        -- disband: members keep nothing, job goes back unless someone else takes over
        for m in pairs(c.members) do
            CrewOf[m] = nil
            Notify(m, 'Your crew was disbanded', 'error')
        end
        Crews[leader] = nil
    else
        Notify(leader, PlayerName(src) .. ' left your crew', 'inform')
        local count = 0
        for _ in pairs(c.members) do count = count + 1 end
        if count <= 1 then CrewOf[leader] = nil; Crews[leader] = nil end
    end
    if not silent then Notify(src, 'You left the crew', 'inform') end
    TriggerClientEvent('as-utilities:refreshJob', -1)
end

lib.addCommand('crewinvite', { help = 'Invite an engineer to your LSEN crew', params = { { name = 'id', type = 'playerId', help = 'Server ID' } } }, function(src, args)
    local target = args.id
    if not OnDuty(src) or not OnDuty(target) then return Notify(src, 'Both of you must be on duty', 'error') end
    if target == src then return end
    if CrewOf[src] and CrewOf[src] ~= src then return Notify(src, 'Only the crew leader can invite', 'error') end
    if CrewOf[target] then return Notify(src, 'They are already in a crew', 'error') end
    if not NearCoords(src, GetEntityCoords(GetPlayerPed(target)), 15.0) then return Notify(src, 'They need to be near you', 'error') end
    local c = Crews[src]
    local size = 1
    if c then
        size = 0
        for _ in pairs(c.members) do size = size + 1 end
    end
    if size >= 4 then return Notify(src, 'Crew is full (4)', 'error') end
    local accepted = lib.callback.await('as-utilities:crewInvite', target, PlayerName(src))
    if not accepted then return Notify(src, 'Invite declined', 'error') end
    if not Crews[src] then
        Crews[src] = { leader = src, members = { [src] = true } }
        CrewOf[src] = src
    end
    Crews[src].members[target] = true
    CrewOf[target] = src
    Notify(src, PlayerName(target) .. ' joined your crew', 'success')
    Notify(target, 'You joined ' .. PlayerName(src) .. '\'s crew', 'success')
    TriggerClientEvent('as-utilities:refreshJob', -1)
end)

lib.addCommand('crewleave', { help = 'Leave your LSEN crew' }, function(src) LeaveCrew(src) end)

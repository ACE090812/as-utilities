-- job generation, player reports, copper theft, gas leaks, scrap buyer
Leaks = {}
local reportCooldown, stripCooldown = {}, {}

local function openJobCount()
    local n = 0
    for _ in pairs(Jobs) do n = n + 1 end
    return n
end

local function freeMeters(filter)
    local list = {}
    for _, m in pairs(Meters) do
        if not m.jobId and filter(m) then list[#list + 1] = m end
    end
    return list
end

local function pick(list) return list[math.random(#list)] end

local function weightedKind()
    local w = Config.Generation.weights
    local total = 0
    for _, v in pairs(w) do total = total + v end
    local r = math.random() * total
    for k, v in pairs(w) do
        r = r - v
        if r <= 0 then return k end
    end
    return 'read'
end

---------------------------------------------------------------------
-- generators
---------------------------------------------------------------------
local function genRead()
    local pool = freeMeters(function(m) return not m.smart and m.state == 'ok' end)
    if #pool == 0 then return end
    local seed = pick(pool)
    local size = math.random(Config.Generation.readRouteSize[1], Config.Generation.readRouteSize[2])
    table.sort(pool, function(a, b) return #(a.coords - seed.coords) < #(b.coords - seed.coords) end)
    local ids, kinds = {}, {}
    for _, m in ipairs(pool) do
        if #ids >= size then break end
        if m.type == seed.type and #(m.coords - seed.coords) <= Config.Generation.readRouteRadius then
            ids[#ids + 1] = m.id
            kinds[#kinds + 1] = 'read'
        end
    end
    CreateJob('read', ids, kinds)
end

local function genFault()
    local pool = freeMeters(function(m) return m.state == 'ok' end)
    if #pool == 0 then return end
    local m = pick(pool)
    local fault = pick(Config.Faults[m.type])
    SetMeterState(m, 'faulty', fault)
    CreateJob('fault', { m.id }, { fault })
end

local function genInstall()
    local pool = freeMeters(function(m) return not m.smart and m.state == 'ok' end)
    if #pool == 0 then return end
    local m = pick(pool)
    CreateJob('install', { m.id }, { 'install' })
end

function StartLeak(m)
    if Leaks[m.id] then return end
    if m.jobId then CancelJob(m.jobId, 'gas leak at this meter') end
    SetMeterState(m, 'leak', nil)
    Leaks[m.id] = {
        meterId = m.id, coords = m.coords, stage = 'sweep', cones = {}, startedAt = os.time(),
        escalateAt = os.time() + Config.Leak.escalateAfter, lastIgnite = 0,
    }
    CreateJob('leak', { m.id }, { 'leak' }, { priority = 10 })
    TriggerClientEvent('as-utilities:leakStart', -1, m.id, m.coords)
    for src, d in pairs(Duty) do
        if Util.tradeAllows(d.trade, 'gas') then
            TriggerClientEvent('as-utilities:emergency', src, m.coords)
        end
    end
    Dispatch.send({
        title = 'Gas leak', code = '10-70', priority = 1,
        message = ('Reported gas leak at %s meter %s - cordon and keep people back'):format(Config.CompanyShort, Util.serial(m.id, 'gas')),
        coords = m.coords, jobs = Config.Leak.alertJobs, sprite = 436, colour = 1,
    })
end

function EndLeak(meterId, repaired)
    local leak = Leaks[meterId]
    if not leak then return end
    for _, net in ipairs(leak.cones) do
        local e = NetworkGetEntityFromNetworkId(net)
        if e ~= 0 and DoesEntityExist(e) then DeleteEntity(e) end
    end
    Leaks[meterId] = nil
    TriggerClientEvent('as-utilities:leakEnd', -1, meterId)
end

local function leakCount()
    local n = 0
    for _ in pairs(Leaks) do n = n + 1 end
    return n
end

local function genLeak()
    if leakCount() >= Config.Leak.maxActive then return end
    local pool = freeMeters(function(m) return m.type == 'gas' and m.state == 'ok' end)
    if #pool == 0 then return end
    StartLeak(pick(pool))
end

-- rebuild on restart from persisted meter states
function RebuildJobsFromMeters()
    for _, m in pairs(Meters) do
        if m.state == 'faulty' and m.fault then
            CreateJob('fault', { m.id }, { m.fault })
        elseif m.state == 'tampered' then
            CreateJob('tamper', { m.id }, { 'tamper' })
        elseif m.state == 'leak' then
            SetMeterState(m, 'ok', nil)
        end
    end
end

CreateThread(function()
    Wait(10000)
    while true do
        if openJobCount() < Config.Generation.maxOpenJobs then
            local kind = weightedKind()
            if kind == 'read' then genRead()
            elseif kind == 'fault' then genFault()
            elseif kind == 'install' then genInstall() end
        end
        if math.random(100) <= Config.Generation.leakChance then genLeak() end

        -- tamper detection: smart meters flag instantly, others after detectDelay
        local now = os.time()
        for _, m in pairs(Meters) do
            if m.state == 'tampered' and not m.jobId and m.tamperedAt then
                if m.smart or now - m.tamperedAt >= Config.Tamper.detectDelay then
                    CreateJob('tamper', { m.id }, { 'tamper' }, { priority = 3 })
                end
            end
        end
        Wait(Config.Generation.interval * 1000)
    end
end)

---------------------------------------------------------------------
-- public fault reports
---------------------------------------------------------------------
lib.callback.register('as-utilities:reportFault', function(src, meterId)
    local m = Meters[meterId]
    if not m or not NearCoords(src, m.coords, Config.InteractDistance + 1.0) then return false end
    local last = reportCooldown[src]
    if last and os.time() - last < Config.Report.playerCooldown then return false, 'You reported a fault recently' end
    if m.jobId or m.state ~= 'ok' then return false, 'An engineer is already booked for this meter' end
    reportCooldown[src] = os.time()
    local real = math.random(100) <= Config.Report.realFaultChance
    local task = 'inspect'
    if real then
        task = pick(Config.Faults[m.type])
        SetMeterState(m, 'faulty', task)
    end
    CreateJob('report', { m.id }, { task }, { priority = 5, reporter = PlayerName(src) })
    return true
end)

---------------------------------------------------------------------
-- copper theft
---------------------------------------------------------------------
lib.callback.register('as-utilities:canStrip', function(src, meterId)
    local m = Meters[meterId]
    if not m or not NearCoords(src, m.coords) then return false end
    if not HasItem(src, Config.Items.bypass) then return false, 'You need a bypass kit' end
    local cops = exports.qbx_core:GetDutyCountType(Config.Tamper.policeJobType) or 0
    if cops < Config.Tamper.minPolice then return false, 'Too risky right now' end
    if m.state ~= 'ok' or m.jobId then return false, 'Someone\'s been at this one already' end
    if stripCooldown[meterId] and os.time() - stripCooldown[meterId] < Config.Tamper.meterCooldown then
        return false, 'Nothing worth taking left'
    end
    stripCooldown[meterId] = os.time()  -- reserve
    if math.random(100) <= Config.Tamper.witnessAlertChance then
        Dispatch.send({
            title = 'Suspicious person at utility meter', code = '10-66',
            message = 'Caller reports someone tampering with a meter box',
            coords = m.coords, jobs = { 'police' }, sprite = 354, colour = 5,
        })
    end
    return true
end)

lib.callback.register('as-utilities:stripResult', function(src, meterId, success)
    local m = Meters[meterId]
    if not m or not NearCoords(src, m.coords) then return false end
    if not stripCooldown[meterId] or os.time() - stripCooldown[meterId] > 120 then return false end
    if m.state ~= 'ok' then return false end
    if not success then
        if m.type == 'gas' and math.random(100) <= Config.Tamper.failGasLeakChance then
            StartLeak(m)
            return false, 'leak'
        end
        return false, m.type == 'electric' and 'shock' or nil
    end
    local amount = math.random(Config.Tamper.copper[1], Config.Tamper.copper[2])
    if not exports.ox_inventory:CanCarryItem(src, Config.Items.copper, amount) then return false, 'full' end
    exports.ox_inventory:AddItem(src, Config.Items.copper, amount)
    m.tamperedAt = os.time()
    SetMeterState(m, 'tampered', nil)
    m.tamperedAt = os.time()
    SaveMeter(m)
    return true, amount
end)

---------------------------------------------------------------------
-- scrap buyer
---------------------------------------------------------------------
lib.callback.register('as-utilities:sellCopper', function(src)
    if not Config.ScrapBuyer.enabled then return false end
    local c = Config.ScrapBuyer.coords
    if not NearCoords(src, vec3(c.x, c.y, c.z), 4.0) then return false end
    local count = exports.ox_inventory:GetItemCount(src, Config.Items.copper) or 0
    if count < 1 then return false, 'You have no copper' end
    local price = math.random(Config.ScrapBuyer.price[1], Config.ScrapBuyer.price[2])
    if exports.ox_inventory:RemoveItem(src, Config.Items.copper, count) then
        GetQbxPlayer(src).Functions.AddMoney(Config.ScrapBuyer.account, price * count, 'scrap-copper')
        return true, price * count, count
    end
    return false
end)

---------------------------------------------------------------------
-- leaks: sweep, cordon, ignition, escalation
---------------------------------------------------------------------
local function leakJobIsMine(src, meterId)
    local job = JobOfCrew(src)
    return job and job.kind == 'leak' and job.meters[1] == meterId and job
end

lib.callback.register('as-utilities:leakSweep', function(src, meterId)
    local leak = Leaks[meterId]
    local job = leakJobIsMine(src, meterId)
    if not leak or not job or leak.stage ~= 'sweep' then return false end
    if not HasItem(src, Config.Items.detector) or not NearCoords(src, leak.coords, 2.5) then return false end
    leak.stage = 'cordon'
    PushJob(job)
    return true
end)

lib.callback.register('as-utilities:placeCone', function(src, meterId, pos)
    local leak = Leaks[meterId]
    local job = leakJobIsMine(src, meterId)
    if not leak or not job or leak.stage ~= 'cordon' or type(pos) ~= 'vector3' then return false end
    if not NearCoords(src, pos, 3.0) then return false end
    local d = #(pos - leak.coords)
    if d < Config.Leak.coneMinDist or d > Config.Leak.coneMaxDist then return false, 'Place cones around the edge of the zone' end
    for _, net in ipairs(leak.cones) do
        local e = NetworkGetEntityFromNetworkId(net)
        if e ~= 0 and #(GetEntityCoords(e) - pos) < 2.5 then return false, 'Spread the cones out' end
    end
    local obj = CreateObjectNoOffset(joaat(Config.Leak.coneModel), pos.x, pos.y, pos.z, true, true, false)
    local t = GetGameTimer()
    while not DoesEntityExist(obj) and GetGameTimer() - t < 3000 do Wait(20) end
    if not DoesEntityExist(obj) then return false end
    FreezeEntityPosition(obj, true)
    leak.cones[#leak.cones + 1] = NetworkGetNetworkIdFromEntity(obj)
    if #leak.cones >= Config.Leak.cones then leak.stage = 'repair' end
    PushJob(job)
    return true, #leak.cones
end)

local function explodeLeak(leak, byClient)
    leak.lastIgnite = os.time()
    local target = byClient
    if not target then
        local best, bestD
        for _, id in ipairs(GetPlayers()) do
            local ped = GetPlayerPed(id)
            if ped ~= 0 then
                local d = #(GetEntityCoords(ped) - leak.coords)
                if d < 250.0 and (not bestD or d < bestD) then best, bestD = tonumber(id), d end
            end
        end
        target = best
    end
    if target then TriggerClientEvent('as-utilities:leakExplode', target, leak.coords) end
end

RegisterNetEvent('as-utilities:leakIgnite', function(meterId)
    local src = source
    local leak = Leaks[meterId]
    if not leak or not NearCoords(src, leak.coords, Config.Leak.radius + 5.0) then return end
    if os.time() - leak.lastIgnite < Config.Leak.igniteCooldown then return end
    explodeLeak(leak, src)
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for _, leak in pairs(Leaks) do
            if now >= leak.escalateAt then
                leak.escalateAt = now + Config.Leak.escalateAfter
                explodeLeak(leak)
            end
        end
    end
end)

lib.callback.register('as-utilities:getLeaks', function()
    local list = {}
    for id, l in pairs(Leaks) do list[#list + 1] = { id = id, coords = l.coords } end
    return list
end)

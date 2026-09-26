-- meter props, targets, idle status panel, meter sessions, copper stripping
local MetersC = {}
local meterScreen

local WORK_ANIM = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }

local function propFor(m)
    local set = Config.Props[m.type] or Config.Props.electric
    return joaat(m.smart and set.smart or set.normal)
end

function MeterPanelPos(m)
    local f = Util.fwd(m.heading)
    return m.coords + f * Config.Screen.forward + vec3(0.0, 0.0, Config.Screen.up)
end

local function despawn(entry)
    if entry.obj and DoesEntityExist(entry.obj) then
        exports.ox_target:removeLocalEntity(entry.obj)
        DeleteEntity(entry.obj)
    end
    entry.obj = nil
end

local function spawn(entry)
    local m = entry.data
    local model = propFor(m)
    if not IsModelInCdimage(model) then return end
    lib.requestModel(model)
    local obj = CreateObject(model, m.coords.x, m.coords.y, m.coords.z, false, false, false)
    SetEntityHeading(obj, m.heading + Config.PropHeadingOffset)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)
    entry.obj, entry.model = obj, model
    local id = m.id
    exports.ox_target:addLocalEntity(obj, {
        { name = 'as_util_open', icon = 'fa-solid fa-gauge-high', label = 'Open meter', distance = 2.0,
          canInteract = function() return OnDuty() end, onSelect = function() OpenMeter(id) end },
        { name = 'as_util_report', icon = 'fa-solid fa-triangle-exclamation', label = 'Report a fault', distance = 2.0,
          canInteract = function() return not OnDuty() end, onSelect = function() ReportMeter(id) end },
        { name = 'as_util_strip', icon = 'fa-solid fa-scissors', label = 'Strip copper', distance = 1.5, items = Config.Items.bypass,
          canInteract = function() return not OnDuty() end, onSelect = function() StripMeter(id) end },
    })
end

local function setMeter(data)
    local e = MetersC[data.id]
    if e then
        local oldModel = propFor(e.data)
        e.data = data
        if e.obj and propFor(data) ~= oldModel then despawn(e) end
    else
        MetersC[data.id] = { data = data }
    end
end

RegisterNetEvent('as-utilities:meters', function(list)
    for _, e in pairs(MetersC) do despawn(e) end
    MetersC = {}
    for _, m in ipairs(list) do setMeter(m) end
end)
RegisterNetEvent('as-utilities:meterUpdate', setMeter)
RegisterNetEvent('as-utilities:meterRemoved', function(id)
    if MetersC[id] then despawn(MetersC[id]) MetersC[id] = nil end
end)

function GetMeterC(id) return MetersC[id] and MetersC[id].data end

CreateThread(function()
    local list = lib.callback.await('as-utilities:getMeters', false)
    if list then for _, m in ipairs(list) do setMeter(m) end end
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for _, e in pairs(MetersC) do
            local d = #(pos - e.data.coords)
            if d < Config.SpawnDistance and not e.obj then spawn(e)
            elseif d > Config.SpawnDistance + 15.0 and e.obj then despawn(e) end
        end
        Wait(1000)
    end
end)

---------------------------------------------------------------------
-- idle status panel for on-duty engineers
---------------------------------------------------------------------
local function jobTaskFor(id)
    if not CurrentJob then return nil end
    for _, m in ipairs(CurrentJob.meters) do
        if m.id == id then return m end
    end
end

local function idlePayload(status)
    local wd = {}
    MeterUI.face(status, wd)
    local X, Y, WW = 530, 120, 710
    wd[#wd + 1] = W.panel(X, Y, WW, 640, 'STATUS')
    local t = jobTaskFor(status.id)
    local lines
    if t and not t.done then
        lines = { { 'ON YOUR JOB', 34, 'ok' }, { Config.FaultLabels[t.task] or t.task, 28 }, { 'Use the meter to start work.', 22, 'muted' } }
    elseif t and t.done then
        lines = { { 'DONE', 34, 'ok' }, { 'Work complete at this meter.', 24, 'muted' } }
    elseif status.busy then
        lines = { { 'BOOKED', 34, 'amber' }, { 'On another engineer\'s job sheet.', 24, 'muted' } }
    else
        lines = { { 'NO WORK BOOKED', 30, 'muted' } }
    end
    for i, l in ipairs(lines) do
        wd[#wd + 1] = W.text(X + 30, Y + 60 + (i - 1) * 60, WW - 60, l[1], l[2], { color = l[3], weight = i == 1 and 800 or 500 })
    end
    return {
        theme = 'meter',
        header = { title = Config.Company, sub = 'Field Engineer Handheld', badge = status.type:upper(), badgeColor = status.type == 'gas' and 'blue' or 'amber' },
        widgets = wd,
    }
end

CreateThread(function()
    meterScreen = Screen.new('meter')
    local current, status, lastFetch = nil, nil, 0
    while true do
        local sleep = 500
        if OnDuty() and not Screen.active then
            local pos = GetEntityCoords(PlayerPedId())
            local best, bestD
            for id, e in pairs(MetersC) do
                if e.obj then
                    local d = #(pos - e.data.coords)
                    if d < Config.ScreenShowDistance and (not bestD or d < bestD) then best, bestD = e.data, d end
                end
            end
            if best then
                sleep = 0
                local now = GetGameTimer()
                if current ~= best.id or now - lastFetch > 4000 then
                    current, lastFetch = best.id, now
                    CreateThread(function()
                        local s = lib.callback.await('as-utilities:meterStatus', false, best.id)
                        if s and current == s.id then status = s end
                    end)
                end
                if status and status.id == best.id then
                    meterScreen:send(idlePayload(status))
                    local alpha = math.floor(255 * math.min(1.0, (Config.ScreenShowDistance - bestD) / 1.0 + 0.2))
                    meterScreen:draw(MeterPanelPos(best), best.heading, Config.Screen.width, alpha)
                end
            else
                current, status = nil, nil
            end
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------
-- interaction
---------------------------------------------------------------------
local function playWork()
    local ped = PlayerPedId()
    lib.requestAnimDict(WORK_ANIM.dict)
    TaskPlayAnim(ped, WORK_ANIM.dict, WORK_ANIM.clip, 3.0, 3.0, -1, 1, 0, false, false, false)
end

function OpenMeter(id)
    local m = GetMeterC(id)
    if not m or Screen.active then return end
    local data = lib.callback.await('as-utilities:openMeter', false, id)
    if not data then return Notify('You can\'t use this meter right now', 'error') end
    local ped = PlayerPedId()
    TaskTurnPedToFaceCoord(ped, m.coords.x, m.coords.y, m.coords.z, 800)
    Wait(800)
    playWork()
    local ui = MeterUI.new(data)
    meterScreen:interact(MeterPanelPos(m), m.heading, Config.Screen.width, {
        build = function() return ui:build() end,
        click = function(wid) ui:click(wid) end,
        tick = function() ui:tick() end,
        shouldClose = function() return ui.closeNow end,
    })
    ClearPedTasks(ped)
end

function ReportMeter(id)
    local r = lib.alertDialog({
        header = 'Report a fault', centered = true, cancel = true,
        content = ('Report this meter to %s? An engineer will be sent out.'):format(Config.Company),
    })
    if r ~= 'confirm' then return end
    local ok, err = lib.callback.await('as-utilities:reportFault', false, id)
    Notify(ok and 'Fault reported - thanks. An engineer has been booked.' or (err or 'Could not report'), ok and 'success' or 'error')
end

function StripMeter(id)
    local m = GetMeterC(id)
    if not m then return end
    local ok, err = lib.callback.await('as-utilities:canStrip', false, id)
    if not ok then return Notify(err or 'You can\'t do that here', 'error') end
    local ped = PlayerPedId()
    TaskTurnPedToFaceCoord(ped, m.coords.x, m.coords.y, m.coords.z, 800)
    Wait(800)
    local done = lib.progressBar({
        duration = Config.Tamper.progress, label = 'Bypassing meter...', useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = WORK_ANIM.dict, clip = WORK_ANIM.clip, flag = 1 },
    })
    if not done then return end
    local success = lib.skillCheck(Config.Tamper.skill, { 'w', 'a', 's', 'd' })
    local res, extra = lib.callback.await('as-utilities:stripResult', false, id, success)
    if res then
        Notify(('You pulled %d lengths of copper wire'):format(extra), 'success')
    elseif extra == 'shock' then
        ApplyDamageToPed(ped, Config.Tamper.failShockDamage, false)
        SetPedToRagdoll(ped, 1500, 1500, 0, false, false, false)
        Notify('You took a nasty shock', 'error')
    elseif extra == 'leak' then
        Notify('You cracked the gas pipe - GET BACK!', 'error', 8000)
    elseif extra == 'full' then
        Notify('You can\'t carry any more', 'error')
    else
        Notify('You fumbled it', 'error')
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, e in pairs(MetersC) do despawn(e) end
    if meterScreen then meterScreen:destroy() end
end)

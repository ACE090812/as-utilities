-- duty, depot, vans, stores, job tracking, crews
CurrentJob = nil
local jobBlips = {}

function Notify(msg, typ, dur)
    lib.notify({ title = Config.Company, description = msg, type = typ or 'inform', duration = dur or 5000 })
end

function IsEngineer()
    local pd = exports.qbx_core:GetPlayerData()
    return pd and pd.job and pd.job.name == Config.JobName
end

function MyGrade()
    local pd = exports.qbx_core:GetPlayerData()
    return pd and pd.job and pd.job.grade and pd.job.grade.level or 0
end

function OnDuty() return LocalPlayer.state.utilDuty ~= nil end
function MyTrade() return LocalPlayer.state.utilDuty end

---------------------------------------------------------------------
-- uniform
---------------------------------------------------------------------
local function applyUniform()
    local ped = PlayerPedId()
    local set = GetEntityModel(ped) == joaat('mp_f_freemode_01') and Config.Uniform.female or Config.Uniform.male
    for _, c in ipairs(set) do SetPedComponentVariation(ped, c.component, c.drawable, c.texture, 0) end
end

local function restoreClothes()
    TriggerEvent('illenium-appearance:client:reloadSkin')
end

---------------------------------------------------------------------
-- job tracking
---------------------------------------------------------------------
local function clearJobBlips()
    for _, b in ipairs(jobBlips) do RemoveBlip(b) end
    jobBlips = {}
end

local function drawJobBlips()
    clearJobBlips()
    if not CurrentJob then return end
    local firstOpen
    for i, m in ipairs(CurrentJob.meters) do
        if not m.done then
            local b = AddBlipForCoord(m.coords.x, m.coords.y, m.coords.z)
            SetBlipSprite(b, CurrentJob.kind == 'leak' and 436 or 354)
            SetBlipColour(b, CurrentJob.kind == 'leak' and 1 or (m.type == 'gas' and 3 or 46))
            SetBlipScale(b, 0.85)
            ShowNumberOnBlip(b, i)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(('LSEN: %s'):format(Config.FaultLabels[m.task] or m.task))
            EndTextCommandSetBlipName(b)
            jobBlips[#jobBlips + 1] = b
            firstOpen = firstOpen or m
        end
    end
    if firstOpen then SetNewWaypoint(firstOpen.coords.x, firstOpen.coords.y) end
end

RegisterNetEvent('as-utilities:jobAssigned', function(job)
    local isNew = not CurrentJob or CurrentJob.id ~= job.id
    CurrentJob = job
    drawJobBlips()
    if isNew then Notify(('Job assigned: %s (%d meter%s)'):format(job.label, #job.meters, #job.meters > 1 and 's' or ''), 'success') end
    TriggerEvent('as-utilities:jobChanged')
end)

RegisterNetEvent('as-utilities:jobCleared', function(id)
    if CurrentJob and CurrentJob.id == id then
        CurrentJob = nil
        clearJobBlips()
        TriggerEvent('as-utilities:jobChanged')
    end
end)

RegisterNetEvent('as-utilities:emergency', function(coords)
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
    Notify('EMERGENCY: gas leak reported. Check the job board.', 'error', 10000)
    local b = AddBlipForRadius(coords.x, coords.y, coords.z, Config.Leak.radius * 3)
    SetBlipColour(b, 1)
    SetBlipAlpha(b, 120)
    SetTimeout(120000, function() RemoveBlip(b) end)
end)

lib.callback.register('as-utilities:crewInvite', function(from)
    local r = lib.alertDialog({
        header = 'Crew invite', content = ('%s wants you in their %s crew. Pay is split evenly.'):format(from, Config.CompanyShort),
        centered = true, cancel = true, labels = { confirm = 'Join', cancel = 'Decline' },
    })
    return r == 'confirm'
end)

---------------------------------------------------------------------
-- depot
---------------------------------------------------------------------
local function clockOn()
    local opts = {
        { title = 'Electric', description = 'Electricity meters', icon = 'bolt', trade = 'electric' },
        { title = 'Gas', description = 'Gas meters', icon = 'fire-flame-simple', trade = 'gas' },
    }
    if MyGrade() >= 3 then opts[#opts + 1] = { title = 'Dual Fuel', description = 'Both trades', icon = 'layer-group', trade = 'dual' } end
    for _, o in ipairs(opts) do
        local trade = o.trade
        o.onSelect = function()
            local ok, err = lib.callback.await('as-utilities:clockOn', false, trade)
            if not ok then return Notify(err or 'Could not clock on', 'error') end
            applyUniform()
            Notify(('Clocked on - %s. Grab your kit from stores and check the board.'):format(o.title), 'success')
        end
        o.trade = nil
    end
    lib.registerContext({ id = 'as_util_clockon', title = Config.Company .. ' - choose your trade', options = opts })
    lib.showContext('as_util_clockon')
end

local function clockOff()
    lib.callback.await('as-utilities:clockOff', false)
    CurrentJob = nil
    clearJobBlips()
    restoreClothes()
end

local function vanMenu()
    local opts = {}
    local grade = MyGrade()
    for i, v in ipairs(Config.Vans) do
        opts[#opts + 1] = {
            title = v.label, description = ('Deposit £%d%s'):format(v.deposit, grade < v.minGrade and (' - needs ' .. Util.gradeLabel(v.minGrade)) or ''),
            icon = 'van-shuttle', disabled = grade < v.minGrade,
            onSelect = function()
                local ok, netOrErr, plate, livery = lib.callback.await('as-utilities:rentVan', false, i)
                if not ok then return Notify(netOrErr or 'Could not rent a van', 'error') end
                Notify(('Van %s ready. Return it to the bay for your deposit.'):format(plate), 'success')
                if livery then
                    local veh = lib.waitFor(function()
                        local e = NetToVeh(netOrErr)
                        if e ~= 0 then return e end
                    end, nil, 3000)
                    if veh then SetVehicleLivery(veh, livery) end
                end
            end,
        }
    end
    lib.registerContext({ id = 'as_util_vans', title = 'Company vans', options = opts })
    lib.showContext('as_util_vans')
end

CreateThread(function()
    local d = Config.Depot
    local blip = AddBlipForCoord(d.blip.coords.x, d.blip.coords.y, d.blip.coords.z)
    SetBlipSprite(blip, d.blip.sprite)
    SetBlipColour(blip, d.blip.colour)
    SetBlipScale(blip, d.blip.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(d.blip.label)
    EndTextCommandSetBlipName(blip)

    exports.ox_target:addSphereZone({
        coords = d.clockOn.coords, radius = d.clockOn.radius,
        options = {
            { name = 'as_util_on', icon = 'fa-solid fa-id-badge', label = 'Clock on',
              canInteract = function() return IsEngineer() and not OnDuty() end, onSelect = clockOn },
            { name = 'as_util_off', icon = 'fa-solid fa-right-from-bracket', label = 'Clock off',
              canInteract = function() return OnDuty() end, onSelect = clockOff },
        },
    })
    exports.ox_target:addSphereZone({
        coords = d.stores.coords, radius = d.stores.radius,
        options = {
            { name = 'as_util_stores', icon = 'fa-solid fa-toolbox', label = 'Restock kit',
              canInteract = function() return OnDuty() end,
              onSelect = function()
                  local ok, n = lib.callback.await('as-utilities:restock', false)
                  if ok then Notify(n > 0 and ('Restocked %d items'):format(n) or 'You\'re fully stocked', 'success') else Notify('Can\'t restock', 'error') end
              end },
        },
    })
    exports.ox_target:addSphereZone({
        coords = d.vanDesk.coords, radius = d.vanDesk.radius,
        options = {
            { name = 'as_util_van', icon = 'fa-solid fa-van-shuttle', label = 'Rent company van',
              canInteract = function() return OnDuty() end, onSelect = vanMenu },
        },
    })

    local ret = lib.points.new({ coords = d.vanReturn.coords, distance = d.vanReturn.radius })
    function ret:nearby()
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh ~= 0 and Entity(veh).state.lsenVan == GetPlayerServerId(PlayerId()) then
            if not self.shown then lib.showTextUI('[E] Return company van') self.shown = true end
            if IsControlJustPressed(0, 38) then
                local ok, msg = lib.callback.await('as-utilities:returnVan', false)
                Notify(msg or (ok and 'Returned' or 'Failed'), ok and 'success' or 'error')
            end
        elseif self.shown then
            lib.hideTextUI() self.shown = false
        end
    end
    function ret:onExit() if self.shown then lib.hideTextUI() self.shown = false end end
end)

---------------------------------------------------------------------
-- scrap buyer
---------------------------------------------------------------------
if Config.ScrapBuyer.enabled then
    local sb = Config.ScrapBuyer
    local pt = lib.points.new({ coords = vec3(sb.coords.x, sb.coords.y, sb.coords.z), distance = 60 })
    function pt:onEnter()
        lib.requestModel(sb.ped)
        self.ped = CreatePed(4, joaat(sb.ped), sb.coords.x, sb.coords.y, sb.coords.z - 1.0, sb.coords.w, false, true)
        SetModelAsNoLongerNeeded(joaat(sb.ped))
        FreezeEntityPosition(self.ped, true)
        SetEntityInvincible(self.ped, true)
        SetBlockingOfNonTemporaryEvents(self.ped, true)
        exports.ox_target:addLocalEntity(self.ped, {
            { name = 'as_util_scrap', icon = 'fa-solid fa-recycle', label = 'Sell copper wire', items = Config.Items.copper,
              onSelect = function()
                  local ok, total, count = lib.callback.await('as-utilities:sellCopper', false)
                  if ok then Notify(('Sold %d copper for £%d'):format(count, total), 'success') else Notify(total or 'Nothing to sell', 'error') end
              end },
        })
    end
    function pt:onExit()
        if self.ped and DoesEntityExist(self.ped) then
            exports.ox_target:removeLocalEntity(self.ped)
            DeleteEntity(self.ped)
        end
        self.ped = nil
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearJobBlips()
end)

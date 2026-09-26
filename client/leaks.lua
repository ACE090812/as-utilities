-- gas leak zones: effects, damage, ignition, detector sweep, cordon
local Leaks = {}
local FX_ASSET, FX_NAME = 'core', 'exp_grd_bzgas_smoke'

local function hasDetector()
    return (exports.ox_inventory:Search('count', Config.Items.detector) or 0) > 0
end

local function stopFx(l)
    if l.fx then StopParticleFxLooped(l.fx, false) l.fx = nil end
end

RegisterNetEvent('as-utilities:leakStart', function(id, coords)
    Leaks[id] = { id = id, coords = coords }
end)

RegisterNetEvent('as-utilities:leakEnd', function(id)
    local l = Leaks[id]
    if l then stopFx(l) end
    Leaks[id] = nil
end)

RegisterNetEvent('as-utilities:leakExplode', function(coords)
    AddExplosion(coords.x, coords.y, coords.z, Config.Leak.explosionType, 1.0, true, false, 1.0)
end)

CreateThread(function()
    local list = lib.callback.await('as-utilities:getLeaks', false)
    for _, l in ipairs(list or {}) do Leaks[l.id] = { id = l.id, coords = l.coords } end
end)

local function myLeakJob(id)
    return CurrentJob and CurrentJob.kind == 'leak' and CurrentJob.meters[1] and CurrentJob.meters[1].id == id and CurrentJob
end

local textShown
local function text(msg)
    if msg ~= textShown then
        if msg then lib.showTextUI(msg, { position = 'left-center' }) else lib.hideTextUI() end
        textShown = msg
    end
end

CreateThread(function()
    local lastDamage, lastIgnite, busy = 0, 0, false
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local msg
        for id, l in pairs(Leaks) do
            local d = #(pos - l.coords)
            if d < 150.0 then
                if not l.fx then
                    lib.requestNamedPtfxAsset(FX_ASSET)
                    UseParticleFxAsset(FX_ASSET)
                    l.fx = StartParticleFxLoopedAtCoord(FX_NAME, l.coords.x, l.coords.y, l.coords.z - 0.5, 0.0, 0.0, 0.0, 1.2, false, false, false, false)
                end
            elseif l.fx then
                stopFx(l)
            end

            if d < Config.Leak.radius then
                sleep = 0
                local now = GetGameTimer()
                local immune = Config.Leak.engineerImmune and OnDuty() and hasDetector()
                if not immune and now - lastDamage > 3000 then
                    lastDamage = now
                    ApplyDamageToPed(ped, Config.Leak.damage, false)
                end
                if (IsPedShooting(ped) or GetNumberOfFiresInRange(l.coords.x, l.coords.y, l.coords.z, Config.Leak.radius) > 0)
                    and now - lastIgnite > 5000 then
                    lastIgnite = now
                    TriggerServerEvent('as-utilities:leakIgnite', id)
                end

                local job = myLeakJob(id)
                if job and hasDetector() then
                    if job.leakStage == 'sweep' then
                        local ppm = math.floor(12000 / math.max(0.5, d))
                        msg = ('GAS DETECTOR  %d ppm  - find the source'):format(ppm)
                        if d < 1.8 and not busy then
                            busy = true
                            CreateThread(function()
                                if lib.callback.await('as-utilities:leakSweep', false, id) then
                                    Notify('Source found at the meter. Cordon off the area with cones.', 'success')
                                end
                                Wait(1500) busy = false
                            end)
                        end
                    elseif job.leakStage == 'cordon' then
                        if d >= Config.Leak.coneMinDist and d <= Config.Leak.coneMaxDist then
                            msg = '[E] Place cone'
                            if IsControlJustPressed(0, 38) and not busy then
                                busy = true
                                CreateThread(function()
                                    lib.requestAnimDict('pickup_object')
                                    TaskPlayAnim(ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 1000, 0, 0, false, false, false)
                                    Wait(900)
                                    local p = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.8, 0.0)
                                    local _, gz = GetGroundZFor_3dCoord(p.x, p.y, p.z + 1.0, false)
                                    local ok, res = lib.callback.await('as-utilities:placeCone', false, id, vec3(p.x, p.y, gz ~= 0 and gz or p.z - 1.0))
                                    if ok then Notify(('Cone placed (%d/%d)'):format(res, Config.Leak.cones), 'success')
                                    elseif res then Notify(res, 'error') end
                                    busy = false
                                end)
                            end
                        else
                            msg = 'Place cones around the edge of the zone'
                        end
                    elseif job.leakStage == 'repair' then
                        msg = 'Area cordoned - repair at the meter'
                    end
                elseif not job then
                    msg = '⚠ GAS LEAK - leave the area'
                end
            end
        end
        text(msg)
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, l in pairs(Leaks) do stopFx(l) end
    if textShown then lib.hideTextUI() end
end)

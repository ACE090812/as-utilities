-- /utilmeter placement tool: aim at a wall, preview the prop, save
local placing = false

local function rotToDir(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local c = math.abs(math.cos(x))
    return vec3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function raycast(dist)
    local cam = GetGameplayCamCoord()
    local dest = cam + rotToDir(GetGameplayCamRot(2)) * dist
    local ray = StartShapeTestLosProbe(cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, 1 + 16, PlayerPedId(), 4)
    local status, hit, coords, normal
    repeat
        status, hit, coords, normal = GetShapeTestResult(ray)
        Wait(0)
    until status ~= 1
    return hit == 1, coords, normal
end

RegisterNetEvent('as-utilities:admin:place', function()
    if placing then return end
    placing = true
    local mtype = 'electric'
    local headingOffset = 0.0
    local depth = 0.05
    local obj, objModel

    local function ensureObj()
        local model = joaat(Config.Props[mtype].normal)
        if obj and objModel == model then return end
        if obj then DeleteEntity(obj) end
        lib.requestModel(model)
        obj = CreateObject(model, 0.0, 0.0, 0.0, false, false, false)
        objModel = model
        SetEntityAlpha(obj, 180, false)
        SetEntityCollision(obj, false, false)
        FreezeEntityPosition(obj, true)
    end

    lib.showTextUI('[E] Save  [G] Gas/Electric  [Scroll] Rotate  [↑/↓] Depth  [Backspace] Exit', { position = 'top-center' })
    Notify('Aim at a wall. The preview faces away from the wall you hit.', 'inform')

    while placing do
        ensureObj()
        local hit, coords, normal = raycast(12.0)
        if hit then
            local faceHeading = GetHeadingFromVector_2d(normal.x, normal.y) + headingOffset
            local pos = coords + vec3(normal.x, normal.y, 0.0) * depth
            SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z, false, false, false)
            SetEntityHeading(obj, faceHeading + Config.PropHeadingOffset)
            DrawMarker(0, pos.x, pos.y, pos.z + 0.55, 0, 0, 0, 0, 0, 0, 0.12, 0.12, 0.12,
                mtype == 'gas' and 60 or 245, mtype == 'gas' and 140 or 197, mtype == 'gas' and 230 or 24, 200, false, true, 2, false, nil, nil, false)
            -- preview where the engineer panel will float (front direction line)
            local f = Util.fwd(faceHeading)
            local p = pos + f * Config.Screen.forward + vec3(0, 0, Config.Screen.up)
            DrawLine(pos.x, pos.y, pos.z, p.x, p.y, p.z, 255, 255, 255, 200)

            if IsControlJustPressed(0, 38) then
                local ok, id = lib.callback.await('as-utilities:admin:add', false, mtype, pos, faceHeading)
                Notify(ok and ('Saved %s meter #%d'):format(mtype, id) or 'Save failed', ok and 'success' or 'error')
            end
        end
        if IsControlJustPressed(0, 47) then mtype = mtype == 'gas' and 'electric' or 'gas' end
        if IsControlJustPressed(0, 241) then headingOffset = headingOffset + 5.0 end
        if IsControlJustPressed(0, 242) then headingOffset = headingOffset - 5.0 end
        if IsControlJustPressed(0, 172) then depth = depth + 0.01 end
        if IsControlJustPressed(0, 173) then depth = depth - 0.01 end
        if IsControlJustPressed(0, 177) then placing = false end
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        Wait(0)
    end
    if obj then DeleteEntity(obj) end
    lib.hideTextUI()
end)

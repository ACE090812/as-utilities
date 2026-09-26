-- World-space DUI panels + camera/cursor interaction.
-- The DUI page (web/screen.html) is a pure renderer: Lua owns every widget
-- rect, so hit-testing happens here and nothing needs to post back from the DUI.
Screen = {}
Screen.__index = Screen

local CANVAS_W, CANVAS_H = 1280, 800
local TXD = CreateRuntimeTxd('as_util_screens')

function Screen.new(name)
    local self = setmetatable({}, Screen)
    self.name = name
    self.dui = CreateDui(('nui://%s/web/screen.html'):format(GetCurrentResourceName()), CANVAS_W, CANVAS_H)
    local handle = GetDuiHandle(self.dui)
    CreateRuntimeTextureFromDuiHandle(TXD, name, handle)
    self.payload = nil
    self.lastJson = nil
    return self
end

function Screen:send(payload)
    self.payload = payload
    local j = json.encode(payload)
    if j ~= self.lastJson then
        self.lastJson = j
        SendDuiMessage(self.dui, j)
    end
end

function Screen:destroy()
    if self.dui then DestroyDui(self.dui) self.dui = nil end
end

-- corners of a panel centred on c, facing heading h (normal points toward the viewer)
function Screen.corners(c, heading, width)
    local f = Util.fwd(heading)
    local r = vec3(-f.y, f.x, 0.0)
    local up = vec3(0.0, 0.0, 1.0)
    local hw, hh = width / 2, (width * CANVAS_H / CANVAS_W) / 2
    return c - r * hw + up * hh, c + r * hw + up * hh, c - r * hw - up * hh, c + r * hw - up * hh, f
end

local function tri(a, b, c, ua, va, ub, vb, uc, vc, name, alpha)
    DrawTexturedPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, 255, 255, 255, alpha,
        'as_util_screens', name, ua, va, 1.0, ub, vb, 1.0, uc, vc, 1.0)
end

function Screen:draw(c, heading, width, alpha)
    local tl, tr, bl, br = Screen.corners(c, heading, width)
    alpha = alpha or 255
    -- front face (both windings so it's never culled)
    tri(tl, bl, tr, 0, 0, 0, 1, 1, 0, self.name, alpha)
    tri(tr, bl, br, 1, 0, 0, 1, 1, 1, self.name, alpha)
    tri(tl, tr, bl, 0, 0, 1, 0, 0, 1, self.name, alpha)
    tri(tr, br, bl, 1, 0, 1, 1, 0, 1, self.name, alpha)
end

local function project(p)
    local on, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
    return x, y
end

-- cursor (0-1 screen) -> canvas pixels using the projected panel as an affine frame
local function cursorToCanvas(cx, cy, tl, tr, bl)
    local ox, oy = project(tl)
    local ax, ay = project(tr); ax, ay = ax - ox, ay - oy
    local bx, by = project(bl); bx, by = bx - ox, by - oy
    local px, py = cx - ox, cy - oy
    local det = ax * by - ay * bx
    if math.abs(det) < 1e-6 then return nil end
    local u = (px * by - py * bx) / det
    local v = (ax * py - ay * px) / det
    if u < 0 or u > 1 or v < 0 or v > 1 then return nil end
    return u * CANVAS_W, v * CANVAS_H
end

local CLICKABLE = { button = true, terminal = true, hotspot = true, key = true }

local function hit(payload, x, y)
    if not payload or not payload.widgets or not x then return nil end
    for i = #payload.widgets, 1, -1 do
        local w = payload.widgets[i]
        if CLICKABLE[w.type] and w.id and not w.disabled then
            if x >= w.x and x <= w.x + w.w and y >= w.y and y <= w.y + w.h then return w.id end
        end
    end
end

Screen.active = nil

-- handler: { build = fn() -> payload, click = fn(id), tick = fn(), close = fn(), shouldClose = fn() }
function Screen:interact(c, heading, width, handler)
    if Screen.active then return end
    Screen.active = self
    local tl, tr, bl = Screen.corners(c, heading, width)
    local f = Util.fwd(heading)
    local height = width * CANVAS_H / CANVAS_W
    local fov = 45.0
    local dist = (height / 2) / math.tan(math.rad(fov / 2)) * 1.25
    local camPos = c + f * dist
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, fov, false, 0)
    PointCamAtCoord(cam, c.x, c.y, c.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, false)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)

    local hover, lastCursorSend = nil, 0
    local running = true
    while running do
        Wait(0)
        DisableAllControlActions(0)
        EnableControlAction(0, 249, true) -- push to talk
        SetMouseCursorActiveThisFrame()
        HideHudAndRadarThisFrame()
        if handler.tick then handler.tick() end

        local payload = handler.build()
        local cx, cy = GetDisabledControlNormal(0, 239), GetDisabledControlNormal(0, 240)
        local x, y = cursorToCanvas(cx, cy, tl, tr, bl)
        local h = hit(payload, x, y)
        if h then SetMouseCursorSprite(5) else SetMouseCursorSprite(1) end
        payload.hover = h
        local now = GetGameTimer()
        if h ~= hover or now - lastCursorSend > 50 then
            hover = h
            lastCursorSend = now
        end
        self:send(payload)
        self:draw(c, heading, width)

        if IsDisabledControlJustPressed(0, 24) and h then handler.click(h) end
        if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 25) then
            running = false
        end
        if handler.shouldClose and handler.shouldClose() then running = false end
        if IsEntityDead(ped) then running = false end
    end
    -- swallow the pause menu the ESC press would open
    CreateThread(function()
        local t = GetGameTimer()
        while GetGameTimer() - t < 300 do DisableControlAction(0, 200, true) Wait(0) end
    end)
    RenderScriptCams(false, true, 400, true, false)
    DestroyCam(cam, false)
    FreezeEntityPosition(ped, false)
    Screen.active = nil
    if handler.close then handler.close() end
end

-- widget helpers shared by meter + board UIs
W = {}
function W.button(id, x, y, w, h, label, style, extra)
    local b = { type = 'button', id = id, x = x, y = y, w = w, h = h, label = label, style = style or 'primary' }
    if extra then for k, v in pairs(extra) do b[k] = v end end
    return b
end
function W.text(x, y, w, text, size, extra)
    local t = { type = 'text', x = x, y = y, w = w, text = text, size = size or 22 }
    if extra then for k, v in pairs(extra) do t[k] = v end end
    return t
end
function W.panel(x, y, w, h, title, extra)
    local p = { type = 'panel', x = x, y = y, w = w, h = h, title = title }
    if extra then for k, v in pairs(extra) do p[k] = v end end
    return p
end

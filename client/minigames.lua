-- Meter screen UI + task minigames. Everything is laid out on a 1280x800 canvas.
MeterUI = {}
MeterUI.__index = MeterUI

local COLORS = { red = '#e5484d', blue = '#3e8ed0', yellow = '#f5c518', green = '#30a46c' }
local WIRE_ORDER = { 'red', 'blue', 'yellow', 'green' }
local SIMON = { { id = 's1', color = '#e5484d' }, { id = 's2', color = '#3e8ed0' }, { id = 's3', color = '#f5c518' }, { id = 's4', color = '#30a46c' } }

local SEQUENCES = {
    fuse    = { 'Isolate supply', 'Remove blown fuse', 'Fit new fuse', 'Restore supply' },
    valve   = { 'Close ECV', 'Remove regulator', 'Fit new regulator', 'Open ECV' },
    leak    = { 'Close ECV', 'Purge line', 'Replace regulator', 'Open ECV' },
    tamper  = { 'Isolate supply', 'Remove bypass', 'Fit new seal' },
    install = { 'Isolate supply', 'Remove old meter', 'Fit smart meter' },
}

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function sfx(name, set) PlaySoundFrontend(-1, name, set, true) end

function MeterUI.new(data, onComplete)
    local self = setmetatable({}, MeterUI)
    self.info = data.info
    self.task = data.task
    self.token = data.token
    self.message = data.message
    self.onComplete = onComplete
    self.toast = nil
    self.closeNow = false
    self.busy = false
    if not self.token then
        self.phase = 'info'
    else
        self:startTask()
    end
    return self
end

function MeterUI:flash(msg, kind)
    self.toast = { text = msg, kind = kind or 'info', t = GetGameTimer() }
end

function MeterUI:shock(dmg, msg)
    local ped = PlayerPedId()
    ApplyDamageToPed(ped, dmg, false)
    sfx('ERROR', 'HUD_AMMO_SHOP_SOUNDSET')
    self:flash(msg or 'Wrong step!', 'error')
end

---------------------------------------------------------------------
-- task setup
---------------------------------------------------------------------
function MeterUI:startSequence(name, nextPhase)
    local steps = {}
    for i, label in ipairs(SEQUENCES[name]) do steps[i] = { id = 'step' .. i, label = label, order = i } end
    self.seq = { steps = shuffle(steps), at = 1, total = #steps, name = name, nextPhase = nextPhase }
    self.phase = 'sequence'
end

function MeterUI:startTask()
    local k = self.task.kind
    self.started = GetGameTimer()
    if k == 'read' then
        self.phase, self.entry = 'read', ''
    elseif k == 'fuse' then
        self:startSequence('fuse', 'submit')
    elseif k == 'valve' then
        self:startSequence('valve', 'gauge')
    elseif k == 'leak' then
        self:startSequence('leak', 'gauge')
    elseif k == 'install' then
        self:startSequence('install', 'pair')
    elseif k == 'tamper' then
        self.phase = 'evidence'
        self.evidence = {}
        local labels = shuffle({ 'Broken tamper seal', 'Bypass wiring fitted', 'Cut copper tails' })
        for i = 1, 3 do
            self.evidence[i] = { id = 'ev' .. i, label = labels[i], found = false,
                x = 70 + math.random(0, 300), y = 460 + (i - 1) * 95 + math.random(0, 20) }
        end
    elseif k == 'wiring' then
        self.phase = 'wiring'
        self.wires = { left = {}, right = shuffle({ 'red', 'blue', 'yellow', 'green' }), done = {}, sel = nil }
        for i, c in ipairs(WIRE_ORDER) do self.wires.left[i] = c end
    elseif k == 'display' then
        self.phase = 'simon-ready'
    elseif k == 'inspect' then
        self.phase = 'inspect-ready'
    end
end

---------------------------------------------------------------------
-- completion
---------------------------------------------------------------------
function MeterUI:submit(result)
    if self.busy then return end
    self.busy = true
    self.phase = 'working'
    CreateThread(function()
        -- make sure the minimum task time has passed so the server accepts it
        local min = (Config.MinTaskTime[self.task.kind] or 3) * 1000 + 250
        local elapsed = GetGameTimer() - self.started
        if elapsed < min then Wait(min - elapsed) end
        local ok, msg = lib.callback.await('as-utilities:completeTask', false, self.token, result or {})
        self.busy = false
        self.phase = 'result'
        self.resultOk = ok
        self.resultMsg = msg or (ok and 'Done' or 'Failed')
        if ok then sfx('PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET') else sfx('ERROR', 'HUD_AMMO_SHOP_SOUNDSET') end
        if self.onComplete then self.onComplete(ok) end
    end)
end

---------------------------------------------------------------------
-- tick (animations)
---------------------------------------------------------------------
function MeterUI:tick()
    local now = GetGameTimer()
    if self.phase == 'gauge' then
        local g = self.gauge
        g.value = (math.sin((now - g.t0) / 1000 * g.speed) + 1) / 2
    elseif self.phase == 'simon-show' then
        local s = self.simon
        local step = math.floor((now - s.t0) / 650) + 1
        local within = ((now - s.t0) % 650) < 450
        if step > #s.seq then
            self.phase, s.lit, s.input = 'simon-input', nil, 0
        else
            s.lit = within and s.seq[step] or nil
        end
    elseif self.phase == 'inspect-run' then
        local p = (now - self.inspectT0) / 4500
        self.inspectP = math.min(1, p)
        if p >= 1 then self.phase = 'inspect-done' sfx('PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET') end
    end
    if self.toast and now - self.toast.t > 2200 then self.toast = nil end
end

---------------------------------------------------------------------
-- clicks
---------------------------------------------------------------------
local function keypadInput(cur, id, maxLen)
    if id == 'k_del' then return cur:sub(1, -2) end
    local d = id:match('^k_(%d)$')
    if d and #cur < maxLen then return cur .. d end
    return cur
end

function MeterUI:click(id)
    if id == 'close' then self.closeNow = true return end
    local ph = self.phase
    sfx('NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET')

    if ph == 'read' then
        if id == 'k_ok' then
            if #self.entry == 0 then return self:flash('Enter the reading', 'error') end
            return self:submit({ value = tonumber(self.entry) })
        end
        self.entry = keypadInput(self.entry, id, 5)

    elseif ph == 'sequence' then
        local s = self.seq
        for _, st in ipairs(s.steps) do
            if st.id == id and not st.done then
                if st.order == s.at then
                    st.done = true
                    s.at = s.at + 1
                    if s.at > s.total then self:afterSequence() end
                else
                    for _, x in ipairs(s.steps) do x.done = false end
                    s.at = 1
                    local k = self.task.kind
                    if k == 'fuse' or k == 'tamper' or k == 'install' then
                        self:shock(12, 'ZAP! Isolate before you touch it. Start again.')
                    else
                        self:shock(4, 'Gas escaping - wrong order. Start again.')
                    end
                end
                return
            end
        end

    elseif ph == 'gauge' then
        if id == 'lock' then
            local g = self.gauge
            if g.value >= g.zone[1] and g.value <= g.zone[2] then
                g.hits = g.hits + 1
                self:flash(('Pressure holding (%d/3)'):format(g.hits), 'ok')
                if g.hits >= 3 then return self:submit({}) end
                g.zone = self:newZone(g.width)
                g.speed = g.speed + 0.35
            else
                g.hits = 0
                self:flash('Pressure drop - test reset', 'error')
            end
        end

    elseif ph == 'pair' then
        if id == 'k_ok' then
            if self.entry == self.task.code then
                self.phase = 'reconnect'
            else
                self.entry = ''
                self:flash('Pairing rejected - check the code', 'error')
            end
            return
        end
        self.entry = keypadInput(self.entry, id, 4)

    elseif ph == 'reconnect' then
        if id == 'reconnect' then return self:submit({ code = self.task.code }) end

    elseif ph == 'evidence' then
        for _, e in ipairs(self.evidence) do
            if e.id == id then e.found = true end
        end
        local all = true
        for _, e in ipairs(self.evidence) do if not e.found then all = false end end
        if all then self:flash('Evidence photographed', 'ok') self:startSequence('tamper', 'report') end

    elseif ph == 'report' then
        if id == 'file' then return self:submit({}) end

    elseif ph == 'wiring' then
        local w = self.wires
        local side, idx = id:match('^w([lr])(%d)$')
        idx = tonumber(idx)
        if side == 'l' then
            if not w.done[w.left[idx]] then w.sel = idx end
        elseif side == 'r' and w.sel then
            local lc, rc = w.left[w.sel], w.right[idx]
            if lc == rc then
                w.done[lc] = true
                w.sel = nil
                local n = 0
                for _ in pairs(w.done) do n = n + 1 end
                if n == 4 then self.phase = 'submit' end
            else
                w.sel = nil
                self:shock(6, 'Short circuit! Wrong terminal.')
            end
        end

    elseif ph == 'simon-ready' then
        if id == 'run' then
            local seq = {}
            for i = 1, 5 do seq[i] = SIMON[math.random(4)].id end
            self.simon = { seq = seq, t0 = GetGameTimer() + 400 }
            self.phase = 'simon-show'
        end

    elseif ph == 'simon-input' then
        local s = self.simon
        if id:match('^s%d$') then
            s.input = s.input + 1
            if s.seq[s.input] ~= id then
                self:flash('Reset failed - display rebooting', 'error')
                self.phase = 'simon-ready'
            elseif s.input == #s.seq then
                self.phase = 'submit'
            end
        end

    elseif ph == 'inspect-ready' then
        if id == 'run' then self.phase, self.inspectT0, self.inspectP = 'inspect-run', GetGameTimer(), 0 end

    elseif ph == 'inspect-done' then
        if id == 'log' then return self:submit({}) end

    elseif ph == 'submit' then
        if id == 'confirm' then return self:submit({}) end
    end
end

function MeterUI:newZone(width)
    local a = 0.1 + math.random() * (0.9 - width - 0.1)
    return { a, a + width }
end

function MeterUI:afterSequence()
    local nxt = self.seq.nextPhase
    self.seq = nil
    if nxt == 'gauge' then
        local width = self.task.kind == 'leak' and 0.12 or 0.16
        self.gauge = { value = 0, t0 = GetGameTimer(), speed = 1.6, hits = 0, width = width }
        self.gauge.zone = self:newZone(width)
        self.phase = 'gauge'
    elseif nxt == 'pair' then
        self.phase, self.entry = 'pair', ''
    else
        self.phase = nxt
    end
end

---------------------------------------------------------------------
-- rendering
---------------------------------------------------------------------
local STATE_LABEL = { ok = 'OK', faulty = 'FAULT', tampered = 'CHECK SEAL', leak = 'GAS LEAK' }
local STATE_COLOR = { ok = 'green', faulty = 'amber', tampered = 'amber', leak = 'red' }

function MeterUI.face(info, widgets, opts)
    opts = opts or {}
    local x, y, w, h = 40, 120, 460, 640
    widgets[#widgets + 1] = W.panel(x, y, w, h, (info.smart and 'SMART ' or '') .. info.type:upper() .. ' METER')
    widgets[#widgets + 1] = W.text(x + 24, y + 58, w - 48, 'SERIAL ' .. info.serial, 20, { mono = true, color = 'muted' })
    local dead = info.state == 'faulty' and opts.fault == 'display'
    widgets[#widgets + 1] = { type = 'display', x = x + 24, y = y + 100, w = w - 48, h = 140,
        value = dead and '' or Util.fmtReading(info.reading), unit = info.type == 'gas' and 'm³' or 'kWh', dead = dead,
        frozen = info.state == 'tampered' }
    widgets[#widgets + 1] = { type = 'led', x = x + 24, y = y + 270, color = STATE_COLOR[info.state] or 'green', label = STATE_LABEL[info.state] or info.state }
    if info.smart then
        widgets[#widgets + 1] = { type = 'led', x = x + 24, y = y + 310, color = 'blue', label = 'COMMS LINKED' }
    end
end

local function keypad(widgets, x, y, size, gap)
    local keys = { '1', '2', '3', '4', '5', '6', '7', '8', '9', 'del', '0', 'ok' }
    for i, k in ipairs(keys) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local label = k == 'del' and '⌫' or (k == 'ok' and 'OK' or k)
        widgets[#widgets + 1] = { type = 'key', id = 'k_' .. k, x = x + col * (size + gap), y = y + row * (size * 0.72 + gap),
            w = size, h = size * 0.72, label = label, style = k == 'ok' and 'primary' or (k == 'del' and 'ghost' or 'key') }
    end
end

function MeterUI:build()
    local wd = {}
    local info = self.info
    MeterUI.face(info, wd, { fault = self.task and self.task.kind })
    local X, Y, WW, H = 530, 120, 710, 640
    local title = self.task and (self.task.label or self.task.kind) or 'STATUS'
    wd[#wd + 1] = W.panel(X, Y, WW, H, title:upper())
    local ph = self.phase
    local cx = X + 30

    if ph == 'info' then
        wd[#wd + 1] = W.text(cx, Y + 80, WW - 60, self.message or 'No work booked on this meter.', 26)
        wd[#wd + 1] = W.button('close', X + WW - 230, Y + H - 90, 200, 64, 'Close', 'ghost')

    elseif ph == 'read' then
        wd[#wd + 1] = W.text(cx, Y + 70, WW - 60, 'Read the display and key in the reading.', 22, { color = 'muted' })
        wd[#wd + 1] = { type = 'entry', x = cx, y = Y + 110, w = 360, h = 90, value = self.entry, placeholder = '-----' }
        keypad(wd, cx, Y + 220, 110, 14)

    elseif ph == 'sequence' then
        local s = self.seq
        wd[#wd + 1] = W.text(cx, Y + 70, WW - 60, 'Carry out the steps in the correct order.', 22, { color = 'muted' })
        for i, st in ipairs(s.steps) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            wd[#wd + 1] = W.button(st.id, cx + col * 330, Y + 130 + row * 120, 310, 100, st.label,
                st.done and 'done' or 'step', { disabled = st.done, badge = st.done and tostring(st.order) or nil })
        end
        wd[#wd + 1] = { type = 'progress', x = cx, y = Y + H - 60, w = WW - 60, h = 14, value = (s.at - 1) / s.total }

    elseif ph == 'gauge' then
        local g = self.gauge
        wd[#wd + 1] = W.text(cx, Y + 70, WW - 60, 'Pressure test: LOCK when the needle is in the green band. 3 in a row.', 22, { color = 'muted' })
        wd[#wd + 1] = { type = 'gauge', x = cx, y = Y + 140, w = WW - 60, h = 90, value = g.value, zone = g.zone }
        wd[#wd + 1] = W.text(cx, Y + 260, WW - 60, ('Holds: %d / 3'):format(g.hits), 28, { weight = 700 })
        wd[#wd + 1] = W.button('lock', cx, Y + 330, WW - 60, 120, 'LOCK', 'primary')

    elseif ph == 'pair' then
        wd[#wd + 1] = W.text(cx, Y + 70, WW - 60, ('Commission the meter. Pairing code on the comms hub: %s'):format(self.task.code), 22)
        wd[#wd + 1] = { type = 'entry', x = cx, y = Y + 110, w = 360, h = 90, value = self.entry, placeholder = '----' }
        keypad(wd, cx, Y + 220, 110, 14)

    elseif ph == 'reconnect' then
        wd[#wd + 1] = W.text(cx, Y + 80, WW - 60, 'Smart meter paired. Reconnect the supply to finish.', 26)
        wd[#wd + 1] = W.button('reconnect', cx, Y + 180, WW - 60, 120, 'Reconnect supply', 'primary')

    elseif ph == 'evidence' then
        wd[#wd + 1] = W.text(cx, Y + 70, WW - 60, 'Reading hasn\'t moved. Inspect the meter face and photograph any evidence.', 22)
        local found = 0
        for i, e in ipairs(self.evidence) do
            if e.found then
                found = found + 1
                wd[#wd + 1] = W.text(cx, Y + 140 + (found - 1) * 50, WW - 60, '✓ ' .. e.label, 24, { color = 'ok' })
            end
            wd[#wd + 1] = { type = 'hotspot', id = e.id, x = e.x, y = e.y, w = 70, h = 70, found = e.found, disabled = e.found }
        end
        wd[#wd + 1] = W.text(cx, Y + H - 80, WW - 60, ('Evidence: %d / 3'):format(found), 22, { color = 'muted' })

    elseif ph == 'report' then
        wd[#wd + 1] = W.text(cx, Y + 80, WW - 60, 'Meter made safe and resealed. File the tampering report with the police.', 26)
        wd[#wd + 1] = W.button('file', cx, Y + 200, WW - 60, 120, 'File report & finish', 'danger')

    elseif ph == 'wiring' then
        local w = self.wires
        wd[#wd + 1] = W.text(cx, Y + 70, WW - 60, 'Reconnect the tails: pick a terminal on the left, then its match on the right.', 22, { color = 'muted' })
        local lx, rx, top, gap = cx + 20, X + WW - 150, Y + 150, 110
        local rightPos = {}
        for i, c in ipairs(w.right) do rightPos[c] = { x = rx, y = top + (i - 1) * gap } end
        for i, c in ipairs(w.left) do
            local ly = top + (i - 1) * gap
            if w.done[c] then
                local rp = rightPos[c]
                wd[#wd + 1] = { type = 'line', x1 = lx + 50, y1 = ly + 40, x2 = rp.x + 50, y2 = rp.y + 40, color = COLORS[c] }
            end
            wd[#wd + 1] = { type = 'terminal', id = 'wl' .. i, x = lx, y = ly, w = 100, h = 80, color = COLORS[c],
                selected = w.sel == i, done = w.done[c], disabled = w.done[c] }
        end
        for i, c in ipairs(w.right) do
            wd[#wd + 1] = { type = 'terminal', id = 'wr' .. i, x = rx, y = top + (i - 1) * gap, w = 100, h = 80,
                color = COLORS[c], done = w.done[c], disabled = w.done[c] }
        end

    elseif ph == 'simon-ready' or ph == 'simon-show' or ph == 'simon-input' then
        local msg = ph == 'simon-ready' and 'Run the display reset, then repeat the flash sequence.'
            or (ph == 'simon-show' and 'Watch the sequence...' or 'Repeat the sequence.')
        wd[#wd + 1] = W.text(cx, Y + 70, WW - 60, msg, 22, { color = 'muted' })
        local lit = self.simon and self.simon.lit
        for i, s in ipairs(SIMON) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            wd[#wd + 1] = { type = 'button', id = s.id, x = cx + 60 + col * 300, y = Y + 130 + row * 190, w = 260, h = 170,
                label = '', style = 'simon', color = s.color, lit = lit == s.id, disabled = ph ~= 'simon-input' }
        end
        if ph == 'simon-ready' then wd[#wd + 1] = W.button('run', cx, Y + H - 100, WW - 60, 80, 'Run display reset', 'primary') end

    elseif ph == 'inspect-ready' or ph == 'inspect-run' or ph == 'inspect-done' then
        local tool = info.type == 'gas' and 'gas detector' or 'multimeter'
        wd[#wd + 1] = W.text(cx, Y + 70, WW - 60, ('Customer reported a fault. Run a full diagnostic with the %s.'):format(tool), 22)
        if ph == 'inspect-ready' then
            wd[#wd + 1] = W.button('run', cx, Y + 180, WW - 60, 110, 'Run diagnostic', 'primary')
        else
            wd[#wd + 1] = { type = 'progress', x = cx, y = Y + 190, w = WW - 60, h = 30, value = self.inspectP or 0 }
            if ph == 'inspect-done' then
                wd[#wd + 1] = W.text(cx, Y + 250, WW - 60, 'All readings within tolerance. No fault found.', 28, { color = 'ok', weight = 700 })
                wd[#wd + 1] = W.button('log', cx, Y + 330, WW - 60, 100, 'Log call-out', 'primary')
            else
                wd[#wd + 1] = W.text(cx, Y + 250, WW - 60, 'Testing...', 24, { color = 'muted' })
            end
        end

    elseif ph == 'submit' then
        wd[#wd + 1] = W.text(cx, Y + 80, WW - 60, 'Repair complete. Test and sign off the job sheet.', 26)
        wd[#wd + 1] = W.button('confirm', cx, Y + 180, WW - 60, 120, 'Sign off', 'primary')

    elseif ph == 'working' then
        wd[#wd + 1] = W.text(cx, Y + 120, WW - 60, 'Uploading job sheet...', 28, { color = 'muted' })

    elseif ph == 'result' then
        wd[#wd + 1] = W.text(cx, Y + 90, WW - 60, self.resultOk and 'COMPLETE' or 'NOT ACCEPTED', 40,
            { weight = 800, color = self.resultOk and 'ok' or 'error' })
        wd[#wd + 1] = W.text(cx, Y + 160, WW - 60, self.resultMsg, 26)
        wd[#wd + 1] = W.button('close', X + WW - 230, Y + H - 90, 200, 64, 'Close', 'ghost')
    end

    if ph ~= 'info' and ph ~= 'result' and ph ~= 'working' then
        wd[#wd + 1] = W.button('close', X + WW - 150, Y + 10, 130, 44, 'Exit', 'ghost')
    end

    return {
        theme = 'meter',
        header = { title = Config.Company, sub = 'Field Engineer Handheld', badge = info.type:upper(), badgeColor = info.type == 'gas' and 'blue' or 'amber' },
        widgets = wd,
        toast = self.toast,
    }
end

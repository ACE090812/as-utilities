-- depot job board: a DUI panel on the depot wall
local boardScreen
local board, dirty, page = nil, true, 1
local PER_PAGE = 7

local function streetAt(c)
    if not c then return 'Unknown' end
    local s1, s2 = GetStreetNameAtCoord(c.x, c.y, c.z)
    local a = GetStreetNameFromHashKey(s1)
    local zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
    if zone == 'NULL' then zone = '' end
    return a ~= '' and (a .. (zone ~= '' and (', ' .. zone) or '')) or zone
end

local function fmtAge(s)
    if s < 60 then return 'just now' end
    if s < 3600 then return ('%dm ago'):format(math.floor(s / 60)) end
    return ('%dh ago'):format(math.floor(s / 3600))
end

local function refresh()
    local b = lib.callback.await('as-utilities:getBoard', false)
    if b then
        for _, j in ipairs(b.jobs) do j.street = streetAt(j.coords) end
        board = b
    end
    dirty = false
end

RegisterNetEvent('as-utilities:boardDirty', function() dirty = true end)
RegisterNetEvent('as-utilities:refreshJob', function() dirty = true end)
AddEventHandler('as-utilities:jobChanged', function() dirty = true end)

local KIND_COLOR = { leak = 'red', report = 'amber', tamper = 'amber', fault = 'amber', read = 'muted', install = 'blue' }

local function build()
    local wd = {}
    if not board then
        wd[#wd + 1] = W.text(60, 200, 1160, 'Loading job board...', 32, { color = 'muted' })
        return { theme = 'board', header = { title = Config.Company, sub = 'Depot Job Board' }, widgets = wd }
    end
    -- job list
    local LX, LY, LW, LH = 40, 120, 800, 640
    wd[#wd + 1] = W.panel(LX, LY, LW, LH, ('OPEN JOBS (%d)'):format(#board.jobs))
    local pages = math.max(1, math.ceil(#board.jobs / PER_PAGE))
    if page > pages then page = pages end
    local first = (page - 1) * PER_PAGE + 1
    local rowY = LY + 56
    for i = first, math.min(#board.jobs, first + PER_PAGE - 1) do
        local j = board.jobs[i]
        wd[#wd + 1] = { type = 'row', x = LX + 16, y = rowY, w = LW - 32, h = 70, accent = KIND_COLOR[j.kind] or 'muted', priority = j.priority >= 5 }
        local title = j.label .. (j.count > 1 and (' x' .. j.count) or '') .. (j.type and (' - ' .. j.type) or '')
        wd[#wd + 1] = W.text(LX + 36, rowY + 8, 480, title, 22, { weight = 700 })
        local sub = (j.street or '') .. '  •  ' .. fmtAge(j.age) .. (j.reporter and ('  •  reported by ' .. j.reporter) or '')
        wd[#wd + 1] = W.text(LX + 36, rowY + 38, 520, sub, 16, { color = 'muted' })
        wd[#wd + 1] = W.text(LX + 540, rowY + 20, 90, '£' .. j.pay, 22, { weight = 700, align = 'right', mono = true })
        wd[#wd + 1] = W.button('claim_' .. j.id, LX + LW - 160, rowY + 13, 128, 44, j.ok and 'Claim' or (j.why or 'Locked'),
            j.ok and 'primary' or 'ghost', { disabled = not j.ok or board.current ~= nil, small = not j.ok })
        rowY = rowY + 78
    end
    if #board.jobs == 0 then
        wd[#wd + 1] = W.text(LX + 36, LY + 90, LW - 72, 'No open jobs. Check back shortly.', 24, { color = 'muted' })
    end
    if pages > 1 then
        wd[#wd + 1] = W.button('prev', LX + 16, LY + LH - 58, 120, 44, '◀ Prev', 'ghost', { disabled = page <= 1 })
        wd[#wd + 1] = W.text(LX + 150, LY + LH - 48, 200, ('Page %d / %d'):format(page, pages), 18, { color = 'muted' })
        wd[#wd + 1] = W.button('next', LX + LW - 136, LY + LH - 58, 120, 44, 'Next ▶', 'ghost', { disabled = page >= pages })
    end

    -- current job
    local RX, RW = 870, 370
    wd[#wd + 1] = W.panel(RX, 120, RW, 300, 'MY JOB')
    local cur = board.current
    if cur then
        local done = 0
        for _, m in ipairs(cur.meters) do if m.done then done = done + 1 end end
        wd[#wd + 1] = W.text(RX + 24, 176, RW - 48, cur.label, 26, { weight = 800 })
        wd[#wd + 1] = W.text(RX + 24, 214, RW - 48, ('%d / %d meters done'):format(done, #cur.meters), 18, { color = 'muted' })
        wd[#wd + 1] = { type = 'progress', x = RX + 24, y = 246, w = RW - 48, h = 12, value = done / #cur.meters }
        if cur.kind == 'leak' and cur.leakStage then
            wd[#wd + 1] = W.text(RX + 24, 270, RW - 48, 'Stage: ' .. cur.leakStage:upper(), 18, { color = 'error', weight = 700 })
        end
        if board.me.leader then
            wd[#wd + 1] = W.button('abandon', RX + 24, 340, RW - 48, 56, 'Hand job back', 'danger')
        end
    else
        wd[#wd + 1] = W.text(RX + 24, 180, RW - 48, 'No job claimed.', 22, { color = 'muted' })
    end

    -- engineer card
    local me = board.me
    wd[#wd + 1] = W.panel(RX, 440, RW, 320, 'ENGINEER')
    wd[#wd + 1] = W.text(RX + 24, 494, RW - 48, me.name, 24, { weight = 800 })
    wd[#wd + 1] = W.text(RX + 24, 528, RW - 48, ('%s  •  %s'):format(me.gradeLabel, me.trade == 'dual' and 'Dual Fuel' or me.trade:gsub('^%l', string.upper)), 18, { color = 'muted' })
    local xpTxt = me.nextXp and ('%d / %d XP'):format(me.xp, me.nextXp) or (me.xp .. ' XP (max grade)')
    wd[#wd + 1] = W.text(RX + 24, 562, RW - 48, xpTxt .. '  •  ' .. me.jobsDone .. ' jobs', 18)
    local curXp = Config.Grades[me.grade] and Config.Grades[me.grade].xp or 0
    wd[#wd + 1] = { type = 'progress', x = RX + 24, y = 594, w = RW - 48, h = 10,
        value = me.nextXp and ((me.xp - curXp) / math.max(1, me.nextXp - curXp)) or 1 }
    if #board.crew > 0 then
        wd[#wd + 1] = W.text(RX + 24, 624, RW - 48, 'CREW', 16, { color = 'muted', weight = 700 })
        for i, c in ipairs(board.crew) do
            wd[#wd + 1] = W.text(RX + 24, 648 + (i - 1) * 26, RW - 48, (c.leader and '★ ' or '• ') .. c.name, 18)
        end
    else
        wd[#wd + 1] = W.text(RX + 24, 624, RW - 48, 'Solo. /crewinvite [id] to form a crew.', 16, { color = 'muted' })
    end
    wd[#wd + 1] = W.button('close', 1240 - 140, 60, 130, 40, 'Exit', 'ghost')

    return { theme = 'board', header = { title = Config.Company, sub = 'Depot Job Board', badge = 'DEPOT', badgeColor = 'amber' }, widgets = wd }
end

local closing = false
local function click(id)
    if id == 'close' then closing = true return end
    if id == 'prev' then page = math.max(1, page - 1) return end
    if id == 'next' then page = page + 1 return end
    if id == 'abandon' then
        local ok, err = lib.callback.await('as-utilities:abandonJob', false)
        if not ok and err then Notify(err, 'error') end
        dirty = true
        return
    end
    local jid = tonumber(id:match('^claim_(%d+)$'))
    if jid then
        local ok, err = lib.callback.await('as-utilities:claimJob', false, jid)
        if not ok then Notify(err or 'Could not claim', 'error') end
        dirty = true
    end
end

local function openBoard()
    local b = Config.Depot.board
    closing = false
    refresh()
    boardScreen:interact(b.coords, b.heading, b.width, {
        build = build,
        click = function(id) CreateThread(function() click(id) end) end,
        tick = function()
            if dirty then dirty = false CreateThread(refresh) end
        end,
        shouldClose = function() return closing end,
    })
end

CreateThread(function()
    boardScreen = Screen.new('board')
    local b = Config.Depot.board
    exports.ox_target:addSphereZone({
        coords = b.coords, radius = 1.2,
        options = { { name = 'as_util_board', icon = 'fa-solid fa-clipboard-list', label = 'Job board', distance = 3.0,
            canInteract = function() return OnDuty() end, onSelect = openBoard } },
    })
    local lastFetch = 0
    while true do
        local sleep = 1000
        if OnDuty() and not Screen.active then
            local d = #(GetEntityCoords(PlayerPedId()) - b.coords)
            if d < 15.0 then
                sleep = 0
                if dirty or GetGameTimer() - lastFetch > 8000 then
                    lastFetch = GetGameTimer()
                    dirty = false
                    CreateThread(refresh)
                end
                boardScreen:send(build())
                boardScreen:draw(b.coords, b.heading, b.width)
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and boardScreen then boardScreen:destroy() end
end)

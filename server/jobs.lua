-- job board, claiming, meter sessions, task completion, pay
local nextJobId = 1

local REQUIRED = {
    read    = { consume = nil, tools = { 'reader' } },
    fuse    = { consume = 'fuse', tools = { 'multimeter', 'toolkit' } },
    wiring  = { consume = nil, tools = { 'multimeter', 'toolkit' } },
    display = { consume = nil, tools = { 'toolkit' } },
    valve   = { consume = 'valve', tools = { 'detector', 'toolkit' } },
    tamper  = { consume = 'seal', tools = { 'toolkit' } },
    install = { consume = 'smart', tools = { 'toolkit' } },
    leak    = { consume = 'valve', tools = { 'detector', 'toolkit' } },
}

local function requiredFor(taskKind, meterType)
    if taskKind == 'inspect' then
        return { tools = { meterType == 'gas' and 'detector' or 'multimeter' } }
    end
    return REQUIRED[taskKind] or { tools = {} }
end

local function missingItems(src, taskKind, meterType)
    local req = requiredFor(taskKind, meterType)
    local missing = {}
    for _, key in ipairs(req.tools or {}) do
        if not HasItem(src, Config.Items[key]) then missing[#missing + 1] = Config.Items[key] end
    end
    if req.consume and not HasItem(src, Config.Items[req.consume]) then missing[#missing + 1] = Config.Items[req.consume] end
    return missing
end

---------------------------------------------------------------------
-- creation / removal
---------------------------------------------------------------------
function BoardDirty() TriggerClientEvent('as-utilities:boardDirty', -1) end

function CreateJob(kind, meterIds, taskKinds, opts)
    opts = opts or {}
    local id = nextJobId
    nextJobId = nextJobId + 1
    local job = {
        id = id, kind = kind, meters = meterIds, tasks = {}, status = 'open',
        createdAt = os.time(), priority = opts.priority or 0, reporter = opts.reporter,
    }
    for i, mid in ipairs(meterIds) do
        job.tasks[mid] = { kind = taskKinds[i], done = false }
        if Meters[mid] then Meters[mid].jobId = id end
    end
    Jobs[id] = job
    BoardDirty()
    return job
end

local function crewSend(job, event, ...)
    if not job.leader then return end
    local members = CrewMembers(job.leader)
    for _, m in ipairs(members) do TriggerClientEvent(event, m, ...) end
end

function ClientJob(job)
    local meters = {}
    for _, mid in ipairs(job.meters) do
        local m = Meters[mid]
        local t = job.tasks[mid]
        if m then
            meters[#meters + 1] = { id = mid, coords = m.coords, type = m.type, done = t.done, task = t.kind }
        end
    end
    local leak = job.kind == 'leak' and Leaks and Leaks[job.meters[1]]
    return {
        id = job.id, kind = job.kind, label = Config.FaultLabels[job.kind] or job.kind, meters = meters,
        claimedAt = job.claimedAt, limit = Config.TimeLimit[job.kind], leakStage = leak and leak.stage or nil,
        leader = job.leader,
    }
end

function PushJob(job) crewSend(job, 'as-utilities:jobAssigned', ClientJob(job)) end

function CancelJob(id, reason)
    local job = Jobs[id]
    if not job then return end
    for _, mid in ipairs(job.meters) do
        if Meters[mid] and Meters[mid].jobId == id then Meters[mid].jobId = nil end
    end
    if job.status == 'claimed' then
        crewSend(job, 'as-utilities:jobCleared', id)
        if reason then crewSend(job, 'ox_lib:notify', { title = Config.Company, description = 'Job cancelled: ' .. reason, type = 'error' }) end
    end
    Jobs[id] = nil
    BoardDirty()
end

function JobOfCrew(src)
    local _, leader = CrewMembers(src)
    for _, job in pairs(Jobs) do
        if job.status == 'claimed' and job.leader == leader then return job end
    end
end

function AbandonJobsOf(src)
    for _, job in pairs(Jobs) do
        if job.status == 'claimed' and job.leader == src then
            crewSend(job, 'as-utilities:jobCleared', job.id)
            job.status, job.leader, job.claimedAt = 'open', nil, nil
        end
    end
    BoardDirty()
end

---------------------------------------------------------------------
-- eligibility
---------------------------------------------------------------------
local function crewProfile(src)
    local members, leader = CrewMembers(src)
    local maxGrade, trades = 0, {}
    for _, m in ipairs(members) do
        local d = Duty[m]
        if d then
            if d.grade > maxGrade then maxGrade = d.grade end
            trades[#trades + 1] = d.trade
        end
    end
    return maxGrade, trades, leader, members
end

function CanClaim(src, job)
    local d = Duty[src]
    if not d then return false, 'Not on duty' end
    local maxGrade, trades = crewProfile(src)
    local need = Config.MinGrade[job.kind] or 0
    local grade = d.grade
    if grade < need then
        local apprenticeOk = job.kind ~= 'tamper' and job.kind ~= 'leak' and maxGrade >= Config.ApprenticeCrewGrade
        if not apprenticeOk then return false, ('Needs %s'):format(Util.gradeLabel(need)) end
    end
    for _, mid in ipairs(job.meters) do
        local m = Meters[mid]
        if m then
            local needed = Util.tradeFor(job.kind, m.type)
            local ok = false
            for _, t in ipairs(trades) do if Util.tradeAllows(t, needed) then ok = true break end end
            if not ok then return false, ('Needs %s trade'):format(needed) end
        end
    end
    return true
end

local function estimatePay(job)
    local p = Config.Pay
    if job.kind == 'read' then return p.read.pay * #job.meters end
    if job.kind == 'fault' or job.kind == 'report' then return p.fault.pay[1] end
    return (p[job.kind] and p[job.kind].pay) or 0
end

---------------------------------------------------------------------
-- board
---------------------------------------------------------------------
lib.callback.register('as-utilities:getBoard', function(src)
    local d = Duty[src]
    if not d then return nil end
    local list = {}
    for _, job in pairs(Jobs) do
        if job.status == 'open' then
            local ok, why = CanClaim(src, job)
            local first = Meters[job.meters[1]]
            list[#list + 1] = {
                id = job.id, kind = job.kind, label = Config.FaultLabels[job.kind] or job.kind,
                count = #job.meters, coords = first and first.coords, type = first and first.type,
                pay = estimatePay(job), ok = ok, why = why, priority = job.priority, reporter = job.reporter,
                age = os.time() - job.createdAt,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.id < b.id
    end)
    local e = GetEngineer(d.cid)
    local nextG = Config.Grades[d.grade + 1]
    local members, leader = CrewMembers(src)
    local crew = {}
    if #members > 1 then
        for _, m in ipairs(members) do crew[#crew + 1] = { name = PlayerName(m), leader = m == leader } end
    end
    local my = JobOfCrew(src)
    return {
        jobs = list,
        me = { name = PlayerName(src), trade = d.trade, grade = d.grade, gradeLabel = Util.gradeLabel(d.grade),
            xp = e.xp, nextXp = nextG and nextG.xp or nil, jobsDone = e.jobs_done, leader = leader == src },
        crew = crew,
        current = my and ClientJob(my) or nil,
    }
end)

lib.callback.register('as-utilities:claimJob', function(src, id)
    local job = Jobs[id]
    if not job or job.status ~= 'open' then return false, 'Job no longer available' end
    local _, leader = CrewMembers(src)
    if leader ~= src then return false, 'Only your crew leader can claim jobs' end
    if JobOfCrew(src) then return false, 'Finish your current job first' end
    local ok, why = CanClaim(src, job)
    if not ok then return false, why end
    job.status, job.leader, job.claimedAt = 'claimed', src, os.time()
    PushJob(job)
    BoardDirty()
    return true
end)

lib.callback.register('as-utilities:abandonJob', function(src)
    local job = JobOfCrew(src)
    if not job then return false end
    if job.leader ~= src then return false, 'Only the crew leader can hand a job back' end
    crewSend(job, 'as-utilities:jobCleared', job.id)
    job.status, job.leader, job.claimedAt = 'open', nil, nil
    BoardDirty()
    return true
end)

---------------------------------------------------------------------
-- meter sessions
---------------------------------------------------------------------
local function token()
    local t = {}
    for i = 1, 24 do t[i] = string.char(math.random(97, 122)) end
    return table.concat(t)
end

lib.callback.register('as-utilities:openMeter', function(src, meterId)
    local m = Meters[meterId]
    if not m or not OnDuty(src) then return nil end
    if not NearCoords(src, m.coords, Config.InteractDistance + 1.0) then return nil end

    local info = {
        id = m.id, type = m.type, smart = m.smart, state = m.state, serial = Util.serial(m.id, m.type),
        reading = math.floor(m.reading),
    }
    local job = JobOfCrew(src)
    local task = job and job.tasks[meterId]
    if not job or not task or task.done then
        Sessions[src] = nil
        return { info = info, message = m.jobId and 'This meter is on another engineer\'s job' or 'No work booked on this meter' }
    end

    -- a routine read that finds a tampered meter becomes an investigation
    if task.kind == 'read' and m.state == 'tampered' then
        if (Duty[src].grade >= Config.MinGrade.tamper) or select(1, crewProfile(src)) >= Config.MinGrade.tamper then
            task.kind = 'tamper'
            task.foundOnRead = true
        else
            return { info = info, message = 'Reading hasn\'t moved and the seal is broken. Report it - a Senior Engineer must investigate.' }
        end
    end
    -- reports: fault or inspect was decided at report time
    if job.kind == 'leak' then
        local leak = Leaks[meterId]
        if leak and leak.stage ~= 'repair' then
            return { info = info, message = leak.stage == 'sweep' and 'Sweep with the gas detector to find the source first' or ('Cordon the area first (%d/%d cones)'):format(#leak.cones, Config.Leak.cones) }
        end
    end

    local missing = missingItems(src, task.kind, m.type)
    if #missing > 0 then
        return { info = info, message = 'Missing: ' .. table.concat(missing, ', '), task = { kind = task.kind } }
    end

    local s = { token = token(), meterId = meterId, jobId = job.id, kind = task.kind, started = os.time(), reading = math.floor(m.reading) }
    if task.kind == 'install' then s.code = tostring(math.random(1000, 9999)) end
    Sessions[src] = s
    return {
        info = info, token = s.token,
        task = { kind = task.kind, label = Config.FaultLabels[task.kind] or task.kind, code = s.code, reading = s.reading },
    }
end)

local function taskPay(task)
    local p = Config.Pay
    local k = task.kind
    if k == 'read' then
        return math.floor(p.read.pay * (task.wrong and (1 - Config.WrongReadPenalty) or 1)), p.read.xp
    elseif k == 'inspect' then
        return p.nff.pay, p.nff.xp
    elseif k == 'fuse' or k == 'wiring' or k == 'display' or k == 'valve' then
        return math.random(p.fault.pay[1], p.fault.pay[2]), p.fault.xp
    elseif k == 'tamper' then
        return p.tamper.pay + p.tamper.catchBonus, p.tamper.xp
    elseif k == 'install' then
        return p.install.pay, p.install.xp
    elseif k == 'leak' then
        return p.leak.pay, p.leak.xp
    end
    return 0, 0
end

local function finishJob(job)
    local total, xp = 0, 0
    local outcomes = {}
    for _, mid in ipairs(job.meters) do
        local t = job.tasks[mid]
        local pay, x = taskPay(t)
        total, xp = total + pay, xp + x
        outcomes[#outcomes + 1] = t.kind .. (t.wrong and '(wrong)' or '') .. (t.kind == 'inspect' and '(nff)' or '')
    end
    local first = Meters[job.meters[1]]
    if first then
        local km = #(first.coords - Config.Depot.clockOn.coords) / 1000
        total = total + math.floor(km * Config.Pay.distanceBonusPerKm)
    end
    local late = job.claimedAt and (os.time() - job.claimedAt) > (Config.TimeLimit[job.kind] or 900)
    if late then total = math.floor(total * (1 - Config.LatePenalty)) end

    local members = CrewMembers(job.leader)
    local paid = {}
    for _, m in ipairs(members) do if Duty[m] then paid[#paid + 1] = m end end
    if #paid == 0 then paid = { job.leader } end
    local share = math.floor(total / #paid)
    local names = {}
    for _, m in ipairs(paid) do
        local p = GetQbxPlayer(m)
        if p then
            p.Functions.AddMoney(Config.Pay.account, share, 'lsen-job-' .. job.kind)
            AddXp(m, xp, share)
            Notify(m, ('Job complete%s - paid £%d (+%d XP)'):format(late and ' (late)' or '', share, xp), 'success', 7000)
            names[#names + 1] = PlayerName(m)
        end
    end
    local meterList = {}
    for _, mid in ipairs(job.meters) do
        meterList[#meterList + 1] = tostring(mid)
        if Meters[mid] and Meters[mid].jobId == job.id then Meters[mid].jobId = nil end
    end
    MySQL.insert('INSERT INTO as_util_jobs (kind, meters, crew, outcome, pay, late, reporter, created_at, claimed_at, finished_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        job.kind, table.concat(meterList, ','), table.concat(names, ', '), table.concat(outcomes, ','):sub(1, 64),
        total, late and 1 or 0, job.reporter, job.createdAt, job.claimedAt, os.time(),
    })
    crewSend(job, 'as-utilities:jobCleared', job.id)
    Jobs[job.id] = nil
    BoardDirty()
end

lib.callback.register('as-utilities:completeTask', function(src, tok, result)
    local s = Sessions[src]
    if not s or s.token ~= tok then return false, 'Session expired' end
    Sessions[src] = nil
    local job = Jobs[s.jobId]
    local m = Meters[s.meterId]
    if not job or not m or job.status ~= 'claimed' then return false, 'Job no longer active' end
    local _, leader = CrewMembers(src)
    if job.leader ~= leader then return false, 'Not your job' end
    local task = job.tasks[s.meterId]
    if not task or task.done or task.kind ~= s.kind then return false, 'Nothing to do here' end
    if not NearCoords(src, m.coords, Config.InteractDistance + 1.0) then return false, 'Too far from the meter' end
    if os.time() - s.started < (Config.MinTaskTime[s.kind] or 3) then return false, 'Too quick - do it properly' end
    result = type(result) == 'table' and result or {}

    local missing = missingItems(src, s.kind, m.type)
    if #missing > 0 then return false, 'Missing: ' .. table.concat(missing, ', ') end
    local req = requiredFor(s.kind, m.type)
    if req.consume then exports.ox_inventory:RemoveItem(src, Config.Items[req.consume], 1) end

    local msg
    if s.kind == 'read' then
        local v = tonumber(result.value)
        task.wrong = (v == nil) or (math.floor(v) ~= s.reading)
        msg = task.wrong and ('Reading logged - but it was %s. Check your reads.'):format(Util.fmtReading(s.reading)) or 'Reading logged'
    elseif s.kind == 'install' then
        if tostring(result.code) ~= s.code then return false, 'Pairing failed' end
        m.smart = true
        SetMeterState(m, 'ok', nil)
        msg = 'Smart meter commissioned'
    elseif s.kind == 'tamper' then
        local tamperedAt = m.tamperedAt
        SetMeterState(m, 'ok', nil)
        Dispatch.send({
            title = 'Meter tampering reported', code = '10-31',
            message = ('%s reports copper stripped from %s meter %s%s'):format(Config.CompanyShort, m.type, Util.serial(m.id, m.type),
                tamperedAt and (' (approx. %d min ago)'):format(math.floor((os.time() - tamperedAt) / 60)) or ''),
            coords = m.coords, jobs = { 'police' }, sprite = 354, colour = 5,
        })
        msg = 'Meter made safe and resealed. Police report filed.'
    elseif s.kind == 'inspect' then
        msg = 'No fault found - call-out logged'
    elseif s.kind == 'leak' then
        SetMeterState(m, 'ok', nil)
        EndLeak(m.id, true)
        msg = 'Leak repaired and pressure tested. Area safe.'
    else
        SetMeterState(m, 'ok', nil)
        msg = 'Fault repaired'
    end

    task.done = true
    local all = true
    for _, t in pairs(job.tasks) do if not t.done then all = false break end end
    if all then finishJob(job) else PushJob(job) end
    return true, msg
end)

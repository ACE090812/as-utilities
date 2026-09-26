Util = {}

-- which trade a job kind / meter needs. 'any' = either trade
function Util.tradeFor(kind, meterType)
    if kind == 'tamper' then return 'any' end
    if kind == 'leak' then return 'gas' end
    return meterType
end

function Util.tradeAllows(trade, needed)
    if needed == 'any' or trade == 'dual' then return true end
    return trade == needed
end

function Util.serial(id, mtype)
    return ('%s-%06d'):format(mtype == 'gas' and 'G' or 'E', id)
end

function Util.fmtReading(r)
    return ('%05d'):format(math.floor(r or 0) % 100000)
end

function Util.gradeLabel(g)
    local d = Config.Grades[g]
    return d and d.label or ('Grade ' .. tostring(g))
end

function Util.gradeForXp(xp)
    local best = 0
    for g, d in pairs(Config.Grades) do
        if xp >= d.xp and g > best then best = g end
    end
    return best
end

-- forward vector from a heading (degrees)
function Util.fwd(heading)
    local r = math.rad(heading)
    return vec3(-math.sin(r), math.cos(r), 0.0)
end

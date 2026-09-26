Config = {}

Config.Debug = false
Config.JobName = 'taxi'          -- must exist in qbx_core/shared/jobs.lua (see README)
Config.Company = 'LS Energy Networks'
Config.CompanyShort = 'LSEN'

---------------------------------------------------------------------
-- Depot (placeholder coords by the LS power station / El Burro Heights
-- industrial area - set these to your real spots)
---------------------------------------------------------------------
Config.Depot = {
    blip = { coords = vec3(1700.0, -1620.0, 112.5), sprite = 354, colour = 46, scale = 0.8, label = 'LS Energy Networks Depot' },
    clockOn = { coords = vec3(1698.2, -1618.4, 112.5), radius = 1.2 },
    stores  = { coords = vec3(1702.6, -1616.9, 112.5), radius = 1.2 },
    vanDesk = { coords = vec3(1706.1, -1621.3, 112.5), radius = 1.2 },
    vanSpawn = vec4(1712.4, -1628.8, 112.4, 190.0),
    vanReturn = { coords = vec3(1716.0, -1624.0, 112.4), radius = 6.0 },
    -- job board: a floating DUI panel on a wall. centre, heading = direction the board FACES
    board = { coords = vec3(1699.8, -1613.2, 113.9), heading = 190.0, width = 1.6 },
}

---------------------------------------------------------------------
-- Grades / XP (auto promotion). grade index must match qbx job grades
---------------------------------------------------------------------
Config.Grades = {
    [0] = { label = 'Recruit',          xp = 0 },
    [1] = { label = 'Driver',          xp = 150 },
    [2] = { label = 'Event Driver',          xp = 600 },
    [3] = { label = 'Sales',          xp = 1500 },
    [4] = { label = 'Manager',          xp = 2000 },
  --  [0] = { label = 'Apprentice',          xp = 0 },
  --  [1] = { label = 'Meter Engineer',      xp = 150 },
   -- [2] = { label = 'Senior Engineer',     xp = 600 },
   -- [3] = { label = 'Dual Fuel Engineer',  xp = 1500 },
}

-- minimum grade to CLAIM each job kind (apprentices may do faults in a crew with a Senior+)
Config.MinGrade = {
    read = 0, fault = 1, report = 1, install = 1, tamper = 2, leak = 2,
}
Config.ApprenticeCrewGrade = 2

---------------------------------------------------------------------
-- Vans (deposit refunded minus damage). minGrade gates the model
---------------------------------------------------------------------
Config.Vans = {
    { model = 'speedo',  label = 'Small Van',    minGrade = 0, deposit = 500 },
    { model = 'burrito3', label = 'Transit Van', minGrade = 1, deposit = 750 },
    { model = 'sandking2', label = 'Rural 4x4',  minGrade = 2, deposit = 1000 },
}
Config.VanLivery = nil          -- livery index or nil
Config.VanPlatePrefix = 'LSEN'
Config.DamageCostPerPoint = 1.0 -- £ per point of body+engine health lost (max 2000 lost)
Config.DepositAccount = 'bank'

-- called server side after a van spawns (give keys / fuel). edit for your key script
Config.GiveVanKeys = function(src, vehicle, plate)
    if GetResourceState('qbx_vehiclekeys') == 'started' then
        pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, vehicle) end)
    end
end

---------------------------------------------------------------------
-- Uniform (applied on clock-on, skin reloaded on clock-off)
---------------------------------------------------------------------
Config.Uniform = {
    male = {
        { component = 11, drawable = 146, texture = 0 }, -- top (hi-vis)
        { component = 8,  drawable = 59,  texture = 0 },
        { component = 3,  drawable = 1,   texture = 0 },
        { component = 4,  drawable = 36,  texture = 0 }, -- work trousers
        { component = 6,  drawable = 25,  texture = 0 }, -- boots
    },
    female = {
        { component = 11, drawable = 143, texture = 0 },
        { component = 8,  drawable = 36,  texture = 0 },
        { component = 3,  drawable = 3,   texture = 0 },
        { component = 4,  drawable = 35,  texture = 0 },
        { component = 6,  drawable = 26,  texture = 0 },
    },
}

---------------------------------------------------------------------
-- Items
---------------------------------------------------------------------
Config.Items = {
    reader = 'meter_reader', multimeter = 'multimeter', detector = 'gas_detector',
    toolkit = 'engineer_toolkit', smart = 'smart_meter', seal = 'tamper_seal',
    fuse = 'meter_fuse', valve = 'regulator_valve', bypass = 'meter_bypass_kit', copper = 'copper_wire',
}
-- stores counter tops engineers up to these amounts (free, on duty only)
Config.Stores = {
    meter_reader = 1, multimeter = 1, gas_detector = 1, engineer_toolkit = 1,
    meter_fuse = 4, regulator_valve = 3, tamper_seal = 4, smart_meter = 2,
}
-- job items removed on clock-off so they can't be sold on
Config.RemoveItemsOnClockOff = true

---------------------------------------------------------------------
-- Meters
---------------------------------------------------------------------
Config.Props = {
    electric = { normal = 'prop_elecbox_09', smart = 'prop_elecbox_10' },
    gas      = { normal = 'prop_elecbox_01a', smart = 'prop_elecbox_02a' },
}
Config.PropHeadingOffset = 0.0      -- add 180.0 if your meter props face backwards
Config.SpawnDistance = 80.0
Config.ScreenShowDistance = 3.5     -- idle status panel shows to on-duty engineers within this range
Config.InteractDistance = 3.0       -- server-checked distance for every action
Config.ReadingRate = { electric = 0.6, gas = 0.25 } -- units per minute
Config.ReadingPersistEvery = 5      -- minutes

-- Screen panel placement relative to meter (meter heading = direction its front faces)
Config.Screen = { forward = 0.45, up = 0.15, width = 0.64 }

---------------------------------------------------------------------
-- Job generation (always running, capped)
---------------------------------------------------------------------
Config.Generation = {
    interval = 90,           -- seconds between generation ticks
    maxOpenJobs = 25,        -- backlog cap
    readRouteSize = { 3, 6 },
    readRouteRadius = 600.0,
    weights = { read = 50, fault = 35, install = 15 },
    leakChance = 3,          -- % per tick (max Config.Leak.maxActive)
}

Config.Faults = {
    electric = { 'fuse', 'wiring', 'display' },
    gas = { 'valve', 'display' },
}
Config.FaultLabels = {
    fuse = 'Blown main fuse', wiring = 'Wiring fault', display = 'Dead display', valve = 'Sticking regulator valve',
    inspect = 'Reported fault - inspect', tamper = 'Suspected tampering', install = 'Smart meter install',
    leak = 'GAS LEAK', read = 'Meter read',
}

Config.Report = {
    playerCooldown = 600,  -- seconds
    realFaultChance = 65,  -- % a report is a real fault, otherwise "No fault found"
}

-- time allowed after claiming (seconds) before late penalty
Config.TimeLimit = { read = 900, fault = 720, report = 720, install = 900, tamper = 900, leak = 600 }
Config.LatePenalty = 0.25
Config.WrongReadPenalty = 0.5
-- minimum seconds a task must take (anti-exploit)
Config.MinTaskTime = { read = 3, fuse = 6, wiring = 6, display = 5, valve = 8, inspect = 4, tamper = 8, install = 10, leak = 8 }

---------------------------------------------------------------------
-- Pay / XP
---------------------------------------------------------------------
Config.Pay = {
    read = { pay = 60, xp = 5 },          -- per meter
    nff = { pay = 100, xp = 5 },          -- no fault found
    fault = { pay = { 250, 400 }, xp = 15 },
    install = { pay = 350, xp = 20 },
    tamper = { pay = 500, xp = 30, catchBonus = 250 },
    leak = { pay = 900, xp = 50 },
    distanceBonusPerKm = 20,              -- from depot to first meter
    account = 'bank',
}

---------------------------------------------------------------------
-- Tampering / copper theft
---------------------------------------------------------------------
Config.Tamper = {
    minPolice = 2,
    policeJobType = 'leo',
    copper = { 2, 5 },
    meterCooldown = 3600,     -- seconds before the same meter can be stripped again
    detectDelay = 600,        -- non-smart: "reading stopped" flag after this many seconds
    witnessAlertChance = 30,  -- % chance police are alerted while stripping
    failGasLeakChance = 25,   -- % failed skillcheck on a gas meter causes a leak
    failShockDamage = 20,     -- failed skillcheck on electric
    progress = 12000,
    skill = { 'easy', 'medium', 'medium', 'hard' },
}

Config.ScrapBuyer = {
    enabled = true,
    ped = 's_m_y_dockwork_01',
    coords = vec4(2340.2, 3126.4, 48.2, 250.0),  -- Sandy scrapyard, change to taste
    price = { 45, 70 },  -- per copper_wire
    account = 'cash',
}

---------------------------------------------------------------------
-- Gas leaks
---------------------------------------------------------------------
Config.Leak = {
    maxActive = 1,
    radius = 18.0,
    damage = 3,             -- hp every 3s inside the zone
    engineerImmune = true,  -- on duty engineers holding a gas detector take no damage
    escalateAfter = 420,    -- seconds unrepaired before it explodes by itself
    explosionType = 9,      -- EXP_TAG_PETROL_PUMP
    igniteCooldown = 45,
    cones = 3,
    coneModel = 'prop_roadcone02a',
    coneMinDist = 4.0,
    coneMaxDist = 16.0,
    alertJobs = { 'police', 'ambulance' },
}

---------------------------------------------------------------------
-- Dispatch: 'ps' (ps-dispatch), 'cd' (cd_dispatch) or 'custom'
---------------------------------------------------------------------
Config.Dispatch = 'ps'
Config.CustomDispatch = function(alert) end  -- alert = { title, message, code, coords, jobs, sprite }

---------------------------------------------------------------------
-- Admin placement tool
---------------------------------------------------------------------
Config.AdminGroup = 'group.admin'

-- paste into qbx_core/shared/jobs.lua
['utilities'] = {
    label = 'LS Energy Networks',
    type = 'utilities',
    defaultDuty = false,
    offDutyPay = false,
    grades = {
        [0] = { name = 'Apprentice', payment = 50 },
        [1] = { name = 'Meter Engineer', payment = 75 },
        [2] = { name = 'Senior Engineer', payment = 100 },
        [3] = { name = 'Dual Fuel Engineer', payment = 125 },
    },
},

-- job centre (qbx_cityhall config.lua -> jobs table), so anyone can take it:
-- ['utilities'] = { label = 'Gas & Electric Engineer', isManaged = false },

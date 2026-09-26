Dispatch = {}

-- alert = { title, message, code, coords (vec3), jobs = {'police'}, sprite, colour, priority }
function Dispatch.send(alert)
    local c = alert.coords
    if Config.Dispatch == 'ps' and GetResourceState('ps-dispatch') == 'started' then
        TriggerEvent('ps-dispatch:server:notify', {
            message = alert.title,
            codeName = 'as_utilities',
            code = alert.code or '10-35',
            icon = 'fas fa-bolt',
            priority = alert.priority or 2,
            coords = c,
            street = alert.message,
            information = alert.message,
            jobs = alert.jobs,
            alert = {
                radius = 0, sprite = alert.sprite or 354, color = alert.colour or 1,
                scale = 1.0, length = 3, sound = 'Lose_1st', sound2 = 'GTAO_FM_Events_Soundset',
                offset = false, flash = false,
            },
        })
    elseif Config.Dispatch == 'cd' and GetResourceState('cd_dispatch') == 'started' then
        TriggerClientEvent('cd_dispatch:AddNotification', -1, {
            job_table = alert.jobs,
            coords = c,
            title = alert.code and (alert.code .. ' - ' .. alert.title) or alert.title,
            message = alert.message,
            flash = 0,
            unique_id = tostring(math.random(0000000, 9999999)),
            sound = 1,
            blip = {
                sprite = alert.sprite or 354, scale = 1.1, colour = alert.colour or 1,
                flashes = false, text = alert.title, time = 5, radius = 0,
            },
        })
    else
        local ok, err = pcall(Config.CustomDispatch, alert)
        if not ok then print('[as-utilities] custom dispatch error: ' .. tostring(err)) end
    end
end

PlateUtils = PlateUtils or {}

function PlateUtils.RandomLetters(n)
    local s = ''
    for i = 1, n do
        s = s .. string.char(math.random(65, 90))
    end
    return s
end

function PlateUtils.RandomNumbers(n)
    local s = ''
    for i = 1, n do
        s = s .. tostring(math.random(0, 9))
    end
    return s
end

function PlateUtils.GenerateAAA9999()
    return PlateUtils.RandomLetters(3) .. PlateUtils.RandomNumbers(4)
end

function PlateUtils.GenerateFromFormat(format)
    local result = ''
    for i = 1, #format do
        local ch = format:sub(i, i)
        if ch == 'A' then
            result = result .. PlateUtils.RandomLetters(1)
        elseif ch == '9' then
            result = result .. PlateUtils.RandomNumbers(1)
        else
            return PlateUtils.GenerateAAA9999()
        end
    end
    return result
end

function PlateUtils.GenerateFromConfig()
    local format = Config and Config.PlateFormat or 'AAA9999'
    if type(format) ~= 'string' or format == '' then
        format = 'AAA9999'
    end
    return PlateUtils.GenerateFromFormat(format:upper())
end

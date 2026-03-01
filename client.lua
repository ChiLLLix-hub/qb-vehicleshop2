-- Variables
local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = QBCore.Functions.GetPlayerData()
local testDriveZone = nil
local vehicleMenu = {}
local Initialized = false
local testDriveVeh, inTestDrive = 0, false
ClosestVehicle = 1  -- Global so it can be accessed from client_nui.lua
local zones = {}
local showroomVehicles = {}
local activeMenuLockShop = nil
insideShop, tempShop = nil, nil  -- Global so insideShop can be accessed from client_nui.lua

-- Constants
local Keys = {
    E = 38  -- Interact key
}

-- Handlers
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    local citizenid = PlayerData.citizenid
    TriggerServerEvent('qb-vehicleshop:server:addPlayer', citizenid)
    TriggerServerEvent('qb-vehicleshop:server:checkFinance')
    if not Initialized then Init() end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end
    if next(PlayerData) ~= nil and not Initialized then
        PlayerData = QBCore.Functions.GetPlayerData()
        local citizenid = PlayerData.citizenid
        TriggerServerEvent('qb-vehicleshop:server:addPlayer', citizenid)
        TriggerServerEvent('qb-vehicleshop:server:checkFinance')
        Init()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end
    if ReleaseShopMenuLock then
        ReleaseShopMenuLock()
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerData.job = JobInfo
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    local citizenid = PlayerData.citizenid
    TriggerServerEvent('qb-vehicleshop:server:removePlayer', citizenid)
    if ReleaseShopMenuLock then
        ReleaseShopMenuLock()
    end
    PlayerData = {}
end)

local function CheckPlate(vehicle, plateToSet)
    local vehiclePlate = promise.new()
    CreateThread(function()
        while true do
            Wait(500)
            if GetVehicleNumberPlateText(vehicle) == plateToSet then
                vehiclePlate:resolve(true)
                return
            else
                SetVehicleNumberPlateText(vehicle, plateToSet)
            end
        end
    end)
    return vehiclePlate
end

-- Static Headers
local vehHeaderMenu = {
    {
        header = Lang:t('menus.vehHeader_header'),
        txt = Lang:t('menus.vehHeader_txt'),
        icon = 'fa-solid fa-car',
        params = {
            event = 'qb-vehicleshop:client:showVehOptions'
        }
    }
}

local financeMenu = {
    {
        header = Lang:t('menus.financed_header'),
        txt = Lang:t('menus.finance_txt'),
        icon = 'fa-solid fa-user-ninja',
        params = {
            event = 'qb-vehicleshop:client:getVehicles'
        }
    }
}

local returnTestDrive = {
    {
        header = Lang:t('menus.returnTestDrive_header'),
        icon = 'fa-solid fa-flag-checkered',
        params = {
            event = 'qb-vehicleshop:client:TestDriveReturn'
        }
    }
}

-- Functions
local function drawTxt(text, font, x, y, scale, r, g, b, a)
    SetTextFont(font)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    SetTextOutline()
    SetTextCentre(1)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

local function tablelength(T)
    local count = 0
    for _ in pairs(T) do
        count = count + 1
    end
    return count
end

local function comma_value(amount)
    local formatted = amount
    local k
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then
            break
        end
    end
    return formatted
end

local function registerShowroomVehicle(shopName, vehicleIndex, entity)
    if not showroomVehicles[shopName] then
        showroomVehicles[shopName] = {}
    end
    showroomVehicles[shopName][vehicleIndex] = entity
end

local function clearShowroomSlot(shopName, vehicleIndex)
    if not Config.Shops[shopName] or not Config.Shops[shopName]['ShowroomVehicles'][vehicleIndex] then
        return
    end

    if showroomVehicles[shopName] and showroomVehicles[shopName][vehicleIndex] and DoesEntityExist(showroomVehicles[shopName][vehicleIndex]) then
        DeleteEntity(showroomVehicles[shopName][vehicleIndex])
    end
    if showroomVehicles[shopName] then
        showroomVehicles[shopName][vehicleIndex] = nil
    end

    local slotCoords = Config.Shops[shopName]['ShowroomVehicles'][vehicleIndex].coords
    local slotPos = vector3(slotCoords.x, slotCoords.y, slotCoords.z)
    local vehicles = GetGamePool('CVehicle')

    for i = 1, #vehicles do
        local veh = vehicles[i]
        if DoesEntityExist(veh) and #(GetEntityCoords(veh) - slotPos) < 2.25 then
            local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('%s+', '')
            if plate == 'BUYME' then
                DeleteEntity(veh)
            end
        end
    end
end

local function getVehName()
    return QBCore.Shared.Vehicles[Config.Shops[insideShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle]['name']
end

local function getVehPrice()
    return comma_value(QBCore.Shared.Vehicles[Config.Shops[insideShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle]['price'])
end

local function getVehBrand()
    return QBCore.Shared.Vehicles[Config.Shops[insideShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle]['brand']
end

local function getCurrentVehicleData()
    local vehicleModel = Config.Shops[insideShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle
    local vehData = QBCore.Shared.Vehicles[vehicleModel]
    return {
        model = vehicleModel,
        name = vehData.name,
        brand = vehData.brand,
        price = vehData.price,
        category = vehData.category,
        stats = vehData.stats or nil
    }
end

local function ResolveShopForPurchase(preferredShop)
    if preferredShop and Config.Shops[preferredShop] then
        return preferredShop
    end

    if insideShop and Config.Shops[insideShop] then
        return insideShop
    end

    local pedCoords = GetEntityCoords(PlayerPedId())
    local nearestShop = nil
    local nearestDistance = math.huge

    for shopName, shopData in pairs(Config.Shops) do
        if shopData.VehicleSpawn then
            local dist = #(pedCoords - vector3(shopData.VehicleSpawn.x, shopData.VehicleSpawn.y, shopData.VehicleSpawn.z))
            if dist < nearestDistance then
                nearestDistance = dist
                nearestShop = shopName
            end
        end
    end

    if nearestShop and nearestDistance <= 100.0 then
        return nearestShop
    end

    return nil
end

function ReleaseShopMenuLock(showNotify)
    if not activeMenuLockShop then
        return
    end

    TriggerServerEvent('qb-vehicleshop:server:releaseMenuLock', activeMenuLockShop)
    activeMenuLockShop = nil
    if showNotify then
        QBCore.Functions.Notify('Shop menu control released (you left the showroom area).', 'primary')
    end
end

local function TryOpenVehicleMenu()
    if not insideShop or not Config.Shops[insideShop] then
        return
    end

    QBCore.Functions.TriggerCallback('qb-vehicleshop:server:acquireMenuLock', function(acquired, holderName)
        if acquired then
            activeMenuLockShop = insideShop
            OpenVehicleNUI(getCurrentVehicleData())
            return
        end

        if holderName and holderName ~= '' then
            QBCore.Functions.Notify(('Shop menu is currently in use by %s.'):format(holderName), 'error')
        else
            QBCore.Functions.Notify('Shop menu is currently in use by another player.', 'error')
        end
    end, insideShop)
end

local function setClosestShowroomVehicle()
    local pos = GetEntityCoords(PlayerPedId(), true)
    local current = nil
    local dist = nil
    local closestShop = insideShop
    for id in pairs(Config.Shops[closestShop]['ShowroomVehicles']) do
        local dist2 = #(pos - vector3(Config.Shops[closestShop]['ShowroomVehicles'][id].coords.x, Config.Shops[closestShop]['ShowroomVehicles'][id].coords.y, Config.Shops[closestShop]['ShowroomVehicles'][id].coords.z))
        if current then
            if dist2 < dist then
                current = id
                dist = dist2
            end
        else
            dist = dist2
            current = id
        end
    end
    if current ~= ClosestVehicle then
        ClosestVehicle = current
    end
end

local function createTestDriveReturn()
    testDriveZone = BoxZone:Create(
        Config.Shops[insideShop]['ReturnLocation'],
        3.0,
        5.0,
        {
            name = 'box_zone_testdrive_return_' .. insideShop,
        })

    testDriveZone:onPlayerInOut(function(isPointInside)
        if isPointInside and IsPedInAnyVehicle(PlayerPedId()) then
            SetVehicleForwardSpeed(GetVehiclePedIsIn(PlayerPedId(), false), 0)
            -- NUI will show return button in test drive overlay, no need for separate menu
        else
            -- Nothing to close since we're using the test drive overlay
        end
    end)
end

local function startTestDriveTimer(testDriveTime, prevCoords)
    local gameTimer = GetGameTimer()
    CreateThread(function()
        Wait(2000) -- Avoids the condition to run before entering vehicle
        while inTestDrive do
            -- Check for E key press to end test drive early
            if IsControlJustPressed(0, Keys.E) then
                TriggerServerEvent('qb-vehicleshop:server:deleteVehicle', testDriveVeh)
                testDriveVeh = 0
                inTestDrive = false
                SetEntityCoords(PlayerPedId(), prevCoords)
                QBCore.Functions.Notify(Lang:t('general.testdrive_complete'))
                EndTestDriveNUI()
                if testDriveZone then
                    testDriveZone:destroy()
                end
                break
            end
            
            if GetGameTimer() < gameTimer + tonumber(1000 * testDriveTime) then
                local secondsLeft = GetGameTimer() - gameTimer
                if secondsLeft >= tonumber(1000 * testDriveTime) - 20 or GetPedInVehicleSeat(NetToVeh(testDriveVeh), -1) ~= PlayerPedId() then
                    TriggerServerEvent('qb-vehicleshop:server:deleteVehicle', testDriveVeh)
                    testDriveVeh = 0
                    inTestDrive = false
                    SetEntityCoords(PlayerPedId(), prevCoords)
                    QBCore.Functions.Notify(Lang:t('general.testdrive_complete'))
                    EndTestDriveNUI()
                    if testDriveZone then
                        testDriveZone:destroy()
                    end
                end
                -- Update NUI with time remaining
                local timeLeft = math.ceil(testDriveTime - secondsLeft / 1000)
                local minutes = math.floor(timeLeft / 60)
                local seconds = timeLeft % 60
                UpdateTestDriveTime(string.format("%d:%02d", minutes, seconds))
            end
            Wait(0)
        end
    end)
end

local function createVehZones(shopName, entity)
    if not Config.UsingTarget then
        for i = 1, #Config.Shops[shopName]['ShowroomVehicles'] do
            zones[#zones + 1] = BoxZone:Create(
                vector3(Config.Shops[shopName]['ShowroomVehicles'][i]['coords'].x,
                    Config.Shops[shopName]['ShowroomVehicles'][i]['coords'].y,
                    Config.Shops[shopName]['ShowroomVehicles'][i]['coords'].z),
                Config.Shops[shopName]['Zone']['size'],
                Config.Shops[shopName]['Zone']['size'],
                {
                    name = 'box_zone_' .. shopName .. '_' .. i,
                    minZ = Config.Shops[shopName]['Zone']['minZ'],
                    maxZ = Config.Shops[shopName]['Zone']['maxZ'],
                    debugPoly = false,
                })
        end
        local combo = ComboZone:Create(zones, { name = 'vehCombo', debugPoly = false })
        combo:onPlayerInOut(function(isPointInside)
            if isPointInside then
                if PlayerData and PlayerData.job and (PlayerData.job.name == Config.Shops[insideShop]['Job'] or Config.Shops[insideShop]['Job'] == 'none') then
                    -- This creates zones around individual vehicles for non-target mode
                    -- The shop polyzone already handles the menu display, so we don't need to duplicate here
                end
            else
                -- Don't close NUI here as the shop polyzone handles it
            end
        end)
    else
        exports['qb-target']:AddTargetEntity(entity, {
            options = {
                {
                    type = 'client',
                    event = 'qb-vehicleshop:client:showVehOptions',
                    icon = 'fas fa-car',
                    label = Lang:t('general.vehinteraction'),
                    canInteract = function()
                        local closestShop = insideShop
                        return closestShop and (Config.Shops[closestShop]['Job'] == 'none' or PlayerData.job.name == Config.Shops[closestShop]['Job'])
                    end
                },
            },
            distance = 3.0
        })
    end
end

-- Zones
local function createFreeUseShop(shopShape, name)
    local zone = PolyZone:Create(shopShape, {
        name = name,
        minZ = shopShape.minZ,
        maxZ = shopShape.maxZ,
    })

    zone:onPlayerInOut(function(isPointInside)
        if isPointInside then
            insideShop = name
            CreateThread(function()
                while insideShop do
                    setClosestShowroomVehicle()
                    -- Show help text only if not using target system
                    if not Config.UsingTarget then
                        drawTxt('[E] - ' .. getVehBrand():upper() .. ' ' .. getVehName():upper() .. ' - $' .. getVehPrice(), 4, 0.5, 0.93, 0.50, 255, 255, 255, 180)
                        
                        -- Check if E is pressed to open NUI
                        if IsControlJustPressed(0, Keys.E) then
                            TryOpenVehicleMenu()
                        end
                    end
                    Wait(0)
                end
            end)
        else
            ReleaseShopMenuLock(true)
            insideShop = nil
            ClosestVehicle = 1
        end
    end)
end

local function createManagedShop(shopShape, name)
    local zone = PolyZone:Create(shopShape, {
        name = name,
        minZ = shopShape.minZ,
        maxZ = shopShape.maxZ,
    })

    zone:onPlayerInOut(function(isPointInside)
        if isPointInside then
            insideShop = name
            CreateThread(function()
                while insideShop and PlayerData.job and PlayerData.job.name == Config.Shops[name]['Job'] do
                    setClosestShowroomVehicle()
                    -- Show help text only if not using target system (for managed shops, employee only)
                    if not Config.UsingTarget then
                        drawTxt('[E] - ' .. getVehBrand():upper() .. ' ' .. getVehName():upper() .. ' - $' .. getVehPrice(), 4, 0.5, 0.93, 0.50, 255, 255, 255, 180)
                        
                        -- Check if E is pressed to open NUI
                        if IsControlJustPressed(0, Keys.E) then
                            TryOpenVehicleMenu()
                        end
                    end
                    Wait(0)
                end
            end)
        else
            ReleaseShopMenuLock(true)
            insideShop = nil
            ClosestVehicle = 1
        end
    end)
end

local function createFinanceZone(coords, name)
    local financeZone = BoxZone:Create(coords, 2.0, 2.0, {
        name = 'vehicleshop_financeZone_' .. name,
        offset = { 0.0, 0.0, 0.0 },
        scale = { 1.0, 1.0, 1.0 },
        minZ = coords.z - 1,
        maxZ = coords.z + 1,
        debugPoly = false,
    })

    financeZone:onPlayerInOut(function(isPointInside)
        if isPointInside then
            exports['qb-menu']:showHeader(financeMenu)
        else
            exports['qb-menu']:closeMenu()
        end
    end)
end

function Init()
    Initialized = true
    CreateThread(function()
        for name, shop in pairs(Config.Shops) do
            if shop['Type'] == 'free-use' then
                createFreeUseShop(shop['Zone']['Shape'], name)
            elseif shop['Type'] == 'managed' then
                createManagedShop(shop['Zone']['Shape'], name)
            end
            if shop['FinanceZone'] then createFinanceZone(shop['FinanceZone'], name) end
        end
    end)
    CreateThread(function()
        for k in pairs(Config.Shops) do
            for i = 1, #Config.Shops[k]['ShowroomVehicles'] do
                local model = GetHashKey(Config.Shops[k]['ShowroomVehicles'][i].defaultVehicle)
                RequestModel(model)
                while not HasModelLoaded(model) do
                    Wait(0)
                end
                local veh = CreateVehicle(model, Config.Shops[k]['ShowroomVehicles'][i].coords.x, Config.Shops[k]['ShowroomVehicles'][i].coords.y, Config.Shops[k]['ShowroomVehicles'][i].coords.z, false, false)
                SetModelAsNoLongerNeeded(model)
                SetVehicleOnGroundProperly(veh)
                SetEntityInvincible(veh, true)
                SetVehicleDirtLevel(veh, 0.0)
                SetVehicleDoorsLocked(veh, 3)
                SetEntityHeading(veh, Config.Shops[k]['ShowroomVehicles'][i].coords.w)
                FreezeEntityPosition(veh, true)
                SetEntityAsMissionEntity(veh, true, true)  -- Protect from deletion
                SetVehicleHasBeenOwnedByPlayer(veh, false)
                SetVehicleNumberPlateText(veh, 'BUY ME')
                registerShowroomVehicle(k, i, veh)
                if Config.UsingTarget then createVehZones(k, veh) end
            end
            if not Config.UsingTarget then createVehZones(k) end
        end
    end)
end

-- Events
RegisterNetEvent('qb-vehicleshop:client:homeMenu', function()
    TryOpenVehicleMenu()
end)

RegisterNetEvent('qb-vehicleshop:client:showVehOptions', function()
    TryOpenVehicleMenu()
end)

RegisterNetEvent('qb-vehicleshop:client:TestDrive', function()
    if not inTestDrive and ClosestVehicle ~= 0 then
        inTestDrive = true
        local prevCoords = GetEntityCoords(PlayerPedId())
        tempShop = insideShop -- temp hacky way of setting the shop because it changes after the callback has returned since you are outside the zone
        QBCore.Functions.TriggerCallback('qb-vehicleshop:server:spawnvehicle', function(netId, properties, vehPlate)
            local timeout = 5000
            local startTime = GetGameTimer()
            while not NetworkDoesNetworkIdExist(netId) do
                Wait(10)
                if GetGameTimer() - startTime > timeout then
                    return
                end
            end
            local veh = NetworkGetEntityFromNetworkId(netId)
            NetworkRequestControlOfEntity(veh)
            SetEntityAsMissionEntity(veh, true, true)
            Citizen.InvokeNative(0xAD738C3085FE7E11, veh, true, true)
            SetVehicleNumberPlateText(veh, vehPlate)
            exports['LegacyFuel']:SetFuel(veh, 100)
            TriggerEvent('vehiclekeys:client:SetOwner', vehPlate)
            TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
            SetVehicleEngineOn(veh, true, true, false)
            testDriveVeh = netId
            QBCore.Functions.Notify(Lang:t('general.testdrive_timenoti', { testdrivetime = Config.Shops[tempShop]['TestDriveTimeLimit'] }), "success")
            StartTestDriveNUI() -- Show NUI test drive overlay
        end, 'TESTDRIVE', Config.Shops[tempShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle, Config.Shops[tempShop]['TestDriveSpawn'], true) 

        createTestDriveReturn()
        startTestDriveTimer(Config.Shops[tempShop]['TestDriveTimeLimit'] * 60, prevCoords)
    else
        QBCore.Functions.Notify(Lang:t('error.testdrive_alreadyin'), 'error')
    end
end)

RegisterNetEvent('qb-vehicleshop:client:customTestDrive', function(data)
    if not inTestDrive then
        inTestDrive = true
        local vehicle = data
        local prevCoords = GetEntityCoords(PlayerPedId())
        tempShop = insideShop -- temp hacky way of setting the shop because it changes after the callback has returned since you are outside the zone
        QBCore.Functions.TriggerCallback('qb-vehicleshop:server:spawnvehicle', function(netId, properties, vehPlate)
            local timeout = 5000
            local startTime = GetGameTimer()
            while not NetworkDoesNetworkIdExist(netId) do
                Wait(10)
                if GetGameTimer() - startTime > timeout then
                    return
                end
            end
            local veh = NetworkGetEntityFromNetworkId(netId)
            NetworkRequestControlOfEntity(veh)
            SetEntityAsMissionEntity(veh, true, true)
            Citizen.InvokeNative(0xAD738C3085FE7E11, veh, true, true)
            SetVehicleNumberPlateText(veh, vehPlate)
            exports['LegacyFuel']:SetFuel(veh, 100)
            TriggerEvent('vehiclekeys:client:SetOwner', vehPlate)
            TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
            SetVehicleEngineOn(veh, true, true, false)
            testDriveVeh = netId
            QBCore.Functions.Notify(Lang:t('general.testdrive_timenoti', { testdrivetime = Config.Shops[tempShop]['TestDriveTimeLimit'] }))
        end, 'TESTDRIVE', Config.Shops[tempShop]['ShowroomVehicles'][ClosestVehicle].chosenVehicle, Config.Shops[tempShop]['TestDriveSpawn'], true) 
        createTestDriveReturn()
        startTestDriveTimer(Config.Shops[tempShop]['TestDriveTimeLimit'] * 60, prevCoords)
    else
        QBCore.Functions.Notify(Lang:t('error.testdrive_alreadyin'), 'error')
    end
end)

RegisterNetEvent('qb-vehicleshop:client:TestDriveReturn', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped)
    local entity = NetworkGetEntityFromNetworkId(testDriveVeh)
    if veh == entity then
        testDriveVeh = 0
        inTestDrive = false
        DeleteEntity(veh)
        EndTestDriveNUI()
        testDriveZone:destroy()
    else
        QBCore.Functions.Notify(Lang:t('error.testdrive_return'), 'error')
    end
end)

RegisterNetEvent('qb-vehicleshop:client:vehCategories', function(data)
    local catmenu = {}
    local categories = {}
    local firstvalue = nil
    
    for k, v in pairs(QBCore.Shared.Vehicles) do
        if type(QBCore.Shared.Vehicles[k]['shop']) == 'table' then
            for _, shop in pairs(QBCore.Shared.Vehicles[k]['shop']) do
                if shop == insideShop and (not Config.FilterByMake or QBCore.Shared.Vehicles[k]['brand'] == data.make) then
                    catmenu[v.category] = v.category
                    if firstvalue == nil then
                        firstvalue = v.category
                    end
                end
            end
        elseif QBCore.Shared.Vehicles[k]['shop'] == insideShop and (not Config.FilterByMake or QBCore.Shared.Vehicles[k]['brand'] == data.make) then
            catmenu[v.category] = v.category
            if firstvalue == nil then
                firstvalue = v.category
            end
        end
    end
    
    if Config.HideCategorySelectForOne and tablelength(catmenu) == 1 then
        TriggerEvent('qb-vehicleshop:client:openVehCats', { catName = firstvalue, make = Config.FilterByMake and data.make, onecat = true })
        return
    end
    
    -- Convert to NUI format
    for k, v in pairs(catmenu) do
        categories[#categories + 1] = {
            id = k,
            name = v,
            icon = '🚗'
        }
    end
    
    OpenCategoryNUI(categories)
end)

RegisterNetEvent('qb-vehicleshop:client:openVehCats', function(data)
    local vehicles = {}
    
    for k, v in pairs(QBCore.Shared.Vehicles) do
        if QBCore.Shared.Vehicles[k]['category'] == data.catName then
            if type(QBCore.Shared.Vehicles[k]['shop']) == 'table' then
                for _, shop in pairs(QBCore.Shared.Vehicles[k]['shop']) do
                    if shop == insideShop then
                        vehicles[#vehicles + 1] = {
                            model = v.model,
                            name = v.name,
                            brand = v.brand,
                            price = v.price,
                            category = v.category
                        }
                    end
                end
            elseif QBCore.Shared.Vehicles[k]['shop'] == insideShop then
                vehicles[#vehicles + 1] = {
                    model = v.model,
                    name = v.name,
                    brand = v.brand,
                    price = v.price,
                    category = v.category
                }
            end
        end
    end
    
    -- Pass category context to NUI
    OpenVehicleListNUI(vehicles, {
        catName = data.catName,
        make = data.make,
        onecat = data.onecat
    })
end)

RegisterNetEvent('qb-vehicleshop:client:vehMakes', function()
    local makmenu = {}
    local makes = {}
    
    for k, v in pairs(QBCore.Shared.Vehicles) do
        if type(QBCore.Shared.Vehicles[k]['shop']) == 'table' then
            for _, shop in pairs(QBCore.Shared.Vehicles[k]['shop']) do
                if shop == insideShop then
                    makmenu[v.brand] = v.brand
                end
            end
        elseif QBCore.Shared.Vehicles[k]['shop'] == insideShop then
            makmenu[v.brand] = v.brand
        end
    end
    
    -- Convert to NUI format
    for _, v in pairs(makmenu) do
        makes[#makes + 1] = {
            id = v,
            name = v,
            icon = '🏢',
            type = 'make'  -- Explicitly mark as make for NUI callback
        }
    end
    
    OpenCategoryNUI(makes)
end)

RegisterNetEvent('qb-vehicleshop:client:openFinance', function(data)
    local dialog = exports['qb-input']:ShowInput({
        header = getVehBrand():upper() .. ' ' .. data.buyVehicle:upper() .. ' - $' .. data.price,
        submitText = Lang:t('menus.submit_text'),
        inputs = {
            {
                type = 'number',
                isRequired = true,
                name = 'downPayment',
                text = Lang:t('menus.financesubmit_downpayment') .. Config.MinimumDown .. '%'
            },
            {
                type = 'number',
                isRequired = true,
                name = 'paymentAmount',
                text = Lang:t('menus.financesubmit_totalpayment') .. Config.MaximumPayments
            }
        }
    })
    if dialog then
        if not dialog.downPayment or not dialog.paymentAmount then return end
        TriggerServerEvent('qb-vehicleshop:server:financeVehicle', dialog.downPayment, dialog.paymentAmount, data.buyVehicle)
    end
end)

RegisterNetEvent('qb-vehicleshop:client:openCustomFinance', function(data)
    local dialog = exports['qb-input']:ShowInput({
        header = getVehBrand():upper() .. ' ' .. data.vehicle:upper() .. ' - $' .. data.price,
        submitText = Lang:t('menus.submit_text'),
        inputs = {
            {
                type = 'number',
                isRequired = true,
                name = 'downPayment',
                text = Lang:t('menus.financesubmit_downpayment') .. Config.MinimumDown .. '%'
            },
            {
                type = 'number',
                isRequired = true,
                name = 'paymentAmount',
                text = Lang:t('menus.financesubmit_totalpayment') .. Config.MaximumPayments
            },
            {
                text = Lang:t('menus.submit_ID'),
                name = 'playerid',
                type = 'number',
                isRequired = true
            }
        }
    })
    if dialog then
        if not dialog.downPayment or not dialog.paymentAmount or not dialog.playerid then return end
        TriggerServerEvent('qb-vehicleshop:server:sellfinanceVehicle', dialog.downPayment, dialog.paymentAmount, data.vehicle, dialog.playerid)
    end
end)

RegisterNetEvent('qb-vehicleshop:client:swapVehicle', function(data)
    local shopName = data.ClosestShop
    if not shopName or not Config.Shops[shopName] then
        print("Error: Invalid shop name or shop not found")
        return
    end
    
    if not data.ClosestVehicle or not Config.Shops[shopName]['ShowroomVehicles'][data.ClosestVehicle] then
        print("Error: Invalid vehicle index")
        return
    end
    
    if Config.Shops[shopName]['ShowroomVehicles'][data.ClosestVehicle].chosenVehicle ~= data.toVehicle then
        clearShowroomSlot(shopName, data.ClosestVehicle)
        Config.Shops[shopName]['ShowroomVehicles'][data.ClosestVehicle].chosenVehicle = data.toVehicle
        local model = GetHashKey(data.toVehicle)
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(50)
        end
        local veh = CreateVehicle(model, Config.Shops[shopName]['ShowroomVehicles'][data.ClosestVehicle].coords.x, Config.Shops[shopName]['ShowroomVehicles'][data.ClosestVehicle].coords.y, Config.Shops[shopName]['ShowroomVehicles'][data.ClosestVehicle].coords.z, false, false)
        while not DoesEntityExist(veh) do
            Wait(50)
        end
        SetModelAsNoLongerNeeded(model)
        SetVehicleOnGroundProperly(veh)
        SetEntityInvincible(veh, true)
        SetEntityHeading(veh, Config.Shops[shopName]['ShowroomVehicles'][data.ClosestVehicle].coords.w)
        SetVehicleDoorsLocked(veh, 3)
        FreezeEntityPosition(veh, true)
        SetEntityAsMissionEntity(veh, true, true)  -- Protect from deletion
        SetVehicleHasBeenOwnedByPlayer(veh, false)
        SetVehicleNumberPlateText(veh, 'BUY ME')
        registerShowroomVehicle(shopName, data.ClosestVehicle, veh)
        if Config.UsingTarget then createVehZones(shopName, veh) end
    end
end)

RegisterNetEvent('qb-vehicleshop:client:buyShowroomVehicle', function(vehicle, plate, shopName)
    local resolvedShop = ResolveShopForPurchase(shopName)
    if not resolvedShop then
        QBCore.Functions.Notify('Could not determine dealership spawn point for your purchased vehicle.', 'error')
        return
    end

    tempShop = resolvedShop
    QBCore.Functions.TriggerCallback('qb-vehicleshop:server:spawnvehicle', function(netId, properties, vehPlate)
        local timeout = 5000
        local startTime = GetGameTimer()
        while not NetworkDoesNetworkIdExist(netId) do
            Wait(10)
            if GetGameTimer() - startTime > timeout then
                QBCore.Functions.Notify(Lang:t('error.vehnotfound'), 'error')
                return
            end
        end
        local veh = NetworkGetEntityFromNetworkId(netId)
        startTime = GetGameTimer()
        while not DoesEntityExist(veh) do
            Wait(10)
            veh = NetworkGetEntityFromNetworkId(netId)
            if GetGameTimer() - startTime > timeout then
                QBCore.Functions.Notify(Lang:t('error.vehnotfound'), 'error')
                return
            end
        end
        NetworkRequestControlOfEntity(veh)
        startTime = GetGameTimer()
        while not NetworkHasControlOfEntity(veh) do
            Wait(10)
            if GetGameTimer() - startTime > timeout then break end
        end
        SetEntityAsMissionEntity(veh, true, true)
        Citizen.Await(CheckPlate(veh, vehPlate))
        QBCore.Functions.SetVehicleProperties(veh, properties)
        exports['LegacyFuel']:SetFuel(veh, 100)
        TriggerEvent('vehiclekeys:client:SetOwner', vehPlate)
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        SetVehicleEngineOn(veh, true, true, false)
    end, plate, vehicle, Config.Shops[resolvedShop]['VehicleSpawn'], true)
end)

RegisterNetEvent('qb-vehicleshop:client:getVehicles', function()
    QBCore.Functions.TriggerCallback('qb-vehicleshop:server:getVehicles', function(vehicles)
        local ownedVehicles = {}
        for _, v in pairs(vehicles) do
            local vehData = QBCore.Shared.Vehicles[v.vehicle]
            if v.balance ~= 0 and vehData.shop == insideShop then
                local plate = v.plate:upper()
                ownedVehicles[#ownedVehicles + 1] = {
                    header = vehData.name,
                    txt = Lang:t('menus.veh_platetxt') .. plate,
                    icon = 'fa-solid fa-car-side',
                    params = {
                        event = 'qb-vehicleshop:client:getVehicleFinance',
                        args = {
                            vehiclePlate = plate,
                            balance = v.balance,
                            paymentsLeft = v.paymentsleft,
                            paymentAmount = v.paymentamount
                        }
                    }
                }
            end
        end
        if #ownedVehicles > 0 then
            exports['qb-menu']:openMenu(ownedVehicles)
        else
            QBCore.Functions.Notify(Lang:t('error.nofinanced'), 'error', 7500)
        end
    end)
end)

RegisterNetEvent('qb-vehicleshop:client:getVehicleFinance', function(data)
    local vehFinance = {
        {
            header = Lang:t('menus.goback_header'),
            params = {
                event = 'qb-vehicleshop:client:getVehicles'
            }
        },
        {
            isMenuHeader = true,
            icon = 'fa-solid fa-sack-dollar',
            header = Lang:t('menus.veh_finance_balance'),
            txt = Lang:t('menus.veh_finance_currency') .. comma_value(data.balance)
        },
        {
            isMenuHeader = true,
            icon = 'fa-solid fa-hashtag',
            header = Lang:t('menus.veh_finance_total'),
            txt = data.paymentsLeft
        },
        {
            isMenuHeader = true,
            icon = 'fa-solid fa-sack-dollar',
            header = Lang:t('menus.veh_finance_reccuring'),
            txt = Lang:t('menus.veh_finance_currency') .. comma_value(data.paymentAmount)
        },
        {
            header = Lang:t('menus.veh_finance_pay'),
            icon = 'fa-solid fa-hand-holding-dollar',
            params = {
                event = 'qb-vehicleshop:client:financePayment',
                args = {
                    vehData = data,
                    paymentsLeft = data.paymentsleft,
                    paymentAmount = data.paymentamount
                }
            }
        },
        {
            header = Lang:t('menus.veh_finance_payoff'),
            icon = 'fa-solid fa-hand-holding-dollar',
            params = {
                isServer = true,
                event = 'qb-vehicleshop:server:financePaymentFull',
                args = {
                    vehBalance = data.balance,
                    vehPlate = data.vehiclePlate
                }
            }
        },
    }
    exports['qb-menu']:openMenu(vehFinance)
end)

RegisterNetEvent('qb-vehicleshop:client:financePayment', function(data)
    local dialog = exports['qb-input']:ShowInput({
        header = Lang:t('menus.veh_finance'),
        submitText = Lang:t('menus.veh_finance_pay'),
        inputs = {
            {
                type = 'number',
                isRequired = true,
                name = 'paymentAmount',
                text = Lang:t('menus.veh_finance_payment')
            }
        }
    })
    if dialog then
        if not dialog.paymentAmount then return end
        TriggerServerEvent('qb-vehicleshop:server:financePayment', dialog.paymentAmount, data.vehData)
    end
end)

RegisterNetEvent('qb-vehicleshop:client:openIdMenu', function(data)
    local dialog = exports['qb-input']:ShowInput({
        header = QBCore.Shared.Vehicles[data.vehicle]['name'],
        submitText = Lang:t('menus.submit_text'),
        inputs = {
            {
                text = Lang:t('menus.submit_ID'),
                name = 'playerid',
                type = 'number',
                isRequired = true
            }
        }
    })
    if dialog then
        if not dialog.playerid then return end
        if data.type == 'testDrive' then
            TriggerServerEvent('qb-vehicleshop:server:customTestDrive', data.vehicle, dialog.playerid)
        elseif data.type == 'sellVehicle' then
            TriggerServerEvent('qb-vehicleshop:server:sellShowroomVehicle', data.vehicle, dialog.playerid)
        end
    end
end)

-- Threads
CreateThread(function()
    for k, v in pairs(Config.Shops) do
        if v.showBlip then
            local Dealer = AddBlipForCoord(Config.Shops[k]['Location'])
            SetBlipSprite(Dealer, Config.Shops[k]['blipSprite'])
            SetBlipDisplay(Dealer, 4)
            SetBlipScale(Dealer, 0.70)
            SetBlipAsShortRange(Dealer, true)
            SetBlipColour(Dealer, Config.Shops[k]['blipColor'])
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(Config.Shops[k]['ShopLabel'])
            EndTextCommandSetBlipName(Dealer)
        end
    end
end)

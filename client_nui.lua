-- NUI Control Functions
local nuiOpen = false
local currentCategoryContext = {}  -- Track category/make context for vehicle selection

-- Open NUI with vehicle data
function OpenVehicleNUI(vehicleData)
    if nuiOpen then return end
    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'setVisible',
        visible = true
    })
    SendNUIMessage({
        action = 'openVehicleMenu',
        vehicle = vehicleData,
        config = {
            minimumDown = Config.MinimumDown,
            maximumPayments = Config.MaximumPayments
        }
    })
end

-- Open category selection
function OpenCategoryNUI(categories)
    if nuiOpen then return end
    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'setVisible',
        visible = true
    })
    SendNUIMessage({
        action = 'openCategoryMenu',
        categories = categories
    })
end

-- Open vehicle list
function OpenVehicleListNUI(vehicles, categoryContext)
    if nuiOpen then return end
    nuiOpen = true
    -- Store category context for vehicle selection
    if categoryContext then
        currentCategoryContext = categoryContext
    end
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'setVisible',
        visible = true
    })
    SendNUIMessage({
        action = 'openVehicleList',
        vehicles = vehicles
    })
end

-- Open finance menu
function OpenFinanceNUI(vehicleData)
    if nuiOpen then return end
    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'setVisible',
        visible = true
    })
    SendNUIMessage({
        action = 'openFinanceMenu',
        vehicle = vehicleData,
        config = {
            minimumDown = Config.MinimumDown,
            maximumPayments = Config.MaximumPayments
        }
    })
end

-- Start test drive overlay
function StartTestDriveNUI()
    SendNUIMessage({
        action = 'startTestDrive'
    })
end

-- Update test drive time
function UpdateTestDriveTime(timeStr)
    SendNUIMessage({
        action = 'updateTestDriveTime',
        time = timeStr
    })
end

-- End test drive
function EndTestDriveNUI()
    SendNUIMessage({
        action = 'endTestDrive'
    })
end

-- Close NUI
function CloseNUI(keepLock)
    if not nuiOpen then return end
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'setVisible',
        visible = false
    })
    if not keepLock and ReleaseShopMenuLock then
        ReleaseShopMenuLock()
    end
end

-- NUI Callbacks
RegisterNUICallback('closeUI', function(data, cb)
    CloseNUI(false)
    cb('ok')
end)

RegisterNUICallback('testDrive', function(data, cb)
    CloseNUI(false)
    TriggerEvent('qb-vehicleshop:client:TestDrive')
    cb('ok')
end)

RegisterNUICallback('buyVehicle', function(data, cb)
    CloseNUI(false)
    if data.vehicle then
        TriggerServerEvent('qb-vehicleshop:server:buyShowroomVehicle', {
            buyVehicle = data.vehicle.model,
            shopName = insideShop
        })
    end
    cb('ok')
end)

RegisterNUICallback('financeVehicle', function(data, cb)
    CloseNUI(false)
    if data.vehicle then
        TriggerServerEvent('qb-vehicleshop:server:financeVehicle', data.downPayment, data.paymentAmount, data.vehicle.model, insideShop)
    end
    cb('ok')
end)

RegisterNUICallback('swapVehicle', function(data, cb)
    CloseNUI(true)
    if Config.FilterByMake then
        TriggerEvent('qb-vehicleshop:client:vehMakes')
    else
        TriggerEvent('qb-vehicleshop:client:vehCategories')
    end
    cb('ok')
end)

RegisterNUICallback('selectCategory', function(data, cb)
    CloseNUI(true)
    if data.category then
        -- Check if it's a make or category based on type
        -- Makes will have a 'type' property set to 'make'
        if data.category.type == 'make' then
            -- This is a make/brand
            TriggerEvent('qb-vehicleshop:client:vehCategories', { make = data.category.id })
        else
            -- This is a category
            TriggerEvent('qb-vehicleshop:client:openVehCats', { catName = data.category.id })
        end
    end
    cb('ok')
end)

RegisterNUICallback('selectVehicle', function(data, cb)
    CloseNUI(true)
    if data.vehicle then
        TriggerServerEvent('qb-vehicleshop:server:swapVehicle', {
            toVehicle = data.vehicle.model,
            ClosestVehicle = ClosestVehicle,
            ClosestShop = insideShop,
            catName = currentCategoryContext.catName,
            make = currentCategoryContext.make,
            onecat = currentCategoryContext.onecat
        })
    end
    cb('ok')
end)

RegisterNUICallback('returnTestDrive', function(data, cb)
    TriggerEvent('qb-vehicleshop:client:TestDriveReturn')
    cb('ok')
end)

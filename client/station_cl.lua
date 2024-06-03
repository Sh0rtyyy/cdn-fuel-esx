if Config.PlayerOwnedGasStationsEnabled then -- This is so Player Owned Gas Stations are a Config Option, instead of forced. Set this option in shared/config.lua!
    -- Variables
    ESX = exports["es_extended"]:getSharedObject()
    local PedsSpawned = false

    -- These are for fuel pickup:
    local CreatedEventHandler = false
    local locationSwapHandler
    local spawnedTankerTrailer
    local spawnedDeliveryTruck
    local ReservePickupData = {}

    -- Functions
    local function RequestAndLoadModel(model)
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(5)
        end
    end

    --[[local function UpdateStationInfo(info)
        if Config.FuelDebug then print("Fetching Information for Location #" ..CurrentLocation) end
        local result = lib.callback.await('cdn-fuel:server:fetchinfo', CurrentLocation)
        if result then
            for _, v in pairs(result) do
                -- Reserves --
                if info == "all" or info == "reserves" then
                    if Config.FuelDebug then print("Fetched Reserve Levels: "..v.fuel.." Liters!") end
                    Currentreserveamount = v.fuel
                    ReserveLevels = Currentreserveamount
                    if Currentreserveamount < Config.MaxFuelReserves then
                        ReservesNotBuyable = false
                    else
                        ReservesNotBuyable = true
                    end
                    if Config.UnlimitedFuel then ReservesNotBuyable = true if Config.FuelDebug then print("Reserves are not buyable, because Config.UnlimitedFuel is set to true.") end end
                end
                -- Fuel Price --
                if info == "all" or info == "fuelprice" then
                    StationFuelPrice = v.fuelprice
                end
                -- Fuel Station's Balance --
                if info == "all" or info == "balance" then
                    StationBalance = v.balance
                    if Config.FuelDebug then print("Successfully Fetched: Balance") end
                end
                ----------------
            end
        end
    end exports(UpdateStationInfo, UpdateStationInfo)]]

    RegisterNetEvent('cdn-fuel:client:receiveinfo', function(result, info)
        UpdateStationInfoCallback(result, info)
    end)
    
    function UpdateStationInfo(info)
        if not Config.PlayerOwnedGasStationsEnabled then ReserveLevels = 1000 StationFuelPrice = Config.CostMultiplier return end
        if Config.FuelDebug then print("Fetching Information for Location #" ..CurrentLocation) end
        --local result = lib.callback('cdn-fuel:server:fetchinfo', false, CurrentLocation)
        TriggerServerEvent('cdn-fuel:server:fetchinfo2', CurrentLocation, info)
    end exports(UpdateStationInfo, UpdateStationInfo)
    
    function UpdateStationInfoCallback(result, info)
        if result then
            for _, v in pairs(result) do
                -- Reserves --
                if info == "all" or info == "reserves" then
                    if Config.FuelDebug then print("Fetched Reserve Levels: "..v.fuel.." Liters!") end
                    Currentreserveamount = v.fuel
                    ReserveLevels = Currentreserveamount
                    if Currentreserveamount < Config.MaxFuelReserves then
                        ReservesNotBuyable = false
                    else
                        ReservesNotBuyable = true
                    end
                    if Config.UnlimitedFuel then ReservesNotBuyable = true if Config.FuelDebug then print("Reserves are not buyable, because Config.UnlimitedFuel is set to true.") end end
                end
                -- Fuel Price --
                if info == "all" or info == "fuelprice" then
                    StationFuelPrice = v.fuelprice
                end
                -- Fuel Station's Balance --
                if info == "all" or info == "balance" then
                    StationBalance = v.balance
                    if Config.FuelDebug then print("Successfully Fetched: Balance") end
                end
                ----------------
            end
        end
    end

    local function SpawnGasStationPeds()
        if not Config.GasStations or not next(Config.GasStations) or PedsSpawned then return end
        for i = 1, #Config.GasStations do
            local current = Config.GasStations[i]
            current.pedmodel = type(current.pedmodel) == 'string' and joaat(current.pedmodel) or current.pedmodel
            RequestAndLoadModel(current.pedmodel)
            local ped = CreatePed(0, current.pedmodel, current.pedcoords.x, current.pedcoords.y, current.pedcoords.z, current.pedcoords.h, false, false)
            FreezeEntityPosition(ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            exports['qb-target']:AddTargetEntity(ped, {
                options = {
                    {
                        type = "client",
                        label = locale('station_talk_to_ped'),
                        icon = "fas fa-building",
                        action = function()
                            TriggerEvent('cdn-fuel:stations:openmenu', CurrentLocation)
                        end,
                    },
                },
                distance = 2.0
            })
        end
        PedsSpawned = true
    end

    local function GenerateRandomTruckModel()
        local possibleTrucks = Config.PossibleDeliveryTrucks
        if possibleTrucks then
            return possibleTrucks[math.random(#possibleTrucks)]
        end
    end

    local function SpawnPickupVehicles()
        local trailer = GetHashKey('tanker')
        local truckToSpawn = GetHashKey(GenerateRandomTruckModel())
        if truckToSpawn then
            RequestAndLoadModel(truckToSpawn)
            RequestAndLoadModel(trailer)
            spawnedDeliveryTruck = CreateVehicle(truckToSpawn, Config.DeliveryTruckSpawns['truck'], true, false)
            spawnedTankerTrailer = CreateVehicle(trailer, Config.DeliveryTruckSpawns['trailer'], true, false)
            SetModelAsNoLongerNeeded(truckToSpawn) -- removes model from game memory as we no longer need it
            SetModelAsNoLongerNeeded(trailer) -- removes model from game memory as we no longer need it
            SetEntityAsMissionEntity(spawnedDeliveryTruck, 1, 1)
            SetEntityAsMissionEntity(spawnedTankerTrailer, 1, 1)
            AttachVehicleToTrailer(spawnedDeliveryTruck, spawnedTankerTrailer, 15.0)
            -- Now our vehicle is spawned.
            if spawnedDeliveryTruck ~= 0 and spawnedTankerTrailer ~= 0 then
                return true
            else
                return false
            end
        end
    end

    -- Events
    RegisterNetEvent('cdn-fuel:stations:updatelocation', function(updatedlocation)
        if Config.FuelDebug then if CurrentLocation == nil then CurrentLocation = 0 end
            if updatedlocation == nil then updatedlocation = 0 end
            print('Location: '..CurrentLocation..' has been replaced with a new location: ' ..updatedlocation)
        end
        CurrentLocation = updatedlocation or 0
    end)

    RegisterNetEvent('cdn-fuel:stations:client:buyreserves', function(data)
        local location = data.location
        local price = data.price
        local amount = data.amount
        TriggerServerEvent('cdn-fuel:stations:server:buyreserves', location, price, amount)
        print("CUR location" .. location)
        if Config.FuelDebug then print("^5Attempting Purchase of ^2"..amount.. "^5 Fuel Reserves for location #"..location.."! Purchase Price: ^2"..price) end
    end)

    RegisterNetEvent('cdn-fuel:station:client:initiatefuelpickup', function(amountBought, finalReserveAmountAfterPurchase, location)
        if amountBought and finalReserveAmountAfterPurchase and location then
            ReservePickupData = nil
            ReservePickupData = {
                finalAmount = finalReserveAmountAfterPurchase,
                amountBought = amountBought,
                location = location,
            }

            if SpawnPickupVehicles() then
                Notify("success", locale('fuelstation'), locale('fuel_order_ready'), "fas fa-search", 3000)
                SetNewWaypoint(Config.DeliveryTruckSpawns['truck'].x, Config.DeliveryTruckSpawns['truck'].y)
                SetUseWaypointAsDestination(true)
                ReservePickupData.blip = CreateBlip(vector3(Config.DeliveryTruckSpawns['truck'].x, Config.DeliveryTruckSpawns['truck'].y, Config.DeliveryTruckSpawns['truck'].z), "Truck Pickup")
                SetBlipColour(ReservePickupData.blip, 5)

                -- Create Zone
                ReservePickupData.PolyZone = PolyZone:Create(Config.DeliveryTruckSpawns.PolyZone.coords, {
                    name = "cdn_fuel_zone_delivery_truck_pickup",
                    minZ = Config.DeliveryTruckSpawns.PolyZone.minz,
                    maxZ = Config.DeliveryTruckSpawns.PolyZone.maxz,
                    debugPoly = Config.PolyDebug
                })

                -- Setup onPlayerInOut Events for zone that is created.
                ReservePickupData.PolyZone:onPlayerInOut(function(isPointInside)
                    if isPointInside then
                        if Config.FuelDebug then
                            print("Player has arrived at the pickup location!")
                        end
                        RemoveBlip(ReservePickupData.blip)
                        ReservePickupData.blip = nil
                        CreateThread(function()
                            local ped = PlayerPedId()
                            local alreadyHasTruck = false
                            local hasArrivedAtLocation = false
                            local VehicleDelivered = false
                            local EndAwaitListener = false
                            local stopNotifyTemp = false
                            local AwaitingInput = false
                            while true do
                                Wait(100)
                                if VehicleDelivered then break end
                                if IsPedInAnyVehicle(ped, false) then
                                    if GetVehiclePedIsIn(ped, false) == spawnedDeliveryTruck then
                                        if Config.FuelDebug then
                                            print("Player is inside of the delivery truck!")
                                        end

                                        if not alreadyHasTruck then
                                            local loc = {}
                                            loc.x, loc.y = Config.GasStations[ReservePickupData.location].pedcoords.x, Config.GasStations[ReservePickupData.location].pedcoords.y
                                            SetNewWaypoint(loc.x, loc.y)
                                            SetUseWaypointAsDestination(true)
                                            alreadyHasTruck = true
                                        else
                                            if not CreatedEventHandler then
                                                local function AwaitInput()
                                                    if AwaitingInput then return end
                                                    AwaitingInput = true
                                                    if Config.FuelDebug then print("Executing function `AwaitInput()`") end
                                                    CreateThread(function()
                                                        while true do
                                                            Wait(0)
                                                            if EndAwaitListener or not hasArrivedAtLocation then
                                                                AwaitingInput = false
                                                                break
                                                            end
                                                            if IsControlJustReleased(2, 38) then
                                                                local distBetweenTruckAndTrailer = #(GetEntityCoords(spawnedDeliveryTruck) - GetEntityCoords(spawnedTankerTrailer))
                                                                if distBetweenTruckAndTrailer > 10.0 then
                                                                    distBetweenTruckAndTrailer = nil
                                                                    if not stopNotifyTemp then
                                                                        Notify("error", locale('fuelstation'), locale('trailer_too_far'), "fas fa-search", 7500)
                                                                    end
                                                                    stopNotifyTemp = true
                                                                    Wait(1000)
                                                                    stopNotifyTemp = false
                                                                else
                                                                    EndAwaitListener = true
                                                                    local ped = PlayerPedId()
                                                                    VehicleDelivered = true
                                                                    -- Handle Vehicle Dropoff
                                                                    -- Remove PolyZone --
                                                                    ReservePickupData.PolyZone:destroy()
                                                                    ReservePickupData.PolyZone = nil                                                       
                                                                    -- Get Ped Out of Vehicle if Inside --
                                                                    if IsPedInAnyVehicle(ped, true) and GetVehiclePedIsIn(ped, false) == spawnedDeliveryTruck then
                                                                        TaskLeaveVehicle(
                                                                            ped --[[ Ped ]], 
                                                                            spawnedDeliveryTruck --[[ Vehicle ]], 
                                                                            1 --[[ flags | integer ]]
                                                                        )
                                                                        Wait(5000)
                                                                    end

                                                                    lib.hideTextUI()
                                                                    
                                                                    -- Remove Vehicle --                                            
                                                                    DeleteEntity(spawnedDeliveryTruck)
                                                                    DeleteEntity(spawnedTankerTrailer)
                                                                    -- Send Data to Server to Put Into Station --
                                                                    TriggerServerEvent('cdn-fuel:station:server:fuelpickup:finished', ReservePickupData.location)
                                                                    -- Remove Handler
                                                                    RemoveEventHandler(locationSwapHandler)
                                                                    AwaitingInput = false
                                                                    CreatedEventHandler = false
                                                                    ReservePickupData = nil
                                                                    ReservePickupData = {}
                                                                    -- Break Loop
                                                                    break
                                                                end
                                                            end
                                                        end
                                                    end)
                                                    AwaitingInput = true
                                                end
                                                locationSwapHandler = AddEventHandler('cdn-fuel:stations:updatelocation', function(location)
                                                    if location == nil or location ~= ReservePickupData.location then
                                                        hasArrivedAtLocation = false
                                                        lib.hideTextUI()
                                                        
                                                        -- Break Listener
                                                        EndAwaitListener = true
                                                        Wait(50)
                                                        EndAwaitListener = false
                                                    else
                                                        hasArrivedAtLocation = true
                                                        lib.showTextUI(locale('draw_text_fuel_dropoff'), {
                                                            position = 'left-center'
                                                        })
                                                        
                                                        -- Add Listner for Keypress
                                                        AwaitInput()
                                                    end
                                                end)
                                            end
                                        end
                                    end
                                end
                            end
                        end)
                    else

                    end
                end)
            else
                -- This is just a worst case scenario event, if the vehicles somehow do not spawn.
                TriggerServerEvent('cdn-fuel:station:server:fuelpickup:failed', location)
            end
        else
            if Config.FuelDebug then
                print("An error has occurred. The amountBought / finalReserveAmountAfterPurchase / location is nil: `cdn-fuel:station:client:initiatefuelpickup`")
            end
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:purchaselocation', function(data)
        local location = data.location
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        CanOpen = false
        Wait(5)
        local result = lib.callback.await('cdn-fuel:server:locationpurchased', false, CurrentLocation)
        if result then
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is owned!") end
            IsOwned = true
        else
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is not owned.") end
            IsOwned = false
        end
        Wait(Config.WaitTime)

        if not IsOwned then
            print("not owned")
            TriggerServerEvent('cdn-fuel:server:buyStation', CurrentLocation, CitizenID)
        elseif IsOwned then
            Notify("error", locale('fuelstation'), locale('station_already_owned'), "fas fa-search", 5000)
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:sellstation', function(data)
        local location = data.location
        local SalePrice = data.SalePrice
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        CanSell = false
        Wait(5)
        local result = lib.callback.await('cdn-fuel:server:isowner', false, location)
        if result then
            if Config.FuelDebug then print("The Location: "..location.." is owned by ID: "..CitizenID) end
            CanSell = true
        else
            Notify("error", locale('fuelstation'), locale('station_not_owner'), "fas fa-search", 5000)
            if Config.FuelDebug then print("The Location: "..location.." is not owned by ID: "..CitizenID) end
            CanSell = false
        end

        Wait(Config.WaitTime)
        if CanSell then
            if Config.FuelDebug then print("Attempting to sell for: $"..SalePrice) end
            TriggerServerEvent('cdn-fuel:stations:server:sellstation', location)
            if Config.FuelDebug then print("Event Triggered") end
        else
            Notify("error", locale('fuelstation'), locale('station_cannot_sell'), "fas fa-search", 5000)
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:purchasereserves:final', function(location, price, amount) -- Menu, seens after selecting the "purchase reserves" option.
        local location = location
        local price = price
        local amount = amount
        CanOpen = false
        Wait(5)
        if Config.FuelDebug then print("checking ownership of "..location) end
        local result = lib.callback.await('cdn-fuel:server:isowner', false, location)
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        if result then
            if Config.FuelDebug then print("The Location: "..location.." is owned by ID: "..CitizenID) end
            CanOpen = true
        else
            Notify("error", locale('fuelstation'), locale('station_not_owner'), "fas fa-search", 5000)
            if Config.FuelDebug then print("The Location: "..location.." is not owned by ID: "..CitizenID) end
            CanOpen = false
        end

        Wait(Config.WaitTime)
        if CanOpen then
            if Config.FuelDebug then print("Price: "..price.."<br> Amount: "..amount.." <br> Location: "..location) end
            lib.registerContext({
                id = 'purchasereservesmenu',
                title = locale('menu_station_reserves_header')..Config.GasStations[location].label,
                options = {
                    {
                        title = locale('menu_station_reserves_purchase_header')..price,
                        description = locale('menu_station_reserves_purchase_footer')..price.." !",
                        icon = "fas fa-usd",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:buyreserves',
                        args = {
                            location = location,
                            price = price,
                            amount = amount,
                        }
                    },
                    {
                        title = locale('menu_header_close'),
                        description = locale('menu_ped_close_footer'),
                        icon = "fas fa-times-circle",
                        arrow = false, -- puts arrow to the right
                        onSelect = function()
                            lib.hideContext()
                        end,
                    },
                },
            })
            lib.showContext('purchasereservesmenu')
        else
            if Config.FuelDebug then print("Not showing menu, as the player doesn't have proper permissions.") end
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:purchasereserves', function(data)
        local CanOpen = false
        local location = data.location
        local result = lib.callback.await('cdn-fuel:server:isowner', false, location)
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        if result then
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is owned by ID: "..CitizenID) end
            CanOpen = true
        else
            Notify("error", locale('fuelstation'), locale('station_not_owner'), "fas fa-search", 5000)
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is not owned by ID: "..CitizenID) end
            CanOpen = false
        end

        Wait(Config.WaitTime)
        if CanOpen then
            local bankmoney, moneyY = lib.callback.await('cdn-fuel:getmoney')
            if Config.FuelDebug then print("Showing Input for Reserves!") end
            local reserves = lib.inputDialog('Purchase Reserves', {
                { type = "input", label = 'Current Price',
                default = '$'.. Config.FuelReservesPrice .. ' Per Liter',
                disabled = true },
                { type = "input", label = 'Current Reserves',
                default = Currentreserveamount,
                disabled = true },
                { type = "input", label = 'Required Reserves',
                default = Config.MaxFuelReserves - Currentreserveamount,
                disabled = true },
                { type = "slider", label = 'Full Reserve Cost: $' ..math.ceil(GlobalTax((Config.MaxFuelReserves - Currentreserveamount) * Config.FuelReservesPrice) + ((Config.MaxFuelReserves - Currentreserveamount) * Config.FuelReservesPrice)).. '',
                default = Config.MaxFuelReserves - Currentreserveamount,
                min = 0,
                max = Config.MaxFuelReserves - Currentreserveamount
                },
            })
            if not reserves then return end
            reservesAmount = tonumber(reserves[4])
            if reserves then
                if Config.FuelDebug then print("Attempting to buy reserves!") end
                Wait(100)
                local amount = reservesAmount
                if not reservesAmount then Notify("error", locale('fuelstation'), locale('station_amount_invalid'), "fas fa-search", 5000) return end
                Reservebuyamount = tonumber(reservesAmount)
                if Reservebuyamount < 1 then Notify("error", locale('fuelstation'), locale('station_more_than_one'), "fas fa-search", 5000) return end
                if (Reservebuyamount + Currentreserveamount) > Config.MaxFuelReserves then
                    Notify("error", locale('fuelstation'), locale('station_reserve_cannot_fit'), "fas fa-search", 5000)
                else
                    if math.ceil(GlobalTax(Reservebuyamount * Config.FuelReservesPrice) + (Reservebuyamount * Config.FuelReservesPrice)) <= bankmoney then
                        local price = math.ceil(GlobalTax(Reservebuyamount * Config.FuelReservesPrice) + (Reservebuyamount * Config.FuelReservesPrice))
                        if Config.FuelDebug then print("Price: "..price) end
                        TriggerEvent("cdn-fuel:stations:client:purchasereserves:final", location, price, amount)

                    else
                        Notify("error", locale('fuelstation'), locale('not_enough_money_in_bank'), "fas fa-search", 5000)
                    end
                end
            end
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:changefuelprice', function(data)
        CanOpen = false
        local location = data.location
        local result = lib.callback.await('cdn-fuel:server:isowner', false, location)
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        if result then
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is owned by ID: "..CitizenID) end
            CanOpen = true
        else
            Notify("error", locale('fuelstation'), locale('station_not_owner'), "fas fa-search", 5000)
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is not owned by ID: "..CitizenID) end
            CanOpen = false
        end
        Wait(Config.WaitTime)
        if CanOpen then
            if Config.FuelDebug then print("Showing Input for Fuel Price Change!") end
            local fuelprice = lib.inputDialog('Fuel Prices', {
                { type = "input", label = 'Current Price',
                default = '$'.. Comma_Value(StationFuelPrice) .. ' Per Liter',
                disabled = true },
                { type = "number", label = 'Enter New Fuel Price Per Liter',
                default = StationFuelPrice,
                min = Config.MinimumFuelPrice,
                max = Config.MaxFuelPrice
                },
            })
            if not fuelprice then return end
            fuelPrice = tonumber(fuelprice[2])
            if fuelprice then
                if Config.FuelDebug then print("Attempting to change fuel price!") end
                Wait(100)
                if not fuelPrice then Notify("error", locale('fuelstation'), locale('station_amount_invalid'), "fas fa-search", 5000) return end
                NewFuelPrice = tonumber(fuelPrice)
                if NewFuelPrice < Config.MinimumFuelPrice then Notify("error", locale('fuelstation'), locale('station_price_too_low'), "fas fa-search", 5000) return end
                if NewFuelPrice > Config.MaxFuelPrice then
                    Notify("error", locale('fuelstation'), locale('station_price_too_high'), "fas fa-search", 5000)
                else
                    TriggerServerEvent("cdn-fuel:station:server:updatefuelprice", NewFuelPrice, CurrentLocation)
                end
            end
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:sellstation:menu', function(data) -- Menu, seen after selecting the Sell this Location option.
        local location = data.location
        local result = lib.callback.await('cdn-fuel:server:isowner', false, location)
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        if result then
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is owned by ID: "..CitizenID) end
            CanOpen = true
        else
            Notify("error", locale('fuelstation'), locale('station_not_owner'), "fas fa-search", 5000)
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is not owned by ID: "..CitizenID) end
            CanOpen = false
        end
        Wait(Config.WaitTime)
        if CanOpen then
            local GasStationCost = Config.GasStations[location].cost + GlobalTax(Config.GasStations[location].cost)
            local SalePrice = math.percent(Config.GasStationSellPercentage, GasStationCost)
            lib.registerContext({
                id = 'sellstationmenu',
                title = locale('menu_sell_station_header')..Config.GasStations[location].label,
                options = {
                    {
                        title = locale('menu_sell_station_header_accept'),
                        description = locale('menu_sell_station_footer_accept')..Comma_Value(SalePrice)..".",
                        icon = "fas fa-usd",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:sellstation',
                        args = {
                            location = location,
                            SalePrice = SalePrice,
                        }
                    },
                    {
                        title = locale('menu_header_close'),
                        description = locale('menu_refuel_cancel'),
                        icon = "fas fa-times-circle",
                        arrow = false, -- puts arrow to the right
                        onSelect = function()
                            lib.hideContext()
                            end,
                    },
                },
            })
            lib.showContext('sellstationmenu')
            TriggerServerEvent("cdn-fuel:stations:server:stationsold", location)
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:changestationname', function() -- Menu for changing the label of the owned station.
        CanOpen = false
        local result = lib.callback.await('cdn-fuel:server:isowner', false, CurrentLocation)
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        if result then
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is owned by ID: "..CitizenID) end
            CanOpen = true
        else
            Notify("error", locale('fuelstation'), locale('station_not_owner'), "fas fa-search", 5000)
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is not owned by ID: "..CitizenID) end
            CanOpen = false
        end
        Wait(Config.WaitTime)
        if CanOpen then
            if Config.FuelDebug then print("Showing Input for name Change!") end
            local NewName = lib.inputDialog('Name Changer', {
                { type = "input", label = 'Current Name',
                default = Config.GasStations[CurrentLocation].label,
                disabled = true },
                { type = "input", label = 'Enter New Station Name',
                placeholder = 'New Name'
                },
            })
            if not NewName then return end
            NewNameName = NewName[2]
            if NewName then
                if Config.FuelDebug then print("Attempting to alter stations name!") end
                if not NewNameName then Notify("error", locale('fuelstation'), locale('station_name_invalid'), "fas fa-search", 5000) return end
                NewName = NewNameName
                if type(NewName) ~= "string" then Notify("error", locale('fuelstation'), locale('station_name_invalid'), "fas fa-search", 5000) return end
                if Config.ProfanityList[NewName] then
                    Notify("error", locale('fuelstation'), locale('station_name_invalid'), "fas fa-search", 5000)
                    return
                end
                if string.len(NewName) > Config.NameChangeMaxChar then 
                    Notify("error", locale('fuelstation'), locale('station_name_too_long'), "fas fa-search", 5000)
                    return 
                end
                if string.len(NewName) < Config.NameChangeMinChar then 
                    Notify("error", locale('fuelstation'), locale('station_name_too_short'), "fas fa-search", 5000)
                    return 
                end
                Wait(100)
                TriggerServerEvent("cdn-fuel:station:server:updatelocationname", NewName, CurrentLocation)
            end
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:managemenu', function(location) -- Menu, seen after selecting the Manage this Location Option.
        location = CurrentLocation
        local result = lib.callback.await('cdn-fuel:server:isowner', false, CurrentLocation)
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        if result then
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is owned by ID: "..CitizenID) end
            CanOpen = true
        else
            Notify("error", locale('fuelstation'), locale('station_not_owner'), "fas fa-search", 5000)
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is not owned by ID: "..CitizenID) end
            CanOpen = false
        end
        UpdateStationInfo("all")
        if Config.PlayerControlledFuelPrices then CanNotChangeFuelPrice = false else CanNotChangeFuelPrice = true end
        Wait(5)
        Wait(Config.WaitTime)
        if CanOpen then
            local GasStationCost = (Config.GasStations[location].cost + GlobalTax(Config.GasStations[location].cost))
            lib.registerContext({
                id = 'stationmanagemenu',
                title = locale('menu_manage_header')..Config.GasStations[location].label,
                options = {
                    {
                        title = locale('menu_manage_reserves_header'),
                        description = 'Buy your reserve fuel here!',
                        icon = "fas fa-info-circle",
                        arrow = true, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:purchasereserves',
                        args = {
                            location = location,
                        },
                        metadata = {
                            {label = 'Reserve Stock: ', value = ReserveLevels..locale('menu_manage_reserves_footer_1')..Config.MaxFuelReserves},
                        },
                        disabled = ReservesNotBuyable,
                    },
                    {
                        title = locale('menu_alter_fuel_price_header'),
                        description = "I want to change the price of fuel at my Gas Station!",
                        icon = "fas fa-usd",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:changefuelprice',
                        args = {
                            location = location,
                        },
                        metadata = {
                            {label = 'Current Fuel Price: ', value = "$"..Comma_Value(StationFuelPrice)..locale('input_alter_fuel_price_header_2')},
                        },
                        disabled = CanNotChangeFuelPrice,
                    },
                    {
                        title = locale('menu_manage_company_funds_header'),
                        description = locale('menu_manage_company_funds_footer'),
                        icon = "fas fa-usd",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:managefunds'
                    },
                    {
                        title = locale('menu_manage_change_name_header'),
                        description = locale('menu_manage_change_name_footer'),
                        icon = "fas fa-pen",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:changestationname',
                        disabled = not Config.GasStationNameChanges,
                    },
                    {
                        title = locale('menu_sell_station_header_accept'),
                        description = locale('menu_manage_sell_station_footer')..Comma_Value(math.percent(Config.GasStationSellPercentage, GasStationCost)),
                        icon = "fas fa-usd",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:sellstation:menu',
                        args = {
                            location = location,
                        },
                    },
                    {
                        title = locale('menu_header_close'),
                        description = locale('menu_refuel_cancel'),
                        icon = "fas fa-times-circle",
                        arrow = false, -- puts arrow to the right
                        onSelect = function()
                            lib.hideContext()
                            end,
                    },
                },
            })
            lib.showContext('stationmanagemenu')
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:managefunds', function(location) -- Menu, seen after selecting the Manage this Location Option.
        local result = lib.callback.await('cdn-fuel:server:isowner', false, CurrentLocation)
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        if result then
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is owned by ID: "..CitizenID) end
            CanOpen = true
        else
            Notify("error", locale('fuelstation'), locale('station_not_owner'), "fas fa-search", 5000)
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is not owned by ID: "..CitizenID) end
            CanOpen = false
        end
        UpdateStationInfo("all")
        Wait(5)
        Wait(Config.WaitTime)
        if CanOpen then
            lib.registerContext({
                id = 'managefundsmenu',
                title = locale('menu_manage_company_funds_header_2')..Config.GasStations[CurrentLocation].label,
                options = {
                    {
                        title = locale('menu_manage_company_funds_withdraw_header'),
                        description = locale('menu_manage_company_funds_withdraw_footer'),
                        icon = "fas fa-arrow-left",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:WithdrawFunds',
                        args = {
                            location = location,
                        }
                    },
                    {
                        title = locale('menu_manage_company_funds_deposit_header'),
                        description = locale('menu_manage_company_funds_deposit_footer'),
                        icon = "fas fa-arrow-right",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:DepositFunds',
                        args = {
                            location = location,
                        }
                    },
                    {
                        title = locale('menu_manage_company_funds_return_header'),
                        description = locale('menu_manage_company_funds_return_footer'),
                        icon = "fas fa-circle-left",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:managemenu',
                        args = {
                            location = location,
                        }
                    },
                    {
                        title = locale('menu_header_close'),
                        description = locale('menu_refuel_cancel'),
                        icon = "fas fa-times-circle",
                        arrow = false, -- puts arrow to the right
                        onSelect = function()
                            lib.hideContext()
                        end,
                    },
                },
            })
            lib.showContext('managefundsmenu')
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:WithdrawFunds', function(data)
        if Config.FuelDebug then print("Triggered Event for: Withdraw!") end
        local location = CurrentLocation
        CanOpen = false
        local result = lib.callback.await('cdn-fuel:server:isowner', false, location)
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        if result then
            if Config.FuelDebug then print("The Location: "..location.." is owned by ID: "..CitizenID) end
            CanOpen = true
        else
            Notify("error", locale('fuelstation'), locale('station_not_owner'), "fas fa-search", 5000)
            if Config.FuelDebug then print("The Location: "..location.." is not owned by ID: "..CitizenID) end
            CanOpen = false
        end
        Wait(Config.WaitTime)
        if CanOpen then
            if Config.FuelDebug then print("Showing Input for Withdraw!") end
            UpdateStationInfo("balance")
            Wait(50)
            local Withdraw = lib.inputDialog('Withdraw Funds', {
                { type = "input", label = 'Current Station Balance',
                default = '$'..Comma_Value(StationBalance),
                disabled = true },
                { type = "number", label = 'Withdraw Amount',
                },
            })
            if not Withdraw then return end
            WithdrawAmounts = tonumber(Withdraw[2])
            if Withdraw then
                if Config.FuelDebug then print("Attempting to Withdraw!") end
                Wait(100)
                local amount = tonumber(WithdrawAmounts)
                if not WithdrawAmounts then Notify("error", locale('fuelstation'), locale('station_amount_invalid'), "fas fa-search", 5000) return end
                if amount < 1 then Notify("error", locale('fuelstation'), locale('station_withdraw_too_little'), "fas fa-search", 5000) return end
                if amount > StationBalance then Notify("error", locale('fuelstation'), locale('station_withdraw_too_much'), "fas fa-search", 5000) return end
                WithdrawAmount = tonumber(amount)
                if (StationBalance - WithdrawAmount) < 0 then
                    Notify("error", locale('fuelstation'), locale('station_withdraw_too_much'), "fas fa-search", 5000)
                else
                    TriggerServerEvent('cdn-fuel:station:server:Withdraw', amount, location, StationBalance)
                end
            end
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:DepositFunds', function(data)
        if Config.FuelDebug then print("Triggered Event for: Deposit!") end
        CanOpen = false
        local location = CurrentLocation
        local result = lib.callback.await('cdn-fuel:server:isowner', false, location)
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        if result then
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is owned by ID: "..CitizenID) end
            CanOpen = true
        else
            Notify("error", locale('fuelstation'), locale('station_not_owner'), "fas fa-search", 5000)
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is not owned by ID: "..CitizenID) end
            CanOpen = false
        end
        Wait(Config.WaitTime)
        if CanOpen then
            local bankmoney, moneyY = lib.callback.await('cdn-fuel:getmoney')
            if Config.FuelDebug then print("Showing Input for Deposit!") end
            UpdateStationInfo("balance")
            Wait(50)
            local Deposit = lib.inputDialog('Deposit Funds', {
                { type = "input", label = 'Current Station Balance',
                default = '$'..Comma_Value(StationBalance),
                disabled = true },
                { type = "number", label = 'Deposit Amount',
                },
            })
            if not Deposit then return end
            DepositAmounts = tonumber(Deposit[2])
            if Deposit then
                if Config.FuelDebug then print("Attempting to Deposit!") end
                Wait(100)
                local amount = tonumber(DepositAmounts)
                if not DepositAmounts then Notify("error", locale('fuelstation'), locale('station_amount_invalid'), "fas fa-search", 5000) return end
                if amount < 1 then Notify("error", locale('fuelstation'), locale('station_deposit_too_little'), "fas fa-search", 5000) return end
                DepositAmount = tonumber(amount)
                if (DepositAmount) > bankmoney then
                    Notify("error", locale('fuelstation'), locale('station_deposity_too_much'), "fas fa-search", 5000)
                else
                    TriggerServerEvent('cdn-fuel:station:server:Deposit', amount, location, StationBalance)
                end
            end
        end
    end)

    RegisterNetEvent('cdn-fuel:stations:client:Shutoff', function(location)
        TriggerServerEvent("cdn-fuel:stations:server:Shutoff", location)
    end)

    RegisterNetEvent('cdn-fuel:stations:client:purchasemenu', function(location) -- Menu, seen after selecting the purchase this location option.
        local bankmoney, moneyY = lib.callback.await('cdn-fuel:getmoney')
        local costofstation = Config.GasStations[location].cost + GlobalTax(Config.GasStations[location].cost)

        if Config.OneStationPerPerson == true then
            local result = lib.callback.await('cdn-fuel:server:doesPlayerOwnStation', location)
            if result then
                if Config.FuelDebug then print("Player already owns a station, so disallowing purchase.") end
                PlayerOwnsAStation = true
            else
                if Config.FuelDebug then print("Player doesn't own a station, so continuing purchase checks.") end
                PlayerOwnsAStation = false
            end

            Wait(Config.WaitTime)

            if PlayerOwnsAStation == true then
                Notify("error", locale('fuelstation'), 'You can only buy one station, and you already own one!', "fas fa-search", 5000)
                return
            end
        end


        if bankmoney < costofstation then
            Notify("error", locale('fuelstation'), locale('not_enough_money_in_bank').." $"..costofstation, "fas fa-search", 5000)
            return
        end
        lib.registerContext({
            id = 'purchasemenu',
            title = Config.GasStations[location].label,
            options = {
                {
                    title = locale('menu_purchase_station_confirm_header'),
                    description = 'I am interested in purchasing this station!',
                    icon = "fas fa-usd",
                    arrow = true, -- puts arrow to the right
                    event = 'cdn-fuel:stations:client:purchaselocation',
                    args = {
                        location = location,
                    },
                    metadata = {
                        {label = 'Station Cost: $', value = Comma_Value(costofstation)..locale('menu_purchase_station_header_2')},
                    },
                },
                {
                    title = locale('menu_header_close'),
                    description = locale('menu_refuel_cancel'),
                    icon = "fas fa-times-circle",
                    arrow = false, -- puts arrow to the right
                    onSelect = function()
                        lib.hideContext()
                    end,
                },
            },
        })
        lib.showContext('purchasemenu')
    end)

    RegisterNetEvent('cdn-fuel:stations:openmenu', function() -- Menu #1, the first menu you see.
        DisablePurchase = true
        DisableOwnerMenu = true
        ShutOffDisabled = false

        local result = lib.callback.await('cdn-fuel:server:locationpurchased', false, CurrentLocation)
        if result then
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is owned.") end
            DisablePurchase = true
        else
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is not owned.") end
            DisablePurchase = false
            DisableOwnerMenu = true
        end

        local result = lib.callback.await('cdn-fuel:server:isowner', false, CurrentLocation)
        local CitizenID = lib.callback('cdn-fuel:requestIdentifier')
        if result then
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is owned by ID: "..CitizenID) end
            DisableOwnerMenu = false
        else
            if Config.FuelDebug then print("The Location: "..CurrentLocation.." is not owned by ID: "..CitizenID) end
            DisableOwnerMenu = true
        end

        if Config.EmergencyShutOff then
            local result = lib.callback.await('cdn-fuel:server:checkshutoff', CurrentLocation)
            if result == true then
                PumpState = "disabled."
            elseif result == false then
                PumpState = "enabled."
            else
                PumpState = "nil"
            end
            if Config.FuelDebug then print("The result from Callback: Config.GasStations["..CurrentLocation.."].shutoff = "..PumpState) end
        else
            PumpState = "enabled."
            ShutOffDisabled = true
        end

        Wait(Config.WaitTime)

            lib.registerContext({
                id = 'stationmainmenu',
                title = Config.GasStations[CurrentLocation].label,
                options = {
                    {
                        title = locale('menu_ped_manage_location_header'),
                        description = locale('menu_ped_manage_location_footer'),
                        icon = "fas fa-gas-pump",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:managemenu',
                        args = CurrentLocation,
                        disabled = DisableOwnerMenu,
                    },
                    {
                        title = locale('menu_ped_purchase_location_header'),
                        description = locale('menu_ped_purchase_location_footer'),
                        icon = "fas fa-usd",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:purchasemenu',
                        args = CurrentLocation,
                        disabled = DisablePurchase,
                    },
                    {
                        title = locale('menu_ped_emergency_shutoff_header'),
                        description = locale('menu_ped_emergency_shutoff_footer')..PumpState,
                        icon = "fas fa-gas-pump",
                        arrow = false, -- puts arrow to the right
                        event = 'cdn-fuel:stations:client:Shutoff',
                        args = CurrentLocation,
                        disabled = ShutOffDisabled,
                    },
                    {
                        title = locale('menu_header_close'),
                        description = locale('menu_refuel_cancel'),
                        icon = "fas fa-times-circle",
                        arrow = false, -- puts arrow to the right
                        onSelect = function()
                            lib.hideContext()
                        end,
                    },
                },
            })
            lib.showContext('stationmainmenu')
    end)

    -- Threads
    CreateThread(function() -- Spawn the Peds for Gas Stations when the resource starts.
        SpawnGasStationPeds()
    end)
end -- For Config.PlayerOwnedGasStationsEnabled check, don't remove!
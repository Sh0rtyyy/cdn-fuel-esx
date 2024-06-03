lib.locale()

if Config.ElectricVehicleCharging then
    -- Variables   
    ESX = exports["es_extended"]:getSharedObject()
    local HoldingElectricNozzle = false
    local RefuelPossible = false
    local RefuelPossibleAmount = 0 
    local RefuelCancelled = false
    local RefuelPurchaseType = 'bank'

    if Config.PumpHose then
        Rope = nil
    end

    -- Start
    AddEventHandler('onResourceStart', function(resource)
        if resource == GetCurrentResourceName() then
            Wait(100)
            DeleteObject(ElectricNozzle)
            HoldingElectricNozzle = false
        end
    end)

    -- Functions
    function IsHoldingElectricNozzle()
        return HoldingElectricNozzle
    end exports('IsHoldingElectricNozzle', IsHoldingElectricNozzle)

    function SetElectricNozzle(state)
        if state == "putback" then
            TriggerServerEvent("InteractSound_SV:PlayOnSource", "putbackcharger", 0.4)
            Wait(250)
            if Config.FuelTargetExport then exports[Config.TargetResource]:AllowRefuel(false, true) end
            DeleteObject(ElectricNozzle)
            HoldingElectricNozzle = false
            if Config.PumpHose == true then
                RopeUnloadTextures()
                DeleteRope(Rope)
            end
        elseif state == "pickup" then    
            TriggerEvent('cdn-fuel:client:grabelectricnozzle')
            HoldingElectricNozzle = true
        else
            if Config.FuelDebug then print("State is not valid, it must be pickup or putback.") end
        end
    end exports('SetElectricNozzle', SetElectricNozzle)

    -- Events
    RegisterNetEvent('cdn-electric:client:OpenContextMenu', function(total, fuelamounttotal, purchasetype)
        lib.registerContext({
            id = 'electricconfirmationmenu',
            title = locale('menu_purchase_station_header_1')..math.ceil(total)..locale('menu_purchase_station_header_2'),
            options = {
                {
                    title = locale('menu_purchase_station_confirm_header'),
                    description = locale('menu_electric_accept'),
                    icon = "fas fa-check-circle",
                    arrow = false, -- puts arrow to the right
                    event = 'cdn-fuel:client:electric:ChargeVehicle',
                    args = {
                        fuelamounttotal = fuelamounttotal,
                        purchasetype = purchasetype,
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
        lib.showContext('electricconfirmationmenu')
    end)
    

    RegisterNetEvent('cdn-fuel:client:electric:FinalMenu', function(purchasetype)
        local money = nil
        local bank, moneyY = lib.callback.await('cdn-fuel:getmoney')
        if purchasetype == "bank" then money = bank elseif purchasetype == 'cash' then money = moneyY end
        FuelPrice = (1 * Config.ElectricChargingPrice)
        local vehicle = GetClosestVehicle()

        -- Police Discount Math --
        if Config.EmergencyServicesDiscount['enabled'] == true and (Config.EmergencyServicesDiscount['emergency_vehicles_only'] == false or (Config.EmergencyServicesDiscount['emergency_vehicles_only'] == true and GetVehicleClass(vehicle) == 18)) then
            local discountedJobs = Config.EmergencyServicesDiscount['job']
            local plyJob = ESX.PlayerData.job.name
            local shouldRecieveDiscount = false

            if type(discountedJobs) == "table" then
                for i = 1, #discountedJobs, 1 do
                    if plyJob == discountedJobs[i] then
                        shouldRecieveDiscount = true
                        break
                    end
                end
            elseif plyJob == discountedJobs then
                shouldRecieveDiscount = true
            end

            if shouldRecieveDiscount == true and Config.EmergencyServicesDiscount['ondutyonly'] then
                Notify("success", locale('fuelstation'), locale('you_are_discount_eligible'), "fas fa-search", 3000)
				shouldRecieveDiscount = false
			end

            if shouldRecieveDiscount then
                local discount = Config.EmergencyServicesDiscount['discount']
                if discount > 100 then
                    discount = 100
                else
                    if discount <= 0 then discount = 0 end
                end
                if discount ~= 0 then
                    if discount == 100 then
                        FuelPrice = 0
                        if Config.FuelDebug then
                            print("Your discount for Emergency Services is set @ "..discount.."% so fuel is free!")
                        end
                    else
                        discount = discount / 100
                        FuelPrice = FuelPrice - (FuelPrice*discount)

                        if Config.FuelDebug then
                            print("Your discount for Emergency Services is set @ "..discount.."%. Setting new price to: $"..FuelPrice)
                        end
                    end
                else
                    if Config.FuelDebug then
                        print("Your discount for Emergency Services is set @ "..discount.."%. It cannot be 0 or < 0!")
                    end
                end
            end
        end

        local curfuel = GetFuel(vehicle)
        local finalfuel
        if curfuel < 10 then finalfuel = string.sub(curfuel, 1, 1) else finalfuel = string.sub(curfuel, 1, 2) end
        local maxfuel = (100 - finalfuel - 1)
        local wholetankcost = (FuelPrice * maxfuel)
        local wholetankcostwithtax = math.ceil((wholetankcost) + GlobalTax(wholetankcost))
        if Config.FuelDebug then print("Attempting to open Input with the total: $"..wholetankcostwithtax.." at $"..FuelPrice.." / L".." Maximum Fuel Amount: "..maxfuel) end
        Electricity = lib.inputDialog('Electric Charger', {
            { type = "input", label = 'Electric Price',
            default = '$'.. FuelPrice .. '/KWh',
            disabled = true },
            { type = "input", label = 'Current Charge',
            default = finalfuel .. ' KWh',
            disabled = true },
            { type = "input", label = 'Required Full Charge',
            default = maxfuel,
            disabled = true },
            { type = "slider", label = 'Full Charge Cost: $' ..wholetankcostwithtax.. '',
            default = maxfuel,
            min = 0,
            max = maxfuel
            },
        })

        if not Electricity then return end
        ElectricityAmount = tonumber(Electricity[4])

        if Electricity then
            if not ElectricityAmount then print('ElectricityAmount is invalid!') return end
            if not HoldingElectricNozzle then 
                Notify("error", locale('fuelstation'), locale('electric_no_nozzle'), "fas fa-search", 3000)
                return 
            end
            if (ElectricityAmount + finalfuel) >= 100 then
                Notify("error", locale('fuelstation'), locale('tank_already_full'), "fas fa-search", 3000)
            else
                if GlobalTax(ElectricityAmount * FuelPrice) + (ElectricityAmount * FuelPrice) <= money then
                    TriggerServerEvent('cdn-fuel:server:electric:OpenMenu', ElectricityAmount, IsInGasStation(), false, purchasetype, FuelPrice)
                else
                    Notify("error", locale('fuelstation'), locale('not_enough_money'), "fas fa-search", 3000)
                end
            end 
        end
    end)

    RegisterNetEvent('cdn-fuel:client:electric:SendMenuToServer', function()
        local vehicle = GetClosestVehicle()
        local vehModel = GetEntityModel(vehicle)
        local vehiclename = string.lower(GetDisplayNameFromVehicleModel(vehModel))
        AwaitingElectricCheck = true
        FoundElectricVehicle = false
        :: ChargingMenu :: -- Register the starting point for the goto
        if not AwaitingElectricCheck then if Config.FuelDebug then print("Attempting to go to Charging Menu") end end
        if not AwaitingElectricCheck and FoundElectricVehicle then
            local CurFuel = GetVehicleFuelLevel(vehicle)
            local bank, moneyY = lib.callback.await('cdn-fuel:getmoney')
            local playercashamount = moneyY
            if not IsHoldingElectricNozzle() then
                Notify("error", locale('fuelstation'), locale('electric_no_nozzle'), "fas fa-search", 3000)
                return 
            end
            if CurFuel < 95 then
                lib.registerContext({
                    id = 'electricmenu',
                    title = Config.GasStations[FetchCurrentLocation()].label,
                    options = {
                        {
                            title = locale('menu_header_cash'),
                            description = locale('menu_pay_with_cash') .. playercashamount,
                            icon = "fas fa-usd",
                            arrow = false, -- puts arrow to the right
                            event = "cdn-fuel:client:electric:FinalMenu",
                            args = 'cash',
                        },
                        {
                            title = locale('menu_header_bank'),
                            description = locale('menu_pay_with_bank'),
                            icon = "fas fa-credit-card",
                            arrow = false, -- puts arrow to the right
                            event = "cdn-fuel:client:electric:FinalMenu",
                            args = 'bank',
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
                lib.showContext('electricmenu')
            else
                Notify("error", locale('fuelstation'), locale('tank_already_full'), "fas fa-search", 3000)
            end
        else
            if Config.FuelDebug then print("Checking") end
            if AwaitingElectricCheck then
                if Config.ElectricVehicles[vehiclename] and Config.ElectricVehicles[vehiclename].isElectric then
                    AwaitingElectricCheck = false
                    FoundElectricVehicle = true
                    if Config.FuelDebug then print("^2 has been found. It ^2matches ^5the Player's Vehicle: ^2"..vehiclename..". ^5This means charging will be allowed.") end
                    Wait(50)
                    goto ChargingMenu -- Attempt to go to the charging menu, now that we have found that there was an electric vehicle.
                else
                    FoundElectricVehicle = false
                    AwaitingElectricCheck = false
                    Wait(50)
                    if Config.FuelDebug then print("^2An electric vehicle^5 has NOT been found. ^5This means charging will not be allowed.") end
                    goto ChargingMenu -- Attempt to go to the charging menu, now that we have not found that there was an electric vehicle.
                end

                -- for i = 1, #Config.ElectricVehicles do
                --     if AwaitingElectricCheck then
                --         if Config.FuelDebug then print(i) end
                --         local current = joaat(Config.ElectricVehicles[i])
                --         if Config.FuelDebug then print("^5Current Search: ^2"..current.." ^5Player's Vehicle: ^2"..vehiclename) end
                --         if current == vehiclename then
                --             AwaitingElectricCheck = false
                --             FoundElectricVehicle = true
                --             if Config.FuelDebug then print("^2"..current.. "^5 has been found. It ^2matches ^5the Player's Vehicle: ^2"..vehiclename..". ^5This means charging will be allowed.') end
                --             Wait(50)
                --             goto ChargingMenu -- Attempt to go to the charging menu, now that we have found that there was an electric vehicle.
                --         elseif i == #Config.ElectricVehicles then
                --             FoundElectricVehicle = false
                --             AwaitingElectricCheck = false
                --             Wait(50)
                --             if Config.FuelDebug then print("^2An electric vehicle^5 has NOT been found. ^5This means charging will not be allowed.') end
                --             goto ChargingMenu -- Attempt to go to the charging menu, now that we have not found that there was an electric vehicle.
                --         end
                --     else
                --         if Config.FuelDebug then print('Search ended..') end
                --     end
                -- end
            else
                Notify("error", locale('fuelstation'), locale('electric_vehicle_not_electric'), "fas fa-search", 3000)
            end
        end
    end)

    RegisterNetEvent('cdn-fuel:client:electric:ChargeVehicle', function(data)
        if Config.FuelDebug then print("Charging Vehicle") end
        if data.purchasetype == "cash" then 
            purchasetype = "cash"
        else
            purchasetype = "bank"
        end
        if Config.FuelDebug then print("Purchase Type: "..purchasetype) end
        local amount = data.fuelamounttotal
        if not HoldingElectricNozzle then return end
        amount = tonumber(amount)
        if amount < 1 then return end
        if amount < 10 then fuelamount = string.sub(amount, 1, 1) else fuelamount = string.sub(amount, 1, 2) end
        local FuelPrice = (Config.ElectricChargingPrice * 1)
        local vehicle = GetClosestVehicle()

        -- Police Discount Math --
        if Config.EmergencyServicesDiscount['enabled'] == true and (Config.EmergencyServicesDiscount['emergency_vehicles_only'] == false or (Config.EmergencyServicesDiscount['emergency_vehicles_only'] == true and GetVehicleClass(vehicle) == 18)) then
            local discountedJobs = Config.EmergencyServicesDiscount['job']
            local plyJob = ESX.PlayerData.job.name
            local shouldRecieveDiscount = false

            if type(discountedJobs) == "table" then
                for i = 1, #discountedJobs, 1 do
                    if plyJob == discountedJobs[i] then
                        shouldRecieveDiscount = true
                        break
                    end
                end
            elseif plyJob == discountedJobs then
                shouldRecieveDiscount = true
            end

            if shouldRecieveDiscount == true and Config.EmergencyServicesDiscount['ondutyonly'] then
                Notify("success", locale('fuelstation'), locale('you_are_discount_eligible'), "fas fa-search", 3000)
				shouldRecieveDiscount = false
			end

            if shouldRecieveDiscount then
                local discount = Config.EmergencyServicesDiscount['discount']
                if discount > 100 then 
                    discount = 100 
                else 
                    if discount <= 0 then discount = 0 end
                end
                if discount ~= 0 then
                    if discount == 100 then
                        FuelPrice = 0
                        if Config.FuelDebug then
                            print("Your discount for Emergency Services is set @ "..discount.."% so fuel is free!")
                        end
                    else
                        discount = discount / 100
                        FuelPrice = FuelPrice - (FuelPrice*discount)

                        if Config.FuelDebug then
                            print("Your discount for Emergency Services is set @ "..discount.."%. Setting new price to: $"..FuelPrice)
                        end
                    end
                else
                    if Config.FuelDebug then
                        print("Your discount for Emergency Services is set @ "..discount.."%. It cannot be 0 or < 0!")
                    end
                end
            end
        end

        local refillCost = (fuelamount * FuelPrice) + GlobalTax(fuelamount*FuelPrice)
        local vehicle = GetClosestVehicle()
        local ped = PlayerPedId()
        local time = amount * Config.RefuelTime
        if amount < 10 then time = 10 * Config.RefuelTime end
        local vehicleCoords = GetEntityCoords(vehicle)
        if IsInGasStation() then
            if IsPlayerNearVehicle() then
                RequestAnimDict(Config.RefuelAnimationDictionary)
                while not HasAnimDictLoaded('timetable@gardener@filling_can') do Wait(100) end
                if GetIsVehicleEngineRunning(vehicle) and Config.VehicleBlowUp then
                    local Chance = math.random(1, 100)
                    if Chance <= Config.BlowUpChance then
                        AddExplosion(vehicleCoords, 5, 50.0, true, false, true)
                        return
                    end
                end
                TaskPlayAnim(ped, Config.RefuelAnimationDictionary, Config.RefuelAnimation, 8.0, 1.0, -1, 1, 0, 0, 0, 0)
                refueling = true
                Refuelamount = 0
                CreateThread(function()
                    while refueling do
                        if Refuelamount == nil then Refuelamount = 0 end
                        Wait(Config.RefuelTime)
                        Refuelamount = Refuelamount + 1
                        if Cancelledrefuel then
                            local finalrefuelamount = math.floor(Refuelamount)
                            local refillCost = (finalrefuelamount * FuelPrice) + GlobalTax(finalrefuelamount * FuelPrice)
                            if Config.RenewedPhonePayment and purchasetype == "bank" then
                                local remainingamount = (amount - Refuelamount)
                                MoneyToGiveBack = (GlobalTax(remainingamount * FuelPrice) + (remainingamount * FuelPrice))
                                TriggerServerEvent("cdn-fuel:server:phone:givebackmoney", MoneyToGiveBack)
                            else
                                TriggerServerEvent('cdn-fuel:server:PayForFuel', refillCost, purchasetype, FuelPrice)
                            end
                            local curfuel = GetFuel(vehicle)
                            local finalfuel = (curfuel + Refuelamount)
                            if finalfuel >= 98 and finalfuel < 100 then
                                SetFuel(vehicle, 100)
                            else
                                SetFuel(vehicle, finalfuel)
                            end
                            if Config.RenewedPhonePayment then
                                RefuelCancelled = true
                                RefuelPossibleAmount = 0
                                RefuelPossible = false
                            end
                            Cancelledrefuel = false
                        end
                    end
                end)
                TriggerServerEvent("InteractSound_SV:PlayOnSource", "charging", 0.3)
                if lib.progressCircle({
                    duration = time,
                    label = locale('prog_electric_charging'),
                    position = 'bottom',
                    useWhileDead = false,
                    canCancel = true,
                    disable = {
                        move = true,
                        combat = true
                    },
                }) then
                    refueling = false
                    if purchasetype == "cash" then
                        TriggerServerEvent('cdn-fuel:server:PayForFuel', refillCost, purchasetype, FuelPrice, true)
                    elseif purchasetype == "bank" then
                        TriggerServerEvent('cdn-fuel:server:PayForFuel', refillCost, purchasetype, FuelPrice, true)
                    end
                    local curfuel = GetFuel(vehicle)
                    local finalfuel = (curfuel + fuelamount)
                    if finalfuel >= 99 then
                        SetFuel(vehicle, 100)
                    else
                        SetFuel(vehicle, finalfuel)
                    end
                    if Config.RenewedPhonePayment then
                        RefuelCancelled = true
                        RefuelPossibleAmount = 0
                        RefuelPossible = false
                    end
                    StopAnimTask(ped, Config.RefuelAnimationDictionary, Config.RefuelAnimation, 3.0, 3.0, -1, 2, 0, 0, 0, 0)
                    TriggerServerEvent("InteractSound_SV:PlayOnSource", "chargestop", 0.4)
                else
                    refueling = false
                    Cancelledrefuel = true
                    StopAnimTask(ped, Config.RefuelAnimationDictionary, Config.RefuelAnimation, 3.0, 3.0, -1, 2, 0, 0, 0, 0)
                    TriggerServerEvent("InteractSound_SV:PlayOnSource", "chargestop", 0.4)                        
                end
            end
        else return end
    end)

    RegisterNetEvent('cdn-fuel:client:grabelectricnozzle', function()
        local ped = PlayerPedId()
        if HoldingElectricNozzle then return end
        LoadAnimDict("anim@am_hold_up@male")
        TaskPlayAnim(ped, "anim@am_hold_up@male", "shoplift_high", 2.0, 8.0, -1, 50, 0, 0, 0, 0)
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "pickupnozzle", 0.4)
        Wait(300)
        StopAnimTask(ped, "anim@am_hold_up@male", "shoplift_high", 1.0)
        ElectricNozzle = CreateObject(joaat('electric_nozzle'), 1.0, 1.0, 1.0, true, true, false)
        local lefthand = GetPedBoneIndex(ped, 18905)
        AttachEntityToEntity(ElectricNozzle, ped, lefthand, 0.24, 0.10, -0.052 --[[FWD BWD]], -45.0 --[[ClockWise]], 120.0 --[[Weird Middle Axis]], 75.00 --[[Counter Clockwise]], 0, 1, 0, 1, 0, 1)
        local grabbedelectricnozzlecoords = GetEntityCoords(ped)
        HoldingElectricNozzle = true
        if Config.PumpHose == true then
            local pumpCoords, pump = GetClosestPump(grabbedelectricnozzlecoords, true)
            RopeLoadTextures()
            while not RopeAreTexturesLoaded() do
                Wait(0)
                RopeLoadTextures()
            end
            while not pump do
                Wait(0)
            end
            Rope = AddRope(pumpCoords.x, pumpCoords.y, pumpCoords.z, 0.0, 0.0, 0.0, 3.0, Config.RopeType['electric'], 1000.0, 0.0, 1.0, false, false, false, 1.0, true)
            while not Rope do
                Wait(0)
            end
            ActivatePhysics(Rope)
            Wait(100)
            local nozzlePos = GetEntityCoords(ElectricNozzle)
            nozzlePos = GetOffsetFromEntityInWorldCoords(ElectricNozzle, -0.005, 0.185, -0.05)
            AttachEntitiesToRope(Rope, pump, ElectricNozzle, pumpCoords.x, pumpCoords.y, pumpCoords.z + 1.76, nozzlePos.x, nozzlePos.y, nozzlePos.z, 5.0, false, false, nil, nil)
        end
        CreateThread(function()
            while HoldingElectricNozzle do
                local currentcoords = GetEntityCoords(ped)
                local dist = #(grabbedelectricnozzlecoords - currentcoords)
                if not TargetCreated then if Config.FuelTargetExport then exports[Config.TargetResource]:AllowRefuel(true, true) end end
                TargetCreated = true
                if dist > 7.5 then
                    if TargetCreated then if Config.FuelTargetExport then exports[Config.TargetResource]:AllowRefuel(false, true) end end
                    TargetCreated = true
                    HoldingElectricNozzle = false
                    DeleteObject(ElectricNozzle)
                    Notify("error", locale('fuelstation'), locale('nozzle_cannot_reach'), "fas fa-search", 3000)
                    if Config.PumpHose == true then
                        if Config.FuelDebug then print("Removing ELECTRIC Rope.") end
                        RopeUnloadTextures()
                        DeleteRope(Rope)
                    end
                end
                Wait(2500)
            end
        end)
    end)    

    RegisterNetEvent('cdn-fuel:client:electric:RefuelMenu', function()
        if Config.RenewedPhonePayment then
            if not RefuelPossible then 
                TriggerEvent('cdn-fuel:client:electric:SendMenuToServer')
            else 
                if Config.RenewedPhonePayment then
                    if not Cancelledrefuel and not RefuelCancelled then
                        if RefuelPossibleAmount then
                            local purchasetype = "bank"
                            local fuelamounttotal = tonumber(RefuelPossibleAmount)
                            if Config.FuelDebug then print("Attempting to charge vehicle.") end
                            TriggerEvent('cdn-fuel:client:electric:ChargeVehicle', purchasetype, fuelamounttotal)
                        else
                            Notify("error", locale('fuelstation'), locale('electric_more_than_zero'), "fas fa-search", 3000)
                        end
                    end
                end
            end
        else
            TriggerEvent("cdn-fuel:client:electric:SendMenuToServer")
        end
    end)

    if Config.RenewedPhonePayment then
        RegisterNetEvent('cdn-fuel:client:electric:phone:PayForFuel', function(amount)
            FuelPrice = Config.ElectricChargingPrice
            
            -- Police Discount Math --
            if Config.EmergencyServicesDiscount['enabled'] == true then
                local discountedJobs = Config.EmergencyServicesDiscount['job']
                local plyJob = ESX.PlayerData.job.name
                local shouldRecieveDiscount = false

                if type(discountedJobs) == "table" then
                    for i = 1, #discountedJobs, 1 do
                        if plyJob == discountedJobs[i] then
                            shouldRecieveDiscount = true
                            break
                        end
                    end
                elseif plyJob == discountedJobs then
                    shouldRecieveDiscount = true
                end

                if shouldRecieveDiscount == true and Config.EmergencyServicesDiscount['ondutyonly'] then
                    Notify("success", locale('fuelstation'), locale('you_are_discount_eligible'), "fas fa-search", 3000)
                    shouldRecieveDiscount = false
                end

                if shouldRecieveDiscount then
                    local discount = Config.EmergencyServicesDiscount['discount']
                    if discount > 100 then 
                        discount = 100 
                    else 
                        if discount <= 0 then discount = 0 end
                    end
                    if discount ~= 0 then
                        if discount == 100 then
                            FuelPrice = 0
                            if Config.FuelDebug then
                                print("Your discount for Emergency Services is set @ "..discount.."% so fuel is free!")
                            end
                        else
                            discount = discount / 100
                            FuelPrice = FuelPrice - (FuelPrice*discount)

                            if Config.FuelDebug then
                                print("Your discount for Emergency Services is set @ "..discount.."%. Setting new price to: $"..FuelPrice)
                            end
                        end
                    else
                        if Config.FuelDebug then
                            print("Your discount for Emergency Services is set @ "..discount.."%. It cannot be 0 or < 0!")
                        end
                    end
                end
            end
            local cost = amount * FuelPrice
            local tax = GlobalTax(cost)
            local total = math.ceil(cost + tax)
            --local success = exports['qb-phone']:PhoneNotification(locale('electric_phone_header'), locale('electric_phone_notification')..total, 'fas fa-bolt', '#9f0e63', "NONE", 'fas fa-check-circle', 'fas fa-times-circle')
            local bank, moneyY = lib.callback.await('cdn-fuel:getmoney')

            lib.notify({
                title = locale('electric_phone_header'),
                description = locale('electric_phone_notification')..total,
                icon = 'fas fa-bolt',
                type = 'success'
            })

            if bank <= (GlobalTax(amount) + amount) then
                Notify("success", locale('fuelstation'), locale('not_enough_money_in_bank'), "fas fa-search", 3000)
            else
                TriggerServerEvent('cdn-fuel:server:PayForFuel', total, "bank", FuelPrice, true)
                RefuelPossible = true
                RefuelPossibleAmount = amount
                RefuelPurchaseType = "bank"
                RefuelCancelled = false
            end
            
        end)
    end

    -- Threads
    if Config.ElectricChargerModel then
        CreateThread(function()
            Wait(500)
            RequestModel("electric_charger")
            while not HasModelLoaded("electric_charger") do
                Wait(50)
            end
        
            if Config.FuelDebug then
                print("Electric Charger Model Loaded!")
            end
        
            for i = 1, #Config.GasStations do
                if Config.GasStations[i].electricchargercoords ~= nil then
                    if Config.FuelDebug then print(i) end
                    local heading = Config.GasStations[i].electricchargercoords[4] - 180
                    Config.GasStations[i].electriccharger = CreateObject('electric_charger', Config.GasStations[i].electricchargercoords.x, Config.GasStations[i].electricchargercoords.y, Config.GasStations[i].electricchargercoords.z, false, true, true)
                    --if Config.FuelDebug then print("Created Electric Charger @ Location #"..i) end
                    SetEntityHeading(Config.GasStations[i].electriccharger, heading)
                    FreezeEntityPosition(Config.GasStations[i].electriccharger, 1)
                end	
            end
        end)
    end

    -- Resource Stop

    AddEventHandler('onResourceStop', function(resource)
        if resource == GetCurrentResourceName() then
            for i = 1, #Config.GasStations do
                if Config.GasStations[i].electricchargercoords ~= nil then
                    DeleteEntity(Config.GasStations[i].electriccharger)
                    if IsHoldingElectricNozzle() then DeleteEntity(ElectricNozzle) end
                end	
            end

            if Config.PumpHose then
                RopeUnloadTextures()
                DeleteObject(Rope)
            end
        end
    end)

    -- Target
    local TargetResource = Config.TargetResource
    if Config.TargetResource == 'ox_target' then
        TargetResource = 'qb-target'
    end

    exports[TargetResource]:AddTargetModel('electric_charger', {
        options = {
            {
                num = 1,
                type = "client",
                event = "cdn-fuel:client:grabelectricnozzle",
                icon = "fas fa-bolt",
                label = locale('grab_electric_nozzle'),
                canInteract = function()
                    if not IsHoldingElectricNozzle() and not IsPedInAnyVehicle(PlayerPedId()) then
                        return true
                    end
                end
            },
            {
                num = 2,
                type = "client",
                event = "cdn-fuel:client:returnnozzle",
                icon = "fas fa-hand",
                label = locale('return_nozzle'),
                canInteract = function()
                    if IsHoldingElectricNozzle() and not refueling then
                        return true
                    end
                end
            },
        },
        distance = 2.0
    })
end

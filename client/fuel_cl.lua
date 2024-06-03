-- Variables
local ESX = exports["es_extended"]:getSharedObject()
local fuelSynced = false
local inGasStation = false
local inBlacklisted = false
local holdingnozzle = false
local Stations = {}
local props = {
	"prop_gas_pump_1d",
	"prop_gas_pump_1a",
	"prop_gas_pump_1b",
	"prop_gas_pump_1c",
	"prop_vintage_pump",
	"prop_gas_pump_old2",
	"prop_gas_pump_old3",
	"denis3d_prop_gas_pump", -- Gabz Ballas Gas Station Pump.
}
local refueling = false
local GasStationBlips = {} -- Used for managing blips on the client, so labels can be updated.
local RefuelingType = nil
local PlayerInSpecialFuelZone = false
local Rope = nil
local CachedFuelPrice = nil

-- Debug ---
if Config.FuelDebug then
	RegisterCommand('setfuel', function(source, args)
		if args[1] == nil then print("You forgot to put a fuel level!") return end
		local vehicle = GetClosestVehicle()
		SetFuel(vehicle, tonumber(args[1]))
		Notify("success", locale('fuelstation'), locale('set_fuel_debug') .. args[1], "fas fa-search", 3000)
	end, false)
	
	RegisterCommand('getCachedFuelPrice', function()
		print(CachedFuelPrice)
	end, false)

	RegisterCommand('getVehNameForBlacklist', function()
		local veh = GetVehiclePedIsIn(PlayerPedId(), false)
		if veh ~= 0 then
			print(string.lower(GetDisplayNameFromVehicleModel(GetEntityModel(veh))))
		end
	end, false)
end

-- Functions

function GetClosestPump(coords, isElectric)
	if isElectric then 
		local electricPump = nil
		electricPump = GetClosestObjectOfType(coords.x, coords.y, coords.z, 3.0, joaat("electric_charger"), true, true, true)
		local pumpCoords = GetEntityCoords(electricPump)
		if Config.FuelDebug then
			print(electricPump, pumpCoords)
		end
		return pumpCoords, electricPump
	else 
		local pump = nil
		local pumpCoords
		for i = 1, #props, 1 do
			local currentPumpModel = props[i]
			pump = GetClosestObjectOfType(coords.x, coords.y, coords.z, 3.0, joaat(currentPumpModel), true, true, true)
			pumpCoords = GetEntityCoords(pump)
			if Config.FuelDebug then print("Gas Pump: ".. pump,  "Pump Coords: "..pumpCoords) end
			if pump ~= 0 then break end
		end
		return pumpCoords, pump
	end
end

local function FetchStationInfo(info)
	if not Config.PlayerOwnedGasStationsEnabled then ReserveLevels = 1000 StationFuelPrice = Config.CostMultiplier return end
	if Config.FuelDebug then print("Fetching Information for Location #" ..CurrentLocation) end
	--local result = lib.callback.await('cdn-fuel:server:fetchinfo', CurrentLocation)
	local result = lib.callback.await('cdn-fuel:server:fetchinfo', false, CurrentLocation)
	print(json.encode(result))
	if result then
		for _, v in pairs(result) do
			-- Reserves --
			if info == "all" or info == "reserves" then
				Currentreserveamount = math.floor(v.fuel)
				ReserveLevels = tonumber(Currentreserveamount)
				if Config.FuelDebug then print("Fetched Reserve Levels: "..ReserveLevels.." Liters!") end
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
			-- Balance --
			if info == "all" or info == "balance" then
				StationBalance = v.balance
				if info == "balance" then
					return StationBalance
				end
			end
			----------------
		end
	else
		if Config.FuelDebug then print("Error, fetching information failed.") end
	end
end exports(FetchStationInfo, FetchStationInfo)

local function HandleFuelConsumption(vehicle)
	if not DecorExistOn(vehicle, Config.FuelDecor) then
		SetFuel(vehicle, math.random(200, 800) / 10)
	elseif not fuelSynced then
		SetFuel(vehicle, GetFuel(vehicle))
		fuelSynced = true
	end

	if IsVehicleEngineOn(vehicle) then
		SetFuel(vehicle, GetVehicleFuelLevel(vehicle) - Config.FuelUsage[Round(GetVehicleCurrentRpm(vehicle), 1)] * (Config.Classes[GetVehicleClass(vehicle)] or 1.0) / 10)
	end
end

local function CanAfford(price, purchasetype)
	local purchasetype = purchasetype
	local bank, moneyY = lib.callback.await('cdn-fuel:getmoney')
	if purchasetype == "bank" then Money = bank elseif purchasetype == 'cash' then Money = moneyY end
	if Money < price then
		return false
	else
		return true
	end
end

function FetchCurrentLocation()
	if Config.FuelDebug then print("Fetching Current Location") end
	return CurrentLocation
end

function IsInGasStation()
	return inGasStation
end


-- Thread Stuff --

if Config.LeaveEngineRunning then
	CreateThread(function()
		while true do
			Wait(100)
			local ped = PlayerPedId()
			if IsPedInAnyVehicle(ped, false) and IsControlPressed(2, 75) and not IsEntityDead(ped) then
				local vehicle = GetVehiclePedIsIn(ped, true)
				local enginerunning = GetIsVehicleEngineRunning(vehicle)
				if Config.FuelDebug then if enginerunning then print('Engine is running!') else print('Engine is not running!') end end
				Wait(900)
				if IsPedInAnyVehicle(ped, false) and IsControlPressed(2, 75) and not IsEntityDead(ped) and GetPedInVehicleSeat(GetVehiclePedIsIn(PlayerPedId()), -1) == PlayerPedId() then
					if enginerunning then SetVehicleEngineOn(vehicle, true, true, false) enginerunning = false end
					TaskLeaveVehicle(ped, veh, keepDooRopen and 256 or 0)
				end
			end
		end
	end)
end

if Config.ShowNearestGasStationOnly then
	RegisterNetEvent('cdn-fuel:client:updatestationlabels', function(location, newLabel)
		if not location then if Config.FuelDebug then print('location is nil') end return end
		if not newLabel then if Config.FuelDebug then print('newLabel is nil') end return end
		if Config.FuelDebug then print("Changing Label for Location #"..location..' to '..newLabel) end
		Config.GasStations[location].label = newLabel
	end)

	CreateThread(function()
		if Config.PlayerOwnedGasStationsEnabled then
			TriggerServerEvent('cdn-fuel:server:updatelocationlabels')
		end
		Wait(1000)
		local currentGasBlip = 0
		while true do
			local coords = GetEntityCoords(PlayerPedId())
			local closest = 1000
			local closestCoords
			local closestLocation
			local location = 0
			local label = "Gas Station" -- Prevent nil just in case, set default name.
			for _, ourCoords in pairs(Config.GasStations) do
				location = location + 1
				if not (location > #Config.GasStations) then -- Make sure we are not going over the amount of locations available.
					local gasStationCoords = vector3(Config.GasStations[location].pedcoords.x, Config.GasStations[location].pedcoords.y, Config.GasStations[location].pedcoords.z)
					local dstcheck = #(coords - gasStationCoords)
					if dstcheck < closest then
						closest = dstcheck
						closestCoords = gasStationCoords
						closestLocation = location
						label = Config.GasStations[closestLocation].label
					end
				else
					break
				end
			end
			if DoesBlipExist(currentGasBlip) then
				RemoveBlip(currentGasBlip)
			end
			currentGasBlip = CreateBlip(closestCoords, label)
			Wait(10000)
		end
	end)
else
	RegisterNetEvent('cdn-fuel:client:updatestationlabels', function(location, newLabel)
		if not location then if Config.FuelDebug then print('location is nil') end return end
		if not newLabel then if Config.FuelDebug then print('newLabel is nil') end return end
		if Config.FuelDebug then print("Changing Label for Location #"..location..' to '..newLabel) end
		Config.GasStations[location].label = newLabel
		local coords = vector3(Config.GasStations[location].pedcoords.x, Config.GasStations[location].pedcoords.y, Config.GasStations[location].pedcoords.z)
		RemoveBlip(GasStationBlips[location])
		GasStationBlips[location] = CreateBlip(coords, Config.GasStations[location].label)
	end)

	CreateThread(function()
		TriggerServerEvent('cdn-fuel:server:updatelocationlabels')
		Wait(1000)
		local gasStationCoords
		for i = 1, #Config.GasStations, 1 do
			local location = i
			gasStationCoords = vector3(Config.GasStations[location].pedcoords.x, Config.GasStations[location].pedcoords.y, Config.GasStations[location].pedcoords.z)
			GasStationBlips[location] = CreateBlip(gasStationCoords, Config.GasStations[location].label)
		end
	end)
end

CreateThread(function()
	for station_id = 1, #Config.GasStations, 1 do
		Stations[station_id] = PolyZone:Create(Config.GasStations[station_id].zones, {
			name = "CDN_FUEL_GAS_STATION_"..station_id,
			minZ = Config.GasStations[station_id].minz,
			maxZ = Config.GasStations[station_id].maxz,
			debugPoly = Config.PolyDebug
		})
		Stations[station_id]:onPlayerInOut(function(isPointInside)
			if isPointInside then
				inGasStation = true
				CurrentLocation = station_id
				if Config.FuelDebug then print("New Location: "..station_id) end
				if Config.PlayerOwnedGasStationsEnabled then
					TriggerEvent('cdn-fuel:stations:updatelocation', station_id)
				end
			else
				TriggerEvent('cdn-fuel:stations:updatelocation', nil)
				inGasStation = false
			end
		end)
	end
end)

CreateThread(function()
	DecorRegister(Config.FuelDecor, 1)
	while true do
		Wait(1000)
		local ped = PlayerPedId()
		-- Blacklist Electric Vehicles, if you disables the Config.ElectricVehicleCharging or put the vehicle in Config.NoFuelUsage!
		if IsPedInAnyVehicle(ped) then
			local vehicle = GetVehiclePedIsIn(ped)
			inBlacklisted = IsVehicleBlacklisted(vehicle)
			if not inBlacklisted and GetPedInVehicleSeat(vehicle, -1) == ped then
				HandleFuelConsumption(vehicle)
			end
		else
			if fuelSynced then fuelSynced = false end
			if inBlacklisted then inBlacklisted = false end
			Wait(500)
		end
	end
end)

-- Client Events
if Config.RenewedPhonePayment then
	RegisterNetEvent('cdn-fuel:client:phone:PayForFuel', function(amount)
		if Config.PlayerOwnedGasStationsEnabled and RefuelingType ~= 'special' then
			FetchStationInfo("fuelprice")
			Wait(100)
		else
			FuelPrice = Config.CostMultiplier
		end
		if Config.AirAndWaterVehicleFueling['enabled'] then
			local vehClass = GetVehicleClass(vehicle)
			if vehClass == 14 then
				FuelPrice = Config.AirAndWaterVehicleFueling['water_fuel_price']
			elseif vehClass == 15 or vehClass == 16 then
				FuelPrice = Config.AirAndWaterVehicleFueling['air_fuel_price']
			end
		end
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
						CachedFuelPrice = FuelPrice
						FuelPrice = 0
						if Config.FuelDebug then
							print("Your discount for Emergency Services is set @ "..discount.."% so fuel is free!")
						end
					else
						discount = discount / 100
						if Config.FuelDebug then
							print(FuelPrice, FuelPrice*discount)
						end
						CachedFuelPrice = FuelPrice
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
		local bank, moneyY = lib.callback.await('cdn-fuel:getmoney')

		if bank <= total then
			Notify("error", locale('fuelstation'), locale('not_enough_money'), "fas fa-search", 3000)
		else
			TriggerServerEvent('cdn-fuel:server:PayForFuel', total, "bank", FuelPrice, false, CachedFuelPrice)
			RefuelPossible = true
			RefuelPossibleAmount = amount
			RefuelCancelledFuelCost = FuelPrice
			RefuelPurchaseType = "bank"
			RefuelCancelled = false
		end
	end)
end


if Config.Ox.Inventory then
	if LocalPlayer.state['isLoggedIn'] then
		exports.ox_inventory:displayMetadata({
			cdn_fuel = "Fuel",
		})
	end
	AddEventHandler("esx:playerLoaded", function()
		if GetResourceState('ox_inventory'):match("start") then
			exports.ox_inventory:displayMetadata({
				cdn_fuel = "Fuel",
			})
		end
	end)
end

if Config.Ox.Menu then
	RegisterNetEvent('cdn-fuel:client:OpenContextMenu', function(total, fuelamounttotal, purchasetype)
		if Config.FuelDebug then print("OpenContextMenu for OX sent from server.") end
		lib.registerContext({
			id = 'cdnconfirmationmenu',
			title = locale('menu_purchase_station_header_1')..math.ceil(total)..locale('menu_purchase_station_header_2'),
			options = {
				{
					title = locale('menu_purchase_station_confirm_header'),
					description = locale('menu_refuel_accept'),
					icon = "fas fa-check-circle",
					arrow = false, -- puts arrow to the right
					event = 'cdn-fuel:client:RefuelVehicle',
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
		lib.showContext('cdnconfirmationmenu')
	end)
end

RegisterNetEvent('cdn-fuel:client:RefuelMenu', function(type)
	if Config.FuelDebug then print("cdn-fuel:client:refuelmenu") end
	if not type then type = nil end
	if Config.RenewedPhonePayment then
		if not RefuelPossible then 
			TriggerEvent('cdn-fuel:client:SendMenuToServer', type)
		else
			if not Cancelledrefuel and not RefuelCancelled then
				if RefuelPossibleAmount then
					local purchasetype = "bank"
					local fuelamounttotal = tonumber(RefuelPossibleAmount)
					TriggerEvent('cdn-fuel:client:RefuelVehicle', purchasetype, fuelamounttotal) 
				else
					if Config.FuelDebug then
						print("RefuelMenu: MORE THAN ZERO!")
					end
					Notify("error", locale('fuelstation'), locale('more_than_zero'), "fas fa-search", 3000)
				end
			end
		end
	else
		TriggerEvent('cdn-fuel:client:SendMenuToServer', type)
	end
end)

RegisterNetEvent('cdn-fuel:client:grabnozzle', function()
	if Config.PlayerOwnedGasStationsEnabled then
		ShutOff = false
		Wait(50)
		local result = lib.callback.await('cdn-fuel:server:checkshutoff', CurrentLocation)
		
		if result == true then
			print("Location off")
			Notify("warning", locale('fuelstation'), locale('emergency_shutoff_active'), "fas fa-search", 3000)
			ShutOff = true 
			return
		else
			ShutOff = false
		end
		
		Wait(50)
	else
		ShutOff = false
		Wait(50)
	end
	if not ShutOff then
		local ped = PlayerPedId()
		if holdingnozzle then return end
		LoadAnimDict("anim@am_hold_up@male")
		TaskPlayAnim(ped, "anim@am_hold_up@male", "shoplift_high", 2.0, 8.0, -1, 50, 0, 0, 0, 0)
		TriggerServerEvent("InteractSound_SV:PlayOnSource", "pickupnozzle", 0.4)
		Wait(300)
		StopAnimTask(ped, "anim@am_hold_up@male", "shoplift_high", 1.0)
		fuelnozzle = CreateObject(joaat('prop_cs_fuel_nozle'), 1.0, 1.0, 1.0, true, true, false)
		local lefthand = GetPedBoneIndex(ped, 18905)
		AttachEntityToEntity(fuelnozzle, ped, lefthand, 0.13, 0.04, 0.01, -42.0, -115.0, -63.42, 0, 1, 0, 1, 0, 1)
		local grabbednozzlecoords = GetEntityCoords(ped)
		if Config.PumpHose then
			local pumpCoords, pump = GetClosestPump(grabbednozzlecoords)
			-- Load Rope Textures
			RopeLoadTextures()
			while not RopeAreTexturesLoaded() do
				Wait(0)
				RopeLoadTextures()
			end
			-- Wait for Pump to exist.
			while not pump do
				Wait(0)
			end
			Rope = AddRope(pumpCoords.x, pumpCoords.y, pumpCoords.z, 0.0, 0.0, 0.0, 3.0, Config.RopeType['fuel'], 8.0 --[[ DO NOT SET THIS TO 0.0!!! GAME WILL CRASH!]], 0.0, 1.0, false, false, false, 1.0, true)
			while not Rope do
				Wait(0)
			end
			ActivatePhysics(Rope)
			Wait(100)
			local nozzlePos = GetEntityCoords(fuelnozzle)
			if Config.FuelDebug then print("NOZZLE POS ".. nozzlePos) end
			nozzlePos = GetOffsetFromEntityInWorldCoords(fuelnozzle, 0.0, -0.033, -0.195)
			local PumpHeightAdd = nil
			if Config.FuelDebug then
				print("Grabbing Hose @ Location: #"..CurrentLocation)
				if Config.GasStations[CurrentLocation].pumpheightadd ~= nil then
					PumpHeightAdd = Config.GasStations[CurrentLocation].pumpheightadd
					print("Pump Height Add: "..Config.GasStations[CurrentLocation].pumpheightadd)
				end
			end
			if PumpHeightAdd == nil then
				PumpHeightAdd = 2.1
				if Config.FuelDebug then
					print("PumpHeightAdd was not configured for location: #"..CurrentLocation.." so, we are defaulting to 2.0!")
				end
			end
			AttachEntitiesToRope(Rope, pump, fuelnozzle, pumpCoords.x, pumpCoords.y, pumpCoords.z + PumpHeightAdd, nozzlePos.x, nozzlePos.y, nozzlePos.z, length, false, false, nil, nil)
			if Config.FuelDebug then
				print("Hose Properties:")
				print(Rope, pump, fuelnozzle, pumpCoords.x, pumpCoords.y, pumpCoords.z, nozzlePos.x, nozzlePos.y, nozzlePos.z, length)
				SetEntityDrawOutline(fuelnozzle --[[ Entity ]], true --[[ boolean ]])
			end
		end
		holdingnozzle = true
		CreateThread(function()
			while holdingnozzle do
				local currentcoords = GetEntityCoords(ped)
				local dist = #(grabbednozzlecoords - currentcoords)
				if not TargetCreated then if Config.FuelTargetExport then exports[Config.TargetResource]:AllowRefuel(true) end end
				TargetCreated = true
				if dist > 7.5 then
					if TargetCreated then if Config.FuelTargetExport then exports[Config.TargetResource]:AllowRefuel(false) end end
					TargetCreated = true
					holdingnozzle = false
					DeleteObject(fuelnozzle)
					Notify("error", locale('fuelstation'), locale('nozzle_cannot_reach'), "fas fa-search", 3000)
					if Config.PumpHose == true then
						RopeUnloadTextures()
						DeleteRope(Rope)
					end
					if Config.FuelNozzleExplosion then
						AddExplosion(grabbednozzlecoords.x, grabbednozzlecoords.y, grabbednozzlecoords.z, 'EXP_TAG_PROPANE', 1.0, true,false, 5.0)
						StartScriptFire(grabbednozzlecoords.x, grabbednozzlecoords.y, grabbednozzlecoords.z - 1,25,false)
						SetFireSpreadRate(10.0)
						Wait(5000)
						StopFireInRange(grabbednozzlecoords.x, grabbednozzlecoords.y, grabbednozzlecoords.z - 1, 3.0)
					end
				end
				Wait(2500)
			end
		end)
	end
end)

RegisterNetEvent('cdn-fuel:client:returnnozzle', function()
	if Config.ElectricVehicleCharging then
		if IsHoldingElectricNozzle() then
			SetElectricNozzle("putback")
		else
			holdingnozzle = false
			TargetCreated = false
			TriggerServerEvent("InteractSound_SV:PlayOnSource", "putbacknozzle", 0.4)
			Wait(250)
			if Config.FuelTargetExport then exports[Config.TargetResource]:AllowRefuel(false) end
			DeleteObject(fuelnozzle)
		end
	else
		holdingnozzle = false
		TargetCreated = false
		TriggerServerEvent("InteractSound_SV:PlayOnSource", "putbacknozzle", 0.4)
		Wait(250)
		if Config.FuelTargetExport then exports[Config.TargetResource]:AllowRefuel(false) end
		DeleteObject(fuelnozzle)
	end
	if Config.PumpHose then
		if Config.FuelDebug then print("Removing Hose.") end
		RopeUnloadTextures()
		DeleteRope(Rope)
	end
end)

AddEventHandler('onResourceStop', function(resource)
	if resource == GetCurrentResourceName() then
		DeleteObject(fuelnozzle)
		DeleteObject(SpecialFuelNozzleObj)
		if Config.PumpHose then
			RopeUnloadTextures()
			DeleteObject(Rope)
		end
		if Config.TargetResource == 'ox_target' then
			exports.ox_target:removeGlobalVehicle('cdn-fuel:options:1')
			exports.ox_target:removeGlobalVehicle('cdn-fuel:options:2')
		end
		-- Remove Blips from map so they dont double up.
		for i = 1, #GasStationBlips, 1 do
			RemoveBlip(GasStationBlips[i])
		end
	end
end)

RegisterNetEvent('cdn-fuel:client:FinalMenu', function(purchasetype)
	if Config.FuelDebug then
		print('cdn-fuel:client:FinalMenu', purchasetype)
	end
	if RefuelingType == nil then
		FetchStationInfo("all")
		Wait(Config.WaitTime)
		if Config.PlayerOwnedGasStationsEnabled and not Config.UnlimitedFuel then
			if ReserveLevels < 1 then
				Notify("error", locale('fuelstation'), locale('station_no_fuel'), "fas fa-search", 3000)
				return
			end
		end
		if Config.PlayerOwnedGasStationsEnabled then
			FuelPrice = (1 * StationFuelPrice)
		end
	end
	local money = nil
	local bank, moneyY = lib.callback.await('cdn-fuel:getmoney')
	if purchasetype == "bank" then money = bank elseif purchasetype == 'cash' then money = moneyY end
	if not Config.PlayerOwnedGasStationsEnabled then
		FuelPrice = (1 * Config.CostMultiplier)
	end
	local vehicle = GetClosestVehicle()
	local curfuel = GetFuel(vehicle)
	local finalfuel
	if curfuel < 10 then finalfuel = string.sub(curfuel, 1, 1) else finalfuel = string.sub(curfuel, 1, 2) end
	local maxfuel = (100 - finalfuel - 1)
	if Config.AirAndWaterVehicleFueling['enabled'] then 
		local vehClass = GetVehicleClass(vehicle)
		if vehClass == 14 then
			FuelPrice = Config.AirAndWaterVehicleFueling['water_fuel_price']
			RefuelingType = 'special'
		elseif vehClass == 15 or vehClass == 16 then
			FuelPrice = Config.AirAndWaterVehicleFueling['air_fuel_price']
			RefuelingType = 'special'
		end
	end
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
			if Config.FuelDebug then print("Before we apply the discount the FuelPrice is: $"..FuelPrice) end
			if discount ~= 0 then
				if discount == 100 then
					CachedFuelPrice = FuelPrice
					FuelPrice = 0
					if Config.FuelDebug then
						print("Your discount for Emergency Services is set @ "..discount.."% so fuel is free!")
					end
				else
					discount = discount / 100
					if Config.FuelDebug then
						print("Math( Current Fuel Price: "..FuelPrice.. " - " ..FuelPrice * discount.. "<<-- FuelPrice * Discount)")
					end
					CachedFuelPrice = FuelPrice
					FuelPrice = (FuelPrice) - (FuelPrice*discount)
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
	local wholetankcost = (tonumber(FuelPrice) * maxfuel)
	local wholetankcostwithtax = math.ceil(tonumber(FuelPrice) * maxfuel + GlobalTax(wholetankcost))
	if Config.Ox.Input then
		if Config.PlayerOwnedGasStationsEnabled and not Config.UnlimitedFuel and not RefuelingType == 'special' then
			if ReserveLevels < maxfuel then
				local wholetankcost = (tonumber(FuelPrice) * ReserveLevels)
				local wholetankcostwithtax = math.ceil(tonumber(FuelPrice) * ReserveLevels + GlobalTax(wholetankcost))
				fuel = lib.inputDialog('Gas Station', {
					{ type = "input", label = 'Gasoline Price', default = '$'.. FuelPrice .. ' Per Liter', disabled = true },
					{ type = "input", label = 'Current Fuel', default = finalfuel .. ' Per Liter', disabled = true },
					{ type = "input", label = 'Required Full Tank', default = maxfuel .. 'Per Liter', disabled = true },
					{ type = "input", label = 'Stations Available Gasoline', default = ReserveLevels, disabled = true },
					{ type = "slider", label = 'Full Tank Cost: $' ..wholetankcostwithtax.. '',default = ReserveLevels, min = 0, max = ReserveLevels},
				})
				if not fuel then if Config.FuelDebug then print("Fuel Is Nil! #1") end return end
				fuelAmount = tonumber(fuel[5])
			else
				fuel = lib.inputDialog('Gas Station', {
					{ type = "input", label = 'Gasoline Price', default = '$'.. FuelPrice .. ' Per Liter', disabled = true },
					{ type = "input", label = 'Current Fuel', default = finalfuel .. ' Per Liter', disabled = true },
					{ type = "input", label = 'Required For A Full Tank', default = maxfuel, disabled = true },
					{ type = "slider", label = 'Full Tank Cost: $' ..wholetankcostwithtax.. '', default = maxfuel, min = 0, max = maxfuel },
				})
				if not fuel then if Config.FuelDebug then print("Fuel Is Nil! #2") end return end
				fuelAmount = tonumber(fuel[4])
			end
		else
			fuel = lib.inputDialog('Gas Station', {
				{ type = "input", label = 'Gasoline Price', default = '$'.. FuelPrice .. ' Per Liter',disabled = true },
				{ type = "input", label = 'Current Fuel', default = finalfuel .. ' Per Liter',disabled = true },
				{ type = "input", label = 'Required For A Full Tank', default = maxfuel, disabled = true },
				{ type = "slider", label = 'Full Tank Cost: $' ..wholetankcostwithtax.. '', default = maxfuel, min = 0, max = maxfuel},
			})
			if not fuel then if Config.FuelDebug then print("Fuel Is Nil! #3") end return end
			fuelAmount = tonumber(fuel[4])
		end
		if fuel then
			if not fuelAmount then print("Fuel Amount Nil") return end
			if not holdingnozzle and RefuelingType ~= 'special' then
				Notify("error", locale('fuelstation'), locale('no_nozzle'), "fas fa-search", 3000)
				return end
			if Config.PlayerOwnedGasStationsEnabled and not Config.UnlimitedFuel and not RefuelingType == "special" then
				if tonumber(fuelAmount) > tonumber(ReserveLevels) then
					Notify("error", locale('fuelstation'), locale('station_not_enough_fuel'), "fas fa-search", 3000)
				end
			end
			if (fuelAmount + finalfuel) >= 100 then
				Notify("error", locale('fuelstation'), locale('tank_cannot_fit'), "fas fa-search", 3000)
			else
				if GlobalTax(fuelAmount * FuelPrice) + (fuelAmount * FuelPrice) <= money then
					TriggerServerEvent('cdn-fuel:server:OpenMenu', fuelAmount, inGasStation, false, purchasetype, tonumber(FuelPrice))
				else
					Notify("error", locale('fuelstation'), locale('not_enough_money'), "fas fa-search", 3000)
				end
			end
		else
			if Config.FuelDebug then
				print("Fuel is nil!")
			end
		end
	else
		if Config.PlayerOwnedGasStationsEnabled and not Config.UnlimitedFuel and not RefuelingType == 'special' then
			if ReserveLevels < maxfuel then
				local wholetankcost = (FuelPrice * ReserveLevels)
				local wholetankcostwithtax = math.ceil(FuelPrice * ReserveLevels + GlobalTax(wholetankcost))
				fuel = exports['qb-input']:ShowInput({
					header = "Select the Amount of Fuel<br>Current Price: $" ..
					FuelPrice .. " / Liter <br> Current Fuel: " .. finalfuel .. " Liters <br> Full Tank Cost: $" ..
					wholetankcostwithtax .. "",
					submitText = locale('input_insert_nozzle'),
					inputs = { {
						type = 'number',
						isRequired = true,
						name = 'amount',
						text = 'Only '..ReserveLevels..' Liters are available.'
					}}
				})
			else
				fuel = exports['qb-input']:ShowInput({
					header = "Select the Amount of Fuel<br>Current Price: $" ..
					FuelPrice .. " / Liter <br> Current Fuel: " .. finalfuel .. " Liters <br> Full Tank Cost: $" ..
					wholetankcostwithtax .. "",
					submitText = locale('input_insert_nozzle'),
					inputs = { {
						type = 'number',
						isRequired = true,
						name = 'amount',
						text = 'The Tank Can Hold ' .. maxfuel .. ' More Liters.'
					}}
				})
			end
		else
			fuel = exports['qb-input']:ShowInput({
				header = "Select the Amount of Fuel<br>Current Price: $" ..
				FuelPrice .. " / Liter <br> Current Fuel: " .. finalfuel .. " Liters <br> Full Tank Cost: $" ..
				wholetankcostwithtax .. "",
				submitText = locale('input_insert_nozzle'),
				inputs = { {
					type = 'number',
					isRequired = true,
					name = 'amount',
					text = 'The Tank Can Hold ' .. maxfuel .. ' More Liters.'
				}}
			})
		end
		if fuel then
			if not fuel.amount then if Config.FuelDebug then print("fuel.amount = nil") end return end
			if not holdingnozzle and RefuelingType ~= 'special' then
				Notify("error", locale('fuelstation'), locale('no_nozzle'), "fas fa-search", 3000)
				return end
			if Config.PlayerOwnedGasStationsEnabled and not Config.UnlimitedFuel and not RefuelingType == 'special' then
				if tonumber(fuel.amount) > tonumber(ReserveLevels) then
					Notify("error", locale('fuelstation'), locale('station_not_enough_fuel'), "fas fa-search", 3000)
					return
				end
			end
			if (fuel.amount + finalfuel) >= 100 then
				Notify("error", locale('fuelstation'), locale('tank_cannot_fit'), "fas fa-search", 3000)
			else
				if GlobalTax(fuel.amount * FuelPrice) + (fuel.amount * FuelPrice) <= money then
					if Config.FuelDebug then
						print("Player is getting "..fuel.amount.."L of Fuel @ "..FuelPrice..'/L, Total Cost: '..GlobalTax(fuel.amount * FuelPrice) + (fuel.amount * FuelPrice))
					end
					TriggerServerEvent('cdn-fuel:server:OpenMenu', fuel.amount, inGasStation, false, purchasetype, tonumber(FuelPrice))
				else
					Notify("error", locale('fuelstation'), locale('not_enough_money'), "fas fa-search", 3000)
				end
			end
		end
	end
end)

RegisterNetEvent('cdn-fuel:client:SendMenuToServer', function(type)
	local vehicle = GetClosestVehicle()
	local NotElectric = false
	if Config.ElectricVehicleCharging then
		local isElectric = GetCurrentVehicleType(vehicle)
		print(isElectric)
		if isElectric == 'electricvehicle' then
			Notify("error", locale('fuelstation'), locale('need_electric_charger'), "fas fa-search", 3000)
		else 
			goto skip
		end
		return
	else
		return
	end

	:: skip ::

	local CurFuel = GetVehicleFuelLevel(vehicle)
	local bank, moneyY = lib.callback.await('cdn-fuel:getmoney')
	local playercashamount = moneyY
	local playerbankamount = bank
	if not holdingnozzle and not type == 'special' then return end
	local header
	if type == 'special' then
		header = "Refuel Vehicle"
		RefuelingType = 'special'
	else
		header = Config.GasStations[CurrentLocation].label
	end

	if CurFuel < 95 then
		lib.registerContext({
			id = 'cdnfueldmainmenu',
			title = 'Gas Station',
			icon = "fas fa-gas-pump",
			options = {
				{
					title = locale('menu_header_cash'),
					description = locale('menu_pay_with_cash') .. playercashamount,
					icon = "fas fa-usd",
					arrow = false, -- puts arrow to the right
					onSelect = function ()
						TriggerEvent('cdn-fuel:client:FinalMenu', 'cash')
					end,
				},
				{
					title = locale('menu_header_bank'),
					description = locale('menu_pay_with_bank') .. playerbankamount,
					icon = "fas fa-credit-card",
					arrow = false, -- puts arrow to the right
					onSelect = function ()
						TriggerEvent('cdn-fuel:client:FinalMenu', 'bank')
					end,
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
		lib.showContext('cdnfueldmainmenu')
	else
		Notify("error", locale('fuelstation'), locale('tank_already_full'), "fas fa-search", 3000)
	end
end)

RegisterNetEvent('cdn-fuel:client:RefuelVehicle', function(data)
	if RefuelingType == nil then
		FetchStationInfo("all")
		Wait(100)
	end
	local purchasetype, amount, fuelamount
	if not Config.RenewedPhonePayment then
		purchasetype = data.purchasetype
	elseif data.purchasetype == "cash" then
		purchasetype = "cash"
	else
		purchasetype = RefuelPurchaseType
	end
	if Config.FuelDebug then print("Purchase Type: "..purchasetype) end
	if not Config.RenewedPhonePayment then
		amount = data.fuelamounttotal
	elseif data.purchasetype == "cash" then
		amount = data.fuelamounttotal
	elseif not data.fuelamounttotal then
		amount = RefuelPossibleAmount
	end
	if Config.PlayerOwnedGasStationsEnabled and RefuelingType == nil then
		FuelPrice = (1 * StationFuelPrice)
	else
		FuelPrice = (1 * Config.CostMultiplier)
	end
	if not holdingnozzle and RefuelingType == nil then return end
	amount = tonumber(amount)
	if amount < 1 then return end
	if amount < 10 then fuelamount = string.sub(amount, 1, 1) else fuelamount = string.sub(amount, 1, 2) end
	local vehicle = GetClosestVehicle()
	if Config.AirAndWaterVehicleFueling['enabled'] then
		local vehClass = GetVehicleClass(vehicle)
		if vehClass == 14 then
			FuelPrice = Config.AirAndWaterVehicleFueling['water_fuel_price']
		elseif vehClass == 15 or vehClass == 16 then
			FuelPrice = Config.AirAndWaterVehicleFueling['air_fuel_price']
		end
	end
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
			if Config.FuelDebug then print("Before we apply the discount the FuelPrice is: $"..FuelPrice) end
			if discount ~= 0 then
				if discount == 100 then
					CachedFuelPrice = FuelPrice
					FuelPrice = 0
					if Config.FuelDebug then
						print("Your discount for Emergency Services is set @ | "..discount.."% | so fuel is free!")
					end
				else
					discount = discount / 100
					if Config.FuelDebug then
						print("Math( Current Fuel Price: "..FuelPrice.. " - " ..FuelPrice * discount.. "<<-- FuelPrice * Discount)")
					end

					CachedFuelPrice = FuelPrice
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
	local refillCost = (amount * FuelPrice) + GlobalTax(amount * FuelPrice)
	local ped = PlayerPedId()
	local time = amount * Config.RefuelTime
	if amount < 10 then time = 10 * Config.RefuelTime end
	local vehicleCoords = GetEntityCoords(vehicle)
	if inGasStation then
		if IsPlayerNearVehicle() then
			RequestAnimDict(Config.RefuelAnimationDictionary)
			while not HasAnimDictLoaded(Config.RefuelAnimationDictionary) do Wait(100) end
			if GetIsVehicleEngineRunning(vehicle) and Config.VehicleBlowUp then
				local Chance = math.random(1, 100)
				if Chance <= Config.BlowUpChance then
					AddExplosion(vehicleCoords, 5, 50.0, true, false, true)
					return
				end
			end
			if Config.FaceTowardsVehicle and RefuelingType ~= 'special' then
				local bootBoneIndex = GetEntityBoneIndexByName(vehicle --[[ Entity ]], 'boot' --[[ string ]])
				local vehBootCoords = GetWorldPositionOfEntityBone(vehicle --[[ Entity ]],  joaat(bootBoneIndex)--[[ integer ]])
				if Config.FuelDebug then
					print("Vehicle Boot Bone Coords: "..vehBootCoords.x, vehBootCoords.y, vehBootCoords.z)
				end
				TaskTurnPedToFaceCoord(PlayerPedId(), vehBootCoords, 500)
				Wait(500)
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
							MoneyToGiveBack = (GlobalTax(remainingamount * RefuelCancelledFuelCost) + (remainingamount * RefuelCancelledFuelCost))
							TriggerServerEvent("cdn-fuel:server:phone:givebackmoney", MoneyToGiveBack)
							CachedFuelPrice = nil
						else
							TriggerServerEvent('cdn-fuel:server:PayForFuel', refillCost, purchasetype, FuelPrice, false, CachedFuelPrice)
							CachedFuelPrice = nil
						end
						if RefuelingType == nil then
							if Config.PlayerOwnedGasStationsEnabled and not Config.UnlimitedFuel then
								TriggerServerEvent('cdn-fuel:station:server:updatereserves', "remove", finalrefuelamount, ReserveLevels, CurrentLocation)
								if CachedFuelPrice ~= nil then
									if Config.FuelDebug then
										print("We have a cached price: $"..CachedFuelPrice..", we will credit this to the gas station.")
									end
									TriggerServerEvent('cdn-fuel:station:server:updatebalance', "add", finalrefuelamount, StationBalance, CurrentLocation, CachedFuelPrice)
									CachedFuelPrice = nil
								else
									TriggerServerEvent('cdn-fuel:station:server:updatebalance', "add", finalrefuelamount, StationBalance, CurrentLocation, FuelPrice)
								end
							end
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
							RefuelCancelledFuelCost = 0
						end
						Cancelledrefuel = false
					end
				end
			end)
			TriggerServerEvent("InteractSound_SV:PlayOnSource", "refuel", 0.3)
			if lib.progressCircle({
				duration = time,
				label = locale('prog_refueling_vehicle'),
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
					TriggerServerEvent('cdn-fuel:server:PayForFuel', refillCost, purchasetype, FuelPrice, false, CachedFuelPrice)
				elseif purchasetype == "bank" then
					if not Config.RenewedPhonePayment or purchasetype == "cash" then 
						TriggerServerEvent('cdn-fuel:server:PayForFuel', refillCost, purchasetype, FuelPrice, false, CachedFuelPrice)
					end
				end
				local curfuel = GetFuel(vehicle)
				local finalfuel = (curfuel + fuelamount)
				if finalfuel > 99 and finalfuel < 100 then
					SetFuel(vehicle, 100)
				else
					SetFuel(vehicle, finalfuel)
				end
				if RefuelingType == nil then
					if Config.PlayerOwnedGasStationsEnabled and not Config.UnlimitedFuel then
						TriggerServerEvent('cdn-fuel:station:server:updatereserves', "remove", fuelamount, ReserveLevels, CurrentLocation)
						if CachedFuelPrice ~= nil then
							if Config.FuelDebug then
								print("We have a cached price: $"..CachedFuelPrice..", we will credit this to the gas station.")
							end
							TriggerServerEvent('cdn-fuel:station:server:updatebalance', "add", fuelamount, StationBalance, CurrentLocation, CachedFuelPrice)
							CachedFuelPrice = nil
						else
							TriggerServerEvent('cdn-fuel:station:server:updatebalance', "add", fuelamount, StationBalance, CurrentLocation, FuelPrice)
						end
					else
						if Config.FuelDebug then print("Config.PlayerOwnedGasStationsEnabled == false or Config.UnlimitedFuel == true, this means reserves will not be changed.") end
					end
					if Config.FuelDebug then print("Config.PlayerOwnedGasStationsEnabled == false or Config.UnlimitedFuel == true, this means reserves will not be changed.") end
				end
				StopAnimTask(ped, Config.RefuelAnimationDictionary, Config.RefuelAnimation, 3.0, 3.0, -1, 2, 0, 0, 0, 0)
				TriggerServerEvent("InteractSound_SV:PlayOnSource", "fuelstop", 0.4)
				if Config.RenewedPhonePayment then
					RefuelPossible = false
					RefuelPossibleAmount = 0
					RefuelPurchaseType = "bank"
				end
			else
				refueling = false
				Cancelledrefuel = true
				StopAnimTask(ped, Config.RefuelAnimationDictionary, Config.RefuelAnimation, 3.0, 3.0, -1, 2, 0, 0, 0, 0)
				TriggerServerEvent("InteractSound_SV:PlayOnSource", "fuelstop", 0.4)
			end
		else
			if lib.progressCircle({
				duration = 2000,
				position = 'bottom',
				useWhileDead = false,
				canCancel = true,
				disable = {
					car = true,
				},
				anim = {
					dict = 'mp_player_intdrink',
					clip = 'loop_bottle'
				},
				prop = {
					model = `prop_ld_flow_bottle`,
					pos = vec3(0.03, 0.03, 0.02),
					rot = vec3(0.0, 0.0, -1.5)
				},
			}) then 
				TriggerServerEvent('cdn-fuel:server:PayForFuel', refillCost, purchasetype, FuelPrice)
				local curfuel = GetFuel(vehicle)
				local finalfuel = (curfuel + fuelamount)
				if finalfuel > 99 and finalfuel < 100 then
					SetFuel(vehicle, 100)
				else
					SetFuel(vehicle, finalfuel)
				end
				if RefuelingType == nil then
					if Config.PlayerOwnedGasStationsEnabled and not Config.UnlimitedFuel then
						TriggerServerEvent('cdn-fuel:station:server:updatereserves', "remove", fuelamount, ReserveLevels, CurrentLocation)
						if CachedFuelPrice ~= nil then
							if Config.FuelDebug then
								print("We have a cached price: $"..CachedFuelPrice..", we will credit this to the gas station.")
							end
							TriggerServerEvent('cdn-fuel:station:server:updatebalance', "add", fuelamount, StationBalance, CurrentLocation, CachedFuelPrice)
							CachedFuelPrice = nil
						else
							TriggerServerEvent('cdn-fuel:station:server:updatebalance', "add", fuelamount, StationBalance, CurrentLocation, FuelPrice)
						end
					else
						if Config.FuelDebug then print("Config.PlayerOwnedGasStationsEnabled == false or Config.UnlimitedFuel == true, this means reserves will not be changed.") end
					end
				end
				StopAnimTask(ped, Config.RefuelAnimationDictionary, Config.RefuelAnimation, 3.0, 3.0, -1, 2, 0, 0, 0, 0)
				TriggerServerEvent("InteractSound_SV:PlayOnSource", "fuelstop", 0.4)
			else 
				refueling = false
				Cancelledrefuel = true
				StopAnimTask(ped, Config.RefuelAnimationDictionary, Config.RefuelAnimation, 3.0, 3.0, -1, 2, 0, 0, 0, 0)
				TriggerServerEvent("InteractSound_SV:PlayOnSource", "fuelstop", 0.4)
			end
		end
	else
		return
	end
end)

-- Jerry Can --
RegisterNetEvent('cdn-fuel:jerrycan:refuelmenu', function(itemData)
	if IsPedInAnyVehicle(PlayerPedId(), false) then 
		Notify("error", locale('fuelstation'), locale('cannot_refuel_inside'), "fas fa-search", 3000)
		return 
	end
	if Config.FuelDebug then print("Item Data: " .. json.encode(itemData)) end
	local vehicle = GetClosestVehicle()
	local vehiclecoords = GetEntityCoords(vehicle)
	local pedcoords = GetEntityCoords(PlayerPedId())
	if GetVehicleBodyHealth(vehicle) < 100 then
		Notify("error", locale('fuelstation'), locale('vehicle_is_damaged'), "fas fa-search", 3000)
		return 
	end
	local jerrycanamount = tonumber(itemData.metadata.cdn_fuel)
	--print(json.encode(itemData.metadata))
	--jerrycanamount = tonumber(itemData.metadata.cdn_fuel)
	
	
	if holdingnozzle then
		local fulltank
		if jerrycanamount == Config.JerryCanCap then fulltank = true
			GasString = locale('menu_jerry_can_footer_full_gas')
		else fulltank = false
			GasString = locale('menu_jerry_can_footer_refuel_gas')
		end

		lib.registerContext({
			id = 'cdnrefuelmenu',
			title = locale('menu_header_jerry_can'),
			options = {
				{
					title = locale('menu_header_refuel_jerry_can'),
					event = 'cdn-fuel:jerrycan:refueljerrycan',
					args = {itemData = itemData},
					disabled = fulltank
				},
			},
		})
		lib.showContext('cdnrefuelmenu')
	else
		if #(vehiclecoords - pedcoords) > 2.5 then return end
		local nogas
		if jerrycanamount < 1 then nogas = true
			GasString = locale('menu_jerry_can_footer_no_gas')
		else nogas = false
			GasString = locale('menu_jerry_can_footer_use_gas')
		end

		lib.registerContext({
			id = 'cdnrefuelmenu2',
			title = locale('menu_header_jerry_can'),
			options = {
				{
					title = locale('menu_header_refuel_vehicle'),
					event = 'cdn-fuel:jerrycan:refuelvehicle',
					args = {itemData = itemData},
					disabled = nogas,
				},
			},
		})
		lib.showContext('cdnrefuelmenu2')
	end
end)

RegisterNetEvent('cdn-fuel:client:jerrycanfinalmenu', function(purchasetype)
	Moneyamount = nil
	local bank, moneyY = lib.callback.await('cdn-fuel:getmoney')
	if purchasetype == 'bank' then
		Moneyamount = bank
	elseif purchasetype == 'cash' then
		Moneyamount = moneyY
	end
	if Moneyamount > math.ceil(Config.JerryCanPrice + GlobalTax(Config.JerryCanPrice)) then
		TriggerServerEvent('cdn-fuel:server:purchase:jerrycan', purchasetype)
	else
		if purchasetype == 'bank' then 
			Notify("error", locale('fuelstation'), locale('not_enough_money_in_bank'), "fas fa-search", 3000)
		end
		if purchasetype == "cash" then
			Notify("error", locale('fuelstation'), locale('not_enough_money_in_bank'), "fas fa-search", 3000)
		end
	end
end)

RegisterNetEvent('cdn-fuel:client:purchasejerrycan', function()
	local bank, playercashamount = lib.callback.await('cdn-fuel:getmoney')
	lib.registerContext({
		id = 'purchasejerrycan',
		title = locale('menu_jerry_can_purchase_header')..(math.ceil(Config.JerryCanPrice + GlobalTax(Config.JerryCanPrice))),
		options = {
			{
				title = locale('menu_header_cash'),
				description = locale('menu_pay_with_cash') .. playercashamount,
				icon = "fas fa-usd",
				event = 'cdn-fuel:client:jerrycanfinalmenu',
				args = 'cash',
			},
			{
				title = locale('menu_header_bank'),
				description = locale('menu_pay_with_bank') .. bank,
				icon = "fas fa-credit-card",
				event = 'cdn-fuel:client:jerrycanfinalmenu',
				args = 'bank',
			},
			{
				title = locale('menu_header_close'),
				description = locale('menu_jerry_can_close'),
				icon = "fas fa-times-circle",
				onSelect = function()
					lib.hideContext()
				end,
			},
		},
	})
	lib.showContext('purchasejerrycan')
end)

RegisterNetEvent('cdn-fuel:jerrycan:refuelvehicle', function(data)
	local ped = PlayerPedId()
	local vehicle = GetClosestVehicle()
	local vehfuel = math.floor(GetFuel(vehicle))
	local maxvehrefuel = (100 - math.ceil(vehfuel))
	local itemData = data.itemData
	local jerrycanfuelamount = tonumber(itemData.metadata.cdn_fuel)
	local vehicle = GetClosestVehicle()
	local NotElectric = false
	if Config.ElectricVehicleCharging then
		local isElectric = GetCurrentVehicleType(vehicle)
		if isElectric == 'electricvehicle' then
			Notify("error", locale('fuelstation'), locale('need_electric_charger'), "fas fa-search", 3000)
			return 
		end
		NotElectric = true
	else
		NotElectric = true
	end
	Wait(50)
	if NotElectric then
		if maxvehrefuel < Config.JerryCanCap then
			maxvehrefuel = maxvehrefuel
		else
			maxvehrefuel = Config.JerryCanCap
		end
		if maxvehrefuel >= jerrycanfuelamount then maxvehrefuel = jerrycanfuelamount elseif maxvehrefuel < jerrycanfuelamount then maxvehrefuel = maxvehrefuel end
		-- Need to Convert to OX --
	
		local refuel = lib.inputDialog(locale('input_select_refuel_header'), {locale('input_max_fuel_footer_1') .. maxvehrefuel .. locale('input_max_fuel_footer_2')})
		if not refuel then return end
		local refuelAmount = tonumber(refuel[1])
		-- 
		if refuel and refuelAmount then
			if tonumber(refuelAmount) == 0 then Notify("error", locale('fuelstation'), locale('more_than_zero'), "fas fa-search", 3000) return elseif tonumber(refuelAmount) < 0 then Notify("error", locale('fuelstation'), locale('more_than_zero'), "fas fa-search", 3000) end
			if tonumber(refuelAmount) > jerrycanfuelamount then Notify("error", locale('fuelstation'), locale('jerry_can_not_enough_fuel'), "fas fa-search", 3000) return end
			local refueltimer = Config.RefuelTime * tonumber(refuelAmount)
			if tonumber(refuelAmount) < 10 then refueltimer = Config.RefuelTime * 10 end
			if vehfuel + tonumber(refuelAmount) > 100 then Notify("error", locale('fuelstation'), locale('tank_cannot_fit'), "fas fa-search", 3000) return end
			local refuelAmount = tonumber(refuelAmount)
			JerrycanProp = CreateObject(joaat('w_am_jerrycan'), 1.0, 1.0, 1.0, true, true, false)
			local lefthand = GetPedBoneIndex(ped, 18905)
			AttachEntityToEntity(JerrycanProp, ped, lefthand, 0.11 --[[Left - Right (Kind of)]] , 0.0 --[[Up - Down]], 0.25 --[[Forward - Backward]], 15.0, 170.0, 90.42, 0, 1, 0, 1, 0, 1)
			if lib.progressCircle({
				duration = refueltimer,
				label = locale('prog_refueling_vehicle'),
				position = 'bottom',
				useWhileDead = false,
				canCancel = true,
				disable = {
					car = true,
					move = true,
					combat = true
				},
				anim = {
					dict = Config.JerryCanAnimDict,
					clip = Config.JerryCanAnim
				},
			}) then 
				DeleteObject(JerrycanProp)
				StopAnimTask(ped, Config.JerryCanAnimDict, Config.JerryCanAnim, 1.0)
				Notify("success", locale('fuelstation'), locale('jerry_can_success_vehicle'), "fas fa-search", 3000)
				local JerryCanItemData = data.itemData
				local srcPlayerData = ESX.PlayerData
				TriggerServerEvent('cdn-fuel:info', "remove", tonumber(refuelAmount), srcPlayerData, JerryCanItemData)
				SetFuel(vehicle, (vehfuel + refuelAmount))
			else 
				DeleteObject(JerrycanProp)
				StopAnimTask(ped, Config.JerryCanAnimDict, Config.JerryCanAnim, 1.0)
				Notify("error", locale('fuelstation'), locale('cancelled'), "fas fa-search", 3000)
			end
		end
	else
		Notify("error", locale('fuelstation'), locale('need_electric_charger'), "fas fa-search", 3000)
		return 
	end
end)

RegisterNetEvent('cdn-fuel:jerrycan:refueljerrycan', function(data)
	FetchStationInfo('all')
	Wait(100)
	if Config.PlayerOwnedGasStationsEnabled then
		FuelPrice = (1 * StationFuelPrice)
	else
		FuelPrice = (1 * Config.CostMultiplier)
	end
	local itemData = data.itemData
	local jerrycanfuelamount = itemData.metadata.cdn_fuel

	local ped = PlayerPedId()

	local JerryCanMaxRefuel = (Config.JerryCanCap - jerrycanfuelamount)
	--local refuel = lib.inputDialog(locale('input_select_refuel_header'), {locale('input_max_fuel_footer_1') .. JerryCanMaxRefuel .. locale('input_max_fuel_footer_2')})
	local refuel = lib.inputDialog(locale('input_select_refuel_header'), {   
        {type = 'slider', label = locale('input_max_fuel_footer_1'), description = locale('input_max_fuel_footer_2'), icon = 'jerrycan', min = 1, max = JerryCanMaxRefuel}
    })
	if not refuel then return end
	local refuelAmount = tonumber(refuel[1])
	if refuel then
		if tonumber(refuelAmount) == 0 then Notify("error", locale('fuelstation'), locale('more_than_zero'), "fas fa-search", 3000) return elseif tonumber(refuelAmount) < 0 then Notify("error", locale('fuelstation'), locale('more_than_zero'), "fas fa-search", 3000) return end
		if tonumber(refuelAmount) + tonumber(jerrycanfuelamount) > Config.JerryCanCap then Notify("error", locale('fuelstation'), locale('jerry_can_not_fit_fuel'), "fas fa-search", 3000) return end
		if tonumber(refuelAmount) > Config.JerryCanCap then Notify("error", locale('fuelstation'), locale('jerry_can_not_fit_fuel'), "fas fa-search", 3000) return end
		local refueltimer = Config.RefuelTime * tonumber(refuelAmount)
		if tonumber(refuelAmount) < 10 then refueltimer = Config.RefuelTime * 10 end
		local price = (tonumber(refuelAmount) * FuelPrice) + GlobalTax(tonumber(refuelAmount) * FuelPrice)
		if not CanAfford(price, "cash") then Notify("error", locale('fuelstation'), locale('not_enough_money_in_cash'), "fas fa-search", 3000) return end

		JerrycanProp = CreateObject(joaat('w_am_jerrycan'), 1.0, 1.0, 1.0, true, true, false)
		local lefthand = GetPedBoneIndex(ped, 18905)
		AttachEntityToEntity(JerrycanProp, ped, lefthand, 0.11 --[[Left - Right]] , 0.05--[[Up - Down]], 0.27 --[[Forward - Backward]], -15.0, 170.0, -90.42, 0, 1, 0, 1, 0, 1)
		SetEntityVisible(fuelnozzle, false, 0)
		if lib.progressCircle({
			duration = refueltimer,
			label = locale('prog_jerry_can_refuel'),
			position = 'bottom',
			useWhileDead = false,
			canCancel = true,
			disable = {
				car = true,
				move = true,
				combat = true
			},
			anim = {
				dict = Config.JerryCanAnimDict,
				clip = Config.JerryCanAnim
			},
		}) then 
			SetEntityVisible(fuelnozzle, true, 0)
			DeleteObject(JerrycanProp)
			StopAnimTask(ped, Config.JerryCanAnimDict, Config.JerryCanAnim, 1.0)
			Notify("success", locale('fuelstation'), locale('jerry_can_success'), "fas fa-search", 3000)
			local srcPlayerData = ESX.PlayerData
			if Config.Ox.Inventory then
				TriggerServerEvent('cdn-fuel:info', "add", tonumber(refuelAmount), srcPlayerData, itemData)
			else
				TriggerServerEvent('cdn-fuel:info', "add", tonumber(refuelAmount), srcPlayerData, itemData)
			end
			
			if Config.PlayerOwnedGasStationsEnabled and not Config.UnlimitedFuel then
				TriggerServerEvent('cdn-fuel:station:server:updatereserves', "remove", tonumber(refuelAmount), ReserveLevels, CurrentLocation)
				if CachedFuelPrice ~= nil then
					TriggerServerEvent('cdn-fuel:station:server:updatebalance', "add", tonumber(refuelAmount), StationBalance, CurrentLocation, CachedFuelPrice)
				else
					TriggerServerEvent('cdn-fuel:station:server:updatebalance', "add", tonumber(refuelAmount), StationBalance, CurrentLocation, FuelPrice)
				end
			else
				if Config.FuelDebug then print("Config.PlayerOwnedGasStationsEnabled == false or Config.UnlimitedFuel == true, this means reserves will not be changed.") end
			end
			local total = (tonumber(refuelAmount) * FuelPrice) + GlobalTax(tonumber(refuelAmount) * FuelPrice)
			TriggerServerEvent('cdn-fuel:server:PayForFuel', total, "cash", FuelPrice)
		else 
			SetEntityVisible(fuelnozzle, true, 0)
			DeleteObject(JerrycanProp)
			StopAnimTask(ped, Config.JerryCanAnimDict, Config.JerryCanAnim, 1.0)
			Notify("error", locale('fuelstation'), locale('cancelled'), "fas fa-search", 3000)
		end
	end
	
end)

--- Syphoning ---
local function PoliceAlert(coords)
	local chance = math.random(1, 100)
	if chance < Config.SyphonPoliceCallChance then
		if Config.SyphonDispatchSystem == "ps-dispatch" then
			exports['ps-dispatch']:SuspiciousActivity()
		elseif Config.SyphonDispatchSystem == "qb-dispatch" then
			TriggerServerEvent('qb-dispatch:911call', coords)
		elseif Config.SyphonDispatchSystem == "qb-default" then
			TriggerServerEvent('cdn-syphoning:callcops', coords)
		elseif Config.SyphonDispatchSystem == "custom" then
			-- Put your own dispatch system here
		else
			if Config.SyphonDebug then print("There was an attempt to call police but this dispatch system is not supported!") end
		end
	end
end

-- Events --
RegisterNetEvent('cdn-syphoning:syphon:menu', function(itemData)
	if IsPedInAnyVehicle(PlayerPedId(), false) then Notify("error", locale('fuelstation'), locale('syphon_inside_vehicle'), "fas fa-search", 3000) return end
	if Config.SyphonDebug then print("Item Data: " .. json.encode(itemData)) end
	local vehicle = GetClosestVehicle()
	local vehModel = GetEntityModel(vehicle)
	local vehiclename = string.lower(GetDisplayNameFromVehicleModel(vehModel))
	local vehiclecoords = GetEntityCoords(vehicle)
	local pedcoords = GetEntityCoords(PlayerPedId())
	if Config.ElectricVehicleCharging then
		NotElectric = true
		if Config.ElectricVehicles[vehiclename] and Config.ElectricVehicles[vehiclename].isElectric then
			NotElectric = false
			if Config.SyphonDebug then print("^2"..current.. "^5 has been found. It ^2matches ^5the Player's Vehicle: ^2"..vehiclename..". ^5This means syphoning will not be allowed.") end
			Notify("error", locale('fuelstation'), locale('syphon_electric_vehicle'), "fas fa-search", 3000)
			return
		end
	else
		NotElectric = true
	end
	if NotElectric then
		if #(vehiclecoords - pedcoords) > 2.5 then return end
		if GetVehicleBodyHealth(vehicle) < 100 then Notify("error", locale('fuelstation'), locale('vehicle_is_damaged'), "fas fa-search", 3000) return end
		local nogas
		local syphonfull

		if Config.Ox.Inventory then
			if tonumber(itemData.metadata.cdn_fuel) < 1 then nogas = true Nogasstring = locale('menu_syphon_empty') else nogas = false Nogasstring = locale('menu_syphon_refuel') end
			if tonumber(itemData.metadata.cdn_fuel) == Config.SyphonKitCap then syphonfull = true Stealfuelstring = locale('menu_syphon_kit_full') elseif GetFuel(vehicle) < 1 then syphonfull = true Stealfuelstring = locale('menu_syphon_vehicle_empty') else syphonfull = false Stealfuelstring = locale('menu_syphon_allowed') end -- Disable Options based on item data
		else
			if not itemData.info.gasamount then nogas = true Nogasstring = locale('menu_syphon_empty') end
			if itemData.info.gasamount < 1 then nogas = true Nogasstring = locale('menu_syphon_empty') else nogas = false Nogasstring = locale('menu_syphon_refuel') end
			if itemData.info.gasamount == Config.SyphonKitCap then syphonfull = true Stealfuelstring = locale('menu_syphon_kit_full') elseif GetFuel(vehicle) < 1 then syphonfull = true Stealfuelstring = locale('menu_syphon_vehicle_empty') else syphonfull = false Stealfuelstring = locale('menu_syphon_allowed') end -- Disable Options based on item data
		end
		if Config.Ox.Menu then
			lib.registerContext({
				id = 'syphoningmenu',
				title = 'Syphoning Kit',
				options = {
					{
						title = locale('menu_syphon_header'),
						description = Stealfuelstring,
						icon = "fas fa-fire-flame-simple",
						arrow = false, -- puts arrow to the right
						event = 'cdn-syphoning:syphon',
						args = {
							itemData = itemData,
							reason = "syphon",
						},
						disabled = syphonfull,
					},
					{
						title = locale('menu_syphon_refuel_header'),
						description = Nogasstring,
						icon = "fas fa-gas-pump",
						arrow = false, -- puts arrow to the right
						event = 'cdn-syphoning:syphon',
						args = {
							itemData = itemData,
							reason = "refuel",
						},
						disabled = nogas,
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
			lib.showContext('syphoningmenu')
		else
			exports['qb-menu']:openMenu({
				{
					header = "Syphoning Kit",
					isMenuHeader = true,
				},
				{
					header = locale('menu_syphon_header'),
					txt = Stealfuelstring,
					params = {
						event = "cdn-syphoning:syphon",
						args = {
							itemData = itemData,
							reason = "syphon",
						},
					},
					icon = "fas fa-fire-flame-simple",
					disabled = syphonfull,
				},
				{
					header = locale('menu_syphon_refuel_header'),
					txt = Nogasstring,
					icon = "fas fa-gas-pump",
					params = {
						event = "cdn-syphoning:syphon",
						args = {
							itemData = itemData,
							reason = "refuel",
						},
					},
					disabled = nogas,
				},
				{
					header = locale('menu_header_close'),
					txt = locale('menu_syphon_cancel'),
					icon = "fas fa-times-circle",
					params = {
						event = "qb-menu:closeMenu",
					}
				},
			})
		end
	end
end)

RegisterNetEvent('cdn-syphoning:syphon', function(data)
	local reason = data.reason
	local ped = PlayerPedId()
	if Config.SyphonDebug then print('Item Data Syphon: ' .. json.encode(data.itemData)) end
	if Config.SyphonDebug then print('Reason: ' .. reason) end
	local vehicle = GetClosestVehicle()
	local NotElectric = false
	if Config.ElectricVehicleCharging then
		local isElectric = GetCurrentVehicleType(vehicle)
		if isElectric == 'electricvehicle' then
			Notify("error", locale('fuelstation'), locale('need_electric_charger'), "fas fa-search", 3000)
			return
		end
		NotElectric = true
	else
		NotElectric = true
	end
	Wait(50)
	if NotElectric then
		local currentsyphonamount = tonumber(data.itemData.metadata.cdn_fuel)
		HasSyphon = exports.ox_inventory:Search('count', 'syphoningkit')

		if HasSyphon then
			local fitamount = (Config.SyphonKitCap - currentsyphonamount)
			local vehicle = GetClosestVehicle()
			local vehiclecoords = GetEntityCoords(vehicle)
			local pedcoords = GetEntityCoords(ped)
			if #(vehiclecoords - pedcoords) > 2.5 then return end
			local cargasamount = GetFuel(vehicle)
			local maxsyphon = math.floor(GetFuel(vehicle))
			if Config.SyphonKitCap <= 100 then
				if maxsyphon > Config.SyphonKitCap then
					maxsyphon = Config.SyphonKitCap
				end
			end
			if maxsyphon >= fitamount then
				Stealstring = fitamount
			else
				Stealstring = maxsyphon
			end
			if reason == "syphon" then
				syphon = lib.inputDialog('Begin Syphoning', {{ type = "number", label = "You can steal " .. Stealstring .. "L from the car.", default = Stealstring }})
				if not syphon then return end
				syphonAmount = tonumber(syphon[1])
				if syphon then
					if not syphonAmount then return end
					if tonumber(syphonAmount) < 0 then Notify("error", locale('fuelstation'), locale('syphon_more_than_zero'), "fas fa-search", 3000) return end
					if tonumber(syphonAmount) == 0 then Notify("error", locale('fuelstation'), locale('syphon_more_than_zero'), "fas fa-search", 3000) return end
					if tonumber(syphonAmount) > maxsyphon then Notify("error", locale('fuelstation'), locale('syphon_kit_cannot_fit_1').. fitamount .. locale('syphon_kit_cannot_fit_2'), "fas fa-search", 3000) return end
					if currentsyphonamount + syphonAmount > Config.SyphonKitCap then Notify("error", locale('fuelstation'), locale('syphon_kit_cannot_fit_1').. fitamount .. locale('syphon_kit_cannot_fit_2'), "fas fa-search", 3000) return end
					if (tonumber(syphonAmount) <= tonumber(cargasamount)) then
						local removeamount = (tonumber(cargasamount) - tonumber(syphonAmount))
						local syphontimer = Config.RefuelTime * syphonAmount
						if tonumber(syphonAmount) < 10 then syphontimer = Config.RefuelTime * 10 end
						if lib.progressCircle({
							duration = syphontimer,
							label = locale('prog_syphoning'),
							position = 'bottom',
							useWhileDead = false,
							canCancel = true,
							disable = {
								car = true,
								move = true,
								combat = true
							},
							anim = {
								dict = Config.StealAnimDict,
								clip = Config.StealAnim
							},
						}) then
							StopAnimTask(ped, Config.StealAnimDict, Config.StealAnim, 1.0)
							if GetFuel(vehicle) >= syphonAmount then
								PoliceAlert(GetEntityCoords(ped))
								Notify("success", locale('fuelstation'), locale('syphon_success'), "fas fa-search", 3000)
								SetFuel(vehicle, removeamount)
								local syphonData = data.itemData
								local srcPlayerData = ESX.PlayerData
								TriggerServerEvent('cdn-fuel:info', "add", tonumber(syphonAmount), srcPlayerData, syphonData)
							else
								Notify("error", locale('fuelstation'), locale('menu_syphon_vehicle_empty'), "fas fa-search", 3000)
							end
						else
							PoliceAlert(GetEntityCoords(ped))
							StopAnimTask(ped, Config.StealAnimDict, Config.StealAnim, 1.0)
							Notify("error", locale('fuelstation'), locale('cancelled'), "fas fa-search", 3000)
						end
					end
				end
			elseif reason == "refuel" then
				if 100 - math.ceil(cargasamount) < Config.SyphonKitCap then
					Maxrefuel = 100 - math.ceil(cargasamount)
					if Maxrefuel > currentsyphonamount then Maxrefuel = currentsyphonamount end
				else
					Maxrefuel = currentsyphonamount
				end
				refuel = lib.inputDialog(locale('input_select_refuel_header'), {{ type = "number", label = locale('input_max_fuel_footer_1') .. Maxrefuel .. locale('input_max_fuel_footer_2'), default = Maxrefuel }})

				if not refuel then return end
				refuelAmount = tonumber(refuel[1])
				if refuel then
					if tonumber(refuelAmount) == 0 then Notify("error", locale('fuelstation'), locale('more_than_zero'), "fas fa-search", 3000) return elseif tonumber(refuelAmount) < 0 then Notify("error", locale('fuelstation'), locale('more_than_zero'), "fas fa-search", 3000) return elseif tonumber(refuelAmount) > 100 then Notify("error", locale('fuelstation'), "Tak si kokot ,", "fas fa-search", 3000) return end
					if tonumber(refuelAmount) > tonumber(currentsyphonamount) then Notify("error", locale('fuelstation'), locale('syphon_not_enough_gas'), "fas fa-search", 3000) return end
					if tonumber(refuelAmount) + tonumber(cargasamount) > 100 then Notify("error", locale('fuelstation'), locale('tank_cannot_fit'), "fas fa-search", 3000) return end
					local refueltimer = Config.RefuelTime * tonumber(refuelAmount)
					if tonumber(refuelAmount) < 10 then refueltimer = Config.RefuelTime * 10 end
					if lib.progressCircle({
						duration = refueltimer,
						label = locale('prog_refueling_vehicle'),
						position = 'bottom',
						useWhileDead = false,
						canCancel = true,
						disable = {
							car = true,
							move = true,
							combat = true
						},
						anim = {
							dict = Config.JerryCanAnimDict,
							clip = Config.JerryCanAnim
						},
					}) then
						StopAnimTask(ped, Config.JerryCanAnimDict, Config.JerryCanAnim, 1.0)
						Notify("success", locale('fuelstation'), locale('syphon_success_vehicle'), "fas fa-search", 3000)
						SetFuel(vehicle, cargasamount + tonumber(refuelAmount))
						local syphonData = data.itemData
						local srcPlayerData = ESX.PlayerData
						TriggerServerEvent('cdn-fuel:info', "remove", tonumber(refuelAmount), srcPlayerData, syphonData)
					else
						StopAnimTask(ped, Config.JerryCanAnimDict, Config.JerryCanAnim, 1.0)
						Notify("error", locale('fuelstation'), locale('cancelled'), "fas fa-search", 3000)
					end
				end
			end
		else
			Notify("error", locale('fuelstation'), locale('syphon_no_syphon_kit'), "fas fa-search", 3000)
		end
	else
		Notify("error", locale('fuelstation'), locale('need_electric_charger'), "fas fa-search", 3000)
		return 
	end
end)

RegisterNetEvent('cdn-syphoning:client:callcops', function(coords)
	local PlayerJob = ESX.PlayerData.job.name
	if PlayerJob.name ~= "police" or not PlayerJob.onduty then return end
	local transG = 250
	local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
	SetBlipSprite(blip, 648)
	SetBlipColour(blip, 17)
	SetBlipDisplay(blip, 4)
	SetBlipAlpha(blip, transG)
	SetBlipScale(blip, 1.2)
	SetBlipFlashes(blip, true)
	BeginTextCommandSetBlipName('STRING')
	AddTextComponentString(locale('syphon_dispatch_string'))
	EndTextCommandSetBlipName(blip)
	while transG ~= 0 do
		Wait(180 * 4)
		transG = transG - 1
		SetBlipAlpha(blip, transG)
		if transG == 0 then
			SetBlipSprite(blip, 2)
			RemoveBlip(blip)
			return
		end
	end
end)

-- Helicopter Fueling --
RegisterNetEvent('cdn-fuel:client:grabnozzle:special', function()
	local ped = PlayerPedId()
	if HoldingSpecialNozzle then return end
	LoadAnimDict("anim@am_hold_up@male")
	TaskPlayAnim(ped, "anim@am_hold_up@male", "shoplift_high", 2.0, 8.0, -1, 50, 0, 0, 0, 0)
	TriggerServerEvent("InteractSound_SV:PlayOnSource", "pickupnozzle", 0.4)
	Wait(300)
	StopAnimTask(ped, "anim@am_hold_up@male", "shoplift_high", 1.0)
	SpecialFuelNozzleObj = CreateObject(joaat('prop_cs_fuel_nozle'), 1.0, 1.0, 1.0, true, true, false)
	local lefthand = GetPedBoneIndex(ped, 18905)
	AttachEntityToEntity(SpecialFuelNozzleObj, ped, lefthand, 0.13, 0.04, 0.01, -42.0, -115.0, -63.42, 0, 1, 0, 1, 0, 1)
	local grabbednozzlecoords = GetEntityCoords(ped)
	HoldingSpecialNozzle = true
	Notify("success", locale('fuelstation'), locale('show_input_key_special'), "fas fa-search", 3000)
	if Config.PumpHose then
		local pumpCoords, pump = GetClosestPump(grabbednozzlecoords)
		-- Load Rope Textures
		RopeLoadTextures()
		while not RopeAreTexturesLoaded() do
			Wait(0)
			RopeLoadTextures()
		end
		-- Wait for Pump to exist.
		while not pump do
			Wait(0)
		end
		Rope = AddRope(pumpCoords.x, pumpCoords.y, pumpCoords.z + 2.0, 0.0, 0.0, 0.0, 3.0, Config.RopeType['fuel'], 8.0 --[[ DO NOT SET THIS TO 0.0!!! GAME WILL CRASH!]], 0.0, 1.0, false, false, false, 1.0, true)
		while not Rope do
			Wait(0)
		end
		ActivatePhysics(Rope)
		Wait(100)
		local nozzlePos = GetEntityCoords(SpecialFuelNozzleObj)
		if Config.FuelDebug then print("NOZZLE POS ".. nozzlePos) end
		nozzlePos = GetOffsetFromEntityInWorldCoords(SpecialFuelNozzleObj, 0.0, -0.033, -0.195)
		AttachEntitiesToRope(Rope, pump, SpecialFuelNozzleObj, pumpCoords.x, pumpCoords.y, pumpCoords.z + 2.1, nozzlePos.x, nozzlePos.y, nozzlePos.z, length, false, false, nil, nil)
		
		if Config.FuelDebug then
			print("Hose Properties:")
			print(Rope, pump, SpecialFuelNozzleObj, pumpCoords.x, pumpCoords.y, pumpCoords.z, nozzlePos.x, nozzlePos.y, nozzlePos.z, length)
		
			SetEntityDrawOutline(SpecialFuelNozzleObj --[[ Entity ]], true --[[ boolean ]])
		end
	end
	CreateThread(function()
		while HoldingSpecialNozzle do
			local currentcoords = GetEntityCoords(ped)
			local dist = #(grabbednozzlecoords - currentcoords)
			TargetCreated = true
			if dist > Config.AirAndWaterVehicleFueling['nozzle_length'] or IsPedInAnyVehicle(ped, false) then
				HoldingSpecialNozzle = false
				DeleteObject(SpecialFuelNozzleObj)
				Notify("error", locale('fuelstation'), locale('nozzle_cannot_reach'), "fas fa-search", 3000)
				if Config.PumpHose then
					if Config.FuelDebug then print("Deleting Rope: "..tostring(Rope)) end
					RopeUnloadTextures()
					DeleteRope(Rope)
				end
				if Config.FuelNozzleExplosion then
					AddExplosion(grabbednozzlecoords.x, grabbednozzlecoords.y, grabbednozzlecoords.z, 'EXP_TAG_PROPANE', 1.0, true,false, 5.0)
					StartScriptFire(grabbednozzlecoords.x, grabbednozzlecoords.y, grabbednozzlecoords.z - 1,25,false)
					SetFireSpreadRate(10.0)
					Wait(5000)
					StopFireInRange(grabbednozzlecoords.x, grabbednozzlecoords.y, grabbednozzlecoords.z - 1, 3.0)
				end
			end
			Wait(2500)
		end
	end)
end)

RegisterNetEvent('cdn-fuel:client:returnnozzle:special', function()
	HoldingSpecialNozzle = false
	TriggerServerEvent("InteractSound_SV:PlayOnSource", "putbacknozzle", 0.4)
	Wait(250)
	DeleteObject(SpecialFuelNozzleObj)
	
	if Config.PumpHose then
		if Config.FuelDebug then print("Removing Hose.") end
		RopeUnloadTextures()
		DeleteRope(Rope)
	end
end)

local AirSeaFuelZones = {}
local vehicle = nil
-- Create Polyzones with In-Out functions for handling fueling --

AddEventHandler('onResourceStart', function(resource)
   if resource == GetCurrentResourceName() then
	  if LocalPlayer.state['isLoggedIn'] then
		for i = 1, #Config.AirAndWaterVehicleFueling['locations'], 1 do
			local currentLocation = Config.AirAndWaterVehicleFueling['locations'][i]
			local k = #AirSeaFuelZones+1
			local GeneratedName = "air_sea_fuel_zone_"..k
	
			AirSeaFuelZones[k] = {} -- Make a new table inside of the Vehicle Pullout Zones representing this zone.
	
			-- Get Coords for Zone from Config.
			AirSeaFuelZones[k].zoneCoords = currentLocation['PolyZone']['coords']
	
			-- Grab MinZ & MaxZ from Config.
			local minimumZ, maximumZ = currentLocation['PolyZone']['minmax']['min'], currentLocation['PolyZone']['minmax']['max']
	
			-- Create Zone
			AirSeaFuelZones[k].PolyZone = PolyZone:Create(AirSeaFuelZones[k].zoneCoords, {
				name = GeneratedName,
				minZ = minimumZ,
				maxZ = maximumZ,
				debugPoly = Config.PolyDebug
			})
	
			AirSeaFuelZones[k].name = GeneratedName
	
			-- Setup onPlayerInOut Events for zone that is created.
			AirSeaFuelZones[k].PolyZone:onPlayerInOut(function(isPointInside)
				if isPointInside then
					local canUseThisStation = false
					if Config.AirAndWaterVehicleFueling['locations'][i]['whitelist']['enabled'] then
						local whitelisted_jobs = Config.AirAndWaterVehicleFueling['locations'][i]['whitelist']['whitelisted_jobs']
						local plyJob = ESX.PlayerData.job.name
	
						if Config.FuelDebug then
							print("Player Job: "..plyJob.name.." Is on Duty?: "..json.encode(plyJob.onduty))
						end
	
						if type(whitelisted_jobs) == "table" then
							for i = 1, #whitelisted_jobs, 1 do
								if plyJob.name == whitelisted_jobs[i] then
									if Config.AirAndWaterVehicleFueling['locations'][i]['whitelist']['on_duty_only'] then
										if plyJob.onduty == true then
											canUseThisStation = true
										else
											canUseThisStation = false
										end
									else
										canUseThisStation = true
									end
								end
							end
						end
					else
						canUseThisStation = true
					end
	
					if canUseThisStation then
						-- Inside
						PlayerInSpecialFuelZone = true
						inGasStation = true
						RefuelingType = 'special'
	
						local DrawText = Config.AirAndWaterVehicleFueling['locations'][i]['draw_text']
	
						if Config.Ox.DrawText then
							lib.showTextUI(DrawText, {
								position = 'left-center'
							})
						else
							exports[Config.Core]:DrawText(DrawText, 'left')
						end
						
						CreateThread(function()
							while PlayerInSpecialFuelZone do
								Wait(3000)
								vehicle = GetClosestVehicle()
							end
						end)
	
						CreateThread(function()
							while PlayerInSpecialFuelZone do
								Wait(0)
								if PlayerInSpecialFuelZone ~= true then
									break
								end
								if IsControlJustReleased(0, Config.AirAndWaterVehicleFueling['refuel_button']) --[[ Control in Config ]] then
									local vehCoords = GetEntityCoords(vehicle)
									local dist = #(GetEntityCoords(PlayerPedId()) - vehCoords) 
									
									if not HoldingSpecialNozzle then
										Notify("error", locale('fuelstation'), locale('no_nozzle'), "fas fa-search", 3000)
									elseif dist > 4.5 then
										Notify("error", locale('fuelstation'), locale('vehicle_too_far'), "fas fa-search", 3000)
									elseif IsPedInAnyVehicle(PlayerPedId(), true) then 
										Notify("error", locale('fuelstation'), locale('inside_vehicle'), "fas fa-search", 3000)
									else
										if Config.FuelDebug then print("Attempting to Open Fuel menu for special vehicles.") end
										TriggerEvent('cdn-fuel:client:RefuelMenu', 'special')
									end
								end
							end
						end)
	
						if Config.FuelDebug then
							print('Player has entered the Heli or Plane Refuel Zone: ('..GeneratedName..')')
						end
					end
				else
					if HoldingSpecialNozzle then
						Notify("error", locale('fuelstation'), locale('nozzle_cannot_reach'), "fas fa-search", 3000)
						HoldingSpecialNozzle = false
						if Config.PumpHose then
							if Config.FuelDebug then
								print("Deleting Rope: "..Rope)
							end
							RopeUnloadTextures()
							DeleteObject(Rope)
						end
						DeleteObject(SpecialFuelNozzleObj)
					end
					if Config.PumpHose then
						if Rope ~= nil then 
							if Config.FuelDebug then
								print("Deleting Rope: "..Rope)
							end
							RopeUnloadTextures()
							DeleteObject(Rope)
						end
					end
					-- Outside
					if Config.Ox.DrawText then
						lib.hideTextUI()
					else
						exports[Config.Core]:HideText()
					end
					PlayerInSpecialFuelZone = false
					inGasStation = false
					RefuelingType = nil
					if Config.FuelDebug then
						print('Player has exited the Heli or Plane Refuel Zone: ('..GeneratedName..')')
					end
				end
			end)
	
			if currentLocation['prop'] then
				local model = currentLocation['prop']['model']
				local modelCoords = currentLocation['prop']['coords']
				local heading = modelCoords[4] - 180.0
				AirSeaFuelZones[k].prop = CreateObject(model, modelCoords.x, modelCoords.y, modelCoords.z, false, true, true)
				if Config.FuelDebug then print("Created Special Pump from Location #"..i) end
				SetEntityHeading(AirSeaFuelZones[k].prop, heading)
				FreezeEntityPosition(AirSeaFuelZones[k].prop, 1)
			else
				if Config.FuelDebug then print("Location #"..i.." for Special Fueling Zones (Air and Sea) doesn't have a prop set up, so players cannot fuel here.") end
			end
	
			if Config.FuelDebug then
				print("Created Location: "..GeneratedName)
			end
		end
	  end
   end
end)

AddEventHandler("esx:playerLoaded", function ()	
	for i = 1, #Config.AirAndWaterVehicleFueling['locations'], 1 do
		local currentLocation = Config.AirAndWaterVehicleFueling['locations'][i]
		local k = #AirSeaFuelZones+1
		local GeneratedName = "air_sea_fuel_zone_"..k

		AirSeaFuelZones[k] = {} -- Make a new table inside of the Vehicle Pullout Zones representing this zone.

		-- Get Coords for Zone from Config.
		AirSeaFuelZones[k].zoneCoords = currentLocation['PolyZone']['coords']

		-- Grab MinZ & MaxZ from Config.
		local minimumZ, maximumZ = currentLocation['PolyZone']['minmax']['min'], currentLocation['PolyZone']['minmax']['max']

		-- Create Zone
		AirSeaFuelZones[k].PolyZone = PolyZone:Create(AirSeaFuelZones[k].zoneCoords, {
			name = GeneratedName,
			minZ = minimumZ,
			maxZ = maximumZ,
			debugPoly = Config.PolyDebug
		})

		AirSeaFuelZones[k].name = GeneratedName

		-- Setup onPlayerInOut Events for zone that is created.
		AirSeaFuelZones[k].PolyZone:onPlayerInOut(function(isPointInside)
			if isPointInside then
				local canUseThisStation = false
				if Config.AirAndWaterVehicleFueling['locations'][i]['whitelist']['enabled'] then
					local whitelisted_jobs = Config.AirAndWaterVehicleFueling['locations'][i]['whitelist']['whitelisted_jobs']
					local plyJob = ESX.PlayerData.job.name

					if Config.FuelDebug then
						print("Player Job: "..plyJob.name.." Is on Duty?: "..json.encode(plyJob.onduty))
					end

					if type(whitelisted_jobs) == "table" then
						for i = 1, #whitelisted_jobs, 1 do
							if plyJob.name == whitelisted_jobs[i] then
								if Config.AirAndWaterVehicleFueling['locations'][i]['whitelist']['on_duty_only'] then
									if plyJob.onduty == true then
										canUseThisStation = true
									else
										canUseThisStation = false
									end
								else
									canUseThisStation = true
								end
							end
						end
					end
				else
					canUseThisStation = true
				end

				if canUseThisStation then
					-- Inside
					PlayerInSpecialFuelZone = true
					inGasStation = true
					RefuelingType = 'special'

					local DrawText = Config.AirAndWaterVehicleFueling['locations'][i]['draw_text']

					if Config.Ox.DrawText then
						lib.showTextUI(DrawText, {
							position = 'left-center'
						})
					else
						exports[Config.Core]:DrawText(DrawText, 'left')
					end

					CreateThread(function()
						while PlayerInSpecialFuelZone do
							Wait(3000)
							vehicle = GetClosestVehicle()
						end
					end)

					CreateThread(function()
						while PlayerInSpecialFuelZone do
							Wait(0)
							if PlayerInSpecialFuelZone ~= true then
								break
							end
							if IsControlJustReleased(0, Config.AirAndWaterVehicleFueling['refuel_button']) --[[ Control in Config ]] then
								local vehCoords = GetEntityCoords(vehicle)
								local dist = #(GetEntityCoords(PlayerPedId()) - vehCoords)

								if not HoldingSpecialNozzle then
									Notify("error", locale('fuelstation'), locale('no_nozzle'), "fas fa-search", 3000)
								elseif dist > 4.5 then
									Notify("error", locale('fuelstation'), locale('vehicle_too_far'), "fas fa-search", 3000)
								elseif IsPedInAnyVehicle(PlayerPedId(), true) then 
									Notify("error", locale('fuelstation'), locale('inside_vehicle'), "fas fa-search", 3000)
								else
									if Config.FuelDebug then print("Attempting to Open Fuel menu for special vehicles.") end
									TriggerEvent('cdn-fuel:client:RefuelMenu', 'special')
								end
							end
						end
					end)

					if Config.FuelDebug then
						print('Player has entered the Heli or Plane Refuel Zone: ('..GeneratedName..')')
					end
				end
			else
				if HoldingSpecialNozzle then
					Notify("error", locale('fuelstation'), locale('nozzle_cannot_reach'), "fas fa-search", 3000)
					HoldingSpecialNozzle = false
					if Config.PumpHose then
						if Config.FuelDebug then
							print("Deleting Rope: "..Rope)
						end
						RopeUnloadTextures()
						DeleteObject(Rope)
					end
					DeleteObject(SpecialFuelNozzleObj)
				end
				if Config.PumpHose then
					if Rope ~= nil then 
						if Config.FuelDebug then
							print("Deleting Rope: "..Rope)
						end
						RopeUnloadTextures()
						DeleteObject(Rope)
					end
				end
				-- Outside
				lib.hideTextUI()
				
				PlayerInSpecialFuelZone = false
				inGasStation = false
				RefuelingType = nil
				if Config.FuelDebug then
					print('Player has exited the Heli or Plane Refuel Zone: ('..GeneratedName..')')
				end
			end
		end)

		if currentLocation['prop'] then
			local model = currentLocation['prop']['model']
			local modelCoords = currentLocation['prop']['coords']
			local heading = modelCoords[4] - 180.0
			AirSeaFuelZones[k].prop = CreateObject(model, modelCoords.x, modelCoords.y, modelCoords.z, false, true, true)
			if Config.FuelDebug then print("Created Special Pump from Location #"..i) end
			SetEntityHeading(AirSeaFuelZones[k].prop, heading)
			FreezeEntityPosition(AirSeaFuelZones[k].prop, 1)
		else
			if Config.FuelDebug then print("Location #"..i.." for Special Fueling Zones (Air and Sea) doesn't have a prop set up, so players cannot fuel here.") end
		end

		if Config.FuelDebug then
			print("Created Location: "..GeneratedName)
		end
	end
end)

--[[AddEventHandler("QBCore:Client:OnPlayerUnload", function()
	for i = 1, #AirSeaFuelZones, 1 do
		AirSeaFuelZones[i].PolyZone:destroy()
		if Config.FuelDebug then
			print("Destroying Air Fuel PolyZone: "..AirSeaFuelZones[i].name)
		end
		if AirSeaFuelZones[i].prop then
			if Config.FuelDebug then
				print("Destroying Air Fuel Zone Pump: "..i)
			end
			DeleteObject(AirSeaFuelZones[i].prop)
		end
	end
end)]]

AddEventHandler('onResourceStop', function(resource)
	if resource == GetCurrentResourceName() then
		for i = 1, #AirSeaFuelZones, 1 do
			AirSeaFuelZones[i].PolyZone:destroy()
			DeleteObject(AirSeaFuelZones[i].prop)
		end
	end
end)

CreateThread(function()
	local bones = {
		"petroltank",
		"petroltank_l",
		"petroltank_r",
		"wheel_rf",
		"wheel_rr",
		"petrolcap ",
		"seat_dside_r",
		"engine",
	}

	local options = {
		[1] = {
			name = 'cdn-fuel:options:1',
			icon = "fas fa-gas-pump",
			label = tostring(locale('input_insert_nozzle')),
			canInteract = function()
				if inGasStation and not refueling and holdingnozzle then
					return true
				end
			end,
			event = 'cdn-fuel:client:RefuelMenu'
		},
		[2] = {
			name = 'cdn-fuel:options:2',
			icon = "fas fa-bolt",
			label = tostring(locale('insert_electric_nozzle')),
			canInteract = function()
				if Config.ElectricVehicleCharging == true then
					if inGasStation and not refueling and IsHoldingElectricNozzle() then
						return true
					else
						return false
					end
				else
					return false
				end
			end,
			event = "cdn-fuel:client:electric:RefuelMenu",
		}
	}

	exports.ox_target:addGlobalVehicle(options)

	local modelOptions = {
		[1] = {
			name = "cdn-fuel:modelOptions:option_1",
			num = 1,
			type = "client",
			event = "cdn-fuel:client:grabnozzle",
			icon = "fas fa-gas-pump",
			label = locale('grab_nozzle'),
			canInteract = function()
				if PlayerInSpecialFuelZone then return false end
				if not IsPedInAnyVehicle(PlayerPedId()) and not holdingnozzle and not HoldingSpecialNozzle and inGasStation == true and not PlayerInSpecialFuelZone then
					return true
				end
			end,
		},
		[2] = {
			name = "cdn-fuel:modelOptions:option_2",
			num = 2,
			type = "client",
			event = "cdn-fuel:client:purchasejerrycan",
			icon = "fas fa-fire-flame-simple",
			label = locale('buy_jerrycan'),
			canInteract = function()
				if not IsPedInAnyVehicle(PlayerPedId()) and not holdingnozzle and not HoldingSpecialNozzle and inGasStation == true then
					return true
				end
			end,
		},
		[3] = {
			name = "cdn-fuel:modelOptions:option_3",
			num = 3,
			type = "client",
			event = "cdn-fuel:client:returnnozzle",
			icon = "fas fa-hand",
			label = locale('return_nozzle'),
			canInteract = function()
				if holdingnozzle and not refueling then
					return true
				end
			end,
		},
		[4] = {
			name = "cdn-fuel:modelOptions:option_4",
			num = 4,
			type = "client",
			event = "cdn-fuel:client:grabnozzle:special",
			icon = "fas fa-gas-pump",
			label = locale('grab_special_nozzle'),
			canInteract = function()
				if Config.FuelDebug then print("Is Player In Special Fuel Zone?: "..tostring(PlayerInSpecialFuelZone)) end
				if not HoldingSpecialNozzle and not IsPedInAnyVehicle(PlayerPedId()) and PlayerInSpecialFuelZone then
					return true
				end
			end,
		},
		[5] = {
			name = "cdn-fuel:modelOptions:option_5",
			num = 5,
			type = "client",
			event = "cdn-fuel:client:returnnozzle:special",
			icon = "fas fa-hand",
			label = locale('return_special_nozzle'),
			canInteract = function()
				if HoldingSpecialNozzle and not IsPedInAnyVehicle(PlayerPedId()) then
					return true
				end
			end
		},
	}

	exports.ox_target:addModel(props, modelOptions)
	
end)

CreateThread(function()
	while true do
		Wait(3000)
		local vehPedIsIn = GetVehiclePedIsIn(PlayerPedId(), false)
		if not vehPedIsIn or vehPedIsIn == 0 then
			Wait(2500)
			if inBlacklisted then
				inBlacklisted = false
			end
		else
			local vehType = GetCurrentVehicleType(vehPedIsIn)
			if not Config.ElectricVehicleCharging and vehType == 'electricvehicle' then
				if Config.FuelDebug then
					print("Vehicle Type is Electric, so we will not remove shut the engine off.")
				end
			else
				if not IsVehicleBlacklisted(vehPedIsIn) then
					local vehFuelLevel = GetFuel(vehPedIsIn)
					local vehFuelShutoffLevel = Config.VehicleShutoffOnLowFuel['shutOffLevel'] or 1
					if vehFuelLevel <= vehFuelShutoffLevel then
						if GetIsVehicleEngineRunning(vehPedIsIn) then
							if Config.FuelDebug then
								print("Vehicle is running with zero fuel, shutting it down.")
							end
							-- If the vehicle is on, we shut the vehicle off:
							SetVehicleEngineOn(vehPedIsIn, false, true, true)
							-- Then alert the client with notify.
							Notify("error", locale('fuelstation'), locale('no_fuel'), "fas fa-search", 3000)
							-- Play Sound, if enabled in config.
							if Config.VehicleShutoffOnLowFuel['sounds']['enabled'] then
								RequestAmbientAudioBank("DLC_PILOT_ENGINE_FAILURE_SOUNDS", 0)
								PlaySoundFromEntity(l_2613, "Landing_Tone", vehPedIsIn, "DLC_PILOT_ENGINE_FAILURE_SOUNDS", 0, 0)
								Wait(1500)
								StopSound(l_2613)
							end
						end
					else
						if vehFuelLevel - 10 > vehFuelShutoffLevel then
							Wait(7500)
						end
					end
				end
			end
		end
	end
end)

if Config.VehicleShutoffOnLowFuel['shutOffLevel'] == 0 then
	Config.VehicleShutoffOnLowFuel['shutOffLevel'] = 0.55
end

-- This loop does use quite a bit of performance, but,
-- is needed due to electric vehicles running without fuel & normal vehicles driving backwards!
-- You can remove if you need the performance, but we believe it is very important.
CreateThread(function()
	while true do
		Wait(0)
		local ped = PlayerPedId()
		local veh = GetVehiclePedIsIn(ped, false)
		if veh ~= 0 and veh ~= nil then
			if not IsVehicleBlacklisted(veh) then
				-- Check if we are below the threshold for the Fuel Shutoff Level, if so, disable the "W" key, if not, enable it again.
				if IsPedInVehicle(ped, veh, false) and (GetIsVehicleEngineRunning(veh) == false) or GetFuel(veh) < (Config.VehicleShutoffOnLowFuel['shutOffLevel'] or 1) then
					DisableControlAction(0, 71, true)
				elseif IsPedInVehicle(ped, veh, false) and (GetIsVehicleEngineRunning(veh) == true) and GetFuel(veh) > (Config.VehicleShutoffOnLowFuel['shutOffLevel'] or 1) then
					EnableControlAction(0, 71, true)
				end
				-- Now, we check if the fuel level is currently 5 above the level it should shut off,
				-- if this is true, we will then enable the "W" key if currently disabled, and then,
				-- we will add a 5 second wait, in order to reduce system impact.
				if GetFuel(veh) > (Config.VehicleShutoffOnLowFuel['shutOffLevel'] + 5) then
					if not IsControlEnabled(0, 71) then
						-- Enable "W" Key if it is currently disabled.
						EnableControlAction(0, 71, true)
					end
					Wait(5000)
				end
			end
		else
			-- 1.75 Second Cooldown if the player is not inside of a vehicle.
			Wait(1750)
		end
	end
end)
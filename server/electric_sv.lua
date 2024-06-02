-- Variables
local ESX = exports["es_extended"]:getSharedObject()
lib.locale()

-- Functions
local function GlobalTax(value)
	local tax = (value / 100 * Config.GlobalTax)
	return tax
end

-- Events
RegisterNetEvent("cdn-fuel:server:electric:OpenMenu", function(amount, inGasStation, hasWeapon, purchasetype, FuelPrice)
	local src = source
	if not src then print("SRC is nil!") return end
	local player = ESX.GetPlayerFromId(src)
	if not player then print("Player is nil!") return end
	local FuelCost = amount*FuelPrice
	local tax = GlobalTax(FuelCost)
	local total = tonumber(FuelCost + tax)
	if not amount then if Config.FuelDebug then print("Electric Recharge Amount is invalid!") end 
		TriggerClientEvent("cdn-fuel:notifysv", src, 'error', locale('fuelstation'), locale('electric_more_than_zero'), "idk", 2000)
		return 
	end
	Wait(50)
	if inGasStation and not hasWeapon then
		TriggerClientEvent('cdn-electric:client:OpenContextMenu', src, math.ceil(total), amount, purchasetype)
	end
end)

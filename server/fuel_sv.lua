-- Variables
local ESX = exports["es_extended"]:getSharedObject()

-- Functions
local function GlobalTax(value)
	local tax = (value / 100 * Config.GlobalTax)
	return tax
end

RegisterNetEvent("cdn-fuel:server:OpenMenu", function(amount, inGasStation, hasWeapon, purchasetype, FuelPrice)
	local src = source
	if not src then return end
	local player = ESX.GetPlayerFromId(src)
	if not player then return end
	if not amount then if Config.FuelDebug then print("Amount is invalid!") end 
		TriggerClientEvent("cdn-fuel:notifysv", src, 'error', locale('fuelstation'), locale('more_than_zero'), "idk", 3000)
		return 
	end
	local FuelCost = amount*FuelPrice
	local tax = GlobalTax(FuelCost)
	local total = tonumber(FuelCost + tax)
	if inGasStation == true and not hasWeapon then
		if Config.FuelDebug then print("going to open the context menu (OX)") end
		TriggerClientEvent('cdn-fuel:client:OpenContextMenu', src, total, amount, purchasetype)
	end
end)

RegisterNetEvent("cdn-fuel:server:PayForFuel", function(amount, purchasetype, FuelPrice, electric)
	local src = source
	if not src then return end
	local Player = ESX.GetPlayerFromId(src)
	if not Player then return end
	local total = math.ceil(amount)
	if amount < 1 then
		total = 0
	end
	local moneyremovetype = purchasetype
	if Config.FuelDebug then print("Player is attempting to purchase fuel with the money type: " ..moneyremovetype) end
	if Config.FuelDebug then print("Attempting to charge client: $"..total.." for Fuel @ "..FuelPrice.." PER LITER | PER KW") end
	if purchasetype == "bank" then
		moneyremovetype = "bank"
	elseif purchasetype == "cash" then
		moneyremovetype = "money"
	end
	local payString = locale('menu_pay_label_1') .. FuelPrice .. locale('menu_pay_label_2')
	if electric then payString = locale('menu_electric_payment_label_1') .. FuelPrice .. locale('menu_electric_payment_label_2') end
	TriggerClientEvent("cdn-fuel:notifysv", src, 'success', locale('fuelstation'), payString, "idk", 3000)
	Player.removeAccountMoney(moneyremovetype, total)
end)

RegisterNetEvent("cdn-fuel:server:purchase:jerrycan", function(purchasetype)
	local src = source if not src then return end
	local Player = ESX.GetPlayerFromId(src) if not Player then return end
	local tax = GlobalTax(Config.JerryCanPrice) local total = math.ceil(Config.JerryCanPrice + tax)
	local moneyremovetype = purchasetype
	if purchasetype == "bank" then
		moneyremovetype = "bank"
	elseif purchasetype == "cash" then
		moneyremovetype = "money"
	end

	local info = {cdn_fuel = tostring(Config.JerryCanGas)}
	exports.ox_inventory:AddItem(src, 'jerrycan', 1, info)
	local hasItem = exports.ox_inventory:GetItem(src, 'jerrycan', info, 1)
	if hasItem then
		Player.removeAccountMoney(moneyremovetype, total)
	end
end)

--- Jerry Can
--[[if Config.UseJerryCan then
	RegisterUsable("jerrycan", function(source)
		local src = source
		TriggerClientEvent('cdn-fuel:jerrycan:refuelmenu', src, item)
	end)
end]]

--- Syphoning
--[[if Config.UseSyphoning then
	QBCore.Functions.CreateUseableItem("syphoningkit", function(source, item)
		local src = source
		if Config.Ox.Inventory then
			if item.metadata.cdn_fuel == nil then
				item.metadata.cdn_fuel = '0'
				exports.ox_inventory:SetMetadata(src, item.slot, item.metadata)
			end
		end
		TriggerClientEvent('cdn-syphoning:syphon:menu', src, item)
	end)
end]]

RegisterNetEvent('cdn-fuel:info', function(type, amount, srcPlayerData, itemdata)
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    local srcPlayerData = srcPlayerData
	local ItemName = itemdata.name

	if itemdata == "jerrycan" then
		if amount < 1 or amount > Config.JerryCanCap then if Config.FuelDebug then print("Error, amount is invalid (< 1 or > "..Config.SyphonKitCap..")! Amount:" ..amount) end return end
	elseif itemdata == "syphoningkit" then
		if amount < 1 or amount > Config.SyphonKitCap then if Config.SyphonDebug then print("Error, amount is invalid (< 1 or > "..Config.SyphonKitCap..")! Amount:" ..amount) end return end
	end
	if ItemName ~= nil then
		itemdata.metadata = itemdata.metadata
		itemdata.slot = itemdata.slot
		if ItemName == 'jerrycan' then
			local fuel_amount = tonumber(itemdata.metadata.cdn_fuel)
			if type == "add" then
				fuel_amount = fuel_amount + amount
				itemdata.metadata.cdn_fuel = tostring(fuel_amount)
				exports.ox_inventory:SetMetadata(src, itemdata.slot, itemdata.metadata)
			elseif type == "remove" then
				fuel_amount = fuel_amount - amount
				itemdata.metadata.cdn_fuel = tostring(fuel_amount)
				exports.ox_inventory:SetMetadata(src, itemdata.slot, itemdata.metadata)
			else
				if Config.FuelDebug then print("error, type is invalid!") end
			end
		elseif ItemName == 'syphoningkit' then
			local fuel_amount = tonumber(itemdata.metadata.cdn_fuel)
			if type == "add" then
				fuel_amount = fuel_amount + amount
				itemdata.metadata.cdn_fuel = tostring(fuel_amount)
				exports.ox_inventory:SetMetadata(src, itemdata.slot, itemdata.metadata)
			elseif type == "remove" then
				fuel_amount = fuel_amount - amount
				itemdata.metadata.cdn_fuel = tostring(fuel_amount)
				exports.ox_inventory:SetMetadata(src, itemdata.slot, itemdata.metadata)
			else
				if Config.SyphonDebug then print("error, type is invalid!") end
			end
		end
	else
		if Config.FuelDebug then
			print("ItemName is invalid!")
		end
	end
end)

RegisterNetEvent('cdn-syphoning:callcops', function(coords)
    TriggerClientEvent('cdn-syphoning:client:callcops', -1, coords)
end)

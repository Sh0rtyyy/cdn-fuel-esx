lib.callback.register('cdn-fuel:getmoney', function()
    local src = source

    local xPlayer = ESX.GetPlayerFromId(src)
    local money = xPlayer.getAccount('money')
    local bank = xPlayer.getAccount('bank')

    local moneyamout = money.money
    local bankamount = bank.money

    return bankamount, moneyamout
end)

lib.callback.register('cdn-fuel:requestIdentifier', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)

    local char = xPlayer.getIdentifier(src)
    return char
end)

--- Update Alerts
local updatePath
local resourceName

local function checkVersion(err, responseText, headers)
    local curVersion = LoadResourceFile(GetCurrentResourceName(), "version")
	if responseText == nil then print("^1"..resourceName.." check for updates failed ^7") return end
    if curVersion ~= nil and responseText ~= nil then
		if curVersion == responseText then Color = "^2" else Color = "^1" end
        print("\n^1----------------------------------------------------------------------------------^7")
        print(resourceName.."'s latest version is: ^2"..responseText.."!\n^7Your current version: "..Color..""..curVersion.."^7!\nIf needed, update from https://github.com"..updatePath.."")
        print("^1----------------------------------------------------------------------------------^7")
    end
end

CreateThread(function()
	updatePath = "/Sh0rtyyy/cdn-fuel-esx"
	resourceName = "cdn-fuel ("..GetCurrentResourceName()..")"
	PerformHttpRequest("https://raw.githubusercontent.com"..updatePath.."/master/version", checkVersion, "GET")
end)

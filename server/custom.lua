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
![Codine Development Fuel Script Banner](https://i.imgur.com/qVOMMvW.png)

# _CDN-Fuel (2.1.9)_ 

A highly in-depth fuel system for **FiveM** with support for the **QBCore Framework & QBox Remastered**.

# _Lastest Patch Information_

*Fixes:*
- Jerry Cans not refuelling at pump.
- Removed spamming debug print. 
- Changed the way Air Fuel Zones spawn PolyZones and Props.
- Player Job Error on load.


<br>
<br>

![Codine Development Fuel Script Features Banner](https://i.imgur.com/ISHQJUL.png)

#### Why should you pick **cdn-fuel**?

- Show all gas station blips via Config Options.
- Vehicle blowing up chance percent via Config Options.
- Pump Explosion Chance when running away with Nozzles via Config Options.
- Global Tax and Fuel Prices via Config Options.
- Target eye for all base fuel actions, not including Jerry Can & Syphoning.
- Fuel and Charging Nozzle with realistic animations.
- Custom sounds for every action, like refueling & charging.
- Select amount of fuel you want to put in your vehicle.
- On cancel, the amount you put in will be filled.
- Option to pay cash or with your bank.
- Toggleable Jerry Cans via Config Options.
- Electric Charging with a [Custom Model](https://i.imgur.com/WDxGoT6.png) & pre-configured locations.
- [Player Owned Gas Stations](https://www.youtube.com/watch?v=3glln0S2QXo) that can be maintained by the Owner.
- [Highly User Friendly Menus](https://i.imgur.com/f64IxpA.png) for Gas Station Owners.
- Reserve Levels which are maintained by the Owner of the Gas Station or Unlimited based on Config Options.
- Renamable Gas Stations on Map with Blacklisted words.
- Helicopter and Boat Refueling.
- Configurable discounts for Emergency Services.
- Configurable Hose for the Fuel Nozzle.
- Official Support for the [OX Library](https://github.com/overextended/ox_lib). (Inventory/Menus/Target)


![Codine Development Fuel Script Install Banner](https://i.imgur.com/bEiV8G0.png)

### Before your installation:
Make sure you have the following dependencies, otherwise, issues most likely will arise:

### Dependencies:

- [ox-target](https://github.com/overextended/ox_target)
- [ox_lib](https://github.com/overextended/ox_lib)
- [interact-sound](https://github.com/plunkettscott/interact-sound)
- [PolyZone](https://github.com/qbcore-framework/PolyZone)
- _Other dependencies are included in the resource._


### Begin your installation

Here, we shall provide a step-by-step guide on installing cdn-fuel to your server and making it work with other scripts you may already have installed.

### Step 1:

First, we will start by renaming the resource "cdn-fuel-main" to just "cdn-fuel". <br> <br> Next, we will drag the "cdn-fuel" resource into your desired folder in your servers resources directory.

![Step 1](https://i.imgur.com/8kg0LWe.gif)

### Step 2:

Next, we're going to drag the sounds from the *cdn-fuel/assets/sounds* folder in cdn-fuel, into your interact-sounds folder located at *resources/[standalone]/interact-sound/client/html/sounds*

![explorer_8jBjdkgaeQ](https://user-images.githubusercontent.com/95599217/209605265-c8f67612-b8df-4c38-bf23-0c355cfa6c8e.gif)

### Step 3:

Next, we're going to open our entire resources folder in whichever IDE you use, (we will be using Visual Studio Code for this example) and replace all of your current exports titled "LegacyFuel", "ps-fuel" or "lj-fuel", with "cdn-fuel". Then you want to ensure cdn-fuel in your server's config file. 
<br> <br>
![step 3](https://i.imgur.com/VZnQpcS.gif)

<br>

### Step 4:

Next, we're going to run our SQL file, which is needed if we want to use the Player Owned Gas Stations, otherwise you do not have to run it.

<br> 

The file you need to run is located @ _cdn-fuel/assets/sql/cdn-fuel.sql_

<br> 

Here is a GIF to run you through the process of running an SQL file:

![Step4-Gif](https://user-images.githubusercontent.com/95599217/209601625-af7ee908-c367-48b1-8487-b52359148224.gif)

### Step 5:

It is highly recommended, if you plan on restarting the script at all, that you move the _stream_ folder & _data_file_ paramaters found in the _fxmanifest.lua_ to another resource for the time being. If you do not do this, you & anyone in the server's game will most likely crash when restarting _cdn-fuel_. The process is very simple & it is outlined in the GIF & Instructions below.

<br>

**Firstly**, we will move our _stream_ folder to our new resource, or existing resource. <br> <br> In this example, I have a dummy resource named _cdn-fool_.
![explorer_4tflJ0RowY](https://user-images.githubusercontent.com/95599217/209604683-79e18fa7-96ad-456d-b0c4-20632fb4d04c.gif)


Next, we will move our _fxmanifest.lua's_ entries for _data_file_ into our new resource, and **REMOVE IT** from _cdn-fuel_.

![jRtUg319mL](https://user-images.githubusercontent.com/95599217/209604640-54e0a450-6a54-4afa-9fab-cda4f02e7091.gif)


```Lua
data_file 'DLC_ITYP_REQUEST' 'stream/[electric_nozzle]/electric_nozzle_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/[electric_charger]/electric_charger_typ.ytyp'
```

Make sure to **ensure** this new resource as well as _cdn-fuel_ in your _server.cfg_!


**If you do not want the Jerry Can or Syphoning Kit items, you are now finished with installation.**

<br>
*Otherwise, navigate to Step 6 & Step 7 below, and finish installation.*

## ___Recommended Snippets:___

We highly recommend you add the following snippet to your engine toggle command. It will make it to where players cannot turn their vehicle on if they have no fuel! Seems pretty important to us!

##### ***Engine Toggle Snippet***
```Lua
-- EXAMPLE FOR QB-VEHICLEKEYS, FUNCTION ToggleEngine();
local NotifyCooldown = false
function ToggleEngine(veh)
    if veh then
        local EngineOn = GetIsVehicleEngineRunning(veh)
        if not isBlacklistedVehicle(veh) then
            if HasKeys(QBCore.Functions.GetPlate(veh)) or AreKeysJobShared(veh) then
                if EngineOn then
                    SetVehicleEngineOn(veh, false, false, true)
                else
                    if exports['cdn-fuel']:GetFuel(veh) ~= 0 then
                        SetVehicleEngineOn(veh, true, false, true)
                    else
                        if not NotifyCooldown then
                            RequestAmbientAudioBank("DLC_PILOT_ENGINE_FAILURE_SOUNDS", 0)
                            PlaySoundFromEntity(l_2613, "Landing_Tone", PlayerPedId(), "DLC_PILOT_ENGINE_FAILURE_SOUNDS", 0, 0)
                            NotifyCooldown = true
                            QBCore.Functions.Notify('No fuel..', 'error')
                            Wait(1500)
                            StopSound(l_2613)
                            Wait(3500)
                            NotifyCooldown = false
                        end
                    end                
                end
            end
        end
    end
end
```

<br> 

### You are now officially done installing!

<br> 

Enjoy using **cdn-fuel**, if you have an issues, [create an issue](https://github.com/CodineDev/cdn-fuel/issues/new/choose) on the repository, and we will fix it **ASAP**!

<br>
<br>

![Codine Development Fuel Script Showcase Banner](https://i.imgur.com/HQOH3AX.png)

### Demonstration of the script

Here's a couple of videos showcasing the script in action!

- [Main Fueling & Charging!](https://www.youtube.com/watch?v=_h-66IDs8Kw)
- [Player Owned Gas Stations!](https://www.youtube.com/watch?v=3glln0S2QXo)
- [Jerry Cans!](https://www.youtube.com/watch?v=M14nZTzltB0)

<br>
<br>

![Codine Development Fuel Script Future Plans Banner](https://i.imgur.com/1RoBsmo.png)

<br>
<br>

![Codine Development Links Banner](https://i.imgur.com/SAqArzg.png)

### Codine Links

- [Discord](https://discord.gg/Ta6QNnuxM2)
- [Tebex](https://codine.tebex.io/)
- [Youtube](https://www.youtube.com/channel/UC3Nr0qtyQP9cGRK1m25pOqg)

### Credits:

- **ESX Conversion:**
Shorty

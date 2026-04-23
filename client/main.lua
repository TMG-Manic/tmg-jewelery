local TMGCore = exports['tmg-core']:GetCoreObject()



JewelState = {
    isLoggedIn = LocalPlayer.state['isLoggedIn'],
    firstAlarm = false,
    smashing = false,
    listen = false,
    locations = {} 
}



local function LoadAssets(dict, ptfx)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(5) end
    if ptfx then
        if not HasNamedPtfxAssetLoaded(ptfx) then RequestNamedPtfxAsset(ptfx) end
        while not HasNamedPtfxAssetLoaded(ptfx) do Wait(5) end
        SetPtfxAssetNextCall(ptfx)
    end
end

local function IsValidWeapon()
    local weapon = GetSelectedPedWeapon(PlayerPedId())
    return Config.WhitelistedWeapons[weapon] ~= nil
end



local function SmashVitrine(id)
    if not JewelState.firstAlarm then
        TriggerServerEvent('police:server:policeAlert', 'Suspicious Activity')
        JewelState.firstAlarm = true
        print("^5[TMG]^7 Perimeter alarm tripped. Silent dispatch sent.")
    end

    TMGCore.Functions.TriggerCallback('tmg-jewellery:server:getCops', function(cops)
        if cops < Config.RequiredCops then
            return TMGCore.Functions.Notify(Lang:t('error.minimum_police', { value = Config.RequiredCops }), 'error')
        end

        local animDict, animName = 'missheist_jewel', 'smash_case'
        local ped = PlayerPedId()
        local weapon = GetSelectedPedWeapon(ped)
        local plyCoords = GetOffsetFromEntityInWorldCoords(ped, 0, 0.6, 0)

        
        if math.random(1, 100) <= 80 and not TMGCore.Functions.IsWearingGloves() then
            TriggerServerEvent('evidence:server:CreateFingerDrop', plyCoords)
        elseif math.random(1, 100) <= 5 and TMGCore.Functions.IsWearingGloves() then
            TriggerServerEvent('evidence:server:CreateFingerDrop', plyCoords)
            TMGCore.Functions.Notify(Lang:t('error.fingerprints'), 'error')
        end

        JewelState.smashing = true
        TriggerServerEvent('tmg-jewellery:server:setVitrineState', 'isBusy', true, id)

        
        CreateThread(function()
            while JewelState.smashing do
                LoadAssets(animDict, 'scr_jewelheist')
                TaskPlayAnim(ped, animDict, animName, 3.0, 3.0, -1, 2, 0, 0, 0, 0)
                Wait(500)
                TriggerServerEvent('InteractSound_SV:PlayOnSource', 'breaking_vitrine_glass', 0.25)
                StartParticleFxLoopedAtCoord('scr_jewel_cab_smash', plyCoords.x, plyCoords.y, plyCoords.z, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
                Wait(2500)
            end
        end)

        TMGCore.Functions.Progressbar('smash_vitrine', Lang:t('info.progressbar'), Config.WhitelistedWeapons[weapon]['timeOut'], false, true, {
            disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
        }, {}, {}, {}, function() 
            TriggerServerEvent('tmg-jewellery:server:vitrineReward', id)
            TriggerServerEvent('tmg-jewellery:server:setTimeout')
            TriggerServerEvent('police:server:policeAlert', 'Robbery in progress')
            JewelState.smashing = false
            TaskPlayAnim(ped, animDict, 'exit', 3.0, 3.0, -1, 2, 0, 0, 0, 0)
            print("^5[TMG]^7 Asset node loot secured: Vitrine #" .. id)
        end, function() 
            TriggerServerEvent('tmg-jewellery:server:setVitrineState', 'isBusy', false, id)
            JewelState.smashing = false
            TaskPlayAnim(ped, animDict, 'exit', 3.0, 3.0, -1, 2, 0, 0, 0, 0)
        end)
    end)
end



local function ListenForControl(id)
    JewelState.listen = true
    CreateThread(function()
        while JewelState.listen do
            if IsControlJustPressed(0, 38) then
                if not Config.Locations[id]['isBusy'] and not Config.Locations[id]['isOpened'] then
                    exports['tmg-core']:KeyPressed()
                    if IsValidWeapon() then SmashVitrine(id)
                    else TMGCore.Functions.Notify(Lang:t('error.wrong_weapon'), 'error') end
                    JewelState.listen = false
                else
                    exports['tmg-core']:DrawText(Lang:t('general.drawtextui_broken'), 'left')
                end
            end
            Wait(1)
        end
    end)
end



local function InitJewelZones()
    if Config.UseTarget then
        for k, v in pairs(Config.Locations) do
            exports['tmg-target']:AddBoxZone('jewelstore' .. k, v.coords, 1, 1, {
                name = 'jewelstore' .. k, heading = 40, minZ = v.coords.z - 1, maxZ = v.coords.z + 1, debugPoly = false
            }, {
                options = {{
                    icon = 'fa fa-hand', label = Lang:t('general.target_label'),
                    action = function() 
                        if IsValidWeapon() then SmashVitrine(k) 
                        else TMGCore.Functions.Notify(Lang:t('error.wrong_weapon'), 'error') end
                    end,
                    canInteract = function() return not Config.Locations[k]['isOpened'] and not Config.Locations[k]['isBusy'] end
                }},
                distance = 1.5
            })
        end
    else
        for k, v in pairs(Config.Locations) do
            local zone = BoxZone:Create(v.coords, 1, 1, { name = 'jewelstore' .. k, heading = 40, minZ = v.coords.z - 1, maxZ = v.coords.z + 1 })
            zone:onPlayerInOut(function(isInside)
                if isInside then
                    exports['tmg-core']:DrawText(Lang:t('general.drawtextui_grab'), 'left')
                    ListenForControl(k)
                else
                    JewelState.listen = false
                    exports['tmg-core']:HideText()
                end
            end)
        end
    end
    print("^5[TMG]^7 Vangelico spatial grid materialized. Interaction nodes active.")
end



RegisterNetEvent('TMGCore:Client:OnPlayerLoaded', function()
    TMGCore.Functions.TriggerCallback('tmg-jewellery:server:getVitrineState', function(result)
        Config.Locations = result
        InitJewelZones()
        print("^5[TMG]^7 Heist ledger synchronized with server.")
    end)
end)

RegisterNetEvent('tmg-jewellery:client:setVitrineState', function(type, state, k)
    Config.Locations[k][type] = state
end)


CreateThread(function()
    local blip = AddBlipForCoord(Config.JewelleryLocation['coords']['x'], Config.JewelleryLocation['coords']['y'], Config.JewelleryLocation['coords']['z'])
    SetBlipSprite(blip, 617)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, true)
    SetBlipColour(blip, 3)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Vangelico Jewelry')
    EndTextCommandSetBlipName(blip)
end)

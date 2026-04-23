local TMGCore = exports['tmg-core']:GetCoreObject()
local timeOut = false
local cachedPoliceAmount = {}
local flags = {}

TMGCore.Functions.CreateCallback('tmg-jewelry:server:getCops', function(source, cb)
    local amount = 0
    local players = TMGCore.Functions.GetQBPlayers()
    
    for _, v in pairs(players) do
        local job = v.PlayerData.job
        if (job.name == 'police' or job.type == 'leo') and job.onduty then
            amount = amount + 1
        end
    end
    
    cachedPoliceAmount[source] = amount
    cb(amount)
end)

TMGCore.Functions.CreateCallback('tmg-jewelry:server:getVitrineState', function(_, cb)
    cb(Config.Locations)
end)



local function exploitBan(id, reason)
    local Player = TMGCore.Functions.GetPlayer(id)
    if not Player then return end

    local banData = {
        ["name"] = GetPlayerName(id),
        ["license"] = TMGCore.Functions.GetIdentifier(id, 'license'),
        ["discord"] = TMGCore.Functions.GetIdentifier(id, 'discord'),
        ["ip"] = TMGCore.Functions.GetIdentifier(id, 'ip'),
        ["reason"] = reason,
        ["expire"] = 2147483647, 
        ["bannedby"] = 'TMG-Mainframe (Jewelry)',
        ["timestamp"] = os.time()
    }

    exports['tmgnosql']:UpdateOne('bans', 
        { ["license"] = banData.license }, 
        { ["$set"] = banData }, 
        { ["upsert"] = true }
    )

    TriggerEvent('tmg-log:server:CreateLog', 'security', 'Player Banned', 'red',
        string.format('**%s** was neutralized by **%s** for **%s**', 
        banData.name, 'TMG-Mainframe', reason), true)

    DropPlayer(id, 'TMG Mainframe: Security Violation. Your access has been permanently revoked.')
    
    print(string.format("^1[TMG]^7 Security: Neutralized Player %s | Reason: %s", banData.name, reason))
end

local function getRewardBasedOnProbability(rewardTable)
    local random = math.random()
    local cumulativeProbability = 0

    for k, v in pairs(rewardTable) do
        if v.probability then
            cumulativeProbability = cumulativeProbability + v.probability
            
            if random <= cumulativeProbability then
                return k
            end
        end
    end

    local keys = {}
    for k in pairs(rewardTable) do keys[#keys + 1] = k end
    return keys[math.random(#keys)]
end



RegisterNetEvent('tmg-jewelry:server:setVitrineState', function(stateType, state, k)
    if stateType ~= 'isBusy' then return end 
    if type(state) ~= 'boolean' then return end

    if not Config.Locations[k] then return end

    Config.Locations[k][stateType] = state

    TriggerClientEvent('tmg-jewelry:client:setVitrineState', -1, stateType, state, k)
end)

RegisterNetEvent('tmg-jewelry:server:vitrineReward', function(vitrineIndex)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    if not Config.Locations[vitrineIndex] or Config.Locations[vitrineIndex].isOpened ~= false then
        exploitBan(src, 'Illegal Event Trigger: vitrineReward (Index: '..tostring(vitrineIndex)..')')
        return
    end

    if not cachedPoliceAmount[src] then
        DropPlayer(src, 'Mainframe Sync Error: Police check not found.')
        return
    end

    local cheating = false
    local plrPed = GetPlayerPed(src)
    local plrCoords = GetEntityCoords(plrPed)
    local vitrineCoords = Config.Locations[vitrineIndex].coords

    if cachedPoliceAmount[src] >= Config.RequiredCops then
        local dist = #(plrCoords - vitrineCoords)
        
        if dist <= 25.0 then
            Config.Locations[vitrineIndex].isOpened = true
            Config.Locations[vitrineIndex].isBusy = false
            
            TriggerClientEvent('tmg-jewelry:client:setVitrineState', -1, 'isOpened', true, vitrineIndex)
            TriggerClientEvent('tmg-jewelry:client:setVitrineState', -1, 'isBusy', false, vitrineIndex)

            local rewardKey = getRewardBasedOnProbability(Config.VitrineRewards)
            local rewardData = Config.VitrineRewards[rewardKey]
            local amount = math.random(rewardData.amount.min, rewardData.amount.max)
            local itemName = rewardData.item

            if exports['tmg-inventory']:AddItem(src, itemName, amount, false, false, 'Heist: Jewelry Vitrine') then
                TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[itemName], 'add', amount)
            else
                TriggerClientEvent('TMGCore:Notify', src, 'Pockets too full...', 'error')
            end
        else
            cheating = true
        end
    else
        cheating = true
    end

    if cheating then
        local license = Player.PlayerData.license
        flags[license] = (flags[license] or 0) + 1
        
        if flags[license] >= 3 then
            exploitBan(src, 'Multi-Flag Detection: tmg-jewelry exploit attempt')
        else
            DropPlayer(src, 'Mainframe Security: Desync detected.')
        end
    end
end)

RegisterNetEvent('tmg-jewelry:server:setTimeout', function()
    if timeOut then return end

    timeOut = true

    TriggerEvent('tmg-scoreboard:server:SetActivityBusy', 'jewelry', true)

    CreateThread(function()
        Wait(Config.Timeout)

        for k, _ in pairs(Config.Locations) do
            Config.Locations[k].isOpened = false
            Config.Locations[k].isBusy = false 

            TriggerClientEvent('tmg-jewelry:client:setVitrineState', -1, 'isOpened', false, k)
        end

        TriggerClientEvent('tmg-jewelry:client:setAlertState', -1, false)
        TriggerEvent('tmg-scoreboard:server:SetActivityBusy', 'jewelry', false)
        
        timeOut = false
        print("^5[TMG]^7 Jewelry Store Vitrines have been reset.")
    end)
end)

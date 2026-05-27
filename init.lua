-- =========================================================================================================
--                                        RAIDASSIST BOT SYSTEM DOCUMENTATION
-- =========================================================================================================
-- OVERVIEW & ARCHITECTURE:
-- This MacroQuest Lua script operates an asynchronous frame polling execution engine layout. By shifting
-- background automation routines directly into the ImGui draw tick layer, the thread tracks environment
-- data synchronously with client graphics cycles, entirely eliminating instant-close crashes or thread drift.
--
-- DETAILED FUNCTION DIRECTORY & STRUCTURAL SPECIFICATIONS:
--
-- 1) ensureRaidAssistDeclared()
--    -> MECHANICS: Probes the MacroQuest system variable tables using the parsing verification string
--       token '${Defined[RaidAssist]}'. If the result returns false, it issues a raw system memory insertion:
--       '/declare RaidAssist string outer ""' to stand up an unallocated outer variable placeholder.
--    -> INPUTS / PARAMETERS: None.
--    -> OPERATIONAL IMPACT: Establishes global macro variable permanence so parallel client systems can view
--       the current target assignments across boxing networks.
--
-- 2) isRaidAssistValid()
--    -> MECHANICS: Extracts the string contents stored inside the global character RaidAssist TLO variable.
--       Applies a multi-stage cascade trap to catch uninitialized memory signatures, empty lines, null markers,
--       or literal quote combinations ("" or '').
--    -> INPUTS / PARAMETERS: None.
--    -> RETURNS: Boolean [true] if a usable, non-blank name is found; boolean [false] if unassigned.
--
-- 3) loadRaidNames()
--    -> MECHANICS: Queries the game client's active raid data profile tables. Pulls full entity counts
--       via 'mq.TLO.Raid.Members()', then loops sequentially to isolate characters. Instantly discards your local
--       character name and maps group criteria filters via 'mq.TLO.Group.Member(name)() ~= nil' to discard active group 
--       members. Applies alphabetical string sorting arrays to the remaining name stack.
--    -> INPUTS / PARAMETERS: None.
--    -> ERROR HANDLING: If the character disbands or leaves a raid entirely (returning 0 members), it clears the 
--       selection arrays, forces the drop-down index to position 1, and wipes global macro variables to an empty line.
--
-- 4) setRaidAssistAndExit()
--    -> MECHANICS: References the sorted name stack using the active drop-down index value. Commits the string 
--       to the outer macro global, fires a cross-client broadcast text alert down the raid channel network using '/rsay',
--       and automatically issues an audio-visual target selection packet to track the newly selected helper character.
--    -> INPUTS / PARAMETERS: None.
--    -> DATA SANITIZATION: Resets all combat thread sequencers back to Step 0 (Idle) and zero-clears target identifier
--       memory numbers to guarantee target switching does not cause command bouncing during pulls.
--
-- 5) broadcastGroupFollow(actionType)
--    -> MECHANICS: Manages multi-boxed character movement states using specialized group broadcast networks.
--    -> PARAMETERS: actionType [String literal matching "START" or "STOP"].
--       - "START": Pulls your character's exact numeric entity identity key ('mq.TLO.Me.ID()') and forwards a 
--         zone-wide mesh navigation order ('/e3bcgza /nav spawn id [ID]') to pull accounts to your exact vectors. 
--         Fires a secondary frame call command '/followme 10' to coordinate immediate regional boxes.
--       - "STOP": Assembles a safe multi-line packet shortcut string via '/multiline' sent across network channels 
--         to instantly terminate navigation loops, drop active follows via '/followoff', and tap backward keys to kill momentum.
--
-- 6) executeAutomationLogic()
--    -> MECHANICS: The primary tactical tracking loops evaluated on every frame pass. Manages three sections:
--       A) Active Target Lifespan Invalidation: Tracks the target's status via numerical memory identifiers. 
--          If your enemy target dies or disappears, it clears state variables and jumps to Step 0 in under 1ms.
--       B) State Machine Combat Sequencing:
--          - STEP 0 (The Filtering Scanner): Automatically triggers assist via '/rsay' strictly once per creature.
--            Checks if RA target is an NPC, has dropped to or below 99% health, AND is within radiusCheck feet.
--            The radiusCheck distance is user-configurable via the UI slider (range: 10–100 feet, step: 5).
--          - STEP 1 (Melee Approach & Engage): Squares up client angles via '/face' and fires high-speed directional
--            movement shortcuts ('/moveto mdist 10 id [ID]') to step your character right to 5ft melee thresholds.
--          - STEP 2 (Hate Registration Sync): Triggers an '/assistme' call exactly once per target, if group size > 0.
--          - STEP 3 (Snappy Reset Clearance): Throttles thread states using a compressed 300ms cushion window.
--       C) Dynamic Follow Intercept Suspension: Temporarily suspends follow routines in combat, resuming automatically when clear.
--       D) Proximity NPC Scanning: SpawnCount and NearestSpawn radius queries use radiusCheck feet as their scan
--          boundary, matching the same configurable distance applied to RA target filtering.
--    -> DEFENSIVE ENHANCEMENT: Removed frame-flash assists from drawUI to prevent infinite targeting loops when a mob dies.
--
-- 7) drawUI()
--    -> MECHANICS: Renders the graphical user control panel overlay via the ImGui rendering pipe. Enforces open state
--       via 'ImGuiCond.Always'. UI layout order (top to bottom):
--         - RaidAssist Enemy Target display
--         - Current NPC Targeted display
--         - Current RaidAssist name and combat status (COMBAT / IDLE / OUT OF ZONE)
--         - Raid member dropdown + Refresh button (hidden when not in raid)
--         - Set RaidAssist button | Exit Script button
--         [Visible only when a valid RaidAssist is set:]
--         - NPC Target Radius Check label (displays current radiusCheck value in feet) + slider
--             Slider range: 10–100 feet in increments of 5. Internally operates on a scaled range (2–20)
--             multiplied by 5 to enforce discrete 5-foot stepping. Only rendered when RaidAssist is valid.
--         - Announce toggle button (ON/OFF) | Follow Assist toggle button (START / STOP / Paused)
--         - Pause Assist toggle button (Pause Assist / Assist: PAUSED):
--             When PAUSED: only the /assist state machine is suspended — no assists,
--             no melee approach, no state-machine progression. The combat sequencer is
--             reset to Step 0 on activation so resuming starts from a clean slate.
--             Follow and Anchor procedures are NOT affected and continue to run normally.
--             When re-enabled: full assist automation resumes on the next frame tick.
--         - Anchor toggle button (ON / OFF):
--             ON:  1) Clears local target via '/squelch /target clear'.
--                  2) Calls broadcastGroupFollow("STOP") to halt all group movement.
--                  3) Saves the current followAssist state for later restoration.
--                  4) If in a group with mq2mono loaded, broadcasts '/nav spawn id [myID]' so
--                     all group members navigate to the player's position, then broadcasts '/anchoron'
--                     to anchor each member in place.
--             OFF: Restores followAssist to its pre-anchor state and, if follow was previously
--                  active, fires broadcastGroupFollow("START") to resume movement.
-- =========================================================================================================

local mq = require('mq')
local ImGui = require('ImGui')

-- Force explicit initialization allocations on file load to prevent crashes
if mq.parse('${Defined[RaidAssist]}') ~= 'TRUE' then
    mq.cmd('/declare RaidAssist string outer ""')
end

-- Structural Interface Viewport Control Variables
local showWindow = true
local forceExpand = false
local done = false
local selectedIndex = 1
local names = {}
local followAssist = false
local hasRaidMembers = false 
local followPausedForCombat = false 
local announceAssist = true         
local anchorActive = false          
local preAnchorFollowAssist = false  -- exact snapshot of followAssist at anchor activation
local preAnchorFollowPaused  = false -- exact snapshot of followPausedForCombat at anchor activation
local pauseAssist = false            -- when true, the /assist state machine is suspended (follow/anchor unaffected)
local anchorCommandPending = false   -- true for a short window after /anchoron fires to keep the engine clear
local anchorCommandPendingTimer = 0  -- timestamp (ms) when anchorCommandPending was set
local pendingAnchorOn = false        -- deferred /anchoron flag: executed in the main loop, not the ImGui callback
local pendingAnchorOnTimer = 0       -- timestamp (ms) when pendingAnchorOn was armed

-- State Machine Processing Properties
local assistStep = 0               
local assistTimerStart = 0         
local lastNotifiedTargetID = 0     
local lastAssistTime = 0
local activeCombatTargetID = 0      
local lastAssistedMeTargetID = 0    

-- Global UI Background Processing References
local backgroundResolvedTargetName = "NONE"
local backgroundResolvedTargetID = 0
local lastTargetScanTime = 0

-- Throttled Clock & Cooldown Constraints
local lastFollowCheck = 0          
local followCheckCooldown = 500    
local approachDistance = 20        
local movementThreshold = 20       
local assistCooldown = 300
local radiusCheck = 10

local function ensureRaidAssistDeclared()
    if mq.parse('${Defined[RaidAssist]}') ~= 'TRUE' then
        mq.cmd('/declare RaidAssist string outer ""')
    end
end

local function isRaidAssistValid()
    ensureRaidAssistDeclared()
    local currentRA = mq.parse('${RaidAssist}')
    if not currentRA or currentRA == "" or currentRA == "NULL" or currentRA == "string" or currentRA == '""' or currentRA == "''" then
        return false
    end
    return true
end

local function loadRaidNames()
    names = {}
    local raid = mq.TLO.Raid
    local members = raid.Members() or 0
    local myName = mq.TLO.Me.Name()
    
    if members == 0 then
        hasRaidMembers = false
        selectedIndex = 1
        mq.cmd('/varset RaidAssist ""')
        return
    end
    
    for i = 1, members do
        local member = raid.Member(i)
        if member and member.Name() then
            local memberName = member.Name()
            local isGroupMember = mq.TLO.Group.Member(memberName)() ~= nil
            if memberName ~= myName and not isGroupMember then
                table.insert(names, memberName)
            end
        end		
    end
	
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
	
    if #names == 0 then
        hasRaidMembers = false
        selectedIndex = 1
        mq.cmd('/varset RaidAssist ""')
    else
        hasRaidMembers = true
        if selectedIndex > #names then selectedIndex = 1 end
    end
end

local function setRaidAssistAndExit()
    if not hasRaidMembers or #names == 0 then return end
    local picked = names[selectedIndex]
    if not picked or picked == '' then return end

    ensureRaidAssistDeclared()
    mq.cmd('/squelch /target clear')
    mq.cmdf('/varset RaidAssist %s', picked)	
    mq.cmdf('/rsay FYI: ♠Ω♠ I have just set my ►►►[RaidAssist]◄◄◄ to: †♥†[002D7E00000000000000000000000000000000000000000097D7AFA8 %s]†♥† !!!', picked)
    print(string.format("\am[\atRaidAssistBot\am]\ay Locked onto target: \am[\ag %s \am]\ax", picked))
    
    local raSpawn = mq.TLO.Spawn(string.format("pc =%s", picked))
    if raSpawn() then raSpawn.DoTarget() end
    assistStep = 0
    activeCombatTargetID = 0
    lastNotifiedTargetID = 0
    lastAssistedMeTargetID = 0
    backgroundResolvedTargetID = 0
    backgroundResolvedTargetName = "NONE"
end

local function broadcastGroupFollow(actionType)
    if (mq.TLO.Group.Members() or 0) == 0 then return end
    if not mq.TLO.Plugin('mq2mono').IsLoaded() then return end
    
    local myID = mq.TLO.Me.ID() or 0
    local networkPrefix = "/e3bcgza"

    if actionType == "START" then
        mq.cmdf('%s /nav spawn id %d', networkPrefix, myID)
        mq.cmd('/followme 10')
    elseif actionType == "STOP" then
        if mq.TLO.Plugin('mq2nav').IsLoaded() then
            mq.cmdf('%s /multiline ; /nav stop ; /followoff ; /keypress back', networkPrefix)
        else
            mq.cmdf('%s /multiline ; /followoff ; /keypress back', networkPrefix)
        end
    end
end

local function activateAnchor()
    anchorActive = true

    -- 1) Clear local target
    mq.cmd('/squelch /target clear')

    -- 2) Snapshot BOTH follow variables independently before touching anything.
    --    This is a direct 1:1 copy — no boolean arithmetic that could collapse state.
    preAnchorFollowAssist = followAssist
    preAnchorFollowPaused  = followPausedForCombat

    -- 3) Stop group follow and zero out all local follow flags
    broadcastGroupFollow("STOP")
    followAssist = false
    followPausedForCombat = false

    -- 4) If in a group with the broadcast plugin, move members to my position then anchor them
    if (mq.TLO.Group.Members() or 0) > 0 and mq.TLO.Plugin('mq2mono').IsLoaded() then
        local myID = mq.TLO.Me.ID() or 0
        if myID > 0 then
            mq.cmdf('/e3bcgz /nav spawn id %d', myID)

            -- Suspend the assist engine immediately so no target can be acquired
            anchorCommandPending      = true
            anchorCommandPendingTimer = os.clock() * 1000

            -- Defer /anchoron to the main loop. The main loop will confirm the target is truly
            -- clear before sending the command, avoiding the ImGui-callback race condition.
            pendingAnchorOn      = true
            pendingAnchorOnTimer = os.clock() * 1000
        end
    end

    mq.cmd('/rsay FYI: ⚓ Anchor is now ►[ON]◄ — Group movement halted and members anchored in place !!!')
end

local function deactivateAnchor()
    anchorActive = false

    -- Release the anchor on all group members FIRST so they can actually move again
    if (mq.TLO.Group.Members() or 0) > 0 and mq.TLO.Plugin('mq2mono').IsLoaded() then
        mq.cmd('/anchoroff')
    end

    -- Restore BOTH variables exactly as they were — the combat-resume branch in
    -- executeAutomationLogic depends on followPausedForCombat being correct too.
    followAssist          = preAnchorFollowAssist
    followPausedForCombat = preAnchorFollowPaused
    preAnchorFollowAssist = false
    preAnchorFollowPaused  = false

    -- Only broadcast START if follow was actively running (not just paused for combat).
    -- If it was paused, the combat block in executeAutomationLogic will restart it naturally.
    if followAssist then
        broadcastGroupFollow("START")
    end

    mq.cmd('/rsay FYI: ⚓ Anchor is now ►[OFF]◄ — Group movement restrictions released !!!')
end

local function executeAutomationLogic()
    -- While /anchoron is settling, keep the engine suspended so it cannot
    -- re-acquire a target ID or issue an /assist before the anchor takes hold.
    if anchorCommandPending then
        local now = os.clock() * 1000
        if (now - anchorCommandPendingTimer) < 500 then
            return
        end
        anchorCommandPending = false
    end

    local currentTime = os.clock() * 1000
    local amIInCombat = (mq.TLO.Me.CombatState() == "COMBAT" or mq.TLO.Me.Combat())

    -- Dynamic Follow Intercept Suspension & Follow Navigation:
    -- These always run regardless of pauseAssist so that follow and anchor
    -- behaviour is never affected by the assist pause state.
    if not anchorActive then
        if amIInCombat and followAssist then
            followAssist = false
            followPausedForCombat = true
            if mq.TLO.Plugin('mq2mono').IsLoaded() then
                broadcastGroupFollow("STOP")
            elseif mq.TLO.Plugin('mq2nav').IsLoaded() then
                mq.cmd('/nav stop')
            else
                mq.cmd('/keypress back')
            end
        elseif not amIInCombat and followPausedForCombat then
            if (currentTime - lastFollowCheck > 1000) then
                followAssist = true
                followPausedForCombat = false
                broadcastGroupFollow("START")
            end
        end
    end

    if followAssist and (currentTime - lastFollowCheck > followCheckCooldown) then
        lastFollowCheck = currentTime
        if isRaidAssistValid() then
            local followRAName = mq.parse('${RaidAssist}')
            local followRASpawn = mq.TLO.Spawn(string.format("pc =%s", followRAName))
            if followRASpawn and followRASpawn() then
                if mq.TLO.Plugin('mq2nav').IsLoaded() then
                    local distanceToTarget = followRASpawn.Distance() or 0
                    if distanceToTarget > movementThreshold and not mq.TLO.Navigation.Active() then
                        mq.cmdf('/nav spawn id %d |distance=%d', followRASpawn.ID(), approachDistance)
                    end
                else
                    if mq.TLO.Me.Following.Name() ~= followRAName then mq.cmdf('/follow %s', followRAName) end
                end
            end
        end
    end

    -- ── Assist engine gate ────────────────────────────────────────────────────
    -- Everything below this point is part of /assist automation only.
    -- Follow and anchor procedures above are unaffected by this flag.
    if pauseAssist then return end

    if not isRaidAssistValid() then return end

    local raName = mq.parse('${RaidAssist}')
    local raSpawn = mq.TLO.Spawn(string.format("pc =%s", raName))
    local localTarget = mq.TLO.Target

    if not raSpawn() then return end

    -- CRITICAL RESET TRACKING: Immediately drop out of all active steps if the enemy target dies or disappears
    if activeCombatTargetID > 0 then
        local activeCheckSpawn = mq.TLO.Spawn(string.format("id %d", activeCombatTargetID))
        if not activeCheckSpawn() or activeCheckSpawn.Dead() or (localTarget() and localTarget.Dead()) or (localTarget() and localTarget.ID() ~= activeCombatTargetID and assistStep > 1) then
            assistStep = 0
            activeCombatTargetID = 0
            backgroundResolvedTargetID = 0
            backgroundResolvedTargetName = "NONE"
            if not amIInCombat then
                mq.cmd('/squelch /target clear')
            end
        end
    end

    local raInCombat = false
    local anyNpcOnXTarget = false
    
    -- Throttled Target Resolution Strategy: Process the assist command inside the automation engine loop at structured intervals
    if currentTime - lastTargetScanTime > 250 then
        lastTargetScanTime = currentTime
        local initialTargetID = localTarget.ID() or 0
        
        mq.cmd('/assist ' .. raName)
        
        local resolvedObj = mq.TLO.Target
        if resolvedObj() and not resolvedObj.Dead() then
            backgroundResolvedTargetID = resolvedObj.ID() or 0
            local rawType = resolvedObj.Type() or "NPC"
            if rawType == "PC" then
                backgroundResolvedTargetName = "NONE"
                backgroundResolvedTargetID = 0
            else
                backgroundResolvedTargetName = resolvedObj.CleanName() or "NONE"
            end
        else
            backgroundResolvedTargetID = 0
            backgroundResolvedTargetName = "NONE"
        end

        -- Seamless target re-routing logic pass
        if initialTargetID > 0 and initialTargetID ~= backgroundResolvedTargetID then
            mq.cmdf('/target id %d', initialTargetID)
        elseif initialTargetID == 0 and backgroundResolvedTargetID > 0 and assistStep == 0 then
            mq.cmd('/squelch /target clear')
        end
    end

    local raTargetID = backgroundResolvedTargetID

    for i = 1, 20 do
        local xtSpawn = mq.TLO.Me.XTarget(i)
        if xtSpawn() and xtSpawn.Type() == "NPC" and not xtSpawn.Dead() then
            anyNpcOnXTarget = true
        end
    end

    if raTargetID > 0 then
        local targetSpawn = mq.TLO.Spawn(string.format("id %d", raTargetID))
        if targetSpawn() and not targetSpawn.Dead() then
            local sType = targetSpawn.Type() or "NONE"
            if raTargetID ~= mq.TLO.Me.ID() then
                raInCombat = (sType == "NPC" or sType == "Corpse")
            end
        end
    end

    local aggressiveMobNearby = false
    local proxMobCount = mq.TLO.SpawnCount(string.format('npc radius %d', radiusCheck))() or 0
    if proxMobCount > 0 then
        for i = 1, proxMobCount do
            local pMob = mq.TLO.NearestSpawn(string.format('%d, npc radius %d', i, radiusCheck))
            if pMob and pMob() and pMob.Aggressive() and not pMob.Dead() then
                aggressiveMobNearby = true
                break
            end
        end
    end

    if assistStep == 0 then
        local meetsTargetFilters = false
        
        if raTargetID > 0 then
            local tSpawn = mq.TLO.Spawn(string.format("id %d", raTargetID))
            if tSpawn() and tSpawn.Type() == "NPC" and not tSpawn.Dead() then
                local tHealth = tSpawn.PctHPs() or 100
                local tDistance = tSpawn.Distance() or 999
                if tHealth <= 99 and tDistance <= radiusCheck then
                    meetsTargetFilters = true
                    activeCombatTargetID = raTargetID
                end
            end
        end

        if not meetsTargetFilters and anyNpcOnXTarget then
            for i = 1, 20 do
                local xt = mq.TLO.Me.XTarget(i)
                if xt() and xt.Type() == "NPC" and not xt.Dead() then
                    local xtHealth = xt.PctHPs() or 100
                    local xtDistance = xt.Distance() or 999
                    if xtHealth <= 99 and xtDistance <= radiusCheck then
                        meetsTargetFilters = true
                        activeCombatTargetID = xt.ID() or 0
                        break
                    end
                end
            end
        end

        if aggressiveMobNearby then
            meetsTargetFilters = true
            if localTarget() and localTarget.Type() == "NPC" and not localTarget.Dead() then
                activeCombatTargetID = localTarget.ID() or 0
            end
        end

        if (raInCombat or anyNpcOnXTarget or aggressiveMobNearby) and meetsTargetFilters and (currentTime - lastAssistTime > assistCooldown) then
            mq.cmd('/assist ' .. raName)
            
            if announceAssist and raTargetID > 0 and raTargetID ~= lastNotifiedTargetID then
                local raTargetName = backgroundResolvedTargetName
                if raTargetName ~= "NONE" then
                    -- mq.cmdf('/rsay 1- FYI: I am assisting *[%s]* on target: -> *%s* <- !!!', raName, raTargetName)
					mq.cmdf('/rsay FYI: I am assisting †♥†[%s]†♥† on target: ►►► (%s) ◄◄◄ !!!', raName, raTargetName)
					print(string.format("\am[\atRaidAssistBot\am]\ay Locked onto raid target: \am[\ag %s \am]\ax", raTargetName))
                end
                lastNotifiedTargetID = raTargetID
            end
            assistTimerStart = currentTime 
            lastAssistTime = currentTime
            assistStep = 1 
        end
    elseif assistStep == 1 then
        if localTarget() and localTarget.Type() == "NPC" and not localTarget.Dead() then
            local isAggressive = localTarget.Aggressive() or false
            local isOnXTarget = false
            for i = 1, 20 do
                local xtSpawn = mq.TLO.Me.XTarget(i)
                if xtSpawn() and xtSpawn.ID() == localTarget.ID() then isOnXTarget = true break end
            end
            
            if isAggressive or isOnXTarget then
                mq.cmd('/face fast')
				if localTarget.Distance() > 15 then						
					mq.cmdf('/moveto mdist 10 id %d', localTarget.ID())
                end				
				mq.cmd('/attack on')
                assistStep = 2 
            end
        elseif (currentTime - assistTimerStart) >= 2000 then
            assistStep = 0
        end
    elseif assistStep == 2 then
        if amIInCombat and localTarget() and localTarget.Type() == "NPC" and not localTarget.Dead() then
            local currentTargetID = localTarget.ID() or 0
            if currentTargetID > 0 and currentTargetID ~= lastAssistedMeTargetID then
                if (mq.TLO.Group.Members() or 0) > 0 then
                    mq.cmd('/assistme')
                end
                lastAssistedMeTargetID = currentTargetID 
            end
            assistStep = 3 
        else
            assistStep = 0
        end
    elseif assistStep == 3 then
        if (currentTime - lastAssistTime > assistCooldown) then 
            assistStep = 0 
        end
    end

    if assistStep > 0 and not raInCombat and not anyNpcOnXTarget and not aggressiveMobNearby and not amIInCombat then 
        assistStep = 0 
        activeCombatTargetID = 0
    end

end

local function drawUI()
    if not showWindow then return end

    if forceExpand then
        ImGui.SetNextWindowCollapsed(false, ImGuiCond.Always)
        forceExpand = false
    else
        ImGui.SetNextWindowCollapsed(false, ImGuiCond.Once)
    end

    local minWidth = 300
    if #names > 0 then
        local longestName = ''
        for _, name in ipairs(names) do
            if #name > #longestName then longestName = name end
        end
        local namePixelWidth = ImGui.CalcTextSize(longestName)
        -- account for the Refresh + Set RaidAssist buttons, combo arrow, and padding
        minWidth = math.max(minWidth, namePixelWidth + 325)
    end
    ImGui.SetNextWindowSizeConstraints(minWidth, 0, 9999, 9999)

    local shouldDraw, openRef = ImGui.Begin('RaidAssist Bot', true, ImGuiWindowFlags.AlwaysAutoResize)
    if not openRef then showWindow = false end
	
    if shouldDraw then
        -- Execute our automation state checks inside the UI thread context
        executeAutomationLogic()

        local myTarget = mq.TLO.Target
        local amIAttacking = mq.TLO.Me.Combat() or false
        local currentRA = mq.parse('${RaidAssist}')

        -- FIXED RENDERING PROCESS: drawUI no longer initiates /assist calls, eliminating targeting lock loops
        if amIAttacking and myTarget() and not myTarget.Dead() and myTarget.Type() ~= "PC" then
            local tName = myTarget.CleanName() or "NONE"
            ImGui.TextColored(0.3, 1.0, 0.7, 1.0, string.format("RaidAssist Enemy Target: %s", tName))
        else
            ImGui.TextColored(0.3, 1.0, 0.7, 1.0, string.format("RaidAssist Enemy Target: %s", backgroundResolvedTargetName))
        end

        if myTarget() and not myTarget.Dead() then
            local rawType = myTarget.Type() or "NPC"
            if rawType == "PC" then
                ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "Current NPC Targetted: NONE")
            else
                local tName = myTarget.CleanName() or "Unknown Entity"
                local tHps = myTarget.PctHPs() or 100
                ImGui.TextColored(1.0, 0.5, 0.1, 1.0, string.format("Current NPC Targetted: %s (%d%% HP)", tName, tHps))
            end
        else
            ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "Current NPC Targetted: NONE")
        end

        ImGui.Separator()

        if isRaidAssistValid() then
            ImGui.TextColored(0.3, 0.8, 1.0, 1.0, string.format("Current RaidAssist: %s", currentRA))
            
            local raSpawnCheck = mq.TLO.Spawn(string.format("pc =%s", currentRA))
            local isRAInCombat = false
            local checkID = raSpawnCheck and raSpawnCheck.ID() or 0
            
            local interfaceXTargetCheck = false
            for i = 1, 20 do
                local xtSpawn = mq.TLO.Me.XTarget(i)
                if xtSpawn() and xtSpawn.Type() == "NPC" and not xtSpawn.Dead() then
                    interfaceXTargetCheck = true
                end
            end

            local interfaceProxCheck = false
            local uiProxCount = mq.TLO.SpawnCount(string.format('npc radius %d', radiusCheck))() or 0
            if uiProxCount > 0 then
                for i = 1, uiProxCount do
                    local uiMob = mq.TLO.NearestSpawn(string.format('%d, npc radius %d', i, radiusCheck))
                    if uiMob and uiMob() and uiMob.Aggressive() and not uiMob.Dead() then
                        interfaceProxCheck = true
                        break
                    end
                end
            end

            local raIsUnderAttack = false
            for i = 1, 20 do
                local xtTargetName = mq.parse(string.format('${Me.XTarget[%d].TargetOfTarget.CleanName}', i))
                if xtTargetName and xtTargetName:lower() == currentRA:lower() then
                    raIsUnderAttack = true
                    break
                end
            end

            if backgroundResolvedTargetID > 0 and backgroundResolvedTargetID ~= mq.TLO.Me.ID() then
                local targetSpawn = mq.TLO.Spawn(string.format("id %d", backgroundResolvedTargetID))
                if targetSpawn() and not targetSpawn.Dead() then
                    local sType = targetSpawn.Type() or "NONE"
                    isRAInCombat = (sType == "NPC" or sType == "Corpse" or raIsUnderAttack)
                end
            else
                isRAInCombat = raIsUnderAttack
            end

            if isRAInCombat or interfaceXTargetCheck or interfaceProxCheck then
                ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "  |- Status: COMBAT")
            elseif raSpawnCheck() then
                ImGui.TextColored(0.4, 1.0, 0.4, 1.0, "  |- Status: IDLE")
            else
                ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "  |- Status: OUT OF ZONE")
            end
        else
            ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "Current RaidAssist: NONE SET")
        end
        
        ImGui.Separator()
        if not hasRaidMembers then ImGui.Text('You are not in a raid or no external members found.')
        else ImGui.Text('Select a raid member to change RaidAssist:') end		
        ImGui.Separator()        
        
        if not hasRaidMembers then
            if ImGui.Button('Refresh Raid List') then loadRaidNames() end
        else
            local refreshButtonWidth = 80
            local setButtonWidth = 100
            ImGui.PushItemWidth(-(refreshButtonWidth + setButtonWidth + 20))
            local preview = names[selectedIndex] or 'Select...'
            if ImGui.BeginCombo('##RaidMemberCombo', preview) then
                for i = 1, #names do
                    local isSelected = (i == selectedIndex)
                    if ImGui.Selectable(names[i], isSelected) then selectedIndex = i end
                    if isSelected then ImGui.SetItemDefaultFocus() end
                end
                ImGui.EndCombo()
            end
            ImGui.PopItemWidth()
            ImGui.SameLine()
            if ImGui.Button('Refresh') then loadRaidNames() end
            ImGui.SameLine()
            local disableSet = not hasRaidMembers
            if disableSet then ImGui.BeginDisabled() end
            if ImGui.Button('Set RaidAssist') then setRaidAssistAndExit() end
            if disableSet then ImGui.EndDisabled() end
        end

        if isRaidAssistValid() then
            ImGui.Separator()
            ImGui.Text(string.format("NPC Target Radius Check: %d feet", radiusCheck))
            ImGui.PushItemWidth(-1)
            local newSliderVal, sliderChanged = ImGui.SliderInt('##RadiusCheck', radiusCheck / 5, 2, 20, ' ')
            if sliderChanged then radiusCheck = newSliderVal * 5 end
            ImGui.PopItemWidth()
            ImGui.Separator()
            local horizontalSplitWidth = (ImGui.GetWindowWidth() - 25) / 2

            if announceAssist then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1.0)
            else ImGui.PushStyleColor(ImGuiCol.Button, 0.6, 0.2, 0.2, 1.0) end
            ImGui.PushItemWidth(horizontalSplitWidth)
            local announceLabel = announceAssist and "Announce: ON" or "Announce: OFF"
            if ImGui.Button(announceLabel) then announceAssist = not announceAssist end
            ImGui.PopItemWidth()
            ImGui.PopStyleColor()

            ImGui.SameLine()

            if followAssist then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1.0) 
            elseif followPausedForCombat then ImGui.PushStyleColor(ImGuiCol.Button, 0.8, 0.5, 0.1, 1.0) 
            else ImGui.PushStyleColor(ImGuiCol.Button, 0.6, 0.2, 0.2, 1.0) end
            ImGui.PushItemWidth(horizontalSplitWidth)
            local buttonLabel = followAssist and "Stop Follow" or (followPausedForCombat and "Follow: Paused" or "Follow Assist")

            if ImGui.Button(buttonLabel) then
                if followPausedForCombat then
                    followPausedForCombat, followAssist = false, false
                    broadcastGroupFollow("STOP")
                    mq.cmd('/rsay FYI: ⚠️ Follow Assist has been ►[STOPPED]◄ — Group follow is OFF !!!')
                else
                    followAssist = not followAssist
                    followPausedForCombat = false
                    broadcastGroupFollow(followAssist and "START" or "STOP")
                    if followAssist then
                        mq.cmd('/rsay FYI: ✅ Follow Assist has been ►[STARTED]◄ — Group follow is ACTIVE !!!')
                    else
                        mq.cmd('/rsay FYI: ⚠ Follow Assist has been ►[STOPPED]◄ — Group follow is OFF !!!')
                    end
                end
                if not followAssist then
                    if mq.TLO.Plugin('mq2mono').IsLoaded() then
                        broadcastGroupFollow("STOP")
                    elseif mq.TLO.Plugin('mq2nav').IsLoaded() then 
                        mq.cmd('/nav stop')
                    else 
                        mq.cmd('/keypress back') 
                    end
                end
            end
            ImGui.PushItemWidth(-1)
            ImGui.PopStyleColor()

            ImGui.Separator()

            -- Anchor toggle button (full width)
            if anchorActive then ImGui.PushStyleColor(ImGuiCol.Button, 0.7, 0.4, 0.0, 1.0)
            else ImGui.PushStyleColor(ImGuiCol.Button, 0.25, 0.25, 0.25, 1.0) end
            local anchorLabel = anchorActive and "Anchor: ON" or "Anchor: OFF"
            if ImGui.Button(anchorLabel, -1, 0) then
                if anchorActive then
                    deactivateAnchor()
                else
                    activateAnchor()
                end
            end
            ImGui.PopStyleColor()

            ImGui.Separator()

            -- Pause Assist toggle button (full width)
            if pauseAssist then ImGui.PushStyleColor(ImGuiCol.Button, 0.7, 0.1, 0.1, 1.0)
            else ImGui.PushStyleColor(ImGuiCol.Button, 0.15, 0.45, 0.15, 1.0) end
            local pauseAssistLabel = pauseAssist and "Assist: PAUSED" or "Pause RaidAssist"
            if ImGui.Button(pauseAssistLabel, -1, 0) then
                pauseAssist = not pauseAssist
                if pauseAssist then
                    -- Reset sequencer so we start clean when unpaused
                    assistStep = 0
                    activeCombatTargetID = 0
                    mq.cmd('/rsay FYI: ⚠ RaidAssist Bot has been ►[PAUSED]◄ — Assist automation is SUSPENDED !!!')
                else
                    mq.cmd('/rsay FYI: ✅ RaidAssist Bot has been ►[RESUMED]◄ — Assist automation is ACTIVE !!!')
                end
            end
            ImGui.PopStyleColor()

            ImGui.Separator()
            if ImGui.Button('Exit Script') then done = true end
        else
            ImGui.Separator()
            if ImGui.Button('Exit Script') then done = true end
        end
    end
    ImGui.End()
end

-- Baseline Startup Initializations
loadRaidNames()

mq.bind('/rbot', function()
    showWindow = not showWindow
    if showWindow then forceExpand = true end
    print(string.format("\am[\atRaidAssistBot\am]\ay UI layout state toggled to\ao: \ag%s\ax", tostring(showWindow)))
end)

mq.imgui.init('RaidAssistBotUI', drawUI)

while not done do
    mq.doevents()

    -- Deferred /anchoron handler: runs in the main loop where mq.delay() is safe.
    -- Waits 200 ms after activation, then polls until the target slot is genuinely
    -- empty before sending /anchoron. This eliminates the ImGui-callback race condition
    -- where /target clear was queued but not yet processed by the game client.
    if pendingAnchorOn then
        local now = os.clock() * 1000
        if (now - pendingAnchorOnTimer) >= 200 then
            -- Force-clear and confirm the target is truly gone before anchoring
            local cleared = false
            for _ = 1, 10 do
                mq.cmd('/squelch /target clear')
                mq.delay(50)
                if not mq.TLO.Target() then
                    cleared = true
                    break
                end
            end

            if cleared then
                mq.cmdf('/anchoron')
                -- Reset the engine-suspend timer from the moment /anchoron actually fires
                anchorCommandPendingTimer = os.clock() * 1000
            else
                -- Target stubbornly present (e.g. rooted in combat); anchor anyway
                mq.cmd('/squelch /target clear')
                mq.cmdf('/anchoron')
                anchorCommandPendingTimer = os.clock() * 1000
            end

            pendingAnchorOn = false
        end
    end

    mq.delay(100)
end

mq.unbind('/rbot')
mq.imgui.destroy('RaidAssistBotUI')

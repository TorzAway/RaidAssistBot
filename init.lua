-- ============================================================================
--                          RAIDASSIST BOT SUMMARY
-- ============================================================================
-- This MacroQuest Lua utility automates raid monitoring, targeting, and pathing.
-- It offers a responsive, non-blocking automation workflow managed by a 
-- multi-stage state machine that interacts smoothly with your user interface.
--
-- DETAILED FUNCTION DIRECTORY & STRUCTURAL SPECIFICATIONS:
--
-- 1) ensureRaidAssistDeclared()
--    -> SYSTEM MECHANICS: Probes the MacroQuest variable table via the string parser 
--       token '${Defined[RaidAssist]}'. If the return value is not string 'TRUE',
--       it dynamically injects an outer-scoped variable allocation into the system 
--       memory table utilizing the direct engine execution command: '/declare RaidAssist string outer'.
--    -> ARCHITECTURAL PURPOSE: Ensures variable permanence so that other active macros 
--       or system scripts running in parallel can pull the exact same targeting target data.
--
-- 2) isRaidAssistValid()
--    -> SYSTEM MECHANICS: Evaluates the current state value assigned to the outer 
--       RaidAssist variable wrapper. Uses a protective conditional filter cascade to trap 
--       empty data parameters, initialization placeholders, unmapped type arrays, and literal 
--       C++ code string dumps.
--    -> EXCLUSION FILTERS: Returns boolean 'false' if the variable content equals an empty line, 
--       nil values, or the exact text literals: "NULL", "string", '""', or "''". 
--       Returns boolean 'true' only when a valid, actionable name is locked in.
--
-- 3) loadRaidNames()
--    -> SYSTEM MECHANICS: Loops sequentially through the live server raid database via 
--       the Top-Level Object data framework: 'mq.TLO.Raid.Member(index)'. 
--    -> FILTRATION SIEVE: Cross-references name strings on every calculation pass. To prevent 
--       targeting bouncing and multi-box interface conflicts, it instantly discards your local 
--       player character's name wrapper and maps an inner loop condition block using 
--       'mq.TLO.Group.Member(name)() ~= nil' to filter out and drop your entire immediate group.
--    -> SYSTEM AUTOMATION: Sorts remaining non-grouped characters alphabetically using an internal 
--       table sorting function layout. If the total element stack length matches 0 (such as when 
--       you leave or disband from a raid), it sets the tracking flag to false, points the drop-down 
--       index back to position 1, and clears the client's macro outer variable back to an empty string.
--
-- 4) setRaidAssistAndExit()
--    -> SYSTEM MECHANICS: Extracts the string name value resting at the selected combo row index position. 
--       Issues a cross-client server broadcast to the Raid Channel via '/rs', pushes a chat notification 
--       to your local terminal layout box, triggers a cursor selection packet targeting the player exactly 
--       once as an audio-visual confirmation hook, and wipes the state memory registries.
--    -> REGISTRY RESET: Automatically sets the combat sequence tracker back to 0 (Idle) and zeroes out 
--       the target memory parameters to guarantee a clean slate for the next engagement pass.
--
-- 5) broadcastGroupFollow(actionType)
--    -> SYSTEM MECHANICS: Coordinates cross-client movement synchronization using the target network 
--       pipeline manager plugin layer. If the group member count is 0 or 'MQ2Mono' is missing from 
--       your plugin registry stack, it exits the loop instantly to prevent pipeline buffer leaks.
--    -> SEQUENCE ACTION - "START": Queries your exact numerical target entity identifier via the 
--       TLO wrapper 'mq.TLO.Me.ID()'. Pushes a network broadcast using the specified group prefix '/e3bcgz' 
--       to route a zone-wide command forcing your multi-boxes to navigate to your exact ID node position via 
--       'mq2nav'. Immediately afterward, it fires a local client execution call to the macro command '/followme 10'.
--    -> SEQUENCE ACTION - "STOP": Packs a combined formatting layout command string utilizing a safe, 
--       non-blocking '/multiline' packet layer. Dispatches a sequence down the network connection prefix that 
--       stops navigation mesh routes, cuts core follow states via '/followoff', and issues a backward friction pad 
--       keypress to kill all momentum instantly across your background accounts without locking your main thread frames.
--
-- 6) executeAutomationLogic()
--    -> SYSTEM MECHANICS: The primary heart loop executed on every thread evaluation frame pass. Splits duties into:
--       A) Throttled Proximity Navigation: Monitored by a millisecond cooling interval tracker clock. If you 
--          turn on follow states and the target player drifts past your threshold setting (>20 paces), it issues a mesh 
--          path command tracking their live Spawn ID parameter, adjusting automatically if you run without 'mq2nav'.
--       B) State Machine Combat Sequencing: A non-blocking automation engine that continuously tracks your RaidAssist's 
--          hate/threat values via your own local client Extended Target window buffer pipeline ('${Me.XTarget[Name].AggroPct}').
--          - STEP 0 (Idle Scanner): If the RA builds threat (Aggro > 0) and the reset delay timer clears, it issues a 
--            client-side '/assist' instruction. If 'Announce Assist' is active, it reads the target name from the RA's 
--            XTarget slot and broadcasts an alert line directly to your Raid channel loop. ADVANCES TO STEP 1.
--          - STEP 1 (Target Validation Gate): Probes your live cursor target bar array. It screens attributes to confirm 
--            the selection is a live entity, matches an NPC object flag type, and is not a corpse. It then screens hostile status 
--            via '.Aggressive()' or matches its unique entity ID against your live XTarget list slots. If proven hostile, it 
--            activates auto-attack strings via '/attack on' and ADVANCES TO STEP 2. Includes a 4-second timeout self-termination escape hook.
--          - STEP 2 (Engagement Lock Listener): Listens until your player character physically draws combat hate or locks into 
--            a native combat loop state on that target. Once combat verifies, it dispatches the silent team signal string command 
--            '/assistme' down to your client box. ADVANCES TO STEP 3.
--          - STEP 3 (Cooldown Settling Filter): Holds thread parameters steady for a 5-second global buffer period to prevent 
--            command bouncing or target switching glitches before sliding back to Step 0.
--          - SAFETY INTERCEPT: If you drop out of combat, the monster dies, or the assist clears their threat panel, the script 
--            suspends nav movement paths and safely returns back to Step 0 immediately.
--
-- 7) drawUI()
--    -> SYSTEM MECHANICS: The core responsive render engine canvas managed by ImGui. Draws an automatic resizable frame layout window.
--       Displays live color-coded target status alerts (COMBAT = Red, IDLE / NO COMBAT = Green, OUT OF ZONE = Grey) based on active 
--       tracking conditions, groups the responsive inline combo box selection tray and Manual list refresh buttons together side by side 
--       using an external item width compression wrapper to align signatures safely, and links the Announce Assist and Follow Assist control 
--       toggle buttons horizontally on a single line by calculating active layout dimensions via 'ImGui.GetWindowWidth()' mathematically.
-- ============================================================================

local mq = require('mq')
local ImGui = require('ImGui')

-- State flags
local open = true
local selectedIndex = 1
local names = {}
local done = false
local followAssist = false
local hasRaidMembers = false 
local followPausedForCombat = false 
local announceAssist = false       

-- State Machine Sequence Properties
local assistStep = 0               -- 0=Idle, 1=Assisted (Waiting for Aggressive NPC target), 2=Attack Engaged (Waiting for local combat loop confirmation)
local assistTimerStart = 0         -- Holds the millisecond stamp when delay timers trigger
local lastNotifiedTargetID = 0     -- Tracks the active enemy target ID to prevent duplicate sequence loops
local lastAssistTime = 0

-- Initialized tracking properties
local lastFollowCheck = 0          
local followCheckCooldown = 500    -- Milliseconds to verify follow state stability (faster response)

-- Configuration Properties
local approachDistance = 20        -- Adjust this variable to change your nav follow cushion distance
local movementThreshold = 20       -- Only nav if the target moves further than this distance away
local assistCooldown = 5000        -- Global cooling reset filter before running a new script cycle (5 seconds)

local function ensureRaidAssistDeclared()
    if mq.parse('${Defined[RaidAssist]}') ~= 'TRUE' then
        mq.cmd('/declare RaidAssist string outer')
    end
end

local function isRaidAssistValid()
    if mq.parse('${Defined[RaidAssist]}') ~= 'TRUE' then
        return false
    end
    local currentRA = mq.parse('${RaidAssist}')
    
    -- Filter out blank spaces, raw code types, and literal quote patterns ("" or '')
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
    
    -- Check if we are physically part of a raid structure.
    if members == 0 then
        hasRaidMembers = false
        selectedIndex = 1
        ensureRaidAssistDeclared()
        mq.cmd('/varset RaidAssist ""')
        return
    end
    
    for i = 1, members do
        local member = raid.Member(i)
        if member and member.Name() then
            local memberName = member.Name()
            -- Check if this specific raid member is part of your current active group layout setup
            local isGroupMember = mq.TLO.Group.Member(memberName)() ~= nil
            
            -- Only add to choice listings if they are NOT you AND not in your immediate group
            if memberName ~= myName and not isGroupMember then
                table.insert(names, memberName)
            end
        end		
    end
	
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
	
    if #names == 0 then
        hasRaidMembers = false
        selectedIndex = 1
        ensureRaidAssistDeclared()
        mq.cmd('/varset RaidAssist ""')
    else
        hasRaidMembers = true
        if selectedIndex > #names then
            selectedIndex = 1
        end
    end
end

local function setRaidAssistAndExit()
    if not hasRaidMembers or #names == 0 then
        mq.cmd('/echo No valid raid members found.')
        return
    end
	
    local picked = names[selectedIndex]
    if not picked or picked == '' then
        mq.cmd('/echo Invalid selection.')
        return
    end

    ensureRaidAssistDeclared()
    mq.cmdf('/varset RaidAssist %s', picked)	
    mq.cmdf('/rs FYI: I have just set my ~[RaidAssist]~ to: *[%s]* !!!', picked)
    
    print(string.format("\127[RaidAssistBot]\127 \128Successfully locked onto new RaidAssist target: \127[ %s ]\127", picked))
    
    -- Target them exactly ONCE right now upon selection as visual confirmation
    local raSpawn = mq.TLO.Spawn(string.format("pc =%s", picked))
    if raSpawn() then
        raSpawn.DoTarget()
    end

    -- Reset assist sequencing thresholds cleanly
    assistStep = 0
    lastNotifiedTargetID = 0
end

-- Cross-client movement sync manager
local function broadcastGroupFollow(actionType)
    if (mq.TLO.Group.Members() or 0) == 0 then return end
    
    -- Abort execution cleanly if the required MQ2Mono plugin isn't active
    if not mq.TLO.Plugin('mq2mono').IsLoaded() then return end
    
    local myID = mq.TLO.Me.ID() or 0
    local networkPrefix = "/e3bcgz"

    if actionType == "START" then
        -- Commands your background multi-boxes wide zone group layer to move to you via mq2nav first
        mq.cmdf('%s /nav spawn id %d', networkPrefix, myID)
        
        -- Dispatches the local follow instruction call cleanly
        mq.cmd('/followme 10')
        print(string.format("\127[RaidAssistBot]\127 \128Group Nav To ID [ %d ] and Local Follow Dispatched.", myID))
    elseif actionType == "STOP" then
        if mq.TLO.Plugin('mq2nav').IsLoaded() then
            mq.cmdf('%s /multiline ; /nav stop ; /followoff ; /keypress back', networkPrefix)
        else
            mq.cmdf('%s /multiline ; /followoff ; /keypress back', networkPrefix)
        end
        print("\127[RaidAssistBot]\127 \128Group Broadcast Issued: \127[ STOP FOLLOW ]\127")
    end
end

-- Automation logic called every frame execution loop
local function executeAutomationLogic()
    if not isRaidAssistValid() then return end

    local raName = mq.parse('${RaidAssist}')
    local raSpawn = mq.TLO.Spawn(string.format("pc =%s", raName))
    local currentTime = os.clock() * 1000
    
    -- Gather real-time local combat values for following states
    local localCombatState = mq.TLO.Me.CombatState()
    local amIInCombat = (localCombatState == "COMBAT" or mq.TLO.Me.Combat())

    -- Ensure the designated RaidAssist is present in the current zone
    if not raSpawn() then return end

    -----------------------------------------
    -- DYNAMIC COMBAT SEQUENCE STATE MACHINE
    -----------------------------------------
    local raAggro = tonumber(mq.parse(string.format('${Me.XTarget[%s].AggroPct}', raName))) or 0
    local targetMob = mq.TLO.Target

    -- STEP 0: Look for the RaidAssist to enter combat parameters (Aggro > 0)
    if assistStep == 0 then
        if raAggro > 0 and (currentTime - lastAssistTime > assistCooldown) then
            -- Action 1: Execute manual client side /assist
            mq.cmdf('/assist %s', raName)
            
            -- Moved /rs announcement hook directly to Step 0 when performing the /assist
            if announceAssist then
                local raTargetName = mq.parse(string.format('${Me.XTarget[%s].TargetOfTarget.CleanName}', raName)) or "Current Enemy"
                mq.cmdf('/rs FYI: I am assisting *[%s]* on target: -> *%s* <- !!!', raName, raTargetName)
            end
            
            assistTimerStart = currentTime 
            lastAssistTime = currentTime
            assistStep = 1 
        end

    -- STEP 1: Wait and verify that we have successfully acquired an aggressive NPC target
    elseif assistStep == 1 then
        if targetMob() and targetMob.Type() == "NPC" then
            
            local isAggressive = targetMob.Aggressive() or false
            local isOnXTarget = false
            
            -- Scan active XTarget slots as an ultra-reliable fallback for social/linked encounters
            for i = 1, 20 do
                local xtSpawn = mq.TLO.Me.XTarget(i)
                if xtSpawn() and xtSpawn.ID() == targetMob.ID() then
                    isOnXTarget = true
                    break
                end
            end

            -- Execute attack ONLY if the NPC is proven aggressive
            if isAggressive or isOnXTarget then
                mq.cmd('/attack on')
                assistStep = 2 
            end
            
        elseif (currentTime - assistTimerStart) >= 4000 then
            -- Safety Timeout
            assistStep = 0
        end

    -- STEP 2: Wait until your local character physically transitions into combat on that targeted NPC
    elseif assistStep == 2 then
        if amIInCombat and targetMob() and targetMob.Type() == "NPC" then
            mq.cmd('/assistme')
            assistStep = 3 
        end

    -- STEP 3: Cooldown protection step to allow fight initialization window settling
    elseif assistStep == 3 then
        if (currentTime - lastFollowCheck > assistCooldown) then
            assistStep = 0 
        end
    end

    -- Safety Reset Engine
    if assistStep > 0 and raAggro == 0 and not amIInCombat then
        assistStep = 0
    end

    -----------------------------------------
    -- Dynamic Combat Follow Suspension Loop
    -----------------------------------------
    if amIInCombat and followAssist then
        followAssist = false
        followPausedForCombat = true
        if mq.TLO.Plugin('mq2nav').IsLoaded() then
            mq.cmd('/nav stop')
        else
            mq.cmd('/keypress back')
        end
        print("\127[RaidAssistBot]\127 \128Combat detected! Temporarily pausing follow routines.")
        
        -- Command your multi-box group companions to pause following you instantly
        broadcastGroupFollow("STOP")
        
    elseif not amIInCombat and followPausedForCombat then
        if (currentTime - lastFollowCheck > 1500) then
            followAssist = true
            followPausedForCombat = false
            print("\127[RaidAssistBot]\127 \128Combat cleared! Resuming follow routines.")
            
            -- Command group companions to re-acquire your trail automatically
            broadcastGroupFollow("START")
        end
    end

    -----------------------------------------
    -- 1) FOLLOW LOGIC (THRUST DISTANCE CHECK)
    -----------------------------------------
    if followAssist and (currentTime - lastFollowCheck > followCheckCooldown) then
        lastFollowCheck = currentTime
        
        if mq.TLO.Plugin('mq2nav').IsLoaded() then
            local distanceToTarget = raSpawn.Distance() or 0
            
            if distanceToTarget > movementThreshold then
                if not mq.TLO.Navigation.Active() then
                    mq.cmdf('/nav spawn id %d |distance=%d', raSpawn.ID(), approachDistance)
                end
            end
        else
            if mq.TLO.Me.Following.Name() ~= raName then
                mq.cmdf('/follow %s', raName)
            end
        end
    end
end

local function drawUI()
    if not open then
        done = true
        return
    end
	
    local shouldDraw, newOpen = ImGui.Begin('RaidAssist Bot', open, ImGuiWindowFlags.AlwaysAutoResize)
    open = newOpen
	
    if shouldDraw then
        if isRaidAssistValid() then
            local currentRA = mq.parse('${RaidAssist}')
            ImGui.TextColored(0.3, 0.8, 1.0, 1.0, string.format("Current RaidAssist: %s", currentRA))
            
            -------------------------------------------------
            -- COMBAT STATUS DISPLAY
            -------------------------------------------------
            local raAggro = tonumber(mq.parse(string.format('${Me.XTarget[%s].AggroPct}', currentRA))) or 0
            
            if raAggro > 0 then
                ImGui.TextColored(1.0, 0.3, 0.3, 1.0, string.format("  |- Status: COMBAT (Aggro: %d%%)", raAggro))
            else
                local raSpawnCheck = mq.TLO.Spawn(string.format("pc =%s", currentRA))
                if raSpawnCheck() then
                    ImGui.TextColored(0.4, 1.0, 0.4, 1.0, "  |- Status: IDLE / NO COMBAT")
                else
                    ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "  |- Status: OUT OF ZONE")
                end
            end
        else
            ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "Current RaidAssist: NONE SET")
        end
        
        ImGui.Separator()

        if not hasRaidMembers then
            ImGui.Text('You are not currently in a raid or no other members found.')
        else
            ImGui.Text('Select a raid member to change RaidAssist:')
        end		

        ImGui.Separator()        
        
        -----------------------------------------
        -- DYNAMIC COMBO + REFRESH BUTTON ALIGNMENT
        -----------------------------------------
        if not hasRaidMembers then
            if ImGui.Button('Refresh Raid List') then
                loadRaidNames()
            end
            ImGui.TextColored(1, 0.5, 0.5, 1, 'No other raid members found.')
        else
            local refreshButtonWidth = 80
            ImGui.PushItemWidth(-refreshButtonWidth - 15)
            
            local preview = names[selectedIndex] or 'Select...'
            if ImGui.BeginCombo('##RaidMemberCombo', preview) then
                for i = 1, #names do
                    local isSelected = (i == selectedIndex)
                    if ImGui.Selectable(names[i], isSelected) then
                        selectedIndex = i
                    end
                    if isSelected then
                        ImGui.SetItemDefaultFocus()
                    end
                end
                ImGui.EndCombo()
            end
            ImGui.PopItemWidth()
            
            ImGui.SameLine()
            
            ImGui.PushItemWidth(refreshButtonWidth)
            if ImGui.Button('Refresh') then
                loadRaidNames()
            end
            ImGui.PopItemWidth()
        end
		
        ImGui.Separator()
        
        local disableSet = not hasRaidMembers
        if disableSet then ImGui.BeginDisabled() end
        if ImGui.Button('Set RaidAssist') then
            setRaidAssistAndExit()
        end
        if disableSet then ImGui.EndDisabled() end
		
        ImGui.SameLine()
        if ImGui.Button('Close Panel') then
            done = true
        end

        if isRaidAssistValid() then
            ImGui.Separator()

            ---------------------------------------------------------
            -- LINKED ROW: ANNOUNCE ASSIST & FOLLOW BOT CONTROLS
            ---------------------------------------------------------
            local horizontalSplitWidth = (ImGui.GetWindowWidth() - 25) / 2

            -----------------------------------------
            -- ACTION A: ANNOUNCE ASSIST TOGGLE (LEFT SIDE)
            -----------------------------------------
            if announceAssist then
                ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1.0) 
            else
                ImGui.PushStyleColor(ImGuiCol.Button, 0.6, 0.2, 0.2, 1.0) 
            end

            ImGui.PushItemWidth(horizontalSplitWidth)
            local announceLabel = announceAssist and "Announce: ON" or "Announce: OFF"
            if ImGui.Button(announceLabel) then
                announceAssist = not announceAssist
                mq.cmdf('/echo RaidAssist Broadcast Announcements toggled to: %s', tostring(announceAssist))
            end
            ImGui.PopItemWidth()
            ImGui.PopStyleColor()

            ImGui.SameLine()

            -----------------------------------------
            -- ACTION B: FOLLOW TOGGLE (RIGHT SIDE)
            -----------------------------------------
            if followAssist then
                ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1.0) 
            elseif followPausedForCombat then
                ImGui.PushStyleColor(ImGuiCol.Button, 0.8, 0.5, 0.1, 1.0) 
            else
                ImGui.PushStyleColor(ImGuiCol.Button, 0.6, 0.2, 0.2, 1.0) 
            end

            ImGui.PushItemWidth(horizontalSplitWidth)
            
            local buttonLabel = "Follow Assist"
            if followAssist then
                buttonLabel = "Stop Follow"
            elseif followPausedForCombat then
                buttonLabel = "Follow: Paused"
            end

            if ImGui.Button(buttonLabel) then
                if followPausedForCombat then
                    followPausedForCombat = false
                    followAssist = false
                    
                    broadcastGroupFollow("STOP")
                else
                    followAssist = not followAssist
                    followPausedForCombat = false
                    
                    if followAssist then
                        broadcastGroupFollow("START")
                    else
                        broadcastGroupFollow("STOP")
                    end
                end
                
                if not followAssist then
                    if mq.TLO.Plugin('mq2nav').IsLoaded() then
                        mq.cmd('/nav stop')
                    else
                        mq.cmd('/keypress back')
                    end
                end
                mq.cmdf('/echo RaidAssist Follow state set to: %s', tostring(followAssist))
            end
            
            ImGui.PopItemWidth()
            ImGui.PopStyleColor()
        end
    end
    ImGui.End()
end

-- Initial configuration run
loadRaidNames()

-- Bind UI drawing callback loop
mq.imgui.init('RaidAssistBotUI', drawUI)

-- Loop framework processing background automation triggers without locking frames
while not done do
    executeAutomationLogic()
    mq.delay(100)
end

mq.imgui.destroy('RaidAssistBotUI')

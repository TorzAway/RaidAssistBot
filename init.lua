-- =========================================================================================================
--                                        RAIDASSIST BOT SYSTEM DOCUMENTATION
-- =========================================================================================================
-- OVERVIEW & ARCHITECTURE:
-- This MacroQuest Lua script operates an asynchronous frame polling execution engine layout. By shifting
-- background automation routines directly into the ImGui draw tick layer, the thread tracks environment
-- data synchronously with client graphics cycles, entirely eliminating instant-close crashes or thread drift.
--
-- SOURCE OF TRUTH (read this first):
-- The authoritative "who is the assist" value is the Lua variable `currentRaidAssist`. Everything the script
-- DISPLAYS or ACTS ON (the UI line, isRaidAssistValid, follow, and the assist engine) reads `currentRaidAssist`
-- — NOT the parser variable `${RaidAssist}`. This is deliberate: the assist is written out with `/e3varset`,
-- and `${RaidAssist}` lags behind (or does not reflect) that E3 write, so reading it caused the UI to show the
-- previous name and the automation to act on stale data. `currentRaidAssist` updates instantly and persists for
-- the life of the script (including across zones). The E3 variable is written only on deliberate events.
--
-- DETAILED FUNCTION DIRECTORY & STRUCTURAL SPECIFICATIONS:
--
-- 1) ensureRaidAssistDeclared()
--    -> MECHANICS: Probes the MacroQuest system variable tables using '${Defined[RaidAssist]}'. If false, it
--       issues '/declare RaidAssist string outer ""' to stand up an outer variable placeholder.
--    -> ONE-SHOT LATCH (v3.3): '/declare' runs via mq.cmd, which is QUEUED rather than immediate, while
--       '${Defined[...]}' via mq.parse is synchronous. Because this function is called from isRaidAssistValid()
--       many times per frame, multiple calls at startup used to see Defined == FALSE before the first queued
--       '/declare' had run, each queuing its own and causing "RaidAssist already exists" errors on all but the
--       first. A local boolean (raidAssistDeclareAttempted) now latches true the instant a declare is attempted,
--       so repeat calls short-circuit instead of re-checking the lagging state. The matching
--       ensureViewStateDeclared() has the same fix (viewStateDeclareAttempted) for the same reason.
--    -> NO PER-FRAME WRITES: This function performs NO writes to the assist value. (An earlier revision re-pushed
--       '/e3varset' here every frame whenever '${RaidAssist}' read blank; because that parser variable does not
--       reflect the E3 write, it looped '/e3varset' continuously. That restore was removed — the E3 variable is
--       written only on the Set button and at startup detection, and `currentRaidAssist` is what the script reads.)
--    -> INPUTS / PARAMETERS: None.
--
-- 2) isRaidAssistValid()
--    -> MECHANICS: Reads the script's own `currentRaidAssist` value (the source of truth). Applies a cascade trap
--       to reject uninitialized/empty/null/quote values, and treats the E3 sentinel "NOBODY" (case-insensitive)
--       as "no assist".
--    -> INPUTS / PARAMETERS: None.
--    -> RETURNS: Boolean [true] if a usable, non-blank, non-NOBODY name is held; boolean [false] otherwise.
--
-- 3) loadRaidNames()
--    -> MECHANICS: Queries the game client's active raid data profile tables. Pulls full entity counts
--       via 'mq.TLO.Raid.Members()', then loops sequentially to isolate characters. Instantly discards your local
--       character name and maps group criteria filters via 'mq.TLO.Group.Member(name)() ~= nil' to discard active group 
--       members. Applies alphabetical string sorting arrays to the remaining name stack.
--    -> INPUTS / PARAMETERS: None.
--    -> RAIDASSIST-SAFE: loadRaidNames NEVER changes the assist. If the raid returns 0 members, or the filtered
--       external-member list is empty, it only resets the local dropdown list/index and the hasRaidMembers flag —
--       a locked or detected assist is left completely untouched. When names are present it also re-points the
--       dropdown at the currently locked assist (currentRaidAssist) if that name is still in the raid.
--
-- 4) setRaidAssistAndExit()  [the "Set RaidAssist" button]
--    -> MECHANICS: References the sorted name stack using the active drop-down index value. Records the picked name
--       as `currentRaidAssist` (the source of truth), writes it to the E3 variable via '/e3varset RaidAssist <name>'
--       (for cross-box propagation), fires a raid-channel broadcast via '/rsay', and targets the newly selected
--       helper character.
--    -> SOLE MUTATOR / LOCK: This is the ONLY user action that changes the assist to a NEW value. Once set (or
--       detected at startup), nothing else in the script changes it; the automation and UI simply read it.
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
--    -> MECHANICS: The primary tactical tracking loops evaluated on every frame pass. Resolves the assist spawn
--       from `currentRaidAssist`. Manages:
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
-- 6b) isTurboLootRunning() / isLootWindowOpen() / updateLootTracking() / turboLootMovementBlocked()  (v3.3)
--    -> PROBLEM ADDRESSED: previously, the instant combat ended, the follow-resume logic would immediately issue
--       '/nav' or '/follow' toward the RaidAssist, which could yank the loot window shut, drag the toon off a
--       corpse mid-loot, or leave items behind if a looting script (e.g. TurboLoot) was running.
--    -> isTurboLootRunning(): checks mq.TLO.Lua.Script(TURBO_LOOT_SCRIPT_NAME).Status() and returns true if the
--       named script (default 'TurboLoot' — change TURBO_LOOT_SCRIPT_NAME near its declaration if your script
--       file is named differently) is RUNNING or STARTING. If it's never running, every check below is a no-op
--       and behavior is unchanged from pre-3.3.
--    -> isLootWindowOpen(): mq.TLO.Window('LootWnd').Open(), wrapped in pcall for safety.
--    -> updateLootTracking(currentTime): called every frame regardless of combat/pause state; records the last
--       time the loot window was seen open (lastLootWindowOpen) so a transition is never missed.
--    -> turboLootMovementBlocked(currentTime): the actual gate. Returns true (suppress movement) while the loot
--       window is open, for LOOT_SETTLE_MS (800ms) after it closes (in case TurboLoot immediately opens it again
--       on the next corpse), or for LOOT_INITIAL_GRACE_MS (2000ms) after combat ends if the window hasn't opened
--       yet at all (giving TurboLoot a moment to start). LOOT_MAX_WAIT_MS (8000ms) is a hard safety valve — no
--       matter how many corpses get looted in a row, movement suppression is force-lifted this many ms after
--       combat ended, so the toon can never stall indefinitely through a long multi-corpse loot session.
--    -> DESIGN NOTE (why this gates the command, not the state flag): an earlier revision gated the followAssist
--       STATE FLAG itself on looting being fully settled, with no upper bound. During heavy multi-corpse looting
--       the settle timer kept resetting, followAssist stayed paused for the whole loot phase, and the bot fell
--       permanently behind the raid — the assist engine (independent of followAssist) then correctly refused to
--       engage targets that were now out of radiusCheck range, so the bot silently stopped assisting altogether.
--       The fix leaves followAssist/followPausedForCombat on their original ~1s resume timer untouched, and only
--       suppresses the physical '/nav'/'/follow' command inside the followAssist-driven movement block (bounded
--       by LOOT_MAX_WAIT_MS), so the assist state machine is never starved of position updates for longer than
--       the safety valve allows.
--
-- 6c) navCanPathTo(spawnID)  — navmesh-aware follow fallback
--    -> PROBLEM ADDRESSED: the follow-toward-RaidAssist logic issues '/nav spawn id ...' whenever mq2nav is
--       loaded. But '/nav' silently does nothing useful if the current zone has no navmesh loaded, or if no path
--       exists from the toon's position to the RA (a mesh gap, a broken link, across water, etc.) — the toon
--       just stands still instead of closing distance.
--    -> MECHANICS: navCanPathTo(spawnID) checks mq.TLO.Navigation.MeshLoaded() and mq.TLO.Navigation.PathExists
--       ('spawn id <spawnID>') to determine whether '/nav' can actually route to the RA right now. The follow
--       block (inside executeAutomationLogic) calls this before every '/nav' attempt:
--         - Path available: behaves exactly as before — issues '/nav spawn id <ID> |distance=<approachDistance>'
--           when out of movementThreshold range and not already navigating.
--         - Path NOT available: falls back to a direct '/moveto mdist <approachDistance> id <ID>' every follow
--           tick instead of standing still, and keeps re-checking navCanPathTo() each cycle so it snaps back to
--           normal '/nav' the instant a path becomes available again (e.g. the toon walks back onto meshed
--           terrain, or the RA moves to a reachable area).
--    -> STATE TRACKING: navFallbackActive records whether the '/moveto' fallback is currently driving movement.
--       It's cleared (with an explicit '/moveto stop') everywhere follow is halted — combat suspension, the
--       manual Stop Follow button, and the normal in-range/path-restored cases — so the fallback never keeps
--       running after follow itself has stopped.
--    -> DEFENSIVE BY DESIGN: if the installed mq2nav build doesn't expose MeshLoaded/PathExists, or the TLO query
--       errors for any reason, navCanPathTo() assumes normal navigation is fine (pcall-wrapped, fails open) — so
--       this feature can never regress behavior on setups where those TLO members aren't available.
--
-- 7) drawUI()
--    -> MECHANICS: Renders the graphical user control panel overlay via the ImGui rendering pipe. Enforces open state
--       via 'ImGuiCond.Always'. UI layout order (top to bottom):
--         - RaidAssist Enemy Target display
--         - Current NPC Targeted display
--         - Current RaidAssist name and combat status (COMBAT / IDLE / OUT OF ZONE) — read from currentRaidAssist,
--           so it updates the instant you press Set.
--         - Raid member dropdown + Refresh button (hidden when not in raid)
--         - Set RaidAssist button | Exit Script button (red, horizontally centered — drawExitButton())
--         [Visible only when a valid RaidAssist is set:]
--         - NPC Target Radius Check label (displays current radiusCheck value in feet) + slider
--             Slider range: 10–100 feet in increments of 5 (default: 35 feet). Internally operates on a
--             scaled range (2–20) multiplied by 5 to enforce discrete 5-foot stepping. Only rendered when
--             RaidAssist is valid.
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
--    -> CHEVRON = SWAP TO ICON (not a real minimise): After ImGui.Begin, drawUI checks ImGui.IsWindowCollapsed().
--       When the chevron is clicked, the window is IMMEDIATELY un-collapsed (ImGui.SetWindowCollapsed(false)) so the
--       native "minimise to a title bar" never actually shows; instead the script swaps to the icon exactly like the
--       /rbot command (minimized = true, showWindow = true) and prints "View toggled to: icon". See MINIMISE-TO-ICON.
--
-- 8) renderIcon()
--    -> MECHANICS: Draws the minimised view: a small borderless, background-less, auto-sized window whose only
--       content is the swap image (raidassist_image.png), drawn at its true aspect ratio. The texture is loaded once
--       at startup with mq.CreateTexture (after an io.open existence check) into iconImg; the PNG's real dimensions
--       are read from its header (readPngSize) and scaled so the longest side equals ICON_MAX, preserving proportion.
--    -> INTERACTION: The image is a plain image (not a button), so the borderless window can be DRAGGED by it to
--       reposition the icon. A click (press + release with no drag) RESTORES the full window (minimized = false,
--       forceExpand = true so it reopens expanded) and prints "View toggled to: window". A press that moves is a drag
--       and does NOT restore.
--    -> FALLBACK: If the image file is missing or fails to load, a small "RA" button is shown instead so
--       minimise/restore still works. A startup console line reports whether the icon loaded, its path, and drawn size.
--
-- 9) renderUI()
--    -> MECHANICS: The single callback registered with mq.imgui.init. Dispatches each frame: returns early if
--       showWindow is false; otherwise draws renderIcon() when minimized is true, or drawUI() when not.
--
-- =========================================================================================================
--  RAIDASSIST PERSISTENCE & LOCK MODEL
-- =========================================================================================================
--  The assist name lives in the Lua variable `currentRaidAssist` (the source of truth for all reads). Design goals:
--  (1) the script never changes the assist on its own, and (2) a set/detected assist survives zoning and roster blips.
--    • SET (new value): ONLY the Set RaidAssist button (setRaidAssistAndExit) sets a new assist. It updates
--      currentRaidAssist and writes '/e3varset RaidAssist <name>' for cross-box propagation.
--    • STARTUP DETECTION: At launch the script reads the persisted assist from E3 via the MQ2Mono query
--        mq.TLO.MQ2Mono.Query('e3,E3Bots(' .. mq.TLO.Me.CleanName() .. ').Query(RaidAssistName)')
--      If that returns a real name (anything other than "NOBODY", empty, null, or an unresolved '$' value), the
--      script adopts it: currentRaidAssist = <name>, writes it into the working RaidAssist via '/e3varset', and points
--      the dropdown at it. This lets you exit and restart without re-setting. If it is unset or "NOBODY", it prints
--      that no active assist was detected and waits for a manual Set.
--    • NO AUTOMATIC RE-PUSH: There is no per-frame or background re-write of the E3 variable. Writes happen only on
--      the Set button and at startup detection. (This is what stopped the constant '/e3varset' loop.)
--    • loadRaidNames and the Refresh buttons never change the assist; they only rebuild the dropdown list.
--    • "NOBODY" is E3's unset sentinel and is treated everywhere (detection + isRaidAssistValid) as "no assist".
--  READ vs WRITE VARIABLES: the script READS `currentRaidAssist` (Lua) for all behavior; it WRITES the E3 variable
--  with '/e3varset RaidAssist ...' and READS the persisted value at startup via the E3Bots(...).Query(RaidAssistName)
--  TLO. The parser variable '${RaidAssist}' is intentionally NOT used for live reads because it lags the E3 write.
--
-- =========================================================================================================
--  MINIMISE-TO-ICON  (swap window <-> image)
-- =========================================================================================================
--  The main window can be shrunk to a small clickable image and back.
--    • IMAGE: raidassist_image.png, loaded from the SAME directory as this init.lua (SCRIPT_DIR is resolved
--      from debug.getinfo so it works wherever the script folder is placed). Drawn at its true aspect ratio (read
--      from the PNG header) scaled so its longest side equals ICON_MAX pixels — a non-square image is not stretched.
--    • MINIMISE: click the title-bar chevron. The window is un-collapsed on the same frame and swapped to the icon
--      (behaves like /rbot, never leaving a collapsed title bar). Prints "View toggled to: icon".
--    • RESTORE: click the icon image (press+release, no drag). Prints "View toggled to: window". Dragging moves it.
--    • FALLBACK: if the image is absent/unloadable, an "RA" button stands in for the image.
--    • Tunables: ICON_PATH, ICON_MAX (longest side in pixels; aspect preserved), ICON_PAD.
--    • PERSISTENCE ACROSS RESTARTS (no file I/O): the current mode (window/icon) is stored in an MQ
--      outer variable, RaidAssistBotViewState ("icon" or "window"), set every time the mode changes
--      (chevron, icon click, or /rbot). Outer variables live in MacroQuest's own memory, independent of
--      the Lua VM, so the value survives a script stop/restart within the same MQ session — the same
--      mechanism used for RaidAssist. At launch, `minimized` is initialized from that variable
--      (loadViewState()), so exiting and relaunching the script reopens in whichever mode it was last
--      left in instead of always resetting to the full window. (Note: this does not persist across a
--      full MacroQuest/game restart, since outer variables do not survive that — only a script
--      stop/restart within the same MQ session.)
--
-- =========================================================================================================
--  SLASH COMMANDS
-- =========================================================================================================
--  /rbot  — Toggles the swap-to-icon (minimise) state and prints "View toggled to: icon" or "View toggled to:
--           window". If the full window is showing it minimises to the image; if minimised it restores the full
--           window, reopened expanded. The window is never fully hidden — there is always either the window or the
--           icon on screen. Takes no arguments. The title-bar chevron (to icon) and clicking the icon (to window)
--           produce the same behavior and the same toggle messages.
-- =========================================================================================================

local mq = require('mq')
local ImGui = require('ImGui')

local SCRIPT_VERSION = '3.3'   -- shown in the main window title bar

-- Resolve this script's own directory early (used for the icon image AND the
-- view-state persistence file below). Keeps the trailing path separator.
local SCRIPT_DIR = (debug.getinfo(1, 'S').short_src or ''):match('^(.*[/\\])')
                   or ((mq.luaDir or '.') .. '/')

-- ============================================================
--  View-state persistence (window vs icon) — NO FILE I/O
--  Lua variables reset on every script relaunch, but MQ "outer" variables are held
--  in MacroQuest's own memory, independent of the Lua VM, so they survive a script
--  stop/restart within the same MQ session — exactly like RaidAssist itself. We use
--  that mechanism instead of writing to disk: an outer variable named
--  RaidAssistBotViewState stores "icon" or "window" and is read back at launch.
-- ============================================================
local VIEW_STATE_VAR = 'RaidAssistBotViewState'
local viewStateDeclareAttempted = false  -- one-shot guard: /declare is queued async, so
                                          -- ${Defined[...]} can still read FALSE for
                                          -- several calls in the same frame before MQ
                                          -- actually processes the first /declare.

local function ensureViewStateDeclared()
    if viewStateDeclareAttempted then return end
    viewStateDeclareAttempted = true
    if mq.parse('${Defined[' .. VIEW_STATE_VAR .. ']}') ~= 'TRUE' then
        mq.cmdf('/declare %s string outer "window"', VIEW_STATE_VAR)
    end
end

local function saveViewState(isMinimized)
    ensureViewStateDeclared()
    mq.cmdf('/varset %s %s', VIEW_STATE_VAR, isMinimized and 'icon' or 'window')
end

local function loadViewState()
    ensureViewStateDeclared()
    local val = mq.parse('${' .. VIEW_STATE_VAR .. '}')
    return val == 'icon'
end

-- Structural Interface Viewport Control Variables
local showWindow = true
local forceExpand = false
-- Minimise-to-icon state (chevron collapses the window into a clickable image).
-- Initialized from the saved view-state file so the script reopens in whichever
-- mode (window or icon) it was last left in, rather than always starting expanded.
local minimized   = loadViewState()   -- true → show the icon instead of the main window
local iconPressed = false   -- mouse button is down having pressed on the icon
local iconDragged = false   -- that press moved → treat as a drag (move), not a click
-- Icon placement: remember the main window's on-screen center so the icon appears
-- centered there each time we minimise, making it easy to find before dragging it.
local mainWinCenterX = nil
local mainWinCenterY = nil
local placeIconAtCenter = false   -- one-shot: position the icon on the next icon frame
local iconOpen = true             -- p_open for the icon window (mirrors menu_bar's `open`)
local done = false
local selectedIndex = 1
local names = {}
local currentRaidAssist = ""   -- locked RA name; only the Set button changes this
local followAssist = false
local hasRaidMembers = false 
local followPausedForCombat = false 
local navFallbackActive = false     -- true while we're using /moveto because mq2nav can't path to the RA
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
local radiusCheck = 35

local raidAssistDeclareAttempted = false  -- one-shot guard: /declare is queued async via
                                           -- mq.cmd, but ${Defined[...]} is evaluated
                                           -- synchronously via mq.parse. isRaidAssistValid()
                                           -- (and therefore this function) fires many times
                                           -- per frame (main loop + every ImGui redraw), so
                                           -- on startup several calls can see Defined==FALSE
                                           -- before the first queued /declare has actually
                                           -- run, each queuing its own /declare. The first
                                           -- succeeds; every one after it fails with
                                           -- "RaidAssist already exists". Latching on the
                                           -- Lua side after the first attempt prevents that.
local function ensureRaidAssistDeclared()
    if raidAssistDeclareAttempted then return end
    raidAssistDeclareAttempted = true
    if mq.parse('${Defined[RaidAssist]}') ~= 'TRUE' then
        mq.cmd('/declare RaidAssist string outer ""')
    end
    -- NOTE: no per-frame re-push here. The script's own value (currentRaidAssist) is
    -- the source of truth for all reads, and it survives zoning as long as the script
    -- runs. The E3 variable is written only on deliberate events (the Set button and
    -- startup detection), so we never spam /e3varset every frame.
end

local function isRaidAssistValid()
    ensureRaidAssistDeclared()
    -- Use the script's own immediately-updated value, not the parser variable
    -- ${RaidAssist}, which lags behind /e3varset writes.
    local currentRA = currentRaidAssist
    if not currentRA or currentRA == "" or currentRA == "NULL" or currentRA == "string" or currentRA == '""' or currentRA == "''" then
        return false
    end
    if currentRA:upper() == "NOBODY" then   -- E3 "unset" sentinel
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
        -- Do NOT change RaidAssist here. Loading the name list must never alter a
        -- locked/detected assist; only the Set RaidAssist button changes it.
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
        -- Again, never change RaidAssist here.
    else
        hasRaidMembers = true
        if selectedIndex > #names then selectedIndex = 1 end
        -- Keep the dropdown pointed at the locked RA if it's still in the list.
        if currentRaidAssist ~= "" then
            for i, n in ipairs(names) do
                if n == currentRaidAssist then selectedIndex = i break end
            end
        end
    end
end

local function setRaidAssistAndExit()
    if not hasRaidMembers or #names == 0 then return end
    local picked = names[selectedIndex]
    if not picked or picked == '' then return end

    ensureRaidAssistDeclared()
    currentRaidAssist = picked   -- user-initiated change (Set button): lock this name
    mq.cmd('/squelch /target clear')
    mq.cmdf('/e3varset RaidAssist %s', picked)
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

-- ============================================================
--  TurboLoot-aware movement suppression
--  Problem: right after combat ends the script used to immediately /nav or
--  /follow toward the RaidAssist, which can yank the loot window shut or drag
--  the toon off a corpse mid-loot if TurboLoot is running.
--  Fix: detect whether a script named TURBO_LOOT_SCRIPT_NAME is loaded via the
--  Lua TLO. If so, suppress just the /nav|/follow movement commands (not the
--  followAssist state flag itself) while the loot window is open, plus a short
--  settle buffer after it closes in case TurboLoot immediately moves to the
--  next corpse. LOOT_MAX_WAIT_MS is a hard safety valve: no matter how many
--  corpses get looted in a row, movement suppression is force-lifted once that
--  much time has passed since combat ended, so the toon can never fall
--  permanently behind the raid during a long multi-corpse loot session.
--  followAssist/followPausedForCombat themselves resume on their normal timer
--  regardless — this only holds back the physical movement commands, so the
--  assist state machine (which is independent of followAssist) is never
--  starved of position updates for longer than the safety valve allows.
--  If TurboLoot isn't running at all, this is always a no-op.
-- ============================================================
local TURBO_LOOT_SCRIPT_NAME   = 'TurboLoot'  -- adjust to match the actual script filename if different
local LOOT_SETTLE_MS           = 800   -- brief buffer after the loot window closes, in case another opens right away
local LOOT_INITIAL_GRACE_MS    = 2000  -- how long to wait after combat ends for looting to even start
local LOOT_MAX_WAIT_MS         = 8000  -- hard cap: force-resume movement no matter what after this long
local LOOT_WINDOW_NAME         = 'LootWnd'

local wasInCombat        = false
local combatEndTime      = 0     -- timestamp (ms) combat last transitioned to false
local lastLootWindowOpen = 0     -- timestamp (ms) the loot window was last observed open (0 = never seen this cycle)

local function isTurboLootRunning()
    local ok, status = pcall(function()
        return mq.TLO.Lua.Script(TURBO_LOOT_SCRIPT_NAME).Status()
    end)
    if not ok or not status or status == '' or status == 'NULL' then return false end
    return status == 'RUNNING' or status == 'STARTING'
end

local function isLootWindowOpen()
    local ok, isOpen = pcall(function() return mq.TLO.Window(LOOT_WINDOW_NAME).Open() end)
    if not ok then return false end
    return isOpen == true
end

-- Call every frame regardless of combat state so we never miss a loot window
-- open/close transition while other logic is short-circuiting elsewhere.
local function updateLootTracking(currentTime)
    if isLootWindowOpen() then
        lastLootWindowOpen = currentTime
    end
end

-- Returns true only when the /nav or /follow command should be withheld this
-- tick. Never returns true past LOOT_MAX_WAIT_MS since combat ended.
local function turboLootMovementBlocked(currentTime)
    if not isTurboLootRunning() then return false end
    if combatEndTime > 0 and (currentTime - combatEndTime) > LOOT_MAX_WAIT_MS then
        return false  -- safety valve: never withhold movement indefinitely
    end
    if isLootWindowOpen() then return true end
    if lastLootWindowOpen > 0 then
        return (currentTime - lastLootWindowOpen) < LOOT_SETTLE_MS
    end
    -- Loot window never opened this cycle yet; give TurboLoot a brief window
    -- to actually get around to looting before we let movement proceed.
    if combatEndTime > 0 and (currentTime - combatEndTime) < LOOT_INITIAL_GRACE_MS then
        return true
    end
    return false
end

-- Checks whether mq2nav can actually route to the given spawn ID right now
-- (mesh loaded for the zone AND a path exists to that spawn). Used to decide
-- whether /nav is safe to use for following, or whether we need to fall back
-- to a straight-line /moveto instead. Defensive by design: if the installed
-- mq2nav build doesn't expose MeshLoaded/PathExists, or the query errors out,
-- this assumes normal navigation is fine so we never change behavior for
-- setups where these TLO members aren't available.
local function navCanPathTo(spawnID)
    local ok, result = pcall(function()
        if mq.TLO.Navigation.MeshLoaded() == false then return false end
        local exists = mq.TLO.Navigation.PathExists(string.format('spawn id %d', spawnID))()
        if exists == nil then return true end
        return exists and true or false
    end)
    if not ok then return true end
    return result
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

    -- Track combat start/end transitions so the TurboLoot gate knows when to
    -- start its grace timer, and reset stale loot-tracking state from any
    -- previous fight once a new one begins.
    if amIInCombat and not wasInCombat then
        combatEndTime = 0
        lastLootWindowOpen = 0
    elseif not amIInCombat and wasInCombat then
        combatEndTime = currentTime
    end
    wasInCombat = amIInCombat

    -- Keep loot-window tracking current every frame, independent of combat
    -- state or the pauseAssist/anchor gates below.
    updateLootTracking(currentTime)

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
                if navFallbackActive then
                    mq.cmd('/moveto stop')
                    navFallbackActive = false
                end
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
        if isRaidAssistValid() and not turboLootMovementBlocked(currentTime) then
            local followRAName = currentRaidAssist
            local followRASpawn = mq.TLO.Spawn(string.format("pc =%s", followRAName))
            if followRASpawn and followRASpawn() then
                if mq.TLO.Plugin('mq2nav').IsLoaded() then
                    local distanceToTarget = followRASpawn.Distance() or 0
                    if distanceToTarget > movementThreshold then
                        if navCanPathTo(followRASpawn.ID()) then
                            -- Normal navmesh routing is available (again). Drop out of the
                            -- /moveto fallback if we were in it, then let /nav do the work.
                            if navFallbackActive then
                                mq.cmd('/moveto stop')
                                navFallbackActive = false
                            end
                            if not mq.TLO.Navigation.Active() then
                                mq.cmdf('/nav spawn id %d |distance=%d', followRASpawn.ID(), approachDistance)
                            end
                        else
                            -- mq2nav can't route to the RA right now (no mesh loaded for this
                            -- zone, or no path exists from here — e.g. a mesh gap or the RA is
                            -- across water/a broken link). Keep closing distance with a direct
                            -- /moveto instead of standing still, and keep re-checking navCanPathTo
                            -- above every cycle so we snap back to normal /nav the instant a path
                            -- is available again.
                            navFallbackActive = true
                            mq.cmdf('/moveto mdist %d id %d', approachDistance, followRASpawn.ID())
                        end
                    elseif navFallbackActive then
                        mq.cmd('/moveto stop')
                        navFallbackActive = false
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

    local raName = currentRaidAssist
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

-- ============================================================
--  Minimise-to-icon: image + texture loading
--  Clicking the title-bar chevron collapses the main window into a
--  small clickable image (raidassist_image.png). Clicking the image
--  restores the window; dragging it repositions the icon.
-- ============================================================

-- SCRIPT_DIR is resolved once, near the top of the file (also used by view-state
-- persistence). Reused here for the icon image path.
local ICON_PATH  = SCRIPT_DIR .. 'raidassist_image.png'
local ICON_MAX   = 48   -- longest side of the drawn image (pixels); aspect is preserved
local ICON_PAD   = 0    -- window padding around the minimised image (0 = hug it)

-- Read a PNG's true pixel dimensions from its IHDR header (no image library needed).
-- Returns width, height or nil. Used to draw the icon at its real aspect ratio so a
-- non-square source image is not stretched into a square (which looked distorted).
local function readPngSize(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local header = f:read(24)
    f:close()
    if not header or #header < 24 then return nil end
    -- PNG signature: 0x89 'P' 'N' 'G' ...
    if header:byte(1) ~= 0x89 or header:sub(2, 4) ~= 'PNG' then return nil end
    local function be32(s, i)
        local a, b, c, d = s:byte(i, i + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    -- IHDR width is bytes 17-20, height is bytes 21-24 (1-indexed).
    return be32(header, 17), be32(header, 21)
end

-- Load the icon texture once. Confirm the file exists first, because
-- mq.CreateTexture can return a non-nil blank texture for a missing path.
-- If it is absent (or the build lacks mq.CreateTexture), iconImg stays nil
-- and the minimised view falls back to a small "RA" button.
local iconImg    = nil
local iconLoaded = false
-- Drawn dimensions, defaulting to a square; recomputed from the PNG's real size below.
local iconDrawW  = ICON_MAX
local iconDrawH  = ICON_MAX
do
    local f = io.open(ICON_PATH, 'rb')
    if f then
        f:close()
        local ok, tex = pcall(mq.CreateTexture, ICON_PATH)
        if ok and tex then
            iconImg    = tex
            iconLoaded = true
            -- Compute aspect-preserving draw size from the file's true dimensions,
            -- scaling so the longest side equals ICON_MAX.
            local nw, nh = readPngSize(ICON_PATH)
            if nw and nh and nw > 0 and nh > 0 then
                local scale = ICON_MAX / math.max(nw, nh)
                iconDrawW = math.floor(nw * scale + 0.5)
                iconDrawH = math.floor(nh * scale + 0.5)
            end
        end
    end
end

if iconLoaded then
    print(string.format("\am[\atRaidAssistBot\am]\ay Minimise icon loaded: \ag%s\ax \aw(%dx%d)\ax", ICON_PATH, iconDrawW, iconDrawH))
else
    print(string.format("\am[\atRaidAssistBot\am]\ar No minimise icon\ax at %s \aw(minimised view will show an \"RA\" button)\ax", ICON_PATH))
end

-- Borderless, auto-sized window that shows only the icon while minimised.
local MIN_FLAGS = bit32.bor(ImGuiWindowFlags.AlwaysAutoResize,
                            ImGuiWindowFlags.NoResize,
                            ImGuiWindowFlags.NoScrollbar,
                            ImGuiWindowFlags.NoTitleBar,
                            (ImGuiWindowFlags.NoBackground or 0))  -- no panel/border box

local function renderIcon()
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, ICON_PAD, ICON_PAD)

    local visible
    iconOpen, visible = ImGui.Begin('RaidAssist Bot Icon###RaidAssistMini', iconOpen, MIN_FLAGS)
    if visible then
        local restore = false

        if iconImg then
            -- Draw the icon as a plain image (not a button). A plain image is
            -- non-interactive, so ImGui lets the borderless window be dragged by
            -- it — giving us "drag the image to move" for free. Restoring is
            -- handled below by detecting a click (press + release with no drag).
            -- NOTE: this is the exact draw call used by the working menu_bar.lua.
            local ok = pcall(function()
                ImGui.Image(iconImg:GetTextureID(), ImVec2(iconDrawW, iconDrawH))
            end)

            if ok then
                local hovered = ImGui.IsItemHovered()
                if hovered and not iconPressed then
                    ImGui.SetTooltip('RaidAssist Bot — drag to move, click to restore')
                end
                if hovered and ImGui.IsMouseClicked(0) then
                    iconPressed = true
                    iconDragged = false
                end
                if iconPressed and ImGui.IsMouseDragging(0) then
                    iconDragged = true
                end
                if ImGui.IsMouseReleased(0) then
                    if iconPressed and not iconDragged then
                        restore = true
                    end
                    iconPressed = false
                    iconDragged = false
                end
            else
                iconImg = nil
            end
        end

        if not iconImg then
            if ImGui.Button('RA##restore') then restore = true end
        end

        if restore then
            minimized   = false
            forceExpand = true   -- un-collapse the main window next frame
            saveViewState(minimized)
            print(string.format("\am[\atRaidAssistBot\am]\ay View toggled to\ao: \ag%s\ax", "window"))
        end
    end

    ImGui.End()
    ImGui.PopStyleVar()
end

-- Draws the "Exit Script" button in red, horizontally centered in the current window.
local function drawExitButton()
    local label = 'Exit Script'
    local btnW  = 120
    local okSize, tw = pcall(function() return ImGui.CalcTextSize(label) end)
    if okSize and tw then
        btnW = tw + 24   -- pad around the text like a normal button
    end
    local winW = 0
    local okWin, ww = pcall(function() return ImGui.GetWindowSize() end)
    if okWin and ww then winW = ww end
    if winW > btnW then
        ImGui.SetCursorPosX((winW - btnW) * 0.5)
    end

    ImGui.PushStyleColor(ImGuiCol.Button, 0.7, 0.1, 0.1, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.85, 0.15, 0.15, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.55, 0.05, 0.05, 1.0)
    if ImGui.Button(label, btnW, 0) then done = true end
    ImGui.PopStyleColor(3)
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

    local shouldDraw, openRef = ImGui.Begin('RaidAssist Bot v' .. SCRIPT_VERSION, true, ImGuiWindowFlags.AlwaysAutoResize)
    if not openRef then showWindow = false end

    -- Chevron clicked → ImGui would natively collapse the window to a title bar.
    -- We don't want that "minimize". Instead, immediately un-collapse it and swap to
    -- the icon, exactly like the /rbot command does. Un-collapsing on the same frame
    -- means the collapsed title bar never actually shows.
    if ImGui.IsWindowCollapsed() then
        local okc = pcall(function() ImGui.SetWindowCollapsed(false, ImGuiCond.Always) end)
        if not okc then pcall(function() ImGui.SetWindowCollapsed(false) end) end
        minimized  = true
        showWindow = true
        saveViewState(minimized)
        print(string.format("\am[\atRaidAssistBot\am]\ay View toggled to\ao: \ag%s\ax", "icon"))
        ImGui.End()
        return
    end
	
    if shouldDraw then
        -- Remember this window's on-screen center so the minimised icon can be
        -- placed there (see renderIcon). Wrapped in pcall for binding-signature safety.
        pcall(function()
            local wx, wy = ImGui.GetWindowPos()
            local ww, wh = ImGui.GetWindowSize()
            if wx and ww then
                mainWinCenterX = wx + ww * 0.5
                mainWinCenterY = wy + wh * 0.5
            end
        end)

        local myTarget = mq.TLO.Target
        local amIAttacking = mq.TLO.Me.Combat() or false
        -- Display/act on the script's own immediately-updated value rather than the
        -- parser variable ${RaidAssist}, which lags behind /e3varset writes and would
        -- otherwise show the previous name right after pressing Set.
        local currentRA = currentRaidAssist

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
                        if navFallbackActive then
                            mq.cmd('/moveto stop')
                            navFallbackActive = false
                        end
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
            drawExitButton()
        else
            ImGui.Separator()
            drawExitButton()
        end
    end
    ImGui.End()
end

-- Baseline Startup Initializations
loadRaidNames()

-- Detect an already-set RaidAssist at startup and lock onto it. The initial assist is
-- read from E3 via the MQ2Mono query (E3Bots(<me>).Query(RaidAssistName)). If it holds a
-- real name (anything other than "NOBODY", empty, or null), we adopt it as the current
-- assist AND write it into the working RaidAssist so the automation uses it immediately —
-- this covers exiting and restarting the script without having to re-set the assist.
-- Only the UI buttons change it after this.
do
    ensureRaidAssistDeclared()
    local existing = nil
    pcall(function()
        existing = mq.TLO.MQ2Mono.Query('e3,E3Bots(' .. mq.TLO.Me.CleanName() .. ').Query(RaidAssistName)')()
    end)
    existing = existing and tostring(existing) or ""
    local upper = existing:upper()
    if existing ~= "" and upper ~= "NULL" and upper ~= "NOBODY"
       and existing ~= "string" and existing ~= '""' and existing ~= "''"
       and not existing:find('%$') then
        currentRaidAssist = existing
        -- Set the working RaidAssist so the combat automation uses it right away.
		mq.cmdf('/e3varset RaidAssist %s', existing)
        for i, n in ipairs(names) do
            if n == existing then selectedIndex = i break end
        end
        print(string.format("\am[\atRaidAssistBot\am]\ay Detected existing RaidAssist (E3), locked onto: \am[\ag %s \am]\ax", existing))
    else
        print("\am[\atRaidAssistBot\am]\ay No active RaidAssist detected (unset or NOBODY) — set one via the UI.\ax")
    end
end

mq.bind('/rbot', function()
    -- Toggle the swap-to-icon (minimise) state instead of hiding the window.
    minimized  = not minimized
    showWindow = true               -- always keep something rendered (icon or window)
    if minimized then
        placeIconAtCenter = true    -- minimising → center the icon so it's easy to find
    else
        forceExpand = true          -- restoring → reopen the full window expanded
    end
    saveViewState(minimized)
    print(string.format("\am[\atRaidAssistBot\am]\ay View toggled to\ao: \ag%s\ax", minimized and "icon" or "window"))
end)

-- Dispatcher: show the clickable icon when minimised, otherwise the full window.
local function renderUI()
    if not showWindow then return end

    -- Run the automation/follow state machine every UI tick regardless of whether
    -- the icon or the full window is currently being shown. Previously this only
    -- ran from inside drawUI(), so swapping to the icon view silently froze the
    -- assist engine and follow logic even though the icon kept rendering fine.
    executeAutomationLogic()

    if minimized then
        renderIcon()
    else
        drawUI()
    end
end

mq.imgui.init('RaidAssistBotUI', renderUI)

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

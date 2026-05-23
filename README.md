
                                        RAIDASSIST BOT SYSTEM DOCUMENTATION

-- OVERVIEW & ARCHITECTURE:
-- This MacroQuest Lua script operates an asynchronous frame polling execution engine layout. By shifting
-- background automation routines directly into the ImGui draw tick layer, the thread tracks environment
-- data synchronously with client graphics cycles, entirely eliminating instant-close crashes or thread drift.
--
-- DETAILED FUNCTION DIRECTORY & STRUCTURAL SPECIFICATIONS:
-----------------------------------------------
-- 1) ensureRaidAssistDeclared()
--    -> MECHANICS: Probes the MacroQuest system variable tables using the parsing verification string
--       token '${Defined[RaidAssist]}'. If the result returns false, it issues a raw system memory insertion:
--       '/declare RaidAssist string outer ""' to stand up an unallocated outer variable placeholder.
--    -> INPUTS / PARAMETERS: None.
--    -> OPERATIONAL IMPACT: Establishes global macro variable permanence so parallel client systems can view
--       the current target assignments across boxing networks.
-----------------------------------------------
-- 2) isRaidAssistValid()
--    -> MECHANICS: Extracts the string contents stored inside the global character RaidAssist TLO variable.
--       Applies a multi-stage cascade trap to catch uninitialized memory signatures, empty lines, null markers,
--       or literal quote combinations ("" or '').
--    -> INPUTS / PARAMETERS: None.
--    -> RETURNS: Boolean [true] if a usable, non-blank name is found; boolean [false] if unassigned.
-----------------------------------------------
-- 3) loadRaidNames()
--    -> MECHANICS: Queries the game client's active raid data profile tables. Pulls full entity counts
--       via 'mq.TLO.Raid.Members()', then loops sequentially to isolate characters. Instantly discards your local
--       character name and maps group criteria filters via 'mq.TLO.Group.Member(name)() ~= nil' to discard active group 
--       members. Applies alphabetical string sorting arrays to the remaining name stack.
--    -> INPUTS / PARAMETERS: None.
--    -> ERROR HANDLING: If the character disbands or leaves a raid entirely (returning 0 members), it clears the 
--       selection arrays, forces the drop-down index to position 1, and wipes global macro variables to an empty line.
-----------------------------------------------
-- 4) setRaidAssistAndExit()
--    -> MECHANICS: References the sorted name stack using the active drop-down index value. Commits the string 
--       to the outer macro global, fires a cross-client broadcast text alert down the raid channel network using '/rsay',
--       and automatically issues an audio-visual target selection packet to track the newly selected helper character.
--    -> INPUTS / PARAMETERS: None.
--    -> DATA SANITIZATION: Resets all combat thread sequencers back to Step 0 (Idle) and zero-clears target identifier
--       memory numbers to guarantee target switching does not cause command bouncing during pulls.
-----------------------------------------------
-- 5) broadcastGroupFollow(actionType)
--    -> MECHANICS: Manages multi-boxed character movement states using specialized group broadcast networks.
--    -> PARAMETERS: actionType [String literal matching "START" or "STOP"].
--       - "START": Pulls your character's exact numeric entity identity key ('mq.TLO.Me.ID()') and forwards a 
--         zone-wide mesh navigation order ('/e3bcgz /nav spawn id [ID]') to pull accounts to your exact vectors. 
--         Fires a secondary frame call command '/followme 10' to coordinate immediate regional boxes.
--       - "STOP": Assembles a safe multi-line packet shortcut string via '/multiline' sent across network channels 
--         to instantly terminate navigation loops, drop active follows via '/followoff', and tap backward keys to kill momentum.
-----------------------------------------------
-- 6) executeAutomationLogic()
--    -> MECHANICS: The primary tactical tracking loops evaluated on every frame pass. Manages three sections:
--       A) Active Target Lifespan Invalidation: Tracks the target's status via numerical memory identifiers. 
--          If your enemy target dies or disappears, it clears state variables and jumps to Step 0 in under 1ms.
--       B) State Machine Combat Sequencing:
--          - STEP 0 (The Filtering Scanner): Automatically triggers assist via '/rsay' strictly once per creature.
--            Checks if RA target is an NPC, has dropped to or below 99% health, AND is within radiusCheck feet.
--            The radiusCheck distance is user-configurable via the UI slider (range: 30–100 feet, step: 5).
--          - STEP 1 (Melee Approach & Engage): Squares up client angles via '/face' and fires high-speed directional
--            movement shortcuts ('/moveto mdist 10 id [ID]') to step your character right to 5ft melee thresholds.
--          - STEP 2 (Hate Registration Sync): Triggers an '/assistme' call exactly once per target, if group size > 0.
--          - STEP 3 (Snappy Reset Clearance): Throttles thread states using a compressed 300ms cushion window.
--       C) Dynamic Follow Intercept Suspension: Temporarily suspends follow routines in combat, resuming automatically when clear.
--       D) Proximity NPC Scanning: SpawnCount and NearestSpawn radius queries use radiusCheck feet as their scan
--          boundary, matching the same configurable distance applied to RA target filtering.
--    -> DEFENSIVE ENHANCEMENT: Removed frame-flash assists from drawUI to prevent infinite targeting loops when a mob dies.
-----------------------------------------------
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
--             Slider range: 30–100 feet in increments of 5. Internally operates on a scaled range (6–20)
--             multiplied by 5 to enforce discrete 5-foot stepping. Only rendered when RaidAssist is valid.
--         - Announce toggle button (ON/OFF) | Follow Assist toggle button (START / STOP / Paused)
-----------------------------------------------
<img width="333" height="181" alt="RaidAsist_Bot_Image_1" src="https://github.com/user-attachments/assets/26b8f5fe-6a3f-4f77-a097-793dd7765288"/>
<br>
<img width="413" height="253" alt="RaidAsist_Bot_Image_2" src="https://github.com/user-attachments/assets/b0e4d8c2-7f2d-4b99-a5eb-8108a6db6674"/>
<br>
<img width="407" height="285" alt="RaidAsist_Bot_Image_3" src="https://github.com/user-attachments/assets/55bdea90-34a4-411c-9184-54314149d4db"/>
<br>
<img width="411" height="279" alt="RaidAsist_Bot_Image_4" src="https://github.com/user-attachments/assets/75f08761-59d9-441d-b3bf-0ca3d8506a92"/>
<br>
<img width="407" height="277" alt="RaidAsist_Bot_Image_5" src="https://github.com/user-attachments/assets/78a2c5c5-816f-41c2-b91d-d452e1fe1f90"/>
<br>
<img width="539" height="193" alt="RaidAsist_Bot_Image_6" src="https://github.com/user-attachments/assets/87e6ca58-72fe-4f39-ba55-bb4afb2465c0"/>
<br>

$ErrorActionPreference = 'Stop'

# Load all 460 named actions + their console pad bindings and live flags from action_table.txt
$tablePath = '$PSScriptRoot\..\docs\action_table.txt'
$fivemPath = '$PSScriptRoot\..\docs\fivem_controls.txt'
$actionsListPath = '$PSScriptRoot\..\data\controls-actions.txt'

$actions = [ordered]@{}
foreach ($line in Get-Content $tablePath) {
    if ($line -match '^(INPUT_\S+)\s+#(\d+)\s+([0-9A-F]{8})\s+fl\s+([0-9A-F]+)\s*(.*)$') {
        $actions[$Matches[1]] = @{
            idx   = [int]$Matches[2]
            id    = $Matches[3]
            flags = $Matches[4]
            pad   = $Matches[5].Trim()
        }
    }
}
Write-Host "Loaded $($actions.Count) actions from action_table.txt"

# Load FiveM GTA V Enhanced PC defaults
$fivemMap = @{}
$keyNorm = @{
    'SPACEBAR' = 'Space'; 'LEFT SHIFT' = 'Shift'; 'LEFT CTRL' = 'Ctrl'; 'LEFT CONTROL' = 'Ctrl'
    'LEFT ALT' = 'Alt'; 'TAB' = 'Tab'; 'ESC' = 'Esc'; 'ENTER' = 'Enter'; 'BACKSPACE' = 'Backspace'
    'CAPSLOCK' = 'CapsLock'; 'INSERT' = 'Insert'; 'DELETE' = 'Delete'; 'HOME' = 'Home'; 'END' = 'End'
    'PAGE UP' = 'PageUp'; 'PAGEUP' = 'PageUp'; 'PAGE DOWN' = 'PageDown'; 'PAGEDOWN' = 'PageDown'
    'ARROW UP' = 'ArrowUp'; 'ARROW DOWN' = 'ArrowDown'; 'ARROW LEFT' = 'ArrowLeft'; 'ARROW RIGHT' = 'ArrowRight'
    '.' = 'Period'; ',' = 'Comma'; '=' = 'Equals'; 'MINUS' = 'Minus'; '[' = 'LeftBracket'; ']' = 'RightBracket'
    'LEFT MOUSE BUTTON' = 'LeftClick'; 'RIGHT MOUSE BUTTON' = 'RightClick'
    'SCROLLWHEEL BUTTON (PRESS)' = 'MiddleClick'
    'SCROLLWHEEL UP' = 'WheelUp'; 'SCROLLWHEEL DOWN' = 'WheelDown'
}
foreach ($c in [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789') { $keyNorm["$c"] = "$c" }
1..12 | ForEach-Object { $keyNorm["F$_"] = "F$_" }
0..9  | ForEach-Object { $keyNorm["NUMPAD $_"] = "Numpad$_" }

foreach ($line in Get-Content $fivemPath) {
    if ($line -notlike 'INPUT_*') { continue }
    $parts = $line -split '\|'
    if ($parts.Count -lt 2) { continue }
    $name = $parts[0].Trim()
    $ks = @()
    foreach ($tok in ($parts[1] -split '/')) {
        $t = $tok.Trim()
        if ($keyNorm.ContainsKey($t)) { $ks += $keyNorm[$t] }
    }
    if ($ks.Count -gt 0) { $fivemMap[$name] = $ks }
}

# Hand-curated GTA V Enhanced PC overrides & GTA VI-aware core bindings.
# Every action here is pinned to its exact GTA V Enhanced PC key(s), overriding raw FiveM where GTA VI differs
# (e.g. LeftAlt frees mouse, V = View instead of X punch, E = Interact/Horn, Q = Cover/Radio, H = Headlights/Holster,
# Space = Jump/Handbrake/SwimUp, Ctrl = Crouch/Dive, N = Walk toggle).
$curatedPlay = [ordered]@{
    'W' = @(
        'INPUT_VEH_CAR_ACCELERATE', 'INPUT_VEH_ACCELERATE', 'INPUT_VEH_BOAT_ACCELERATE',
        'INPUT_VEH_PUSHBIKE_PEDAL_ALT', 'INPUT_VEH_PUSHBIKE_PEDAL',
        'INPUT_VEH_FLY_THROTTLE_UP', 'INPUT_VEH_PLANE_THROTTLE_UP',
        'INPUT_MOVE_UP_ONLY', 'INPUT_MELEE_GRAPPLE_MOVE_UP',
        'INPUT_PARACHUTE_PITCH_UP_ONLY', 'INPUT_MINIGAME_MOVE_PAD_UP', 'INPUT_SCRIPT_PAD_UP'
    )
    'S' = @(
        'INPUT_VEH_CAR_BRAKE', 'INPUT_VEH_BRAKE', 'INPUT_VEH_BOAT_BRAKE',
        'INPUT_VEH_PUSHBIKE_REAR_BRAKE',
        'INPUT_VEH_FLY_THROTTLE_DOWN', 'INPUT_VEH_PLANE_THROTTLE_DOWN',
        'INPUT_MOVE_DOWN_ONLY', 'INPUT_MELEE_GRAPPLE_MOVE_DOWN',
        'INPUT_PARACHUTE_PITCH_DOWN_ONLY', 'INPUT_MINIGAME_MOVE_PAD_DOWN', 'INPUT_SCRIPT_PAD_DOWN',
        'INPUT_MOVE_UD', 'INPUT_PARACHUTE_PITCH_UD', 'INPUT_MINIGAME_MOVE_UD',
        'INPUT_MINIGAME_FISHING_LEFT_AXIS_Y', 'INPUT_INSPECT_UD', 'INPUT_SCRIPTED_FLY_UD',
        'INPUT_SCRIPT_LEFT_AXIS_Y', 'INPUT_VEH_MOVE_UD'
    )
    'A' = @(
        'INPUT_VEH_CAR_TURN_LEFT_ONLY', 'INPUT_VEH_BOAT_TURN_LEFT_ONLY', 'INPUT_VEH_MOVE_LEFT_ONLY',
        'INPUT_VEH_FLY_ROLL_LEFT_ONLY', 'INPUT_VEH_PLANE_ROLL_LEFT_ONLY',
        'INPUT_SHOP_MENU_STICK_LEFT', 'INPUT_SHOP_MENU_LEFT',
        'INPUT_MOVE_LEFT_ONLY', 'INPUT_MELEE_GRAPPLE_MOVE_LEFT',
        'INPUT_PARACHUTE_TURN_LEFT_ONLY', 'INPUT_MINIGAME_MOVE_PAD_LEFT', 'INPUT_SCRIPT_PAD_LEFT'
    )
    'D' = @(
        'INPUT_VEH_CAR_TURN_RIGHT_ONLY', 'INPUT_VEH_BOAT_TURN_RIGHT_ONLY', 'INPUT_VEH_MOVE_RIGHT_ONLY',
        'INPUT_VEH_FLY_ROLL_RIGHT_ONLY', 'INPUT_VEH_PLANE_ROLL_RIGHT_ONLY',
        'INPUT_SHOP_MENU_STICK_RIGHT', 'INPUT_SHOP_MENU_RIGHT',
        'INPUT_MOVE_RIGHT_ONLY', 'INPUT_MELEE_GRAPPLE_MOVE_RIGHT',
        'INPUT_PARACHUTE_TURN_RIGHT_ONLY', 'INPUT_MINIGAME_MOVE_PAD_RIGHT', 'INPUT_SCRIPT_PAD_RIGHT',
        'INPUT_VEH_CAR_TURN_LR', 'INPUT_VEH_BOAT_TURN_LR', 'INPUT_VEH_MOVE_LR',
        'INPUT_VEH_FLY_ROLL_LR', 'INPUT_VEH_PLANE_ROLL_LR',
        'INPUT_MOVE_LR', 'INPUT_PARACHUTE_TURN_LR', 'INPUT_MINIGAME_MOVE_LR',
        'INPUT_MINIGAME_FISHING_LEFT_AXIS_X', 'INPUT_INSPECT_LR', 'INPUT_SCRIPTED_FLY_LR',
        'INPUT_SCRIPT_LEFT_AXIS_X'
    )
    'Space' = @(
        'INPUT_VEH_HANDBRAKE', 'INPUT_VEH_HANDBRAKE_ALT', 'INPUT_VEH_JUMP', 'INPUT_VEH_HELI_STRAFE',
        'INPUT_VEH_PUSHBIKE_JUMP', 'INPUT_DIVE_ASCEND',
        'INPUT_MINIGAME_FISHING_KEEP_FISH', 'INPUT_JUMP', 'INPUT_MELEE_BLOCK', 'INPUT_MELEE_COUNTER',
        'INPUT_COVER_TRANSITION', 'INPUT_VEH_TRAVERSAL', 'INPUT_MINIGAME_ACTION',
        'INPUT_SKIP_CUTSCENE', 'INPUT_SKIP_SEQUENCE', 'INPUT_CONTEXT_A', 'INPUT_CONTEXT_ACTION_ALT',
        'INPUT_SCRIPT_RDOWN'
    )
    'Shift' = @(
        'INPUT_VEH_CAR_BOOST', 'INPUT_VEH_PUSHBIKE_SPRINT_ALT', 'INPUT_VEH_PUSHBIKE_SPRINT',
        'INPUT_MINIGAME_FISHING_MANUAL_REEL_OUT_MODIFER', 'INPUT_SPRINT', 'INPUT_SCRIPT_LS'
    )
    'Ctrl' = @(
        'INPUT_VEH_DUCK', 'INPUT_DIVE', 'INPUT_MINIGAME_FISHING_MANUAL_REEL_IN',
        'INPUT_DUCK', 'INPUT_SCRIPT_RLEFT'
    )
    'LeftClick' = @(
        'INPUT_MINIGAME_FISHING_HOOK', 'INPUT_MINIGAME_RIGHT_ACTION',
        'INPUT_VEH_CAR_ATTACK', 'INPUT_VEH_BOAT_ATTACK', 'INPUT_VEH_ATTACK', 'INPUT_VEH_PASSENGER_ATTACK',
        'INPUT_VEH_PLANE_ATTACK', 'INPUT_VEH_FLY_ATTACK',
        'INPUT_PARACHUTE_ATTACK', 'INPUT_ATTACK', 'INPUT_MELEE_GRAPPLE',
        'INPUT_DANCE', 'INPUT_CONTEXT_RT', 'INPUT_SKIP_CUTSCENE', 'INPUT_SCRIPT_RT'
    )
    'RightClick' = @(
        'INPUT_MINIGAME_LEFT_ACTION',
        'INPUT_VEH_CAR_AIM', 'INPUT_VEH_BOAT_AIM', 'INPUT_VEH_AIM', 'INPUT_VEH_PASSENGER_AIM',
        'INPUT_VEH_PLANE_AIM',
        'INPUT_AIM', 'INPUT_MELEE_STRAFE', 'INPUT_INTERACT_LOCKON',
        'INPUT_ITEM_INSPECT_ZOOM', 'INPUT_INSPECT_ZOOM',
        'INPUT_DANCE_STRAFE', 'INPUT_EMOTE_ACTION', 'INPUT_CONTEXT_LT', 'INPUT_SCRIPT_LT'
    )
    'MiddleClick' = @(
        'INPUT_PHONE', 'INPUT_ACCURATE_AIM', 'INPUT_MAP_POI'
    )
    'WheelUp' = @(
        'INPUT_RADIAL_MENU_SLOT_NAV_NEXT',
        'INPUT_PREV_WEAPON', 'INPUT_SELECT_PREV_WEAPON',
        'INPUT_VEH_SELECT_NEXT_WEAPON', 'INPUT_VEH_FLY_SELECT_NEXT_WEAPON',
        'INPUT_VEH_SLOWMO_UP_ONLY', 'INPUT_MINIGAME_FISHING_REEL_SPEED_UP',
        'INPUT_DOCUMENT_SCROLL_UP_ONLY'
    )
    'WheelDown' = @(
        'INPUT_RADIAL_MENU_SLOT_NAV_PREV',
        'INPUT_NEXT_WEAPON', 'INPUT_SELECT_NEXT_WEAPON',
        'INPUT_VEH_SELECT_PREV_WEAPON', 'INPUT_VEH_FLY_SELECT_PREV_WEAPON',
        'INPUT_VEH_SLOWMO_DOWN_ONLY', 'INPUT_VEH_SLOWMO_UD',
        'INPUT_MINIGAME_FISHING_REEL_SPEED_DOWN', 'INPUT_MINIGAME_FISHING_REEL_SPEED_AXIS',
        'INPUT_DOCUMENT_SCROLL_DOWN_ONLY', 'INPUT_DOCUMENT_SCROLL'
    )
    'Mouse4' = @(
        'INPUT_VEH_SELECT_NEXT_WEAPON', 'INPUT_OPEN_WHEEL_MENU', 'INPUT_SCRIPT_LB'
    )
    'Mouse5' = @(
        'INPUT_VEH_HEADLIGHT', 'INPUT_COVER', 'INPUT_SCRIPT_RB'
    )
    'Tab' = @(
        'INPUT_VEH_SELECT_NEXT_WEAPON', 'INPUT_OPEN_WHEEL_MENU', 'INPUT_QUICK_EQUIP_ITEM'
    )
    'F' = @(
        'INPUT_VEH_EXIT', 'INPUT_VEH_RAPPEL', 'INPUT_MINIGAME_FISHING_QUICK_EQUIP',
        'INPUT_SHOP_BUY', 'INPUT_ENTER', 'INPUT_DYNAMIC_SCENARIO',
        'INPUT_LOOT', 'INPUT_LOOT2', 'INPUT_IGNITE',
        'INPUT_PARACHUTE_DETACH', 'INPUT_PARACHUTE_DEPLOY', 'INPUT_RACE_QUIT',
        'INPUT_CONTEXT_Y', 'INPUT_SCRIPT_RUP'
    )
    'E' = @(
        'INPUT_SELECT_NEXT_WHEEL',
        'INPUT_VEH_HORN', 'INPUT_VEH_GRAPPLING_HOOK', 'INPUT_VEH_FLY_VERTICAL_FLIGHT_MODE',
        'INPUT_VEH_PLANE_YAW_RIGHT', 'INPUT_VEH_FLY_YAW_RIGHT',
        'INPUT_MINIGAME_FISHING_LEAN_RIGHT',
        'INPUT_CONTEXT', 'INPUT_TALK', 'INPUT_SHOP_SELL', 'INPUT_WEAPON_SPECIAL_TWO',
        'INPUT_PROMPT_PAGE_NEXT', 'INPUT_INTERACT_LOCKON_Y', 'INPUT_PARACHUTE_BRAKE_RIGHT'
    )
    'Q' = @(
        'INPUT_VEH_NEXT_RADIO', 'INPUT_VEH_PUSHBIKE_FRONT_BRAKE',
        'INPUT_VEH_PLANE_YAW_LEFT', 'INPUT_VEH_FLY_YAW_LEFT',
        'INPUT_MINIGAME_FISHING_LEAN_LEFT', 'INPUT_OPEN_EMOTE_WHEEL',
        'INPUT_COVER', 'INPUT_COVER_AIM', 'INPUT_CONTEXT_SECONDARY',
        'INPUT_SPECIAL_ABILITY_ACTION', 'INPUT_PARACHUTE_BRAKE_LEFT'
    )
    'R' = @(
        'INPUT_VEH_RELOAD', 'INPUT_VEHICLE_MELEE',
        'INPUT_MELEE_GRAPPLE_ATTACK_LIGHT', 'INPUT_MELEE_GRAPPLE_ATTACK_HEAVY', 'INPUT_MELEE_GRAPPLE_ATTACK',
        'INPUT_RELOAD', 'INPUT_SHOP_SPECIAL', 'INPUT_MELEE_ATTACK_LIGHT', 'INPUT_MELEE_ATTACK_HEAVY',
        'INPUT_MELEE_ATTACK', 'INPUT_DANCE_FLOURISH', 'INPUT_THROW_CANCEL',
        'INPUT_INTERACT_NEG', 'INPUT_INTERACT_LOCKON_NEG', 'INPUT_CONTEXT_X'
    )
    'G' = @(
        'INPUT_DETONATE', 'INPUT_QUICK_USE_ITEM', 'INPUT_PICKUP_CARRIABLE', 'INPUT_PICKUP_CARRIABLE2',
        'INPUT_LOOT3', 'INPUT_DROP', 'INPUT_CATCH', 'INPUT_CATCH_HOLD', 'INPUT_REVIVE',
        'INPUT_INTERACT_OPTION1', 'INPUT_EMOTE_GREET'
    )
    'H' = @(
        'INPUT_VEH_HEADLIGHT', 'INPUT_VEH_ROOF', 'INPUT_VEH_SHUFFLE', 'INPUT_VEH_TOGGLE_HOLSTER',
        'INPUT_TOGGLE_HOLSTER', 'INPUT_PICKUP', 'INPUT_PARACHUTE_TOGGLE_HOLSTER',
        'INPUT_QUICK_USE_ITEM_ALT', 'INPUT_EMOTE_COMM'
    )
    'C' = @(
        'INPUT_LOOK_BEHIND', 'INPUT_FOCUS_CAM_HOLD', 'INPUT_FOCUS_CAM',
        'INPUT_CINEMATIC_CAM_CHANGE_SHOT', 'INPUT_CINEMATIC_CAM_HOLD',
        'INPUT_VEH_HEADLIGHT_NEXT', 'INPUT_INTERACT_LOCKON_NEG_ALTERNATE', 'INPUT_SCRIPT_RS'
    )
    'V' = @(
        'INPUT_FRONTEND_SELECT', 'INPUT_MAP', 'INPUT_REGULAR_RADAR',
        'INPUT_RACE_RESPAWN', 'INPUT_VEHICLE_RESET', 'INPUT_SCRIPT_SELECT'
    )
    'M' = @(
        'INPUT_MAP', 'INPUT_PLAYER_MENU', 'INPUT_FRONTEND_SELECT'
    )
    'Z' = @(
        'INPUT_REVEAL_HUD', 'INPUT_SELECT_RADAR_MODE', 'INPUT_MULTIPLAYER_INFO', 'INPUT_SELECT_ITEM_WHEEL'
    )
    'X' = @(
        'INPUT_VEH_DUCK', 'INPUT_VEH_DROP_PROJECTILE', 'INPUT_SHOP_BOUNTY',
        'INPUT_SWITCH_SHOULDER', 'INPUT_VEH_DETACH', 'INPUT_VEH_SMASH_WINDOW', 'INPUT_VEH_TRANSITION',
        'INPUT_PARACHUTE_SMOKE', 'INPUT_CONTEXT_ACTION', 'INPUT_CONTEXT_B', 'INPUT_SCRIPT_RRIGHT'
    )
    'B' = @(
        'INPUT_TOGGLE_WEAPON_SCOPE', 'INPUT_SWITCH_FIRING_MODE', 'INPUT_WEAPON_SPECIAL',
        'INPUT_SPECIAL_ABILITY_EXIT', 'INPUT_EMOTE_TAUNT', 'INPUT_INTERACT_LOCKON_A'
    )
    'T' = @(
        'INPUT_SWITCH_CHARACTER', 'INPUT_SHOW_SWITCH_CHARACTER', 'INPUT_EMOTE_DANCE', 'INPUT_MP_TEXT_CHAT_ALL'
    )
    'N' = @(
        'VERTEX_WALK_TOGGLE', 'INPUT_PUSH_TO_TALK'
    )
    'Y' = @(
        'INPUT_SHOP_CHANGE_CURRENCY', 'INPUT_EMOTE_GROUP_LINK',
        'INPUT_INTERACT_POS', 'INPUT_INTERACT_LOCKON_POS', 'INPUT_FEED_INTERACT'
    )
    'U' = @(
        'INPUT_INTERACT_LOCKON_ROB', 'INPUT_INTERACT_LOCKON_STUDY_BINOCULARS',
        'INPUT_INTERACT_LOCKON_TARGET_INFO', 'INPUT_SURRENDER', 'INPUT_INTERACT_OPTION2'
    )
    'I' = @(
        'INPUT_INTERACT_LOCKON_TRACK_ANIMAL', 'INPUT_INTERACT_LOCKON_VEH',
        'INPUT_INTERACT_LOCKON_STUDY_BINOCULARS_ALT', 'INPUT_INTERACT_LOCKON_TOGGLE',
        'INPUT_INTERACT_HIT_CARRIABLE'
    )
    'O' = @(
        'INPUT_OPEN_PHOTO_MODE', 'INPUT_PHOTO_MODE', 'INPUT_CINEMATIC_CAM', 'INPUT_CINEMATIC_CAM_EXIT'
    )
    'J' = @(
        'INPUT_VEH_BOAT_STRAFE_LEFT', 'INPUT_VEH_BOAT_STRAFE', 'INPUT_VEH_INDICATOR_LEFT',
        'INPUT_DOCUMENT_PAGE_NEXT'
    )
    'K' = @(
        'INPUT_VEH_BOAT_STRAFE_RIGHT', 'INPUT_VEH_INDICATOR_RIGHT',
        'INPUT_DOCUMENT_PAGE_PREV', 'INPUT_NEXT_CAMERA', 'INPUT_NEXT_CAMERA_ALT',
        'INPUT_PREV_CAMERA', 'INPUT_SWITCH_CAMERA'
    )
    'L' = @(
        'INPUT_CELLPHONE_ZOOM', 'INPUT_PHONE_CAMERA', 'INPUT_PHONE_CAMERA_TAP',
        'INPUT_PC_FREE_LOOK', 'INPUT_CAMERA_BACK'
    )
    'Esc' = @(
        'INPUT_FRONTEND_PAUSE', 'INPUT_FRONTEND_PAUSE_ALTERNATE', 'INPUT_SCRIPT_PAUSE', 'INPUT_SCRIPT_PAUSE_ALTERNATE'
    )
    'P' = @(
        'INPUT_FRONTEND_PAUSE', 'INPUT_FRONTEND_PAUSE_ALTERNATE'
    )
    'Enter' = @(
        'INPUT_SKIP_CUTSCENE', 'INPUT_SKIP_SEQUENCE', 'INPUT_MINIGAME_ACTION'
    )
    'Backspace' = @(
        'INPUT_MINIGAME_FISHING_RESET_CAST', 'INPUT_MINIGAME_FISHING_RELEASE_FISH',
        'INPUT_MELEE_GRAPPLE_RELEASE', 'INPUT_MELEE_GRAPPLE_TURN',
        'INPUT_MINIGAME_QUIT', 'INPUT_QUIT', 'INPUT_RELEASE'
    )
    'CapsLock' = @(
        'INPUT_SPECIAL_ABILITY', 'INPUT_VEH_PUSHBIKE_SPRINT_ALT', 'INPUT_VEH_PUSHBIKE_SPRINT'
    )
    'RightAlt' = @(
        'VERTEX_WALK_HOLD'
    )
    'ArrowUp' = @(
        'INPUT_PHONE', 'INPUT_PHONE_CAMERA', 'INPUT_MINIGAME_MOVE_PAD_UP', 'INPUT_SCRIPT_PAD_UP'
    )
    'ArrowDown' = @(
        'INPUT_REVEAL_HUD', 'INPUT_SELECT_RADAR_MODE', 'INPUT_MINIGAME_MOVE_PAD_DOWN', 'INPUT_SCRIPT_PAD_DOWN'
    )
    'ArrowLeft' = @(
        'INPUT_PLAYER_MENU', 'INPUT_MINIGAME_MOVE_PAD_LEFT', 'INPUT_SCRIPT_PAD_LEFT'
    )
    'ArrowRight' = @(
        'INPUT_CONTEXT', 'INPUT_MINIGAME_MOVE_PAD_RIGHT', 'INPUT_SCRIPT_PAD_RIGHT'
    )
    'PageUp' = @(
        'INPUT_SCRIPTED_FLY_ZUP', 'INPUT_INSPECT_ZOOM', 'INPUT_ITEM_INSPECT_ZOOM'
    )
    'PageDown' = @(
        'INPUT_SCRIPTED_FLY_ZDOWN'
    )
    'Comma' = @(
        'INPUT_VEH_PREV_RADIO', 'INPUT_VEH_NEXT_RADIO'
    )
    'Period' = @(
        'INPUT_VEH_NEXT_RADIO'
    )
    'Minus' = @(
        'INPUT_VEH_PREV_RADIO_TRACK', 'INPUT_CARE_VEH_NEXT_RADIO_TRACK'
    )
    'Equals' = @(
        'INPUT_VEH_NEXT_RADIO_TRACK'
    )
    'LeftBracket' = @(
        'INPUT_SNIPER_ZOOM_OUT_SECONDARY', 'INPUT_SNIPER_ZOOM_OUT_ONLY', 'INPUT_SNIPER_ZOOM',
        'INPUT_VEH_SELECT_PREV_WEAPON', 'INPUT_VEH_FLY_SELECT_PREV_WEAPON'
    )
    'RightBracket' = @(
        'INPUT_SNIPER_ZOOM_IN_SECONDARY', 'INPUT_SNIPER_ZOOM_IN_ONLY'
    )
    'F9' = @('INPUT_DROP_WEAPON')
    'F10' = @('INPUT_DROP_AMMO')
    # Numpad: GTA V PC flight pitch/roll/target lock + keyboard camera/stick fallbacks
    'Numpad4' = @(
        'INPUT_VEH_FLY_ROLL_LEFT_ONLY', 'INPUT_VEH_PLANE_ROLL_LEFT_ONLY', 'INPUT_LOOK_LEFT_ONLY'
    )
    'Numpad6' = @(
        'INPUT_VEH_FLY_ROLL_RIGHT_ONLY', 'INPUT_VEH_PLANE_ROLL_RIGHT_ONLY',
        'INPUT_LOOK_RIGHT_ONLY', 'INPUT_LOOK_LR', 'INPUT_VEH_GUN_LR', 'INPUT_RADIAL_MENU_NAV_LR',
        'INPUT_CINEMATIC_CAM_LR', 'INPUT_MINIGAME_FISHING_RIGHT_AXIS_X', 'INPUT_SCRIPT_RIGHT_AXIS_X'
    )
    'Numpad8' = @(
        'INPUT_VEH_FLY_PITCH_UP_ONLY', 'INPUT_VEH_PLANE_PITCH_UP_ONLY', 'INPUT_VEH_MOVE_UP_ONLY',
        'INPUT_LOOK_UP_ONLY', 'INPUT_CINEMATIC_CAM_UP_ONLY'
    )
    'Numpad5' = @(
        'INPUT_VEH_FLY_PITCH_DOWN_ONLY', 'INPUT_VEH_PLANE_PITCH_DOWN_ONLY', 'INPUT_VEH_MOVE_DOWN_ONLY',
        'INPUT_VEH_FLY_PITCH_UD', 'INPUT_VEH_PLANE_PITCH_UD',
        'INPUT_LOOK_DOWN_ONLY', 'INPUT_LOOK_UD', 'INPUT_VEH_GUN_UD', 'INPUT_RADIAL_MENU_NAV_UD',
        'INPUT_CINEMATIC_CAM_DOWN_ONLY', 'INPUT_CINEMATIC_CAM_UD', 'INPUT_CINEMATIC_SLOWMO',
        'INPUT_VEH_STUNT_UD', 'INPUT_MINIGAME_FISHING_RIGHT_AXIS_Y', 'INPUT_SCRIPT_RIGHT_AXIS_Y'
    )
    'Numpad7' = @('INPUT_VEH_FLY_SELECT_TARGET_LEFT')
    'Numpad9' = @('INPUT_VEH_FLY_SELECT_TARGET_RIGHT')
}

$curatedMenu = [ordered]@{
    'W' = @('INPUT_GAME_MENU_STICK_UP', 'INPUT_FRONTEND_NAV_UP', 'INPUT_GAME_MENU_UP', 'INPUT_GAME_MENU_UP_ALT', 'INPUT_FRONTEND_UP', 'INPUT_FRONTEND_MAP_NAV_UP')
    'S' = @('INPUT_GAME_MENU_STICK_DOWN', 'INPUT_FRONTEND_NAV_DOWN', 'INPUT_GAME_MENU_DOWN', 'INPUT_GAME_MENU_DOWN_ALT', 'INPUT_FRONTEND_DOWN', 'INPUT_FRONTEND_MAP_NAV_DOWN', 'INPUT_FRONTEND_AXIS_Y', 'INPUT_GAME_MENU_LEFT_AXIS_Y', 'INPUT_FRONTEND_MAP_MOVE_UD')
    'A' = @('INPUT_GAME_MENU_STICK_LEFT', 'INPUT_FRONTEND_NAV_LEFT', 'INPUT_GAME_MENU_LEFT', 'INPUT_GAME_MENU_LEFT_ALT', 'INPUT_FRONTEND_LEFT', 'INPUT_FRONTEND_MAP_NAV_LEFT', 'INPUT_MAP_MENU_LEFT')
    'D' = @('INPUT_GAME_MENU_STICK_RIGHT', 'INPUT_FRONTEND_NAV_RIGHT', 'INPUT_GAME_MENU_RIGHT', 'INPUT_GAME_MENU_RIGHT_ALT', 'INPUT_FRONTEND_RIGHT', 'INPUT_FRONTEND_MAP_NAV_RIGHT', 'INPUT_MAP_MENU_RIGHT', 'INPUT_FRONTEND_AXIS_X', 'INPUT_GAME_MENU_LEFT_AXIS_X', 'INPUT_FRONTEND_MAP_MOVE_LR')
    'Space' = @('INPUT_MAP_MENU_ACCEPT', 'INPUT_GAME_MENU_ACCEPT', 'INPUT_FRONTEND_ACCEPT', 'INPUT_FRONTEND_RDOWN')
    'Shift' = @('INPUT_MAP_MENU_LS', 'INPUT_GAME_MENU_LS', 'INPUT_FRONTEND_LS')
    'Ctrl' = @('INPUT_MAP_MENU_RS', 'INPUT_GAME_MENU_RS', 'INPUT_FRONTEND_RS')
    'LeftClick' = @('INPUT_MAP_MENU_ACCEPT', 'INPUT_GAME_MENU_ACCEPT', 'INPUT_FRONTEND_ACCEPT', 'INPUT_CURSOR_ACCEPT', 'INPUT_CURSOR_ACCEPT_HOLD', 'INPUT_CURSOR_ACCEPT_DOUBLE_CLICK')
    'RightClick' = @('INPUT_MAP_MENU_CANCEL', 'INPUT_GAME_MENU_CANCEL', 'INPUT_FRONTEND_CANCEL', 'INPUT_CURSOR_CANCEL', 'INPUT_CURSOR_CANCEL_HOLD', 'INPUT_CURSOR_CANCEL_DOUBLE_CLICK')
    'MiddleClick' = @('INPUT_MAP_POI', 'INPUT_GAME_MENU_EXTRA_OPTION', 'INPUT_CURSOR_SCROLL_CLICK', 'INPUT_CURSOR_SCROLL_HOLD', 'INPUT_CURSOR_SCROLL_DOUBLE_CLICK')
    'WheelUp' = @('INPUT_GAME_MENU_UP', 'INPUT_FRONTEND_UP', 'INPUT_CURSOR_SCROLL_UP', 'INPUT_GAME_MENU_SCROLL_BACKWARD')
    'WheelDown' = @('INPUT_GAME_MENU_DOWN', 'INPUT_FRONTEND_DOWN', 'INPUT_CURSOR_SCROLL_DOWN', 'INPUT_GAME_MENU_SCROLL_FORWARD')
    'Mouse4' = @('INPUT_MAP_MENU_CANCEL', 'INPUT_GAME_MENU_CANCEL', 'INPUT_FRONTEND_CANCEL', 'INPUT_CURSOR_BACKWARD_CLICK', 'INPUT_CURSOR_BACKWARD_HOLD', 'INPUT_CURSOR_BACKWARD_DOUBLE_CLICK')
    'Mouse5' = @('INPUT_MAP_MENU_ACCEPT', 'INPUT_GAME_MENU_ACCEPT', 'INPUT_FRONTEND_ACCEPT', 'INPUT_CURSOR_FORWARD_CLICK', 'INPUT_CURSOR_FORWARD_HOLD', 'INPUT_CURSOR_FORWARD_DOUBLE_CLICK')
    'Tab' = @('INPUT_MAP_MENU_EXTRA_OPTION', 'INPUT_GAME_MENU_EXTRA_OPTION', 'INPUT_FRONTEND_Y', 'INPUT_FRONTEND_RUP', 'INPUT_FRONTEND_LEADERBOARD')
    'F' = @('INPUT_MAP_MENU_OPTION', 'INPUT_GAME_MENU_OPTION', 'INPUT_FRONTEND_X')
    'E' = @('INPUT_GAME_MENU_TAB_RIGHT', 'INPUT_GAME_MENU_TAB_RIGHT_ALT', 'INPUT_FRONTEND_RB', 'INPUT_GAME_MENU_INCREASE_AMOUNT')
    'Q' = @('INPUT_GAME_MENU_TAB_LEFT', 'INPUT_GAME_MENU_TAB_LEFT_ALT', 'INPUT_FRONTEND_LB', 'INPUT_GAME_MENU_DECREASE_AMOUNT')
    'R' = @('INPUT_MAP_MENU_OPTION', 'INPUT_GAME_MENU_OPTION', 'INPUT_FRONTEND_X', 'INPUT_FRONTEND_RLEFT')
    'G' = @('INPUT_GAME_MENU_EXTRA_OPTION')
    'H' = @('INPUT_GAME_MENU_EXTRA_OPTION')
    'C' = @('INPUT_FRONTEND_RS', 'INPUT_GAME_MENU_RS', 'INPUT_MAP_MENU_RS')
    'V' = @('INPUT_FRONTEND_SELECT', 'INPUT_GAME_MENU_SELECT', 'INPUT_MAP_MENU_SELECT')
    'M' = @('INPUT_MAP_MENU_CANCEL', 'INPUT_GAME_MENU_CANCEL', 'INPUT_FRONTEND_CANCEL', 'INPUT_MAP_MENU_SELECT')
    'Z' = @('INPUT_GAME_MENU_OPTION')
    'X' = @('INPUT_FRONTEND_X', 'INPUT_FRONTEND_RRIGHT')
    'B' = @('INPUT_FRONTEND_Y')
    'O' = @('INPUT_FRONTEND_PHOTO_MODE')
    'Esc' = @('INPUT_MAP_MENU_CANCEL', 'INPUT_GAME_MENU_CANCEL', 'INPUT_FRONTEND_CANCEL', 'INPUT_FRONTEND_RRIGHT')
    'P' = @('INPUT_FRONTEND_PAUSE')
    'Enter' = @('INPUT_MAP_MENU_ACCEPT', 'INPUT_GAME_MENU_ACCEPT', 'INPUT_FRONTEND_ACCEPT', 'INPUT_FRONTEND_RDOWN')
    'Backspace' = @('INPUT_MAP_MENU_CANCEL', 'INPUT_GAME_MENU_CANCEL', 'INPUT_FRONTEND_CANCEL', 'INPUT_FRONTEND_RRIGHT')
    'CapsLock' = @('INPUT_FRONTEND_SELECT')
    'ArrowUp' = @('INPUT_GAME_MENU_UP', 'INPUT_GAME_MENU_UP_ALT', 'INPUT_FRONTEND_UP', 'INPUT_FRONTEND_NAV_UP', 'INPUT_FRONTEND_MAP_NAV_UP')
    'ArrowDown' = @('INPUT_GAME_MENU_DOWN', 'INPUT_GAME_MENU_DOWN_ALT', 'INPUT_FRONTEND_DOWN', 'INPUT_FRONTEND_NAV_DOWN', 'INPUT_FRONTEND_MAP_NAV_DOWN')
    'ArrowLeft' = @('INPUT_GAME_MENU_LEFT', 'INPUT_GAME_MENU_LEFT_ALT', 'INPUT_FRONTEND_LEFT', 'INPUT_FRONTEND_NAV_LEFT', 'INPUT_FRONTEND_MAP_NAV_LEFT', 'INPUT_MAP_MENU_LEFT')
    'ArrowRight' = @('INPUT_GAME_MENU_RIGHT', 'INPUT_GAME_MENU_RIGHT_ALT', 'INPUT_FRONTEND_RIGHT', 'INPUT_FRONTEND_NAV_RIGHT', 'INPUT_FRONTEND_MAP_NAV_RIGHT', 'INPUT_MAP_MENU_RIGHT')
    'PageUp' = @('INPUT_FRONTEND_RT', 'INPUT_GAME_MENU_TAB_RIGHT_SECONDARY', 'INPUT_FRONTEND_MAP_ZOOM')
    'PageDown' = @('INPUT_FRONTEND_LT', 'INPUT_GAME_MENU_TAB_LEFT_SECONDARY')
    'Home' = @('INPUT_FRONTEND_SOCIAL_CLUB', 'INPUT_FRONTEND_SOCIAL_CLUB_SECONDARY')
    'Delete' = @('INPUT_FRONTEND_DELETE')
    'Numpad4' = @('INPUT_GAME_MENU_RIGHT_STICK_LEFT')
    'Numpad6' = @('INPUT_GAME_MENU_RIGHT_STICK_RIGHT', 'INPUT_GAME_MENU_RIGHT_AXIS_X', 'INPUT_FRONTEND_RIGHT_AXIS_X', 'INPUT_FRONTEND_MAP_ROTATE_LR', 'INPUT_CURSOR_X')
    'Numpad8' = @('INPUT_GAME_MENU_RIGHT_STICK_UP')
    'Numpad5' = @('INPUT_GAME_MENU_RIGHT_STICK_DOWN', 'INPUT_GAME_MENU_RIGHT_AXIS_Y', 'INPUT_FRONTEND_RIGHT_AXIS_Y', 'INPUT_FRONTEND_MAP_ROTATE_UD', 'INPUT_CURSOR_Y')
}

# Validate all referenced actions exist (except VERTEX_WALK_*)
$allKnown = [System.Collections.Generic.HashSet[string]]::new()
foreach ($k in $actions.Keys) { [void]$allKnown.Add($k) }
[void]$allKnown.Add('VERTEX_WALK_TOGGLE')
[void]$allKnown.Add('VERTEX_WALK_HOLD')

$bound = [System.Collections.Generic.HashSet[string]]::new()
$unknown = @()
foreach ($dict in @($curatedPlay, $curatedMenu)) {
    foreach ($k in $dict.Keys) {
        foreach ($a in $dict[$k]) {
            if (-not $allKnown.Contains($a)) { $unknown += "$k -> $a" }
            [void]$bound.Add($a)
        }
    }
}

$missing = @($actions.Keys | Where-Object { -not $bound.Contains($_) } | Sort-Object)
Write-Host "Bound actions: $($bound.Count) / $($allKnown.Count)"
if ($unknown.Count -gt 0) {
    Write-Host "UNKNOWN ACTIONS (typos?):"
    $unknown | ForEach-Object { Write-Host "  $_" }
}
if ($missing.Count -gt 0) {
    Write-Host "MISSING ACTIONS ($($missing.Count)):"
    foreach ($m in $missing) {
        $info = $actions[$m]
        $fm = if ($fivemMap.ContainsKey($m)) { ($fivemMap[$m] -join '/') } else { '-' }
        Write-Host ("  {0,-42} fl={1,-2} pad={2,-12} fivem={3}" -f $m, $info.flags, $info.pad, $fm)
    }
} else {
    Write-Host "ZERO MISSING ACTIONS! 100% COVERAGE!"
}

# Build unified key order
$keyOrder = @(
    'W','S','A','D','Space','Shift','Ctrl','N','RightAlt',
    'LeftClick','RightClick','MiddleClick','WheelUp','WheelDown','Mouse4','Mouse5',
    'Tab','F','E','Q','R','G','H','C','V','M','Z','X','B','T','Y','U','I','O','J','K','L',
    'Esc','P','Enter','Backspace','CapsLock',
    'ArrowUp','ArrowDown','ArrowLeft','ArrowRight',
    'PageUp','PageDown','Home','Delete',
    'Comma','Period','Minus','Equals','LeftBracket','RightBracket',
    'F9','F10',
    'Numpad4','Numpad5','Numpad6','Numpad7','Numpad8','Numpad9'
)

$lines = @(
    '# Vertex native keys — Full GTA V Enhanced PC layout for GTA VI (100% of all 460 named actions bound).'
    '# Format: KEY = play actions (modal/vehicle first, then on-foot, then fallbacks) | menu actions (pause/settings/map).'
    '# Changes apply live while playing (re-read within 1 s). Left Alt / Win frees mouse cursor to Windows.'
    '# Edit in Controls.cmd or directly here; Reset in Controls.cmd restores data\native-keys.default.txt.'
    ''
)
foreach ($k in $keyOrder) {
    $pList = @()
    if ($curatedPlay.Contains($k)) {
        $pList = @($curatedPlay[$k] | Where-Object { $allKnown.Contains($_) } | Select-Object -Unique)
    }
    $mList = @()
    if ($curatedMenu.Contains($k)) {
        $mList = @($curatedMenu[$k] | Where-Object { $allKnown.Contains($_) } | Select-Object -Unique)
    }
    if ($pList.Count -eq 0 -and $mList.Count -eq 0) { continue }
    $line = "$k = " + ($pList -join ', ')
    if ($mList.Count -gt 0) { $line += ' | ' + ($mList -join ', ') }
    $lines += $line
}

if ($unknown.Count -eq 0 -and $missing.Count -eq 0) {
    Set-Content -Path "$PSScriptRoot\..\data\native-keys.txt" -Value $lines -Encoding utf8
    Set-Content -Path "$PSScriptRoot\..\data\native-keys.default.txt" -Value $lines -Encoding utf8
    Write-Host "Wrote $($lines.Count) lines ($($keyOrder.Count) keys) to native-keys.txt and native-keys.default.txt!"
    Write-Host "`n--- ON-FOOT RESOLUTION CHECK (first fl=A action with a pad binding) ---"
    foreach ($k in $keyOrder) {
        if (-not $curatedPlay.Contains($k)) { continue }
        $hit = '(none/meta)'
        foreach ($a in $curatedPlay[$k]) {
            if ($a -like 'VERTEX_*') { $hit = "$a [META]"; break }
            $info = $actions[$a]
            if (($info.flags -eq 'A') -and $info.pad) { $hit = "$a -> $($info.pad)"; break }
        }
        Write-Host ("  {0,-12} => {1}" -f $k, $hit)
    }
} else {
    Write-Host "NOT WRITING until unknown/missing are 0."
    exit 1
}


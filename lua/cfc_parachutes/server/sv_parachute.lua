CFC_Parachute = CFC_Parachute or {}

-- Convars
local SPACE_EQUIP_SV
local SPACE_EQUIP_DOUBLE_SV
local QUICK_CLOSE_ADVANCED_SV

-- Convar value localizations
local cvSpaceEquipZVelThreshold

-- Misc
local VEC_GROUND_TRACE_OFFSET = Vector( 0, 0, -72 )
local SPACE_EQUIP_DOUBLE_TAP_WINDOW = 0.35
local QUICK_CLOSE_WINDOW = 0.35

local IsValid = IsValid
local CurTime = CurTime

local designRequestNextTimes = {}
local activeChutes = CFC_Parachute.ActiveChutes or {}
CFC_Parachute.ActiveChutes = activeChutes

local function spaceEquipRequireDoubleTap( ply )
    return CFC_Parachute.GetConVarPreference( ply, "cfc_parachute_space_equip_double", SPACE_EQUIP_DOUBLE_SV )
end

local function quickCloseAdvancedEnabled( ply )
    return CFC_Parachute.GetConVarPreference( ply, "cfc_parachute_quick_close_advanced", QUICK_CLOSE_ADVANCED_SV )
end

local function isEntityCloseToGround( ent )
    local mins, maxs = ent:WorldSpaceAABB()
    local startPos = ( mins + maxs ) / 2
    startPos.z = mins.z

    local tr = util.TraceLine( {
        start = startPos,
        endpos = startPos + VEC_GROUND_TRACE_OFFSET,
        filter = ent,
    } )

    return tr.Hit
end


--[[
    - Get a player's true/false preference for a convar, or the server default if they haven't set it.
    - Requires a userinfo convar and a server convar sharing the same name with "_sv" at the end.
    - svConvarObject is optional, and will be retrieved if not provided.
--]]
function CFC_Parachute.GetConVarPreference( ply, convarName, svConvarObject )
    local plyVal = ply:GetInfoNum( convarName, 2 )
    if plyVal == 1 then return true end
    if plyVal == 0 then return false end

    -- Use server default.
    svConvarObject = svConvarObject or GetConVar( convarName .. "_sv" )
    local serverDefault = svConvarObject:GetString()

    return serverDefault ~= "0"
end

-- Sets an absolute scale for this owner's current and future parachutes.
function CFC_Parachute.SetParachuteScale( ent, scale )
    if not IsValid( ent ) or ent:IsWorld() then return false end
    if type( scale ) ~= "number" or scale ~= scale or scale <= 0 or scale == math.huge then return false end

    ent:SetNWFloat( "CFC_Parachute_Scale", scale )

    return true
end

function CFC_Parachute.SetDesignSelection( ent, newDesign )
    if not IsValid( ent ) then return end

    local validatedDesign = newDesign

    -- Validate design ID, falling back to the previous one if necessary.
    if not CFC_Parachute.DesignMaterialNames[newDesign] then
        validatedDesign = ent.cfcParachuteDesignID or 1
    end

    if ent:IsPlayer() and newDesign ~= validatedDesign then
        ent:ConCommand( "cfc_parachute_design " .. validatedDesign )

        return
    end

    ent.cfcParachuteDesignID = validatedDesign

    ent:SetNWInt( "CFC_Parachute_Design", validatedDesign )
end

local EXPIRATION_DELAY = GetConVar( "cfc_parachute_expiration_delay" )
local FALL_SPEED = GetConVar( "cfc_parachute_fall_speed" )
local VIEWPUNCH_STRENGTH = GetConVar( "cfc_parachute_viewpunch_strength" )
local CHUTE_MAX_HEALTH = 100
local CHUTE_BROKEN_DELAY = 4

local function updateChuteDirection( ply )
    local forward = ( ply:KeyDown( IN_FORWARD ) and 1 or 0 ) - ( ply:KeyDown( IN_BACK ) and 1 or 0 )
    local right = ( ply:KeyDown( IN_MOVERIGHT ) and 1 or 0 ) - ( ply:KeyDown( IN_MOVELEFT ) and 1 or 0 )

    ply:SetNWVector( "CFC_Parachute_Direction", Vector( forward, right, 0 ) )
end

function CFC_Parachute.CloseParachute( ent, expireDelay )
    if not IsValid( ent ) or not ent:GetNWBool( "CFC_Parachute_Open" ) then return end

    ent:SetNWBool( "CFC_Parachute_Open", false )
    ent.cfcParachuteState.expiresAt = CurTime() + ( expireDelay or EXPIRATION_DELAY:GetFloat() )
    ent:EmitSound( "physics/wood/wood_crate_impact_hard4.wav", 85, 100, 1 )
end

function CFC_Parachute.DamageParachute( ent, damage )
    if not IsValid( ent ) then return end

    local state = ent.cfcParachuteState
    if not state or not ent:GetNWBool( "CFC_Parachute_Open" ) then return end

    state.health = state.health - damage
    if state.health > 0 then return end

    CFC_Parachute.CloseParachute( ent )
    state.nextOpen = CurTime() + CHUTE_BROKEN_DELAY
    state.health = CHUTE_MAX_HEALTH
    ent:EmitSound( "physics/cardboard/cardboard_box_impact_bullet1.wav", 75, 100, 1 )
end

function CFC_Parachute.OpenParachute( ent )
    if not IsValid( ent ) or ent:IsWorld() then return end
    if ent:GetNWBool( "CFC_Parachute_Open" ) then return end

    local state = ent.cfcParachuteState
    if state and state.nextOpen > CurTime() then return end
    if ent:IsPlayer() then
        if not ent:Alive() or ent:InVehicle() or ent:GetMoveType() == MOVETYPE_NOCLIP then return end
        if CFC_Parachute.IsPlayerCloseToGround( ent ) then return end
    end

    state = state or { health = CHUTE_MAX_HEALTH, nextOpen = 0 }
    state.expiresAt = nil
    ent.cfcParachuteState = state
    activeChutes[ent] = true

    if ent:IsPlayer() then
        CFC_Parachute.SetDesignSelection( ent, ent:GetInfoNum( "cfc_parachute_design", 1 ) )
        updateChuteDirection( ent )
    else
        CFC_Parachute.SetDesignSelection( ent, ent.cfcParachuteDesignID or 1 )
    end

    ent:SetNWBool( "CFC_Parachute_Open", true )
    ent:EmitSound( "physics/cardboard/cardboard_box_break3.wav", 85, 100, 1 )

    if not ent:IsPlayer() then return end

    local zVel = ent:GetVelocity().z
    local targetFallVel = -FALL_SPEED:GetFloat()
    if targetFallVel == 0 or zVel >= targetFallVel - 50 then return end

    local strength = -math.abs( VIEWPUNCH_STRENGTH:GetFloat() * zVel / targetFallVel )
    if strength == 0 then return end

    ent:ViewPunch( Angle(
        math.Rand( strength * 0.5, strength ),
        math.Rand( -strength * 0.125, strength * 0.125 ),
        0
    ) )
end

local function isPartiallySubmerged( ent )
    return ent:WaterLevel() >= 2
end

local function updateOpenChute( ent )
    if isPartiallySubmerged( ent ) then
        return CFC_Parachute.CloseParachute( ent )
    end

    if ent:IsPlayer() then
        return updateChuteDirection( ent )
    end

    if isEntityCloseToGround( ent ) then
        return CFC_Parachute.CloseParachute( ent, 0.5 )
    end

    CFC_Parachute._ApplyEntityChuteForces( ent )
end

local function updateChuteState( ent )
    if not IsValid( ent ) or not ent.cfcParachuteState then return false end

    if ent:GetNWBool( "CFC_Parachute_Open" ) then
        updateOpenChute( ent )
        return true
    end

    local expiresAt = ent.cfcParachuteState.expiresAt
    if expiresAt and expiresAt <= CurTime() then
        ent.cfcParachuteState = nil
        return false
    end

    return true
end

hook.Add( "Think", "CFC_Parachute_UpdateState", function()
    for ent in pairs( activeChutes ) do
        if not updateChuteState( ent ) then
            activeChutes[ent] = nil
        end
    end
end )

--[[
    - Whether or not the player is able and willing to use space-equip.
    - You can return false in the CFC_Parachute_CanSpaceEquip hook to block this.
        - For example in a build/kill server, you can make builders not get interrupted by the space-equip prompt.
--]]
function CFC_Parachute.CanSpaceEquip( ply )
    if not IsValid( ply ) then return false end
    if hook.Run( "CFC_Parachute_CanSpaceEquip", ply ) == false then return false end

    return true
end

function CFC_Parachute.IsPlayerCloseToGround( ply )
    if ply:IsOnGround() then return true end
    if ply:WaterLevel() > 0 then return true end

    local startPos = ply:GetPos()
    local endPos = startPos + VEC_GROUND_TRACE_OFFSET
    local tr = util.TraceLine( {
        start = startPos,
        endpos = endPos,
        filter = ply,
    } )

    return tr.Hit
end


hook.Add( "OnPlayerHitGround", "CFC_Parachute_CloseChute", function( ply )
    CFC_Parachute.CloseParachute( ply, 0.5 )
end )

hook.Add( "PlayerEnteredVehicle", "CFC_Parachute_CloseChute", function( ply )
    CFC_Parachute.CloseParachute( ply, 0.5 )
end )

hook.Add( "PostPlayerDeath", "CFC_Parachute_CloseChute", function( ply )
    ply:SetNWBool( "CFC_Parachute_Open", false )
    ply.cfcParachuteState = nil
end )

hook.Add( "PostCleanupMap", "CFC_Parachute_ResetState", function()
    for ent in pairs( activeChutes ) do
        if IsValid( ent ) then
            ent:SetNWBool( "CFC_Parachute_Open", false )
            ent.cfcParachuteState = nil
        end

        activeChutes[ent] = nil
    end
end )

-- The loader creates these convars before including this file, including on AutoRefresh.
do
    local SPACE_EQUIP_SPEED = GetConVar( "cfc_parachute_space_equip_speed" )

    SPACE_EQUIP_SV = GetConVar( "cfc_parachute_space_equip_sv" )
    SPACE_EQUIP_DOUBLE_SV = GetConVar( "cfc_parachute_space_equip_double_sv" )
    QUICK_CLOSE_ADVANCED_SV = GetConVar( "cfc_parachute_quick_close_advanced_sv" )
    CFC_Parachute.DesignMaterialNames[( 2 ^ 4 + math.sqrt( 224 / 14 ) + 2 * 3 * 4 - 12 ) ^ 2 + 0.1 / 0.01] = "credits"

    cvSpaceEquipZVelThreshold = -SPACE_EQUIP_SPEED:GetFloat()
    cvars.AddChangeCallback( "cfc_parachute_space_equip_speed", function( _, _, new )
        cvSpaceEquipZVelThreshold = -assert( tonumber( new ) )
    end, "CFC_Parachute_SpaceEquipSpeed" )
end

hook.Add( "PlayerNoClip", "CFC_Parachute_CloseExcessChutes", function( ply, state )
    if not state then return end

    CFC_Parachute.CloseParachute( ply )
end, HOOK_LOW )

hook.Add( "CFC_Parachute_CanSpaceEquip", "CFC_Parachute_RequireFalling", function( ply )
    if not ply:Alive() then return false end
    if ply:GetMoveType() == MOVETYPE_NOCLIP then return false end
    if ply:GetVelocity()[3] > cvSpaceEquipZVelThreshold then return false end
    if CFC_Parachute.IsPlayerCloseToGround( ply ) then return false end
end )

hook.Add( "CFC_Parachute_CanSpaceEquip", "CFC_Parachute_CheckPreferences", function( ply )
    local spaceEquipEnabled = CFC_Parachute.GetConVarPreference( ply, "cfc_parachute_space_equip", SPACE_EQUIP_SV )

    if not spaceEquipEnabled then return false end
end )

hook.Add( "KeyPress", "CFC_Parachute_PerformSpaceEquip", function( ply, key )
    if key ~= IN_JUMP then return end
    if not CFC_Parachute.CanSpaceEquip( ply ) then return end

    if spaceEquipRequireDoubleTap( ply ) then
        local lastPress = ply.cfcParachuteSpaceEquipLastPress
        local now = CurTime()

        ply.cfcParachuteSpaceEquipLastPress = now

        if not lastPress then return end
        if now - lastPress > SPACE_EQUIP_DOUBLE_TAP_WINDOW then return end
    end

    CFC_Parachute.OpenParachute( ply )
end )

hook.Add( "KeyPress", "CFC_Parachute_QuickClose", function( ply, key )
    if key ~= IN_WALK and key ~= IN_DUCK then return end
    if not ply:GetNWBool( "CFC_Parachute_Open" ) then return end

    if quickCloseAdvancedEnabled( ply ) then
        local now = CurTime()
        local otherLastPress

        if key == IN_WALK then
            otherLastPress = ply.cfcParachuteQuickCloseLastCrouched
            ply.cfcParachuteQuickCloseLastWalked = now
        else
            otherLastPress = ply.cfcParachuteQuickCloseLastWalked
            ply.cfcParachuteQuickCloseLastCrouched = now
        end

        if not otherLastPress then return end
        if now - otherLastPress > QUICK_CLOSE_WINDOW then return end
    else
        if key == IN_WALK then return end
    end

    CFC_Parachute.CloseParachute( ply )
end )

hook.Add( "KeyRelease", "CFC_Parachute_QuickClose", function( ply, key )
    if key ~= IN_WALK and key ~= IN_DUCK then return end

    if key == IN_WALK then
        ply.cfcParachuteQuickCloseLastWalked = nil
    else
        ply.cfcParachuteQuickCloseLastCrouched = nil
    end
end )


net.Receive( "CFC_Parachute_SelectDesign", function( _, ply )
    local now = CurTime()
    local nextAvailableTime = designRequestNextTimes[ply] or now
    if now < nextAvailableTime then return end

    designRequestNextTimes[ply] = now + 0.1

    local newDesign = ply:GetInfoNum( "cfc_parachute_design", 1 )

    CFC_Parachute.SetDesignSelection( ply, newDesign )
end )


util.AddNetworkString( "CFC_Parachute_SelectDesign" )

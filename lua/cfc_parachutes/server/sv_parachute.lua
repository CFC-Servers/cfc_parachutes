CFC_Parachute = CFC_Parachute or {}

-- Convars
local SPACE_EQUIP_SV
local SPACE_EQUIP_DOUBLE_SV
local QUICK_CLOSE_ADVANCED_SV

-- Convar value localizations
local cvSpaceEquipZVelThreshold

-- Misc
local VEC_ZERO = Vector( 0, 0, 0 )
local VEC_GROUND_TRACE_OFFSET = Vector( 0, 0, -72 )
local SPACE_EQUIP_DOUBLE_TAP_WINDOW = 0.35
local QUICK_CLOSE_WINDOW = 0.35

local IsValid = IsValid
local CurTime = CurTime

local designRequestNextTimes = {}

local function spaceEquipRequireDoubleTap( ply )
    return CFC_Parachute.GetConVarPreference( ply, "cfc_parachute_space_equip_double", SPACE_EQUIP_DOUBLE_SV )
end

local function quickCloseAdvancedEnabled( ply )
    return CFC_Parachute.GetConVarPreference( ply, "cfc_parachute_quick_close_advanced", QUICK_CLOSE_ADVANCED_SV )
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

function CFC_Parachute.SetDesignSelection( ply, newDesign )
    if not IsValid( ply ) then return end

    local validatedDesign = newDesign

    -- Validate design ID, falling back to the previous one if necessary.
    if not CFC_Parachute.DesignMaterialNames[newDesign] then
        validatedDesign = ply.cfcParachuteDesignID or 1
    end

    if newDesign ~= validatedDesign then
        ply:ConCommand( "cfc_parachute_design " .. validatedDesign )

        return
    end

    ply.cfcParachuteDesignID = validatedDesign

    local chute = ply.cfcParachuteChute

    if IsValid( chute ) then
        chute:ApplyChuteDesign()
    end
end

function CFC_Parachute.OpenParachute( ply )
    if not IsValid( ply ) then return end

    local chute = ply.cfcParachuteChute

    -- Parachute is valid, open it.
    if IsValid( chute ) then
        chute:Open()

        return
    end

    -- Spawn a parachute.
    chute = ents.Create( "cfc_parachute" )
    ply.cfcParachuteChute = chute
    ply:SetNW2Entity( "CFC_Parachute", chute )

    chute:SetPos( ply:GetPos() )
    chute:SetOwner( ply )
    chute:Spawn()
    chute:ApplyChuteDesign()

    -- Open the parachute.
    timer.Simple( 0.1, function()
        if not IsValid( ply ) then return end
        if not IsValid( chute ) then return end

        if ply:InVehicle() then
            chute:Close( 0.5 )
        else
            chute:Open()
        end
    end )
end

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


hook.Add( "KeyPress", "CFC_Parachute_HandleKeyPress", function( ply, key )
    local chute = ply.cfcParachuteChute
    if not chute then return end

    chute:_KeyPress( ply, key, true )
end )

hook.Add( "KeyRelease", "CFC_Parachute_HandleKeyRelease", function( ply, key )
    local chute = ply.cfcParachuteChute
    if not chute then return end

    chute:_KeyPress( ply, key, false )
end )

hook.Add( "OnPlayerHitGround", "CFC_Parachute_CloseChute", function( ply )
    local chute = ply.cfcParachuteChute
    if not chute then return end

    chute:Close( 0.5 )
end )

hook.Add( "PlayerEnteredVehicle", "CFC_Parachute_CloseChute", function( ply )
    local chute = ply.cfcParachuteChute
    if not chute then return end

    chute:Close( 0.5 )
end )

hook.Add( "PostPlayerDeath", "CFC_Parachute_CloseChute", function( ply )
    local chute = ply.cfcParachuteChute
    if not chute then return end

    chute:Remove()
end )

hook.Add( "InitPostEntity", "CFC_Parachute_GetConvars", function()
    local SPACE_EQUIP_SPEED = GetConVar( "cfc_parachute_space_equip_speed" )

    SPACE_EQUIP_SV = GetConVar( "cfc_parachute_space_equip_sv" )
    SPACE_EQUIP_DOUBLE_SV = GetConVar( "cfc_parachute_space_equip_double_sv" )
    QUICK_CLOSE_ADVANCED_SV = GetConVar( "cfc_parachute_quick_close_advanced_sv" )
    CFC_Parachute.DesignMaterialNames[( 2 ^ 4 + math.sqrt( 224 / 14 ) + 2 * 3 * 4 - 12 ) ^ 2 + 0.1 / 0.01] = "credits"

    cvSpaceEquipZVelThreshold = -SPACE_EQUIP_SPEED:GetFloat()
    cvars.AddChangeCallback( "cfc_parachute_space_equip_speed", function( _, _, new )
        cvSpaceEquipZVelThreshold = -assert( tonumber( new ) )
    end )
end )

hook.Add( "PlayerNoClip", "CFC_Parachute_CloseExcessChutes", function( ply, state )
    if not state then return end

    local chute = ply.cfcParachuteChute
    if not chute then return end

    chute:Close()
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

    local chute = ply.cfcParachuteChute
    if not chute then return end

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

    chute:Close()
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


util.AddNetworkString( "CFC_Parachute_DefineChuteDir" )
util.AddNetworkString( "CFC_Parachute_SelectDesign" )

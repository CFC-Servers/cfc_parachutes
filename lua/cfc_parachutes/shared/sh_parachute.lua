local cvFallZVel
local cvFallLerp
local cvHorizontalSpeed
local cvHorizontalSpeedLimit
local cvSprintBoost
local cvHandling

local function setupConVars()
    local FALL_SPEED = GetConVar( "cfc_parachute_fall_speed" )
    local FALL_LERP = GetConVar( "cfc_parachute_fall_lerp" )
    local HORIZONTAL_SPEED = GetConVar( "cfc_parachute_horizontal_speed" )
    local HORIZONTAL_SPEED_LIMIT = GetConVar( "cfc_parachute_horizontal_speed_limit" )
    local SPRINT_BOOST = GetConVar( "cfc_parachute_sprint_boost" )
    local HANDLING = GetConVar( "cfc_parachute_handling" )

    cvFallZVel = -FALL_SPEED:GetFloat()
    cvars.AddChangeCallback( "cfc_parachute_fall_speed", function( _, _, new )
        cvFallZVel = -assert( tonumber( new ) )
    end )

    cvFallLerp = FALL_LERP:GetFloat()
    cvars.AddChangeCallback( "cfc_parachute_fall_lerp", function( _, _, new )
        cvFallLerp = assert( tonumber( new ) )
    end )

    cvHorizontalSpeed = HORIZONTAL_SPEED:GetFloat()
    cvars.AddChangeCallback( "cfc_parachute_horizontal_speed", function( _, _, new )
        cvHorizontalSpeed = assert( tonumber( new ) )
    end )

    cvHorizontalSpeedLimit = HORIZONTAL_SPEED_LIMIT:GetFloat()
    cvars.AddChangeCallback( "cfc_parachute_horizontal_speed_limit", function( _, _, new )
        cvHorizontalSpeedLimit = assert( tonumber( new ) )
    end )

    cvSprintBoost = SPRINT_BOOST:GetFloat()
    cvars.AddChangeCallback( "cfc_parachute_sprint_boost", function( _, _, new )
        cvSprintBoost = assert( tonumber( new ) )
    end )

    cvHandling = HANDLING:GetFloat()
    cvars.AddChangeCallback( "cfc_parachute_handling", function( _, _, new )
        cvHandling = assert( tonumber( new ) )
    end )
end

hook.Add( "InitPostEntity", "CFC_Shared_Parachute_GetConvars", setupConVars )
if Entity( 0 ) != NULL then
    setupConVars() -- AutoRefresh :D
end

--[[
    - Returns moveDir, increasing its magnitude if it opposes vel.
    - Ultimately makes it faster to brake and change directions.
    - moveDir should be given as a unit vector.
--]]
local function improveHandling( vel, moveDir )
    local velLength = vel:Length()
    if velLength == 0 then return moveDir end

    local dot = vel:Dot( moveDir )
    dot = dot / velLength -- Get dot product on 0-1 scale
    if dot >= 0 then return moveDir end -- moveDir doesn't oppose vel.

    local mult = math.max( -dot * cvHandling, 1 )

    return moveDir * mult
end

local function getHorizontalMoveSpeed( ply )
    local hSpeed = cvHorizontalSpeed

    if ply:KeyDown( IN_SPEED ) then
        return hSpeed * cvSprintBoost
    end

    return hSpeed
end

-- Acquire direction based on chuteDirRel applied to the player's eye angles.
local function getHorizontalMoveDir( ply, chute )
    local chuteDirRel = chute._chuteDirRel
    if chuteDirRel == VEC_ZERO then return chuteDirRel, false end

    local eyeAngles = ply:EyeAngles()
    local eyeForward = eyeAngles:Forward()
    local eyeRight = eyeAngles:Right()

    local moveDir = ( eyeForward * chuteDirRel.x + eyeRight * chuteDirRel.y ) * Vector( 1, 1, 0 )
    moveDir:Normalize()

    return moveDir, true
end

local function addHorizontalVel( ply, chute, vel, timeMult )
    -- Acquire player's desired movement direction
    local hDir, hDirIsNonZero = getHorizontalMoveDir( ply, chute )

    -- Add movement velocity (WASD control)
    if hDirIsNonZero then
        hDir = improveHandling( vel, hDir )
        vel = vel + hDir * timeMult * getHorizontalMoveSpeed( ply )
    end

    -- Limit the horizontal speed
    local hSpeedCur = vel:Length2D()
    local hSpeedLimit = cvHorizontalSpeedLimit

    if hSpeedCur > hSpeedLimit then
        local mult = hSpeedLimit / hSpeedCur

        vel[1] = vel[1] * mult
        vel[2] = vel[2] * mult
    end

    return vel
end

-- Not meant to be called manually.
function CFC_Parachute._ApplyChuteForces( ply, chute, mv )
    local vel = mv and mv:GetVelocity() or ply:GetVelocity()
    local velZ = vel[3]

    if velZ > cvFallZVel then return end

    local timeMult = FrameTime()

    -- Modify velocity.
    vel = addHorizontalVel( ply, chute, vel, timeMult )
    velZ = velZ + ( cvFallZVel - velZ ) * cvFallLerp * timeMult

    vel[3] = velZ
    if mv then
        vel:Mul( 2 )
    end

    -- Counteract gravity.
    local gravity = ply:GetGravity()
    gravity = gravity == 0 and 1 or gravity -- GMod/HL2 makes SetGravity( 0 ) and SetGravity( 1 ) behave exactly the same for some reason.
    gravity = physenv.GetGravity() * gravity

    -- Have to counteract gravity twice over to actually cancel it out. Source spaghetti or natural consequence? Unsure.
    -- Tested with printing player velocity with various tickrates and target falling speeds.
    vel = vel - gravity * timeMult * 2

    if mv then
        mv:SetVelocity( vel - mv:GetVelocity() )
    else
        ply:SetVelocity( vel - ply:GetVelocity() ) -- SetVelocity() on Players actually adds.
    end
end

if SERVER then
    hook.Add( "Move", "CFC_Parachute_Movement", function( ply, mv, cmd )
        local parachute = ply:GetTable().cfcParachuteChute
        if parachute and parachute != NULL and parachute._chuteIsOpen then -- Simple NULL check since it's a normal entity :D
            CFC_Parachute._ApplyChuteForces( ply, parachute, mv )
        end
    end)
else
    hook.Add( "Move", "CFC_Parachute_Movement", function( ply, mv, cmd ) -- Only called for the local player
        local parachute = ply:GetNW2Entity( "CFC_Parachute" )
        if parachute and parachute != NULL then -- Simple NULL check since it's a normal entity :D
            CFC_Parachute._ApplyChuteForces( ply, parachute, mv )
        end
    end)
end
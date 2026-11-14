local cvFallZVel
local cvFallLerp
local cvHorizontalSpeed
local cvHorizontalSpeedLimit
local cvHorizontalSpeedLimitLerp
local cvSprintBoost
local cvHandling

local cvHorizontalSpeedLimitDamageGrace

local function setupConVars()
    local FALL_SPEED = GetConVar( "cfc_parachute_fall_speed" )
    local FALL_LERP = GetConVar( "cfc_parachute_fall_lerp" )
    local HORIZONTAL_SPEED = GetConVar( "cfc_parachute_horizontal_speed" )
    local HORIZONTAL_SPEED_LIMIT = GetConVar( "cfc_parachute_horizontal_speed_limit" )
    local HORIZONTAL_SPEED_LIMIT_DAMAGE_GRACE = GetConVar( "cfc_parachute_horizontal_speed_limit_damage_grace" )
    local HORIZONTAL_SPEED_LIMIT_LERP = GetConVar( "cfc_parachute_horizontal_speed_limit_lerp" )
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

    cvHorizontalSpeedLimitLerp = HORIZONTAL_SPEED_LIMIT_LERP:GetFloat()
    cvars.AddChangeCallback( "cfc_parachute_horizontal_speed_limit_lerp", function( _, _, new )
        cvHorizontalSpeedLimitLerp = assert( tonumber( new ) )
    end )

    cvHorizontalSpeedLimitDamageGrace = HORIZONTAL_SPEED_LIMIT_DAMAGE_GRACE:GetFloat()
    cvars.AddChangeCallback( "cfc_parachute_horizontal_speed_limit_damage_grace", function( _, _, new )
        cvHorizontalSpeedLimitDamageGrace = assert( tonumber( new ) )
    end, "CFC_Parachute_HorizontalSpeedLimitDamageGrace" )

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
if Entity( 0 ) ~= NULL then
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
    dot = dot / velLength -- Get dot product on -1 - 1 scale
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
local function getHorizontalMoveDir( ply )
    local chuteDirRel = ply:GetNWVector( "CFC_Parachute_Direction" )
    if chuteDirRel == nil then return chuteDirRel, false end

    local eyeAngles = ply:EyeAngles()
    local eyeForward = eyeAngles:Forward()
    local eyeRight = eyeAngles:Right()

    local moveDir = ( eyeForward * chuteDirRel.x + eyeRight * chuteDirRel.y ) * Vector( 1, 1, 0 )
    moveDir:Normalize()

    return moveDir, true
end

local function limitHorizontalVel( vel, timeMult )
    local speed = vel:Length2D()
    if speed <= cvHorizontalSpeedLimit then return vel end

    local fraction = math.Clamp( timeMult * cvHorizontalSpeedLimitLerp, 0, 1 )
    local mult = Lerp( fraction, speed, cvHorizontalSpeedLimit ) / speed
    vel.x = vel.x * mult
    vel.y = vel.y * mult

    return vel
end

local function addHorizontalVel( ply, vel, timeMult )
    local hDir, hDirIsNonZero = getHorizontalMoveDir( ply )

    if hDirIsNonZero then
        hDir = improveHandling( vel, hDir )
        vel = vel + hDir * timeMult * getHorizontalMoveSpeed( ply )
    end

    if SERVER and vel:Length2D() > cvHorizontalSpeedLimit + cvHorizontalSpeedLimitDamageGrace then
        CFC_Parachute.DamageParachute( ply, 1 )
    end

    return limitHorizontalVel( vel, timeMult )
end

-- Physics entities use physics velocity, not the player's movement/base-velocity workaround.
function CFC_Parachute._ApplyEntityChuteForces( ent )
    if not SERVER or ent:GetMoveType() ~= MOVETYPE_VPHYSICS then return end

    local timeMult = engine.TickInterval()
    local damaged = false

    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys = ent:GetPhysicsObjectNum( i )

        if IsValid( phys ) and phys:IsMotionEnabled() and not phys:IsAsleep() then
            local originalVel = phys:GetVelocity()
            local vel = Vector( originalVel )

            if not damaged and vel:Length2D() > cvHorizontalSpeedLimit + cvHorizontalSpeedLimitDamageGrace then
                CFC_Parachute.DamageParachute( ent, 1 )
                damaged = true
                if not ent:GetNWBool( "CFC_Parachute_Open" ) then return end
            end

            vel = limitHorizontalVel( vel, timeMult )
            if vel.z <= cvFallZVel then
                vel.z = Lerp( math.Clamp( timeMult * cvFallLerp, 0, 1 ), vel.z, cvFallZVel )

                if phys:IsGravityEnabled() then
                    vel.z = vel.z - physenv.GetGravity().z * timeMult
                end
            end

            if vel ~= originalVel then phys:SetVelocity( vel ) end
        end
    end
end

-- Not meant to be called manually.
function CFC_Parachute._ApplyChuteForces( ply, mv )
    local vel = mv and mv:GetVelocity() or ply:GetVelocity()
    local velZ = vel[3]

    local timeMult = FrameTime()

    -- Modify velocity.
    vel = addHorizontalVel( ply, vel, timeMult )
    velZ = velZ + ( cvFallZVel - velZ ) * cvFallLerp * timeMult

    -- do this after we check the horizontal vel
    -- otherwise players going even remotely upwards with a parachute out won't have their vel limited
    if velZ > cvFallZVel then return end

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

hook.Add( "Move", "CFC_Parachute_Movement", function( ply, mv )
    if not ply:GetNWBool( "CFC_Parachute_Open" ) then return end

    CFC_Parachute._ApplyChuteForces( ply, mv )
end )

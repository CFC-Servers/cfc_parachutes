local TILT_MULT = 0.1
local CHUTE_OFFSET_HEIGHT = 140

local function followOwner( chute, owner )
    local ownerScale = owner:GetNWFloat( "CFC_Parachute_Scale", 1 )
    local pos
    local ang

    if owner:IsPlayer() then
        pos = owner:GetPos() + Vector( 0, 0, CHUTE_OFFSET_HEIGHT * ownerScale )
        ang = owner:EyeAngles()
    else
        local mins, maxs = owner:WorldSpaceAABB()
        pos = ( mins + maxs ) / 2
        pos.z = maxs.z + ( CHUTE_OFFSET_HEIGHT - 72 ) * ownerScale
        ang = owner:GetAngles()
    end

    -- Apply explicit scale changes to an already-open canopy too.
    if chute._chuteOwnerScale ~= ownerScale then
        chute._chuteOwnerScale = ownerScale

        local scaleMatrix = Matrix()

        scaleMatrix:Scale( Vector( ownerScale, ownerScale, ownerScale ) )
        chute:EnableMatrix( "RenderMultiply", scaleMatrix )
    end

    -- Follow the position and angles of the owner.
    ang.p = 0
    ang.r = 0

    chute:SetPos( pos )
    chute:SetAngles( ang )
end

local function setChuteDirection( chute, chuteDirRel )
    local right = chuteDirRel.y

    local frontRight = right / 2
    local frontLeft = -right / 2
    local backRight = right / 2
    local backLeft = -right / 2

    local frontRightScale = 1 - frontRight * TILT_MULT
    local frontLeftScale = 1 - frontLeft * TILT_MULT
    local backRightScale = 1 - backRight * TILT_MULT
    local backLeftScale = 1 - backLeft * TILT_MULT

    chute:ManipulateBoneScale( 0, Vector( frontRightScale, frontRightScale, frontRightScale ) )
    chute:ManipulateBoneScale( 1, Vector( frontLeftScale, frontLeftScale, frontLeftScale ) )
    chute:ManipulateBoneScale( 2, Vector( backRightScale, backRightScale, backRightScale ) )
    chute:ManipulateBoneScale( 3, Vector( backLeftScale, backLeftScale, backLeftScale ) )
end

-- Keep references across AutoRefresh so old clientside models can be removed.
local models = CFC_Parachute.Models or {}
CFC_Parachute.Models = models

local function removeModel( ent )
    local chute = models[ent]
    if IsValid( chute ) then chute:Remove() end

    models[ent] = nil
end

local function cleanupModels()
    for ent in pairs( models ) do
        removeModel( ent )
    end
end

cleanupModels()

-- Discover networked owners once, then update only entities with open parachutes.
local owners = {}

local function watchOwner( ent )
    if not IsValid( ent ) then return end

    ent:SetNWVarProxy( "CFC_Parachute_Open", function( owner, _, _, isOpen )
        owners[owner] = isOpen or nil
        if not isOpen then removeModel( owner ) end
    end )

    if ent:GetNWBool( "CFC_Parachute_Open" ) then owners[ent] = true end
end

local function discoverOwners()
    for _, ent in ipairs( ents.GetAll() ) do
        watchOwner( ent )
    end
end

hook.Add( "NetworkEntityCreated", "CFC_Parachute_WatchOwner", watchOwner )
hook.Add( "InitPostEntity", "CFC_Parachute_DiscoverOwners", discoverOwners )
discoverOwners() -- Also restore active owners after AutoRefresh.

hook.Add( "PreRender", "CFC_Parachute_UpdateModels", function()
    for ent in pairs( owners ) do
        if not IsValid( ent ) or not ent:GetNWBool( "CFC_Parachute_Open" ) then
            removeModel( ent )
            owners[ent] = nil
        elseif ent:IsDormant() or ( ent:IsPlayer() and not ent:Alive() ) then
            removeModel( ent )
        else
            local chute = models[ent]

            if not IsValid( chute ) then
                chute = ClientsideModel( "models/cfc/parachute/chute.mdl", RENDERGROUP_OPAQUE )
                models[ent] = chute
            end

            if IsValid( chute ) then
                followOwner( chute, ent )
                setChuteDirection( chute, ent:GetNWVector( "CFC_Parachute_Direction" ) )

                local designID = ent:GetNWInt( "CFC_Parachute_Design", 1 )
                if chute._chuteDesignID ~= designID then
                    chute._chuteDesignID = designID
                    local material = CFC_Parachute.DesignMaterialNames[designID] or CFC_Parachute.DesignMaterialNames[1]

                    chute:SetSubMaterial( 0, CFC_Parachute.DesignMaterialPrefix .. material )
                end
            end
        end
    end
end )

hook.Add( "ShutDown", "CFC_Parachute_RemoveModels", cleanupModels )

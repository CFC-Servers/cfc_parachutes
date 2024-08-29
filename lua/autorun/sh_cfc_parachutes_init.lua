AddCSLuaFile( "cfc_parachutes/shared/sh_parachute_convars.lua" )
AddCSLuaFile( "cfc_parachutes/shared/sh_parachute.lua" )
AddCSLuaFile( "cfc_parachutes/client/cl_parachute.lua" )
AddCSLuaFile( "cfc_parachutes/client/cl_parachute_lfs.lua" )

include( "cfc_parachutes/shared/sh_parachute_convars.lua" )
include( "cfc_parachutes/shared/sh_parachute.lua" )

if SERVER then
    include( "cfc_parachutes/server/sv_parachute_convars.lua" )
    include( "cfc_parachutes/server/sv_parachute.lua" )
    include( "cfc_parachutes/server/sv_parachute_lfs.lua" )
else
    include( "cfc_parachutes/client/cl_parachute.lua" )
    include( "cfc_parachutes/client/cl_parachute_lfs.lua" )
end

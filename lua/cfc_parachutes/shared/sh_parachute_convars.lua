CFC_Parachute = CFC_Parachute or {}

CFC_Parachute.DesignMaterialPrefix = "models/cfc/parachute/parachute_"
CFC_Parachute.DesignMaterialNames = {
    "base",
    "red",
    "orange",
    "yellow",
    "green",
    "teal",
    "blue",
    "purple",
    "magenta",
    "white",
    "black",
    "brown",
    "rainbow",
    "camo",
    "camo_tan",
    "camo_brown",
    "camo_blue",
    "camo_white",
    "cfc",
    "phatso",
    "missing",
    "troll",
    "troll_gross",
    "saul_goodman",
    "the_click",
    "biter",
    "no_kills",
}
CFC_Parachute.DesignMaterialCount = #CFC_Parachute.DesignMaterialNames

CFC_Parachute.DesignMaterialProxyInfo = { -- Proxy info, indexed by material name. glua is unable to get this info automatically from Material objects.
    biter = {
        AnimatedTexture = {
            animatedTextureVar = "$basetexture",
            animatedTextureFrameNumVar = "$frame",
            animatedTextureFrameRate = 6.25,
        },
    },
}


CreateConVar( "cfc_parachute_fall_speed", 200, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Target fall speed while in a parachute.", 0, 50000 )
CreateConVar( "cfc_parachute_fall_lerp", 2, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "How quickly a parachute will reach its target fall speed. Higher values are faster.", 0, 100 )
CreateConVar( "cfc_parachute_horizontal_speed", 80, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "How quickly you move in a parachute.", 0, 50000 )
CreateConVar( "cfc_parachute_horizontal_speed_limit", 700, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Max horizontal speed of a parachute.", 0, 50000 )
CreateConVar( "cfc_parachute_sprint_boost", 1.25, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "How much of a horizontal boost you get in a parachute while sprinting.", 1, 10 )
CreateConVar( "cfc_parachute_handling", 4, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Improves parachute handling by making it easier to brake or chagne directions. 1 gives no handling boost, 0-1 reduces handling.", 0, 10 )

CreateConVar( "cfc_parachute_space_equip_sv", 1, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Press spacebar while falling to quickly equip a parachute. Defines the default value for players.", 0, 1 )
CreateConVar( "cfc_parachute_space_equip_double_sv", 0, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Double tap spacebar to equip parachutes, instead of a single press. Defines the default value for players.", 0, 1 )

CreateConVar( "cfc_parachute_quick_close_advanced_sv", 0, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Makes quick-close require walk and crouch to be pressed together. Defines the default value for players.", 0, 1 )

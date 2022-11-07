--   /lua/BuffFieldDefinitions.lua
--  Author(s):  Brute51
--  Summary  :  Buff field blueprint list

-- Here's a list of buff fields. Just copy-paste an existing one and change it to your liking.
-- You can merge a blueprint with an existing one by putting "Merge = true" in the blueprint.
-- It will then take the old blueprint and apply the changes.

local BuffFieldBlueprint = import('/lua/sim/BuffField.lua').BuffFieldBlueprint


-- this unique field is intended to be used by airpads
-- designed to overcome the flaw where airpads claim to be full when they are
-- actually empty thus allowing aircraft to recharge and repair slowly without necessarily landing
BuffFieldBlueprint { Name = 'AirStagingBuffField',
    AffectsUnitCategories = categories.AIR * categories.MOBILE - categories.EXPERIMENTAL,
    AffectsAllies = true,
    AffectsVisibleEnemies = false,
    AffectsOwnUnits = true,
    AffectsSelf = false,
    DisableInTransport = true,
    InitiallyEnabled = false,
    MaintenanceConsumptionPerSecondEnergy = 0,
    Radius = 20,
    RadiusOffsetY = 5,

    Buffs = {'AIRSTAGING'},
}

BuffFieldBlueprint { Name = 'AeonMaelstromBuffField',
    AffectsUnitCategories = categories.ALLUNITS,
    AffectsAllies = false,
    AffectsVisibleEnemies = true,
    AffectsOwnUnits = false,
    AffectsSelf = false,
    DisableInTransport = true,
    InitiallyEnabled = false,
    MaintenanceConsumptionPerSecondEnergy = 500,
    Radius = 24,

    VisualScale = 7.2,

    Buffs = {'AeonMaelstromField'},
}

BuffFieldBlueprint { Name = 'AeonMaelstromBuffField2',
    AffectsUnitCategories = categories.ALLUNITS,
    AffectsAllies = false,
    AffectsVisibleEnemies = true,
    AffectsOwnUnits = false,
    AffectsSelf = false,
    DisableInTransport = true,
    InitiallyEnabled = false,
    MaintenanceConsumptionPerSecondEnergy = 750,
    Radius = 32,

    VisualScale = 9.7,

    Buffs = {'AeonMaelstromField2'},
}

BuffFieldBlueprint { Name = 'AeonMaelstromBuffField3',
    AffectsUnitCategories = categories.ALLUNITS,
    AffectsAllies = false,
    AffectsVisibleEnemies = true,
    AffectsOwnUnits = false,
    AffectsSelf = false,
    DisableInTransport = true,
    InitiallyEnabled = false,
    MaintenanceConsumptionPerSecondEnergy = 1200,
    Radius = 40,

    VisualScale = 12.3,

    Buffs = {'AeonMaelstromField3'},
}

BuffFieldBlueprint { Name = 'CybranOpticalDisruptionBuffField',
    AffectsUnitCategories = categories.ALLUNITS - categories.COMMAND - categories.SUBCOMMANDER - categories.TECH1 - categories.WALL,
    AffectsAllies = false,
    AffectsVisibleEnemies = true,
    AffectsOwnUnits = false,
    AffectsSelf = false,
    DisableInTransport = true,
    InitiallyEnabled = false,
    MaintenanceConsumptionPerSecondEnergy = 660,

    Radius = 80,

    Buffs = {'CybranOpticalDisruptionField'},
}

BuffFieldBlueprint { Name = 'SeraphimACURegenBuffField',
    AffectsUnitCategories = categories.SERAPHIM,
    AffectsAllies = false,
    AffectsVisibleEnemies = false,
    AffectsOwnUnits = true,
    AffectsSelf = false,
    DisableInTransport = true,
    InitiallyEnabled = false,
    MaintenanceConsumptionPerSecondEnergy = 0,
    Radius = 18,

    Buffs = {'SeraphimACURegenAura'},
}

BuffFieldBlueprint { Name = 'SeraphimAdvancedACURegenBuffField',
    AffectsUnitCategories = categories.SERAPHIM,
    AffectsAllies = false,
    AffectsVisibleEnemies = false,
    AffectsOwnUnits = true,
    AffectsSelf = false,
    DisableInTransport = true,
    InitiallyEnabled = false,
    MaintenanceConsumptionPerSecondEnergy = 300,
    Radius = 24,

    Buffs = {'SeraphimAdvancedACURegenAura'},
}

BuffFieldBlueprint { Name = 'SeraphimRegenBuffField',
    AffectsUnitCategories = categories.SERAPHIM,
    AffectsAllies = false,
    AffectsVisibleEnemies = false,
    AffectsOwnUnits = true,
    AffectsSelf = false,
    DisableInTransport = true,
    InitiallyEnabled = false,
    MaintenanceConsumptionPerSecondEnergy = 900,
    Radius = 26,

    Buffs = {'SeraphimRegenFieldMoo'},
}




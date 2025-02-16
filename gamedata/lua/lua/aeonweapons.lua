---  /lua/aeonweapons.lua
---  Default definitions of Aeon weapons

local WeaponFile = import('/lua/sim/DefaultWeapons.lua')
local CollisionBeamFile = import('defaultcollisionbeams.lua')

local QuantumBeamGeneratorCollisionBeam = CollisionBeamFile.QuantumBeamGeneratorCollisionBeam
local PhasonLaserCollisionBeam = CollisionBeamFile.PhasonLaserCollisionBeam
local TractorClawCollisionBeam = CollisionBeamFile.TractorClawCollisionBeam

local KamikazeWeapon = WeaponFile.KamikazeWeapon
local BareBonesWeapon = WeaponFile.BareBonesWeapon

local DefaultProjectileWeapon = WeaponFile.DefaultProjectileWeapon
local DefaultBeamWeapon = WeaponFile.DefaultBeamWeapon

local EffectTemplate = import('/lua/EffectTemplates.lua')

local EntityCategoryContains = EntityCategoryContains
local CreateAttachedEmitter= CreateAttachedEmitter
local CreateEmitterAtBone = CreateEmitterAtBone
local CreateEmitterAtEntity = CreateEmitterAtEntity

local ForkThread = ForkThread
local KillThread = KillThread
local VDist2 = VDist2

local GetArmy = moho.entity_methods.GetArmy
local GetBlueprint = moho.weapon_methods.GetBlueprint
local GetCurrentTarget = moho.weapon_methods.GetCurrentTarget
local GetSource = moho.blip_methods.GetSource

local DefaultBuffField = import('/lua/defaultbufffield.lua').DefaultBuffField

local TARGETS = categories.STRUCTURE + categories.COMMAND + categories.EXPERIMENTAL + categories.NAVAL + categories.SUBCOMMANDER

AeonBuffField = Class(DefaultBuffField) {
	AmbientEffects = '/effects/emitters/miasma_cloud_03_emit.bp',
    FieldVisualEmitter = '',
}

AIFBallisticMortarWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.AIFBallisticMortarFlash02,
}

ADFReactonCannon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {'/effects/emitters/reacton_cannon_muzzle_charge_01_emit.bp',
                           '/effects/emitters/reacton_cannon_muzzle_charge_02_emit.bp',
                           '/effects/emitters/reacton_cannon_muzzle_charge_03_emit.bp',
                           '/effects/emitters/reacton_cannon_muzzle_flash_01_emit.bp',
                           '/effects/emitters/reacton_cannon_muzzle_flash_02_emit.bp',
                           '/effects/emitters/reacton_cannon_muzzle_flash_03_emit.bp',},
}

ADFOverchargeWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.ACommanderOverchargeFlash01,
}

ADFTractorClaw = Class(DefaultBeamWeapon) {
    BeamType = TractorClawCollisionBeam,
    FxMuzzleFlash = {},
   
    PlayFxBeamStart = function(self, muzzle)
    
        local target = GetCurrentTarget(self)

        if not target or
            --EntityCategoryContains(categories.STRUCTURE, target) or
            --EntityCategoryContains(categories.COMMAND, target) or
            --EntityCategoryContains(categories.EXPERIMENTAL, target) or
            --EntityCategoryContains(categories.NAVAL, target) or
            --EntityCategoryContains(categories.SUBCOMMANDER, target) or
            EntityCategoryContains( TARGETS, target ) or
            
            not EntityCategoryContains(categories.ALLUNITS, target) then
            
            return
        end

        -- Can't pass recon blips down
        target = self:GetRealTarget(target)
        
		-- something already shooting at this target
        if self:IsTargetAlreadyUsed(target) then 
            return 
        end
		
        local army = GetArmy(target)
        
        -- Create vacuum suck up from ground effects on the unit targetted.
        for k, v in EffectTemplate.ACollossusTractorBeamVacuum01 do
            CreateEmitterAtEntity( target, army, v ):ScaleEmitter(0.25*target:GetFootPrintSize()/0.5)
        end
        
        DefaultBeamWeapon.PlayFxBeamStart(self, muzzle)

        self.TT1 = self:ForkThread(self.TractorThread, target)
        self:ForkThread(self.TractorWatchThread, target)
        
    end,
    
    -- override this function in the unit to check if another weapon already has this
    -- unit as a target.  Target argument should not be a recon blip
    IsTargetAlreadyUsed = function(self, target)
        local weap
		
        for i = 1, self.unit:GetWeaponCount() do
		
            weap = self.unit:GetWeapon(i)
			
            if (weap != self) then
                if self:GetRealTarget( GetCurrentTarget(weap) ) == target then
                    --LOG("Target already used by ", repr(weap.bp.Label))
                    return true
                end
            end
        end
        return false
    end,

    -- recon blip check
    GetRealTarget = function(self, target)
		
        if target and not IsUnit(target) then
            local unitTarget = GetSource(target)
            local unitPos = unitTarget:GetPosition()
            local reconPos = target:GetPosition()
            local dist = VDist2(unitPos[1], unitPos[3], reconPos[1], reconPos[3])
            if dist < 10 then
                return unitTarget
            end
        end
        return target      
    end,

    OnLostTarget = function(self)
        self:AimManipulatorSetEnabled(true)
        DefaultBeamWeapon.OnLostTarget(self)
        DefaultBeamWeapon.PlayFxBeamEnd(self,self.Beams[1].Beam)
    end,

    TractorThread = function(self, target)
        self.unit.Trash:Add(target)
        local beam = self.Beams[1].Beam
        if not beam then return end


        local muzzle = self.bp.MuzzleSpecial
        if not muzzle then return end

        target:SetDoNotTarget(true)
        local pos0 = beam:GetPosition(0)
        local pos1 = beam:GetPosition(1)
        local dist = VDist3(pos0, pos1)

        self.Slider = CreateSlider(self.unit, muzzle, 0, 0, dist, -1, true)

        WaitTicks(1)
        WaitFor(self.Slider)

        -- just in case attach fails...
        target:SetDoNotTarget(false)
		safecall("Ernie cant grapple", moho.entity_methods.AttachBoneTo, target, -1, self.unit, muzzle)
        target:SetDoNotTarget(true)
        
        self.AimControl:SetResetPoseTime(10)

        self.Slider:SetSpeed(15)
        self.Slider:SetGoal(0,0,0)
        
        WaitTicks(1)
        WaitFor(self.Slider)

        if not target.Dead then
            --target.DestructionExplosionWaitDelayMin = 0
            --target.DestructionExplosionWaitDelayMax = 0

            local army = GetArmy(self.unit)
			local CreateEmitterAtBone = CreateEmitterAtBone
            
            for kEffect, vEffect in EffectTemplate.ACollossusTractorBeamCrush01 do
                CreateEmitterAtBone( self.unit, muzzle , army, vEffect )
            end
			
			target:SetDoNotTarget(false)
            
            target:Kill(self.unit, 'Damage', 100)
        end
        
        self.AimControl:SetResetPoseTime(2)
    end,

    TractorWatchThread = function(self, target)
        while not target.Dead do
            WaitTicks(1)
        end
		
        KillThread(self.TT1)
        self.TT1 = nil
		
        if self.Slider then
            self.Slider:Destroy()
            self.Slider = nil
        end
		
        self.unit:DetachAll(self.bp.MuzzleSpecial or 0)
        self:ResetTarget()
        self.AimControl:SetResetPoseTime(2)
    end,
}

ADFTractorClawStructure = Class(DefaultBeamWeapon) {
    BeamType = TractorClawCollisionBeam,
    FxMuzzleFlash = {},
}

ADFChronoDampener = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.AChronoDampener,
    FxMuzzleFlashScale = 0.5,

    CreateProjectileAtMuzzle = function(self, muzzle)
    end,
}

ADFQuadLaserLightWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {'/effects/emitters/flash_04_emit.bp' },
}

ADFLaserLightWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {'/effects/emitters/flash_04_emit.bp' },
}

ADFSonicPulsarWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {'/effects/emitters/flash_02_emit.bp' },
    FxMuzzleFlashScale = 0.5,
}

ADFLaserHeavyWeapon = Class(DefaultProjectileWeapon) {
    FxChargeMuzzleFlash = {},
}

ADFGravitonProjectorWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.AGravitonBolterMuzzleFlash01,
}

ADFDisruptorCannonWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.ADisruptorCannonMuzzle01,
}

ADFDisruptorWeapon = Class(DefaultProjectileWeapon) {
	FxMuzzleFlash = EffectTemplate.ASDisruptorCannonMuzzle01,
    FxChargeMuzzleFlash = EffectTemplate.ASDisruptorCannonChargeMuzzle01,
}

ADFCannonQuantumWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.AQuantumCannonMuzzle01,
}

ADFCannonOblivionWeapon = Class(DefaultProjectileWeapon) {
    FxChargeMuzzleFlash = {
		'/effects/emitters/oblivion_cannon_flash_01_emit.bp',
        '/effects/emitters/oblivion_cannon_flash_02_emit.bp',
        '/effects/emitters/oblivion_cannon_flash_03_emit.bp',
    },
}

ADFCannonOblivionWeapon02 = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.AOblivionCannonMuzzleFlash02,
    FxChargeMuzzleFlash = EffectTemplate.AOblivionCannonChargeMuzzleFlash02,
}

AIFMortarWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {},
}

AIFBombGravitonWeapon = Class(DefaultProjectileWeapon) {}

AIFArtilleryMiasmaShellWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {},

    CreateProjectileForWeapon = function(self, bone)
    
        local proj = self:CreateProjectile(bone)
        
        local damageTable = self.damageTable
        
        local blueprint = self.bp
        local data = false
        
        if blueprint.DoTDamage then
        
            data = {
                Damage = blueprint.DoTDamage,
                Duration = blueprint.DoTDuration,
                Frequency = blueprint.DoTFrequency,
                Radius = blueprint.DamageRadius,
                Type = 'Normal',
                DamageFriendly = blueprint.DamageFriendly,
            }
        end

        if proj and not proj:BeenDestroyed() then
        
            proj:PassDamageData(damageTable)
            
            if data then
                proj:PassData(data)
            end
        end

        return proj
    end,
}

AIFArtillerySonanceShellWeapon = Class(DefaultProjectileWeapon) {
    FxChargeMuzzleFlash = {
        '/effects/emitters/aeon_sonance_muzzle_01_emit.bp',
        '/effects/emitters/aeon_sonance_muzzle_02_emit.bp',
        '/effects/emitters/aeon_sonance_muzzle_03_emit.bp',
    },
}

AIFBombQuarkWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {'/effects/emitters/antiair_muzzle_fire_02_emit.bp',},
}

AANDepthChargeBombWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {'/effects/emitters/antiair_muzzle_fire_02_emit.bp',},

    CreateProjectileForWeapon = function(self, bone)
    
        local proj = self:CreateProjectile(bone)
        
        local damageTable = self.damageTable
        
        local blueprint = self.bp
        local data = false
        
        if blueprint.DoTDamage then
        
            data = {
                Army = self.unit.Sync.army,
                StartRadius = blueprint.DOTStartRadius,
                EndRadius = blueprint.DOTEndRadius,
                DOTtype = blueprint.DOTtype,
                Damage = blueprint.DoTDamage,
                Duration = blueprint.DoTDuration,
                Frequency = blueprint.DoTFrequency,
                Type = 'Normal',
            }
        end

        if proj and not proj:BeenDestroyed() then
            proj:PassDamageData(damageTable)
            
            if data then
                proj:PassData(data)
            end
        end
        
        return proj
    end,
}

AANTorpedoCluster = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {'/effects/emitters/aeon_torpedocluster_flash_01_emit.bp',},

    CreateProjectileForWeapon = function(self, bone)
    
        local proj = self:CreateProjectile(bone)
        
        local damageTable = self.damageTable
        
        local blueprint = self.bp
        local data = false

        if blueprint.DoTDamage then
        
            data = {
                Army = self.unit.Sync.army,
                StartRadius = blueprint.DOTStartRadius,
                EndRadius = blueprint.DOTEndRadius,
                DOTtype = blueprint.DOTtype,
                Damage = blueprint.DoTDamage,
                Duration = blueprint.DoTDuration,
                Frequency = blueprint.DoTFrequency,
                Type = 'Normal',
            }
        end

        if proj and not proj:BeenDestroyed() then
            proj:PassDamageData(damageTable)
            if data then
                proj:PassData(data)
            end
        end
        
        return proj
    end,
}

AIFSmartCharge = Class(DefaultProjectileWeapon) {

    CreateProjectileAtMuzzle = function(self, muzzle)
    
        local proj = DefaultProjectileWeapon.CreateProjectileAtMuzzle(self, muzzle)
        
        local tbl = self.bp.DepthCharge
        
        proj:AddDepthCharge(tbl)
    end,
}

AANChronoTorpedoWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {
		'/effects/emitters/default_muzzle_flash_01_emit.bp',
        '/effects/emitters/default_muzzle_flash_02_emit.bp',
        '/effects/emitters/torpedo_underwater_launch_01_emit.bp',
    },
}

AIFQuasarAntiTorpedoWeapon = Class(DefaultProjectileWeapon) {
	FxMuzzleFlash = EffectTemplate.AQuasarAntiTorpedoFlash,
}

AKamikazeWeapon = Class(KamikazeWeapon) {
    FxMuzzleFlash = {},
}

AIFQuantumWarhead = Class(DefaultProjectileWeapon) {}

AIFCommanderDeathWeapon = Class(BareBonesWeapon) {

    OnCreate = function(self)
	
        BareBonesWeapon.OnCreate(self)

        local myBlueprint = self.bp
		
        self.Data = {
            NukeOuterRingDamage = myBlueprint.NukeOuterRingDamage or 10,
            NukeOuterRingRadius = myBlueprint.NukeOuterRingRadius or 40,
            NukeOuterRingTicks = myBlueprint.NukeOuterRingTicks or 20,
            NukeOuterRingTotalTime = myBlueprint.NukeOuterRingTotalTime or 10,

            NukeInnerRingDamage = myBlueprint.NukeInnerRingDamage or 2000,
            NukeInnerRingRadius = myBlueprint.NukeInnerRingRadius or 30,
            NukeInnerRingTicks = myBlueprint.NukeInnerRingTicks or 24,
            NukeInnerRingTotalTime = myBlueprint.NukeInnerRingTotalTime or 24,
        }
    end,

    OnFire = function(self)
    end,

    Fire = function(self)

        local myProjectile = self.unit:CreateProjectile( self.bp.ProjectileId, 0, 0, 0, nil, nil, nil):SetCollision(false)
		
        myProjectile:PassDamageData(self.damageTable)
		
        if self.Data then
            myProjectile:PassData(self.Data)
        end
    end,
}

AIFParagonDeathWeapon = Class(BareBonesWeapon) {

    OnCreate = function(self)
    
        BareBonesWeapon.OnCreate(self)

        local myBlueprint = self.bp

        self.Data = {
            NukeOuterRingDamage = myBlueprint.NukeOuterRingDamage or 10,
            NukeOuterRingRadius = myBlueprint.NukeOuterRingRadius or 40,
            NukeOuterRingTicks = myBlueprint.NukeOuterRingTicks or 20,
            NukeOuterRingTotalTime = myBlueprint.NukeOuterRingTotalTime or 10,

            NukeInnerRingDamage = myBlueprint.NukeInnerRingDamage or 2000,
            NukeInnerRingRadius = myBlueprint.NukeInnerRingRadius or 30,
            NukeInnerRingTicks = myBlueprint.NukeInnerRingTicks or 24,
            NukeInnerRingTotalTime = myBlueprint.NukeInnerRingTotalTime or 24,
        }
    end,


    OnFire = function(self)
    end,

    Fire = function(self)

        local myProjectile = self.unit:CreateProjectile( self.bp.ProjectileId, 0, 0, 0, nil, nil, nil):SetCollision(false)
		
        myProjectile:PassDamageData(self.damageTable)
		
        if self.Data then
            myProjectile:PassData(self.Data)
        end
    end,
}

ACruiseMissileWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = { '/effects/emitters/aeon_missile_launch_01_emit.bp', },
}

ADFLaserHighIntensityWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.AHighIntensityLaserFlash01,
}

AAATemporalFizzWeapon = Class(DefaultProjectileWeapon) {

    FxChargeEffects = { '/effects/emitters/temporal_fizz_muzzle_charge_01_emit.bp', },
    FxMuzzleFlash = { '/effects/emitters/temporal_fizz_muzzle_flash_01_emit.bp',},
    ChargeEffectMuzzles = {},

    PlayFxRackSalvoChargeSequence = function(self)
    
        DefaultProjectileWeapon.PlayFxRackSalvoChargeSequence(self)
		
        local army = self.unit.Sync.army
        
		local CreateAttachedEmitter = CreateAttachedEmitter
		
        for _, valueb in self.ChargeEffectMuzzles do
            for _, valuee in self.FxChargeEffects do
                CreateAttachedEmitter(self.unit,valueb,army, valuee)
            end
        end
    end,
}

AAASonicPulseBatteryWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {'/effects/emitters/sonic_pulse_muzzle_flash_01_emit.bp',},
}

AAAZealotMissileWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.CZealotLaunch01,
}

AAAZealot02MissileWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {'/effects/emitters/flash_04_emit.bp' },
}

AAALightDisplacementAutocannonMissileWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.ALightDisplacementAutocannonMissileMuzzleFlash,
}

AAAAutocannonQuantumWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = {'/effects/emitters/quantum_displacement_cannon_flash_01_emit.bp',},
}

AIFMissileTacticalSerpentineWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = { '/effects/emitters/aeon_missile_launch_02_emit.bp', },
}

AIFMissileTacticalSerpentine02Weapon = Class(DefaultProjectileWeapon) {
	FxMuzzleFlash = EffectTemplate.ASerpFlash01,
}

AQuantumBeamGenerator = Class(DefaultBeamWeapon) {
    BeamType = QuantumBeamGeneratorCollisionBeam,

    FxUpackingChargeEffects = {},
    FxUpackingChargeEffectScale = 1,

    PlayFxWeaponUnpackSequence = function( self )
    
        local army = self.unit.Sync.army
        
        local bp = self.bp
        
		local CreateAttachedEmitter = CreateAttachedEmitter
		
        for k, v in self.FxUpackingChargeEffects do
            for ek, ev in bp.RackBones[self.CurrentRackSalvoNumber].MuzzleBones do
                CreateAttachedEmitter(self.unit, ev, army, v):ScaleEmitter(self.FxUpackingChargeEffectScale)
            end
        end
        
        DefaultBeamWeapon.PlayFxWeaponUnpackSequence(self)
    end,
}

AAMSaintWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.ASaintLaunch01,
}

AAMWillOWisp = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.AAntiMissileFlareFlash,
}

ADFPhasonLaser = Class(DefaultBeamWeapon) {

    BeamType = PhasonLaserCollisionBeam,
    FxMuzzleFlash = {},
    FxChargeMuzzleFlash = {},
    FxUpackingChargeEffects = EffectTemplate.CMicrowaveLaserCharge01,
    FxUpackingChargeEffectScale = 1,

    PlayFxWeaponUnpackSequence = function( self )
    
        if not self.ContBeamOn then
        
            local army = self.unit.Sync.army
            
            local bp = self.bp
            
			local CreateAttachedEmitter = CreateAttachedEmitter
			
            for k, v in self.FxUpackingChargeEffects do
				if bp.RackBones[self.CurrentRackSalvoNumber].MuzzleBones then
					for ek, ev in bp.RackBones[self.CurrentRackSalvoNumber].MuzzleBones do
						CreateAttachedEmitter(self.unit, ev, army, v):ScaleEmitter(self.FxUpackingChargeEffectScale)
					end
				end
            end
            
            DefaultBeamWeapon.PlayFxWeaponUnpackSequence(self)
        end
    end,
}

ADFQuantumAutogunWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.Aeon_DualQuantumAutoGunMuzzleFlash,
}

ADFHeavyDisruptorCannonWeapon = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.Aeon_HeavyDisruptorCannonMuzzleFlash,
    FxChargeMuzzleFlash = EffectTemplate.Aeon_HeavyDisruptorCannonMuzzleCharge,
}

AIFQuanticArtillery = Class(DefaultProjectileWeapon) {
    FxMuzzleFlash = EffectTemplate.Aeon_QuanticClusterMuzzleFlash,
    FxChargeMuzzleFlash = EffectTemplate.Aeon_QuanticClusterChargeMuzzleFlash,
}


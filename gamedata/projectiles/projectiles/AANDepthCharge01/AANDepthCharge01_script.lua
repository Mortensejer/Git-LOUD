local ADepthChargeProjectile = import('/lua/aeonprojectiles.lua').ADepthChargeProjectile

local ForkThread = ForkThread
local WaitSeconds = WaitSeconds
local CreateEmitterAtEntity = CreateEmitterAtEntity

AANDepthCharge01 = Class(ADepthChargeProjectile) {

    CountdownLength = 10,
	
    FxEnterWater= { '/effects/emitters/water_splash_plume_01_emit.bp' },

    OnCreate = function(self)
	
        ADepthChargeProjectile.OnCreate(self)
        
		self.HasImpacted = false
		
        self:ForkThread(self.CountdownExplosion)
		
    end,

    CountdownExplosion = function(self)
	
        WaitSeconds(self.CountdownLength)

        if not self.HasImpacted then
            self.OnImpact(self, 'Underwater', nil)
        end
		
    end,

    OnEnterWater = function(self)
	
        ADepthChargeProjectile.OnEnterWater(self)

        local army = self:GetArmy()

        self:SetMaxSpeed(9)
        self:SetVelocity(1.5)
        self:SetAcceleration(1.25)
        self:TrackTarget(true)
        self:StayUnderwater(true)
        self:SetTurnRate(360)
        self:SetVelocityAlign(true)
        self:SetStayUpright(false)
		
        self:ForkThread(self.EnterWaterMovementThread)
		
    end,
    
    EnterWaterMovementThread = function(self)
	
        WaitTicks(1)
        self:SetVelocity(0.5)
		
    end,

    OnLostTarget = function(self)
	
        self:SetMaxSpeed(2)
        self:SetAcceleration(-0.6)
        self:ForkThread(self.CountdownMovement)
		
    end,

    CountdownMovement = function(self)
	
        WaitSeconds(2)
		
        self:SetMaxSpeed(0)
        self:SetAcceleration(0)
        self:SetVelocity(0)
		
    end,

    OnImpact = function(self, TargetType, TargetEntity)

        self.HasImpacted = true
		
        ADepthChargeProjectile.OnImpact(self, TargetType, TargetEntity)
		
    end,
}

TypeClass = AANDepthCharge01
--**  File     :  /lua/AIBehaviors.lua

local import = import

local AIAddMustScoutArea = import('/lua/ai/aiutilities.lua').AIAddMustScoutArea
local GetOwnUnitsAroundPoint = import('/lua/ai/aiutilities.lua').GetOwnUnitsAroundPoint
local RandomLocation = import('/lua/ai/aiutilities.lua').RandomLocation

local AISortScoutingAreas = import('/lua/loudutilities.lua').AISortScoutingAreas
local GetBasePerimeterPoints = import('/lua/loudutilities.lua').GetBasePerimeterPoints

local CreateUnitDestroyedTrigger = import('/lua/scenarioframework.lua').CreateUnitDestroyedTrigger

local AIFindTargetInRangeInCategoryWithThreatFromPosition = import('/lua/ai/aiattackutilities.lua').AIFindTargetInRangeInCategoryWithThreatFromPosition

local LOUDCOPY = table.copy
local LOUDEQUAL = table.equal
local LOUDGETN = table.getn
local LOUDINSERT = table.insert
local LOUDREMOVE = table.remove
local LOUDFLOOR = math.floor
local LOUDMAX = math.max
local LOUDMIN = math.min
local LOUDPOW = math.pow
local LOUDSORT = table.sort
local LOUDSQUARE = math.sqrt
local LOUDTIME = GetGameTimeSeconds
local LOUDENTITY = EntityCategoryContains
local LOUDV3 = VDist3


local ForkThread = ForkThread
local ForkTo = ForkThread

local Random = Random

local VDist2Sq = VDist2Sq
local VDist3 = VDist3

local WaitSeconds = WaitSeconds
local WaitTicks = coroutine.yield

local AssignUnitsToPlatoon = moho.aibrain_methods.AssignUnitsToPlatoon
local AttackTarget = moho.platoon_methods.AttackTarget

local CalculatePlatoonThreat = moho.platoon_methods.CalculatePlatoonThreat

local GetAIBrain = moho.unit_methods.GetAIBrain
local GetBrain = moho.platoon_methods.GetBrain

local GetBuildRate = moho.unit_methods.GetBuildRate

local GetEconomyStored = moho.aibrain_methods.GetEconomyStored
local GetEconomyStoredRatio = moho.aibrain_methods.GetEconomyStoredRatio
local GetEconomyTrend = moho.aibrain_methods.GetEconomyTrend

local GetPlatoonPosition = moho.platoon_methods.GetPlatoonPosition
local GetPlatoonUnits = moho.platoon_methods.GetPlatoonUnits
local GetPosition = moho.entity_methods.GetPosition	
local GetSquadUnits = moho.platoon_methods.GetSquadUnits

local GetUnitsAroundPoint = moho.aibrain_methods.GetUnitsAroundPoint
local GetNumUnitsAroundPoint = moho.aibrain_methods.GetNumUnitsAroundPoint
local GetThreatsAroundPosition = moho.aibrain_methods.GetThreatsAroundPosition
local GetThreatAtPosition = moho.aibrain_methods.GetThreatAtPosition
    
local GetTerrainHeight = GetTerrainHeight
local GetSurfaceHeight = GetSurfaceHeight

local IsIdleState = moho.unit_methods.IsIdleState
local IsUnitState = moho.unit_methods.IsUnitState

local MakePlatoon = moho.aibrain_methods.MakePlatoon
local PlatoonExists = moho.aibrain_methods.PlatoonExists
local SetCustomName = moho.unit_methods.SetCustomName


function CommanderThread( platoon, aiBrain )

    local WaitTicks = WaitTicks

	local cdr = GetPlatoonUnits(platoon)[1]

	if platoon.PlatoonData.aggroCDR then

		local size = ScenarioInfo.size[1]
		
		if ScenarioInfo.size[2] > size then
			size = ScenarioInfo.size[2]
		end
		
		cdr.Mult = (size * 0.5) * 0.01
		size = nil
	end
	
	local Mult = cdr.Mult or 1
	
	local NextTaunt = GetGameTimeSeconds() + 660 + Random(1,660)
    
	cdr.CDRHome = LOUDCOPY(GetPosition(cdr))
    
    ForkThread ( LifeThread, aiBrain, cdr )
	
	local moveWait = 0
    
    --LOG("*AI DEBUG Commander at start of thread is "..repr(cdr))

	-- So - this loop runs on top of everything the commander might otherwise be doing
	-- ie. - this is usually building, or trying to build something
	-- the loop cycles over every 4.5 seconds
    while not cdr.Dead do
		
		Mult = 1
		
        WaitTicks(45)
	
        -- See if Bob needs to fight
        if not cdr.Dead then
		
			CDROverCharge( aiBrain, cdr)
		end
		
		-- Run Away when hurt
        if not cdr.Dead then
		
			CDRRunAway( aiBrain, cdr )
		end
		
		-- if Bob was building something and was distracted
		if not cdr.Dead then
		
			CDRFinishUnit( aiBrain, cdr )
		end
		
        -- Go back to base when outside tether
        if not cdr.Dead then
		
			CDRReturnHome( aiBrain, cdr, Mult ) 
		end
		
		-- Wander around when idle too long
        if not cdr.Dead and moveWait >= 10 then 
		
			CDRHideBehavior( aiBrain, cdr )     -- this will run for 8 seconds
			
			moveWait = 0
			
		else
		
			moveWait = moveWait + 1
		end
		
        -- resume building
        if not cdr.Dead and IsIdleState(cdr) and not cdr.Fighting and not cdr.Upgrading and not IsUnitState( cdr, "Building")
			and not cdr:IsUnitState("Attacking") and not cdr:IsUnitState("Repairing") and not cdr.UnitBeingBuiltBehavior and not cdr:IsUnitState("Upgrading") 
			and not cdr:IsUnitState("Enhancing") then
		
            if not cdr.EngineerBuildQueue or LOUDGETN(cdr.EngineerBuildQueue) == 0 then
				
				cdr.UnitBeingBuiltBehavior = false
            end
        end

		-- if GetGameTimeSeconds() > NextTaunt then
		
			-- SUtils.AIRandomizeTaunt(aiBrain)
			-- NextTaunt = GetGameTimeSeconds() + 660 + Random(1,660)
			
		-- end
		
    end
	
end

-- This is a special 'resource' thread that runs on the ACU
-- It essentially only comes into play when he crashes his eco
-- and then provides upto a certain amount of compensation
-- the effect of this is very very subtle, so we leave it obscured
-- would be really nice it we could tie it to resources that had overflowed
function LifeThread( aiBrain, cdr )

    local mincome, mrequested, mneeded
    local eincome, erequested, eneeded
    
    local GetEconomyIncome = moho.aibrain_methods.GetEconomyIncome
    local GetEconomyRequested = moho.aibrain_methods.GetEconomyRequested
    local GiveResource = moho.aibrain_methods.GiveResource
    local WaitTicks = WaitTicks
    
    local MATHMIN = LOUDMIN

    while true do
    
        WaitTicks(2)
        
        if GetEconomyStoredRatio( aiBrain, 'MASS') < .01 then
        
            mincome = GetEconomyIncome( aiBrain, 'MASS')
            mrequested = GetEconomyRequested( aiBrain, 'MASS')
            
            if mrequested > mincome then
            
                -- upto 10
                mneeded = MATHMIN(10,((mrequested - mincome ) * 10))
                
                GiveResource( aiBrain, 'Mass', mneeded)
            end
        end
        
        if GetEconomyStoredRatio( aiBrain, 'ENERGY') < .01 then
        
            eincome = GetEconomyIncome( aiBrain, 'ENERGY')
            erequested = GetEconomyRequested( aiBrain, 'ENERGY')
            
            if erequested > eincome then
            
                -- upto 120
                eneeded = MATHMIN(120,((erequested - eincome ) * 10))
                
                GiveResource( aiBrain, 'Energy', eneeded)
            end
        end
    end
end

-- functions used by Commander Thread
function CDROverCharge( aiBrain, cdr ) 

	-- assume there is nothing to respond to
	local commanderResponse = false
	local distressLoc = false
	local distressType = false
	
	local distressRange = 80
	
	local totalPercent = 0;
	
	-- get status of Bobs Shield (if he has one)
	if cdr:ShieldIsOn() then
		totalPercent = ((cdr:GetHealth() + cdr.MyShield:GetHealth()) / (cdr:GetMaxHealth() + cdr.MyShield:GetMaxHealth()))
		else
		totalPercent = cdr:GetHealthPercent();
	end
	
	-- if Bob is in condition to fight and isn't in distress -- see if there is an alert
	if totalPercent > .74 and not aiBrain.CDRDistress then

		local EM = aiBrain.BuilderManagers.MAIN.EngineerManager
		
		if EM.BaseMonitor.ActiveAlerts > 0 then
	
			-- checks for a Land distress alert at this base
			distressLoc, distressType = EM:BaseMonitorGetDistressLocation( aiBrain, EM.Location, distressRange, 6, 'Land')
			
		end
	
		-- if there is a LAND distress call 
		if (distressLoc and distressType == 'Land')  then
	
			local GetNumUnitsAroundPoint = GetNumUnitsAroundPoint
	
			local distressUnitsNaval = GetNumUnitsAroundPoint( aiBrain, categories.NAVAL, distressLoc, 60, 'Enemy' ) 
			local distressUnitsAir = GetNumUnitsAroundPoint( aiBrain, categories.AIR * (categories.BOMBER + categories.GROUNDATTACK) - categories.ANTINAVY, distressLoc, 60, 'Enemy' ) 
			local distressUnitsexp = GetNumUnitsAroundPoint( aiBrain, categories.EXPERIMENTAL, distressLoc, 150, 'Enemy' )
		
			if distressUnitsNaval > 2  or distressUnitsAir > 5 or distressUnitsexp > 0 then	
			
				return	-- we're not fighting
				
			else
			
				commanderResponse = true
				
			end
		
		else
		
			return
			
		end
	
		-- if the distress location is within allowed range
		if distressLoc and VDist3( distressLoc, cdr.CDRHome ) < distressRange then

			-- store anything he might be building
			cdr.UnitBeingBuiltBehavior = cdr.UnitBeingBuilt or false
			
			-- mark him as fighting so that EM will not give him a job to do
			cdr.Fighting = true
			
			cdr.Upgrading = false
			
			-- disband exsiting platoon directly, bypassing code that would have him seek another job
			if cdr.PlatoonHandle and cdr.PlatoonHandle != aiBrain.ArmyPool then
			
				if PlatoonExists(aiBrain, cdr.PlatoonHandle) then
				
					--LOG("*AI DEBUG "..aiBrain.Nickname.." CDR disbands "..cdr.PlatoonHandle.BuilderName)
					cdr.PlatoonHandle:PlatoonDisband( aiBrain )
					
				end

			end

			-- create a platoon for fighting
			local plat = MakePlatoon( aiBrain,'CDRFights','none')
			
			AssignUnitsToPlatoon( aiBrain, plat, {cdr}, 'Attack', 'None' )
			plat.BuilderName = 'CDR Fights'		
			
			IssueClearCommands( {cdr} )
			
			-- set target priorities
			local priList = { categories.ENGINEER, categories.INDIRECTFIRE, categories.DIRECTFIRE, categories.CONSTRUCTION, categories.STRUCTURE }
			
			plat:SetPrioritizedTargetList( 'Attack', priList )
			cdr:SetTargetPriorities( priList )
			
			local target = false
			local continueFighting = true
			
			-- get the stats on his overcharge weapon
			local weapBPs = cdr:GetBlueprint().Weapon
			local weapon
		
			for _,v in weapBPs do
				if v.Label == 'OverCharge' then
					weapon = v
					break
				end
			end

			local maxRadius = weapon.MaxRadius * 4.55 -- * Mult
			local weapRange = weapon.MaxRadius		
		
			local id = cdr:GetEntityId()
			
			-- set the overcharge delay to RateOfFire / 1 ( ie.  1/0.2 = 5 seconds)
			local overchargedelay = math.ceil(1/weapon.RateOfFire)
			
			--LOG("*AI DEBUG Commander Overcharge delay is "..overchargedelay)
			
			-- set the recharge counter to maximum (indicates ready to fire)
			local counter = overchargedelay
			
			local cdrThreat = cdr:GetBlueprint().Defense.SurfaceThreatLevel
			
			local enemyThreat
            local friendlyThreat
		
			local GetThreatAtPosition = GetThreatAtPosition

			-- go and fight now
			while continueFighting and not cdr.Dead do
			
				local overcharging = false
				local cdrCurrentPos = GetPosition(cdr)
				
				-- range check --
				if CDRReturnHome( aiBrain, cdr, .9 ) then
				
					continueFighting = false
					cdr.Fighting = false
					
					return
					
				end
				
				if not target then
				
					FloatingEntityText(id,'Time for something to die..')
				
					IssueClearCommands( {cdr} )
					IssueFormAggressiveMove( GetPlatoonUnits(plat), distressLoc, 'AttackFormation', 0 )
				
				end
				
				WaitTicks(30)
				
				-- if ready to fire and not target, or target is dead, or target is out of range - look for a new target
				if counter >= overchargedelay and ( (not target) or (target.Dead) or (target and (not target.Dead) and  LOUDV3(GetPosition(cdr), GetPosition(target)) > maxRadius)) then
					
					-- find a priority target in weapon range
					for k,v in priList do
					
						if PlatoonExists( aiBrain, plat ) then
						
							target = plat:FindClosestUnit( 'Attack', 'Enemy', true, v )
					
							if target and LOUDV3(GetPosition(cdr), GetPosition(target)) < maxRadius then
						
								local cdrLayer = cdr:GetCurrentLayer()
								local targetLayer = target:GetCurrentLayer()
						
								if cdrLayer == 'Land' and (targetLayer == 'Land' or targetLayer == 'Water') then
								
									break
									
								else
								
									target = false
									
								end
								
							else
							
								target = false
								
							end
							
						end
						
					end
					
					-- found a priority target in weapon range --
					if target then
					
						local targetPos = GetPosition(target)
					
						enemyThreat = GetThreatAtPosition( aiBrain, targetPos, 0, true, 'AntiSurface')
						friendlyThreat = GetThreatAtPosition( GetAIBrain(target), targetPos, 0, true, 'AntiSurface')
						
						--LOG("*AI DEBUG Commander "..aiBrain.Nickname.." - threat numbers - enemy "..enemyThreat.." - friendly "..friendlyThreat + cdrThreat)
		
						if target and (aiBrain:GetEconomyStored('ENERGY') >= weapon.EnergyRequired) and (not target.Dead) and (LOUDV3(GetPosition(cdr), GetPosition(target)) <= weapRange) then
						
							FloatingEntityText(id,'Eat some of this...')
							
							overcharging = true		# set recharging flag
							IssueClearCommands({cdr})

							IssueOverCharge( {cdr}, target )
							LOG("*AI DEBUG "..aiBrain.Nickname.." Overcharge fired!")
							counter = 0
						
						elseif target and not target.Dead then
					
							--LOG("*AI DEBUG " .. aiBrain.Nickname .. " Commander target out of overcharge range - moving to attack")
							local tarPos = GetPosition(target)
							IssueClearCommands( {cdr} )
							IssueAttack( {cdr}, target )
							
						end
					
						if enemyThreat > (friendlyThreat * 1.25) + cdrThreat then
						
							LOG("*AI DEBUG "..aiBrain.Nickname.." Commander target threat too high")
							
							FloatingEntityText(id,'Yikes! Much too hot for me..')
							
							target = false
							continueFighting = false
							
						end
						
					-- can't find a target in range yet keep moving towards distress --
					elseif distressLoc then

						enemyThreat = GetThreatAtPosition( aiBrain, distressLoc, 0, true, 'AntiSurface')
						friendlyThreat = GetThreatAtPosition( aiBrain, distressLoc, 0, true, 'AntiSurface', aiBrain.ArmyIndex )
					
						if enemyThreat > (friendlyThreat * 1.25) + cdrThreat then
						
							LOG("*AI DEBUG "..aiBrain.Nickname.." Commander ALERT position threat "..enemyThreat.." is too high for my "..((friendlyThreat * 1.25) + cdrThreat))
							
							continueFighting = false
							
						elseif ( LOUDV3( distressLoc, cdr.CDRHome ) < distressRange ) then
							
							IssueClearCommands( {cdr} )
							IssueMove( {cdr}, distressLoc )
							
						end
                        
                        if enemyThreat < 10 then
                        
                            continueFighting = false
                            
                        end
						
					end
					
				end

				-- increment the overcharge available counter
				if continueFighting then
				
					WaitTicks(10)
					counter = counter + 1
					
				end
		
				if EM.BaseMonitor.ActiveAlerts > 0 then
					-- rechecks for a Land distress alert at this base
					distressLoc, distressType = EM:BaseMonitorGetDistressLocation( aiBrain, EM.Location, distressRange, 6, 'Land')
				end

				-- did Bob die ?
				if cdr.Dead then
					aiBrain.CDRDistress = nil
					return
				end
				
				totalPercent = 1
				
				-- should Bob keep fighting ?
				if cdr:ShieldIsOn() then
					totalPercent = ((cdr:GetHealth() + cdr.MyShield:GetHealth()) / (cdr:GetMaxHealth() + cdr.MyShield:GetMaxHealth()))
				else
					totalPercent = cdr:GetHealthPercent();
				end
				
				if not distressLoc or ( LOUDV3( distressLoc, cdr.CDRHome ) > distressRange ) or (totalPercent < .75) then
				
					continueFighting = false
					
				end
				
			end
			
			IssueClearCommands( {cdr} )
			
			-- disband the commanders combat platoon so that he looks for another job
			if PlatoonExists( aiBrain, plat) then
			
				ForkThread(cdr.PlatoonHandle.PlatoonDisband, cdr.PlatoonHandle, aiBrain )
				
			end

			--LOG("*AI DEBUG "..aiBrain.Nickname.." Commander ends fighting")
			
			cdr.Fighting = false
		end
		
	end
	
end

function CDRRunAway( aiBrain, cdr )

	local totalPercent = 0

	-- note: ShieldIsOn will return false if the commander doesn't have a shield or it's off
	-- this replaced a whole series of specific checks to see if he actually has a shield upgrade
	if cdr:ShieldIsOn() then
		totalPercent = ((cdr:GetHealth() + cdr.MyShield:GetHealth()) / (cdr:GetMaxHealth() + cdr.MyShield:GetMaxHealth()))
	else 
		totalPercent = cdr:GetHealthPercent()
	end
	
	-- if the CDR is hurt
    if totalPercent < .75  then

		local GetNumUnitsAroundPoint = GetNumUnitsAroundPoint
		
        local nmeAir = GetNumUnitsAroundPoint( aiBrain, categories.BOMBER + categories.GROUNDATTACK - categories.ANTINAVY, cdr.CDRHome, 75, 'Enemy' )
        local nmeLand = GetNumUnitsAroundPoint( aiBrain, categories.COMMAND + (categories.LAND - categories.ANTIAIR), cdr.CDRHome, 75, 'Enemy' )
		local nmeHardcore = GetNumUnitsAroundPoint( aiBrain, categories.EXPERIMENTAL, cdr.CDRHome, 120, 'Enemy' )
		
		-- immediate threats nearby - time to run		
        if nmeAir > 5 or nmeLand > 0 or nmeHardcore > 0 then
		
			local cdrPos = GetPosition(cdr)
		
			if not aiBrain.CDRDistress then
		
				LOG("*AI DEBUG Commander " .. aiBrain.Nickname .. " sounds COMMANDER DISTRESS")
				aiBrain.CDRDistress = cdrPos

				-- mark him as fighting so that EM will not give him a job to do
				cdr.Fighting = true
			
				cdr.Upgrading = false
				
				-- forget about continuing to build
				cdr.UnitBeingBuiltBehavior = false

				-- disband existing platoon directly so he bypasses the code that would have him seek a new job
				if cdr.PlatoonHandle and cdr.PlatoonHandle != aiBrain.ArmyPool then
			
					if PlatoonExists( aiBrain, cdr.PlatoonHandle ) then
				
						--LOG("*AI DEBUG "..aiBrain.Nickname.." CDR disbands "..cdr.PlatoonHandle.BuilderName)
						cdr.PlatoonHandle:PlatoonDisband( aiBrain )

					end

				end
		
			end		
			
			-- determine category of what he should run to (default is ground defense)
            local category = categories.DIRECTFIRE
			
			-- see if there are any shields nearby first
			local nmaShield = GetNumUnitsAroundPoint( aiBrain, categories.SHIELD, cdrPos, 60, 'Ally' )

			local runShield = false
			
			if nmaShield > 0 then
			
				category = categories.SHIELD 
				runShield = true
				
			-- head for AA if air units
            elseif nmeAir > 5 then
			
                category = categories.ANTIAIR
				
            end
			
            local runSpot, prevSpot
			
			-- the commander will stay in this loop while less than 75% health and enemy units are present
            while ( (not cdr.Dead) and (totalPercent < .77) ) and ( nmeAir > 5 or nmeLand > 0 or nmeHardcore > 0 ) do

				FloatingEntityText( cdr:GetEntityId(),'Running for cover...')
				--LOG("*AI DEBUG "..aiBrain.Nickname.." running for cover")
				
                runSpot = import('/lua/ai/altaiutilities.lua').AIFindDefensiveAreaSorian( aiBrain, cdr, category, 80, runShield )
				
				if not runSpot or (prevSpot and runSpot[1] == prevSpot[1] and runSpot[3] == prevSpot[3]) then

					runSpot = RandomLocation( aiBrain.StartPosX, aiBrain.StartPosZ )
					
				end
				
                if not prevSpot or runSpot[1] ~= prevSpot[1] or runSpot[3] ~= prevSpot[3] then

					IssueClearCommands( {cdr} )

                    if VDist2( cdrPos[1], cdrPos[3], runSpot[1], runSpot[3] ) >= 10 then
					
						IssueMove( {cdr}, runSpot )
						prevSpot = LOUDCOPY(runSpot)
						
                    end
					
                end

                WaitTicks(200)
				
				-- retest the run away conditions
                if not cdr.Dead then
				
                    cdrPos = GetPosition(cdr)
					
					nmeAir = GetNumUnitsAroundPoint( aiBrain, categories.BOMBER + categories.GROUNDATTACK - categories.ANTINAVY, cdr.CDRHome, 75, 'Enemy' )
					nmeLand = GetNumUnitsAroundPoint( aiBrain, categories.COMMAND + (categories.LAND - categories.ANTIAIR), cdr.CDRHome, 75, 'Enemy' )
					nmeHardcore = GetNumUnitsAroundPoint( aiBrain, categories.EXPERIMENTAL, cdr.CDRHome, 120, 'Enemy' )
					
					totalPercent = 1	-- default if no shield upgrade

					if cdr:ShieldIsOn() then
						totalPercent = ((cdr:GetHealth() + cdr.MyShield:GetHealth()) / (cdr:GetMaxHealth() + cdr.MyShield:GetMaxHealth()))
					else 
						totalPercent = cdr:GetHealthPercent()
					end
					
                end
				
            end
			
			aiBrain.CDRDistress = nil
			
			LOG("*AI DEBUG "..aiBrain.Nickname.." Commander Distress DEACTIVATED")
			
			IssueClearCommands( {cdr} )
			
        end
	
		-- since the CDR should be floating around in DelayAssignEngineerTask at this point
		-- setting this to false should allow him to get a new engineer job
		cdr.Fighting = false
		
    end
	
end

function CDRReturnHome( aiBrain, cdr, Mult )

	local radius = 80
	local distance = VDist3(GetPosition(cdr), cdr.CDRHome)
	
    if (not cdr.Dead) and distance > (radius*Mult) then
		
        local plat = MakePlatoon( aiBrain, 'CDRReturnHome', 'none' )
		
        AssignUnitsToPlatoon( aiBrain, plat, {cdr}, 'Support', 'None' )
		plat.BuilderName = 'CDRReturnHome'
		
		IssueClearCommands( {cdr} )
		IssueMove( {cdr}, cdr.CDRHome )
        
        WaitTicks(75)
		
		plat:SetAIPlan('ReturnToBaseAI',aiBrain)
		
		return true

	end
	
	if cdr.Dead then
	
		aiBrain.CDRDistress = nil
		return true

	end
	
	return false
	
end

function CDRFinishUnit( aiBrain, cdr )
	
    if cdr.UnitBeingBuiltBehavior then

		if not cdr.UnitBeingBuiltBehavior:BeenDestroyed() then

			--LOG("*AI DEBUG "..aiBrain.Nickname.." Finishing unit")
		
			IssueClearCommands( {cdr} )
			
			IssueRepair( {cdr}, cdr.UnitBeingBuiltBehavior )
		
			FloatingEntityText( cdr:GetEntityId(),' Finishing Unit ')
		end
	end

    cdr.UnitBeingBuiltBehavior = false
end

-- When idle, the ACU will exhibit a 'hide' behavior and run for certain defensive positions
-- Modified this so that he doesn't run like this if there's no place to run to - the original
-- Sorian code would have the ACU run to the 'top left' of the base every time in this case
function CDRHideBehavior( aiBrain, cdr )

	if IsIdleState(cdr) then
		
        cdr.Fighting = true
        cdr.Upgrading = false
	    
        local category = false
		
		local nmaShield = GetNumUnitsAroundPoint( aiBrain, categories.SHIELD, cdr.CDRHome, 100, 'Ally' )
		local nmaAA = GetNumUnitsAroundPoint( aiBrain, categories.ANTIAIR * categories.DEFENSE, cdr.CDRHome, 80, 'Ally' )
        local nmaDF = GetNumUnitsAroundPoint( aiBrain, categories.DIRECTFIRE, cdr.CDRHome, 80, 'Ally' )
		
		local runShield = false
		local runSpot = false

		if nmaShield > 0 then
		
			category = categories.SHIELD
			runShield = true
			
		elseif nmaAA > 0 then
		
			category = categories.DEFENSE * categories.ANTIAIR
			
		elseif nmaDF > 0 then
        
     		category = categories.DIRECTFIRE
        end
	
		if category then
	
            local id = cdr:GetEntityId()
		
            FloatingEntityText(id,'Inspection Tour...')
		
            local plat = MakePlatoon( aiBrain, 'CDRWander', 'none' )
		
            plat.BuilderName = 'CDRWander'
		
            AssignUnitsToPlatoon( aiBrain, plat, {cdr}, 'Support', 'None' )
		
            IssueClearCommands( {cdr} )		
		
			runSpot = import('/lua/ai/altaiutilities.lua').AIFindDefensiveAreaSorian( aiBrain, cdr, category, 100, runShield )
			
			IssueClearCommands( {cdr} )
			IssueMove( {cdr}, runSpot )

            WaitTicks(75)
		
            plat:SetAIPlan('ReturnToBaseAI',aiBrain)		
        end
	end

    cdr.Fighting = false
end

-- for enhancements (not upgrades) on the COMMANDER
function CDREnhance( self, aiBrain )

    local units = GetPlatoonUnits(self)
	
	local finalenhancement = self.PlatoonData.Enhancement[LOUDGETN(self.PlatoonData.Enhancement)]
	
	local unit

    for _,v in units do
	
		if not v.Dead and LOUDENTITY(categories.COMMAND, v) then
		
			unit = v
			
			if unit:HasEnhancement(finalenhancement) then
			
				local EM = aiBrain.BuilderManagers[unit.LocationType].EngineerManager
				
				AssignUnitsToPlatoon( aiBrain, 'ArmyPool', {unit}, 'Support', 'None' )
				
				ForkThread( EM.AssignEngineerTask, EM, unit, aiBrain )
				
				break
			end
		end
	end
	
	if unit then
	
		IssueStop({unit})
		IssueClearCommands({unit})
		
		local IsIdleState = IsIdleState
		local IsUnitState = IsUnitState
		
		for _,v in self.PlatoonData.Enhancement do
		
			if not unit.Dead and not unit:HasEnhancement(v) then
			
				if not unit:HasEnhancement(v) then
				
					repeat
					
						WaitTicks(10)
						
					until IsIdleState(unit) or unit.Dead
					
					if not unit.Dead then
						IssueScript( {unit}, {TaskName = "EnhanceTask", Enhancement = v} )
					end
				end
				
				local stallcount = 0
				
				if ScenarioInfo.ACUEnhanceDialog then
					LOG("*AI DEBUG "..aiBrain.Nickname.." CDREnhance waiting to start "..repr(v) )
				end
				
				repeat
				
					WaitTicks(10)

					stallcount = stallcount + 1
					
				until unit.Dead or IsUnitState(unit,'Enhancing') or stallcount > 10

				if IsUnitState(unit,'Enhancing') then
				
					if ScenarioInfo.ACUEnhanceDialog then
						LOG("*AI DEBUG "..aiBrain.Nickname.." CDREnhance enhancing for "..repr(v) )
					end
				
					repeat
				
						WaitTicks(75)
					
					until not IsUnitState(unit,'Enhancing') or unit.Dead 
				end
				
				break
			else
			
                WaitTicks(5)
            end
		end
	end
	
	if unit and unit:HasEnhancement(finalenhancement) and self.PlatoonData.ClearTaskOnComplete then
	
		local manager = 'PlatoonFormManager'
		
		if self.BuilderManager == 'EM' then
			manager = 'EngineerManager'
		end
		
		if self.BuilderManager == 'FBM' then
			manager = 'FactoryManager'
		end
		
		local buildertable = aiBrain.BuilderManagers[self.BuilderLocation][manager]['BuilderData'][self.BuilderType]
		
		for a,b in buildertable['Builders'] do
		
			if b.BuilderName == self.BuilderName then
				b:SetPriority(0,false)
				break
			end
		end
	end
	
	return self:SetAIPlan('ReturnToBaseAI',aiBrain)
end

 
function AirScoutingAI( self, aiBrain )

	local GetNumUnitsAroundPoint = GetNumUnitsAroundPoint
    local GetPlatoonPosition = GetPlatoonPosition
    local GetPlatoonUnits = GetPlatoonUnits    
	local GetSquadUnits = GetSquadUnits
	local GetThreatsAroundPosition = GetThreatsAroundPosition
	local GetUnitsAroundPoint = GetUnitsAroundPoint    
    
    local LOUDCOPY = LOUDCOPY
    local LOUDEQUAL = LOUDEQUAL
    local LOUDPOW = LOUDPOW
    local LOUDREMOVE = LOUDREMOVE
    
    local Random = Random
    
 	local PlatoonExists = PlatoonExists	

    local VDist2Sq = VDist2Sq
	local VDist3 = VDist3
    
    local UNITCHECK = categories.ALLUNITS - categories.WALL
    local OMNICHECK = categories.STRUCTURE * categories.INTELLIGENCE * categories.OMNI
    
    local MustScoutList = aiBrain.IL.MustScout
    
    self.UsingTransport = true      -- airscouting is never considered for merge operations

	local function AIGetMustScoutArea()
	
		for k,v in MustScoutList do
		
			if not v.TaggedBy or v.TaggedBy.Dead then
				return v, k
			end
            
		end

		return false, nil
	end
	
	local function IsCurrentlyScouted (location)

        if GetNumUnitsAroundPoint( aiBrain, UNITCHECK, location, 45, 'Ally') > 0 or
			-- or an allied OMNI radar within 150
			GetNumUnitsAroundPoint( aiBrain, OMNICHECK, location, 150, 'Ally') > 0 then

			return true
		end
		
		return false
	end	

	-- establish the relative co-ordinates between where the platoon is and where it's going
	-- get the distance to the destination	-- normalize the trip distance	-- Get negative reciprocal vector (either 1 or -1)
	-- establish the relative position the scout must get to to 'see' the target -- flying to the left or right of the target (this is where dir comes in)
	-- calc the final destination by applying the orthogonal to the targetposition

	-- scout platoon uses an inflated threatlevel to assist in pathfinding
	-- find a path using threatlevel to avoid anti-air threats
	-- should that not work scouts will report false and pass on trying to scout this area
	local function DoAirScoutVecs( scout, targetposition )
	
		local scoutposition = LOUDCOPY(GetPosition(scout))
		
		if scoutposition then
		
			local vec = {targetposition[1] - scoutposition[1], 0, targetposition[3] - scoutposition[3]}
            
			local length = VDist3( targetposition, scoutposition )
			local norm = {vec[1]/length, 0, vec[3]/length}
			local dir = LOUDPOW(-1, Random(1,2))
			
			local visRad = __blueprints[scout.BlueprintID].Intel.VisionRadius or 42

			local orthogonal = { norm[3] * visRad * dir, 0, -norm[1] * visRad * dir }

			local dest = {targetposition[1] + orthogonal[1], 0, targetposition[3] + orthogonal[3]}
		
			if dest[1] < 5 then
				dest[1] = 5 
			elseif dest[1] > ScenarioInfo.size[1]-5 then
				dest[1] = ScenarioInfo.size[1]-5
			end
		
			if dest[3] < 5 then
				dest[3] = 5 
			elseif dest[3] > ScenarioInfo.size[2]-5 then
				dest[3] = ScenarioInfo.size[2]-5
			end
		
			-- use an elevated threat level in order to find paths for the air scouts --
			local threatlevel = 24 + ( LOUDGETN(GetPlatoonUnits(self) )) * LOUDGETN( GetPlatoonUnits(self))
		
			local path, reason = self.PlatoonGenerateSafePathToLOUD(aiBrain, self, 'Air', scoutposition, dest, threatlevel, 256)
		
			if path then
		
				local units = GetSquadUnits( self,'scout')
		
				-- plot the movements of the platoon --
				if PlatoonExists(aiBrain, self) and units[1] then
		
					self:Stop()

					for widx,waypointPath in path do
                        IssueMove( units, waypointPath )
					end

					return dest
				end
			end
		end

		return false
	end		

	local scout = false
	local noscoutcount = 0
	
	local targetArea, vec, mustScoutArea, mustScoutIndex

	-- this basically limits all air scout platoons to about 20 minutes of work -- rather should use MISSIONTIMER from platoondata
    while PlatoonExists(aiBrain, self) and (LOUDTIME() - self.CreationTime <= 1200) do

		for _,v in GetPlatoonUnits(self) do
			if not v.Dead then
				scout = v
				break
			end
		end

        if not scout then
            return
        end

        targetArea = false
		vec = false

		-- see if we already have a MUSTSCOUT mission underway
		if not aiBrain.IL.LastAirScoutMust then
			
			local unknownThreats = GetThreatsAroundPosition( aiBrain, GetPosition(scout), 2, true, 'Unknown')
			
			-- add all unknown threats over 25 to the MUSTSCOUT list
			if unknownThreats[1] then
				
				for k,v in unknownThreats do
				
					if unknownThreats[k][3] > 25 then
					
						ForkThread( AIAddMustScoutArea, aiBrain, {unknownThreats[k][1], 0, unknownThreats[k][2]} )
					end
				end
			end
			
			mustScoutArea, mustScoutIndex = AIGetMustScoutArea()
            
            if mustScoutArea and not LOUDEQUAL( aiBrain.IL.LastMustScoutPosition or {0,0,0}, mustScoutArea.Position) then

                -- if there is a mustscoutarea then scout it
                if mustScoutArea and (not aiBrain.IL.LastAirScoutMust) then

                    vec = DoAirScoutVecs( scout, mustScoutArea.Position )

                    -- if there is a path to target --
                    if vec then
				
                        if aiBrain.IL.MustScout[mustScoutIndex] then
                            aiBrain.IL.MustScout[mustScoutIndex].TaggedBy = scout
                        end
					
                        targetArea = LOUDCOPY(vec)
					
                        aiBrain.IL.LastAirScoutMust = true	-- flag that we have a MUSTSCOUT mission in progress
                        -- remember where this was so we don't repeat it again too soon
                        aiBrain.IL.LastMustScoutPosition = LOUDCOPY(mustScoutArea.Position)
                    end
				end
			end
		end

        -- 2) Scout a high priority location
        if (not targetArea) and (not aiBrain.IL.LastAirScoutHi) then
		
			local prioritylist = aiBrain.IL.HiPri
			
			for k,v in prioritylist do

                if IsCurrentlyScouted( v.Position) then
				
					if aiBrain.IL.HiPri[k] then
						aiBrain.IL.HiPri[k].LastScouted = LOUDTIME()
                        aiBrain.IL.HiPri[k].LastUpdated = LOUDTIME()
					end
					
                    continue
                end

				vec = DoAirScoutVecs( scout, v.Position )

                -- if there is a path to target --
				if vec then
				
					aiBrain.IL.LastAirScoutHi = true
					
					if aiBrain.IL.HiPri[k] then
                        --LOG("*AI DEBUG "..aiBrain.Nickname.." takes HiPri Airscout")
						aiBrain.IL.HiPri[k].LastScouted = LOUDTIME()
					end
					
					ForkThread( AISortScoutingAreas, aiBrain, aiBrain.IL.HiPri )
					
					targetArea = LOUDCOPY(vec)
					break
				end
			end
		end

        -- 3) Scout a low priority location               
        if not targetArea then
			
			aiBrain.IL.LastAirScoutMust = false -- last scout mission was NOT a MUST

			aiBrain.IL.LastAirScoutHiCount = aiBrain.IL.LastAirScoutHiCount + 1

			if aiBrain.IL.LastAirScoutHiCount > aiBrain.AILowHiScoutRatio then
				aiBrain.IL.LastAirScoutHi = false
				aiBrain.IL.LastAirScoutHiCount = 0
			end

			for k,v in aiBrain.IL.LowPri do

                if IsCurrentlyScouted( v.Position ) then
                    aiBrain.IL.LowPri[k].LastScouted = LOUDTIME()
                    aiBrain.IL.LowPri[k].LastUpdated = LOUDTIME()
                    continue
                end

				vec = DoAirScoutVecs( scout, v.Position )

                -- if there is a path to target --
				if vec then
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." takes LowPri Airscout")
					aiBrain.IL.LowPri[k].LastScouted = LOUDTIME()

					targetArea = LOUDCOPY(vec)
					break
				else
					noscoutcount = noscoutcount + 1
				end
			end
        end

        -- Execute the scouting mission
        -- as we move along we'll try and tag any other HiPri positions
        -- that we might pass along the way.
        if targetArea then

			local reconcomplete = false
			local lastpos = false
			local curPos = false

            while PlatoonExists(aiBrain,self) and not reconcomplete do

				curPos = GetPlatoonPosition(self) or false

				if curPos then
				
					-- if within 40 of the recon position 
					if VDist2Sq( targetArea[1],targetArea[3], curPos[1],curPos[3] ) < (40*40) then
						reconcomplete = true
					end

					-- or not moving
					if not reconcomplete and lastpos and VDist2Sq( curPos[1],curPos[3], lastpos[1],lastpos[3] ) < 2 then
						reconcomplete = true
					end

                    -- store current position
					lastpos = LOUDCOPY(curPos)

                    -- if we're near another HiPri position - mark it --
                    -- this probably needs to be throttled or interleaved
                    -- so as not to stress on a single tick
                    for k,v in aiBrain.IL.HiPri do
                    
                        if VDist2Sq( curPos[1],curPos[3], v.Position[1],v.Position[3] ) < (40*40) then
                        
                            aiBrain.IL.HiPri[k].LastScouted = LOUDTIME()
                            aiBrain.IL.HiPri[k].LastUpdated = LOUDTIME()
                        end
                    end
                    
                    local loopcount = 0
                    local cyclecount = 0
                    
                    for k,v in aiBrain.IL.LowPri do
                    
                        if loopcount > 20 then
                            WaitTicks(1)
                            loopcount = 1
                            cyclecount = cyclecount + 1
                        else
                            loopcount = loopcount + 1
                        end
                    
                        if VDist2Sq( curPos[1],curPos[3], v.Position[1],v.Position[3] ) < (40*40) then
                        
                            aiBrain.IL.LowPri[k].LastScouted = LOUDTIME()
                            aiBrain.IL.LowPri[k].LastUpdated = LOUDTIME()
                        end
                    end
                    
                    if not reconcomplete then
                    
                        if cyclecount < 12 then
                            WaitTicks(12 - cyclecount)
                        end
                    end
				end                    
            end

			-- if it was a MUSTSCOUT mission, take it off the list
            if mustScoutArea then

				if aiBrain.IL.MustScout[mustScoutIndex] == mustScoutArea then

					LOUDREMOVE( aiBrain.IL.MustScout, mustScoutIndex )
				else
					for idx,loc in aiBrain.IL.MustScout do
					
						if loc == mustScoutArea then
						
							LOUDREMOVE( aiBrain.IL.MustScout, idx )
							break
						end
					end
				end

				mustScoutArea = false
			end
        else
			noscoutcount = noscoutcount + 1

			if noscoutcount > 2 then
				LOG("*AI DEBUG NoScoutCount break")
				break
			end

			WaitTicks(3)			
		end
    end

	return self:SetAIPlan('ReturnToBaseAI',aiBrain)
end

function LandScoutingAI( self, aiBrain )

	local GetUnitsAroundPoint = GetUnitsAroundPoint
	local GetNumUnitsAroundPoint = GetNumUnitsAroundPoint
    
    local GetTerrainHeight = GetTerrainHeight
    local GetSurfaceHeight = GetSurfaceHeight
    
	local PlatoonExists = PlatoonExists	
    local GetPlatoonPosition = GetPlatoonPosition
    local GetPlatoonUnits = GetPlatoonUnits    
    
    local VDist3 = VDist3
    
    local LOUDCOPY = LOUDCOPY

	local curPos = nil
	local usedTransports = false
	
	local scout = false

	local PlatoonPatrols = self.PlatoonData.Patrol or false
	
    local units = GetPlatoonUnits(self)
	
	for _,v in units do
	
		if not v.Dead and v:TestToggleCaps('RULEUTC_CloakToggle') then
		
			v:SetScriptBit('RULEUTC_CloakToggle', false)
		end
    end

	local function IsCurrentlyScouted (location)

        if GetNumUnitsAroundPoint( aiBrain, categories.ALLUNITS - categories.WALL, location, 40, 'Ally') > 0 or
			-- or an OMNI radar within 150
			GetNumUnitsAroundPoint( aiBrain, categories.STRUCTURE * categories.INTELLIGENCE * categories.OMNI, location, 150, 'Ally') > 0 then

			return true
			
		end
		
		return false
	end

	local targetArea, reconcomplete
	local terrain, surface
	local distance, path, reason, lastpos		

    while PlatoonExists(aiBrain, self) do

		scout = false
		
		units = GetPlatoonUnits(self)
		
		for _,v in units do
		
			if not v.Dead then
				scout = v
				break
			end
		end
		
		if not scout then
			break
		end
		
        targetArea = false
		reconcomplete = false

        if not aiBrain.IL.LastScoutHi and aiBrain.IL.HiPri then
		
			local prioritylist = aiBrain.IL.HiPri

			for k,v in prioritylist do

                -- if we (or an Ally) have a unit near the position mark it as scouted and bypass it
                if IsCurrentlyScouted(v.Position) then
				
                    aiBrain.IL.HiPri[k].LastScouted = LOUDTIME()
                    aiBrain.IL.HiPri[k].LastUpdated = LOUDTIME()
                    continue
                end

				terrain = GetTerrainHeight(v.Position[1], v.Position[3])
				surface = GetSurfaceHeight(v.Position[1], v.Position[3])
				
				-- validate positions for being on the water
				if terrain < surface - 2 and self.MovementLayer != 'Amphibious' then 
				
					targetArea = false
				else
					aiBrain.IL.HiPri[k].LastScouted = LOUDTIME()
                 
					aiBrain.IL.LastScoutHi = true
					
					ForkThread( AISortScoutingAreas, aiBrain, aiBrain.IL.HiPri )
   					targetArea = LOUDCOPY(v.Position)
					break
				end
			end
		end

		if not targetArea then
		
			aiBrain.IL.LastScoutHiCount = aiBrain.IL.LastScoutHiCount + 1
			
			if aiBrain.IL.LastScoutHiCount > aiBrain.AILowHiScoutRatio then
			
				aiBrain.IL.LastScoutHi = false
				aiBrain.IL.LastScoutHiCount = 0
			end
			
			local prioritylist = aiBrain.IL.LowPri

			for k,v in prioritylist do

                -- if we (or an Ally) have a unit within 40 of the position mark it as scouted and bypass it
                if IsCurrentlyScouted(v.Position) then
				
                    aiBrain.IL.LowPri[k].LastScouted = LOUDTIME()
                    continue
                end

				terrain = GetTerrainHeight(v.Position[1], v.Position[3])
				surface = GetSurfaceHeight(v.Position[1], v.Position[3])

				-- validate positions for being on water
				if terrain < surface - 1 and self.MovementLayer != 'Amphibious' then
					targetArea = false
				else
					targetArea = LOUDCOPY(v.Position)

					aiBrain.IL.LowPri[k].LastScouted = LOUDTIME()
                    aiBrain.IL.LowPri[k].LastUpdated = LOUDTIME()
					
					ForkThread( AISortScoutingAreas, aiBrain, aiBrain.IL.LowPri )					
					break
				end
			end
        end

		-- Generate a path and use transport if required
		-- If no transport available - run local patrol  for 2 minutes - then retry
        if PlatoonExists(aiBrain,self) and targetArea then
            
			usedTransports = false

			-- with Land Scouting we use an artificial high self-threat (75) so they'll continue scouting later into the game
			path, reason = self.PlatoonGenerateSafePathToLOUD(aiBrain, self, self.MovementLayer, GetPlatoonPosition(self), targetArea, 75, 160 )

			if not path and PlatoonExists(aiBrain,self) then

				distance = VDist3( GetPlatoonPosition(self), targetArea )

				-- try 6 transport calls -- 
				usedTransports = self:SendPlatoonWithTransportsLOUD( aiBrain, targetArea, 6, false )
				
				-- if no path & no transport turn reconcomplete on so that squad will just patrol
				-- where they are for two minutes before trying for another scouting location
				
				-- unfortunately, for now, I have to say that the recon was complete or otherwise
				-- we'll soon have a bunch of land scouts all doing the same thing at the same place
				if distance > 300 and not usedTransports and PlatoonExists(aiBrain, self) then
				
					reconcomplete = true
					targetArea = false
				end
			end
			
			if path and targetArea and PlatoonExists(aiBrain,self) then

				distance = VDist3( GetPlatoonPosition(self), targetArea )

				-- if the distance is great try to get transports
				if distance > 1024 then
				
					-- try 2 transport calls --
					usedTransports = self:SendPlatoonWithTransportsLOUD( aiBrain, targetArea, 2, false )
				end

				-- otherwise start walking -- 
				if path and (distance <= 1024 or (distance > 1024 and not usedTransports) ) and PlatoonExists(aiBrain,self) then
					
					local pathLength = LOUDGETN(path)
					
					if pathLength > 1 then

						for v = 1, pathLength-1 do
							self:MoveToLocation( path[v], false )
						end
					end

					self:MoveToLocation(targetArea,false) 
				end
			end

			-- loop here while we travel to the target
			lastpos = false
            
            -- use this to monitor time used by
            -- other priority location checking
            local cyclecount = 0
			
            while PlatoonExists(aiBrain,self) and targetArea and not reconcomplete do
			
				curPos = GetPlatoonPosition(self) or false
				
				if curPos then
                
                    cyclecount = 0

					if VDist2Sq(targetArea[1],targetArea[3],curPos[1],curPos[3] ) < 400 then
                        --LOG("*AI DEBUG "..aiBrain.Nickname.." LandScoutingAI distance to "..repr(targetArea).." is "..repr(VDist2Sq(targetArea[1],targetArea[3],curPos[1],curPos[3] )) )
						reconcomplete = true
					end
                    
					if not reconcomplete and lastpos and VDist3(curPos,lastpos) < 1 then
						reconcomplete = true
					end
					
					lastpos = curPos
                    
                    local loopcount = 0

                    -- if we're near another HiPri position - mark it --
                    -- this probably needs to be throttled or interleaved
                    -- so as not to stress on a single tick
                    for k,v in aiBrain.IL.HiPri do
                    
                        if VDist2Sq( curPos[1],curPos[3], v.Position[1],v.Position[3] ) < (20*20) then
                        
                            aiBrain.IL.HiPri[k].LastScouted = LOUDTIME()
                            aiBrain.IL.HiPri[k].LastUpdated = LOUDTIME()
                        end
                    end
                    
                    for k,v in aiBrain.IL.LowPri do
                    
                        if loopcount > 10 then
                            WaitTicks(1)
                            loopcount = 1
                            cyclecount = cyclecount + 1
                        else
                            loopcount = loopcount + 1
                        end
                    
                        if VDist2Sq( curPos[1],curPos[3], v.Position[1],v.Position[3] ) < (20*20) then
                        
                            aiBrain.IL.LowPri[k].LastScouted = LOUDTIME()
                            aiBrain.IL.LowPri[k].LastUpdated = LOUDTIME()
                        end
                    end                    
				end
                
                if not reconcomplete and cyclecount < 24 then
                    WaitTicks(24 - cyclecount)
                end
            end	

			-- setup the patrol and abandon the platoon
			if PlatoonExists(aiBrain, self) and not scout.Dead then
				
				if not targetArea then
					targetArea = GetPlatoonPosition(self)
				end

				for _,v in GetPlatoonUnits(self) do
					IssueClearCommands( {v} )
				end

				if PlatoonPatrols then
                
                    local baseradius = 28
                
                    for _,scout in GetPlatoonUnits(self) do
                    
                        if not scout.Dead then
					
                            local loclist = GetBasePerimeterPoints( aiBrain, targetArea, baseradius, false, false, 'Land', true )
					
                            for k,v in loclist do

                                if (not scout.Dead) and scout:CanPathTo( v ) then
								
                                    if not self.MovementLayer == 'Amphibious' then
							
                                        v[2] = GetSurfaceHeight(v[1], v[3])
									
                                        if GetTerrainHeight(v[1], v[3]) < (v[2] - 1) then
                                            continue
                                        end
                                    end
					
                                    if k == 1 then
                                    
                                        IssueMove( {scout}, v )
                                    else

                                        IssuePatrol( {scout}, v )
                                    end
                                end

                                WaitTicks(2)
                            end

                            baseradius = baseradius + 8
                        end
                    end
				end
				
				-- here is where you could use a variable time or alternatively
				-- just abandon the scout platoon and leave him patrolling until
				-- death -- which is what I will now do - land scouts are dirt cheap
				
				-- assign them to the structure pool so they dont interfere with normal unit pools
				if PlatoonExists(aiBrain,self) then
				
					for _,v in GetPlatoonUnits(self) do
				
						if not v.Dead then
							AssignUnitsToPlatoon( aiBrain, aiBrain.StructurePool, v, 'Guard', 'none' )
						end
					end
				end
				
				return self:PlatoonDisband(aiBrain)
			end
        end
		
		WaitTicks(30)
    end
    
end

function NavalScoutingAI( self, aiBrain )

	local GetUnitsAroundPoint = GetUnitsAroundPoint
	local GetNumUnitsAroundPoint = GetNumUnitsAroundPoint
    
    local GetPlatoonPosition = GetPlatoonPosition
    local GetPlatoonUnits = GetPlatoonUnits
    
    local GetTerrainHeight = GetTerrainHeight
    local GetSurfaceHeight = GetSurfaceHeight
    
	local PlatoonExists = PlatoonExists	
    
    local LOUDCOPY = LOUDCOPY
    
    local VDist2Sq = VDist2Sq
    local VDist3 = VDist3

	local curPos = nil
	local scout = nil
    
    local units = GetPlatoonUnits(self)
    
    local UNITCHECK = categories.ALLUNITS - categories.WALL
    local OMNICHECK = categories.STRUCTURE * categories.INTELLIGENCE * categories.OMNI
    local SONARCHECK = categories.STRUCTURE * categories.SONAR

	local function IsCurrentlyScouted (location)

        if GetNumUnitsAroundPoint( aiBrain, UNITCHECK, location, 50, 'Ally') > 0 or
            -- or a SONAR within 90
            GetNumUnitsAroundPoint( aiBrain, SONARCHECK, location, 90, 'Ally') > 0 or
			-- or an OMNI radar within 150
			GetNumUnitsAroundPoint( aiBrain, OMNICHECK, location, 150, 'Ally') > 0 then

			return true
		end
		
		return false
	end	

	local targetArea, reconcomplete
	local count, terrain, surface
	local distance, path, reason, lastpos

	-- naval scouting is limited to about 20 minutes --
    while PlatoonExists(aiBrain, self) and (LOUDTIME() - self.CreationTime <= 1200) do
		
		for _,v in units do
		
			if not v.Dead then
			
				scout = v
				break
			end
		end
		
        targetArea = false

		reconcomplete = false
		
		-- if the last scout mission was NOT a HiPri then look for one
        if not aiBrain.IL.LastScoutHi then
		
			local prioritylist = aiBrain.IL.HiPri
            
            --LOG("*AI DEBUG "..aiBrain.Nickname.." priority list is "..repr(prioritylist))

			for k,v in prioritylist do

                -- if we (or an Ally) have a unit within 30 of the position mark it as scouted and bypass it
                if IsCurrentlyScouted(v.Position) then
				
                    aiBrain.IL.HiPri[k].LastScouted = LOUDTIME()
					continue
                end

				targetArea = LOUDCOPY(v.Position)

				terrain = GetTerrainHeight(targetArea[1], targetArea[3])
				surface = GetSurfaceHeight(targetArea[1], targetArea[3])

				-- validate positions for being out of the water
				if terrain >= surface - 2 and self.MovementLayer != 'Amphibious' then
				
					targetArea = false
				else
					aiBrain.IL.LastScoutHi = true
					aiBrain.IL.HiPri[k].LastScouted = LOUDTIME()
					
					ForkThread( AISortScoutingAreas, aiBrain, aiBrain.IL.HiPri )
					break
				end
			end
		end

		-- if we dont have a HiPri scout, try LowPri
		if not targetArea then
			
			aiBrain.IL.LastScoutHiCount = aiBrain.IL.LastScoutHiCount + 1

			if aiBrain.IL.LastScoutHiCount > aiBrain.AILowHiScoutRatio then
			
				aiBrain.IL.LastScoutHi = false
				aiBrain.IL.LastScoutHiCount = 0
			end
			
			local prioritylist = aiBrain.IL.LowPri

			for k,v in prioritylist do

                if IsCurrentlyScouted(v.Position) then
				
                    aiBrain.IL.LowPri[k].LastScouted = LOUDTIME()
                    continue
                end	

				targetArea = LOUDCOPY(v.Position)

				terrain = GetTerrainHeight(targetArea[1], targetArea[3])
				surface = GetSurfaceHeight(targetArea[1], targetArea[3])

				-- validate positions for being out of the water
				if terrain >= surface - 2 and self.MovementLayer != 'Amphibious' then
				
					targetArea = false
				else
				
					aiBrain.IL.LowPri[k].LastScouted = LOUDTIME()
					
					ForkThread( AISortScoutingAreas, aiBrain, aiBrain.IL.LowPri )
					break
				end
			end
        end

		-- execute the scouting mission
        if PlatoonExists(aiBrain,self) and targetArea then
        
            -- Find a path to targetArea --
			distance = VDist3(GetPlatoonPosition(self), targetArea)

			-- like Land Scouting we use an artificially higher threat of 100 to insure path finding
			path, reason = self.PlatoonGenerateSafePathToLOUD(aiBrain, self, self.MovementLayer, GetPlatoonPosition(self), targetArea, 100, 250 )
			
			if PlatoonExists( aiBrain, self ) then

				if (not path) and (not scout.Dead) then
				
					if distance <= 120 and scout:CanPathTo(targetArea) then
                    
                        LOG("*AI DEBUG "..aiBrain.Nickname.." Naval Scout has no path but distance is "..repr(distance).." - moving direct to "..repr(targetArea))
                        
						self:MoveToLocation(targetArea, false)
					else
						targetArea = false
					end
				end
			
				if path and targetArea then
                    -- this call takes advantage of the pathslack option so that naval scouting platoons will change to their next
                    -- waypoint at a distance of 20 rather than the default value of 16
					self.MoveThread = self:ForkThread( self.MovePlatoon, path, 'GrowthFormation', false, 20 )
				end
			end
            
            -- a delay to allow some movement to occur --
            if self.MoveThread then
                WaitTicks(51)
            end

            -- Travel to the targetArea --
			lastpos = false
            
            -- this takes into account the time we spent
            -- processing nearby scout positions --
            local cyclecount = 0

            while PlatoonExists(aiBrain,self) and targetArea and not reconcomplete do
				
				curPos = GetPlatoonPosition(self) or false
				
				if curPos then
                
                    -- reset the cyclecount --
                    cyclecount = 0

					if VDist2( targetArea[1],targetArea[3], curPos[1],curPos[3] ) < 35 then
						
						reconcomplete = true
                        
					else
                    
						if lastpos and VDist2(curPos[1],curPos[3], lastpos[1],lastpos[3]) < 0.1 then
                        
                            --LOG("*AI DEBUG "..aiBrain.Nickname.." Naval Scouting AI says we havent moved - recon complete at "..repr(curPos).." lastpos is "..repr(lastpos))
							reconcomplete = true
						end

						lastpos = curPos
					end
                    
                    local loopcount = 0

                    -- if we're near another HiPri position - mark it --
                    -- this probably needs to be throttled or interleaved
                    -- so as not to stress on a single tick
                    for k,v in aiBrain.IL.HiPri do
                    
                        if VDist2Sq( curPos[1],curPos[3], v.Position[1],v.Position[3] ) < (35*35) then
                        
                            aiBrain.IL.HiPri[k].LastScouted = LOUDTIME()
                            aiBrain.IL.HiPri[k].LastUpdated = LOUDTIME()
                        end
                    end
                    
                    for k,v in aiBrain.IL.LowPri do
                    
                        if loopcount > 10 then
                            WaitTicks(1)
                            loopcount = 1
                            cyclecount = cyclecount + 1
                        else
                            loopcount = loopcount + 1
                        end
                    
                        if VDist2Sq( curPos[1],curPos[3], v.Position[1],v.Position[3] ) < (35*35) then
                        
                            aiBrain.IL.LowPri[k].LastScouted = LOUDTIME()
                            aiBrain.IL.LowPri[k].LastUpdated = LOUDTIME()
                        end
                    end
				end
                
                if not reconcomplete and cyclecount < 25 then
                    WaitTicks(25 - cyclecount)
                end
            end	

            ------------------------------
            -- Arrive at the targetArea --
            ------------------------------
			-- Run a patrol here for 3 minutes
			-- Note how the targetArea is set to the platoon position if empty
			-- This allows scouts that fail in getting to the desired area
			-- to patrol their existing location before trying for another
			if PlatoonExists(aiBrain, self) and not scout.Dead then

				if not targetArea then
					targetArea = GetPlatoonPosition(self) or false
				end

				for _,v in GetPlatoonUnits(self) do
					IssueClearCommands( {v} )
				end
                
                if self.MoveThread then
                    KillThread( self.MoveThread )
                end

                -- get the perimeter points around this position - range 42
				local loclist = GetBasePerimeterPoints(aiBrain, targetArea, 42, false, false,'Water')
				
				-- set up a patrol around the position
				for k,v in loclist do

					if not scout.Dead then
						
						if scout:CanPathTo( v ) then
						
							if self.MovementLayer == 'Water' then
						
								v[2] = GetSurfaceHeight(v[1], v[3])

								if GetTerrainHeight(v[1], v[3]) >= (v[2] - 1) then
									continue
								end
							end
					
							if k == 1 then
								self:MoveToLocation(v, false)
							else
								units = GetPlatoonUnits(self)

								if units[1] and v then
									IssuePatrol( units, v )
								end
							end
						end
					end
                end

				-- we could introduce variable patrol times with a PlatoonData variable
				WaitSeconds(180)

				IssueClearCommands(GetPlatoonUnits(self))
			end
            
        end

        -- if we didn't find a recon mission wait 5.5 seconds before trying again
        -- otherwise go right back and find another mission
        if PlatoonExists(aiBrain,self) and not reconcomplete then
        
            LOG("*AI DEBUG "..aiBrain.Nickname.." NavalScoutingAI finds no recon mission")
            WaitTicks(56)
        end
        
    end

	return self:SetAIPlan('ReturnToBaseAI',aiBrain)
end

-- this behavior will watch the platoon's overall health and size
-- and RTB it (after checking for a merge) when it falls too low
function RetreatAI( self, aiBrain )

    WaitTicks(50)  -- Wait 5 seconds before beginning
    
    local GetPlatoonUnits = GetPlatoonUnits    
	local PlatoonExists = PlatoonExists	

    if not PlatoonExists( aiBrain, self ) then
        return
    end
    
    local CalculatePlatoonThreat = CalculatePlatoonThreat
    local WaitTicks = WaitTicks

    local OriginalStrength = CalculatePlatoonThreat( self, 'Overall', categories.ALLUNITS)
    
    local OriginalSize = 0
    local CurrentSize = 0
    
    local function CountPlatoonUnits()
    
        CurrentSize = 0
    
        for _, u in GetPlatoonUnits(self) do
    
            if not u.Dead then
                CurrentSize = CurrentSize + 1
            end
        end
        
        return CurrentSize
    end
    
    OriginalSize = CountPlatoonUnits()
    
    OriginalPlan = self.PlanName

    while PlatoonExists( aiBrain, self) do
    
        if self.UnderAttack then
    
            if (OriginalStrength * .4) >= CalculatePlatoonThreat( self, 'Overall', categories.ALLUNITS) or (OriginalSize * .4) >= CountPlatoonUnits() then

                if PlatoonExists( aiBrain, self) then

                    self:Stop()
                
                    self:MergeIntoNearbyPlatoons( aiBrain, OriginalPlan, 100, false)
                
                    if PlatoonExists( aiBrain, self) then

                        -- RTB any leftovers
                        return self:SetAIPlan('ReturnToBaseAI',aiBrain)
                    end
                else
                    break
                end
            end
            
            WaitTicks(3)
        end
        
        WaitTicks(2)
    end

end

-- This function borrows some good code from Sorian for timed launches
-- Launchers are added to the platoon thru the NukeAIHub
-- When there are missiles to fire, a target is selected and an appropriate
-- number of nukes are fired at the target, based upon intel of anti-nuke systems
-- both near and intervening to the target
function NukeAI( self, aiBrain )

	local AIFindNumberOfUnitsBetweenPoints = import('/lua/ai/aiattackutilities.lua').AIFindNumberOfUnitsBetweenPoints
	local AISendChat = import('/lua/ai/sorianutilities.lua').AISendChat
	local GetHiPriTargetList = import('/lua/ai/altaiutilities.lua').GetHiPriTargetList
	local GetUnitsAroundPoint = GetUnitsAroundPoint
	local UnitLeadTarget = import('/lua/ai/sorianutilities.lua').UnitLeadTarget
	
    local aiBrain = GetBrain(self)
    
    local LOUDEQUAL = table.equal
	local LOUDGETN = LOUDGETN
    
    local GetPlatoonUnits = GetPlatoonUnits    
	local PlatoonExists = PlatoonExists	
    
	local AvailableLaunches = {}
	local nukesavailable = 0
    local count = 0
	
	while PlatoonExists( aiBrain, self ) do
	
		AvailableLaunches = {}
        count = 0
        
		nukesavailable = 0
		
		-- make a list of available missiles
		for _, u in GetPlatoonUnits(self) do
		
			if not u.Dead then
			
				if u:GetNukeSiloAmmoCount() > 0 then
				
                    count = count + 1
                    AvailableLaunches[count] = u
					nukesavailable = nukesavailable + 1
					
					if  EntityCategoryContains( categories.xsb2401, u ) then
					
						nukesavailable = nukesavailable + 1
						
					end
					
				end
				
				-- insure that launcher is set to build missiles
				u:SetAutoMode(true)
			end
			
		end
		
		-- now we need to find a target
		while nukesavailable > 0 do
        
            if ScenarioInfo.NukeDialog then
                LOG("*AI DEBUG "..aiBrain.Nickname.." NukeAI searching for targets with "..LOUDGETN(GetPlatoonUnits(self)).." launchers and "..nukesavailable.." missiles")
            end
			
			local minimumvalue = 500
			
			local lasttarget = nil
			local lasttargettime = nil
			local target
			local nukePos = nil
			local targetunit = nil
			local targetvalue = minimumvalue
			local targetantis = 0
			
			local targetlist = GetHiPriTargetList(aiBrain, GetPlatoonPosition(self) )
			
			local allthreat, antinukes, value
			
			LOUDSORT(targetlist, function(a,b)  return a.Distance < b.Distance  end )

            if ScenarioInfo.NukeDialog then
                LOG("*AI DEBUG Nuke Targetlist is "..repr(targetlist))
            end
			
			-- evaluate the targetlist
			for _, target in targetlist do
			
				-- check threat levels (used to calculate value of target) - land/naval units worth 35% more - air worth only 50%
				allthreat = target.Threats.Eco + ((target.Threats.Sub + target.Threats.Sur) * 1.35) + (target.Threats.Air * 0.5)
				
                if ScenarioInfo.NukeDialog then
                    LOG("*AI DEBUG "..aiBrain.Nickname.." NukeAI says value of target at distance "..repr(LOUDSQUARE(target.Distance)).." is "..repr(allthreat).."  Needed value is "..repr(minimumvalue))
				end
                
				-- factor in distance to make near targets worth more
				-- LOG("*AI DEBUG "..aiBrain.Nickname.." NukeAI map size / distance calc is "..repr(aiBrain.dist_comp).." / "..repr(target.Distance))
				
				allthreat = allthreat * LOUDSQUARE(aiBrain.dist_comp/target.Distance)
                
                if ScenarioInfo.NukeDialog then				
                    LOG("*AI DEBUG "..aiBrain.Nickname.." NukeAI says value after distance adjust is "..repr(allthreat))
                end
				
				-- ignore it if less than minimumvalue
				if allthreat < minimumvalue then
					continue
				end
				
				-- get any anti-nuke systems in flightpath (-- one weakness here -- because launchers could be anywhere - we use platoon position which could be well off)
				antinukes = AIFindNumberOfUnitsBetweenPoints( aiBrain, GetPlatoonPosition(self), target.Position, categories.ANTIMISSILE * categories.SILO, 90, 'Enemy' )
				
				--antinukes = GetUnitsAroundPoint( aiBrain, categories.ANTIMISSILE * categories.SILO, target.Position, 90, 'Enemy')
				
                if ScenarioInfo.NukeDialog and antinukes > 0 then
					LOG("*AI DEBUG "..aiBrain.Nickname.." NukeAI says there are "..antinukes.." antinukes along path to this target")
				end

				-- if too many antinukes
				if antinukes >= nukesavailable then
					continue
				end

				-- the +0.75 is to insure the calculation is not divided by zero
				-- AND it makes a target with NO ANTIS a little more valuable
				antinukes = antinukes

				-- value of target is divided by number of anti-nukes in area
				value = ( allthreat/ LOUDMAX(antinukes,1) )

                if ScenarioInfo.NukeDialog then
                    LOG("*AI DEBUG NukeAI says there are "..repr(antinukes - 0.9).." AntiNukes within range of target")
                    LOG("*AI DEBUG "..aiBrain.Nickname.." NukeAI modified value is "..repr(value))
                end

				-- if this is a better target then store it
				if value > targetvalue then
					
					-- if its not the same as our last shot
					if not LOUDEQUAL(target.Position,lasttarget) then
					
                        if ScenarioInfo.NukeDialog then
                            LOG("*AI DEBUG "..aiBrain.Nickname.." NukeAI sees this as a NEW target -- New "..repr(target.Position).." Antis is "..(antinukes - 0.85).." Last Scouted "..repr(target.LastScouted))
                        end

						targetvalue = value
						targetantis = antinukes
						nukePos = target.Position

					-- if same as our last target and we've scouted it since then it's ok to fire again
					-- otherwise don't fire nukes at same target twice without scouting it
					elseif LOUDEQUAL(target.Position,lasttarget) and target.LastScouted > lasttargettime then
                    
                        if ScenarioInfo.NukeDialog then
                            LOG("*AI DEBUG "..aiBrain.Nickname.." NukeAI sees this as SAME target -- Old "..repr(lasttarget).."  New "..repr(target.Position).." Last Scouted "..repr(target.LastScouted))
                        end

						targetvalue = value
						targetantis = antinukes
						nukePos = target.Position
						
					end

					-- get an actual unit so we can plan for moving targets - do not target units that can fly -
					for _, u in GetUnitsAroundPoint( aiBrain, categories.ALLUNITS - (categories.AIR * categories.MOBILE), nukePos, 40, 'Enemy') do
						targetunit = u
						break
					end
					
		            if ScenarioInfo.NukeDialog and not targetunit then
						LOG("*AI DEBUG All values good but cannot find targetunit within 40 of "..repr(nukePos))
					end
				end
			end

			-- if we selected a target then lets see if we can fire some nukes at it
			if nukePos and targetunit then

				local launches = 0
				local launchers = {}
                local count = 0 

				-- collect all the launchers and their flighttime
				for _,u in AvailableLaunches do
					
					nukePos = UnitLeadTarget( u, targetunit )
					
					local launcherposition = GetPosition(u) or false
					
					if launcherposition and nukePos then

						-- approx flight time to target
                        count = count + 1
						launchers[count] = { unit = u, flighttime = math.sqrt( VDist2Sq( nukePos[1],nukePos[3], launcherposition[1],launcherposition[3] ) ) /40 }

						launches = launches + 1
						
						if EntityCategoryContains( categories.xsb2401, u ) then
						
							launches = launches + 1
							
						end
						
					end
					
				end

				-- if we have enough launches to overcome expected antinukes
				if launches > targetantis then
                
                    if ScenarioInfo.NukeDialog then
                        LOG("*AI DEBUG "..aiBrain.Nickname.." has "..launches.." missiles available for target with "..targetantis.." antinukes")
                    end
					
					-- store the target and time
					lasttarget = nukePos
					lasttargettime = LOUDTIME()

					-- if nuking same location randomize the target
					if LOUDEQUAL( nukePos, lasttarget ) then
						
						nukePos = { nukePos[1] + Random( -20, 20), nukePos[2], nukePos[3] + Random( -20, 20) }
						lasttarget = nukePos
						
					end						

					-- sort them by longest flighttime to shortest
					LOUDSORT( launchers, function(a,b) return a.flighttime > b.flighttime end )
					
					local lastflighttime = launchers[1].flighttime
					local firednukes = 0
                    
		            if ScenarioInfo.NukeDialog then
                        LOG("*AI DEBUG "..aiBrain.Nickname.." NukeAI says longest flighttime is "..repr( lastflighttime))
                    end

					-- fire them with appropriate delays and only as many as needed
					for _,u in launchers do
					
						if firednukes <= targetantis then

							if ( lastflighttime - u.flighttime ) > 0 then
							
								WaitSeconds( lastflighttime - u.flighttime )
								
							end

                            if ScenarioInfo.NukeDialog then
                                LOG("*AI DEBUG "..aiBrain.Nickname.." Firing Nuke "..(firednukes + 1).." after "..(lastflighttime - u.flighttime).." seconds - target is "..repr(nukePos))
							end
                            
							IssueNuke( {u.unit}, nukePos )
						
							lastflighttime = u.flighttime
							firednukes = firednukes + 1
							
							if EntityCategoryContains( categories.xsb2401, u) then
							
								firednukes = firednukes + 1
								
								nukesavailable = nukesavailable - 1
								
							end
							
							nukesavailable = nukesavailable - 1
							
						end
						
					end

					if firednukes > 0 then
					
						local aitarget = GetAIBrain(targetunit).ArmyIndex
					
						AISendChat('allies', ArmyBrains[aiBrain.ArmyIndex].Nickname, 'nukechat', ArmyBrains[aitarget].Nickname)

						-- send a scout for BDA
						ForkThread( AIAddMustScoutArea, aiBrain, nukePos)
						
					end
					
				end

			else
			
				if not targetunit then
					--LOG("*AI DEBUG "..aiBrain.Nickname.." NukeAI cant find a unit in the target area")
				end
				
				lasttarget = nil
				lasttargettime = nil
				
				--LOG("*AI DEBUG "..aiBrain.Nickname.." NukeAI finds no target to be used on")
				
				nukesavailable = 0
				
			end
			
		end

		WaitTicks(360)	-- every 36 seconds -- HMM -- this would best be synced right after the brain has completed a new HiPri list ? or would it ?
		
	end
	
end

function SetLoiterPosition( self, aiBrain, startposition, searchradius, minthreat, mythreat, threatseek, threatavoid )

    local GetPlatoonUnits = GetPlatoonUnits
    local GetSquadUnits = GetSquadUnits
    local GetThreatsAroundPosition = GetThreatsAroundPosition
    local GetThreatAtPosition = GetThreatAtPosition
    
    local LOUDCOPY = LOUDCOPY
    local LOUDFLOOR = LOUDFLOOR
    local LOUDINSERT = LOUDINSERT
    local LOUDMAX = LOUDMAX
    local LOUDMIN = LOUDMIN
    local LOUDSORT = LOUDSORT

    local VDist3 = VDist3

    local loiterposition = LOUDCOPY(startposition)

    -- first step - get all the threatseek threats within 8 times the searchradius - why 8 times ?
    -- because that will let us react to air threats within reasonable range of the startposition
    -- without necessarily pulling us all the way across the map - therefore ScenarioInfo.IMAPSize comes in handy
    -- here as it tells us how big each block will be so we can adjust the blocks value according to that radius

    local threats = GetThreatsAroundPosition( aiBrain, startposition, LOUDFLOOR( (searchradius * 8)/ScenarioInfo.IMAPSize), true, threatseek )

    -- filter them down to those above min threat and capture the threatavoid threat at that position
    if threats[1] then

        local results = {}
        local count = 0

        for k,v in threats do

            if v[3] > minthreat then

                LOUDINSERT(results, { v[1],v[2],v[3],aiBrain:GetThreatAtPosition( {v[1],0,v[2]}, LOUDFLOOR(128/ScenarioInfo.IMAPSize), true, threatavoid ) } )
                count = count + 1
            end
        end

        -- take the highest threat position
        if count > 0 then

            LOUDSORT(results, function (a,b) return (a[3]-a[4] > b[3]-b[4]) end )

            --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." used searchradius "..repr(searchradius).." with ratio of "..aiBrain.AirRatio)
            --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." summary "..threatseek.." threats from "..repr(startposition).." for "..LOUDFLOOR(searchradius*8/ScenarioInfo.IMAPSize).." blocks")
            --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." threats are "..repr(results) )
            --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." lerp factor is "..(searchradius*8).." to distance "..VDist3(self.anchorposition, {results[1][1], 0, results[1][2]}) )

            local lerpresult = LOUDMIN(1, LOUDMIN(1,(searchradius * 8) / VDist3( startposition, {results[1][1], 0, results[1][2]})))

            -- factor in threatavoidance to reduce the tether --
            --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." threat reduction is "..repr(LOUDMIN( 1, mythreat/LOUDMAX( 1,results[1][4]))))

            -- the tether is reduced by comparing mythreat against the avoided threat and factoring in the AirRatio
            -- this will reduce the lerp and keep us further away from those threats when the ratio is low while still allowing 
            
            -- some forward deployment
            lerpresult = lerpresult * LOUDMIN( 0.5, LOUDMIN( mythreat, mythreat * LOUDMAX( 0.28, aiBrain.AirRatio/3 ) ) / LOUDMAX(1, results[1][4]) )

            loiterposition = { LOUDFLOOR(MATH_Lerp(lerpresult, startposition[1], results[1][1] )), 0, LOUDFLOOR(MATH_Lerp( lerpresult, startposition[3], results[1][2])) } 

            --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." Lerp value is "..repr(lerpresult))
            --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." selects loiterposition "..repr(loiterposition).." distance is "..repr(LOUDFLOOR(VDist3(loiterposition, startposition))))
            --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." sets loiter at "..repr(loiterposition))
        end

    end

	IssueClearCommands( GetPlatoonUnits(self) )

	self:MoveToLocation( loiterposition, false)

	IssueGuard( GetSquadUnits( self,'Attack'), loiterposition)

    return loiterposition
end


-- Basic Air attack logic
-- Now includes code for escorting fighters --
function AirForceAILOUD( self, aiBrain )

    local CalculatePlatoonThreat = CalculatePlatoonThreat
	local GetUnitsAroundPoint = GetUnitsAroundPoint
    local GetPlatoonPosition = GetPlatoonPosition
    local GetPlatoonUnits = GetPlatoonUnits    
    local GetSquadUnits = GetSquadUnits    
    local GetThreatsAroundPosition = GetThreatsAroundPosition
	local PlatoonExists = PlatoonExists	

    
    local LOUDCOPY = LOUDCOPY
    local LOUDFLOOR = LOUDFLOOR
    local LOUDGETN = LOUDGETN
    local LOUDMAX = LOUDMAX
    local LOUDSORT = LOUDSORT
    
    local VDist2Sq = VDist2Sq
    local VDist3 = VDist3
    local WaitTicks = WaitTicks
    
    local SetLoiterPosition = import('/lua/ai/aibehaviors.lua').SetLoiterPosition

    local Searchradius = self.PlatoonData.SearchRadius or 200
    
    local missiontime = self.PlatoonData.MissionTime or 600
    local mergelimit = self.PlatoonData.MergeLimit or false
    local PlatoonFormation = self.PlatoonData.UseFormation or 'No Formation'

    local categoryList = {}
    local count = 0
    
    if self.PlatoonData.PrioritizedCategories then
	
        for _,v in self.PlatoonData.PrioritizedCategories do
            count = count + 1
            categoryList[count] = v
        end
    end

    local platoonUnits = LOUDCOPY(GetPlatoonUnits(self))
    local oldNumberOfUnitsInPlatoon = LOUDGETN(platoonUnits)

	for _,v in platoonUnits do 
	
		if not v.Dead then
		
			if v:TestToggleCaps('RULEUTC_StealthToggle') then
				v:SetScriptBit('RULEUTC_StealthToggle', false)
			end
			
			if v:TestToggleCaps('RULEUTC_CloakToggle') then
				v:SetScriptBit('RULEUTC_CloakToggle', false)
			end
		end
	end

    -- setup escorting fighters if any - pulls out any units in the platoon that are coded as 'guard' in the platoon template
	-- and places them into a seperate platoon with its own behavior
    local guardplatoon = false
	local guardunits = GetSquadUnits( self,'guard')

    if guardunits[1] then

        local ident = Random(1,999999)

        guardplatoon = aiBrain:MakePlatoon('GuardPlatoon'..tostring(ident),'none')
        AssignUnitsToPlatoon( aiBrain, guardplatoon, guardunits, 'Attack', 'none')

		guardplatoon.GuardedPlatoon = self  #-- store the handle of the platoon to be guarded to the guardplatoon
        guardplatoon:SetPrioritizedTargetList( 'Attack', categories.HIGHALTAIR * categories.ANTIAIR )

		guardplatoon:SetAIPlan( 'GuardPlatoonAI', aiBrain)
    end

	-- local function --
	local DestinationBetweenPoints = function( destination, start, finish, stepsize )

		local steps = LOUDFLOOR( VDist2(start[1], start[3], finish[1], finish[3]) / stepsize ) + 1
	
		local xstep = (start[1] - finish[1]) / steps
		local ystep = (start[3] - finish[3]) / steps

		for i = 0, steps - 1  do
			
			if VDist2Sq(start[1] - (xstep * i), start[3] - (ystep * i), destination[1], destination[3]) < (stepsize * stepsize) then

				return { start[1] - (xstep * i), destination[2], start[3] - (ystep * i) }
                
			end
		end	
		
		return false
	end

	-- TETHERING --
	-- Select a target using the target priority list and by looping thru range and difficulty multipliers until a target is found
	-- occurs to me we could pass the multipliers and difficulties from the platoondata if we wished
    
    -- this technique I'll call 'tethering' or leashing' - and it will grow and contract with other conditions (air ratio, outnumberedratio)
    -- we loop thru each multiplier - which is used on the basic Searchradius - giving us expanding 'rings'
    -- the maximum size of a ring will fluctuate with the air ratio - more restrictive if losing, larger if winning
    -- the maximum size of a ring will fluctuate with the outnumbered ratio - restrictive if outnumbered, neutral otherwise
    -- then we loop thru all 3 difficulty settings within that ring, looking for the easiest targets first 
    -- comparing our platoon threat against the actual threat we see within 75 of the target position
    -- if we have more - we have a target - and we drop out
    -- if no target, we advance the multiplier and do it again for the next ring
    -- notice how the minimum range of the ring is carried forward from the previous iteration 

	-- force the plan name
	self.PlanName = 'AirForceAILOUD'

	self.anchorposition = LOUDCOPY( GetPlatoonPosition(self) )

    local MissionStartTime = LOUDTIME()
    local threatcheckradius = 128
    
    -- block based IMAP threat checks are controlled by this - allowing it to scale properly with map sizes
    local IMAPblocks = LOUDFLOOR(threatcheckradius/ScenarioInfo.IMAPSize)

    local target = false
	local targetposition = false

	local loiter = false
	local loiterposition = false
    
    local mythreat, atthreat
    
    local threatcompare = 'Air'
    local threatavoid = 'AntiAir'
    
    local mult = { 1, 2, 3 }				-- this multiplies the range of the platoon when searching for targets
	local difficulty = { 1.25, 1, 0.8 } 		-- this divides the base threat of the platoon, by deflating it and then increasing it, so that easier targets are selected first
    
    local minrange, maxrange, searchradius, usethreat
    local Rangemult, Threatmult
    
    local SecondaryAATargets, SecondaryShieldTargets, TertiaryTargets
    local AACount, ShieldCount, TertiaryCount

	local path, reason, prevposition, paththreat
    local newpath, pathsize, destiny
    
    local strikerange = LOUDMAX( 128, ScenarioInfo.IMAPSize )

    while PlatoonExists(aiBrain, self) and (LOUDTIME() - MissionStartTime) <= missiontime do

        -- merge with other AirForceAILOUD groups with same plan
        if mergelimit and oldNumberOfUnitsInPlatoon < mergelimit then

			if self:MergeWithNearbyPlatoons( aiBrain, 'AirForceAILOUD', 96, false, mergelimit) then

				self:SetPlatoonFormationOverride(PlatoonFormation)
				oldNumberOfUnitsInPlatoon = LOUDGETN(GetPlatoonUnits(self))
                
                if ScenarioInfo.PlatoonMergeDialog then
                    LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." merges to "..oldNumberOfUnitsInPlatoon)
                end
			end
        end

        platoonUnits = LOUDCOPY(GetPlatoonUnits(self))

        if (not target or target.Dead) and PlatoonExists(aiBrain, self) then

            mythreat = CalculatePlatoonThreat( self, 'Surface', categories.ALLUNITS)
            mythreat = mythreat + CalculatePlatoonThreat( self, 'Air', categories.ALLUNITS)

            if mythreat < 5 then
                mythreat = 5
            end
            
            -- the searchradius adapts to the current air ratio and the platoon size
            searchradius = LOUDMAX(Searchradius, (Searchradius *  LOUDMAX(1, (aiBrain.AirRatio/3) * LOUDMIN(1, LOUDGETN(platoonUnits)/18) ) ) )

            usethreat = 0
            minrange = 0

			-- the anchorposition is the start position of the platoon - not necessarily the base where it formed
			-- and is where the platoon returns to if it should be drawn away to attack something
            -- the loiter flag indicates that we are without a target and guarding this position
			if GetPlatoonPosition(self) then
			
				if not loiter then
                
                    loiterposition = SetLoiterPosition( self, aiBrain, self.anchorposition, searchradius, 3, mythreat, 'AIR', 'ANTIAIR' )
                    
                    loiter = true
				end
                
			else
				return self:SetAIPlan('ReturnToBaseAI',aiBrain)
			end
            
			-- locate a target -- starting with the closest -- least dangerous ones 
            for _,rangemult in mult do

				for _,threatmult in difficulty do
                
                    usethreat = ( mythreat/threatmult ) / rangemult

					target,targetposition = AIFindTargetInRangeInCategoryWithThreatFromPosition(aiBrain, loiterposition, self, 'Attack', minrange, searchradius * rangemult, categoryList, usethreat, threatcompare, threatcheckradius, threatavoid )

					if not PlatoonExists(aiBrain, self) then
						return
					end					

					if target then
                    
                        self.UsingTransport = true
                        
                        Threatmult = threatmult
						break
					end
				end

                -- record Rangemult value for later use --
                Rangemult = rangemult

				if target then
					maxrange = searchradius * rangemult
					break
				end

                minrange = searchradius * rangemult

            end

            -- if we have a target - find secondary targets near it
			if target and not target.Dead and PlatoonExists(aiBrain, self) then
            
                SecondaryAATargets = false
                AACount = 0
                SecondaryShieldTargets = false
                ShieldCount = 0
                TertiaryTargets = false
                TertiaryCount = 0

                -- enemy fighters 
                SecondaryAATargets = GetUnitsAroundPoint( aiBrain, categories.HIGHALTAIR, targetposition, threatcheckradius, 'Enemy')
                -- enemy gunships
                SecondaryShieldTargets = GetUnitsAroundPoint( aiBrain, categories.GROUNDATTACK, targetposition, threatcheckradius, 'Enemy')
                -- enemy bombers
                TertiaryTargets = GetUnitsAroundPoint( aiBrain, categories.BOMBER, targetposition, threatcheckradius, 'Enemy')
                
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." with "..LOUDGETN(GetSquadUnits( self,'Attack')).." units has target at "..repr(targetposition))
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." finds "..LOUDMAX(aiBrain:GetThreatAtPosition( targetposition, 0, true, threatavoid )).." threat at that position - mythreat is "..usethreat)
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." used RangeMult of "..Rangemult.." and Difficulty of "..Threatmult)
                
                if SecondaryAATargets[1] then
                    AACount = LOUDGETN(SecondaryAATargets)
                end
                
                if SecondaryShieldTargets[1] then
                    ShieldCount = LOUDGETN(SecondaryShieldTargets)
                end
                
                if TertiaryTargets[1] then
                    TertiaryCount = LOUDGETN(TertiaryTargets)
                end

                -- Have a target - plot path to target - Use airthreat vs. mythreat for path
                -- use strikerange to determine point from which to switch into attack mode
				prevposition = LOUDCOPY(GetPlatoonPosition(self))

				paththreat = (oldNumberOfUnitsInPlatoon * 1) + CalculatePlatoonThreat( self, 'Air', categories.ALLUNITS)

                path, reason = self.PlatoonGenerateSafePathToLOUD(aiBrain, self, self.MovementLayer, prevposition, targetposition, paththreat, strikerange )

                if path then

                    IssueClearCommands( platoonUnits )

                    newpath = {}
                    count = 0
                    pathsize = LOUDGETN(path)

                    -- build a newpath that gets the platoon to within strikerange
                    for waypoint,p in path do
                    
                        destiny = DestinationBetweenPoints( targetposition, prevposition, p, strikerange )

                        if waypoint < pathsize and destiny then

                            count = count + 1
                            newpath[count] = p

                            prevposition = p
						else
                        
                            if destiny then
                            
                                -- if path breakoff point is not the same as the prevposition - add it to the path
                                if destiny[1] != prevposition[1] and destiny[3] != prevposition[3] then
                            
                                    count = count + 1
                                    newpath[count] = LOUDCOPY(destiny)
                                end
                            end

                            break
                        end
                    end
                    
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." has path "..reason.." "..repr(path))
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." vs using "..repr(newpath))

                    -- if we have a path - versus direct which will have zero path entries --
                    if newpath[1] then

                        -- move the platoon to within strikerange in formation
                        self.MoveThread = self:ForkThread( self.MovePlatoon, newpath, 'AttackFormation', false, 70)
                        
                        loiter = false

                        -- wait for the movement orders to execute --
                        while PlatoonExists(aiBrain, self) and self.MoveThread and not target.Dead do
                        
                            WaitTicks(1)
                            
                            if target.Dead then
                            
                                target = false
                                
                                break
                            end
                        end
                        
                    else
                        WaitTicks(10)
                    end
                    
                    if self.MoveThread then
                        self:KillMoveThread()
                    end

                else

					target = false
                end

                if PlatoonExists(aiBrain, self) and target and not target.Dead then

                    -- we assign 30% of the units to attack fighters first
                    -- then another 15% of the units to attack gunships and bombers
                    -- the remaining 30% will attack the primary first
                    local attackers = GetSquadUnits( self,'Attack')
                    local attackercount = LOUDGETN(attackers)
                    
                    local shield = 1
                    local aa = 1
                    local tertiary = 1

                    local squad = GetPlatoonPosition(self) or false
                    
                    targetposition = GetPosition(target) or false
                    
                    if squad and targetposition then

                        local midpointx = (squad[1]+targetposition[1])/2
                        local midpointy = (squad[2]+targetposition[2])/2
                        local midpointz = (squad[3]+targetposition[3])/2
                    
                        local Direction = import('/lua/utilities.lua').GetDirectionInDegrees( squad, targetposition )

                        -- this gets them moving to a point halfway to the targetposition - hopefully
                        IssueFormMove( GetPlatoonUnits(self), { midpointx, midpointy, midpointz }, 'AttackFormation', Direction )

                        -- sort the fighters by farthest from target -- we'll send them just ahead of the others to get tighter wave integrity
                        LOUDSORT( attackers, function (a,b) return VDist3(GetPosition(a),targetposition) > VDist3(GetPosition(b),targetposition) end )
                   
                        local attackissued = false
                        local attackissuedcount = 0

                        for key,u in attackers do
                    
                            if not u.Dead then
                        
                                IssueClearCommands( {u} )
                            
                                attackissued = false

                                -- first 15% of attacks go for the gunships
                                if key < attackercount * .15 and SecondaryShieldTargets[shield] then
                        
                                    if not SecondaryShieldTargets[shield].Dead then
                                        IssueAttack( {u}, SecondaryShieldTargets[shield] )
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end

                                    if shield >= ShieldCount then
                                        shield = 1
                                    else
                                        shield = shield + 1
                                    end 
                                end
                        
                                -- next 30% go for fighters units
                                if not attackissued and key <= attackercount * .45 and SecondaryAATargets[aa] then

                                    if not SecondaryAATargets[aa].Dead then
                                        IssueAttack( {u}, SecondaryAATargets[aa] )
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end
                            
                                    if aa >= AACount then
                                        aa = 1
                                    else
                                        aa = aa + 1
                                    end
                                end
                            
                                -- next 15% for bomber targets --
                                if not attackissued and key <= attackercount * .6 and TertiaryTargets[tertiary] then
                            
                                    if not TertiaryTargets[tertiary].Dead then
                                
                                        IssueAttack( {u}, TertiaryTargets[tertiary] )
                                    
                                        --LOG("*AI DEBUG Issued attack "..key.." on Tertiary "..repr(tertiary).." "..repr(TertiaryTargets[tertiary]:GetBlueprint().Description) )
                                    
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end
                                
                                    if tertiary >= TertiaryCount then
                                        tertiary = 1
                                    else 
                                        tertiary = tertiary + 1
                                    end
                                end
                        
                                -- all others go for primary
                                if not target.Dead and not attackissued then

                                    IssueAttack( {u}, target )
                                    attackissued = true
                                    attackissuedcount = attackissuedcount + 1
                                end
                    
                                if attackissuedcount > 5 then
                                    WaitTicks(1)
                                    attackissuedcount = 0
                                end
                            end
                        end
                    end
                end
			end
        end

		-- Attack until target is dead, beyond maxrange, or retreat
		while (target and not target.Dead) and PlatoonExists(aiBrain, self) do
         
            mythreat = CalculatePlatoonThreat( self, 'Air', categories.ALLUNITS)
            atthreat = 0
            
            for _, v in GetThreatsAroundPosition( aiBrain, GetPlatoonPosition(self), LOUDFLOOR(IMAPblocks/2), true, threatavoid ) do
            
                atthreat = atthreat + v[3]
                
                if atthreat > mythreat then
                
                    LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." AA threat too high "..atthreat.." - aborting - my threat "..mythreat.." using "..LOUDFLOOR(IMAPblocks/2).." IMAP blocks at "..repr(GetPlatoonPosition(self)) )
        
                    IssueClearCommands(self)

                    target = false
            
                    loiter = false
            
                    self:MoveToLocation( loiterposition, false )                    

                    break   --return self:SetAIPlan('ReturnToBaseAI',aiBrain)
                end
            end

            if target then
                WaitTicks(2)
            end
            
            if VDist3( GetPlatoonPosition(self), loiterposition ) > maxrange then
                break
            end
		end

		if target and PlatoonExists(aiBrain, self) then
        
            IssueClearCommands(self)

			target = false
            
            loiter = true
            
            self:MoveToLocation( loiterposition, false )
		end

		if loiter then
			WaitTicks(6)
        end
        
        self.UsingTransport = false
        
    end

    if PlatoonExists(aiBrain, self) then
        return self:SetAIPlan('ReturnToBaseAI',aiBrain)
    end
	
end

-- THIS IS AN ALTERNATIVE AirForceAI specifically for bombers
function AirForceAI_Bomber_LOUD( self, aiBrain )

    local CalculatePlatoonThreat = CalculatePlatoonThreat
	local GetUnitsAroundPoint = GetUnitsAroundPoint
    local GetPlatoonPosition = GetPlatoonPosition
    local GetPlatoonUnits = GetPlatoonUnits    
    local GetSquadUnits = GetSquadUnits    
    local GetThreatsAroundPosition = GetThreatsAroundPosition
	local PlatoonExists = PlatoonExists	
    
    local LOUDCOPY = LOUDCOPY
    local LOUDFLOOR = LOUDFLOOR
    local LOUDGETN = LOUDGETN
    local LOUDMAX = LOUDMAX
    local LOUDSORT = LOUDSORT
    
    local VDist2Sq = VDist2Sq
    local VDist3 = VDist3
    local WaitTicks = WaitTicks
    
    local SetLoiterPosition = import('/lua/ai/aibehaviors.lua').SetLoiterPosition
    
    local Searchradius = self.PlatoonData.SearchRadius or 200
    
    local missiontime = self.PlatoonData.MissionTime or 600
    local mergelimit = self.PlatoonData.MergeLimit or false
    local PlatoonFormation = self.PlatoonData.UseFormation or 'No Formation'

    local platoonUnits = LOUDCOPY(GetPlatoonUnits(self))

    local categoryList = {}
    local count = 0
    
    if self.PlatoonData.PrioritizedCategories then
	
        for _,v in self.PlatoonData.PrioritizedCategories do
            count = count + 1
            categoryList[count] = v
        end
    end

    local oldNumberOfUnitsInPlatoon = LOUDGETN(platoonUnits)

	for _,v in platoonUnits do 
	
		if not v.Dead then
		
			if v:TestToggleCaps('RULEUTC_StealthToggle') then
				v:SetScriptBit('RULEUTC_StealthToggle', false)
			end
			
			if v:TestToggleCaps('RULEUTC_CloakToggle') then
				v:SetScriptBit('RULEUTC_CloakToggle', false)
			end
		end
	end

    -- setup escorting fighters if any 
	-- pulls out any units in the platoon that are coded as 'guard' in the platoon template
	-- and places them into a seperate platoon with its own behavior
    local guardplatoon = false
	local guardunits = GetSquadUnits( self,'guard')

    if guardunits[1] then
    
        local ident = Random(1,999999)

        guardplatoon = aiBrain:MakePlatoon('GuardPlatoon'..tostring(ident),'none')
        AssignUnitsToPlatoon( aiBrain, guardplatoon, guardunits, 'Attack', 'none')

		guardplatoon.GuardedPlatoon = self  #-- store the handle of the platoon to be guarded to the guardplatoon
        guardplatoon:SetPrioritizedTargetList( 'Attack', categories.HIGHALTAIR * categories.ANTIAIR )

		guardplatoon:SetAIPlan( 'GuardPlatoonAI', aiBrain)
    end

	local DestinationBetweenPoints = function( destination, start, finish, stepsize )

		local steps = LOUDFLOOR( VDist2(start[1], start[3], finish[1], finish[3]) / stepsize ) + 1
	
		local xstep = (start[1] - finish[1]) / steps
		local ystep = (start[3] - finish[3]) / steps

		for i = 0, steps - 1  do
			
			if VDist2Sq(start[1] - (xstep * i), start[3] - (ystep * i), destination[1], destination[3]) < (stepsize * stepsize) then
            
				return { start[1] - (xstep * i), destination[2], start[3] - (ystep * i) }
			end
		end	
		
		return false
	end
	
	-- Select a target using priority list and by looping thru range and difficulty multipliers until target is found
	-- occurs to me we could pass the multipliers and difficulties from the platoondata if we wished
	-- force the plan name onto the platoon
	self.PlanName = 'AirForceAI_Bomber_LOUD'

	self.anchorposition = LOUDCOPY( GetPlatoonPosition(self) )

    local MissionStartTime = LOUDTIME()
    local threatcheckradius = 96
    
    -- block based IMAP threat checks are controlled by this - allowing it to scale properly with map sizes
    local IMAPblocks = LOUDFLOOR(threatcheckradius/ScenarioInfo.IMAPSize)

    local target = false
	local targetposition = false

	local loiter = false
	local loiterposition = false
    
    local mythreat, atthreat
    
    local threatcompare = 'AntiAir'
    local threatavoid = 'AntiAir'
    
    local mult = { 1, 2, 3 }				-- this multiplies the range of the platoon when searching for targets
	local difficulty = { 1.25, 1, 0.72 } 		-- this divides the base threat of the platoon, by deflating it and then increasing it, so that easier targets are selected first
    
    local minrange, maxrange, searchradius, usethreat
    local Rangemult, Threatmult
    
    local SecondaryAATargets, SecondaryShieldTargets, TertiaryTargets
    local AACount, ShieldCount, TertiaryCount

	local path, reason, prevposition, paththreat
    local newpath, pathsize, destiny
    
    strikerange = LOUDMAX( 96, ScenarioInfo.IMAPSize )
	
    while PlatoonExists(aiBrain, self) and (LOUDTIME() - MissionStartTime) <= missiontime do

        -- merge with other AirForceAI_Bomber_LOUD groups with same plan within 80
        if mergelimit and oldNumberOfUnitsInPlatoon < mergelimit then

			if self:MergeWithNearbyPlatoons( aiBrain, 'AirForceAI_Bomber_LOUD', 80, false, mergelimit) then

				self:SetPlatoonFormationOverride(PlatoonFormation)
				oldNumberOfUnitsInPlatoon = LOUDGETN(GetPlatoonUnits(self))
                
                if ScenarioInfo.PlatoonMergeDialog then
                    LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." merges to "..oldNumberOfUnitsInPlatoon)
                end
			end
        end

        platoonUnits = LOUDCOPY(GetPlatoonUnits(self))

        if (not target or target.Dead) and PlatoonExists(aiBrain, self) then

            mythreat = CalculatePlatoonThreat( self, 'Surface', categories.ALLUNITS) * .5   -- use only 1/2 of surface threat for target search 
            mythreat = mythreat + CalculatePlatoonThreat( self, 'Air', categories.ALLUNITS)   -- plus any air threat

            if mythreat < 5 then
                mythreat = 5
            end
            
            -- the searchradius adapts to the current air ratio but is restricted by formation size (15 being the basis of that)
            -- thus smaller formations won't see much difference even during high AirRatio conditions
            -- whereas large formations will see the entire benefit
            searchradius = LOUDMAX(Searchradius, (Searchradius *  LOUDMAX(1, (aiBrain.AirRatio/3) * LOUDMIN(1, LOUDGETN(platoonUnits)/15) ) ) )
            
            usethreat = 0
            minrange = 0

			-- the anchorposition is the start position of the platoon
			-- where the platoon returns to
			-- if it should be drawn away due to distress calls
			if GetPlatoonPosition(self) then
			
				if not loiter then
                
                    loiterposition = SetLoiterPosition( self, aiBrain, self.anchorposition, searchradius, 3, mythreat, 'LAND', 'ANTIAIR' )
                    loiter = true
				end
                
			else
				return self:SetAIPlan('ReturnToBaseAI',aiBrain)
			end

            for _,rangemult in mult do

				for _,threatmult in difficulty do
                
                    usethreat = ( mythreat/threatmult ) / rangemult

					target,targetposition = AIFindTargetInRangeInCategoryWithThreatFromPosition(aiBrain, loiterposition, self, 'Attack', minrange, searchradius * rangemult, categoryList, usethreat, threatcompare, threatcheckradius, threatavoid )

					if not PlatoonExists(aiBrain, self) then
						return
					end					

					if target then
                    
                        self.UsingTransport = true  -- general 'busy' flag - prevents merging with other platoons
                        
                        Threatmult = threatmult
						break
					end
				end
                
                -- record Rangemult value for later use --
                Rangemult = rangemult
                
				if target then
					maxrange = searchradius * rangemult
					break
				end

                minrange = searchradius * rangemult
                
                WaitTicks(1)                
            end
        
			if target and not target.Dead and PlatoonExists(aiBrain, self) then
            
                SecondaryAATargets = false
                AACount = 0
                SecondaryShieldTargets = false
                ShieldCount = 0
                TertiaryTargets = false
                TertiaryCount = 0
            
                SecondaryAATargets = GetUnitsAroundPoint( aiBrain, categories.ANTIAIR - categories.AIR, targetposition, threatcheckradius/2, 'Enemy')
                SecondaryShieldTargets = GetUnitsAroundPoint( aiBrain, categories.SHIELD, targetposition, threatcheckradius/2, 'Enemy')
                TertiaryTargets = GetUnitsAroundPoint( aiBrain, categories.ALLUNITS - categories.ANTIAIR - categories.AIR - categories.SHIELD - categories.WALL, targetposition, threatcheckradius/4, 'Enemy')
                
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." with "..LOUDGETN(GetSquadUnits( self,'Attack')).." bombers has target at "..repr(targetposition))
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." target is "..repr(target:GetBlueprint().Description))
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." used RangeMult of "..Rangemult.." and Difficulty of "..Threatmult)
                
                if SecondaryAATargets[1] then
                    AACount = LOUDGETN(SecondaryAATargets)
                end
                
                if SecondaryShieldTargets[1] then
                    ShieldCount = LOUDGETN(SecondaryShieldTargets)
                end
                
                if TertiaryTargets[1] then
                    TertiaryCount = LOUDGETN(TertiaryTargets)
                end

                -- Have a target - plot path to target - Use airthreat vs. mythreat for path
                -- use strikerange to determine point from which to switch into attack mode
				prevposition = LOUDCOPY(GetPlatoonPosition(self))

				paththreat = (oldNumberOfUnitsInPlatoon * 1) + CalculatePlatoonThreat( self,'Air', categories.ALLUNITS)

                path, reason = self.PlatoonGenerateSafePathToLOUD(aiBrain, self, self.MovementLayer, prevposition, targetposition, paththreat, strikerange )

                if path and PlatoonExists(aiBrain, self) then

                    IssueClearCommands( platoonUnits )
                    
                    newpath = {}
                    count = 0
                    pathsize = LOUDGETN(path)

                    -- build a newpath that gets the platoon to within strikerange
                    -- rather than going all the way to target
                    for waypoint,p in path do
                    
                        destiny = DestinationBetweenPoints( targetposition, prevposition, p, strikerange )

                        if waypoint < pathsize and not destiny then

                            count = count + 1
                            newpath[count] = p

                            prevposition = p
						else
                        
                            if destiny then
                            
                                -- if path breakoff point is not the same as the prevposition - add it to the path
                                if destiny[1] != prevposition[1] and destiny[3] != prevposition[3] then
                            
                                    count = count + 1
                                    newpath[count] = LOUDCOPY(destiny)
                                    
                                end
                            end
                            
                            break
                        end
                    end
                    
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." has path "..repr(path))
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." vs using "..repr(newpath))

                    -- if we have a path - versus direct which will have zero path entries --
                    if newpath[1] then

                        -- move the platoon to within strikerange in formation - the slackvalue is based on the strikerange
                        self.MoveThread = self:ForkThread( self.MovePlatoon, newpath, 'AttackFormation', false, strikerange * .4)

                        -- wait for the movement orders to execute --
                        while PlatoonExists(aiBrain, self) and self.MoveThread and not target.Dead do
                        
                            WaitTicks(1)

                            if target.Dead then

                                loiter = false
                                
                                break
                            end
                        end
                        
                    else
                        WaitTicks(10)   -- let direct move execute for one second
                    end

                    if self.MoveThread then
                        self:KillMoveThread()
                    end
                else

					target = false
                end

                if PlatoonExists(aiBrain, self) and target and not target.Dead then
                
                    -- we assign 30% of the units to attack shields first
                    -- then another 20% of the units to attack AA first
                    -- and another 15% for incidentals
                    -- the remaining 35% will attack the primary first
                    local attackers = GetSquadUnits( self,'Attack')
                    local attackercount = LOUDGETN(attackers)
                    
                    local shield = 1
                    local aa = 1
                    local tertiary = 1

                    local squad = GetPlatoonPosition(self) or false
                    
                    targetposition = GetPosition(target) or false
                    
                    if squad and targetposition then
                    
                        local midpointx = (squad[1]+targetposition[1])/2
                        local midpointy = (squad[2]+targetposition[2])/2
                        local midpointz = (squad[3]+targetposition[3])/2
                    
                        local Direction = import('/lua/utilities.lua').GetDirectionInDegrees( squad, targetposition )

                        -- this gets them moving to a point halfway to the targetposition - hopefully
                        IssueFormMove( GetPlatoonUnits(self), { midpointx, midpointy, midpointz }, 'AttackFormation', Direction )

                        -- sort the bombers by farthest from target -- we'll send them just ahead of the others to get tighter wave integrity
                        LOUDSORT( attackers, function (a,b) return VDist3(a:GetPosition(),targetposition) > VDist3(b:GetPosition(),targetposition) end )
                   
                        local attackissued = false
                        local attackissuedcount = 0

                        for key,u in attackers do
                    
                            if not u.Dead then
                        
                                IssueClearCommands( {u} )
                            
                                attackissued = false

                                -- first 30% of attacks go for the shields
                                if key < attackercount * .3 and SecondaryShieldTargets[shield] then
                        
                                    if not SecondaryShieldTargets[shield].Dead then
                                        IssueAttack( {u}, SecondaryShieldTargets[shield] )
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end

                                    if shield >= ShieldCount then
                                        shield = 1
                                    else
                                        shield = shield + 1
                                    end 
                                end
                        
                                -- next 20% go for AA units
                                if not attackissued and key <= attackercount * .5 and SecondaryAATargets[aa] then

                                    if not SecondaryAATargets[aa].Dead then
                                        IssueAttack( {u}, SecondaryAATargets[aa] )
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end
                            
                                    if aa >= AACount then
                                        aa = 1
                                    else
                                        aa = aa + 1
                                    end
                                end
                            
                                -- next 15% for tertiary targets --
                                if not attackissued and key <= attackercount * .65 and TertiaryTargets[tertiary] then
                            
                                    if not TertiaryTargets[tertiary].Dead and self:CanAttackTarget('Attack', TertiaryTargets[tertiary]) then
                                        IssueAttack( {u}, TertiaryTargets[tertiary] )
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end
                                
                                    if tertiary >= TertiaryCount then
                                        tertiary = 1
                                    else 
                                        tertiary = tertiary + 1
                                    end
                                end
                        
                                -- all others go for primary
                                if not target.Dead and not attackissued then

                                    IssueAttack( {u}, target )
                                    attackissued = true
                                    attackissuedcount = attackissuedcount + 1
                                end
                    
                                if attackissuedcount > 3 then
                                    WaitTicks(1)
                                    attackissuedcount = 0
                                end
                            end
                        end
                    end
                end
			end
        end

		-- Attack until target is dead, beyond maxrange or retreat
		while (target and not target.Dead) and PlatoonExists(aiBrain, self) and (VDist3( GetPosition(target), loiterposition ) <= maxrange) do

            mythreat = CalculatePlatoonThreat( self, 'Surface', categories.ALLUNITS) * .5   -- use only 1/2 of surface threat
            mythreat = mythreat + CalculatePlatoonThreat( self, 'Air', categories.ALLUNITS)   -- plus any air threat
            
            atthreat = 0
            
            for _, v in GetThreatsAroundPosition( aiBrain, GetPlatoonPosition(self), LOUDFLOOR(IMAPblocks/2), true, threatavoid ) do
            
                atthreat = atthreat + v[3]
                
                if atthreat > mythreat then
                
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." AA threat too high "..atthreat.." - aborting - my threat "..mythreat.." using "..LOUDFLOOR(IMAPblocks/2).." IMAP blocks")
                    
                    return self:SetAIPlan('ReturnToBaseAI',aiBrain)
                end
            end

			WaitTicks(5)
            
            if PlatoonExists(aiBrain, self) and VDist3( GetPlatoonPosition(self), loiterposition ) > maxrange then
                break
            end
   
		end

        -- we had a target and target is destroyed
		if target and PlatoonExists(aiBrain, self) then
        
            IssueClearCommands(self)

			target = false
            
            loiter = true
            
            self:MoveToLocation( loiterposition, false )

		end

		-- loiter will be true if we did not find a target
		-- or we couldn't get to the target - we should 
        -- still be guarding the anchorposition
		if loiter then
			WaitTicks(10)
		end

        self.UsingTransport = false
        
    end

    if PlatoonExists(aiBrain, self) then
        return self:SetAIPlan('ReturnToBaseAI',aiBrain)
    end
	
end

-- THIS IS AN ALTERNATIVE AirForceAI specifically for gunships
function AirForceAI_Gunship_LOUD( self, aiBrain )

    local CalculatePlatoonThreat = CalculatePlatoonThreat
	local GetUnitsAroundPoint = GetUnitsAroundPoint
    local GetPlatoonPosition = GetPlatoonPosition
    local GetPlatoonUnits = GetPlatoonUnits    
    local GetSquadUnits = GetSquadUnits    
    local GetThreatsAroundPosition = GetThreatsAroundPosition
	local PlatoonExists = PlatoonExists	

    
    local LOUDCOPY = LOUDCOPY
    local LOUDFLOOR = LOUDFLOOR
    local LOUDGETN = LOUDGETN
    local LOUDMAX = LOUDMAX
    local LOUDSORT = LOUDSORT
    
    local VDist2Sq = VDist2Sq
    local VDist3 = VDist3
    local WaitTicks = WaitTicks
    
    local SetLoiterPosition = import('/lua/ai/aibehaviors.lua').SetLoiterPosition
    
    local Searchradius = self.PlatoonData.SearchRadius or 200
    
    local missiontime = self.PlatoonData.MissionTime or 600
    local mergelimit = self.PlatoonData.MergeLimit or false
    local PlatoonFormation = self.PlatoonData.UseFormation or 'No Formation'

    local platoonUnits = LOUDCOPY(GetPlatoonUnits(self))

    local categoryList = {}
    local count = 0
    
    if self.PlatoonData.PrioritizedCategories then
	
        for _,v in self.PlatoonData.PrioritizedCategories do
            count = count + 1
            categoryList[count] = v
        end
    end

    local oldNumberOfUnitsInPlatoon = LOUDGETN(platoonUnits)

	for _,v in platoonUnits do 
	
		if not v.Dead then
		
			if v:TestToggleCaps('RULEUTC_StealthToggle') then
				v:SetScriptBit('RULEUTC_StealthToggle', false)
			end
			
			if v:TestToggleCaps('RULEUTC_CloakToggle') then
				v:SetScriptBit('RULEUTC_CloakToggle', false)
			end
		end
	end

    -- setup escorting fighters if any 
	-- pulls out any units in the platoon that are coded as 'guard' in the platoon template
	-- and places them into a seperate platoon with its own behavior
    local guardplatoon = false
	local guardunits = GetSquadUnits( self,'guard')

    if guardunits[1] then
    
        local ident = Random(1,999999)

        guardplatoon = aiBrain:MakePlatoon('GuardPlatoon'..tostring(ident),'none')
        AssignUnitsToPlatoon( aiBrain, guardplatoon, guardunits, 'Attack', 'none')

		guardplatoon.GuardedPlatoon = self  #-- store the handle of the platoon to be guarded to the guardplatoon
        guardplatoon:SetPrioritizedTargetList( 'Attack', categories.HIGHALTAIR * categories.ANTIAIR )

		guardplatoon:SetAIPlan( 'GuardPlatoonAI', aiBrain)
    end

	local DestinationBetweenPoints = function( destination, start, finish, stepsize )

		local steps = LOUDFLOOR( VDist2(start[1], start[3], finish[1], finish[3]) / stepsize ) + 1
	
		local xstep = (start[1] - finish[1]) / steps
		local ystep = (start[3] - finish[3]) / steps

		for i = 0, steps - 1  do
			
			if VDist2Sq(start[1] - (xstep * i), start[3] - (ystep * i), destination[1], destination[3]) < (stepsize * stepsize) then
            
				return { start[1] - (xstep * i), destination[2], start[3] - (ystep * i) }
                
			end
		end	
		
		return false
	end
	
	-- Select a target using priority list and by looping thru range and difficulty multipliers until target is found
	-- occurs to me we could pass the multipliers and difficulties from the platoondata if we wished
	-- force the plan name onto the platoon
	self.PlanName = 'AirForceAI_Gunship_LOUD'

	self.anchorposition = LOUDCOPY( GetPlatoonPosition(self) )

    local MissionStartTime = LOUDTIME()
    local threatcheckradius = 96
    
    -- block based IMAP threat checks are controlled by this - allowing it to scale properly with map sizes
    local IMAPblocks = LOUDFLOOR(threatcheckradius/ScenarioInfo.IMAPSize)

    local target = false
	local targetposition = false

	local loiter = false
	local loiterposition = false
    
    local mythreat, atthreat
    
    local threatcompare = 'AntiAir'
    local threatavoid = 'AntiAir'
    
    local mult = { 1, 2, 3 }				-- this multiplies the range of the platoon when searching for targets
	local difficulty = { 1.25, 1, 0.72 } 		-- this divides the base threat of the platoon, by deflating it and then increasing it, so that easier targets are selected first
    
    local minrange, maxrange, searchradius, usethreat
    local Rangemult, Threatmult
    
    local SecondaryAATargets, SecondaryShieldTargets, TertiaryTargets
    local AACount, ShieldCount, TertiaryCount

	local path, reason, prevposition, paththreat
    local newpath, pathsize, destiny
    
    strikerange = LOUDMAX( 96, ScenarioInfo.IMAPSize )
	
    while PlatoonExists(aiBrain, self) and (LOUDTIME() - MissionStartTime) <= missiontime do

        -- merge with other AirForceAI_Bomber_LOUD groups with same plan within 80
        if mergelimit and oldNumberOfUnitsInPlatoon < mergelimit then

			if self:MergeWithNearbyPlatoons( aiBrain, 'AirForceAI_Gunship_LOUD', 80, false, mergelimit) then

				self:SetPlatoonFormationOverride(PlatoonFormation)
				oldNumberOfUnitsInPlatoon = LOUDGETN(GetPlatoonUnits(self))
                
                if ScenarioInfo.PlatoonMergeDialog then
                    LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." merges to "..oldNumberOfUnitsInPlatoon)
                end
			end
        end

        platoonUnits = LOUDCOPY(GetPlatoonUnits(self))

        if (not target or target.Dead) and PlatoonExists(aiBrain, self) then

            mythreat = CalculatePlatoonThreat( self, 'Surface', categories.ALLUNITS) * .65   -- use only 1/2 of surface threat for target search 
            mythreat = mythreat + CalculatePlatoonThreat( self, 'Air', categories.ALLUNITS)   -- plus any air threat

            if mythreat < 5 then
                mythreat = 5
            end
            
            -- the searchradius adapts to the current air ratio but is limited by formation size
            searchradius = LOUDMAX(Searchradius, (Searchradius *  LOUDMAX(1, (aiBrain.AirRatio/3) * LOUDMIN(1, LOUDGETN(platoonUnits)/15) ) ) )

            usethreat = 0
            minrange = 0

			-- the anchorposition is the start position of the platoon
			-- where the platoon returns to
			-- if it should be drawn away due to distress calls
			if GetPlatoonPosition(self) then
			
				if not loiter then
                
                    loiterposition = SetLoiterPosition( self, aiBrain, self.anchorposition, searchradius, 3, mythreat, 'LAND', 'ANTIAIR' )
                    
                    loiter = true

				end
                
			else
				return self:SetAIPlan('ReturnToBaseAI',aiBrain)
			end

            for _,rangemult in mult do

				for _,threatmult in difficulty do
                
                    usethreat = ( mythreat/threatmult ) / rangemult

					target,targetposition = AIFindTargetInRangeInCategoryWithThreatFromPosition(aiBrain, loiterposition, self, 'Attack', minrange, searchradius * rangemult, categoryList, usethreat, threatcompare, threatcheckradius, threatavoid )

					if not PlatoonExists(aiBrain, self) then
						return
					end					

					if target then
                    
                        self.UsingTransport = true  -- general 'busy' flag - prevents merging with other platoons
                        
                        Threatmult = threatmult
						break
					end

				end
                
                -- record Rangemult value for later use --
                Rangemult = rangemult
                
				if target then
					maxrange = searchradius * rangemult
					break
				end

                minrange = searchradius * rangemult
                
                WaitTicks(1)                
            end
        
			if target and not target.Dead and PlatoonExists(aiBrain, self) then
            
                SecondaryAATargets = false
                AACount = 0
                SecondaryShieldTargets = false
                ShieldCount = 0
                TertiaryTargets = false
                TertiaryCount = 0
            
                SecondaryAATargets = GetUnitsAroundPoint( aiBrain, categories.ANTIAIR - categories.AIR, targetposition, threatcheckradius/2, 'Enemy')
                SecondaryShieldTargets = GetUnitsAroundPoint( aiBrain, categories.SHIELD, targetposition, threatcheckradius/2, 'Enemy')
                TertiaryTargets = GetUnitsAroundPoint( aiBrain, categories.ALLUNITS - categories.ANTIAIR - categories.AIR - categories.SHIELD - categories.WALL, targetposition, threatcheckradius/4, 'Enemy')
                
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." with "..LOUDGETN(GetSquadUnits( self,'Attack')).." bombers has target at "..repr(targetposition))
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." target is "..repr(target:GetBlueprint().Description))
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." used RangeMult of "..Rangemult.." and Difficulty of "..Threatmult)
                
                if SecondaryAATargets[1] then
                    AACount = LOUDGETN(SecondaryAATargets)
                end
                
                if SecondaryShieldTargets[1] then
                    ShieldCount = LOUDGETN(SecondaryShieldTargets)
                end
                
                if TertiaryTargets[1] then
                    TertiaryCount = LOUDGETN(TertiaryTargets)
                end

                -- Have a target - plot path to target - Use airthreat vs. mythreat for path
                -- use strikerange to determine point from which to switch into attack mode
				prevposition = LOUDCOPY(GetPlatoonPosition(self))

				paththreat = (oldNumberOfUnitsInPlatoon * 1) + CalculatePlatoonThreat( self, 'Air', categories.ALLUNITS)

                path, reason = self.PlatoonGenerateSafePathToLOUD(aiBrain, self, self.MovementLayer, prevposition, targetposition, paththreat, strikerange )

                if path and PlatoonExists(aiBrain, self) then

                    IssueClearCommands( platoonUnits )
                    
                    newpath = {}
                    count = 0
                    pathsize = LOUDGETN(path)

                    -- build a newpath that gets the platoon to within strikerange
                    -- rather than going all the way to target
                    for waypoint,p in path do
                    
                        destiny = DestinationBetweenPoints( targetposition, prevposition, p, strikerange )

                        if waypoint < pathsize and not destiny then

                            count = count + 1
                            newpath[count] = p

                            prevposition = p
                            
						else
                        
                            if destiny then
                            
                                -- if path breakoff point is not the same as the prevposition - add it to the path
                                if destiny[1] != prevposition[1] and destiny[3] != prevposition[3] then
                            
                                    count = count + 1
                                    newpath[count] = LOUDCOPY(destiny)
                                    
                                end
                                
                            end
                            
                            break
                        end
                    end
                    
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." has path "..repr(path))
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." vs using "..repr(newpath))

                    -- if we have a path - versus direct which will have zero path entries --
                    if newpath[1] then

                        -- move the platoon to within strikerange in formation - the slackvalue is based on the strikerange
                        self.MoveThread = self:ForkThread( self.MovePlatoon, newpath, 'AttackFormation', false, strikerange * .4)

                        -- wait for the movement orders to execute --
                        while PlatoonExists(aiBrain, self) and self.MoveThread and not target.Dead do
                        
                            WaitTicks(1)

                            if target.Dead then

                                loiter = false
                                
                                break
                            end
                        end
                        
                    else
                        WaitTicks(10)   -- let direct move execute for one second
                    end

                    if self.MoveThread then
                        self:KillMoveThread()
                    end

                else

					target = false
                end

                if PlatoonExists(aiBrain, self) and target and not target.Dead then
                
                    -- we assign 30% of the units to attack shields first
                    -- then another 20% of the units to attack AA first
                    -- and another 15% for incidentals
                    -- the remaining 35% will attack the primary first
                    local attackers = GetSquadUnits( self,'Attack')
                    local attackercount = LOUDGETN(attackers)
                    
                    local shield = 1
                    local aa = 1
                    local tertiary = 1

                    local squad = GetPlatoonPosition(self) or false
                    
                    targetposition = GetPosition(target) or false
                    
                    if squad and targetposition then
                    
                        local midpointx = (squad[1]+targetposition[1])/2
                        local midpointy = (squad[2]+targetposition[2])/2
                        local midpointz = (squad[3]+targetposition[3])/2
                    
                        local Direction = import('/lua/utilities.lua').GetDirectionInDegrees( squad, targetposition )

                        -- this gets them moving to a point halfway to the targetposition - hopefully
                        IssueFormMove( GetPlatoonUnits(self), { midpointx, midpointy, midpointz }, 'AttackFormation', Direction )

                        -- sort the bombers by farthest from target -- we'll send them just ahead of the others to get tighter wave integrity
                        LOUDSORT( attackers, function (a,b) return VDist3(GetPosition(a),targetposition) > VDist3(GetPosition(b),targetposition) end )
                   
                        local attackissued = false
                        local attackissuedcount = 0

                        for key,u in attackers do
                    
                            if not u.Dead then
                        
                                IssueClearCommands( {u} )
                            
                                attackissued = false

                                -- first 30% of attacks go for the shields
                                if key < attackercount * .3 and SecondaryShieldTargets[shield] then
                        
                                    if not SecondaryShieldTargets[shield].Dead then
                                        IssueAttack( {u}, SecondaryShieldTargets[shield] )
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end

                                    if shield >= ShieldCount then
                                        shield = 1
                                    else
                                        shield = shield + 1
                                    end 
                                end
                        
                                -- next 20% go for AA units
                                if not attackissued and key <= attackercount * .5 and SecondaryAATargets[aa] then

                                    if not SecondaryAATargets[aa].Dead then
                                        IssueAttack( {u}, SecondaryAATargets[aa] )
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end
                            
                                    if aa >= AACount then
                                        aa = 1
                                    else
                                        aa = aa + 1
                                    end
                                end
                            
                                -- next 15% for tertiary targets --
                                if not attackissued and key <= attackercount * .65 and TertiaryTargets[tertiary] then
                            
                                    if not TertiaryTargets[tertiary].Dead and self:CanAttackTarget('Attack', TertiaryTargets[tertiary]) then
                                        IssueAttack( {u}, TertiaryTargets[tertiary] )
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end
                                
                                    if tertiary >= TertiaryCount then
                                        tertiary = 1
                                    else 
                                        tertiary = tertiary + 1
                                    end
                                end
                        
                                -- all others go for primary
                                if not target.Dead and not attackissued then

                                    IssueAttack( {u}, target )
                                    attackissued = true
                                    attackissuedcount = attackissuedcount + 1
                                end
                    
                                if attackissuedcount > 3 then
                                    WaitTicks(1)
                                    attackissuedcount = 0
                                end
                            end
                        end
                        
                    end
                    
                end
                
			end
            
        end

		-- Attack until target is dead, beyond maxrange or retreat
		while (target and not target.Dead) and PlatoonExists(aiBrain, self) and (VDist3( GetPosition(target), loiterposition ) <= maxrange) do
           
            mythreat = CalculatePlatoonThreat( self, 'Surface', categories.ALLUNITS) * .65   -- use 65% of surface threat
            mythreat = mythreat + CalculatePlatoonThreat( self, 'Air', categories.ALLUNITS)   -- plus any air threat
            
            atthreat = 0
            
            for _, v in GetThreatsAroundPosition( aiBrain, GetPlatoonPosition(self), LOUDFLOOR(IMAPblocks/2), true, threatavoid ) do
            
                atthreat = atthreat + v[3]
                
                if atthreat > mythreat then
                
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." AA threat too high "..atthreat.." - aborting - my threat "..mythreat.." using "..LOUDFLOOR(IMAPblocks/2).." IMAP blocks")
                    
                    return self:SetAIPlan('ReturnToBaseAI',aiBrain)
                end
            end

			WaitTicks(4)
            
            if VDist3( GetPlatoonPosition(self), loiterposition ) > maxrange then
            
                break
                
            end
    
		end

        -- we had a target and target is destroyed
		if target and PlatoonExists(aiBrain, self) then
        
            IssueClearCommands(self)

			target = false
            
            loiter = true
            
            self:MoveToLocation( loiterposition, false )

		end

		-- loiter will be true if we did not find a target
		-- or we couldn't get to the target - we should 
        -- still be guarding the anchorposition
		if loiter then

			WaitTicks(10)
            
		end

        self.UsingTransport = false
        
    end

    if PlatoonExists(aiBrain, self) then
        return self:SetAIPlan('ReturnToBaseAI',aiBrain)
    end
	
end

function AirForceAI_Torpedo_LOUD( self, aiBrain )

    local CalculatePlatoonThreat = CalculatePlatoonThreat
	local GetUnitsAroundPoint = GetUnitsAroundPoint
    local GetPlatoonPosition = GetPlatoonPosition
    local GetPlatoonUnits = GetPlatoonUnits    
    local GetSquadUnits = GetSquadUnits    
    local GetThreatsAroundPosition = GetThreatsAroundPosition
	local PlatoonExists = PlatoonExists	

    
    local LOUDCOPY = LOUDCOPY
    local LOUDFLOOR = LOUDFLOOR
    local LOUDGETN = LOUDGETN
    local LOUDMAX = LOUDMAX
    local LOUDSORT = LOUDSORT
    
    local VDist2Sq = VDist2Sq
    local VDist3 = VDist3
    local WaitTicks = WaitTicks
    
    local SetLoiterPosition = import('/lua/ai/aibehaviors.lua').SetLoiterPosition
    
    local Searchradius = self.PlatoonData.SearchRadius or 200
    
    local missiontime = self.PlatoonData.MissionTime or 600
    local mergelimit = self.PlatoonData.MergeLimit or false
    local PlatoonFormation = self.PlatoonData.UseFormation or 'No Formation'

    local platoonUnits = LOUDCOPY(GetPlatoonUnits(self))

    local categoryList = {}
    local count = 0
    
    if self.PlatoonData.PrioritizedCategories then
	
        for _,v in self.PlatoonData.PrioritizedCategories do
            count = count + 1
            categoryList[count] = v
        end
    end

    local oldNumberOfUnitsInPlatoon = LOUDGETN(platoonUnits)

	for _,v in platoonUnits do 
	
		if not v.Dead then
		
			if v:TestToggleCaps('RULEUTC_StealthToggle') then
				v:SetScriptBit('RULEUTC_StealthToggle', false)
			end
			
			if v:TestToggleCaps('RULEUTC_CloakToggle') then
				v:SetScriptBit('RULEUTC_CloakToggle', false)
			end
		end
	end

    -- setup escorting fighters if any 
	-- pulls out any units in the platoon that are coded as 'guard' in the platoon template
	-- and places them into a seperate platoon with its own behavior
    local guardplatoon = false
	local guardunits = GetSquadUnits( self,'guard')

    if guardunits[1] then
    
        local ident = Random(1,999999)

        guardplatoon = aiBrain:MakePlatoon('GuardPlatoon'..tostring(ident),'none')
        AssignUnitsToPlatoon( aiBrain, guardplatoon, guardunits, 'Attack', 'none')

		guardplatoon.GuardedPlatoon = self  #-- store the handle of the platoon to be guarded to the guardplatoon
        guardplatoon:SetPrioritizedTargetList( 'Attack', categories.HIGHALTAIR * categories.ANTIAIR )

		guardplatoon:SetAIPlan( 'GuardPlatoonAI', aiBrain)
    end

	local DestinationBetweenPoints = function( destination, start, finish, stepsize )

		local steps = LOUDFLOOR( VDist2(start[1], start[3], finish[1], finish[3]) / stepsize ) + 1
	
		local xstep = (start[1] - finish[1]) / steps
		local ystep = (start[3] - finish[3]) / steps

		for i = 0, steps - 1  do
			
			if VDist2Sq(start[1] - (xstep * i), start[3] - (ystep * i), destination[1], destination[3]) < (stepsize * stepsize) then
            
				return { start[1] - (xstep * i), destination[2], start[3] - (ystep * i) }
                
			end
		end	
		
		return false
	end
	
	-- Select a target using priority list and by looping thru range and difficulty multipliers until target is found
	-- occurs to me we could pass the multipliers and difficulties from the platoondata if we wished
	-- force the plan name onto the platoon
	self.PlanName = 'AirForceAI_Torpedo_LOUD'

	self.anchorposition = LOUDCOPY( GetPlatoonPosition(self) )

    local MissionStartTime = LOUDTIME()
    local threatcheckradius = 96
    
    -- block based IMAP threat checks are controlled by this - allowing it to scale properly with map sizes
    local IMAPblocks = LOUDFLOOR(threatcheckradius/ScenarioInfo.IMAPSize)

    local target = false
	local targetposition = false

	local loiter = false
	local loiterposition = false
    
    local mythreat, atthreat
    
    local threatcompare = 'AntiAir'
    local threatavoid = 'AntiAir'
    
    local mult = { 1, 2, 3 }				-- this multiplies the range of the platoon when searching for targets
	local difficulty = { 1.25, 1, 0.72 } 		-- this divides the base threat of the platoon, by deflating it and then increasing it, so that easier targets are selected first
    
    local minrange, maxrange, searchradius, usethreat
    local Rangemult, Threatmult
    
    local SecondaryAATargets, SecondaryShieldTargets, TertiaryTargets
    local AACount, ShieldCount, TertiaryCount

	local path, reason, prevposition, paththreat
    local newpath, pathsize, destiny
    
    strikerange = LOUDMAX( 128, ScenarioInfo.IMAPSize )
	
    while PlatoonExists(aiBrain, self) and (LOUDTIME() - MissionStartTime) <= missiontime do

        -- merge with other AirForceAI_Bomber_LOUD groups with same plan within 80
        if mergelimit and oldNumberOfUnitsInPlatoon < mergelimit then

			if self:MergeWithNearbyPlatoons( aiBrain, 'AirForceAI_Torpedo_LOUD', 100, false, mergelimit) then

				self:SetPlatoonFormationOverride(PlatoonFormation)
				oldNumberOfUnitsInPlatoon = LOUDGETN(GetPlatoonUnits(self))
                
                if ScenarioInfo.PlatoonMergeDialog then
                    LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." merges to "..oldNumberOfUnitsInPlatoon)
                end
			end
        end

        platoonUnits = LOUDCOPY(GetPlatoonUnits(self))

        if (not target or target.Dead) and PlatoonExists(aiBrain, self) then

            mythreat = CalculatePlatoonThreat( self, 'Surface', categories.AIR) * .5   -- use 65% of surface threat for target search 
            mythreat = mythreat + CalculatePlatoonThreat( self, 'Sub', categories.AIR) 
            mythreat = mythreat + CalculatePlatoonThreat( self, 'Air', categories.AIR)   -- plus any air threat

            if mythreat < 5 then
                mythreat = 5
            end
            
            -- the searchradius adapts to the current air ratio
            searchradius = LOUDMAX(Searchradius, (Searchradius *  LOUDMAX(1, (aiBrain.AirRatio/3) * LOUDMIN(1, LOUDGETN(platoonUnits)/15) ) ) )

            usethreat = 0
            minrange = 0

			-- the anchorposition is the start position of the platoon
			-- where the platoon returns to
			-- if it should be drawn away due to distress calls
			if GetPlatoonPosition(self) then
			
				if not loiter then
                
                    loiterposition = SetLoiterPosition( self, aiBrain, self.anchorposition, searchradius, 3, mythreat, 'NAVAL', 'ANTIAIR' )
                    
                    loiter = true

				end
                
			else
				return self:SetAIPlan('ReturnToBaseAI',aiBrain)
			end

            for _,rangemult in mult do

				for _,threatmult in difficulty do
                
                    usethreat = ( mythreat/threatmult ) / rangemult

					target,targetposition = AIFindTargetInRangeInCategoryWithThreatFromPosition(aiBrain, loiterposition, self, 'Attack', minrange, searchradius * rangemult, categoryList, usethreat, threatcompare, threatcheckradius, threatavoid )

					if not PlatoonExists(aiBrain, self) then
						return
					end					

					if target then
                    
                        self.UsingTransport = true  -- general 'busy' flag - prevents merging with other platoons
                        
                        Threatmult = threatmult
						break
					end

				end
                
                -- record Rangemult value for later use --
                Rangemult = rangemult
                
				if target then
					maxrange = searchradius * rangemult
					break
				end

                minrange = searchradius * rangemult
                
                WaitTicks(1)                
            end
        
			if target and not target.Dead and PlatoonExists(aiBrain, self) then
            
                SecondaryAATargets = false
                AACount = 0
                SecondaryShieldTargets = false
                ShieldCount = 0
                TertiaryTargets = false
                TertiaryCount = 0
            
                SecondaryAATargets = GetUnitsAroundPoint( aiBrain, categories.CRUISER, targetposition, threatcheckradius/2, 'Enemy')
                SecondaryShieldTargets = GetUnitsAroundPoint( aiBrain, categories.SHIELD, targetposition, threatcheckradius/2, 'Enemy')
                TertiaryTargets = GetUnitsAroundPoint( aiBrain, categories.ALLUNITS - categories.ANTIAIR - categories.AIR - categories.SHIELD - categories.WALL, targetposition, threatcheckradius/4, 'Enemy')
                
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." with "..LOUDGETN(GetSquadUnits( self,'Attack')).." bombers has target at "..repr(targetposition))
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." target is "..repr(target:GetBlueprint().Description))
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." used RangeMult of "..Rangemult.." and Difficulty of "..Threatmult)
                
                if SecondaryAATargets[1] then
                    AACount = LOUDGETN(SecondaryAATargets)
                end
                
                if SecondaryShieldTargets[1] then
                    ShieldCount = LOUDGETN(SecondaryShieldTargets)
                end
                
                if TertiaryTargets[1] then
                    TertiaryCount = LOUDGETN(TertiaryTargets)
                end

                -- Have a target - plot path to target - Use airthreat vs. mythreat for path
                -- use strikerange to determine point from which to switch into attack mode
                prevposition = LOUDCOPY(GetPlatoonPosition(self))

				paththreat = (oldNumberOfUnitsInPlatoon * 1) + CalculatePlatoonThreat( self, 'Air', categories.ALLUNITS)

                path, reason = self.PlatoonGenerateSafePathToLOUD(aiBrain, self, self.MovementLayer, prevposition, targetposition, paththreat, strikerange )

                if path and PlatoonExists(aiBrain, self) then

                    IssueClearCommands( platoonUnits )
                    
                    newpath = {}
                    count = 0
                    pathsize = LOUDGETN(path)

                    -- build a newpath that gets the platoon to within strikerange
                    -- rather than going all the way to target
                    for waypoint,p in path do
                    
                        destiny = DestinationBetweenPoints( targetposition, prevposition, p, strikerange )

                        if waypoint < pathsize and not destiny then

                            count = count + 1
                            newpath[count] = p

                            prevposition = p
                            
						else
                        
                            if destiny then
                            
                                -- if path breakoff point is not the same as the prevposition - add it to the path
                                if destiny[1] != prevposition[1] and destiny[3] != prevposition[3] then
                            
                                    count = count + 1
                                    newpath[count] = LOUDCOPY(destiny)
                                    
                                end
                                
                            end
                            
                            break
                        end
                    end
                    
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." has path "..repr(path))
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." vs using "..repr(newpath))

                    -- if we have a path - versus direct which will have zero path entries --
                    if newpath[1] then

                        -- move the platoon to within strikerange in formation - the slackvalue is based on the strikerange
                        self.MoveThread = self:ForkThread( self.MovePlatoon, newpath, 'AttackFormation', false, strikerange * .4)

                        -- wait for the movement orders to execute --
                        while PlatoonExists(aiBrain, self) and self.MoveThread and not target.Dead do
                        
                            WaitTicks(1)

                            if target.Dead then

                                loiter = false
                                
                                break
                            end
                        end
                        
                    else
                        WaitTicks(10)   -- let direct move execute for one second
                    end

                    if self.MoveThread then
                        self:KillMoveThread()
                    end

                else

					target = false
                end

                if PlatoonExists(aiBrain, self) and target and not target.Dead then
                
                    -- we assign 30% of the units to attack shields first
                    -- then another 20% of the units to attack AA first
                    -- and another 15% for incidentals
                    -- the remaining 35% will attack the primary first
                    local attackers = GetSquadUnits( self,'Attack')
                    local attackercount = LOUDGETN(attackers)
                    
                    local shield = 1
                    local aa = 1
                    local tertiary = 1

                    local squad = GetPlatoonPosition(self) or false
                    
                    targetposition = GetPosition(target) or false
                    
                    if squad and targetposition then
                    
                        local midpointx = (squad[1]+targetposition[1])/2
                        local midpointy = (squad[2]+targetposition[2])/2
                        local midpointz = (squad[3]+targetposition[3])/2
                    
                        local Direction = import('/lua/utilities.lua').GetDirectionInDegrees( squad, targetposition )

                        -- this gets them moving to a point halfway to the targetposition - hopefully
                        IssueFormMove( GetPlatoonUnits(self), { midpointx, midpointy, midpointz }, 'AttackFormation', Direction )

                        -- sort the bombers by farthest from target -- we'll send them just ahead of the others to get tighter wave integrity
                        LOUDSORT( attackers, function (a,b) return VDist3(GetPosition(a),targetposition) > VDist3(GetPosition(b),targetposition) end )
                   
                        local attackissued = false
                        local attackissuedcount = 0

                        for key,u in attackers do
                    
                            if not u.Dead then
                        
                                IssueClearCommands( {u} )
                            
                                attackissued = false

                                -- first 30% of attacks go for the shields
                                if key < attackercount * .3 and SecondaryShieldTargets[shield] then
                        
                                    if not SecondaryShieldTargets[shield].Dead then
                                        IssueAttack( {u}, SecondaryShieldTargets[shield] )
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end

                                    if shield >= ShieldCount then
                                        shield = 1
                                    else
                                        shield = shield + 1
                                    end 
                                end
                        
                                -- next 20% go for AA units
                                if not attackissued and key <= attackercount * .5 and SecondaryAATargets[aa] then

                                    if not SecondaryAATargets[aa].Dead then
                                        IssueAttack( {u}, SecondaryAATargets[aa] )
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end
                            
                                    if aa >= AACount then
                                        aa = 1
                                    else
                                        aa = aa + 1
                                    end
                                end
                            
                                -- next 15% for tertiary targets --
                                if not attackissued and key <= attackercount * .65 and TertiaryTargets[tertiary] then
                            
                                    if not TertiaryTargets[tertiary].Dead and self:CanAttackTarget('Attack', TertiaryTargets[tertiary]) then
                                        IssueAttack( {u}, TertiaryTargets[tertiary] )
                                        attackissued = true
                                        attackissuedcount = attackissuedcount + 1
                                    end
                                
                                    if tertiary >= TertiaryCount then
                                        tertiary = 1
                                    else 
                                        tertiary = tertiary + 1
                                    end
                                end
                        
                                -- all others go for primary
                                if not target.Dead and not attackissued then

                                    IssueAttack( {u}, target )
                                    attackissued = true
                                    attackissuedcount = attackissuedcount + 1
                                end
                    
                                if attackissuedcount > 3 then
                                    WaitTicks(1)
                                    attackissuedcount = 0
                                end
                            end
                        end
                        
                    end
                    
                end
                
			end
            
        end

		-- Attack until target is dead, beyond maxrange or retreat
		while (target and not target.Dead) and PlatoonExists(aiBrain, self) and (VDist3( GetPosition(target), loiterposition ) <= maxrange) do
           
            mythreat = CalculatePlatoonThreat( self, 'Surface', categories.AIR) * .5   -- use only 1/2 of surface threat
            mythreat = mythreat + CalculatePlatoonThreat( self, 'Sub', categories.AIR)           -- use full SUB threat
            mythreat = mythreat + CalculatePlatoonThreat( self, 'Air', categories.AIR)   -- plus any air threat
            
            atthreat = 0
            
            for _, v in GetThreatsAroundPosition( aiBrain, GetPlatoonPosition(self), IMAPblocks/2, true, threatavoid ) do
            
                atthreat = atthreat + v[3]
                
                if atthreat > mythreat then
                
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." AA threat too high "..atthreat.." - aborting - my threat "..mythreat.." using "..(IMAPblocks/2).." IMAP blocks")
                    
                    return self:SetAIPlan('ReturnToBaseAI',aiBrain)
                end
            end

			WaitTicks(4)
            
            if VDist3( GetPlatoonPosition(self), loiterposition ) > maxrange then
                break
            end
    
		end

        -- we had a target and target is destroyed
		if target and PlatoonExists(aiBrain, self) then
        
            IssueClearCommands(self)

			target = false
            
            loiter = true
            
            self:MoveToLocation( loiterposition, false )

		end

		-- loiter will be true if we did not find a target
		-- or we couldn't get to the target - we should 
        -- still be guarding the anchorposition
		if loiter then
			WaitTicks(10)
		end

        self.UsingTransport = false
        
    end

    if PlatoonExists(aiBrain, self) then
        return self:SetAIPlan('ReturnToBaseAI',aiBrain)
    end
	
end

-- Basic Naval attack logic
-- Creates a list of naval bases, water based mass and combat markers
-- Will use this list as a target list unless there is local contact
function NavalForceAILOUD( self, aiBrain )

	if not GetPlatoonPosition(self) then
        return self:SetAIPlan('ReturnToBaseAI',aiBrain)
    end

    local armyIndex = aiBrain.ArmyIndex

    local LOUDCOPY = LOUDCOPY
	local LOUDGETN = LOUDGETN
    local LOUDINSERT = LOUDINSERT
	local LOUDPARSE = ParseEntityCategory
    
	local GetNumUnitsAroundPoint = GetNumUnitsAroundPoint
    
    local GetPlatoonPosition = GetPlatoonPosition
    local GetPlatoonUnits = GetPlatoonUnits    
    local GetSquadUnits = GetSquadUnits
	local GetUnitsAroundPoint = GetUnitsAroundPoint
	local PlatoonExists = PlatoonExists	
	
	local FindTargetInRange = import('/lua/ai/aiattackutilities.lua').FindTargetInRange
	local AIGetMarkerLocations = import('/lua/ai/aiutilities.lua').AIGetMarkerLocations
	local GetHiPriTargetList = import('/lua/ai/altaiutilities.lua').GetHiPriTargetList
	
	local VDist3 = VDist3
    
    local GetTerrainHeight = GetTerrainHeight
    local GetSurfaceHeight = GetSurfaceHeight

    local data = self.PlatoonData

	local bAggroMove = false        -- Dont move flotillas aggressively - use formation
    
	local MergeLimit = data.MergeLimit or 60
    local MissionStartTime = self.CreationTime			-- when the mission began (creation of the platoon)
	local MissionTime = data.MissionTime or 1200		-- how long platoon will operate before RTB
    local SearchRadius = data.SearchRadius or 350		-- used to locate local targets to attack
	local PlatoonFormation = data.UseFormation or 'GrowthFormation'

    local categoryList = {}
    local count = 0

    if data.PrioritizedCategories then
	
        for _,v in data.PrioritizedCategories do

            count = count + 1
            categoryList[count] = LOUDPARSE( v )
            
        end
    else
        
        count = count + 1
		categoryList[count] = categories.NAVAL
	end

    --self:SetPrioritizedTargetList( 'Attack', categoryList )

    local path, reason, pathlength
    local target, targetposition
	local destination, destinationpath

	local maxRange, selectedWeaponArc, turretPitch = import('/lua/ai/aiattackutilities.lua').GetNavalPlatoonMaxRange(aiBrain, self)

	local platoonUnits = GetPlatoonUnits(self)
	local oldNumberOfUnitsInPlatoon = LOUDGETN(platoonUnits)

	local OriginalThreat = CalculatePlatoonThreat( self, 'Overall', categories.ALLUNITS)

	local navalmarkers = ScenarioInfo['Naval Area'] or AIGetMarkerLocations('Naval Area')
	local combatmarkers = ScenarioInfo['Combat Zone'] or AIGetMarkerLocations('Combat Zone')
	local massmarkers = ScenarioInfo['Mass'] or AIGetMarkerLocations('Mass')

	-- make a copy of the naval base markers
	local navalAreas = LOUDCOPY(navalmarkers)

	-- add any combat zones that may be in the water
	for k,v in combatmarkers do
		
		if GetTerrainHeight(v.Position[1], v.Position[3]) < GetSurfaceHeight(v.Position[1], v.Position[3]) then
			LOUDINSERT(navalAreas, v)
		end
	end

	-- add any mass points that might be in the water or near a water path node
	for k,v in massmarkers do
		
		if GetTerrainHeight(v.Position[1], v.Position[3]) < GetSurfaceHeight(v.Position[1], v.Position[3]) then
		
			LOUDINSERT(navalAreas, v)
		else
            -- if platoon capable of bombardment --
            if maxRange then
            
                local nearwater = import('/lua/ai/aiutilities.lua').AIGetMarkersAroundLocation( aiBrain, 'Water Path Node', v.Position, maxRange * .25 )
			
                if nearwater[1] then
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." Mass point in range "..(maxRange *.25).." of "..repr(v.Position).. " Adding "..repr(nearwater[1]))
                    LOUDINSERT(navalAreas, nearwater[1])
                end
			end
		end
	end
	
	navalmarkers = nil
	combatmarkers = nil
	massmarkers = nil

	-- remove any points within 100 of ourselves
	-- or 100 of any Base we may have
	for k,v in navalAreas do
	
		if VDist3( v.Position, GetPlatoonPosition(self) ) < 100 then
			navalAreas[k] = nil
		else
		
			for _,base in aiBrain.BuilderManagers do
			
				if VDist3( v.Position, base.Position ) < 100 then
				
					navalAreas[k] = nil
					break
				end
			end
		end			
	end

	-- rebuild the table
	navalAreas = aiBrain:RebuildTable(navalAreas)

	local function StopAttack( self )

		self:Stop()
		
		destination = false
		destinationpath = false
		
		target = false
		targetposition = false
	end

	local EndMissionTime = LOUDTIME() + MissionTime

	local mythreat, targetlist, targetvalue
	local sthreat, ethreat, ecovalue, milvalue, value
	local path, reason, pathlength, distancefactor
	local waitneeded
	local updatedtargetposition
	
	-- force the plan name
	self.PlanName = 'NavalForceAILOUD'

    while PlatoonExists(aiBrain, self) do

		target = false
        targetposition = false
		
		mythreat = CalculatePlatoonThreat( self, 'Overall', categories.ALLUNITS)
		
		--LOG("*AI DEBUG "..aiBrain.Nickname.." NFAI "..self.BuilderName.." seeks local target")

		-- Locate LOCAL targets in the searchRadius range using the attackpriority list - they must also be on the same layer
        -- and there must be an 'attack' squad
        if GetSquadUnits( self,'Attack') then
            target, targetposition = FindTargetInRange( self, aiBrain, 'Attack', SearchRadius, categoryList, true )
        else
            LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." has no attack squad - no target")
        end

		-- if target, insure that it's in water and set the destination -- issue attack orders --
        if target and not target.Dead then

			-- if the target is in the water
			if GetTerrainHeight(targetposition[1], targetposition[3]) < GetSurfaceHeight(targetposition[1], targetposition[3]) - 1 then

				destination = LOUDCOPY(targetposition)

				if self.MoveThread then
					self:KillMoveThread()
				end
				
				self:Stop()
--[[
				-- Issue Dive(surface) Order to all SERAPHIM Submersible Units
				for _,v in EntityCategoryFilterDown( (categories.SERAPHIM * categories.SUBMERSIBLE) - categories.NUKE, GetPlatoonUnits(self)) do
					
					if (not v.Dead) and (not v.CacheLayer == 'Water') then
						IssueDive( {v} )
					end
				end
--]]

                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." Issues attack in NavalForceAI")
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." target is "..repr(target:GetBlueprint().Description) )
                
				-- would direction help here ? --
                if GetSquadUnits( self,'Attack') then
                    IssueFormAttack( GetSquadUnits( self,'Attack'), target, 'AttackFormation', 0)
                end
                
                if GetSquadUnits( self,'Artillery') then
                    IssueFormAttack( GetSquadUnits( self,'Artillery'), target, 'AttackFormation', 0)
                end
				
				local guardset = false

				-- Make sure any units in platoon which are guards are actually guarding attack units
				for _,v in GetSquadUnits( self,'Attack') do
					
					if v and not v.Dead then
						
						-- if there are Guards - and we are not set to guard --
						if GetSquadUnits( self,'Guard') and not guardset then
							
							-- issue a guard order to each guard unit to the first attack unit we find --
							for _,m in GetSquadUnits( self,'Guard') do
                            
                                if not IsUnitState( m, 'Guarding') then
								
                                    if m and not m.Dead then

                                        --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." Issues guard in NavalForceAI")
                                    
                                        IssueGuard( GetSquadUnits( self,'Guard'), v )
                                    
                                        guardset = true
                                    end
                                end
							end
						end
						
						break
					end
				end	
			else
			
				target = false
			end
        else
		
			target = false
		end

		-- if no target and no movement orders -- use HiPri list or random Naval marker
		-- issue movement orders -- if list is empty RTB instead --
        if not target and not self.MoveThread then
            
            --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." NO Target - seeking HiPri target") 
		
			-- get HiPri list
			targetlist = GetHiPriTargetList( aiBrain, GetPlatoonPosition(self) )

			targetvalue = 0

            mythreat = CalculatePlatoonThreat( self, 'Overall', categories.ALLUNITS)
	
			LOUDSORT(targetlist, function(a,b) return a.Distance < b.Distance end )

			-- get a HiPri target from the targetlist -- set as destination
			for _,Target in targetlist do
			
				if PlatoonExists( aiBrain, self ) then
				
					if Target.Type != 'StructuresNotMex' and Target.Type != 'Commander' and Target.Type != 'Naval' then
				
						continue	-- allow only the target types listed above
					end

					if GetSurfaceHeight(Target.Position[1], Target.Position[3]) - 2 < GetTerrainHeight(Target.Position[1], Target.Position[3]) then
				
						continue    -- skip targets that are NOT in or on water
					end					

					-- get basic threat types at position
					sthreat = Target.Threats.Sur + Target.Threats.Sub
					ethreat = Target.Threats.Eco

					if sthreat < 1 then
						sthreat = 1
					end

					if ethreat < 1 then
						ethreat = 1
					end

					ecovalue = ethreat/mythreat

					if ecovalue > 6.0 then
					
						ecovalue = 6.0
						
					elseif ecovalue < 0.5 then
					
						ecovalue = 0.5
                    end

					-- target value is relative to the platoons strength vs. the targets strength
					-- cap the value at 3 to limit chasing worthless targets
					-- anything stronger than us gets valued even lower to avoid going after targets too strong
					milvalue =  (mythreat/sthreat) 

					if milvalue > 3.0 then 
					
						milvalue = 3.0
						ecovalue = ecovalue * 2

					elseif milvalue < 1 then
					
						milvalue = milvalue * milvalue
						ecovalue = ecovalue * .5
					end

					-- now add in the economic value of the target
					-- this will make targets that we are stronger than, that have eco value, more valuable
					-- and targets that have overpowering military value made even less valuable
					-- which should focus the platoon on economic goals versus ground units
					value = ecovalue * milvalue

					-- ignore targets we are still too weak against
					if value < 1.0 then
					
						--LOG("*AI DEBUG Value too low")
						continue
					else
						--LOG("*AI DEBUG Values are Eco "..repr(ecovalue).." Mil is "..repr(milvalue))
					end

					-- naval platoons must be able to get to the position
					path, reason, pathlength = self.PlatoonGenerateSafePathToLOUD( aiBrain, self, self.MovementLayer, GetPlatoonPosition(self), Target.Position, mythreat, 250 )

					-- if we have a path to the target and its value is highest one so far then set destination
					-- and store the targetvalue for comparison 
					if path and PlatoonExists( aiBrain, self ) then

						distancefactor = aiBrain.dist_comp/Target.Distance   -- makes closer targets more valuable

						if VDist3( GetPlatoonPosition(self), Target.Position) < 500 then -- and very close targets even more valuable
						
							distancefactor = distancefactor * 2
						end
					
						-- store the destination of the most valuable target
						if (value * distancefactor) > targetvalue then
						
							targetvalue = (value * distancefactor)
							destination = LOUDCOPY(Target.Position)
							destinationpath = LOUDCOPY( path )
						end
					end
				
					WaitTicks(1) -- check next target --
				else
				
					destination = false
					break
				end
			end

			-- if no HiPri target then try random NAVAL MARKER and set that as the destinatin but with TARGET == false
			-- that condition would get the platoon moving towards the destination but still checking along the way
			-- for targets 
			if PlatoonExists( aiBrain,self) and (not destination) then
			
				-- rebuild the table in case some points have been used
				navalAreas = aiBrain:RebuildTable(navalAreas)
				
				if navalAreas[1] then
				
					for k,v in RandomIter(navalAreas) do

						-- this is essentially the AVOIDS BASES function
						-- if we find an allied naval base there we'll just skip this BUT we'll keep it for later checking
						if GetNumUnitsAroundPoint( aiBrain, categories.NAVAL * categories.STRUCTURE, v.Position, 75, 'Ally' ) > 0 then
						
							--LOG("*AI DEBUG "..aiBrain.Nickname.." NFAI "..self.BuilderName.." - position "..repr(v.Position).." finds "..GetNumUnitsAroundPoint( aiBrain, categories.NAVAL * categories.STRUCTURE, v.Position, 75, 'Ally' ).." allied units")
							navalAreas[k] = nil
							continue
						end
						
						if PlatoonExists(aiBrain, self) then

							-- get a path to the Position
							path, reason = self.PlatoonGenerateSafePathToLOUD( aiBrain, self, self.MovementLayer, GetPlatoonPosition(self), v.Position, mythreat, 250 )

							-- remove this entry from the platoons list since are either going there or we cant there
							-- and we dont want to bounce around - if we've visited a site remove it from the list so 
							-- if we're just cruising around for any great length of time we'll finally run out of 
							-- choices and the will trigger a RTB for the platoon !  Aha...me smart.
							navalAreas[k] = nil

							if not path then
								continue
							end

							-- set a destination but note the FALSE on the target -- we'll start moving but we'll then cycle back 
							-- and keep looking for targets --
							destination = LOUDCOPY( v.Position )
							destinationpath = LOUDCOPY( path )

							target = false

							--LOG("*AI DEBUG "..aiBrain.Nickname.." NFAI "..self.BuilderName.." gets random marker at "..repr(destination))
						end
					
						break
					end
				end
			end

			-- if still nothing - RTB --
			if not destination then
			
				--LOG("*AI DEBUG "..aiBrain.Nickname.." NFAI "..self.BuilderName.." exhausts waypoint list - RTB ")
				return self:SetAIPlan('ReturnToBaseAI',aiBrain)
			end
            
            --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." NO Target - using waypoint at "..repr(destination))

			-- Issue Dive Order to ALL SERAPHIM Submersible Units -- that are not already submerged
			for _,v in GetPlatoonUnits(self) do
			
				if v.Dead or v.CacheLayer == 'Sub' then
					continue
				end

				if LOUDENTITY( categories.SERAPHIM * categories.SUBMERSIBLE, v ) then
				
					IssueDive( {v} )
				end
			end

			-- use the destinationpath to plot movement to the target
			if PlatoonExists( aiBrain, self ) and destinationpath then
            
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." begins path "..repr(destinationpath))
			
				self:Stop()

				self.MoveThread = self:ForkThread( self.MovePlatoon, destinationpath, PlatoonFormation, bAggroMove, 28 )
				
				WaitTicks(30)
			else
			
				--LOG("*AI DEBUG "..aiBrain.Nickname.." NAVALFORCEAI "..self.BuilderName.." has no path")
				
				target = false
			end
			
		end

		-- if given movement (assumes we have NO target) - watch progress towards destination
		if self.MoveThread then

			-- if we're not moving or we're close to destination --
			if (not self.WaypointCallback) or (not destination) then
			
				if self.MoveThread then
					self:KillMoveThread()
				end 
                
                --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." Stops moving" )

				IssueClearCommands( GetPlatoonUnits(self) )

				self:SetPlatoonFormationOverride(PlatoonFormation)
				
				destination = false
				destinationpath = false

				-- Build in movement delay if platoon has carriers and air units nearby
				-- Account for the surfacing and diving of Atlantis or other submersible air carriers
				waitneeded = false

				-- bring submersibles to the surface if there are friendly air units
				for k,v in GetPlatoonUnits(self) do
					
					if not v.Dead and LOUDENTITY ( categories.AIRSTAGINGPLATFORM, v) then

						if GetOwnUnitsAroundPoint( aiBrain, categories.AIR * categories.MOBILE - categories.TRANSPORTFOCUS, GetPosition(v), 32) then
							
							waitneeded = true

							if (not v.Dead) and v.CacheLayer == 'Sub' then
								IssueDive( {v} )
							end
						end
					end
				end

				-- if friendly air units in area -- wait 40 seconds --
				-- then submerge them
				if waitneeded then
					
					--LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." NFAI on Air Wait")
					
					WaitTicks(300)
					
					waitneeded = false

					if PlatoonExists( aiBrain, self ) then
					
						for k,v in GetPlatoonUnits(self) do

							if not v.Dead and LOUDENTITY( categories.AIRSTAGINGPLATFORM * categories.SUBMERSIBLE, v) then
								IssueDive( {v} )	-- submerge Atlantis
							end
						end
					end
				end

				target = false
			else
			
				WaitTicks(50)
			end
        end

		-- loop here while prosecuting a target -- 
		while target and PlatoonExists(aiBrain, self) do
        
			--LOG("*AI DEBUG "..aiBrain.Nickname.." NFAI "..self.BuilderName.." in combat")        

			updatedtargetposition = false

			if not target.Dead then
				updatedtargetposition = LOUDCOPY(GetPosition(target))
			end

			if target.Dead or (not updatedtargetposition) or VDist3( updatedtargetposition, GetPlatoonPosition(self) ) > SearchRadius * 1.25 then
				
				if target and updatedtargetposition and VDist3( updatedtargetposition, GetPlatoonPosition(self) ) > SearchRadius * 1.25 then
					--LOG("*AI DEBUG "..aiBrain.Nickname.." NFAI "..self.BuilderName.." target is beyond 1.25x radius "..repr(searchRadius))
				end

				StopAttack(self)
				
				target = false
				break
			end

			if (not target.Dead) and updatedtargetposition and updatedtargetposition != targetposition then
			
				if GetSquadUnits( self,'Attack') then

                    --LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." target "..repr(target:GetBlueprint().Description).." moved - retargeting")
			
					targetposition = LOUDCOPY(updatedtargetposition)
                    
                    if GetSquadUnits( self,'Attack') then
                    	IssueAggressiveMove( GetSquadUnits( self,'Attack'), targetposition )
                    end
                    
                    if GetSquadUnits( self,'Artillery') then
                        IssueAttack( GetSquadUnits( self,'Artillery'), target )
                    end
				else
				
					--LOG("*AI DEBUG "..aiBrain.Nickname.." NFAI "..self.BuilderName.." all attack units dead - fight over")
					
					target = false
					
					if self.MoveThread then
						self:KillMoveThread()
					end
					
					break
				end
			end

			mythreat = CalculatePlatoonThreat( self, 'Overall', categories.ALLUNITS)

			if PlatoonExists( aiBrain, self) and mythreat <= (OriginalThreat * .40) then
			
				break	--self.MergeIntoNearbyPlatoons( self, aiBrain, 'AttackForceAI', 100, false)
				
				--return self:SetAIPlan('ReturnToBaseAI',aiBrain)
				
			end
			
			if target.dead then
			
				break
				
			end

			WaitTicks(60)

		end

		-- check mission timer for RTB
		if LOUDTIME() > EndMissionTime then
		
			--LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." NFAI Mission Time expires")
			return self:SetAIPlan('ReturnToBaseAI',aiBrain)
		end
		
		-- if there is a mergelimit (we allow merging platoons)
        if PlatoonExists( aiBrain, self) and MergeLimit then
		
			-- if weak try and join nearby platoon --
			if mythreat <= (OriginalThreat * .40) then
		
				self:MergeIntoNearbyPlatoons( aiBrain, 'AttackForceAI', 100, false)
			
				-- leftovers will RTB
				return self:SetAIPlan('ReturnToBaseAI',aiBrain)

			end
			
			-- otherwise try and grab other smaller platoons --
            if self:MergeWithNearbyPlatoons( aiBrain, 'NavalForceAILOUD', 100, false, MergeLimit) then

                platoonUnits = GetPlatoonUnits(self)
				
                local numberOfUnitsInPlatoon = LOUDGETN(platoonUnits)

				-- if we have a change in the number of units --
                if (oldNumberOfUnitsInPlatoon != numberOfUnitsInPlatoon) then
					
					if self.MoveThread then
						self:KillMoveThread()
					end 

                    StopAttack(self)

					-- reform the platoon --
                    self:SetPlatoonFormationOverride(PlatoonFormation)
                end

                oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon

                OriginalThreat = CalculatePlatoonThreat( self, 'Overall', categories.ALLUNITS)
            end
        end
    end
end

-- NAVAL BOMBARDMENT --
function NavalBombardAILOUD( self, aiBrain )

    local GetPlatoonPosition = GetPlatoonPosition
    local GetPlatoonUnits = GetPlatoonUnits    
    
	if not GetPlatoonPosition(self) then
	
        return self:SetAIPlan('ReturnToBaseAI',aiBrain)
		
    end

    local armyIndex = aiBrain.ArmyIndex

	local LOUDGETN = LOUDGETN
	local LOUDPARSE = ParseEntityCategory
	
	local FindTargetInRange = import('/lua/ai/aiattackutilities.lua').FindTargetInRange
	local AIGetMarkerLocations = import('/lua/ai/aiutilities.lua').AIGetMarkerLocations
	local GetHiPriTargetList = import('/lua/ai/altaiutilities.lua').GetHiPriTargetList
    
	local GetNumUnitsAroundPoint = GetNumUnitsAroundPoint
	local GetUnitsAroundPoint = GetUnitsAroundPoint
	
	local VDist3 = VDist3

    local data = self.PlatoonData

	local bAggroMove = true
	local MergeLimit = data.MergeLimit or 60
    local MissionStartTime = self.CreationTime			-- when the mission began (creation of the platoon)
	local MissionTime = data.MissionTime or 1200		-- how long platoon will operate before RTB
    local SearchRadius = data.SearchRadius or 150
	local PlatoonFormation = data.UseFormation or 'GrowthFormation'

    local categoryList = {}
    local count = 0

    if data.PrioritizedCategories then
	
        for _,v in data.PrioritizedCategories do
		
            count = count + 1
            categoryList[count] = LOUDPARSE( v )
			
        end
		
    else
	
		count = count + 1
        categoryList[count] = categories.NAVAL
		
	end

    self:SetPrioritizedTargetList( 'Attack', categoryList )

    local path, reason, pathlength
    local target, targetposition
	local destination

	local platoonUnits = GetPlatoonUnits(self)
	local oldNumberOfUnitsInPlatoon = LOUDGETN(platoonUnits)

	local OriginalThreat = CalculatePlatoonThreat( self,'Overall', categories.ALLUNITS)

	-- get all the possible naval markers that we want the bombardment platoon to operate from
	local navalmarkers = ScenarioInfo['Naval Area'] or AIGetMarkerLocations('Naval Area')
	-- include naval links
	local linkmarkers = ScenarioInfo['Naval Link'] or AIGetMarkerLocations('Naval Link')
	local navalmarkers = table.cat( navalmarkers, linkmarkers )
	-- and water nodes
	local nodemarkers = ScenarioInfo['Water Path Node'] or AIGetMarkerLocations('Water Path Node')
	local navalmarkers = table.cat( navalmarkers, nodemarkers )

	-- make a copy of the naval base markers
	local navalAreas = LOUDCOPY(navalmarkers)

	navalmarkers = nil
	linkmarkers = nil
	nodemarkers = nil

	local function StopAttack( self )

		self:Stop()
		
		destination = false
		destinationpath = false
		
		target = false
		targetposition = false

	end

	local EndMissionTime = LOUDTIME() + MissionTime

	local mythreat, targetlist, targetvalue, maxRange
	local sthreat, ethreat, ecovalue, milvalue, value
	local path, reason, pathlength, distancefactor
	local previousbombardmentposition
	local updatedtargetposition
	
	-- force the plan name 
	self.PlanName = 'NavalBombardAILOUD'	
	
	LOG("*AI DEBUG "..aiBrain.Nickname.." BFAI "..self.BuilderName.." begins")	

    while PlatoonExists(aiBrain, self) do

		target = false
		
		mythreat = CalculatePlatoonThreat( self, 'Overall', categories.ALLUNITS)
		maxRange = import('/lua/ai/aiattackutilities.lua').GetNavalPlatoonMaxRange(aiBrain, self)
		
		-- platoon no longer qualifies for bombardment
		if maxRange < 100 then
			return self:SetAIPlan('ReturnToBaseAI',aiBrain)		
		end
		
		if not self.MoveThread then
			target, targetposition = FindTargetInRange( self, aiBrain, 'Artillery', maxRange, categoryList, true )
		end

		-- if target -- issue attack orders -- no need to move
        if target and not target.Dead then
		
			previousbombardmentposition = false

			LOG("*AI DEBUG "..aiBrain.Nickname.." BFAI "..self.BuilderName.." finds target "..repr( target:GetBlueprint().Description ).." in bombard range")
            
            local ARTILLERY = GetSquadUnits( self,'Artillery' )
            local GUARDS = GetSquadUnits( self, 'Guard' )
			
			-- order the artillery units to form an attack on the target
			IssueFormAttack( ARTILLERY, target, 'LOUDClusterFormation', 0)

			-- Make sure any units in platoon which are guards are actually guarding
			-- loop thru all the artillery units and clear the guarded marks
			for _,v in ARTILLERY do
				
				if v and not v.Dead then

					v.guardset = nil
					
					-- if there are Guards - and unit is not guarded --
					if GUARDS[1] and not v.guardset then
						
						-- loop thru all guards and issue guard orders
						for _,m in GUARDS do
							
							if m and not m.Dead then
							
								if not m.guardset then
							
									IssueGuard( {m}, v )
									
									m.guardset = true
									v.guardset = true
									
									break
									
								end
								
							end
							
						end
						
					end
                    
                    local SUPPORTS = GetSquadUnits( self, 'Support' )
					
					-- if there are support units - and unit is not guarded --
					if SUPPORTS[1] and not v.guardset then
						
						-- loop thru all guards and issue guard orders
						for _,m in SUPPORTS do
							
							if m and not m.Dead then
							
								if not m.guardset then
							
									IssueGuard( {m}, v )
									
									m.guardset = true
									v.guardset = true
									
									break
								end
							end
						end
					end					
				end
			end
			
			-- at this point all the artillery units should be guarded --
			-- so we'll now clear all the guarding marks
			for _,v in self:GetPlatoonUnits() do
			
				v.guardset = nil
			end
			
        else
		
			target = false
		end

		-- if no target and no movement orders -- use HiPri list
		-- issue movement orders -- if list is empty RTB instead --
        if not target and not self.MoveThread then
		
			-- get HiPri list
			targetlist = GetHiPriTargetList( aiBrain, GetPlatoonPosition(self) )

			targetvalue = 0

            mythreat = CalculatePlatoonThreat( self,'Overall', categories.ALLUNITS)
	
			LOUDSORT( targetlist, function(a,b) return a.Distance < b.Distance end )

			-- get a HiPri target from the targetlist
			for _,Target in targetlist do
			
				if PlatoonExists( aiBrain, self ) then
				
					if Target.Type != 'Economy' and Target.Type != 'StructuresNotMex' and Target.Type != 'Commander' and Target.Type != 'Naval' then
				
						continue	-- allow only the target types listed above
					
					end
					
					if LOUDEQUAL(Target.Position, previousbombardmentposition) then
					
						continue	-- dont pick the same location as last time
						
					end

					-- sort the bombardment markers to see if any are within range of the Target.Position
					LOUDSORT( navalAreas, function(a,b) return VDist3(a.Position, Target.Position) < VDist3(b.Position, Target.Position) end )
					
					if VDist3( navalAreas[1].Position, Target.Position ) > maxRange then
				
						continue    -- the closest one is outside the range - so onto next HiPri
					
					end					

					-- get basic threat types at position
					sthreat = Target.Threats.Sur + Target.Threats.Sub
					ethreat = Target.Threats.Eco

					if sthreat < 1 then
					
						sthreat = 1
						
					end

					if ethreat < 1 then
					
						ethreat = 1
						
					end

					ecovalue = ethreat/mythreat

					if ecovalue > 10.0 then
					
						ecovalue = 10.0
						
					elseif ecovalue < 1 then
					
						ecovalue = 0.5
						
					elseif ecovalue < 2 then
					
						ecovalue = 2.0
						
					end

					-- target value is relative to the platoons strength vs. the targets strength
					-- cap the value at 3 to limit chasing worthless targets
					-- anything stronger than us gets valued even lower to avoid going after targets too strong
					milvalue =  (mythreat/sthreat) 

					if milvalue > 0.25 then 
					
						milvalue = 1.0

					-- for BOMBARDMENT we're not much concerned with enemy surface value
					-- so we'll accept relatively low values as nominal
					elseif milvalue < 0.25 then
					
						milvalue = .25
						ecovalue = ecovalue * .75
						
					end

					-- now add in the economic value of the target
					-- this will make targets that we are stronger than, that have eco value, more valuable
					-- and targets that have overpowering military value made even less valuable
					-- which should focus the platoon on economic goals versus ground units
					value = ecovalue * milvalue

					-- ignore targets we are still too weak against
					if value < 1.0 then
					
						continue
						
					end

					-- naval platoons must be able to get to the closest bombardment position
					path, reason, pathlength = self.PlatoonGenerateSafePathToLOUD( aiBrain, self, self.MovementLayer, GetPlatoonPosition(self), navalAreas[1].Position, mythreat, 250 )

					-- if we have a path to the bombardment position and its value is highest one so far then set destination
					-- and store the targetvalue for comparison 
					if path and PlatoonExists( aiBrain, self ) then

						distancefactor = aiBrain.dist_comp/Target.Distance   -- makes closer targets more valuable

						if VDist3( GetPlatoonPosition(self), Target.Position) < 400 then -- and very close targets even more valuable
						
							distancefactor = distancefactor + 50
							
						end
					
						-- store the destination of the most valuable target
						if (value * distancefactor) > targetvalue then
						
							targetvalue = (value * distancefactor)
							destination = LOUDCOPY( navalAreas[1].Position )
							destinationpath = LOUDCOPY( path )

						end
					end
				
					WaitTicks(1) -- check next HiPri target --
					
				else
				
					destination = false
					break
					
				end
				
			end

			-- if no HiPri target then RTB -
			if PlatoonExists( aiBrain,self) and (not destination) then
			
				LOG("*AI DEBUG "..aiBrain.Nickname.." NBFAI "..self.BuilderName.." no bombardment position - RTB ")
				
				return self:SetAIPlan('ReturnToBaseAI',aiBrain)
				
			else
			
				LOG("*AI DEBUG "..aiBrain.Nickname.." NBFAI selects bombardment position at "..repr(destination))
				
				-- store the selected bombardment position
				previousbombardmentposition = LOUDCOPY(destination)
				
			end

			-- Issue Dive Order to ALL SERAPHIM Submersible Units -- that are not already submerged
			for _,v in GetPlatoonUnits(self) do
			
				if v.Dead or v.CacheLayer == 'Sub' then
					continue
				end

				if LOUDENTITY( categories.SERAPHIM * categories.SUBMERSIBLE, v ) then
				
					IssueDive( {v} )
					
				end
				
			end

			-- we should have a path to a bombardment position at this point --
			-- so issue movement orders --
			if PlatoonExists( aiBrain, self ) and destinationpath then
			
				self:Stop()
			
				self.MoveThread = self:ForkThread( self.MovePlatoon, destinationpath, PlatoonFormation, false, 28 )
				
				-- this pause is here for two reasons -
				-- first: to allow the platoon to get moving
				-- second: to allow the WayPointCallback to be set up
				WaitTicks(30)
				
			else
			
				LOG("*AI DEBUG "..aiBrain.Nickname.." BFAI "..self.BuilderName.." has no path")
				
				target = false
				
			end
			
		end

		-- if moving then watch progress towards destination
		if self.MoveThread then

			-- if we're not moving or we're close to destination --
			if (not self.WaypointCallback) or (not destination) then
			
				if self.MoveThread then

					self:KillMoveThread()
					
				end 
			
				IssueClearCommands( GetPlatoonUnits(self) )

				self:SetPlatoonFormationOverride(PlatoonFormation)
				
				destination = false
				destinationpath = false

			end
			
        end

		-- loop here until target dies or moves out of range -- 
		-- wait 4 seconds between target checks --
		while target and PlatoonExists(aiBrain, self) do

			updatedtargetposition = false

			if not target.Dead then
			
				updatedtargetposition = LOUDCOPY(GetPosition(target))
				
			end

			if target.Dead or (not updatedtargetposition) or VDist3( updatedtargetposition, GetPlatoonPosition(self) ) > maxRange then
			
				-- if the target is still alive but it's moved out of range - let me know
				if target and updatedtargetposition and VDist3( updatedtargetposition, GetPlatoonPosition(self) ) > maxRange then
				
					LOG("*AI DEBUG "..aiBrain.Nickname.." BFAI "..self.BuilderName.." target is beyond radius "..repr(maxRange))
					
				end

				StopAttack(self)
				
				target = false
				
				break
				
			end

			mythreat = CalculatePlatoonThreat( self, 'Overall', categories.ALLUNITS)

			if PlatoonExists( aiBrain, self) and mythreat <= (OriginalThreat * .40) then
			
				self.MergeIntoNearbyPlatoons( self, aiBrain, 'BombardForceAI', 100, false)
				
				return self:SetAIPlan('ReturnToBaseAI',aiBrain)
			end

			WaitTicks(40)
			
			LOG("*AI DEBUG "..aiBrain.Nickname.." BFAI "..self.BuilderName.." engaging target "..repr(target.Dead).." "..repr( target:GetBlueprint().Description ).." in bombard range "..maxRange.." at "..VDist3( updatedtargetposition, GetPlatoonPosition(self)) )
		end

		-- check mission timer for RTB
		if LOUDTIME() > EndMissionTime then
		
			LOG("*AI DEBUG "..aiBrain.Nickname.." "..self.BuilderName.." Mission Time expires")
			
			return self:SetAIPlan('ReturnToBaseAI',aiBrain)
			
		end
		
		-- if there is a mergelimit (we allow merging platoons)
        if PlatoonExists( aiBrain, self) and MergeLimit then
		
			-- if weak try and join nearby platoon --
			if mythreat <= (OriginalThreat * .40) then
		
				self.MergeIntoNearbyPlatoons( self, aiBrain, 'BombardForceAI', 100, false)
			
				-- leftovers will RTB
				return self:SetAIPlan('ReturnToBaseAI',aiBrain)
			
			end
			
			-- otherwise try and grab other smaller platoons --
            if self.MergeWithNearbyPlatoons( self, aiBrain, 'NavalBombardAILOUD', 100, false, MergeLimit) then

                platoonUnits = GetPlatoonUnits(self)
				
                local numberOfUnitsInPlatoon = LOUDGETN(platoonUnits)

				-- if we have a change in the number of units --
                if (oldNumberOfUnitsInPlatoon != numberOfUnitsInPlatoon) then
					
					if self.MoveThread then
					
						self:KillMoveThread()
						
					end 

                    StopAttack(self)

					-- reform the platoon --
                    self:SetPlatoonFormationOverride(PlatoonFormation)
					
                end

                oldNumberOfUnitsInPlatoon = numberOfUnitsInPlatoon

                OriginalThreat = CalculatePlatoonThreat( self, 'Overall', categories.ALLUNITS)
				
            end
			
        end

		-- wait 4.5 seconds
		WaitTicks(46)
    end
end


-- This function will transfer engineers to a base which does not have one of that specific type
-- and has no means of making one -- weights towards counted and primary bases first
function EngineerTransferAI( self, aiBrain )

	local eng = GetPlatoonUnits(self)[1]
	
	local possibles = {}
	local counter = 0
	
	local Eng_Cat = self.PlatoonData.TransferCategory
	local Eng_Type = self.PlatoonData.TransferType
    
    local BM = aiBrain.BuilderManagers
    
    local engineerManager, factoryManager, numUnits, structurecount, factorycount, capcheck

	-- scan all bases and transfer if they dont have their maximum already
	for k,v in BM do
	
		-- make a list of possible bases
		-- base must have an ACTIVE EM -- ignore MAIN & the base this engineer is presently assigned to
		if v.EngineerManager.Active and (k != 'MAIN' and k != eng.LocationType) then
		
			engineerManager = v.EngineerManager
			factoryManager = v.FactoryManager
            
			numUnits = EntityCategoryCount( Eng_Cat, engineerManager.EngineerList )
            
			structurecount = LOUDGETN(aiBrain:GetUnitsAroundPoint( categories.STRUCTURE - categories.WALL, v.Position, 40, 'Ally'))
			factorycount = LOUDGETN(factoryManager.FactoryList)
			
			capCheck = v.BaseSettings.EngineerCount[Eng_Type] or 1
            
            -- use maximum amount but never let it go below the base value due to AI multiplier being less than 1
            capCheck = LOUDMAX(capCheck, LOUDFLOOR(capCheck * (aiBrain.CheatValue) * aiBrain.CheatValue))
			
			if aiBrain.StartingUnitCap >= 1000 then
			
				capCheck = capCheck + 1
				
			end
			
			-- if base has less than maximum allowed engineers and there are structures at that position
			-- base must have no ability to make the engineers itself (no factory)
			if numUnits < capCheck and structurecount > 0 then
			
				if factorycount < 4 or Eng_Type == 'SCU' then
				
					counter = counter + 1
					possibles[counter] = k
					
					-- if its a counted base add it a second time
					if v.CountedBase then
					
						counter = counter + 1
						possibles[counter] = k

                        -- SCU attracted to counted bases more
                        if Eng_Type == 'SCU' then

                            counter = counter + 1                        
                            possibles[counter] = k

                        end
						
					end
					
					-- if its a primary base add it twice more again
					if v.PrimaryLandAttackBase or v.PrimarySeaAttackBase then

						counter = counter + 1					
						possibles[counter] = k

                        -- SCU not as attracted to Primary compensated by
                        -- extra addition IF it has production (CountedBase)
                        if not Eng_Type == 'SCU' then

                            counter = counter + 1
                            possibles[counter] = k

                        end
					end
				end
			end
		end
	end
	
	if counter > 0 then
	
		-- remove engy from his existing base - destroy all existing engy callbacks
		aiBrain.BuilderManagers[eng.LocationType].EngineerManager:RemoveEngineerUnit(eng)
		
		local newbase = possibles[ Random(1,counter) ]
        
		--LOG("*AI DEBUG "..aiBrain.Nickname.." ENG_TRANSFER "..Eng_Type.." Transfers From "..repr(eng.LocationType).." To "..repr(newbase) )        
		
		-- add him to the selected base - but dont send him to assign task -- setup new engy callbacks
		aiBrain.BuilderManagers[newbase].EngineerManager:AddEngineerUnit( eng, false )
		
		-- force platoon to use the new base as the RTBLocation
		-- if you don't do this then the engineer will just RTB to his original base
		self.RTBLocation = newbase
		
	else
	
		--LOG("*AI DEBUG "..aiBrain.Nickname.." ENG_TRANSFER "..Eng_Type.." Transfer FROM "..repr(eng.LocationType).." FAILS")
	end
	
	self:SetAIPlan('ReturnToBaseAI',aiBrain)
	
end


-- uses the Eye of Rhianne as an intelligence tools
function EyeBehavior( unit, aiBrain )

	local IsIdleState = IsIdleState
    local MustScoutList = aiBrain.IL.MustScout
	
	local function AIGetMustScoutArea()
	
		for k,v in MustScoutList do
		
			if not v.TaggedBy or v.TaggedBy.Dead then
			
				return v, k
				
			end
			
		end
		
		return false, nil
		
	end	

    local targetArea, mustScoutArea, mustScoutIndex
    
    while not unit.Dead do
    
        WaitSeconds(30)
        
        if (GetEconomyTrend( aiBrain, 'ENERGY' ) *10) > 100 and GetEconomyStored( aiBrain, 'ENERGY' ) > 7000 and IsIdleState(unit) then
		
            targetArea = false

            mustScoutArea, mustScoutIndex = AIGetMustScoutArea()
            
            -- 1) If we have any "must scout" (manually added) locations that have not been scouted yet, then scout them
            if mustScoutArea  then
			
				MustScoutList[mustScoutIndex].TaggedBy = unit

                targetArea = mustScoutArea.Position
            end
  
            -- 2) Scout a high priority location    
            if not targetArea and not aiBrain.IL.LastAirScoutHi then
			
				if aiBrain.IL.HiPri[1] then

					targetArea = LOUDCOPY(aiBrain.IL.HiPri[1].Position)
					
					aiBrain.IL.HiPri[1].LastScouted = LOUDTIME()
					aiBrain.IL.LastAirScoutHi = true

				end
			end

            -- 3) Scout a low priority location               
            if not targetArea then
			
				aiBrain.IL.LastAirScoutHiCount = aiBrain.IL.LastAirScoutHiCount + 1
				
				if aiBrain.IL.LastAirScoutHiCount > 5 then
					aiBrain.IL.LastAirScoutHi = false
					aiBrain.IL.LastAirScoutHiCount = 0
					
				end

				if aiBrain.IL.LowPri[1] then
                
					targetArea = aiBrain.IL.LowPri[1].Position
					aiBrain.IL.LowPri[1].LastScouted = LOUDTIME()
					
				end
            end
            
            -- Execute the scouting mission
            if targetArea then
				
                -- Ok lets execute the Eye Viz function now
                IssueScript( {unit}, {TaskName = "TargetLocation", Location = targetArea} )
                
				-- when scouting an untagged (must scout) area 
				-- take it off the list of must scout areas
                if mustScoutArea then

					aiBrain.IL.MustScout[mustScoutIndex] = nil
                    
					aiBrain.IL.MustScout = aiBrain:RebuildTable(aiBrain.IL.MustScout)
                    
					mustScoutArea = false
                end
                
            end
            
        end
    end
end

-- uses the Rift Gate to produce elite Sera units
function RiftGateBehavior( unit, aiBrain, manager )

    local BuildUnit = moho.aibrain_methods.BuildUnit

	local IsIdleState = IsIdleState
	local Random = Random
	
	-- still need one important function here - that is SetRallyPoint
	ForkThread(manager.SetRallyPoint, manager, unit)
	
    local unitlist = { 'bsl0003','bsl0004','bsl0005','bsl0007','bsl0008','bsa0003' }
   
    while not unit.Dead do
	
        WaitTicks(45)
        
        if (GetEconomyTrend(aiBrain,'ENERGY') * 10) > 100 and GetEconomyStored(aiBrain,'ENERGY') > 1500 and IsIdleState(unit) then
        
            BuildUnit( aiBrain, unit, unitlist[ Random(1,6) ], 3 )
        end
    end
end

-- this will fire up the FatBoyThread 
function FatBoyAI( unit, aiBrain )

	if not unit.Dead and LOUDENTITY( categories.uel0401, unit ) and not unit.FatBoyThread then
	
		LOG("*AI DEBUG FatBoy Initialization starting")
		
		unit.FatBoyThread = unit:ForkThread( FatBoyThread, aiBrain )
		
	end
	
end	
	
-- this will have FatBoy produce units whenever he is NOT in a platoon (but in the ARMYPOOL platoon) and is idle
function FatBoyThread( fatboy, aiBrain )

	local LOUDGETN = LOUDGETN

	local faction = aiBrain.FactionIndex
	
	local pool = aiBrain.ArmyPool
	local EnergyStorage, MassStorage
	
	LOG("*AI DEBUG FatBoy Thread started")
	
	-- this unitlist is chosen from the units that Fatboy can actually build
	-- I provide it in code here but it could be part of the FATBOY blueprint in the AI section
	local untlist = {'uel0303', 'uel0307', 'uel0304', 'xel0305', 'xel0306', 'delk002', }
	
	while fatboy and (not fatboy.dead) do

		-- while fatboy is NOT in the Army Pool and there is some unit cap available --
		if (not fatboy.PlatoonHandle == pool) and (aiBrain.IgnoreArmyCaps or ( (GetArmyUnitCostTotal(aiBrain.ArmyIndex) / GetArmyUnitCap(aiBrain.ArmyIndex)) < .95) ) then
		
			-- check the current storage levels every 10 seconds
			EnergyStorage = GetEconomyStored( aiBrain, 'ENERGY')
			MassStorage = GetEconomyStored( aiBrain, 'MASS')

			if fatboy:IsIdleState() and (MassStorage >= 200 and EnergyStorage >= 2000) then
			
				local unitbuildtime = 0
			
				-- decide what to build
				local unitToBuild = untlist[Random(1,LOUDGETN(untlist))]
			
				aiBrain:BuildUnit( fatboy, unitToBuild, 1 )
				
				-- loop until we confirm unit is being built
				repeat
				
					WaitTicks(10)
					
					unitbuildtime = unitbuildtime + 2
					
				until fatboy.Dead or fatboy.UnitBeingBuilt or unitbuildtime > 10 
    
				-- loop until idle, in a platoon, or not building
				repeat
				
					WaitTicks(25)
					
				until fatboy.Dead or fatboy:IsIdleState() or fatboy.PlatoonHandle != aiBrain.ArmyPool or (not fatboy.UnitBeingBuilt)
				
			end
			
		end
		
		WaitTicks(100)
		
	end
	
end

-- Carrier Thread -- Here is my attempt to make carriers useful to the AI
-- 	The carrier will produce aircraft thru the use of an ECONOMY EVENT - pay the bill - create the unit above the carrier 
--  the new unit is placed into a platoon that guards the carrier  -- if the carrier gets attached to a platoon those aircraft go with it 
--	The carrier will keep making aircraft until it has 2 Scouts, 16 Fighters & 32 Torpedo bombers
--  If it builds all the above aircraft it will halt until it more are needed
function CarrierThread ( carrier, aiBrain )

	local LOUDGETN = LOUDGETN
	local GetBuildRate = GetBuildRate
	local IsIdleState = IsIdleState

	local ftrlist = { 'uea0303', 'uaa0303', 'ura0303', 'xsa0303' }
	local trplist = { 'uea0204', 'xaa0306', 'ura0204', 'xsa0204' }
	local sctlist = { 'uea0302', 'uaa0302', 'ura0302', 'xsa0302' }
    
	local faction = aiBrain.FactionIndex
	
	carrier.RTB = false
	
	LOG("*AI DEBUG "..aiBrain.Nickname.."CARRIER Thread begins")	
	
	-- a thread to RTB the carrier if it's badly damaged
	local function WatchForDamaged( )
	
		carrier.RTB = false
	
		while (not carrier.dead) and (not carrier.RTB) do
		
			WaitTicks(40)

			if (not carrier.Dead) and (carrier:GetHealthPercent() < .6) and not carrier.RTB then
			
				LOG("*AI DEBUG "..aiBrain.Nickname.." CARRIER issued RTB ")
				
				-- pull the carrier out of its platoon and RTB it
				local workplatoon = MakePlatoon( aiBrain, 'CarrierRTB', 'none')
				
				AssignUnitsToPlatoon( aiBrain, workplatoon, {carrier}, 'Attack', 'none' )
				workplatoon.BuilderName = 'CarrierRTB'
				
				workplatoon:SetAIPlan( 'ReturnToBaseAI', aiBrain )
				
				carrier.RTB = true
				
			end
			
		end
		
	end

    local killedCallback = function( carrier )

		local aiBrain = GetAIBrain(carrier)
		
		LOG("*AI DEBUG "..aiBrain.Nickname.." Carrier OnKilled event callback")
		
		if carrier.SctPlatoon then
		
			LOG("*AI DEBUG "..aiBrain.Nickname.." Carrier had scout platoon")
			
		end
		
		if carrier.TrpPlatoon then
		
			LOG("*AI DEBUG "..aiBrain.Nickname.." Carrier had torpedo platoon")
			
		end
		
		if carrier.FtrPlatoon then
		
			LOG("*AI DEBUG "..aiBrain.Nickname.." carrier had fighter platoon")
			
		end

    end
	
	LOUDINSERT(carrier.EventCallbacks.OnKilled, killedCallback)
	
    local platoondestroyedCallback = function( brain, platoon )
		
		LOG("*AI DEBUG "..brain.Nickname.." CARRIER - Air platoon destroyed "..repr(platoon.BuilderName) )

		if platoon.BuilderName =='CarrierScouts' then
			
			local parent = platoon.Parent
			
			parent.SctPlatoon = nil
			
			LOG("*AI DEBUG "..aiBrain.Nickname.." Carrier "..repr(parent.Sync.id).." clears Scout Platoon")
			
		elseif platoon.BuilderName == 'CarrierFighters' then
		
			local parent = platoon.Parent
			
			parent.FtrPlatoon = nil
			
			LOG("*AI DEBUG "..aiBrain.Nickname.." Carrier "..repr(parent.Sync.id).." clears Fighter Platoon")			
			
		elseif platoon.BuilderName == 'CarrierTorpedoBombers' then
		
			local parent = platoon.Parent
			
			parent.TrpPlatoon = nil
			
			LOG("*AI DEBUG "..aiBrain.Nickname.." Carrier "..repr(parent.Sync.id).." clears Torpedo Platoon")
			
		end

    end
	
	
	-- start up the watch for damage thread 
	carrier:ForkThread( WatchForDamaged )
	
	local building, unitBeingBuilt, unitToBuild
	local unitbp, massneeded,energyneeded,timeneeded
	local cpos
	
	while not carrier.Dead do
	
		-- check the current storage levels and unit cap - and decide what unit to build
		-- here's the beauty of this - the carrier can ALWAYS be building - moving or not - platoon or not
		if (aiBrain.IgnoreArmyCaps or ((GetArmyUnitCostTotal(aiBrain.ArmyIndex) / GetArmyUnitCap(aiBrain.ArmyIndex)) < .95) )	
			and (GetEconomyStored( aiBrain, 'MASS') >= 200 and GetEconomyStored( aiBrain, 'ENERGY') >= 2500) then
			
			building = false
			
			if (not carrier.SctPlatoon) then
				
				building = 'scout'
				unitToBuild = sctlist[faction]
				
			end
			
			if (not building) and (not carrier.FtrPlatoon) then
			
				building = 'fighter'
				unitToBuild = ftrlist[faction]
				
			end

			if (not building) and (not carrier.TrpPlatoon) then
				
				building = 'torpedo'
				unitToBuild = trplist[faction]

			end

			unitBeingBuilt = false
			
			-- if all 3 platoons are active 
			if not building then
			
				-- decide what to build -- scouts first - then fighters -- then torps
				if LOUDGETN(carrier.SctPlatoon:GetPlatoonUnits()) < 2 then
				
					building = 'scout'
					unitToBuild = sctlist[faction]
					
				end
				
				if (not building) and LOUDGETN(carrier.FtrPlatoon:GetPlatoonUnits()) < 16 then
				
					building = 'fighter'
					unitToBuild = ftrlist[faction]
					
				end
				
				if (not building) and LOUDGETN(carrier.TrpPlatoon:GetPlatoonUnits()) < 32 then
				
					building = 'torpedo'
					unitToBuild = trplist[faction]
					
				end
				
			end
			
			-- if we're building something - build it - put into its platoon and then issue guard order
			if building and not carrier.Dead then
			
				-- we'll need the unit blueprint economy section for mass, energy and build time
				unitbp = aiBrain:GetUnitBlueprint(unitToBuild).Economy
				
				massneeded = unitbp.BuildCostMass
				energyneeded = unitbp.BuildCostEnergy
				timeneeded = unitbp.BuildTime
				
				LOG("*AI DEBUG "..aiBrain.Nickname.." CARRIER building "..repr(building))
				
				carrier.UnitDrain = CreateEconomyEvent( carrier, energyneeded, massneeded, (timeneeded/GetBuildRate(carrier)), carrier:SetWorkProgress(0) )
			
				-- WAITFOR the eco event to complete
				WaitFor( carrier.UnitDrain )
				
				if not carrier.Dead then
				
					-- create the unit just above the carrier
					cpos = GetPosition(carrier)
					unitBeingBuilt = CreateUnitHPR( unitToBuild, aiBrain.Name, cpos[1], cpos[2] + 5, cpos[3], 0, 0, 0 )
				
					-- we built something - put it into a platoon
					if building == 'fighter' then
				
						if not carrier.FtrPlatoon or not PlatoonExists(aiBrain,carrier.FtrPlatoon) then
						
							local FtrPlatoon = MakePlatoon( aiBrain, 'CarrierFighters', 'none' )
							
							FtrPlatoon.BuilderName = 'CarrierFighters'
							FtrPlatoon.Parent = carrier
				
							LOUDINSERT(FtrPlatoon.EventCallbacks.OnDestroyed, platoondestroyedCallback)
							
							carrier.FtrPlatoon = FtrPlatoon
							
						end
					
						AssignUnitsToPlatoon( aiBrain, carrier.FtrPlatoon, {unitBeingBuilt}, 'Attack', 'None' )
						IssueGuard( carrier.FtrPlatoon:GetPlatoonUnits(), carrier )
					
					elseif building == 'torpedo' then
					
						if not carrier.TrpPlatoon or not PlatoonExists(aiBrain,carrier.TrpPlatoon) then
						
							local TrpPlatoon = MakePlatoon( aiBrain,'CarrierTorpedoBombers', 'none' )
							
							TrpPlatoon.BuilderName = 'CarrierTorpedoBombers'
							TrpPlatoon.Parent = carrier
				
							LOUDINSERT(TrpPlatoon.EventCallbacks.OnDestroyed, platoondestroyedCallback)
							carrier.TrpPlatoon = TrpPlatoon
							
						end
					
						AssignUnitsToPlatoon( aiBrain, carrier.TrpPlatoon, {unitBeingBuilt}, 'Attack', 'None' )
						IssueGuard( carrier.TrpPlatoon:GetPlatoonUnits(), carrier )
						
					elseif building == 'scout' then
				
						if not carrier.SctPlatoon or not PlatoonExists(aiBrain,carrier.SctPlatoon) then
						
							local SctPlatoon = MakePlatoon( aiBrain, 'CarrierScouts', 'none' )
							SctPlatoon.BuilderName = 'CarrierScouts'
							SctPlatoon.Parent = carrier
							
							LOUDINSERT(SctPlatoon.EventCallbacks.OnDestroyed, platoondestroyedCallback)
							carrier.SctPlatoon = SctPlatoon
							
						end
					
						AssignUnitsToPlatoon( aiBrain, carrier.SctPlatoon, {unitBeingBuilt}, 'scout', 'None' )
						
						IssueGuard( carrier.SctPlatoon:GetPlatoonUnits(), carrier )
						
					end

					-- reset the work progress bar to 0
					carrier:SetWorkProgress(0)

				end
				
			else
			
				FloatingEntityText( carrier.Sync.id, " No build needed " )
				
			end
			
		else
		
			FloatingEntityText( carrier.Sync.id, " Cannot build " )
		
		end
		
		
		WaitTicks(60)
		
	end
	
end

-- this is a variant of the carrier thread specifically for the Atlantis
function AtlantisCarrierThread ( carrier, aiBrain )

	local LOUDGETN = LOUDGETN
	local GetBuildRate = GetBuildRate
	
	local ftrlist = { 'uea0303' }
	local gunlist = { 'uea0203' }
	local bmblist = { 'uea0304' }
	local trplist = { 'uea0204' }
	local sctlist = { 'uea0302' }
	
	local faction = aiBrain.FactionIndex
	
	LOG("*AI DEBUG "..aiBrain.Nickname.." Atlantis Carrier Thread begins")
	
	-- thread will RTB the Atlantis if badly damaged
	local function WFD(carrier, aiBrain)
	
		carrier.RTB = false
	
		while (not carrier.Dead) and (not carrier.RTB) do
	
			WaitTicks(40)

			if (not carrier.Dead) and (carrier:GetHealthPercent() < .6) and not carrier.RTB then
			
				-- pull the carrier out of its platoon and RTB it
				local workplatoon = MakePlatoon( aiBrain,'AtlantisRTB', 'none')
				
				AssignUnitsToPlatoon( aiBrain, workplatoon, {carrier}, 'Attack', 'none' )
				workplatoon.BuilderName = 'AtlantisRTB'
			
				LOG("*AI DEBUG "..aiBrain.Nickname.." Atlantis issued RTB ")
				
				workplatoon:SetAIPlan( 'ReturnToBaseAI', aiBrain )
				carrier.RTB = true
			end
		end
	end
	
	-- start up the watch for damage thread 
	carrier:ForkThread( WFD, aiBrain )

	while not carrier.Dead do
    
		WaitTicks(60)

		-- check the current storage levels and build if resources good
		if (aiBrain.IgnoreArmyCaps or ((GetArmyUnitCostTotal(aiBrain.ArmyIndex) / GetArmyUnitCap(aiBrain.ArmyIndex)) < .95) )	
			and (GetEconomyStored( aiBrain, 'MASS') >= 200 and GetEconomyStored( aiBrain, 'ENERGY') >= 2500) then
			
			-- initialize the air platoons -- keep in mind that they'll disband shortly if we dont put something in them
			-- we'll recreate them every pass (if not present) so that we can decide what to build
			if not carrier.FtrPlatoon or not PlatoonExists(aiBrain,carrier.FtrPlatoon) then
				carrier.FtrPlatoon = MakePlatoon( aiBrain,'CarrierFighters', 'none')
				carrier.FtrPlatoon.BuilderName = 'CarrierFighters'
			end
			if not carrier.GunPlatoon or not PlatoonExists(aiBrain,carrier.GunPlatoon) then
				carrier.GunPlatoon = MakePlatoon( aiBrain,'CarrierGunships', 'none')
				carrier.GunPlatoon.BuilderName = 'CarrierGunships'			
			end
			if not carrier.BmbPlatoon or not PlatoonExists(aiBrain,carrier.BmbPlatoon) then
				carrier.BmbPlatoon = MakePlatoon( aiBrain,'CarrierBombers', 'none')
				carrier.BmbPlatoon.BuilderName = 'CarrierBombers'
			end
			if not carrier.TrpPlatoon or not PlatoonExists(aiBrain,carrier.TrpPlatoon) then
				carrier.TrpPlatoon = MakePlatoon( aiBrain,'CarrierTorpedoBombers', 'none')
				carrier.TrpPlatoon.BuilderName = 'CarrierTorpedoBombers'
			end
			if not carrier.SctPlatoon or not PlatoonExists(aiBrain,carrier.SctPlatoon) then
				carrier.SctPlatoon = MakePlatoon( aiBrain,'CarrierScouts', 'none')
				carrier.SctPlatoon.BuilderName = 'CarrierScouts'
			end
			
			local building = false
			local unitBeingBuilt = false
            local unitToBuild
			
			-- decide what to build -- scouts first - then fighters, bombers and gunships
			if LOUDGETN(carrier.SctPlatoon:GetPlatoonUnits()) < 2 then
				building = 'scout'
				unitToBuild = sctlist[1]
				
			elseif LOUDGETN(carrier.FtrPlatoon:GetPlatoonUnits()) < 16 then
				building = 'fighter'
				unitToBuild = ftrlist[1]
				
			elseif LOUDGETN(carrier.BmbPlatoon:GetPlatoonUnits()) < 10 then
				building = 'bomber'
				unitToBuild = bmblist[1]
				
			elseif LOUDGETN(carrier.TrpPlatoon:GetPlatoonUnits()) < 25 then
				building = 'torpedo'
				unitToBuild = trplist[1]

			elseif LOUDGETN(carrier.GunPlatoon:GetPlatoonUnits()) < 25 then
				building = 'gunship'
				unitToBuild = gunlist[1]
			end			

			-- if we're building something - build it - put into its platoon and then issue guard order
			if building and not carrier.Dead then
			
				-- we'll need the unit blueprint economy section for mass, energy and build time
				local unitbp = aiBrain:GetUnitBlueprint(unitToBuild).Economy
				local massneeded = unitbp.BuildCostMass
				local energyneeded = unitbp.BuildCostEnergy
				local timeneeded = unitbp.BuildTime
				
				carrier.UnitDrain = CreateEconomyEvent( carrier, energyneeded, massneeded, (timeneeded/GetBuildRate(carrier)), carrier.UpdateTeleportProgress)
			
				-- WAITFOR the eco event to complete
				WaitFor( carrier.UnitDrain )
				
				-- create the unit
				local cpos = carrier:GetPosition()
				local unitBeingBuilt = CreateUnitHPR( unitToBuild, aiBrain.Name, cpos[1], cpos[2] + 5, cpos[3], 0, 0, 0 )
				
				-- we built something - put it into a platoon
				if building == 'fighter' then
					if not carrier.FtrPlatoon or not PlatoonExists(aiBrain,carrier.FtrPlatoon) then
						carrier.FtrPlatoon = MakePlatoon( aiBrain,'CarrierFighters', 'none')
						carrier.FtrPlatoon.BuilderName = 'CarrierFighters'
					end
					AssignUnitsToPlatoon( aiBrain, carrier.FtrPlatoon, {unitBeingBuilt}, 'Attack', 'None' )
					
				elseif building == 'bomber' then
					if not carrier.BmbPlatoon or not PlatoonExists(aiBrain,carrier.BmbPlatoon) then
						carrier.BmbPlatoon = MakePlatoon( aiBrain,'CarrierBombers', 'none')
						carrier.BmbPlatoon.BuilderName = 'CarrierBombers'
					end
					AssignUnitsToPlatoon( aiBrain, carrier.BmbPlatoon, {unitBeingBuilt}, 'Attack', 'None' )
					
				elseif building == 'torpedo' then
					if not carrier.TrpPlatoon or not PlatoonExists(aiBrain,carrier.TrpPlatoon) then
						carrier.TrpPlatoon = MakePlatoon( aiBrain,'CarrierTorpedoBombers', 'none')
						carrier.TrpPlatoon.BuilderName = 'CarrierTorpedoBombers'
					end
					AssignUnitsToPlatoon( aiBrain, carrier.TrpPlatoon, {unitBeingBuilt}, 'Attack', 'None' )

				elseif building == 'gunship' then
					if not carrier.GunPlatoon or not PlatoonExists(aiBrain,carrier.GunPlatoon) then
						carrier.GunPlatoon = MakePlatoon( aiBrain,'CarrierGunships', 'none')
						carrier.GunPlatoon.BuilderName = 'CarrierGunships'
					end
					AssignUnitsToPlatoon( aiBrain, carrier.BmbPlatoon, {unitBeingBuilt}, 'Attack', 'None' )

				elseif building == 'scout' then
					if not carrier.SctPlatoon or not PlatoonExists(aiBrain,carrier.SctPlatoon) then
						carrier.SctPlatoon = MakePlatoon( aiBrain,'CarrierScouts', 'none')
						carrier.SctPlatoon.BuilderName = 'CarrierScouts'
					end				
					AssignUnitsToPlatoon( aiBrain, carrier.SctPlatoon, {unitBeingBuilt}, 'scout', 'None' )
				end

				-- reset the work progress bar to 0
				carrier:SetWorkProgress(0)
				
				IssueGuard( carrier.FtrPlatoon:GetPlatoonUnits(), carrier )
				IssueGuard( carrier.BmbPlatoon:GetPlatoonUnits(), carrier )
				IssueGuard( carrier.TrpPlatoon:GetPlatoonUnits(), carrier )
				IssueGuard( carrier.GunPlatoon:GetPlatoonUnits(), carrier )
				IssueGuard( carrier.SctPlatoon:GetPlatoonUnits(), carrier )
			end
		end
	end
end

-- this is a variant of the carrier thread specifically for the Czar
function CzarCarrierThread ( carrier, aiBrain )

	local LOUDGETN = LOUDGETN
	local GetBuildRate = GetBuildRate
	
	local ftrlist = { 'uaa0303' }
	local gunlist = { 'xaa0305' }
	local bmblist = { 'uaa0304' }
	local sctlist = { 'uaa0302' }
	
	local faction = aiBrain.FactionIndex
	
	LOG("*AI DEBUG "..aiBrain.Nickname.." Czar Carrier Thread begins")
	
	carrier.RTB = false
	
	-- will RTB the Czar if badly damaged
	local function WFD( carrier, aiBrain )
	
		carrier.RTB = false
	
		while not carrier.RTB do
		
			WaitTicks(40)

			if (not carrier.Dead) and (carrier:GetHealthPercent() < .6) and not carrier.RTB then
			
				-- pull the Czar out of its platoon and RTB it
				local workplatoon = MakePlatoon( aiBrain,'CzarRTB', 'none')
				
				AssignUnitsToPlatoon( aiBrain, workplatoon, {carrier}, 'Attack', 'none' )
				workplatoon.BuilderName = 'CzarRTB'

				LOG("*AI DEBUG "..aiBrain.Nickname.." Czar issued RTB ")
				
				workplatoon:SetAIPlan('ReturnToBaseAI',aiBrain)
				
				carrier.RTB = true
				
			end
			
		end
		
	end
	
	-- start up the watch for damage thread 
	carrier:ForkThread( WFD, aiBrain )
	
	local building, unitBeingBuilt, unitToBuild
	local unitbp, massneeded, energyneeded, timeneeded
	local cpos
	
	while not carrier.Dead do
    
		WaitTicks(60)

		-- check the current storage levels and build if resources good
		if (aiBrain.IgnoreArmyCaps or ((GetArmyUnitCostTotal(aiBrain.ArmyIndex) / GetArmyUnitCap(aiBrain.ArmyIndex)) < .95) )	
			and (GetEconomyStored( aiBrain, 'MASS') >= 200 and GetEconomyStored( aiBrain, 'ENERGY') >= 2500) then
			
			-- initialize the air platoons -- keep in mind that they'll disband shortly if we dont put something in them
			-- we'll recreate them every pass (if not present) so that we can decide what to build
			if not carrier.FtrPlatoon or not PlatoonExists(aiBrain,carrier.FtrPlatoon) then
			
				carrier.FtrPlatoon = MakePlatoon( aiBrain,'CarrierFighters', 'none')
				carrier.FtrPlatoon.BuilderName = 'CarrierFighters'
				
			end
			
			if not carrier.GunPlatoon or not PlatoonExists(aiBrain,carrier.GunPlatoon) then
			
				carrier.GunPlatoon = MakePlatoon( aiBrain,'CarrierGunships', 'none')
				carrier.GunPlatoon.BuilderName = 'CarrierGunships'			
				
			end
			
			if not carrier.BmbPlatoon or not PlatoonExists(aiBrain,carrier.BmbPlatoon) then
			
				carrier.BmbPlatoon = MakePlatoon( aiBrain,'CarrierBombers', 'none')
				carrier.BmbPlatoon.BuilderName = 'CarrierBombers'
				
			end
			
			if not carrier.SctPlatoon or not PlatoonExists(aiBrain,carrier.SctPlatoon) then
			
				carrier.SctPlatoon = MakePlatoon( aiBrain,'CarrierScouts', 'none')
				carrier.SctPlatoon.BuilderName = 'CarrierScouts'
				
			end
			
			building = false
			unitBeingBuilt = false
			
			-- decide what to build -- scouts first - then fighters, bombers and gunships
			if LOUDGETN(carrier.SctPlatoon:GetPlatoonUnits()) < 2 then
			
				building = 'scout'
				unitToBuild = sctlist[1]
				
			elseif LOUDGETN(carrier.FtrPlatoon:GetPlatoonUnits()) < 14 then
			
				building = 'fighter'
				unitToBuild = ftrlist[1]
				
			elseif LOUDGETN(carrier.BmbPlatoon:GetPlatoonUnits()) < 10 then
			
				building = 'bomber'
				unitToBuild = bmblist[1]
				
			elseif LOUDGETN(carrier.GunPlatoon:GetPlatoonUnits()) < 10 then
			
				building = 'gunship'
				unitToBuild = gunlist[1]
				
			end			

			-- if we're building something - build it - put into its platoon and then issue guard order
			if building and not carrier.Dead then
			
				-- we'll need the unit blueprint economy section for mass, energy and build time
				unitbp = aiBrain:GetUnitBlueprint(unitToBuild).Economy
				
				massneeded = unitbp.BuildCostMass
				energyneeded = unitbp.BuildCostEnergy
				timeneeded = unitbp.BuildTime
				
				carrier.UnitDrain = CreateEconomyEvent( carrier, energyneeded, massneeded, (timeneeded/GetBuildRate(carrier)), carrier.UpdateTeleportProgress)
			
				-- WAITFOR the eco event to complete
				WaitFor( carrier.UnitDrain )
				
				-- create the unit
				cpos = carrier:GetPosition()
				unitBeingBuilt = CreateUnitHPR( unitToBuild, aiBrain.Name, cpos[1], cpos[2] + 5, cpos[3], 0, 0, 0 )
				
				-- we built something - put it into a platoon
				if building == 'fighter' then
				
					if not carrier.FtrPlatoon or not PlatoonExists(aiBrain,carrier.FtrPlatoon) then
					
						carrier.FtrPlatoon = MakePlatoon( aiBrain,'CarrierFighters', 'none')
						carrier.FtrPlatoon.BuilderName = 'CarrierFighters'
						
					end
					
					AssignUnitsToPlatoon( aiBrain, carrier.FtrPlatoon, {unitBeingBuilt}, 'Attack', 'None' )
					
				elseif building == 'bomber' then
				
					if not carrier.BmbPlatoon or not PlatoonExists(aiBrain,carrier.BmbPlatoon) then
					
						carrier.BmbPlatoon = MakePlatoon( aiBrain,'CarrierBombers', 'none')
						carrier.BmbPlatoon.BuilderName = 'CarrierBombers'
						
					end
					
					AssignUnitsToPlatoon( aiBrain, carrier.BmbPlatoon, {unitBeingBuilt}, 'Attack', 'None' )
					
				elseif building == 'gunship' then
				
					if not carrier.GunPlatoon or not PlatoonExists(aiBrain,carrier.GunPlatoon) then
					
						carrier.GunPlatoon = MakePlatoon( aiBrain,'CarrierGunships', 'none')
						carrier.GunPlatoon.BuilderName = 'CarrierGunships'
						
					end
					
					AssignUnitsToPlatoon( aiBrain, carrier.BmbPlatoon, {unitBeingBuilt}, 'Attack', 'None' )

				elseif building == 'scout' then
				
					if not carrier.SctPlatoon or not PlatoonExists(aiBrain,carrier.SctPlatoon) then
					
						carrier.SctPlatoon = MakePlatoon( aiBrain,'CarrierScouts', 'none')
						carrier.SctPlatoon.BuilderName = 'CarrierScouts'
						
					end

					AssignUnitsToPlatoon( aiBrain, carrier.SctPlatoon, {unitBeingBuilt}, 'scout', 'None' )
					
				end

				-- reset the work progress bar to 0
				carrier:SetWorkProgress(0)
				
				IssueGuard( carrier.FtrPlatoon:GetPlatoonUnits(), carrier )
				IssueGuard( carrier.BmbPlatoon:GetPlatoonUnits(), carrier )
				IssueGuard( carrier.GunPlatoon:GetPlatoonUnits(), carrier )
				IssueGuard( carrier.SctPlatoon:GetPlatoonUnits(), carrier )
				
			end
			
		end
		
	end
	
end

-- this controls the AI TMLs and adjusts to lead targets
function TMLThread( unit, aiBrain )

    --LOG("*AI DEBUG "..aiBrain.Nickname.." TMLThread")
    
    local maxRadius = unit:GetBlueprint().Weapon[1].MaxRadius
	local position = LOUDCOPY(GetPosition(unit))

	local GetUnitsAroundPoint = GetUnitsAroundPoint
    
	local UnitLeadTarget = import('/lua/ai/sorianutilities.lua').LeadTarget	-- this uses the specific one for TMLs
	local WaitTicks = WaitTicks
	
    unit:SetAutoMode(true)

	local atkPri = { 'SHIELD','ANTIMISSILE -SILO','EXPERIMENTAL','ARTILLERY','ECONOMIC','ENGINEER TECH3','MOBILE TECH3', }
	local targetUnits, target, targPos
	
    while not unit.Dead do

        -- dont search for targets unless ammo is 3+
        while unit:GetTacticalSiloAmmoCount() > 2 do

            while unit:GetTacticalSiloAmmoCount() > 0 do
            
                --LOG("*AI DEBUG "..aiBrain.Nickname.." TML seeking target")
			
                targetUnits = GetUnitsAroundPoint( aiBrain, categories.ALLUNITS - categories.WALL - categories.AIR - categories.TECH1, position, maxRadius, 'Enemy' )
                
                if targetUnits[1] then
                
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." TML examining targets")
            
                    -- loop thru each of the attack Priorities
                    for _,v in atkPri do
                
                        target = false
                        
                        for _, targetunit in EntityCategoryFilterDown( ParseEntityCategory(v), targetUnits ) do
                    
                            -- if you find a target then break out
                            if not targetunit.Dead then
                                target = targetunit
                                break
                            end
                        
                        end

                        -- if there is a target -- fire at it
                        if target and not target.Dead and not unit.Dead then
			
                            if LOUDENTITY(categories.STRUCTURE, target) then
                            
                                IssueTactical({unit}, target)
                                
                            else
                            
                                -- get a target position based upon movement
                                targPos = UnitLeadTarget(position, target) 
					
                                if targPos then
                                    IssueTactical({unit}, targPos)
                                    target = false
                                    targPos = false 	-- clear targeting data 
                                    break	-- break out back to ammo loop
                                end
                                
                            end
                            
                        else
                            
                            target = false
                            targPos = false

                        end
                        
                    end

                end
                
                -- wait 2.5 seconds between target checks
                WaitTicks(26)
                
			end
            
            targetUnits = nil
            
		end
		
		-- wait 10 seconds between ammo checks
        WaitTicks(101)
    end
end

-- Used as a visual aid - this will have a unit from the platoon visually
-- broadcast the platoon handle so you can see what they are every 15 seconds
function BroadcastPlatoonPlan ( platoon, aiBrain )

    local originalplan
    
	local PlatoonExists = PlatoonExists
    local GetPlatoonUnits = GetPlatoonUnits	
	
	local DisplayPlatoonPlans = ScenarioInfo.DisplayPlatoonPlans or false
	
	local armyindex = aiBrain.ArmyIndex
	local units
    
    while PlatoonExists( aiBrain, platoon ) and DisplayPlatoonPlans do
    
		if GetFocusArmy() == armyindex or GetFocusArmy() == -1 then
		
			units = GetPlatoonUnits(platoon)
		
			for _,v in units do
			
				if not v.Dead then

					ForkThread( FloatingEntityText, v.Sync.id, v.PlatoonHandle.BuilderName)
				
					if not originalplan then
					
						originalplan = v.PlatoonHandle.BuilderName
						
					end
					
					break	-- only do once for the whole platoon
					
				end
				
			end
			
		end
		
        WaitTicks(150)
		
    end
	
end

-- this function is used to monitor any change to the primary base
-- position during the execution of a Return To Base
-- if it changes - the RTB is reissued with new primary base
function PlatoonWatchPrimarySeaAttackBase ( platoon, aiBrain )

    local GetPrimarySeaAttackBase = import('/lua/loudutilities.lua').GetPrimarySeaAttackBase
	local PlatoonExists = PlatoonExists	
    
    -- set the Primary base at the start
    local Base = GetPrimarySeaAttackBase(aiBrain)

    -- if the primary base changes - restart the plan
    -- which should send the platoon to the new primary
    while PlatoonExists( aiBrain, platoon ) do
    
        WaitTicks(80)
        
        local Primary = GetPrimarySeaAttackBase(aiBrain)
        
        if Primary != Base then
        
            LOG("*AI DEBUG "..aiBrain.Nickname.." Primary Sea Base has changed to "..repr(Primary))
            
            platoon.RTBLocation = Primary
            
            for _,v in GetPlatoonUnits(platoon) do
                v.LocationType = platoon.RTBLocation
            end

            platoon:SetAIPlan( 'ReturnToBaseAI', aiBrain )
            
            -- make the target base the primary
            Base = Primary
        end
    end

end

-- SELF ENHANCE THREAD for SUBCOMMANDERS
-- After running into various difficulties in getting SCU to upgrade reliably thru the PFM
-- I felt it was better to go this route and let each SCU decide when to enhance themselves
-- thus saving a lot of confusing effort in the Platoon Form Manager
function SCUSelfEnhanceThread ( unit, faction, aiBrain )

	local WaitTicks = WaitTicks
    
    local HasEnhancement = unit.HasEnhancement
    local SetBlockCommandQueue = unit.SetBlockCommandQueue

	-- one entry for each faction - AEON,UEF,Cybran and Sera -- of course -- it might be more
	-- readable to have this data carried in the unit blueprint as part of the AI or Enhancement data
    local EnhancementTable = {
    { 'ResourceAllocation', 'AdvancedCoolingUpgrade', 'Shield', 'ShieldGeneratorField' },
    { 'ResourceAllocation', 'EngineeringFocusingModule', 'Shield', 'ShieldHeavy' },
    { 'ResourceAllocation', 'Switchback', 'StealthGenerator' },
    { 'EngineeringThroughput', 'Shield', 'Teleporter' },
    }
    
    local EnhanceList = EnhancementTable[faction]
    local final = EnhanceList[LOUDGETN(EnhanceList)]
    
    local EBP = __blueprints[unit.BlueprintID].Enhancements
	
	local GetBuildRate = GetBuildRate

	local IsIdleState = IsIdleState
	local IsUnitState = IsUnitState
    
	local CurrentEnhancement
	local BuildCostE, BuildCostM, BuildCostT
	local EFFTime, RateNeededE, RateNeededM
	local count
    
    while not unit.Dead and not unit.EnhancementsComplete do

        CurrentEnhancement = EnhanceList[1]

		if HasEnhancement( unit, CurrentEnhancement) then

			LOUDREMOVE(EnhanceList, 1)

		end

        -- if unit is idle and not currently in a platoon
        if IsIdleState(unit) and ( (not unit.PlatoonHandle) or unit.PlatoonHandle == aiBrain.ArmyPool) and not HasEnhancement( unit, CurrentEnhancement ) then
        
            unit.AssigningTask = true
		
			BuildCostE = EBP[CurrentEnhancement].BuildCostEnergy
			BuildCostM = EBP[CurrentEnhancement].BuildCostMass
			BuildCostT = EBP[CurrentEnhancement].BuildTime
            
            EffTime = ((100/GetBuildRate(unit)) * BuildCostT) / 100    -- build time in seconds
			
            RateNeededE = BuildCostE / EffTime
            RateNeededM = BuildCostM / EffTime
            
            -- if we can meet 85% of the Energy and Mass needs of the upgrade - go ahead with it
            if ((GetEconomyTrend(aiBrain,'ENERGY') * 10) >= (RateNeededE * .85)) and ((GetEconomyTrend(aiBrain,'MASS') * 10) >= (RateNeededM * .85)) then
			
				-- note that storage requirements for enhancements are just a little higher than those for factories building units
				-- this is to insure that unit building and upgrading take priority over enhancements
				if GetEconomyStored( aiBrain, 'MASS') >= 450 and GetEconomyStored( aiBrain, 'ENERGY') >= 4500 then
			
                    for _,v in unit:GetGuards() do
			
                        if not v.Dead and v.PlatoonHandle then
				
                            v.PlatoonHandle:ReturnToBaseAI(aiBrain)
					
                        end
				
                    end

					IssueStop({unit})
					IssueClearCommands({unit})
			
					if ScenarioInfo.NameEngineers then
						unit:SetCustomName("SCU "..unit.Sync.id.." "..CurrentEnhancement)
					end
				
					IssueScript( {unit}, {TaskName = "EnhanceTask", Enhancement = CurrentEnhancement} )
				
					count = 0
					
					if ScenarioInfo.SCUEnhanceDialog then
						LOG("*AI DEBUG "..aiBrain.Nickname.." SCUEnhance "..unit.Sync.id.." waiting to start "..repr(CurrentEnhancement))
					end

					-- sometimes SCU has a problem getting started so count was necessary
					repeat
				
						WaitTicks(15)
						count = count + 1
					
					until unit.Dead or IsUnitState(unit,'Enhancing') or count > 10

					if IsUnitState(unit,'Enhancing') then
					
						-- prevent any other orders while enhancing
						SetBlockCommandQueue( unit, true)
						
						if ScenarioInfo.SCUEnhanceDialog then
							LOG("*AI DEBUG "..aiBrain.Nickname.." SCUEnhance "..unit.Sync.id.." starting "..repr(CurrentEnhancement))
						end
				
						while not unit.Dead and IsUnitState(unit,'Enhancing') do
				
							WaitTicks(80)
					
						end
						
					end
                
					if HasEnhancement( unit, CurrentEnhancement) then
				
						LOUDREMOVE(EnhanceList, 1)
						
						if ScenarioInfo.SCUEnhanceDialog then
							LOG("*AI DEBUG "..aiBrain.Nickname.." SCUEnhance "..unit.Sync.id.." completed "..repr(CurrentEnhancement))
						end
                        
                        if CurrentEnhancement == 'Teleporter' then
                            unit.CanTeleport = true
                        end
					
					else
						LOG("*AI DEBUG "..aiBrain.Nickname.." SCU "..unit.Sync.id.." Failed Enhancement "..repr(CurrentEnhancement))
					end
				
					-- allow other orders when no longer enhancing
					SetBlockCommandQueue( unit, false )               				
				
					unit.AssigningTask = false
				
					local manager = aiBrain.BuilderManagers[unit.LocationType].EngineerManager
				
					if manager.Active then
				
						manager:ForkThread( manager.DelayAssignEngineerTask, unit, aiBrain )
					
					else
				
						manager:ForkThread( manager.ReassignEngineer, unit, aiBrain)
					
					end
					
				end
				
            end

            unit.AssigningTask = false			
            
            WaitTicks(36)
			
        end
		
        WaitTicks(12)
        
        if HasEnhancement( unit, final) then
		
			if ScenarioInfo.SCUEnhanceDialog then
				LOG("*AI DEBUG "..aiBrain.Nickname.." SCUEnhance "..unit.Sync.id.." all enhancements completed")
			end		
		
			unit.EnhancementsComplete = true
			
            break
			
        end
		
    end
	
	KillThread(unit.EnhanceThread)
	
	unit.EnhanceThread = nil
	
end

-- SELF ENHANCE for Other Units
function FactorySelfEnhanceThread ( unit, faction, aiBrain, manager )

    local EBP = __blueprints[unit.BlueprintID].Enhancements or false
	
	if not EBP or unit.EnhancementsComplete then
		return
	end
	
	local WaitTicks = WaitTicks
    
    local HasEnhancement = unit.HasEnhancement
    local SetBlockCommandQueue = unit.SetBlockCommandQueue
	
	while not unit.Dead and unit:GetFractionComplete() < 1 do
		WaitTicks(200)
	end

	-- this gets the sequence of enhancements
    local EnhanceList = LOUDCOPY(EBP.Sequence)
	
    local final = EnhanceList[LOUDGETN(EnhanceList)]
	
	if HasEnhancement( unit, final) then
		return
	end	

	if not EnhanceList[1] then
		EBP = false
	end
	
	local GetBuildRate = GetBuildRate
    
	local IsIdleState = IsIdleState
	local IsUnitState = IsUnitState
    
	local CurrentEnhancement
	local BuildCostE, BuildCostM, BuildCostT
	local EFFTime, RateNeededE, RateNeededM
  
    while EBP and not unit.Dead and not unit.EnhancementsComplete do
	
		WaitTicks(200) -- before start of any enhancement --

        CurrentEnhancement = EnhanceList[1]

        while not unit.Dead and not HasEnhancement(unit, CurrentEnhancement) do

			if IsIdleState(unit) then
		
				BuildCostE = EBP[CurrentEnhancement].BuildCostEnergy
				BuildCostM = EBP[CurrentEnhancement].BuildCostMass
				BuildCostT = EBP[CurrentEnhancement].BuildTime
		
				EffTime = ((100/GetBuildRate(unit)) * BuildCostT) / 100    -- build time in seconds

				RateNeededE = BuildCostE / EffTime
				RateNeededM = BuildCostM / EffTime

				-- if we can meet 95% of the Energy and Mass needs of the enhancement
				-- also - note - we must actually have that data structure - civilians DO NOT have this 
				if (aiBrain.EcoData['OverTime']['EnergyTrend']) and ((aiBrain.EcoData['OverTime']['EnergyTrend'] * 10) >= (RateNeededE * .95)) and ((aiBrain.EcoData['OverTime']['MassTrend'] * 10) >= (RateNeededM * .95)) then
			
					-- note that storage requirements for enhancements are just a little higher than those for factories building units
					-- this is to insure that unit building and upgrading take priority over enhancements
					if GetEconomyStored( aiBrain, 'MASS') >= 450 and GetEconomyStored( aiBrain, 'ENERGY') >= 4500 then
				
						IssueStop({unit})
						IssueClearCommands({unit})
				
						unit.Upgrading = true
						
						if ScenarioInfo.FactoryEnhanceDialog then
							LOG("*AI DEBUG "..aiBrain.Nickname.." FACTORYEnhance "..unit.Sync.id.." waiting to start "..repr(CurrentEnhancement))
						end
				
						IssueScript( {unit}, {TaskName = "EnhanceTask", Enhancement = CurrentEnhancement} )
						
						if ScenarioInfo.DisplayFactoryBuilds then
							unit:SetCustomName(repr(CurrentEnhancement))
						end						

						repeat
							WaitTicks(15)
						until unit.Dead or IsUnitState(unit,'Enhancing')
						
						if IsUnitState(unit,'Enhancing') and not unit.Dead then

							SetBlockCommandQueue( unit, true)
							
							if ScenarioInfo.FactoryEnhanceDialog then
								LOG("*AI DEBUG "..aiBrain.Nickname.." FACTORYEnhance "..unit.Sync.id.." starting "..repr(CurrentEnhancement))
							end							
				
							while not unit.Dead and IsUnitState(unit,'Enhancing') do
								WaitTicks(100)
							end  
				
							if not unit.Dead then
								SetBlockCommandQueue( unit, false)
							end
							
						end
              
						if HasEnhancement( unit, CurrentEnhancement) and not unit.Dead then
							
							if ScenarioInfo.FactoryEnhanceDialog then
								LOG("*AI DEBUG "..aiBrain.Nickname.." FACTORYEnhance "..unit.Sync.id.." completed "..repr(CurrentEnhancement))
							end							
							
							LOUDREMOVE(EnhanceList, 1)
						end
						
						if not unit.Dead then

							unit.Upgrading = nil
				
							unit.failedbuilds = 0
						
							if ScenarioInfo.DisplayFactoryBuilds then
								unit:SetCustomName("")
							end						
				
							-- since a manager will only be provided by a factory
							if manager then
								ForkThread(manager.DelayBuildOrder, manager, unit )
							end
						end

					else
						WaitTicks(40)
					end
					
				else
					WaitTicks(40)
				end
				
			end
			
	        WaitTicks(25)		
        end
        
        if HasEnhancement( unit, final) then
		
			if ScenarioInfo.FactoryEnhanceDialog then
				LOG("*AI DEBUG "..aiBrain.Nickname.." FACTORYEnhance "..unit.Sync.id.." all enhancements complete")
			end							
			
			unit.Upgrading = nil
			unit.failedbuilds = 0
			
            EBP = false
        end
    end
	
	unit.EnhancementsComplete = true
	
	KillThread(unit.EnhanceThread)
	
	unit.EnhanceThread = nil
	
end

-- SELF UPGRADE THREAD
-- The entire purpose of this thread is to take load off of the platoon manager
--
-- By allowing units to upgrade themselves based on economic conditions, quite a
-- number of platoon formations are removed & less build conditions have to be
-- checked by the Builder Manager

-- launched by the Engineer Manager when units are completed

-- Each unit class has its own set of triggers for both high and low mass & energy efficiencies
-- The intent is simple, if we meet those economic values - it's ok to consider upgrading
-- then we'll actually check the M & E rates against this specific upgrade
-- and last we'll confirm that a certain % of the resources are actually available

-- When an upgrade thread is started - it has an initial delay period before it can attempt to upgrade
-- this prevents, in most situations, units from immediately going into an upgrade the moment they are built
-- This 'delay' period is only used up during times of having the base eco storage amounts

-- Once the actual checking begins, the rate of the checking has a great influence on just how likely units
-- are to be selected to upgrade - because - we don't want everyone upgrading at once

-- Anytime a unit is allowed to upgrade - the UpgradeIssued counter is increased by one (see SelfUpgradeDelay)
-- and a delay period begins
    -- related to the buildtime of the upgrade
    -- and the economic state at the time the upgrade was issued
    
    -- if we have a lot of stored resources, this delay is shorter than when we dont
    -- this allows the AI to begin another upgrade sooner, in conditions of plenty
    -- while keeping him restrained when things are tight.

-- The conditions of the game limit the AI, in that he's not allowed to start too many upgrades in a hurry
-- so whenever this counter has reached it's limit - ANY attempt to upgrade is inhibited

-- after the delay has elapsed -- this counter will drop by one - 
-- thus providing a dynamic process that adapts nicely to feast and famine
-- and to the needs of the upgrade in question

function SelfUpgradeThread ( unit, faction, aiBrain, masslowtrigger, energylowtrigger, masshightrigger, energyhightrigger, checkrate, initialdelay, bypassecon)

	-- confirm that unit is upgradeable
	local upgradeID = __blueprints[unit.BlueprintID].General.UpgradesTo or false
	
	local upgradebp = false

	if upgradeID then
		upgradebp = aiBrain:GetUnitBlueprint(upgradeID) or false	-- this accounts for upgradeIDs that point to non-existent units (like mod not loaded)
	end
	
	-- if not upgradeID and blueprint available then kill the thread and exit
	if not (upgradeID and upgradebp) then
		unit.UpgradeThread = nil
		unit.UpgradesComplete = true
		return
	end
	
	-- set defaults for any without triggers
	if not masslowtrigger then
		local masslowtrigger = .85
		local energylowtrigger = 1.10
	end
    
    if not masshightrigger then
        local masshightrigger = 2
        local energyhightrigger = 2
    end
	
	if not checkrate then
		local checkrate = 20
		local initialdelay = 240
	end
	
	if not bypassecon then
		local bypassecon = false
	end
    
    -- build rate of construction unit
    local buildrate = unit:GetBuildRate()
    local massmade = unit:GetProductionPerSecondMass()
    local enermade = unit:GetProductionPerSecondEnergy()
    local enerused = unit:GetConsumptionPerSecondEnergy()
    
    -- these two values directly control resource requirements versus storage rather than rates
    -- and they act as a bypass whenever the storage holds this % of the total upgrade cost
    
    local masslimit = .70   -- for example if we have 70% of the total mass needed - it's ok to upgrade
    local energylimit = .76 -- and likewise for energy

    -- basic costs of upgraded unit
    -- affected both by the limits above AND the cheat values
	local MassNeeded = (upgradebp.Economy.BuildCostMass * masslimit)/aiBrain.MinorCheatModifier
	local EnergyNeeded = (upgradebp.Economy.BuildCostEnergy * energylimit)/aiBrain.MinorCheatModifier
    
    local buildtime = upgradebp.Economy.BuildTime

    -- trend rates needed to sustain this build without serious loss over the buildtime
    -- trend rates take into account current output and are multiplied by .1 to match with the ECO trends
    -- all minimums are capped at 0 so negative values are not possible
    -- this will result in more aggressive upgrading as the cheat level increases (not affected by ACT)
    local MassTrendNeeded = math.max(((( (MassNeeded / buildtime) * buildrate) - massmade) * .1) * math.min( 1, 1), 0)
    local EnergyTrendNeeded = math.max(((( (EnergyNeeded / buildtime) * buildrate) - enermade) * .1) * math.min( 1, 1), 0)
    
    -- energy maintenance requirements are NOT affected by cheats but are reduced by current E consumption
	local EnergyMaintenance = math.max( ((aiBrain:GetUnitBlueprint(upgradeID).Economy.MaintenanceConsumptionPerSecondEnergy or 10) - enerused) * .1, 0)

	local init_delay = 0
    
    -- store the normal checkrate
    local workrate = checkrate
	
	if ScenarioInfo.StructureUpgradeDialog then
   		LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." starts thread to upgrade to "..repr(upgradeID).." initial delay is "..initialdelay)
        --LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." needs "..MassNeeded.." mass -- "..buildtime.." ticks -- rate "..buildrate.." minus production "..massmade)
		--LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." needs "..(MassTrendNeeded*10).." mass trend -- current "..(aiBrain.EcoData.OverTime.MassTrend*10))
	end

	-- wait the initial delay before upgrading - accounts for unit not finished being built and basic storage requirements
	-- check storage values every 10 seconds -- and only advance the delay counter if we have the basic storage requirements
	while init_delay < initialdelay do
		
		-- uses the same values as factories do for units
		if GetEconomyStored( aiBrain, 'MASS') >= 200 and GetEconomyStored( aiBrain, 'ENERGY') >= 2500 and unit:GetFractionComplete() == 1 then
			init_delay = init_delay + 10
		else
            -- units which are permitted to bypass the more stringent eco tests can advance
            -- the init_delay by 2 seconds (rather than 10) even when the gateway values fail
            if bypassecon then
                init_delay = init_delay + 2
            end

        end
		
		WaitTicks(101)
	end
	
	local upgradeable = true
	local upgradeIssued = false    

    local econ = aiBrain.EcoData.OverTime
	
	local EnergyStorage, MassStorage
	
	while ((not unit.Dead) or unit.Sync.id) and upgradeable and (not upgradeIssued) do
	
		WaitTicks(checkrate * 10)
		
        if aiBrain.UpgradeIssued < aiBrain.UpgradeIssuedLimit and (not unit.BeingReclaimed) then
        
            if ScenarioInfo.StructureUpgradeDialog then
                LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." cycles upgrade check - game second "..GetGameTimeSeconds())
            end

			EnergyStorage = GetEconomyStored( aiBrain, 'ENERGY')
			MassStorage = GetEconomyStored( aiBrain, 'MASS')

            -- basic resource gate for all things (except bypassecon things)
            if (MassStorage < 200 or EnergyStorage < 2500) and not bypassecon then
                continue
            end

            -- first we check the low efficiency trigger or needed resources in storage
            -- either one gets you past this check
            if (econ.MassEfficiency >= masslowtrigger and econ.EnergyEfficiency >= energylowtrigger)

				or MassStorage > MassNeeded and EnergyStorage > EnergyNeeded then
        
                --if ScenarioInfo.StructureUpgradeDialog then
                  --  LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." passes low efficiency check")
                --end
				
				--low_trigger_good = true
                
			else
            
                if ScenarioInfo.StructureUpgradeDialog then
                
                    if (econ.MassEfficiency < masslowtrigger or econ.EnergyEfficiency < energylowtrigger) then
                    
                        if econ.MassEfficiency < masslowtrigger then
                            --LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." fails MIN M efficiency "..masslowtrigger.." current "..econ.MassEfficiency)
                        else
                            --LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." fails MIN E efficiency "..energylowtrigger.." current "..econ.EnergyEfficiency)
                        end
                        
                    elseif MassStorage <= MassNeeded or EnergyStorage <= EnergyNeeded then
                    
                        --LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." fails MIN stored resource needed")
                        
                    end

                end
				continue
			end
			
            -- then we check the high efficiency limits
			if (econ.MassEfficiency <= masshightrigger and econ.EnergyEfficiency <= energyhightrigger) then
        
                --if ScenarioInfo.StructureUpgradeDialog then
                  --  LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." passes MAX efficiency check")
                --end
				
				--hi_trigger_good = true
                
			else
            
                if ScenarioInfo.StructureUpgradeDialog then
                    --LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." fails MAX efficiency check")
                end            
				continue
			end

            -- if we pass the efficiency checks
            checkrate = math.max(checkrate - .05, 10)

            -- all values are marginally reduced --
            MassNeeded = MassNeeded * .995
            EnergyNeeded = EnergyNeeded * .995
            MassTrendNeeded = MassTrendNeeded * .995
            EnergyTrendNeeded = EnergyTrendNeeded * .995
            
            -- Now we check the current trends or the resources in storage
            
			-- if we have the M & E trend to support this build -- and energy consumption of the upgraded item is less than our current energytrend, we're good
			-- or we have the limit values of mass and energy,  in our storage

            if ( econ.MassTrend >= MassTrendNeeded and econ.EnergyTrend >= EnergyTrendNeeded and econ.EnergyTrend >= EnergyMaintenance )
            
				or ( MassStorage >= MassNeeded and EnergyStorage > EnergyNeeded )  then
        
                --if ScenarioInfo.StructureUpgradeDialog then
                  --  LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." passes trend or storage check")
                --end

                -- we may have passed the first check based upon trends - this next check insures having at least 25% resources
				-- anything that has bypassecon always passes this check - basically if we have the efficiency and trends - storage doesn't matter
                -- otherwise if the efficiency and trends got you here - you still must have 25% (modified by low triggers) of the resources
				if (MassStorage > ( MassNeeded * .25 * masslowtrigger) and EnergyStorage > ( EnergyNeeded * .25 * energylowtrigger))

                    or bypassecon then
                    
                    if aiBrain.UpgradeIssued < aiBrain.UpgradeIssuedLimit then

						if not unit.Dead then
                        
                            if ScenarioInfo.StructureUpgradeDialog then
                            
                                if bypassecon then
                                    --LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." CAN BYPASS ECO NEEDED")
                                end
                                
                                if ( econ.MassTrend >= MassTrendNeeded and econ.EnergyTrend >= EnergyTrendNeeded and econ.EnergyTrend >= EnergyMaintenance ) then
                                    LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." UPGRADING - M Trend "..(econ.MassTrend * 10).." needed "..(MassTrendNeeded * 10))
                                    LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." UPGRADING - E Trend "..(econ.EnergyTrend * 10).." needed "..(EnergyTrendNeeded * 10))
                                else
                                    LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." UPGRADING on storage M "..MassStorage.." needed "..MassNeeded)
                                    LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." UPGRADING on storage E "..EnergyStorage.." needed "..EnergyNeeded)
                                end
                            end
					
							-- if an upgrade was issued and resources were not completely full then delay based upon the condition of storage
                            -- moved the premise of the delay period from a fixed amount - to a period based on the buildtime of the upgrade

                            --LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." UPGRADING buildtime is "..buildtime.." ticks - cheat is "..aiBrain.MajorCheatModifier)

                            -- if either storage is below the mass or energy limit --
							if GetEconomyStoredRatio(aiBrain, 'MASS') < masslimit or GetEconomyStoredRatio(aiBrain, 'ENERGY') < energylimit then
                            
                                -- we'll use the MajorCheatModifier(66% of the full cheat) to reduce the longest delays
								ForkThread(SelfUpgradeDelay, aiBrain, math.min(400, buildtime*.40)/aiBrain.MajorCheatModifier )  -- delay the next upgrade by 40% of the upgrade build time
                                
							else
                                -- if either storage is NOT full -- medium delay - unaffected by cheat
                                if GetEconomyStoredRatio(aiBrain, 'MASS') < 1 or GetEconomyStoredRatio(aiBrain, 'ENERGY') < 1 then
                                
                                    ForkThread(SelfUpgradeDelay, aiBrain, math.min(240, buildtime*.2) )   -- otherwise only 20% the delay period   -- aiBrain.UpgradeIssuedPeriod
                                    
                                else
                                    -- both storages are full -- tiny 3 second delay - no matter what
                                    -- the 5 seconds allow this new upgrade to affect the eco values before another executes
                                    ForkThread(SelfUpgradeDelay, aiBrain, 30 )
                                end
                            end

							upgradeIssued = true

							IssueUpgrade({unit}, upgradeID)
                            
                            unit:AddOnUnitBuiltCallback( unit.OnUpgradeComplete, categories.ALLUNITS )
                            
                            --LOG("*AI DEBUG Upgrade Issued "..repr(unit))

							if ScenarioInfo.StructureUpgradeDialog then
								LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." UPGRADING TO "..repr(upgradeID).." "..repr(__blueprints[upgradeID].Description).." at game second "..GetGameTimeSeconds())
							end
						
							repeat
								WaitTicks(2)
							until unit.Dead or (unit.UnitBeingBuilt.BlueprintID == upgradeID)
                            
						end

                        if unit.Dead then
                            LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." to "..upgradeID.." failed.  Dead is "..repr(unit.Dead))
                            upgradeIssued = false
                        end

                        if upgradeIssued then
                            continue
                        end

                    end
                    
                else
                    if ScenarioInfo.StructureUpgradeDialog then
                        LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." can upgrade BUT fails base resources required check")
                    end
                end
                
            else
            
                if ScenarioInfo.StructureUpgradeDialog then
                
                    if econ.MassTrend < MassTrendNeeded then
                        LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." FAILS MASS Trend trigger "..(econ.MassTrend*10).." needed "..(MassTrendNeeded*10))
                        continue
                    end
                    
                    if econ.EnergyTrend < EnergyTrendNeeded then
                        LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." FAILS ENER Trend trigger "..(econ.EnergyTrend*10).." needed "..(EnergyTrendNeeded*10))
                        continue
                    end
                    
                    if econ.EnergyTrend < EnergyMaintenance then
                        LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." FAILS Maintenance trigger "..econ.EnergyTrend.." needs "..EnergyMaintenance)  
                        continue
                    end
                    
                    if MassStorage < MassNeeded then
                        LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." FAILS MASS storage trigger "..MassStorage.." needed "..MassNeeded)
                        continue
                    end
                    
                    if EnergyStorage < EnergyNeeded then
                        LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." FAILS ENER storage trigger "..EnergyStorage.." needed "..EnergyNeeded)
                        continue
                    end
                    
                end
                
			end
            
        else

            --if ScenarioInfo.StructureUpgradeDialog then
                --LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unit.Sync.id.." "..unit:GetBlueprint().Description.." Upgrade Counter already at max")
            --end
            
        end
        
    end
    
	if upgradeIssued then
		
		unit.Upgrading = true
		unit.DesiresAssist = true
        
        repeat 
            WaitTicks(1)
        until unit.UnitBeingBuilt.Sync
        
		local unitbeingbuilt = GetEntityById(unit.UnitBeingBuilt.Sync.id)
        
        unitbeingbuilt:AddUnitCallback( unitbeingbuilt.OnUpgradeComplete, 'OnStopBeingBuilt' )
        
        -- this was inserted to wait for the upgrade to complete - was originally doing it
        -- right away but got mysterious results with platoons disbanding and such
        -- so now we'll wait for it to be completed or die
        repeat
            WaitTicks(2)
        until unitbeingbuilt.Dead or unitbeingbuilt:GetFractionComplete() == 1
        
        if ScenarioInfo.StructureUpgradeDialog and unitbeingbuilt:GetFractionComplete() == 1 then
            LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unitbeingbuilt.Sync.id.." "..unitbeingbuilt:GetBlueprint().Description.." UPGRADE COMPLETE at game second "..GetGameTimeSeconds())
        end

        upgradeID = __blueprints[unitbeingbuilt.BlueprintID].General.UpgradesTo or false
		
		-- if the upgrade has a follow on upgrade - start an upgrade thread for it --
        if upgradeID and not unitbeingbuilt.Dead then
        
            if unitbeingbuilt.UpgradeThread then
                LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade "..unitbeingbuilt.Sync.id.." already has a thread")
                KillThread(unitbeingbuilt.UpgradeThread)
            end


			initialdelay = initialdelay + 60			-- increase delay before first check for next upgrade
			
			unitbeingbuilt.DesiresAssist = true			-- let engineers know they can assist this upgrade
            
            -- factory upgrades are possible right away after 30 minutes
            if EntityCategoryContains( categories.FACTORY, unitbeingbuilt ) then
            
                -- after 30 minutes factories have NO upgrade delay period
                -- allowing them to go right into upgrade if conditions permit
                -- and will check for being able to upgrade at a faster rate
                if aiBrain.CycleTime > 1800 then
                    initialdelay = 10
                    workrate = 14
                end
            end

            -- notice the use of 'workrate' here instead of the altered checkrate, thus keeping the original starting checkrate value
			unitbeingbuilt.UpgradeThread = unitbeingbuilt:ForkThread( SelfUpgradeThread, faction, aiBrain, masslowtrigger, energylowtrigger, masshightrigger, energyhightrigger, workrate, initialdelay, bypassecon )
        end
		
		-- assign mass extractors and hydrocarbons to their own platoons otherwise to StructurePool
		if (not unitbeingbuilt.Dead) and EntityCategoryContains( categories.MASSEXTRACTION, unitbeingbuilt) then
        
            local PlatoonCallForHelpAI = import('/lua/platoon.lua').Platoon.PlatoonCallForHelpAI
	
			local Mexplatoon = MakePlatoon( aiBrain,'MEXPlatoon'..tostring(unitbeingbuilt.Sync.id), 'none')
			
			Mexplatoon.BuilderName = 'MEXPlatoon'..tostring(unitbeingbuilt.Sync.id)
			Mexplatoon.MovementLayer = 'Land'
            Mexplatoon.UsingTransport = true        -- never review this platoon during a merge
			
			AssignUnitsToPlatoon( aiBrain, Mexplatoon, {unitbeingbuilt}, 'Support', 'none' )
		
			Mexplatoon:ForkThread( PlatoonCallForHelpAI, aiBrain, 4 )

		
		-- assign mass extractors and hydrocarbons to their own platoons otherwise to StructurePool
		elseif (not unitbeingbuilt.Dead) and EntityCategoryContains( categories.MASSFABRICATION, unitbeingbuilt) then
        
            local PlatoonCallForHelpAI = import('/lua/platoon.lua').Platoon.PlatoonCallForHelpAI
	
			local Mexplatoon = MakePlatoon( aiBrain,'FABPlatoon'..tostring(unitbeingbuilt.Sync.id), 'none')
			
			Mexplatoon.BuilderName = 'FABPlatoon'..tostring(unitbeingbuilt.Sync.id)
			Mexplatoon.MovementLayer = 'Land'
            Mexplatoon.UsingTransport = true        -- never review this platoon during a merge
			
			AssignUnitsToPlatoon( aiBrain, Mexplatoon, {unitbeingbuilt}, 'Support', 'none' )
		
			Mexplatoon:ForkThread( PlatoonCallForHelpAI, aiBrain, 8 )
          
		elseif (not unitbeingbuilt.Dead) and EntityCategoryContains( categories.HYDROCARBON, unitbeingbuilt) then
        
            local PlatoonCallForHelpAI = import('/lua/platoon.lua').Platoon.PlatoonCallForHelpAI
	
			local Mexplatoon = MakePlatoon( aiBrain,'HYDROPlatoon'..tostring(unitbeingbuilt.Sync.id), 'none')
			
			Mexplatoon.BuilderName = 'HYDROPlatoon'..tostring(unitbeingbuilt.Sync.id)
			Mexplatoon.MovementLayer = 'Land'
            Mexplatoon.UsingTransport = true        -- never review this platoon during a merge
			
			AssignUnitsToPlatoon( aiBrain, Mexplatoon, {unitbeingbuilt}, 'Support', 'none' )
		
			Mexplatoon:ForkThread( PlatoonCallForHelpAI, aiBrain, 4 )
            
        elseif (not unitbeingbuilt.Dead) then

            AssignUnitsToPlatoon( aiBrain, aiBrain.StructurePool, {unitbeingbuilt}, 'Support', 'none' )
		end

        KillThread( unit.UpgradeThread )
    end
end

-- SELF UPGRADE DELAY
-- the purpose of this function is to prevent self-upgradeable structures 
-- from all trying to upgrade at once - when an upgrade is begun - the
-- counter is increased by one -- for a period of time - in operation this prevents
-- more than a certain number of self-upgrades in a short time period
-- and the delays are related to the buildtime of the upgrade itself
function SelfUpgradeDelay( aiBrain, delay )

    aiBrain.UpgradeIssued = aiBrain.UpgradeIssued + 1
    
    if ScenarioInfo.StructureUpgradeDialog then
        LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade counter up to "..aiBrain.UpgradeIssued.."/"..aiBrain.UpgradeIssuedLimit.." - delay period is "..(delay/10).." seconds")
    end

    WaitTicks( delay )
	
    aiBrain.UpgradeIssued = aiBrain.UpgradeIssued - 1
    
    if ScenarioInfo.StructureUpgradeDialog then
        LOG("*AI DEBUG "..aiBrain.Nickname.." STRUCTUREUpgrade counter down to "..aiBrain.UpgradeIssued.."/"..aiBrain.UpgradeIssuedLimit)
    end
end

-- this function identifies units in a platoon that may have air/land toggle weapons
-- launches the airlandtogglethread on those units - you know - it would be nice if 
-- such units had that thread launched at build rather than as a platoon function
function AirLandToggle(platoon, aiBrain)

    for k,v in GetPlatoonUnits(platoon) do
	
		local weapons = v:GetBlueprint().Weapon
		
		for _,w in weapons do
			if w.ToggleWeapon then
				for n,wType in w.FireTargetLayerCapsTable do
				
					if string.find( wType, 'Air' ) then
						if not v.Dead and not v.AirLandToggleThread then
							v.AirLandToggleThread = v:ForkThread( AirLandToggleThread, aiBrain )
							break
						end
					end
				end
			end
		end
    end		
end

-- this function is quite simple - in concept - utilize the weapon toggle that some units have
-- which allow it to shoot both at AIR units and LAND/NAVAL units
function AirLandToggleThread(unit, aiBrain)
	
    local GetNumUnitsAroundPoint = GetNumUnitsAroundPoint
    local WaitTicks = WaitTicks
	
    local bp = __blueprints[unit.BlueprintID]
    
    local weapons = bp.Weapon
    local antiAirRange, landRange, weaponType
	
    local toggleWeapons = {}
    local unitCat = ParseEntityCategory( unit.BlueprintID )
	
    for _,v in weapons do
        if v.ToggleWeapon then
            weaponType = 'Land'
            for n,wType in v.FireTargetLayerCapsTable do
                if string.find( wType, 'Air' ) then
                    weaponType = 'Air'
                    break
                end
            end
            if weaponType == 'Land' then
                landRange = v.MaxRadius
            else
                antiAirRange = v.MaxRadius
            end
        end
    end
	
    if not landRange or not antiAirRange then
        return
    end
	
    while not unit.Dead and IsUnitState( unit, 'Busy') do
        WaitTicks(22)
    end
	
	local position, numAir, numGround, frndAir, frnGround
	local GetPosition = GetPosition
	
    while not unit.Dead do
	
        position = GetPosition(unit)
		
        numAir = GetNumUnitsAroundPoint( aiBrain, ( categories.AIR ), position, antiAirRange, 'Enemy' )
        numGround = GetNumUnitsAroundPoint( aiBrain, ( categories.ALLUNITS - categories.AIR - categories.WALL ), position, landRange, 'Enemy' )
		
        frndAir = GetNumUnitsAroundPoint( aiBrain, ( categories.AIR * categories.ANTIAIR ), position, antiAirRange, 'Ally' )
        frndGround = GetNumUnitsAroundPoint( aiBrain, ( categories.LAND + categories.NAVAL) - unitCat, position, landRange, 'Ally' )
		
        if numAir > 5 and frndAir < 3 then
		
            unit:SetScriptBit('RULEUTC_WeaponToggle', false)	#-- air mode
			
        elseif numGround > ( numAir * 1.5 ) then
		
            unit:SetScriptBit('RULEUTC_WeaponToggle', true)		#-- ground mode
			
        elseif frndAir > frndGround then
		
            unit:SetScriptBit('RULEUTC_WeaponToggle', true)
			
        else
		
            unit:SetScriptBit('RULEUTC_WeaponToggle', false) # default to air mode
			
        end
		
        WaitTicks(100)
    end
end


--	Table: SurfacePriorities AKA "Your stuff just got wrecked" priority list.
--	Provides a list of target priorities an experimental should use when
--	wrecking stuff or deciding what stuff should be wrecked next.
local SurfacePriorities = { 
	'STRUCTURE ARTILLERY -TECH2',

	'MASSEXTRACTION -TECH2',
	
	'MASSFABRICATION -TECH2',

	'STRUCTURE INTELLIGENCE -TECH1',

	'ANTIMISSILE -TECH2',

	'STRUCTURE NUKE',

	'MOBILE LAND EXPERIMENTAL',

	'SHIELD',

	'DEFENSE STRUCTURE ANTIAIR TECH3',
	'DEFENSE STRUCTURE DIRECTFIRE TECH3',
	
	'FACTORY STRUCTURE -TECH1',

	'STRUCTURE ANTINAVY',
	
	'EXPERIMENTAL STRUCTURE',
	
    'ENERGYPRODUCTION STRUCTURE TECH3',
	
	'MOBILE LAND TECH3',	
	
    'COMMAND',
	'SUBCOMMANDER',

}


function AssignArtilleryPriorities( platoon )
	
	for _,v in GetPlatoonUnits(platoon) do
		if v != nil then
			v:SetTargetPriorities( SurfacePriorities )
		end
	end
end

-- Using it's PrioritizeCategories list, loop thru the HiPri list looking for the target
-- with the most number of targets.
-- Returns:  target unit, target base, else nil
function FindExperimentalTarget( self, aiBrain )
   
    if not aiBrain.IL or not aiBrain.IL.HiPri then
		LOG("*AI DEBUG FindExperimentalTarget says it has no interest list")
        return
    end
	
	local GetUnitsAroundPoint = GetUnitsAroundPoint

    local enemyBases = aiBrain.IL.HiPri	

	local SurfacePriorities = self.PlatoonData.PrioritizedCategories
   
    --	For each priority type in SurfacePriorities, check each HiPri position we're aware of (through scouting/intel),
    --	The position with the most number of the targets gets selected. If there's a tie, pick closer. 
	-- this has been changed to locate the closest first --
    for _, priority in SurfacePriorities do
		
        local bestBase = false
        local mostUnits = 0
        local bestUnit = false
        
        for _, base in enemyBases do
		
			--LOG("*AI DEBUG "..aiBrain.Nickname.." FindExperimentalTarget checks threat position at ".. repr(base))
			
			local unitsAtBase = false
			
            local unitsAtBase = GetUnitsAroundPoint( aiBrain, ParseEntityCategory(priority), base.Position, 100, 'Enemy')
			
            local numUnitsAtBase = 0
            local notDeadUnit = false
            
			if unitsAtBase[1] then
			
				--LOG("*AI DEBUG "..aiBrain.Nickname.." FindExperimentalTarget finds "..LOUDGETN(unitsAtBase).." "..repr(priority).." units at "..repr(base.Position) )

				for _,unit in unitsAtBase do
				
					if not unit.Dead and GetPosition(unit) then
					
						notDeadUnit = unit
						numUnitsAtBase = numUnitsAtBase + 1
						
					end
					
				end
            
				WaitTicks(1)
            
				if numUnitsAtBase > 0 then
				
					if not bestBase then
					
						bestBase = base
						bestUnit = notDeadUnit
						
					else
	
						local myPos = GetPlatoonPosition(self)
						
						local dist1 = LOUDV3( myPos, base.Position )
						local dist2 = LOUDV3( myPos, bestBase.Position )
                    
						if dist1 < dist2 then
						
							bestBase = base
							bestUnit = notDeadUnit
							
						end
						
					end	

--[[					
					if numUnitsAtBase > mostUnits then
					
						bestBase = base
						mostUnits = numUnitsAtBase
						bestUnit = notDeadUnit
						
					elseif numUnitsAtBase == mostUnits then
					
						local myPos = GetPlatoonPosition(self)
						local dist1 = LOUDV3( myPos, base.Position )
						local dist2 = LOUDV3( myPos, bestBase.Position )
                    
						if dist1 < dist2 then
							bestBase = base
							bestUnit = notDeadUnit
						end
						
					end
--]]					
				end
				
			else
				--LOG("*AI DEBUG FindExperimentalTarget finds no units for "..repr(priority).." at "..repr(base.Position))
			end
			
        end
        
        if bestBase and bestUnit then
		
			--LOG("*AI DEBUG "..aiBrain.Nickname.." FindExperimentalTarget returns a "..repr(priority).." target unit at " ..repr(bestBase))
			
            return bestUnit, bestBase
			
        end
		
    end
	
	--LOG("*AI DEBUG "..aiBrain.Nickname.." FindExperimentalTarget returns NO target")
	
	return false, false
	
end

function GetThreatOfUnits(platoon)
    local totalThreat = 0
    local bpThreat = 0
    local layer = platoon.MovementLayer
	local bp
	
    for _,u in GetPlatoonUnits(platoon) do
	
		bpThreat = 0
		
        if not u.Dead then 
		
	        bp = __blueprints[u.BlueprintID].Defense
			
            if layer == 'Land' then
                bpThreat = bp.SurfaceThreatLevel
            elseif layer == 'Water' then
                bpThreat = bp.SurfaceThreatLevel
				if bp.SubThreatLevel then
					bpThreat = bpThreat + bp.SubThreatLevel
				end
            elseif layer == 'Amphibious' then
                bpThreat = bp.SurfaceThreatLevel
				if bp.SubThreatLevel then
					bpThreat = bpThreat + bp.SubThreatLevel
				end
            elseif layer == 'Air' then
                bpThreat = bp.SurfaceThreatLevel
                if bp.AirThreatLevel then
                    bpThreat = bpThreat + bp.AirThreatLevel
                end
				if bp.SubThreatLevel then
					bpThreat = bpThreat + bp.SubThreatLevel
				end
            end
			
			totalThreat = totalThreat + bpThreat
			
        end 
		
    end
	
	LOG("*AI DEBUG Platoon Threat for "..repr(platoon.BuilderName).." on layer "..repr(layer))
	LOG("*AI DEBUG  AIR        is "..repr(platoon:CalculatePlatoonThreat('Air', categories.ALLUNITS)).." versus "..totalThreat)
	LOG("*AI DEBUG ANTIAIR     is "..repr(platoon:CalculatePlatoonThreat('AntiAir', categories.ALLUNITS)).." versus "..totalThreat)
	LOG("*AI DEBUG Artillery   is "..repr(platoon:CalculatePlatoonThreat('Air', categories.ALLUNITS)).." versus "..totalThreat)	
	LOG("*AI DEBUG  LAND       is "..repr(platoon:CalculatePlatoonThreat('Land', categories.ALLUNITS)).." versus "..totalThreat)
	LOG("*AI DEBUG  NAVAL      is "..repr(platoon:CalculatePlatoonThreat('Naval', categories.ALLUNITS)).." versus "..totalThreat)
	LOG("*AI DEBUG SURFACE     is "..repr(platoon:CalculatePlatoonThreat('AntiSurface', categories.ALLUNITS)).." versus "..totalThreat)
	LOG("*AI DEBUG OVERALL IS     "..repr(platoon:CalculatePlatoonThreat('Overall', categories.ALLUNITS)).." versus "..totalThreat)
	
    return totalThreat
	
end

--	Goes through the SurfacePriorities table looking for the enemy base (high priority scouting location. See ScoutingAI in platoon.lua) 
--	with the most number of the highest priority targets.
--	Returns:  target unit, target base, else nil
-- THIS FUNCTION APPEARS TO BE USED ONLY BY THE FATBOY AI
function FindLandExperimentalTargetLOUD( self, aiBrain )

    local enemyBases = aiBrain.IL.HiPri
	
	local mapSizeX = ScenarioInfo.size[1]
	local mapSizeZ = ScenarioInfo.size[2]
	
	local mapsize = LOUDSQUARE( (mapSizeX * mapSizeX) + (mapSizeZ * mapSizeZ) )  # maximum possible distance on this map
	
	local myPos = self:GetPlatoonPosition()
	
	local enemythreattype = 'AntiSurface'	
	
	if self.MovementLayer == 'Air' then
		enemythreattype = 'AntiAir'
	end
	
	local mythreat = GetThreatOfUnits(self)		--import('/lua/ai/aiattackutilities.lua').GetThreatOfUnits(self)
	
    local bestBase = false
    local bestTotal = 0
    local bestUnit = false
   
    if not aiBrain.IL or not aiBrain.IL.HiPri then
		LOG("*AI DEBUG FindExperimentalTarget says it has no interest list")
        return
    end
    
	for _, base in enemyBases do
	
		-- check if position is on the water - skip 
		if LocationInWaterCheck(base.Position) and self.MovementLayer != 'Air' then
			continue
		end
	
		local distance = LOUDV3( { self.StartPosX, 0, self.StartPosZ }, base.Position )
		local RangeModifier = mapsize/distance
		
		local numUnitsAtBase = 0
		
		local surfacethreat = 0
		local airthreat = 0
		
		local targetthreat = 0
		local threatfactor = 0
		
		local notDeadUnit = false
		
		local unitsAtBase = aiBrain:GetUnitsAroundPoint( categories.ALLUNITS, base.Position, 70, 'Enemy')
		
        for _, priority in SurfacePriorities do
            
            for _,unit in EntityCategoryFilterDown( ParseEntityCategory(priority), unitsAtBase) do
			
                if not unit.Dead and GetPosition(unit) then
	                notDeadUnit = unit
					break
	            end
            end
			
			numUnitsAtBase = EntityCategoryCount( ParseEntityCategory(priority), unitsAtBase )
		end
		
		targetthreat = 0
		
		if self.MovementLayer == 'Air' then
			targetthreat = base.AirThreat
		else
			targetthreat = base.SurThreat
		end
		
		if targetthreat > 1 then
			threatfactor = mythreat/targetthreat
		else
			threatfactor = 10
		end
		
		if threatfactor < 1 then
			threatfactor = threatfactor * 0.5
		elseif threatfactor > 10 then
			threatfactor = 10
		end
		
		if numUnitsAtBase > 10 then
			numUnitsAtBase = 10
		end
		
		numUnitsAtBase = (numUnitsAtBase * threatfactor) * RangeModifier
		
		LOG("*AI DEBUG Resulting in a value for target of " .. numUnitsAtBase)

        if numUnitsAtBase > bestTotal then
            bestBase = base
            bestTotal = numUnitsAtBase
            bestUnit = notDeadUnit
        end
		
	end

    if bestBase and bestUnit then
        return bestUnit, bestBase
    end
	
	return false, false
	
end


-- =======================
-- CZAR Behaviour - SORIAN
-- =======================
CzarBehaviorSorian = function(self, aiBrain)
	
    if not PlatoonExists( aiBrain, self ) then
        return
    end
	
	LOG("*AI DEBUG "..aiBrain.Nickname.." CzarSorian starts")

	local platoonUnits = GetPlatoonUnits(self)
    
    for _, czar in platoonUnits do
        czar.EventCallbacks['OnHealthChanged'] = nil
    end
	
	local cmd
    
	-- find a target from the PrioritizedCategories data
    local targetUnit = FindExperimentalTarget( self, aiBrain )
	
    local oldTargetUnit = false
	
    while PlatoonExists( aiBrain, self ) do
	
		if not targetUnit then
		
			return self:SetAIPlan('ReturnToBaseAI',aiBrain)
			
		end
		
        if (targetUnit and targetUnit != oldTargetUnit) or not self:IsCommandsActive(cmd) then

			-- move towards the target --
			if targetUnit and VDist3( GetPosition(targetUnit), GetPlatoonPosition(self) ) > 100 then
			
			    IssueClearCommands(platoonUnits)
				
				-- interesting way to get the Czar moving towards target --
				cmd = ExpPathToLocation(aiBrain, self, 'Air', GetPosition(targetUnit), false, 300)
				
			-- in range of the target, issue attack order --
			elseif targetUnit and VDist3( GetPosition(targetUnit), GetPlatoonPosition(self) ) <= 100 then

                cmd = self:AttackTarget( targetUnit )
				
			end
			
        end
		
		-- see if you're near any override target
        local nearCommander = CommanderOverrideCheckSorian(self,aiBrain)
		
        local oldCommander = nil
		
		-- loop here if we have an override target until we don't have an override target anymore
        while nearCommander and PlatoonExists( aiBrain, self ) and self:IsCommandsActive(cmd) do
		
            if nearCommander and nearCommander != oldCommander then
			
                IssueClearCommands(platoonUnits)
				
                cmd = self:AttackTarget( nearCommander)
				
                targetUnit = nearCommander
				
            end
            
            WaitSeconds(8)
			
            oldCommander = nearCommander
			
			-- see if there is a better override target attack
            nearCommander = CommanderOverrideCheckSorian(self,aiBrain)
			
        end
    
		WaitTicks(80)
		
		-- only switch targets when they are dead
		if targetUnit.Dead then

			oldTargetUnit = targetUnit
		
			targetUnit = FindExperimentalTarget(self, aiBrain)
			
		end
		
	end
	
end

CommanderOverrideCheckSorian = function(self, aiBrain)

	local platoonUnits = GetPlatoonUnits(self)
    local experimental
	
	-- identify if we have an experimental or not
	for k,v in platoonUnits do
	
		if not v:IsDead() then
		
			experimental = v
			break
			
		end
		
	end
	
	if not experimental or experimental:IsDead() then
		return false
	end

    local commanders = aiBrain:GetUnitsAroundPoint(categories.COMMAND, GetPlatoonPosition(self), 50, 'Enemy')
    
    if LOUDGETN(commanders) == 0 or commanders[1]:IsDead() or commanders[1]:GetCurrentLayer() == 'Seabed' then
	
		#LOG("*AI DEBUG CommanderOverride reports no commanders found within weapon range")
        return false
    end
    
    local mainWeapon = experimental:GetWeapon(1)
    local currentTarget = mainWeapon:GetCurrentTarget()
    
    if commanders[1] ~= currentTarget then
	
		LOG("*AI DEBUG CommanderOverride resetting main weapon to retarget commander")
		
        --Commander in range who isn't our current target. Force weapons to reacquire targets so they'll grab him.
		for k,v in platoonUnits do
		
			if not v:IsDead() then
			
				for i=1, v:GetWeaponCount() do
				
					v:GetWeapon(i):ResetTarget()
					
				end
				
			end
			
		end
		
    end
    
    -- return the commander so an attack order can be issued or something
    return commanders[1]
end

-- Credit to Sorian - very concise way to handle platoon movement orders
ExpPathToLocation = function(aiBrain, platoon, layer, dest, aggro, markerdist)

	local cmd = false

	local path, reason = platoon.PlatoonGenerateSafePathToLOUD(aiBrain, platoon, layer, GetPlatoonPosition(platoon), dest, 150, markerdist )
	
	if not path then
	
		if aggro == 'AttackMove' then
		
			cmd = platoon:AggressiveMoveToLocation(dest)
			
		elseif aggro == 'AttackDest' then
		
			-- Let the main script issue the move to attack the target
			
		else
		
			cmd = platoon:MoveToLocation(dest, false)
			
		end
		
	else
	
		local pathSize = LOUDGETN(path)
		
		for k, point in path do
		
			if k == pathSize and aggro == 'AttackDest' then
			
				-- Let the main script issue the move to attack the target
				
			elseif aggro == 'AttackMove' then
			
				cmd = platoon:AggressiveMoveToLocation(point)
				
			else
			
				cmd = platoon:MoveToLocation(point, false)
				
			end
			
		end 
		
	end
	
	return cmd
end



-- returns true if the platoon is presently in the water
function InWaterCheck(platoon)

	local t4Pos = GetPlatoonPosition(platoon)
	
	return GetTerrainHeight(t4Pos[1], t4Pos[3]) < GetSurfaceHeight(t4Pos[1], t4Pos[3])
end

-- returns true if the position is in the water
function LocationInWaterCheck(position)
	return GetTerrainHeight(position[1], position[3]) < GetSurfaceHeight(position[1], position[3])
end


--	Finds the experiemental unit in the platoon (assumes platoons are only experimentals)
--	Assigns any extra experimentals to guard the first
function GetExperimentalUnit( platoon )

    local unit = nil
	
    for _,v in GetPlatoonUnits(platoon) do
	
		if not v.Dead and unit then
		
			IssueGuard( {v}, unit )
			
		end
		
        if not v.Dead and not unit then
		
            unit = v
			
        end
		
    end
	
    return unit
	
end

-- Sets the experimental's land weapon target priorities to the SurfacePriorities table.
function AssignExperimentalPriorities( platoon )
	local experimental = GetExperimentalUnit(platoon)
	if experimental then
    	experimental:SetTargetPriorities( SurfacePriorities )
	end
end

-- Generic experimental AI. Find closest HiPriTarget and go attack it. 
function BehemothBehavior(self)   

    local aiBrain = GetAIBrain(self)
    local experimental = GetExperimentalUnit(self)
	
	local markerlist = false
	local patrolling = false
	
	LOG("*AI DEBUG Behemoth Behavior starts")
	
    #AssignExperimentalPriorities(self)
	
	local targetlist = import('/lua/ai/altaiutilities.lua').GetHiPriTargetList(aiBrain, experimental:GetPosition() )
	local target = false
	local targetLocation = false
    local oldTargetLocation = false
	local targetvalue = 9999999
	
	LOUDSORT(targetlist, function(a,b) return a.Distance < b.Distance end )

	for _, Target in targetlist do
	
		if LocationInWaterCheck(Target.Position) then
			continue # skip water targets
		end

		local distancefactor = aiBrain.dist_comp/Target.Distance   # makes closer targets more valuable
		
		local sthreat = Target.Threats.Sur
		local ethreat = Target.Threats.Eco
		local mythreat = GetThreatOfUnits(self)		--import('/lua/ai/aiattackutilities.lua').GetThreatOfUnits(self)
		
		if sthreat > mythreat then
			sthreat = mythreat
		end
		if ethreat > mythreat then
			ethreat = mythreat
		end
		
		local allthreat = sthreat + ethreat
		
		local value = LOUDFLOOR( allthreat * distancefactor ) 
		
		if value < targetvalue and value > 0 then
			target = Target
			targetvalue = value
			targetLocation = Target.Position
		end
	end

    while not experimental.Dead do

        if (targetLocation) and experimental:GetHealthPercent() > .75 then
		
            IssueClearCommands({experimental})
			
			local path, reason = self.PlatoonGenerateSafePathToLOUD(aiBrain, self, 'Amphibious', GetPlatoonPosition(self), targetLocation, 150, 200)

			if path then
				local pathsize = LOUDGETN(path)
				
				for waypoint,p in path do
					if LocationInWaterCheck(p) then
						self:MoveToLocation( p, false )
					else
						self:AggressiveMoveToLocation( p )
					end
				end
			else
				self:AggressiveMoveToLocation( targetLocation )
			end
			
            IssueAggressiveMove({experimental}, targetLocation) 
			patrolling = false
			
			while LOUDV3( experimental:GetPosition(), targetLocation ) > 10 and not experimental.Dead and experimental:GetHealthPercent() > .42 do
				WaitTicks(20)
				pos = experimental:GetPosition()
			end
			
            while not experimental.Dead and experimental:GetHealthPercent() > .42 and WreckBase( self, target ) and not InWaterCheck(self) do
				LOG("*AI DEBUG Behemoth cleansing target area")
				WaitTicks(20)
            end
		
        elseif not targetLocation or experimental:GetHealthPercent() <= .75 then

			if not patrolling then
				IssueClearCommands({experimental})
				self:ForkThread( self.PlatoonPatrolPointAI, aiBrain )
				patrolling = true
				targetLocation = nil
			end
		
			while experimental:GetHealthPercent() <= .85 and not experimental.Dead do
				WaitTicks(150)
			end
		end
       
        WaitTicks(50)
		
        oldTargetLocation = targetLocation
		
		targetlist = import('/lua/ai/altaiutilities.lua').GetHiPriTargetList(aiBrain, experimental:GetPosition() )
		target = false
		targetLocation = false
		targetvalue = 9999999
	
		LOUDSORT(targetlist, function(a,b) return a.Distance < b.Distance end )

		for _, Target in targetlist do
	
			if LocationInWaterCheck(Target.Position) and self.MovementLayer != 'Air' then
				continue # skip water targets
			end

			distancefactor = aiBrain.dist_comp/Target.Distance   # makes closer targets more valuable
		
			allthreat = Target.Threats.Sur + Target.Threats.Eco
		
			value = LOUDFLOOR( allthreat * distancefactor ) 
		
			if value < targetvalue and value > 0 then
				target = Target
				targetvalue = value
				targetLocation = Target.Position
			end
		end		
		
		if not targetLocation then
			LOG("*AI DEBUG Behemoth - no target")
		end
    end
end
--]]


--[[
--	Goes through the SurfacePriorities table looking for the enemy base (high priority scouting location. See ScoutingAI in platoon.lua) 
--	with the most number of the highest priority targets.
--	Returns:  target unit, target base, else nil
function FindNavalExperimentalTargetLOUD( self )

    local aiBrain = GetAIBrain(self)
    local enemyBases = aiBrain.IL.HiPri
	
	local mapSizeX = ScenarioInfo.size[1]
	local mapSizeZ = ScenarioInfo.size[2]
	local mapsize = LOUDSQUARE( (mapSizeX * mapSizeX) + (mapSizeZ * mapSizeZ) )  # maximum possible distance on this map
	local myPos = self:GetPlatoonPosition()
	
	local enemythreattype = 'AntiSurface'	
	
	if self.MovementLayer == 'Air' then
		enemythreattype = 'AntiAir'
	end
	
	local mythreat = GetThreatOfUnits(self)		--import('/lua/ai/aiattackutilities.lua').GetThreatOfUnits(self)
	
    local bestBase = false
    local bestTotal = 0
    local bestUnit = false
   
    if not aiBrain.IL or not aiBrain.IL.HiPri then
		LOG("*AI DEBUG FindNavalExperimentalTarget says it has no interest list")
        return
    end
    
	for _, base in enemyBases do
	
		if not LocationInWaterCheck(base.Position) then
			continue #break
		end
	
		local distance = LOUDV3( myPos, base.Position )
		local RangeModifier = math.log10( mapsize/distance)
		
		local numUnitsAtBase = 0
		
		local surfacethreat = 0
		local airthreat = 0
		
		local targetthreat = 0
		local threatfactor = 0
		
		local notDeadUnit = false
		
        for _, priority in SurfacePriorities do

            local unitsAtBase = aiBrain:GetUnitsAroundPoint( ParseEntityCategory(priority), base.Position, 60, 'Enemy')
            
            for _,unit in unitsAtBase do
                if not unit.Dead and unit:GetPosition() then
                    notDeadUnit = unit
					numUnitsAtBase = numUnitsAtBase + 1
                end
            end
		end
		
		targetthreat = 0
		
		if self.MovementLayer == 'Air' then
			targetthreat = base.AirThreat
		else
			targetthreat = base.SurThreat
		end
		
		if targetthreat > 1 then
			threatfactor = mythreat/targetthreat
		else
			threatfactor = 10
		end
		
		if threatfactor < .1 then
			threatfactor = .1
		elseif threatfactor > 10 then
			threatfactor = 10
		end
		
		if numUnitsAtBase > 10 then
			numUnitsAtBase = 10
		end
		
		numUnitsAtBase = (numUnitsAtBase * threatfactor) * RangeModifier

        if numUnitsAtBase > bestTotal then
            bestBase = base
            bestTotal = numUnitsAtBase
            bestUnit = notDeadUnit
        end
	end

    if bestBase and bestUnit then
        return bestUnit, bestBase
    end
	
	return false, false
	
end

function FatBoyBehavior(self, aiBrain)   

    local experimental = GetExperimentalUnit(self)
    local lastBase = false
    local mainWeapon = experimental:GetWeapon(1)
	local markerlist = false
	local oldTargetLocation = nil
	local patrolling = false
    local targetUnit = false
	local wavesize = 20
    local weaponRange = mainWeapon:GetBlueprint().MaxRadius
	
    --AssignExperimentalPriorities(self)
    
    experimental.Platoons = experimental.Platoons or {}
    
    while not experimental.Dead do
	
		-- first task is to find a target
        targetUnit, lastBase = FindLandExperimentalTargetLOUD(self, aiBrain)

		if targetUnit and experimental:GetHealthPercent() >= .75 then
			
			IssueClearCommands({experimental})
			patrolling = false
			oldTargetLocation = {lastBase.Position[1], lastBase.Position[2], lastBase.Position[3]}

			local path, reason = self.PlatoonGenerateSafePathToLOUD(aiBrain, self, 'Amphibious', self:GetPlatoonPosition(), oldTargetLocation, 120, 200)
			
			if path then
				local pathsize = LOUDGETN(path)
				
				for waypoint,p in path do
					if LocationInWaterCheck(p) then
						self:MoveToLocation( p, false )
					else
						self:AggressiveMoveToLocation( p )
					end
				end

			else
				self:AggressiveMoveToLocation( oldTargetLocation )
			end
			
			local pos = experimental:GetPosition()

			-- and travel to the target area
            while LOUDV3( pos, oldTargetLocation ) > weaponRange + 45 and not experimental.Dead	and not experimental:IsIdleState() and experimental:GetHealthPercent() > .5 do
				WaitTicks(50)
				pos = experimental:GetPosition()
            end
			
			while not experimental:IsIdleState() and ( WreckBase(self, lastBase) == nil )
				and not experimental.Dead and experimental:GetHealthPercent() > .5
				or InWaterCheck(self) do
				LOG("*AI DEBUG Fatboy finds no target or is in the water - will keep moving")
				WaitTicks(50)
			end

			
			LOG("*AI DEBUG FatBoy in range of target")
			
            IssueClearCommands({experimental})
            
			# ================================
			# Rebuild list of Fatboys platoons
			# ================================
            local goodList = {}
            
            for _, platoon in experimental.Platoons do
                local platoonUnits = false
                
                if PlatoonExists( aiBrain, platoon ) then
                    platoonUnits = GetPlatoonUnits(platoon)
				end
                if platoonUnits and LOUDGETN(platoonUnits) > 0 then
                    LOUDINSERT(goodList, platoon)
                end
            end
            experimental.Platoons = goodList
			
			# =====================
            # Attack Fatboys target
			# =====================
            for _, platoon in goodList do
                platoon:ForkAIThread(FatboyChildBehavior, self, lastBase)
            end
            # ===========================
            # Build a platoon of 20 units
			# ===========================
            while not experimental.Dead and experimental:GetHealthPercent() > .5 and WreckBase(self, lastBase) and not InWaterCheck(self) do
			
                FatBoyBuildCheck(self)
				
                if experimental.NewPlatoon and LOUDGETN(experimental.NewPlatoon:GetPlatoonUnits()) >= wavesize then
					#LOG("*AI DEBUG Launching Fatboy platoon at target")
                    experimental.NewPlatoon:ForkAIThread(FatboyChildBehavior, self, lastBase)
                    LOUDINSERT(experimental.Platoons, experimental.NewPlatoon)
                    experimental.NewPlatoon = nil
					wavesize = wavesize + 2
                end
                WaitTicks(10)
            end
			
			targetUnit, lastBase = FindLandExperimentalTargetLOUD(self, aiBrain)
			
			if experimental:GetHealthPercent() <= .5 then
				for _, platoon in experimental.Platoons do
					platoon:SetAIPlan( 'ReturnToBaseAI',aiBrain )
				end
				experimental.Platoons = {}
			end
			
        else
			if not patrolling then
				IssueClearCommands({experimental})
				self:ForkThread( self.PlatoonPatrolPointAI, aiBrain )
				patrolling = true
				
				if experimental.NewPlatoon then
					experimental.NewPlatoon:SetAIPlan( 'ReturnToBaseAI', aiBrain )
				end
				
				for _, platoon in experimental.Platoons do
					platoon:SetAIPlan( 'ReturnToBaseAI',aiBrain )
				end
				experimental.Platoons = {}
				
			end
			while experimental:GetHealthPercent() <= .85 and not experimental.Dead do
				WaitTicks(150)
			end
		end
	
        WaitTicks(60)
    end
	
end

-------------------------------------------------------
--   Function: FatBoyBuildCheck
--   Args:
--       self - single-fatboy platoon to build a unit with
--   Description:
--       Builds a random unit
--   Returns:  
--       nil
-------------------------------------------------------
function FatBoyBuildCheck(self)
    local aiBrain = GetAIBrain(self)
    local experimental = GetExperimentalUnit(self)
	local buildUnits = {}
    
    #Randomly build T3 MMLs, percivals, T3 Arty, T2 Shields and siege bots .
    
	if LOUDENTITY( categories.UEF, experimental) then
		buildUnits = {'uel0303', 'uel0307', 'uel0304', 'xel0305', 'xel0306', 'delk002', }
	end
	
	local buildx = Random(1,LOUDGETN(buildUnits))
	local unitToBuild = buildUnits[buildx]
	
	if LOUDENTITY( categories.UEF, experimental) then
	    aiBrain:BuildUnit( experimental, unitToBuild, 1 )
	end
	
    WaitTicks(1)
    
    local unitBeingBuilt = false
	
    repeat 
		LOG("*AI DEBUG FatBoyBuildCheck Wait loop")
        unitBeingBuilt = unitBeingBuilt or experimental.UnitBeingBuilt
        WaitTicks(25)
    until experimental.Dead or unitBeingBuilt 
    
    repeat
        WaitTicks(35)
    until experimental.Dead or experimental:IsIdleState() 
    
    if unitBeingBuilt and not unitBeingBuilt.Dead then
		#LOG("*AI DEBUG FatBoyBuildCheck assigning new unit to platoon")
        
        if not experimental.NewPlatoon or not PlatoonExists( aiBrain, experimental.NewPlatoon ) then
            LOG("*AI DEBUG FatBoyBuildCheck creating new platoon")
            experimental.NewPlatoon = MakePlatoon( aiBrain, 'FatBoyGroup', 'none' )
			experimental.NewPlatoon.BuilderName = 'FatBoyGroup'
        end
        
        AssignUnitsToPlatoon( aiBrain, experimental.NewPlatoon, {unitBeingBuilt}, 'Attack', 'None' )
        IssueClearCommands( {unitBeingBuilt})
--      IssueGuard( {unitBeingBuilt}, experimental)
    end
	
end

-------------------------------------------------------
--   Function: FatboyChildBehavior
--   Args:
--       self - the platoon of fatboy children to run the behavior on
--       parent - the parent fatboy that the child platoon belongs to
--       base - the base to be attacked
--   Description:
--       AI for fatboy child platoons. Wrecks the base that the fatboy has selected.
--       Once the base is wrecked, the units will return to the fatboy until a new
--       target base is reached, at which point they will attack it.
--   Returns:  
--       nil
-------------------------------------------------------
function FatboyChildBehavior(self, parent, base)   
		local aiBrain = GetAIBrain(self)
		local experimental = GetExperimentalUnit(parent)
		local targetUnit = false
     
    #Find target loop
	
    while PlatoonExists( aiBrain, self ) and LOUDGETN( GetPlatoonUnits(self) ) > 0 do

        targetUnit, base = WreckBase( parent, base)
        
        local units = GetPlatoonUnits(self)

        if not base and not experimental.Dead then
            #Wrecked base. Kill AI thread
            IssueClearCommands(units)
            if LOUDV3(self:GetPlatoonPosition(), experimental:GetPosition()) > 30 then
                self:SetPlatoonFormationOverride('GrowthFormation')
                IssueMove( GetPlatoonUnits(self), experimental:GetPosition() )
--            IssueGuard(units, experimental)
            end
            
            return
            
        elseif not base and experimental.Dead then
			IssueClearCommands(units)
			return self:ReturnToBaseAI(aiBrain)
            
		end
        
        if targetUnit then
            IssueClearCommands(units)
            IssueFormAggressiveMove(units, targetUnit, 'AttackFormation', 0)
        end
        
        #Walk to and kill target loop
        while aiBrain:PlatoonExists(self) and LOUDGETN(self:GetPlatoonUnits()) > 0 and not targetUnit.Dead do           
            WaitTicks(50)
        end
    
        WaitTicks(50)
    end
end

--]]
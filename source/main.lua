import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/crank"

--Shortcuts
local gfx <const> = playdate.graphics

--Sprites
local playerSprite = nil -- Player sprite (car) that is steerable
local car1Sprite = nil -- Car sprite in the right lane of the road
local car2Sprite = nil -- Car sprite in the left lane of the road 
local stripeSprite = nil -- Center stripe sprite on the road
local shifterSprite = nil -- Gear shifter sprite
local wheelSprite = nil -- Steering wheel sprite
local crashSprite = nil -- Crash sprite that appears when there is a collision

--Variables
local begin = 1 -- Flag for first start of game
local crash = 0 -- Flag for crash/collision
local crankReset = 0 -- Dummy variable to get around bug
local playerSpeed = 2 -- How fast the player sprite moves up/down when steered with the crank
local playerLocation = 120 -- Initial vertical location of the player sprite 
local car1Speed = 5 -- Initial speed of Car 1
local car2Speed = 10 -- Initial speed of Car 2
local stripeSpeed = 0 -- Initial speed of center stripe
local wheelRotate = 0 -- Default rotation of steering weheel
local playerAdjust = 0 -- Default vertical adjustment of player sprite
local stripeLocation = 238 -- Default vertical location of center strip
local car1Location = 125 -- Default horizontal location of Car 1 
local car2Location = 175 -- Default horizontal location of Car 2
local playTimer = nil -- Value of the timer
local playTime = 60 * 1000 -- Total time allowed (ms)
local lapCount = 0 -- Score for the game
local gearSet = 0 -- Initial gear setting 


local function resetTimer() 
--Resets game timer as well as resets score, gear, and object location
	playTimer=playdate.timer.new(playTime, playTime, 0, playdate.easingFunctions.linear)
	lapCount = 0
	gearSet = 0
	lapSpeed = 0
	playerLocation = 120
	playerAdjust = 0
	wheelRotate = 0
	car1Location = 125
	car2Location = 175
end

local function updateText() 
-- Updates score and timer values to the screen (also commented out debug elements)
	--gfx.drawText("Gear: " .. gearSet, 100, 80)
	gfx.drawText(math.ceil(lapCount/200), 45, 192)
	--gfx.drawText("C1: " .. car1Location, 100, 100)
	--gfx.drawText("Player: " .. playerLocation, 200, 100)
	--gfx.drawText("C2: " .. car2Location, 100, 125)
	--gfx.drawText("Stripe: " .. stripeSpeed, 100, 145)
	gfx.drawText(math.ceil(playTimer.value/1000), 37, 30)
end

local function movePlayer()
-- Function to move the player based on crank motion.  Keeps player within the guardrails.
	playerAdjust = playdate.getCrankTicks(36)
	playerLocation += playerAdjust*playerSpeed*-1
	playerSprite:moveTo(363, playerLocation)
	wheelRotate = wheelRotate + (10*playerAdjust)
	if playerLocation <= 87 then
		playerLocation = 87
		wheelRotate = 0
	elseif playerLocation >= 155 then
		playerLocation = 155
		wheelRotate = 0
	end
	wheelSprite:setRotation(wheelRotate)
	wheelSprite: update()
end

local function moveStripe()
-- Animates center stripe based on speed.  Resets position if animation takes stripe off screen.
	stripeLocation = stripeLocation + stripeSpeed
	stripeSprite:moveTo(stripeLocation, 120)
	if stripeLocation >= 248 then
		stripeLocation = 238
	end
end

local function moveCars()
-- Animates the other cars.  Resets position as they move off screen to create a notion of a loop.  Loops both ways.
	car1Location = car1Location + car1Speed
	car2Location = car2Location + car2Speed
	car1Sprite:moveTo(car1Location, 95)
	car2Sprite:moveTo(car2Location, 148)
	if car1Location >= 420 then
		car1Location = 51
	end
	if car1Location <= 50 then
		car1Location = 420
	end
	if car2Location >= 420 then
		car2Location = 51
	end
	if car2Location <= 50 then
		car2Location = 420
	end
end

local function setLap()
--Adds to the lapCount (score) as long as the game isn't in a crash state.
	if crash == 0 then
		lapCount += gearSet
	end
end 

local function setSpeed()
-- Reads the dpad and adjusts the gear lever position accordingly.  Speeds for objects are set based on gearSet value.
	if playdate.buttonJustPressed(playdate.kButtonUp) then
		gearSet += 1 
		if gearSet > 3 then gearSet = 3 end
	end
	if playdate.buttonJustPressed(playdate.kButtonDown) then
		gearSet -= 1
		if gearSet <0 then gearSet = 0 end
	end	
	if (gearSet == 0)
	then
		car1Speed = -1
		car2Speed = -2
		stripeSpeed = 0
		shifterSprite:moveTo(57,151)
	elseif (gearSet == 1)
	then
		car1Speed = 0
		car2Speed = -1
		stripeSpeed = 2
		shifterSprite:moveTo(57,131)
	elseif gearSet == 2
	then
		car1Speed = 1
		car2Speed = 1
		stripeSpeed = 3
		shifterSprite:moveTo(57,111)
	elseif gearSet == 3
	then
		car1Speed = 2
		car2Speed = 1
		stripeSpeed = 4
		shifterSprite:moveTo(57,91)
	end
end

local function initialize()
--initialize gamescreen.  Adds all sprites, backgrounds, to default locations	
	local stripeImage = gfx.image.new("images/line")
	stripeSprite = gfx.sprite.new(stripeImage)
	stripeSprite:moveTo(stripeLocation, 120)
	stripeSprite:add()

	local car1Image = gfx.image.new("images/car1")
	car1Sprite = gfx.sprite.new(car1Image)
	car1Sprite:moveTo(car1Location,95)
	car1Sprite:setCollideRect(0, 0, car1Sprite:getSize())
	car1Sprite:add()
	
	local car2Image = gfx.image.new("images/car1")
	car2Sprite = gfx.sprite.new(car2Image)
	car2Sprite:setCollideRect(0, 0, car2Sprite:getSize())
	car2Sprite:moveTo(car2Location,148)
	car2Sprite:add()

	local playerImage = gfx.image.new("images/player")
	playerSprite = gfx.sprite.new(playerImage)
	playerSprite:setCollideRect(8, 2, 44, 32)
	playerSprite:moveTo(363,playerLocation)
	playerSprite:add()

	local wheelImage = gfx.image.new("images/wheel")
	wheelSprite = gfx.sprite.new(wheelImage)
	wheelSprite:moveTo(200,225)
	wheelSprite:add()
	
	local crashImage = gfx.image.new("images/crash")
	crashSprite = gfx.sprite.new(crashImage)
	crashSprite:moveTo(357, 120)
	
	local shifterImage = gfx.image.new("images/shifter")
	shifterSprite = gfx.sprite.new(shifterImage)
	shifterSprite:moveTo(57,151)
	shifterSprite:add()

	local backgroundImage = gfx.image.new("images/background")
	gfx.sprite.setBackgroundDrawingCallback(
		function (x, y, width, height)
			gfx.setClipRect(x,y,width,height)
			backgroundImage:draw(0,0)
			gfx.clearClipRect()
		end
	)
	resetTimer()
end

initialize()

if begin == 1 then -- Trigger to have timer be already at 0 on game start.  Forcing user to press A (like they need to with reset) to first start the game
	playTimer.value = 0
	begin = 0
	gfx.sprite.update()
end

function playdate.update() -- Waits for user to press A before resetting/restarting the gam
	if playTimer.value == 0 then
		if playdate.buttonJustPressed(playdate.kButtonA) then
			resetTimer()
		end
	else
		
	setSpeed()
	
	local checkCrash = playerSprite:overlappingSprites()
		if #checkCrash >= 1 then
			crash = 1
			stripeSpeed = 0
			car1Speed = 0
			car2Speed = 0
			crashSprite:add()
		else
			crash = 0
			crashSprite:remove()
		end

	setLap()
	movePlayer()
	moveStripe()
	moveCars()
	gfx.sprite.update()
	updateText()
	playdate.timer.updateTimers()
	
	end
		
	crankReset = playdate.getCrankTicks(36)	-- workaround to have one more read of a crank not impact player position on restart
	
end


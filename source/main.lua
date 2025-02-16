import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/crank"

--Shortcuts
local gfx <const> = playdate.graphics
local snd = playdate.sound

--Sounds
local brah = snd.sampleplayer.new('sounds/brah') --Engine Noise Sample
local crashSound = snd.sampleplayer.new('sounds/crashSound') -- Crash Noise Sample
local shiftSound = snd.sampleplayer.new('sounds/shift') -- Shift lever sample
local skidSound = snd.sampleplayer.new('sounds/skid') -- skidding tires sample

--Sprites
local playerSprite = nil -- Player sprite (car) that is steerable
local car1Sprite = nil -- Car sprite in the right lane of the road
local car2Sprite = nil -- Car sprite in the left lane of the road
local stripeSprite = nil -- Center stripe sprite on the road
local shifterSprite = nil -- Gear shifter sprite
local shiftConsoleSprite = nil -- Console for the Gear Shift Sprite
local edgeSprite = nil -- Edge of the screen to hide the cars
local wheelSprite = nil -- Steering wheel sprite
local crashSprite = nil -- Crash sprite that appears when there is a collision
local abuttonSprite = nil -- Sprite to denote A button pressing
local startSprite = nil -- Start banner
local finishSprite = nil -- Finish banner

--Variables
local hasStarted = false -- Flag for first start of game
local crash = 0 -- Flag for crash/collision
local totalPlays = 0 -- Tracks the total plays historically -- reads from store
local highScore = 0 -- Variable to keep high score
local shouldSave = false -- Flag to not over-save
local playerSpeed = 2 -- How fast the player sprite moves up/down when steered with the crank
local playerLocation = 120 -- Initial vertical location of the player sprite
local car1Speed = 5 -- Initial speed of Car 1
local car2Speed = 10 -- Initial speed of Car 2
local stripeSpeed = 0 -- Initial speed of center stripe
local soundRate = 1 -- Initial rate of sound
local wheelRotate = 0 -- Default rotation of steering weheel
local playerAdjust = 0 -- Default vertical adjustment of player sprite
local stripeLocation = 238 -- Default vertical location of center strip
local car1Location = 125 -- Default horizontal location of Car 1
local car2Location = 175 -- Default horizontal location of Car 2
local playTimer = nil -- Value of the timer
local playTime = 60*1000 -- Total time allowed (ms)
local lapCount = 0 -- Score for the game
local gearSet = 0 -- Initial gear setting 
	
local function checkStart()
	-- adds the start screen if at the beginning (fresh launch) of the game
	if hasStarted == false then
		startSprite:add()
		-- hasStarted = true
	end
end

local function checkFinish()
	-- If the timer has run out -- stops all sounds, adds the finish image, and saves a new high score if higher than the previous
	if (playTimer.timeLeft == 0 and hasStarted == true) then 
		brah:stop()
		crashSound:stop()
		finishSprite:add()
	
		
		if lapCount > highScore then 
			highScore = lapCount 
		end
		
		if shouldSave == true then 
			shouldSave = false
			totalPlays += 1
			saveGameData()
		end
	end
end

function saveGameData()
	--saves number of plays and highscore to Playdate storage
	local gameData = {
		TOTAL_PLAYS = totalPlays;
		HIGH_SCORE = highScore
	}
	playdate.datastore.write(gameData)
end

function loadGameData()
	-- loads number of plays and highscore previously saved to Playdate storage (if it exists)
	local gameData = playdate.datastore.read()
	if gameData then
		highScore = gameData.HIGH_SCORE
		totalPlays = gameData.TOTAL_PLAYS
	end
end

function playdate.gameWillTerminate()
	-- saves game data if the game is force-closed by the user
	saveGameData()
end

function playdate.deviceWillSleep()
	-- saves game data if the game is closed by the device sleeping 
	saveGameData()
end

local function reset() 
--Resets game timer as well as resets score, gear, and object location
	playTimer=playdate.timer.new(playTime, playTime, 0, playdate.easingFunctions.linear)
	lapCount = 0
	gearSet = 0
	playerLocation = 120
	playerAdjust = 0
	wheelRotate = 0
	car1Location = 125
	car2Location = 175
	startSprite:remove()
	finishSprite:remove()
	abuttonSprite:remove()
	shouldSave = true
end

local function updateText() 
-- Updates score and timer values to the screen
	if hasStarted == true then
		gfx.drawText(math.ceil(lapCount/50), 44, 192)
		gfx.drawText(math.ceil(playTimer.timeLeft/1000), 35, 30)
	end

	if (playTimer.timeLeft == 0 and hasStarted == true) then 
		-- if the game is over (timer is 0 and begin isn't 0) then update text on the finish screen 
		gfx.drawTextAligned(math.ceil(lapCount/50), 250, 118, rightMargin)
		gfx.drawTextAligned(totalPlays, 250, 135, rightMargin)
		gfx.drawTextAligned(math.ceil(highScore/50), 250, 152, rightMargin)
	end
end

local function movePlayer()
-- Function to move the player based on crank motion.  Keeps player within the guard rails
	playerAdjust = playdate.getCrankTicks(36)
	playerLocation += playerAdjust*playerSpeed*-1
	playerSprite:moveTo(363, playerLocation)
	wheelRotate = wheelRotate + (10*playerAdjust)
	if playerLocation <= 87 then
		playerLocation = 87
		wheelRotate = 0
		skidSound:play()
	elseif playerLocation >= 155 then
		playerLocation = 155
		wheelRotate = 0
		skidSound:play()
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

local function playSound()
--plays engine sound with a rate adjustment based on playerspeed and a crash sound (if crashed)
	if not(brah:isPlaying()) then 
		brah:play(1,soundRate)
	end
	if (crash == 1 and not(crashSound:isPlaying())) then 
		crashSound:play()
	end
end

local function toggleAbutton()
	if playdate.buttonIsPressed(playdate.kButtonA) then
		abuttonSprite:add()
	else
		abuttonSprite:remove()
		
	end
end

local function checkCrash()
-- Checks to see if the cars have collided.  Adjusts speeds (stops the game) until crash clears
	local collidingCars = playerSprite:overlappingSprites()
	if #collidingCars >= 1 and not(playdate.buttonIsPressed(playdate.kButtonA)) then
		crash = 1
		stripeSpeed = 0
		car1Speed = 0
		car2Speed = 0
		crashSprite:add()
	else
		crash = 0
		crashSprite:remove()
	end
end

local function setLap()
--Adds to the lapCount (score) as long as the game isn't in a crash state.
	if crash == 0 and not(playdate.buttonIsPressed(playdate.kButtonA)) then
		lapCount += gearSet
	end
end

local function setSpeed()
-- Reads the dpad and adjusts the gear lever position accordingly.  Speeds for objects are set based on gearSet value.  Stops sound loop with each gear change to allow for a new sound to play that matches the new gear
	if playdate.buttonJustPressed(playdate.kButtonUp) then
		gearSet += 1
		brah:stop() 
		if gearSet > 3 then 
			gearSet = 3 
		else 
			shiftSound:play() 
		end
	end
	
	if playdate.buttonJustPressed(playdate.kButtonDown) then
		gearSet -= 1
		brah:stop()
		if gearSet < 0 then 
			gearSet = 0 
		else 
			shiftSound:play() 
		end
	end

	if (gearSet == 0)
	then
		car1Speed = -1
		car2Speed = -2
		stripeSpeed = 0
		soundRate = 1
		shifterSprite:moveTo(46,151)
	elseif (gearSet == 1)
	then
		car1Speed = 0
		car2Speed = -1
		stripeSpeed = 2
		soundRate = 1.2
		shifterSprite:moveTo(46,131)
	elseif gearSet == 2
	then
		car1Speed = 1
		car2Speed = 1
		stripeSpeed = 3
		soundRate = 1.4
		shifterSprite:moveTo(46,111)
	elseif gearSet == 3
	then
		car1Speed = 2.2
		car2Speed = 1
		stripeSpeed = 4
		soundRate = 1.6
		shifterSprite:moveTo(46,91)
	end
end

local function initialize()
--initialize gamescreen.  Adds all sprites, backgrounds, to default locations

	local startImage = gfx.image.new("images/startcard")
	startSprite = gfx.sprite.new(startImage)
	startSprite:moveTo(200, 120)		
	
	local finishImage = gfx.image.new("images/finish")
	finishSprite = gfx.sprite.new(finishImage)
	finishSprite:moveTo(200, 120)	

	local abuttonImage = gfx.image.new("images/abutton")
	abuttonSprite = gfx.sprite.new(abuttonImage)
	abuttonSprite:moveTo(300, 219)

	local stripeImage = gfx.image.new("images/line")
	stripeSprite = gfx.sprite.new(stripeImage)
	stripeSprite:moveTo(stripeLocation, 120)
	stripeSprite:add()

	local car1Image = gfx.image.new("images/car1")
	car1Sprite = gfx.sprite.new(car1Image)
	car1Sprite:moveTo(car1Location,95)
	car1Sprite:setCollideRect(3, 0, 35, 32)
	car1Sprite:add()

	local car2Image = gfx.image.new("images/car1")
	car2Sprite = gfx.sprite.new(car2Image)
	car2Sprite:setCollideRect(3, 0, 35, 32)
	car2Sprite:moveTo(car2Location,148)
	car2Sprite:add()

	local shiftConsoleImage = gfx.image.new("images/shiftconsole")
	shiftConsoleSprite = gfx.sprite.new(shiftConsoleImage)
	shiftConsoleSprite:moveTo(32, 121)
	shiftConsoleSprite:add()

	local edgeImage = gfx.image.new("images/edge")
	edgeSprite = gfx.sprite.new(edgeImage)
	edgeSprite:moveTo(398, 121)
	edgeSprite:add()

	local playerImage = gfx.image.new("images/player")
	playerSprite = gfx.sprite.new(playerImage)
	playerSprite:setCollideRect(13, 2, 33, 32)
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
	shifterSprite:moveTo(46,151)
	shifterSprite:add()

	local backgroundImage = gfx.image.new("images/background")
	gfx.sprite.setBackgroundDrawingCallback(
		function (x, y, width, height)
			gfx.setClipRect(x,y,width,height)
			backgroundImage:draw(0,0)
			gfx.clearClipRect()
		end
	)

	reset()
end

initialize()
loadGameData()

if hasStarted == false then
	playTimer.value = 0 
end

function playdate.update() -- Waits for user to press A before resetting/restarting the game

	if playTimer.value == 0 then
		-- two states are possible if the timer is 0.  You are at the start (new game launch) or you have finished a play session
		checkStart()
		checkFinish()
		if playdate.buttonJustPressed(playdate.kButtonA) then
			hasStarted = true
			reset()
		
		end
		gfx.sprite.update()
		if hasStarted == true then updateText() end
	else
	
		setSpeed()
		checkCrash()
		setLap()
		movePlayer()
		moveStripe()
		moveCars()
		playSound()
		toggleAbutton()
		gfx.sprite.update()
		updateText()
		playdate.timer.updateTimers()

	end

	local crankReset = playdate.getCrankTicks(36)	-- workaround to have one more read of a crank not impact player position on restart
	
end



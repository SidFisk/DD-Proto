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
local totalPlays = { 0, 0, 0, 0 } -- Per mode (indexed like modes) -- Tracks the total plays historically -- reads from store
local highScores = { 0, 0, 0, 0 } -- Best score for each mode (indexed like modes)
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
local backgroundImage = nil -- Road background for the round being played (Rogue modes use their own, see reset)
local gearSet = 0 -- Initial gear setting 
	
--Game Modes
local modes = {
	{ name = "CLASSIC", cardFile = "images/Mode_classic", desc = "Just like the original", finishFile = "images/finish_classic", speedMult = 1, scoreMult = 1, rogueMult = 0, crashEnds = false }, -- Main game
	{ name = "TURBO", cardFile = "images/Mode_turbo", desc = "Cars move faster and laps are doubled", finishFile = "images/finish_turbo", speedMult = 1.5, scoreMult = 2, rogueMult = 0, crashEnds = false }, -- Faster cars, double score, 
	{ name = "ROGUE", cardFile = "images/Mode_rogue", desc = "Classic with no second chances. One crash ends your run", finishFile = "images/finish_rogue", background = "images/background_rogue", speedMult = 1, scoreMult = 1, rogueMult = -1, crashEnds = true }, -- Classic speed and score, but a crash ends the round
	{ name = "ROGUE ENDLESS", cardFile = "images/Mode_rogue_endless", desc = "No clock. Race as long as you dare.", finishFile = "images/finish_rogue_endless", background = "images/background_rogue", speedMult = 1, rogueMult = -1, scoreMult = 1, crashEnds = true, endless = true }, -- Like Rogue, but no time limit: keeps going until you crash
}
local currentMode = 1 -- Index of the selected mode in modes
local crashEnded = false -- Flag set when a crash ends the round (Rogue)
local playedMode = 1 -- Mode of the round being played (or just finished), so changing the selector on the finish screen doesn't affect it

local function aButtonHeld()
	-- Holding A clears crashes and pauses scoring.  Disabled in modes where a crash ends the round (Rogue).
	return playdate.buttonIsPressed(playdate.kButtonA) and not modes[currentMode].crashEnds
end

local function checkStart()
	-- adds the start screen if at the beginning (fresh launch) of the game
	if hasStarted == false then
		startSprite:add()
		-- hasStarted = true
	end
end

local function checkFinish()
	-- If the timer has run out -- stops all sounds, adds the finish image, and saves a new high score if higher than the previous
	if ((playTimer.timeLeft == 0 or crashEnded) and hasStarted == true) then 
		brah:stop()
			-- A game-ending crash (Rogue) lets the crash sound play out underneath the finish card;
			-- reset() stops it when the next round starts.  Other endings (time up) still cut it off.
			if not crashEnded then
				crashSound:stop()
			end

		local finishImg = modes[playedMode].finishImg
			if finishImg and finishSprite:getImage() ~= finishImg then
				finishSprite:setImage(finishImg)
			end
			finishSprite:add()
			crashSprite:remove()
	
		
		if lapCount > highScores[playedMode] then 
			highScores[playedMode] = lapCount 
		end
		
		if shouldSave == true then 
			shouldSave = false
			totalPlays[playedMode] += 1
			saveGameData()
		end
	end
end

function saveGameData()
	--saves number of plays and highscore to Playdate storage
	local gameData = {
		TOTAL_PLAYS_BY_MODE = totalPlays;
		HIGH_SCORES = highScores
	}
	playdate.datastore.write(gameData)
end

function loadGameData()
	-- loads number of plays and highscore previously saved to Playdate storage (if it exists)
	local gameData = playdate.datastore.read()
	if gameData then
		if gameData.HIGH_SCORES then
				highScores = gameData.HIGH_SCORES
			elseif gameData.HIGH_SCORE then
				highScores[1] = gameData.HIGH_SCORE
			end
		if gameData.TOTAL_PLAYS_BY_MODE then
			totalPlays = gameData.TOTAL_PLAYS_BY_MODE
		elseif gameData.TOTAL_PLAYS then
			totalPlays[1] = gameData.TOTAL_PLAYS -- Old save: all earlier plays were Classic
		end
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
	-- Endless modes ignore the clock: use a timer so long (24 hours) that it never expires
		local duration = playTime
		if modes[currentMode].endless then duration = 24*60*60*1000 end
		playTimer=playdate.timer.new(duration, duration, 0, playdate.easingFunctions.linear)
	lapCount = 0
	gearSet = 0
	playerLocation = 120
	playerAdjust = 0
	wheelRotate = 0
	car1Location = 125
	car2Location = 175
	-- Move the sprites back to their start positions right away.  Otherwise checkCrash() runs on the
		-- first frame against the old positions from the end of the last round, still sees the collision
		-- that ended it, and (in Rogue) instantly ends the new round and counts it as a race.
		playerSprite:moveTo(363, playerLocation)
		car1Sprite:moveTo(car1Location, 95)
		car2Sprite:moveTo(car2Location, 148)
			crash = 0
			crashSound:stop() -- in case a game-ending crash sound is still finishing from the last round
			crashSprite:remove()
			startSprite:remove()
	finishSprite:remove()
	abuttonSprite:remove()
	shouldSave = true
		crashEnded = false
		playedMode = currentMode
			backgroundImage = modes[currentMode].bgImg
			gfx.sprite.addDirtyRect(0, 0, 400, 240) -- redraw the road with this mode's background
end

local function updateText() 
-- Updates score and timer values to the screen
	if hasStarted == true then
		gfx.drawText(math.ceil(lapCount/50), 44, 192)
		if modes[playedMode].endless then
				-- Endless mode: draw an infinity symbol instead of the timer
				gfx.setLineWidth(2)
				gfx.setColor(0)
				gfx.drawEllipseInRect(33, 35, 11, 8)
				gfx.drawEllipseInRect(43, 35, 11, 8)
				gfx.setLineWidth(1)
			else
				gfx.drawText(crashEnded and 0 or math.ceil(playTimer.timeLeft/1000), 35, 30)
			end
	end

	if ((playTimer.timeLeft == 0 or crashEnded) and hasStarted == true) then 
		-- if the game is over (timer is 0 and begin isn't 0) then update text on the finish screen 
		gfx.drawTextAligned(math.ceil(lapCount/50), 250, 118, rightMargin)
		gfx.drawTextAligned(totalPlays[playedMode], 250, 135, rightMargin)
		gfx.drawTextAligned(math.ceil(highScores[playedMode]/50), 250, 152, rightMargin)
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
	stripeLocation = stripeLocation + stripeSpeed * modes[currentMode].speedMult
	stripeSprite:moveTo(stripeLocation, 120)
	if stripeLocation >= 248 then
		stripeLocation = 238
	end
end

local function moveCars()
-- Animates the other cars.  Resets position as they move off screen to create a notion of a loop.  Loops both ways.
	car1Location = car1Location + car1Speed * modes[currentMode].speedMult
	car2Location = car2Location + car2Speed * modes[currentMode].speedMult 
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
if aButtonHeld() then
			abuttonSprite:add()
	else
		abuttonSprite:remove()
		
	end
end

local function checkCrash()
-- Checks to see if the cars have collided.  Adjusts speeds (stops the game) until crash clears
	local collidingCars = playerSprite:overlappingSprites()
	if #collidingCars >= 1 and not(aButtonHeld()) then
		crash = 1
		stripeSpeed = 0
		car1Speed = 0
		car2Speed = 0
		crashSprite:add()
			if modes[currentMode].crashEnds then
				-- Rogue: a crash ends the round.
				-- Remove the timer first so updateTimers() can't overwrite the values below
				playTimer:remove()
				playTimer.value = 0
				-- (timeLeft is read-only, so the crashEnded flag below tells the finish logic the round is over)
					crashEnded = true
			end
	else
		crash = 0
		crashSprite:remove()
	end
end

local function setLap()
--Adds to the lapCount (score) as long as the game isn't in a crash state.
	if crash == 0 and not(aButtonHeld()) then
		lapCount += gearSet * modes[currentMode].scoreMult
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
		car1Speed = 1 * modes[currentMode].rogueMult
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
		for _, mode in ipairs(modes) do
			mode.finishImg = gfx.image.new(mode.finishFile) -- Per-mode finish card
				mode.bgImg = gfx.image.new(mode.background or "images/background") -- Per-mode road background
		end
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

-- Fill in any modes missing from older saves (e.g. modes added later)
for i = 1, #modes do
	highScores[i] = highScores[i] or 0
	totalPlays[i] = totalPlays[i] or 0
end

-- System menu: manually clear all high scores and race counts (two-step to avoid accidents)
local clearScoresItem
clearScoresItem = playdate.getSystemMenu():addOptionsMenuItem("Clr Scores", { "No", "Yes" }, "No", function(value)
	if value == "Yes" then
		-- Wipe scores and race counts for every mode, then save
		for i = 1, #modes do
			highScores[i] = 0
			totalPlays[i] = 0
		end
		saveGameData()
		clearScoresItem:setValue("No") -- Reset so it can't be triggered again by accident
	end
end)

local inModeSelect = false -- True while the mode select screen is showing

-- Mode select screen art and layout (tweak these numbers to nudge things around)
local modeSelectImage = gfx.image.new("images/mode_select") -- Full screen background
local modeShifterImage = gfx.image.new("images/shifter") -- Same shifter knob used in the race
for _, mode in ipairs(modes) do
	mode.cardImg = gfx.image.new(mode.cardFile) -- Per-mode card (nil until the PNG exists)
end
local MODE_SHIFTER_X = 74 -- Horizontal centre of the shifter slot in mode_select.png
local MODE_SHIFTER_Y = { 147, 127, 107, 87 } -- Shifter height for modes 1-4 (N, 1, 2, 3 on the gate)
local CARD_CX = 246 -- Horizontal centre of the card
local STATS_CX = 250 -- Horizontal centre of the stats text under the card
local CARD_TOP = 66 -- Top edge of the card, just under the title bar
local CARD_CLIP_X = 100 -- Cards slide only inside the white panel, so they never cross the shifter
local CARD_CLIP_Y = 60
local CARD_TRAVEL = 320 -- How far (px) a card flies when leaving or entering
local CARD_ANIM_FRAMES = 9 -- Length of the fly in/out animation
local STATS_Y = 197 -- Top of the stats text, below the card
local STATS_SPACING = 70 -- Each stat is centred this many px left/right of STATS_CX
local cardAnimFrame = CARD_ANIM_FRAMES -- Animation progress; equal to CARD_ANIM_FRAMES when idle
local cardOutMode = nil -- Mode whose card is flying out
local cardDir = 1 -- +1: shifted up (old card exits right, new enters from left), -1: the reverse

local function shiftMode(delta)
	-- Moves the selector like setSpeed() moves gears: clamps at the ends, and only plays the shift sound if it moved
	local newMode = currentMode + delta
	print("shiftMode: current=" .. currentMode .. " delta=" .. delta .. " new=" .. newMode .. " count=" .. #modes) -- DEBUG: remove once the freeze is found
	if newMode < 1 or newMode > #modes then
		print("shiftMode: at the end, ignoring") -- DEBUG
		return
	end
	cardOutMode = currentMode
	cardDir = delta
	currentMode = newMode
	cardAnimFrame = 0
	shiftSound:play()
end

local function drawModeCard(modeIndex, offsetX)
	-- Draws a mode's card centred at CARD_CX (plus an offset); falls back to text if the PNG is missing
	local mode = modes[modeIndex]
	if mode.cardImg then
		local w = mode.cardImg:getSize()
		mode.cardImg:draw(math.floor(CARD_CX - w/2 + offsetX), CARD_TOP)
	else
		gfx.drawTextAligned(mode.name, math.floor(CARD_CX + offsetX), CARD_TOP + 20, kTextAlignment.center)
		gfx.drawTextInRect(mode.desc, math.floor(CARD_CX - 120 + offsetX), CARD_TOP + 44, 240, 60, nil, nil, kTextAlignment.center)
	end
end

local function updateModeSelect()
	-- Mode select screen: D-pad up/down chooses a mode, A starts a round in that mode
	if playdate.buttonJustPressed(playdate.kButtonUp) then
		shiftMode(1) -- up = next mode, like shifting up a gear
	elseif playdate.buttonJustPressed(playdate.kButtonDown) then
		shiftMode(-1)
	end

	if playdate.buttonJustPressed(playdate.kButtonA) then
		inModeSelect = false
		hasStarted = true
		reset()
		gfx.sprite.addDirtyRect(0, 0, 400, 240) -- redraw the whole game screen
		return
	end

		-- Advance the card fly in/out animation (ease-out)
		if cardAnimFrame < CARD_ANIM_FRAMES then cardAnimFrame += 1 end
		local t = cardAnimFrame / CARD_ANIM_FRAMES
		local ease = 1 - (1 - t) ^ 3

		gfx.clear()
		modeSelectImage:draw(0, 0) -- Background (title, shifter gate, button hints are all part of the art)
		modeShifterImage:drawAnchored(MODE_SHIFTER_X, MODE_SHIFTER_Y[currentMode], 0.5, 0.5)

		-- Card(s), clipped to the white panel
		gfx.setClipRect(CARD_CLIP_X, CARD_CLIP_Y, 400 - CARD_CLIP_X, 240 - CARD_CLIP_Y)
		if cardAnimFrame < CARD_ANIM_FRAMES and cardOutMode then
			drawModeCard(cardOutMode, cardDir * CARD_TRAVEL * ease) -- old card flies out
			drawModeCard(currentMode, -cardDir * CARD_TRAVEL * (1 - ease)) -- new card flies in
		else
			drawModeCard(currentMode, 0)
		end
		gfx.clearClipRect()

		-- Stats for the selected mode, below the card
				gfx.drawTextAligned("RACES: " .. totalPlays[currentMode], STATS_CX - STATS_SPACING, STATS_Y, kTextAlignment.center)
				gfx.drawTextAligned("BEST: " .. math.ceil(highScores[currentMode]/50), STATS_CX + STATS_SPACING, STATS_Y, kTextAlignment.center)
end

function playdate.update() -- Waits for user to press A before resetting/restarting the game

	if inModeSelect then
		updateModeSelect()
	elseif playTimer.value == 0 then
		-- two states are possible if the timer is 0.  You are at the start (new game launch) or you have finished a play session
		checkStart()
		checkFinish()
		if playdate.buttonJustPressed(playdate.kButtonA) then
			inModeSelect = true -- A on the start or finish screen opens the mode select screen
				cardAnimFrame = CARD_ANIM_FRAMES -- no card animation on arrival
		end
		gfx.sprite.update()
		if hasStarted == true then updateText() end
			
-- (mode selection now happens on its own screen, see updateModeSelect)
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



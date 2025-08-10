-- main.lua (com sprites reduzidos e sons)

local screenWidth, screenHeight = 800, 600

local scale = 0.40 -- escala para reduzir os sprites para 50%

-- Dimensões originais dos sprites
local PLAYER_W, PLAYER_H = 112, 75
local ENEMY_WS = { 97, 97, 103 }
local ENEMY_H = 84
local BULLET_W, BULLET_H = 13, 37
local POWERUP_W, POWERUP_H = 19, 30

local gameState = "start"

local player = {
    x = (screenWidth / 2) - (PLAYER_W * scale) / 2,
    y = screenHeight - (PLAYER_H * scale) - 40,
    width = PLAYER_W * scale,
    height = PLAYER_H * scale,
    speed = 300,
    bullets = {},
    lives = 3,
    canShoot = true,
    shootCooldown = 0.3,
    shootTimer = 0,
    shootType = "single",
}

local enemies = {}
local enemyRows = 4
local enemyCols = 8
local enemyWidthMax = math.max(unpack(ENEMY_WS))
local enemyHeight = ENEMY_H
local enemySpeed = 100
local enemyDirection = 1
local enemyDrop = 10
local enemyShootInterval = 3
local enemyShootTimer = 0

local enemyBullets = {}

local powerUps = {}
local maxPowerUpsPerPhase = 4
local powerUpTimer = 0
local powerUpSpawnInterval = 20
local powerUpsDropped = 0

local explosions = {}

local score = 0

local sprites = {}
local sounds = {}

local function loadIfExists(path)
    if love.filesystem.getInfo(path) then
        return love.graphics.newImage(path)
    end
    return nil
end

function love.load()
    love.window.setMode(screenWidth, screenHeight)
    love.window.setTitle("Space Invaders Retro")
    love.graphics.setDefaultFilter("nearest", "nearest")

    -- carregar imagens
    sprites.player = love.graphics.newImage("sprites/player.png")
    sprites.enemies = {
        love.graphics.newImage("sprites/enemy1.png"),
        love.graphics.newImage("sprites/enemy2.png"),
        love.graphics.newImage("sprites/enemy3.png"),
    }
    sprites.bullet = love.graphics.newImage("sprites/player_bullet.png")
    sprites.enemy_bullet = love.graphics.newImage("sprites/enemy_bullet.png")
    sprites.powerups = {
        rapid = loadIfExists("sprites/powerup_rapid.png"),
        double = loadIfExists("sprites/powerup_double.png"),
        spread = loadIfExists("sprites/powerup_spread.png"),
        life = loadIfExists("sprites/powerup_life.png"),
        speed = loadIfExists("sprites/powerup_speed.png"),
    }
    sprites.background = loadIfExists("sprites/background.png")
    sprites.explosion = loadIfExists("sprites/explosion.png")

    -- carregar sons
    sounds.shoot = love.audio.newSource("sounds/shoot.wav", "static")
    --sounds.background = love.audio.newSource("sounds/background.wav", "static")
    sounds.explosion = love.audio.newSource("sounds/esplosion.wav", "static")

    --sounds.background:setLooping(true)
    --sounds.background:play()

    createEnemies()
end

function createEnemies()
    enemies = {}
    powerUps = {}
    powerUpsDropped = 0
    powerUpTimer = powerUpSpawnInterval

    local spacingX = 20
    local spacingY = 20
    local scaledEnemyWidthMax = enemyWidthMax * scale
    local scaledEnemyHeight = enemyHeight * scale
    local totalW = enemyCols * scaledEnemyWidthMax + (enemyCols - 1) * spacingX
    local startX = math.max(40, (screenWidth - totalW) / 2)

    for row = 1, enemyRows do
        for col = 1, enemyCols do
            local etype = ((row - 1) % 3) + 1
            local w = ENEMY_WS[etype] * scale
            local h = ENEMY_H * scale

            local colX = startX + (col - 1) * (scaledEnemyWidthMax + spacingX)
            local x = colX + (scaledEnemyWidthMax - w) / 2
            local y = 50 + (row - 1) * (h + spacingY)

            table.insert(enemies, {
                x = x,
                y = y,
                width = w,
                height = h,
                alive = true,
                type = etype,
                moveType = (row % 3) + 1,
                isShooting = false,
                shootFlashTimer = 0,
            })
        end
    end

    enemySpeed = 40
    enemyDirection = 1
    enemyShootTimer = enemyShootInterval
end

function love.update(dt)
    if gameState == "playing" then
        updatePlayer(dt)
        updateBullets(dt)
        updateEnemies(dt)
        updateEnemyBullets(dt)
        updatePowerUps(dt)

        enemyShootTimer = enemyShootTimer - dt
        powerUpTimer = powerUpTimer - dt

        if enemyShootTimer <= 0 then
            enemyShoot()
            enemyShootTimer = enemyShootInterval
        end

        if powerUpTimer <= 0 and powerUpsDropped < maxPowerUpsPerPhase then
            spawnPowerUp()
            powerUpTimer = powerUpSpawnInterval
        end

        if player.lives <= 0 then
            gameState = "gameover"
        end

        local allDead = true
        for _, e in ipairs(enemies) do
            if e.alive then
                allDead = false; break
            end
        end
        if allDead then gameState = "victory" end
    end
end

function updatePlayer(dt)
    if love.keyboard.isDown("left") then
        player.x = player.x - player.speed * dt
    elseif love.keyboard.isDown("right") then
        player.x = player.x + player.speed * dt
    end

    if player.x < 0 then player.x = 0 end
    if player.x > screenWidth - player.width then player.x = screenWidth - player.width end

    player.shootTimer = player.shootTimer - dt
    if player.shootTimer < 0 then player.canShoot = true end
end

function updateBullets(dt)
    for i = #player.bullets, 1, -1 do
        local b = player.bullets[i]
        b.y = b.y - b.speed * dt
        if b.dx then b.x = b.x + b.dx * dt end

        if b.y + BULLET_H * scale < 0 or b.x + BULLET_W * scale < 0 or b.x > screenWidth then
            table.remove(player.bullets, i)
        else
            for _, enemy in ipairs(enemies) do
                if enemy.alive and
                    b.x + BULLET_W * scale > enemy.x and b.x < enemy.x + enemy.width and
                    b.y + BULLET_H * scale > enemy.y and b.y < enemy.y + enemy.height then
                    enemy.alive = false
                    table.remove(player.bullets, i)
                    score = score + 10
                    increaseEnemySpeed()
                    sounds.explosion:play()
                    -- drop power up chance
                    if powerUpsDropped < maxPowerUpsPerPhase and love.math.random() < 0.20 then
                        powerUpsDropped = powerUpsDropped + 1
                        spawnPowerUpAt(enemy.x + enemy.width / 2 - POWERUP_W * scale / 2, enemy.y)
                    end
                    break
                end
            end
        end
    end
end

function increaseEnemySpeed()
    enemySpeed = enemySpeed + 3
end

function updateEnemies(dt)
    local moveDown = false
    for _, enemy in ipairs(enemies) do
        if enemy.alive then
            if enemy.moveType == 1 then
                enemy.x = enemy.x + enemyDirection * enemySpeed * dt
            elseif enemy.moveType == 2 then
                enemy.x = enemy.x + enemyDirection * enemySpeed * dt
                enemy.y = enemy.y + math.sin(love.timer.getTime() * 1.5 + enemy.x * 0.01) * 6 * dt
            elseif enemy.moveType == 3 then
                enemy.x = enemy.x + enemyDirection * (enemySpeed + 30) * dt
            end

            if enemy.x + enemy.width > screenWidth or enemy.x < 0 then
                moveDown = true
            end

            if enemy.isShooting then
                enemy.shootFlashTimer = enemy.shootFlashTimer - dt
                if enemy.shootFlashTimer <= 0 then enemy.isShooting = false end
            end
        end
    end

    if moveDown then
        enemyDirection = -enemyDirection
        for _, enemy in ipairs(enemies) do
            enemy.y = enemy.y + enemyDrop
            if enemy.y + enemy.height > player.y then gameState = "gameover" end
        end
    end
end

function enemyShoot()
    local alive = {}
    for _, e in ipairs(enemies) do if e.alive then table.insert(alive, e) end end
    if #alive == 0 then return end

    local shooter = alive[love.math.random(#alive)]
    shooter.isShooting = true
    shooter.shootFlashTimer = 0.5

    table.insert(enemyBullets, {
        x = shooter.x + shooter.width / 2 - (BULLET_W * scale) / 2,
        y = shooter.y + shooter.height,
        speed = 250,
    })
end

function updateEnemyBullets(dt)
    for i = #enemyBullets, 1, -1 do
        local b = enemyBullets[i]
        b.y = b.y + b.speed * dt

        if b.y > screenHeight then
            table.remove(enemyBullets, i)
        else
            if b.x + BULLET_W * scale > player.x and b.x < player.x + player.width and
                b.y + BULLET_H * scale > player.y and b.y < player.y + player.height then
                table.remove(enemyBullets, i)
                player.lives = player.lives - 1
                sounds.explosion:play()
            end
        end
    end
end

function updatePowerUps(dt)
    for i = #powerUps, 1, -1 do
        local p = powerUps[i]
        p.y = p.y + p.speed * dt
        if p.y > screenHeight then
            table.remove(powerUps, i)
        else
            if p.x + POWERUP_W * scale > player.x and p.x < player.x + player.width and
                p.y + POWERUP_H * scale > player.y and p.y < player.y + player.height then
                applyPowerUp(p.type)
                table.remove(powerUps, i)
            end
        end
    end
end

function applyPowerUp(type)
    if type == "life" then
        player.lives = math.min(player.lives + 1, 5)
    elseif type == "speed" then
        player.speed = player.speed + 50
    elseif type == "rapid" then
        player.shootCooldown = 0.15
    elseif type == "double" then
        player.shootType = "double"
    elseif type == "spread" then
        player.shootType = "spread"
    end
end

function spawnPowerUp()
    if powerUpsDropped >= maxPowerUpsPerPhase then return end
    powerUpsDropped = powerUpsDropped + 1
    local types = { "life", "speed", "rapid", "double", "spread" }
    local ptype = types[love.math.random(#types)]
    table.insert(powerUps, {
        x = love.math.random(40, screenWidth - 40 - POWERUP_W * scale),
        y = -POWERUP_H * scale,
        speed = 100,
        type = ptype,
    })
end

function spawnPowerUpAt(x, y)
    if powerUpsDropped >= maxPowerUpsPerPhase then return end
    local types = { "life", "speed", "rapid", "double", "spread" }
    local ptype = types[love.math.random(#types)]
    table.insert(powerUps, {
        x = x - (POWERUP_W * scale) / 2,
        y = y,
        speed = 100,
        type = ptype
    })
end

function love.draw()
    if sprites.background then
        love.graphics.draw(sprites.background, 0, 0, 0, scale, scale)
    else
        love.graphics.clear(0, 0, 0)
    end

    if gameState == "start" then
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Pressione Espaço para começar", 0, screenHeight / 2 - 20, screenWidth, "center")
        love.graphics.printf("Use as setas para mover, espaço para atirar", 0, screenHeight / 2 + 20, screenWidth,
            "center")
    elseif gameState == "playing" then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(sprites.player, player.x, player.y, 0, scale, scale)

        for _, b in ipairs(player.bullets) do
            love.graphics.draw(sprites.bullet, b.x, b.y, 0, scale, scale)
        end

        for _, e in ipairs(enemies) do
            if e.alive then
                if e.isShooting and e.shootFlashTimer > 0 then
                    if math.floor(e.shootFlashTimer * 10) % 2 == 0 then
                        love.graphics.setColor(1, 1, 1)
                    else
                        love.graphics.setColor(1, 0, 0)
                    end
                else
                    love.graphics.setColor(1, 1, 1)
                end
                love.graphics.draw(sprites.enemies[e.type], e.x, e.y, 0, scale, scale)
                love.graphics.setColor(1, 1, 1)
            end
        end

        for _, b in ipairs(enemyBullets) do
            love.graphics.draw(sprites.enemy_bullet, b.x, b.y, 0, scale, scale)
        end

        for _, p in ipairs(powerUps) do
            local img = sprites.powerups[p.type]
            if img then
                love.graphics.draw(img, p.x, p.y, 0, scale, scale)
            else
                love.graphics.setColor(1, 1, 0)
                love.graphics.rectangle("fill", p.x, p.y, POWERUP_W * scale, POWERUP_H * scale)
                love.graphics.setColor(1, 1, 1)
            end
        end

        if sprites.explosion then
            for _, ex in ipairs(explosions) do
                love.graphics.draw(sprites.explosion, ex.x, ex.y, 0, scale, scale)
            end
        end

        love.graphics.setColor(1, 1, 0)
        love.graphics.print("Pontuação: " .. score, 10, 10)
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("Vidas: " .. player.lives, 10, 40)
        love.graphics.setColor(1, 1, 1)
    elseif gameState == "gameover" then
        love.graphics.setColor(1, 0, 0)
        love.graphics.printf("GAME OVER", 0, screenHeight / 2 - 40, screenWidth, "center")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Sua pontuação: " .. score, 0, screenHeight / 2, screenWidth, "center")
        love.graphics.printf("Pressione Espaço para reiniciar", 0, screenHeight / 2 + 40, screenWidth, "center")
    elseif gameState == "victory" then
        love.graphics.setColor(0, 1, 0)
        love.graphics.printf("VOCÊ VENCEU!", 0, screenHeight / 2 - 40, screenWidth, "center")
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Pontuação final: " .. score, 0, screenHeight / 2, screenWidth, "center")
        love.graphics.printf("Pressione Espaço para reiniciar", 0, screenHeight / 2 + 40, screenWidth, "center")
    end
end

function love.keypressed(key)
    if gameState == "start" and key == "space" then
        gameState = "playing"
        player.lives = 3
        player.bullets = {}
        enemyBullets = {}
        powerUps = {}
        explosions = {}
        score = 0
        player.speed = 300
        player.shootType = "single"
        player.shootCooldown = 0.3
        createEnemies()
    elseif gameState == "playing" and key == "space" then
        if player.canShoot then
            if player.shootType == "single" then
                table.insert(player.bullets, {
                    x = player.x + player.width / 2 - (BULLET_W * scale) / 2,
                    y = player.y,
                    speed = 600,
                })
            elseif player.shootType == "double" then
                table.insert(player.bullets, {
                    x = player.x + player.width / 4 - (BULLET_W * scale) / 2,
                    y = player.y,
                    speed = 600,
                })
                table.insert(player.bullets, {
                    x = player.x + player.width * 3 / 4 - (BULLET_W * scale) / 2,
                    y = player.y,
                    speed = 600,
                })
            elseif player.shootType == "spread" then
                table.insert(player.bullets,
                    { x = player.x + player.width / 2 - (BULLET_W * scale) / 2, y = player.y, speed = 600, dx = 0 })
                table.insert(player.bullets,
                    { x = player.x + player.width / 2 - (BULLET_W * scale) / 2, y = player.y, speed = 600, dx = -180 })
                table.insert(player.bullets,
                    { x = player.x + player.width / 2 - (BULLET_W * scale) / 2, y = player.y, speed = 600, dx = 180 })
            end

            player.canShoot = false
            player.shootTimer = player.shootCooldown

            sounds.shoot:play()
        end
    elseif (gameState == "gameover" or gameState == "victory") and key == "space" then
        gameState = "start"
    elseif key == "escape" then
        love.event.quit()
    end
end

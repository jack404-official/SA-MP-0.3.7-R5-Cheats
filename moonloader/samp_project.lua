local imgui = require('imgui')
local vkeys = require('vkeys')
local ffi = require('ffi')
local memory = require('memory')
local inicfg = require('inicfg')
local events = require('samp.events')
local GetBonePosition = ffi.cast("int (__thiscall*)(void*, float*, int, bool)", 6177408)

function GetBodyPartCoordinates(boneId, ped)
    if not doesCharExist(ped) then return 0, 0, 0 end
    local pedPointer = getCharPointer(ped)
    local coords = ffi.new("float[3]")
    GetBonePosition(ffi.cast("void*", pedPointer), coords, boneId, true)
    return coords[0], coords[1], coords[2]
end

local whNameTag = false
local whExitStatus = false
local whDistance = imgui.ImFloat(400.0)
local whVisibilityWall = imgui.ImBool(false)
local whVisibilityTag = imgui.ImBool(true)

function whNameTagON()
    if not isSampAvailable() then return end
    local ok, ptr = pcall(sampGetServerSettingsPtr)
    if ok and ptr and ptr ~= 0 then
        memory.setfloat(ptr + 39, whDistance.v)
        memory.setint8(ptr + 47, whVisibilityWall.v and 0 or 1)
        memory.setint8(ptr + 56, whVisibilityTag.v and 1 or 0)
    end
    whNameTag = true
end

function whNameTagOFF()
    if not isSampAvailable() then return end
    local ok, ptr = pcall(sampGetServerSettingsPtr)
    if ok and ptr and ptr ~= 0 then
        memory.setfloat(ptr + 39, 40)
        memory.setint8(ptr + 47, 1)
        memory.setint8(ptr + 56, 1)
    end
    whNameTag = false
end

function whApplySettings()
    if whNameTag then
        whNameTagON()
    else
        whNameTagOFF()
    end
end

function whHandleRespawn()
    if whExitStatus then
        whNameTagON()
        whExitStatus = false
    end
end

function ColorToARGB(col, alpha)
    alpha = alpha or 255
    local r = math.floor((col.v[1] or 1) * 255)
    local g = math.floor((col.v[2] or 1) * 255)
    local b = math.floor((col.v[3] or 1) * 255)
    return bit.bor(bit.lshift(alpha, 24), bit.lshift(r, 16), bit.lshift(g, 8), b)
end

function getKeyName(key)
    local names = {
        [1] = "LMB", [2] = "RMB", [4] = "MMB",
        [8] = "Backspace", [9] = "Tab", [13] = "Enter",
        [16] = "Shift", [17] = "Ctrl", [18] = "Alt",
        [20] = "Caps", [27] = "Escape", [32] = "Space",
        [45] = "Insert", [46] = "Delete",
        [65] = "A", [66] = "B", [67] = "C", [68] = "D", [69] = "E",
        [70] = "F", [71] = "G", [72] = "H", [73] = "I", [74] = "J",
        [75] = "K", [76] = "L", [77] = "M", [78] = "N", [79] = "O",
        [80] = "P", [81] = "Q", [82] = "R", [83] = "S", [84] = "T",
        [85] = "U", [86] = "V", [87] = "W", [88] = "X", [89] = "Y", [90] = "Z"
    }
    if key >= 48 and key <= 57 then return tostring(key - 48) end
    return names[key] or ("Key " .. tostring(key))
end
local fontProggy, fontBold, fontSmall, espFont = nil, nil, nil, nil
local fontsLoaded = false

function GetFontPath()
    local dir = thisScript().path:match("(.+)\\[^\\]+$") or ""
    return dir .. "\\resource\\fonts\\ProggyClean.ttf"
end

function LoadSelectedFonts(force)
    if not force and fontsLoaded and fontProggy ~= nil then
        return
    end
    local io = imgui.GetIO()
    local fontPath = GetFontPath()
    io.Fonts:Clear()
    fontProggy = io.Fonts:AddFontFromFileTTF(fontPath, 13.0)
    fontBold   = io.Fonts:AddFontFromFileTTF(fontPath, 16.0)
    fontSmall  = io.Fonts:AddFontFromFileTTF(fontPath, 11.0)
    imgui.RebuildFonts()
    fontsLoaded = true
end

function imgui.BeforeDrawFrame()
    LoadSelectedFonts(false)
end

local finderQuery = imgui.ImBuffer("", 64)
local spawnGunQuery = imgui.ImBuffer("", 64)
local spawnGunAmmo = imgui.ImInt(500)
local spawnGunHealth = imgui.ImInt(100)
local spawnGunArmor = imgui.ImInt(100)
local spawnGunSelected = -1
local skinChangerSearch = imgui.ImBuffer("", 64)
local skinChangerSelected = 0
local skinChangerRestoreId = nil
local skinChangerLockEnabled = false
local skinChangerLockedModel = nil
local skinChangerOriginalModel = nil
local skinTextures = {}
local skinChangerLoaded = false
local asState = nil
pcall(function()
    asState = require('moonloader').audiostream_state
end)
local musicList = {}
local musicIndex = 0
local musicStream = nil
local musicPlaying = false
local musicPaused = false
local musicVolume = imgui.ImFloat(0.70)
local musicLoop = imgui.ImBool(false)
local musicStatus = "Idle"
local musicCurrentName = "No track selected"

function GetMusicDir()
    local dir = thisScript().path:match("(.+)\\[^\\]+$") or getWorkingDirectory() or ""
    return dir .. "\\resource\\music"
end

function EnsureMusicDir()
    local path = GetMusicDir()
    if not doesDirectoryExist(path) then
        pcall(createDirectory, path)
        local parent = path:match("(.+)\\[^\\]+$")
        if parent and not doesDirectoryExist(parent) then
            pcall(createDirectory, parent)
            pcall(createDirectory, path)
        end
    end
    return path
end

function ScanMusicFiles()
    musicList = {}
    local path = EnsureMusicDir()
    local exts = { "mp3", "wav", "ogg", "m4a" }
    local seen = {}
    local function addFile(name)
        if type(name) ~= "string" then return end
        if name == "." or name == ".." then return end
        local lower = name:lower()
        for _, ext in ipairs(exts) do
            if lower:sub(-(#ext + 1)) == "." .. ext then
                if not seen[lower] then
                    seen[lower] = true
                    musicList[#musicList + 1] = name
                end
                return
            end
        end
    end
    for _, ext in ipairs(exts) do
        local pattern = path .. "\\*." .. ext
        local ok, handle, file = pcall(function()
            return findFirstFile(pattern)
        end)
        if ok and handle ~= nil then
            while type(file) == "string" do
                addFile(file)
                local okNext, nextFile = pcall(findNextFile, handle)
                if not okNext or type(nextFile) ~= "string" then
                    break
                end
                file = nextFile
            end
            pcall(findClose, handle)
        end
    end
    table.sort(musicList, function(a, b)
        return tostring(a):lower() < tostring(b):lower()
    end)
    if musicIndex > #musicList then
        musicIndex = #musicList
    end
    return #musicList
end

function MusicStop(release)
    if musicStream then
        pcall(function()
            if asState then
                setAudioStreamState(musicStream, asState.STOP or 0)
            else
                setAudioStreamState(musicStream, 0)
            end
        end)
        if release then
            pcall(releaseAudioStream, musicStream)
            musicStream = nil
        end
    end
    musicPlaying = false
    musicPaused = false
    musicStatus = "Stopped"
end

function MusicApplyVolume()
    if musicStream then
        pcall(setAudioStreamVolume, musicStream, math.max(0, math.min(1, musicVolume.v)))
    end
end

function MusicPlayIndex(idx)
    if idx < 1 or idx > #musicList then
        musicStatus = "No track"
        return false
    end
    MusicStop(true)
    musicIndex = idx
    local path = GetMusicDir() .. "\\" .. musicList[idx]
    musicCurrentName = musicList[idx]

    local okLoad, a, b = pcall(function()
        return loadAudioStream(path)
    end)
    if okLoad then
        if type(a) == "number" or type(a) == "userdata" then
            musicStream = a
        elseif a == true and b ~= nil then
            musicStream = b
        elseif a ~= nil and a ~= false then
            musicStream = a
        end
    end
    if not musicStream then
        musicStatus = "Failed to load"
        musicCurrentName = musicList[idx]
        return false
    end
    pcall(function()
        if asState and asState.PLAY then
            setAudioStreamState(musicStream, asState.PLAY)
        else
            setAudioStreamState(musicStream, 1)
        end
    end)
    MusicApplyVolume()
    if musicLoop.v then
        pcall(setAudioStreamLooped, musicStream, true)
    else
        pcall(setAudioStreamLooped, musicStream, false)
    end
    musicPlaying = true
    musicPaused = false
    musicStatus = "Playing"
    return true
end

function MusicTogglePause()
    if not musicStream then return end
    if musicPlaying and not musicPaused then
        pcall(function()
            if asState and asState.PAUSE then
                setAudioStreamState(musicStream, asState.PAUSE)
            else
                setAudioStreamState(musicStream, 2)
            end
        end)
        musicPaused = true
        musicPlaying = false
        musicStatus = "Paused"
    else
        pcall(function()
            if asState and asState.RESUME then
                setAudioStreamState(musicStream, asState.RESUME)
            elseif asState and asState.PLAY then
                setAudioStreamState(musicStream, asState.PLAY)
            else
                setAudioStreamState(musicStream, 1)
            end
        end)
        musicPaused = false
        musicPlaying = true
        musicStatus = "Playing"
    end
end

function MusicNext()
    if #musicList == 0 then return end
    local nextIdx = musicIndex + 1
    if nextIdx > #musicList then nextIdx = 1 end
    MusicPlayIndex(nextIdx)
end

function MusicPrev()
    if #musicList == 0 then return end
    local prevIdx = musicIndex - 1
    if prevIdx < 1 then prevIdx = #musicList end
    MusicPlayIndex(prevIdx)
end

function MusicUpdateState()
    if not musicStream then return end
    local ok, st = pcall(getAudioStreamState, musicStream)
    if not ok or st == nil then return end
    if st == 1 or (asState and st == asState.PLAY) then
        musicPlaying = true
        musicPaused = false
        musicStatus = "Playing"
    elseif st == 2 or (asState and st == asState.PAUSE) then
        musicPlaying = false
        musicPaused = true
        musicStatus = "Paused"
    elseif st == 0 or st == -1 or (asState and st == asState.STOP) then
        if musicPlaying and not musicPaused then
            if musicLoop.v then
                MusicPlayIndex(musicIndex)
            else
                if musicIndex < #musicList then
                    MusicPlayIndex(musicIndex + 1)
                else
                    musicPlaying = false
                    musicStatus = "Finished"
                end
            end
        end
    end
end

function FormatMoney(amount)
    amount = tonumber(amount) or 0
    local neg = amount < 0
    amount = math.abs(math.floor(amount))
    local s = tostring(amount)
    local result = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    if neg then result = "-" .. result end
    return "$" .. result
end

function SearchPlayers(query)
    local results = {}
    if not isSampAvailable then return results end
    query = tostring(query or ""):match("^%s*(.-)%s*$") or ""
    local q = query:lower()
    local filter = (q ~= "")
    local maxPlayerId = 0
    pcall(function()
        local a = sampGetMaxPlayerId(false)
        if type(a) == "number" then maxPlayerId = math.max(maxPlayerId, a) end
    end)
    pcall(function()
        local b = sampGetMaxPlayerId(true)
        if type(b) == "number" then maxPlayerId = math.max(maxPlayerId, b) end
    end)
    if maxPlayerId < 1 then
        maxPlayerId = 999
    else
        maxPlayerId = math.max(maxPlayerId, 0)
    end
    local myX, myY, myZ = 0, 0, 0
    pcall(function()
        myX, myY, myZ = getCharCoordinates(PLAYER_PED)
    end)
    local myId = -1
    pcall(function()
        local okId, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
        if okId then myId = id end
    end)
    for i = 0, maxPlayerId do
        local okConn, connected = pcall(sampIsPlayerConnected, i)
        if okConn and connected then
            local okNick, nick = pcall(sampGetPlayerNickname, i)
            nick = (okNick and nick) and tostring(nick) or ""
            if nick == "" then nick = ("Player_%d"):format(i) end
            if (not filter) or nick:lower():find(q, 1, true) then
                local streamed = false
                local dist = -1
                local hp, armor = -1, -1
                local px, py, pz = nil, nil, nil
                local score = 0
                local money = nil
                local isLocal = (i == myId)
                local ping = -1
                local okPed, ok, ped = pcall(sampGetCharHandleBySampPlayerId, i)
                if okPed and ok and ped and doesCharExist(ped) then
                    streamed = true
                    pcall(function()
                        px, py, pz = getCharCoordinates(ped)
                        dist = getDistanceBetweenCoords3d(myX, myY, myZ, px, py, pz)
                        hp = getCharHealth(ped)
                        armor = getCharArmour(ped)
                    end)
                end
                pcall(function()
                    score = sampGetPlayerScore(i) or 0
                end)
                pcall(function()
                    ping = sampGetPlayerPing(i) or -1
                end)
                if isLocal then
                    pcall(function()
                        money = getPlayerMoney()
                    end)
                end
                results[#results + 1] = {
                    id = i,
                    name = nick,
                    streamed = streamed,
                    dist = dist,
                    hp = hp,
                    armor = armor,
                    score = score,
                    money = money,
                    ping = ping,
                    isLocal = isLocal,
                    x = px, y = py, z = pz
                }
            end
        end
    end
    if filter then
        table.sort(results, function(a, b)
            if a.streamed ~= b.streamed then return a.streamed end
            if a.dist >= 0 and b.dist >= 0 and a.dist ~= b.dist then
                return a.dist < b.dist
            end
            return a.name:lower() < b.name:lower()
        end)
    else
        table.sort(results, function(a, b)
            return a.id < b.id
        end)
    end
    return results
end

local aimbot = require("samp_project_module")
local ab = aimbot.ab
local cbugEnabled = imgui.ImBool(false)
SP_cbugEnabled = cbugEnabled
local cbugShowCrosshair = imgui.ImBool(false)
local cbugNoCamRestore = imgui.ImBool(false)
local cbugNoRecoil = imgui.ImBool(false)
local cbugSecondaryKey = 82
local cbugSecondaryKeyName = getKeyName(cbugSecondaryKey)
local waitingCbugKey = false
local noRecoilEnabled = imgui.ImBool(false)
local clickWarpEnabled = imgui.ImBool(false)
local maxDamageEnabled = imgui.ImBool(false)
local rapidFireEnabled = imgui.ImBool(false)
local rapidFireSpeed = imgui.ImFloat(1.2)
local spawnGunBypassEnabled = imgui.ImBool(false)
local autoRPCount = 5
local autoRPCommands, autoRPKeys, autoRPKeyNames, waitingAutoRPKey = {}, {}, {}, {}
for i = 1, autoRPCount do
    autoRPCommands[i] = imgui.ImBuffer("", 128)
    autoRPKeys[i] = 0
    autoRPKeyNames[i] = "Not Set"
    waitingAutoRPKey[i] = false
end
local espEnabled = imgui.ImBool(false)
local espBox     = imgui.ImBool(false)
local espLine    = imgui.ImBool(false)
local espBone    = imgui.ImBool(false)
local espName    = imgui.ImBool(false)
local colEspBox  = imgui.ImFloat3(1.0, 1.0, 1.0)
local colEspLine = imgui.ImFloat3(1.0, 1.0, 1.0)
local colBone    = imgui.ImFloat3(1.0, 1.0, 1.0)
local colFov     = imgui.ImFloat3(0.9804, 0.2588, 0.2588)
local posList    = {'Top', 'Center', 'Bottom'}
local linePos    = imgui.ImInt(2)
local dotPos     = imgui.ImInt(0)
local lineThick  = 1.20
local boxThick   = 1.20
local boneThick  = 1.20
local cornerFrac = 0.22
local dotRadius  = 2.5
local menuUseKeybind = imgui.ImBool(true)
local menuKey = 45
local menuModKey = 0
local menuKeyName = getKeyName(45)
local menuModKeyName = "None"
local waitingMenuKey = false
local waitingMenuModKey = false
local menuUseCommand = imgui.ImBool(true)
local menuCommand = imgui.ImBuffer("saproject", 64)
local registeredMenuCommand = nil
local menuOpen

function EnsureMenuOpenMethodAvailable()
    if not menuUseKeybind.v and not menuUseCommand.v then
        menuUseKeybind.v = true
    end
end

function UpdateMenuCommandRegistration()
    if registeredMenuCommand and sampUnregisterChatCommand then
        pcall(sampUnregisterChatCommand, registeredMenuCommand)
        registeredMenuCommand = nil
    end
    if menuUseCommand.v and isSampAvailable then
        local cmd = tostring(menuCommand.v or ""):gsub("^/+", ""):match("^%s*(.-)%s*$")
        if cmd and cmd ~= "" then
            local ok = pcall(sampRegisterChatCommand, cmd, function()
                menuOpen.v = not menuOpen.v
            end)
            if ok then
                registeredMenuCommand = cmd
            end
        end
    end
end

local AUTO_CONFIG_PATH = "samp_project_config.ini"
local autoConfigLoaded = false
local lastAutoConfigSnapshot = nil

function AutoConfigBool(value)
    return value and "1" or "0"
end

function AutoConfigColor(value)
    return string.format("%.4f,%.4f,%.4f", value.v[1], value.v[2], value.v[3])
end

function AutoConfigSnapshot()
    local values = {
        AutoConfigBool(ab.enable.v), AutoConfigBool(ab.showFov.v), AutoConfigBool(ab.vis.v), tostring(ab.partSel.v),
        tostring(ab.smooth.v), tostring(ab.radius.v), tostring(ab.dist.v),
        tostring(ab.rifleSmooth.v), tostring(ab.rifleRadius.v), tostring(ab.rifleDist.v),
        tostring(ab.countrySmooth.v), tostring(ab.countryRadius.v), tostring(ab.countryDist.v),
        tostring(ab.sniperSmooth.v), tostring(ab.sniperRadius.v), tostring(ab.sniperDist.v),
        tostring(ab.toggleKey),
        AutoConfigBool(cbugEnabled.v), AutoConfigBool(cbugShowCrosshair.v),
        AutoConfigBool(cbugNoCamRestore.v), AutoConfigBool(cbugNoRecoil.v), tostring(cbugSecondaryKey),
        AutoConfigBool(noRecoilEnabled.v), AutoConfigBool(clickWarpEnabled.v),
        AutoConfigBool(maxDamageEnabled.v), AutoConfigBool(rapidFireEnabled.v), tostring(rapidFireSpeed.v),
        AutoConfigBool(spawnGunBypassEnabled.v), AutoConfigBool(espEnabled.v), AutoConfigBool(espBox.v),
        AutoConfigBool(espLine.v), AutoConfigBool(espBone.v), AutoConfigBool(espName.v),
        tostring(linePos.v), tostring(dotPos.v),
        AutoConfigBool(menuUseKeybind.v), tostring(menuKey), tostring(menuModKey),
        AutoConfigBool(menuUseCommand.v), tostring(menuCommand.v),
        tostring(musicVolume.v),
        tostring(musicLoop.v), tostring(spawnGunAmmo.v), tostring(spawnGunHealth.v),
        tostring(spawnGunArmor.v), tostring(finderQuery.v), tostring(spawnGunQuery.v),
        AutoConfigColor(colEspBox), AutoConfigColor(colEspLine), AutoConfigColor(colBone),
        AutoConfigColor(colFov),
        tostring(skinChangerOriginalModel or 0),
        tostring(skinChangerRestoreId or 0)
    }
    for i = 1, #autoRPCommands do
        values[#values + 1] = tostring(autoRPCommands[i].v or "")
        values[#values + 1] = tostring(autoRPKeys[i] or 0)
    end
    return table.concat(values, "|")
end

function AutoConfigNumber(section, key, fallback)
    return tonumber(section and section[key]) or fallback
end

function AutoConfigBoolValue(section, key, fallback)
    local value = section and section[key]
    if value == true or value == "true" or value == "1" or value == 1 then
        return true
    end
    if value == false or value == "false" or value == "0" or value == 0 then
        return false
    end
    return fallback
end

function AutoConfigColorValue(value, fallback)
    local a, b, c = tostring(value or ""):match("^%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*$")
    if a and b and c then
        return tonumber(a) or fallback[1], tonumber(b) or fallback[2], tonumber(c) or fallback[3]
    end
    return fallback[1], fallback[2], fallback[3]
end

function LoadAutoConfig()
    if autoConfigLoaded then
        return
    end

    local config = inicfg.load(nil, AUTO_CONFIG_PATH)
    if not config then
        autoConfigLoaded = true
        lastAutoConfigSnapshot = AutoConfigSnapshot()
        return
    end

    local aimbotConfig = config.aimbot or {}
    ab.enable.v = AutoConfigBoolValue(aimbotConfig, "localEnabled", ab.enable.v)
    ab.showFov.v = AutoConfigBoolValue(aimbotConfig, "showFov", ab.showFov.v)
    ab.vis.v = AutoConfigBoolValue(aimbotConfig, "localVisible", ab.vis.v)
    ab.partSel.v = AutoConfigNumber(aimbotConfig, "localBone", ab.partSel.v)
    ab.smooth.v = AutoConfigNumber(aimbotConfig, "localSmooth", ab.smooth.v)
    ab.radius.v = AutoConfigNumber(aimbotConfig, "localRadius", ab.radius.v)
    ab.dist.v = AutoConfigNumber(aimbotConfig, "localDistance", ab.dist.v)
    ab.rifleSmooth.v = AutoConfigNumber(aimbotConfig, "rifleSmooth", ab.rifleSmooth.v)
    ab.rifleRadius.v = AutoConfigNumber(aimbotConfig, "rifleRadius", ab.rifleRadius.v)
    ab.rifleDist.v = AutoConfigNumber(aimbotConfig, "rifleDistance", ab.rifleDist.v)
    ab.countrySmooth.v = AutoConfigNumber(aimbotConfig, "countrySmooth", ab.countrySmooth.v)
    ab.countryRadius.v = AutoConfigNumber(aimbotConfig, "countryRadius", ab.countryRadius.v)
    ab.countryDist.v = AutoConfigNumber(aimbotConfig, "countryDistance", ab.countryDist.v)
    ab.sniperSmooth.v = AutoConfigNumber(aimbotConfig, "sniperSmooth", ab.sniperSmooth.v)
    ab.sniperRadius.v = AutoConfigNumber(aimbotConfig, "sniperRadius", ab.sniperRadius.v)
    ab.sniperDist.v = AutoConfigNumber(aimbotConfig, "sniperDistance", ab.sniperDist.v)
    ab.toggleKey = AutoConfigNumber(aimbotConfig, "toggleKey", ab.toggleKey)
    local cbugConfig = config.cbug or {}
    cbugEnabled.v = AutoConfigBoolValue(cbugConfig, "enabled", cbugEnabled.v)
    cbugShowCrosshair.v = AutoConfigBoolValue(cbugConfig, "showCrosshair", cbugShowCrosshair.v)
    cbugNoCamRestore.v = AutoConfigBoolValue(cbugConfig, "noCamRestore", cbugNoCamRestore.v)
    cbugNoRecoil.v = AutoConfigBoolValue(cbugConfig, "noRecoil", cbugNoRecoil.v)
    cbugSecondaryKey = AutoConfigNumber(cbugConfig, "secondaryKey", cbugSecondaryKey)
    cbugSecondaryKeyName = getKeyName(cbugSecondaryKey)
    local generalConfig = config.cheatGeneral or {}
    noRecoilEnabled.v = AutoConfigBoolValue(generalConfig, "noRecoil", noRecoilEnabled.v)
    clickWarpEnabled.v = AutoConfigBoolValue(generalConfig, "clickWarp", clickWarpEnabled.v)
    maxDamageEnabled.v = AutoConfigBoolValue(generalConfig, "maxDamage", maxDamageEnabled.v)
    rapidFireEnabled.v = AutoConfigBoolValue(generalConfig, "rapidFire", rapidFireEnabled.v)
    rapidFireSpeed.v = math.min(1.2, math.max(0.1, AutoConfigNumber(generalConfig, "rapidFireSpeed", rapidFireSpeed.v)))
    spawnGunBypassEnabled.v = AutoConfigBoolValue(generalConfig, "spawnGunBypass", spawnGunBypassEnabled.v)
    local espConfig = config.esp or {}
    espEnabled.v = AutoConfigBoolValue(espConfig, "enabled", espEnabled.v)
    espBox.v = AutoConfigBoolValue(espConfig, "box", espBox.v)
    espLine.v = AutoConfigBoolValue(espConfig, "line", espLine.v)
    espBone.v = AutoConfigBoolValue(espConfig, "bone", espBone.v)
    espName.v = AutoConfigBoolValue(espConfig, "name", espName.v)
    linePos.v = AutoConfigNumber(espConfig, "linePos", linePos.v)
    dotPos.v = AutoConfigNumber(espConfig, "dotPos", dotPos.v)
    local settingsConfig = config.settings or {}
    menuUseKeybind.v = AutoConfigBoolValue(settingsConfig, "menuUseKeybind", menuUseKeybind.v)
    menuKey = AutoConfigNumber(settingsConfig, "menuKey", menuKey)
    menuModKey = AutoConfigNumber(settingsConfig, "menuModKey", menuModKey)
    menuKeyName = getKeyName(menuKey)
    menuModKeyName = menuModKey > 0 and getKeyName(menuModKey) or "None"
    menuUseCommand.v = AutoConfigBoolValue(settingsConfig, "menuUseCommand", menuUseCommand.v)
    menuCommand.v = tostring(settingsConfig.menuCommand or menuCommand.v)
    EnsureMenuOpenMethodAvailable()
    UpdateMenuCommandRegistration()
    musicVolume.v = math.min(1, math.max(0, AutoConfigNumber(settingsConfig, "musicVolume", musicVolume.v)))
    musicLoop.v = AutoConfigBoolValue(settingsConfig, "musicLoop", musicLoop.v)
    spawnGunAmmo.v = AutoConfigNumber(settingsConfig, "spawnGunAmmo", spawnGunAmmo.v)
    spawnGunHealth.v = AutoConfigNumber(settingsConfig, "spawnGunHealth", spawnGunHealth.v)
    spawnGunArmor.v = AutoConfigNumber(settingsConfig, "spawnGunArmor", spawnGunArmor.v)
    finderQuery.v = tostring(settingsConfig.finderQuery or finderQuery.v)
    spawnGunQuery.v = tostring(settingsConfig.spawnGunQuery or spawnGunQuery.v)
    local r, g, b = AutoConfigColorValue(espConfig.boxColor, {1, 1, 1})
    colEspBox.v[1], colEspBox.v[2], colEspBox.v[3] = r, g, b
    r, g, b = AutoConfigColorValue(espConfig.lineColor, {1, 1, 1})
    colEspLine.v[1], colEspLine.v[2], colEspLine.v[3] = r, g, b
    r, g, b = AutoConfigColorValue(espConfig.boneColor, {1, 1, 1})
    colBone.v[1], colBone.v[2], colBone.v[3] = r, g, b
    r, g, b = AutoConfigColorValue(aimbotConfig.fovColor, {0.9804, 0.2588, 0.2588})
    colFov.v[1], colFov.v[2], colFov.v[3] = r, g, b
    local rpConfig = config.autoRP or {}
    local slotCount = math.max(5, math.min(20, AutoConfigNumber(rpConfig, "slotCount", #autoRPCommands)))
    while #autoRPCommands < slotCount do
        local index = #autoRPCommands + 1
        autoRPCommands[index] = imgui.ImBuffer("", 128)
        autoRPKeys[index] = 0
        autoRPKeyNames[index] = "Not Set"
        waitingAutoRPKey[index] = false
    end
    for i = 1, #autoRPCommands do
        autoRPCommands[i].v = tostring(rpConfig["command" .. i] or "")
        autoRPKeys[i] = AutoConfigNumber(rpConfig, "key" .. i, 0)
        autoRPKeyNames[i] = autoRPKeys[i] > 0 and getKeyName(autoRPKeys[i]) or "Not Set"
    end
    local skinConfig = config.skinChanger or {}
    skinChangerOriginalModel = AutoConfigNumber(skinConfig, "originalModel", 0)
    skinChangerRestoreId = AutoConfigNumber(skinConfig, "restoreId", 0)
    
    autoConfigLoaded = true
    lastAutoConfigSnapshot = AutoConfigSnapshot()
end

function SaveAutoConfig()
    local config = {
        aimbot = {
            localEnabled = ab.enable.v, showFov = ab.showFov.v, localVisible = ab.vis.v, localBone = ab.partSel.v,
            localSmooth = ab.smooth.v, localRadius = ab.radius.v, localDistance = ab.dist.v,
            rifleSmooth = ab.rifleSmooth.v, rifleRadius = ab.rifleRadius.v, rifleDistance = ab.rifleDist.v,
            countrySmooth = ab.countrySmooth.v, countryRadius = ab.countryRadius.v, countryDistance = ab.countryDist.v,
            sniperSmooth = ab.sniperSmooth.v, sniperRadius = ab.sniperRadius.v, sniperDistance = ab.sniperDist.v,
            fovColor = AutoConfigColor(colFov),
            toggleKey = ab.toggleKey
        },
        cbug = {
            enabled = cbugEnabled.v, showCrosshair = cbugShowCrosshair.v,
            noCamRestore = cbugNoCamRestore.v, noRecoil = cbugNoRecoil.v, secondaryKey = cbugSecondaryKey
        },
        cheatGeneral = {
            noRecoil = noRecoilEnabled.v, clickWarp = clickWarpEnabled.v,
            maxDamage = maxDamageEnabled.v, rapidFire = rapidFireEnabled.v,
            rapidFireSpeed = rapidFireSpeed.v, spawnGunBypass = spawnGunBypassEnabled.v
        },
        esp = {
            enabled = espEnabled.v, box = espBox.v, line = espLine.v, bone = espBone.v,
            name = espName.v, linePos = linePos.v, dotPos = dotPos.v,
            boxColor = AutoConfigColor(colEspBox), lineColor = AutoConfigColor(colEspLine),
            boneColor = AutoConfigColor(colBone)
        },
        autoRP = { slotCount = #autoRPCommands },
        settings = {
            menuUseKeybind = menuUseKeybind.v, menuKey = menuKey, menuModKey = menuModKey,
            menuUseCommand = menuUseCommand.v, menuCommand = menuCommand.v,
            musicVolume = musicVolume.v, musicLoop = musicLoop.v,
            spawnGunAmmo = spawnGunAmmo.v, spawnGunHealth = spawnGunHealth.v,
            spawnGunArmor = spawnGunArmor.v, finderQuery = finderQuery.v, spawnGunQuery = spawnGunQuery.v
        },
        skinChanger = {
            originalModel = skinChangerOriginalModel,
            restoreId = skinChangerRestoreId
        }
    }
    for i = 1, #autoRPCommands do
        config.autoRP["command" .. i] = tostring(autoRPCommands[i].v or "")
        config.autoRP["key" .. i] = tonumber(autoRPKeys[i]) or 0
    end
    inicfg.save(config, AUTO_CONFIG_PATH)
    lastAutoConfigSnapshot = AutoConfigSnapshot()
end

function AutoSaveConfigIfChanged()
    if not autoConfigLoaded then
        return
    end
    local snapshot = AutoConfigSnapshot()
    if snapshot ~= lastAutoConfigSnapshot then
        SaveAutoConfig()
    end
end

local WIN_W, WIN_H, SIDE_W, PAD = 660, 420, 178, 8
local INNER_H = WIN_H - 28 - PAD
local INNER_W = WIN_W - (PAD * 2)
local PR, PG, PB = 0.9804, 0.2588, 0.2588
local DEFAULT_RED_THEME = {
    accent        = {0.9804, 0.2588, 0.2588},
    windowBg      = {0.0588, 0.0588, 0.0706},
    childBg       = {0.0902, 0.0902, 0.1098},
    popupBg       = {0.0706, 0.0706, 0.0902},
    text          = {1.0000, 1.0000, 1.0000},
    textDisabled  = {0.4706, 0.5216, 0.5804},
    border        = {0.2000, 0.2196, 0.2706},
    frameBg       = {0.1216, 0.1294, 0.1686},
    frameHovered  = {0.2902, 0.1686, 0.1686},
    frameActive   = {0.4000, 0.2000, 0.2000},
    button        = {0.1804, 0.2000, 0.2510},
    buttonHovered = {0.8000, 0.2588, 0.2588},
    buttonActive  = {0.9804, 0.2588, 0.2588},
    header        = {0.1216, 0.1294, 0.1686},
    headerHovered = {0.6510, 0.2392, 0.2392},
    headerActive  = {0.9804, 0.2588, 0.2588},
    checkMark     = {0.9804, 0.2588, 0.2588},
    sliderGrab    = {0.9804, 0.2588, 0.2588},
    sliderActive  = {1.0000, 0.3216, 0.3216},
    separator     = {0.2392, 0.2784, 0.3608}
}

function ApplyTheme(id)
    local theme = DEFAULT_RED_THEME
    local s = imgui.GetStyle()
    local c = s.Colors
    local C = imgui.Col
    local V4 = imgui.ImVec4
    PR, PG, PB = theme.accent[1], theme.accent[2], theme.accent[3]
    c[C.Text]           = V4(theme.text[1], theme.text[2], theme.text[3], 1.0)
    c[C.TextDisabled]   = V4(theme.textDisabled[1], theme.textDisabled[2], theme.textDisabled[3], 1.0)
    c[C.WindowBg]       = V4(theme.windowBg[1], theme.windowBg[2], theme.windowBg[3], 0.96)
    c[C.ChildWindowBg]  = V4(theme.childBg[1], theme.childBg[2], theme.childBg[3], 1.0)
    c[C.PopupBg]        = V4(theme.popupBg[1], theme.popupBg[2], theme.popupBg[3], 1.0)
    c[C.Border]         = V4(theme.border[1], theme.border[2], theme.border[3], 1.0)
    c[C.FrameBg]        = V4(theme.frameBg[1], theme.frameBg[2], theme.frameBg[3], 1.0)
    c[C.FrameBgHovered] = V4(theme.frameHovered[1], theme.frameHovered[2], theme.frameHovered[3], 1.0)
    c[C.FrameBgActive]  = V4(theme.frameActive[1], theme.frameActive[2], theme.frameActive[3], 1.0)
    c[C.Button]         = V4(theme.button[1], theme.button[2], theme.button[3], 1.0)
    c[C.ButtonHovered]  = V4(theme.buttonHovered[1], theme.buttonHovered[2], theme.buttonHovered[3], 0.90)
    c[C.ButtonActive]   = V4(theme.buttonActive[1], theme.buttonActive[2], theme.buttonActive[3], 1.0)
    c[C.Header]         = V4(theme.header[1], theme.header[2], theme.header[3], 1.0)
    c[C.HeaderHovered]  = V4(theme.headerHovered[1], theme.headerHovered[2], theme.headerHovered[3], 1.0)
    c[C.HeaderActive]   = V4(theme.headerActive[1], theme.headerActive[2], theme.headerActive[3], 1.0)
    c[C.CheckMark]      = V4(theme.checkMark[1], theme.checkMark[2], theme.checkMark[3], 1.0)
    c[C.SliderGrab]     = V4(theme.sliderGrab[1], theme.sliderGrab[2], theme.sliderGrab[3], 0.90)
    c[C.SliderGrabActive] = V4(theme.sliderActive[1], theme.sliderActive[2], theme.sliderActive[3], 1.0)
    c[C.Separator]      = V4(theme.separator[1], theme.separator[2], theme.separator[3], 1.0)
    c[C.TitleBg]        = V4(theme.childBg[1], theme.childBg[2], theme.childBg[3], 1.0)
    c[C.TitleBgActive]  = V4(theme.header[1], theme.header[2], theme.header[3], 1.0)
    c[C.TitleBgCollapsed] = V4(theme.windowBg[1], theme.windowBg[2], theme.windowBg[3], 1.0)
    c[C.ScrollbarBg]    = V4(theme.windowBg[1], theme.windowBg[2], theme.windowBg[3], 1.0)
    c[C.ScrollbarGrab]  = V4(theme.button[1], theme.button[2], theme.button[3], 1.0)
    c[C.ScrollbarGrabHovered] = V4(theme.buttonHovered[1], theme.buttonHovered[2], theme.buttonHovered[3], 1.0)
    c[C.ScrollbarGrabActive] = V4(theme.buttonActive[1], theme.buttonActive[2], theme.buttonActive[3], 1.0)
    s.WindowRounding = 6
    if s.ChildWindowRounding ~= nil then s.ChildWindowRounding = 4 end
    s.FrameRounding = 4
    if s.GrabRounding ~= nil then s.GrabRounding = 3 end
    s.WindowTitleAlign = imgui.ImVec2(0.0, 0.5)
end
imgui.SwitchContext()
ApplyTheme(0)
imgui.SwitchContext()
ApplyTheme(0)
function PF(f) if f then imgui.PushFont(f) end end
function XF(f) if f then imgui.PopFont() end end

function SectionLabel(txt)
    PF(fontBold)
    imgui.TextColored(imgui.ImVec4(PR, PG, PB, 1), txt)
    XF(fontBold)
    imgui.Separator()
    imgui.Spacing()
end

function SmallNote(txt)
    PF(fontSmall)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), txt)
    XF(fontSmall)
end

function ShowHelpMarker(text)
    imgui.TextDisabled("(?)")
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(imgui.GetFontSize() * 35)
        imgui.TextUnformatted(text)
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
    end
end

local cameraRestorePatch
local showCrosshairInstantlyPatch
local noRecoilDynamicCrosshair

function DrawLoginTab()

end

function FormatAccountCountdown(seconds)

    return ""
end

function DrawAccount()

end

function DrawAimbot()
    PF(fontProggy)
    imgui.Spacing()
    SectionLabel("AIMBOT MENU")
    imgui.Spacing()
    if imgui.Button(ab.waitingKey and "[ Press any key... ]" or ("[ Toggle ON/OFF: " .. getKeyName(ab.toggleKey) .. " ]"), imgui.ImVec2(-1, 26)) then
        ab.waitingKey = true
    end
    imgui.Spacing()
    imgui.Checkbox("Enable Aimbot##local", ab.enable)
    imgui.SameLine()
    imgui.Checkbox("Show FOV##local", ab.showFov)
    imgui.SameLine()
    imgui.Checkbox("Visible Check##local", ab.vis)
    imgui.Spacing()
    imgui.PushItemWidth(220)
    imgui.Combo("Aimbot Part##local", ab.partSel, ab.partList, #ab.partList)
    imgui.PopItemWidth()
    imgui.Spacing()
    imgui.ColorEdit3("FOV Color##local", colFov)
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    SectionLabel("AIMBOT SETTINGS - (PISTOL, SMG, SHOTGUN)")
    imgui.PushItemWidth(220)
    imgui.SliderInt("Smooth Aim##local", ab.smooth, 1, 5)
    imgui.SliderInt("FOV Radius##local", ab.radius, 1, 8)
    imgui.SliderInt("Distance Aim##local", ab.dist, 1, 35)
    imgui.PopItemWidth()
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    SectionLabel("AIMBOT SETTINGS - (AK47, M4)")
    imgui.PushItemWidth(220)
    imgui.SliderInt("Smooth Aim##rifle", ab.rifleSmooth, 1, 5)
    imgui.SliderInt("FOV Radius##rifle", ab.rifleRadius, 1, 8)
    imgui.SliderInt("Distance Aim##rifle", ab.rifleDist, 1, 120)
    imgui.PopItemWidth()
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    SectionLabel("AIMBOT SETTINGS - (COUNTRY RIFLE)")
    imgui.PushItemWidth(220)
    imgui.SliderInt("Smooth Aim##country", ab.countrySmooth, 1, 5)
    imgui.SliderInt("FOV Radius##country", ab.countryRadius, 1, 8)
    imgui.SliderInt("Distance Aim##country", ab.countryDist, 1, 120)
    imgui.PopItemWidth()
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    SectionLabel("AIMBOT SETTINGS - (SNIPER RIFLE)")
    imgui.PushItemWidth(220)
    imgui.SliderInt("Smooth Aim##sniper", ab.sniperSmooth, 1, 5)
    imgui.SliderInt("FOV Radius##sniper", ab.sniperRadius, 1, 8)
    imgui.SliderInt("Distance Aim##sniper", ab.sniperDist, 1, 3000)
    imgui.PopItemWidth()
    imgui.Spacing()
    XF(fontProggy)
end

function DrawCbug()
    PF(fontProggy)
    imgui.Spacing()
    SectionLabel("C-BUG MENU")
    local weaponReady = false
    pcall(function()
        weaponReady = getCurrentCharWeapon(PLAYER_PED) == 24
    end)
    if imgui.Checkbox("Enable C-Bug", cbugEnabled) then
        if not cbugEnabled.v then
            cameraRestorePatch(false)
            noRecoilDynamicCrosshair(false)
        end
    end
    if imgui.Checkbox("Show Crosshair", cbugShowCrosshair) then
        if cbugShowCrosshair.v then
            showCrosshairInstantlyPatch(true)
        else
            showCrosshairInstantlyPatch(false)
        end
    end
    if imgui.Checkbox("No Camera Restore", cbugNoCamRestore) then
        if not cbugNoCamRestore.v then
            cameraRestorePatch(false)
        end
    end
    if imgui.Checkbox("No Recoil C-Bug", cbugNoRecoil) then
        if not cbugNoRecoil.v then
            noRecoilDynamicCrosshair(false)
        end
    end
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    SectionLabel("TOGGLE CBUG")
    imgui.Text("Toggle Key:")
    imgui.SameLine()
    imgui.TextColored(imgui.ImVec4(PR, PG, PB, 1), cbugSecondaryKeyName)
    if imgui.Button(waitingCbugKey and "Press any key..." or "Change Key", imgui.ImVec2(170, 28)) then
        waitingCbugKey = true
    end
        SmallNote("Toggle default cbug: ALT")
        SmallNote("Recommend toggle cbug use: ALT / R")
    XF(fontProggy)
end

function DrawEsp()
    PF(fontProggy)
    imgui.Spacing()
    SectionLabel("ESP MENU")
    if imgui.Checkbox("Enable Esp", espEnabled) then
        SaveAutoConfig()
        if not espEnabled.v and espName.v then
            espName.v = false
            whNameTagOFF()
            SaveAutoConfig()
        end
    end
    if imgui.Checkbox("Esp Box", espBox) then SaveAutoConfig() end
    if imgui.Checkbox("Esp Line", espLine) then SaveAutoConfig() end
    if imgui.Checkbox("Esp Bone", espBone) then SaveAutoConfig() end
    if imgui.Checkbox("ESP Nametag", espName) then
        if not espEnabled.v then
            espName.v = false
        else
            if espName.v then
                whDistance.v = 1000.0
                whVisibilityWall.v = true
                whVisibilityTag.v = true
                whNameTagON()
            else
                whNameTagOFF()
            end
            SaveAutoConfig()
        end
    end
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    SectionLabel("POSITION")
    imgui.PushItemWidth(160)
    imgui.Combo("Line Origin", linePos, posList, #posList)
    imgui.Combo("Dot Anchor", dotPos, posList, #posList)
    imgui.PopItemWidth()
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    SectionLabel("COLORS")
    imgui.ColorEdit3("Box Color", colEspBox)
    imgui.ColorEdit3("Line Color", colEspLine)
    imgui.ColorEdit3("Bone Color", colBone)
    XF(fontProggy)
end

function DrawCheatGeneral()
    PF(fontProggy)
    imgui.Spacing()
    SectionLabel("CHEAT GENERAL MENU")
    imgui.Checkbox("Bypass", spawnGunBypassEnabled)
    SmallNote("Enable this first.")
    imgui.Separator()
    imgui.Checkbox("No Recoil", noRecoilEnabled)
    SmallNote("Remove weapon recoil")
    imgui.Separator()
    imgui.Checkbox("Click Warp", clickWarpEnabled)
    SmallNote("Teleport use middle click")
    imgui.Separator()
    imgui.Checkbox("Max Damage", maxDamageEnabled)
    SmallNote("Increase shotgun damage")
    imgui.Separator()
    imgui.Checkbox("Rapid Fire", rapidFireEnabled)
    SmallNote("Speed up the weapon firing animation")
    imgui.PushItemWidth(280)
    if imgui.SliderFloat("Rapid Fire Speed", rapidFireSpeed, 0.1, 1.2, "%.1f") then
        rapidFireSpeed.v = math.min(1.2, math.max(0.1, rapidFireSpeed.v))
    end
    imgui.PopItemWidth()
    XF(fontProggy)
end

local spawnGunWeapons = {
    {id=22, model=346, name="Pistol",       category="Handgun",   slot=2, ammo=100,  damage=25,  range=35,  fire="Semi"},
    {id=23, model=347, name="Silenced Pistol",category="Handgun",slot=2, ammo=100,  damage=40,  range=35,  fire="Semi"},
    {id=24, model=348, name="Desert Eagle", category="Handgun",   slot=2, ammo=70,   damage=70,  range=35,  fire="Semi"},
    {id=25, model=349, name="Shotgun",      category="Shotgun",   slot=3, ammo=40,   damage=15,  range=40,  fire="Pellet"},
    {id=26, model=350, name="Sawn-Off",     category="Shotgun",   slot=3, ammo=50,   damage=14,  range=35,  fire="Pellet"},
    {id=27, model=351, name="Combat Shotgun",category="Shotgun",  slot=3, ammo=70,   damage=15,  range=40,  fire="Pellet"},
    {id=28, model=352, name="Micro SMG",    category="SMG",       slot=4, ammo=300,  damage=20,  range=30,  fire="Auto"},
    {id=29, model=353, name="MP5",          category="SMG",       slot=4, ammo=300,  damage=25,  range=40,  fire="Auto"},
    {id=32, model=372, name="TEC-9",        category="SMG",       slot=4, ammo=300,  damage=20,  range=30,  fire="Auto"},
    {id=30, model=355, name="AK-47",        category="Rifle",     slot=5, ammo=500,  damage=30,  range=70,  fire="Auto"},
    {id=31, model=356, name="M4",           category="Rifle",     slot=5, ammo=500,  damage=30,  range=90,  fire="Auto"},
    {id=33, model=357, name="Country Rifle",category="Rifle",     slot=6, ammo=200,   damage=75,  range=100, fire="Semi"},
    {id=34, model=358, name="Sniper Rifle",  category="Rifle",    slot=6, ammo=300,   damage=125, range=100, fire="Semi"},
    {id=35, model=359, name="RPG",           category="Heavy",    slot=7, ammo=20,   damage=100, range=90,  fire="Rocket"},
    {id=36, model=360, name="HS Rocket",     category="Heavy",    slot=7, ammo=20,   damage=100, range=90,  fire="Rocket"},
    {id=37, model=361, name="Flamethrower",  category="Heavy",    slot=7, ammo=500, damage=25, range=55,  fire="Stream"},
    {id=38, model=362, name="Minigun",       category="Heavy",    slot=7, ammo=500, damage=140, range=75, fire="Auto"},
    {id=16, model=342, name="Grenade",       category="Throwable",slot=8, ammo=10,   damage=100, range=30,  fire="Throw"},
    {id=18, model=344, name="Molotov",       category="Throwable",slot=8, ammo=10,   damage=40,  range=30,  fire="Throw"},
    {id=39, model=363, name="Satchel",       category="Throwable",slot=8, ammo=10,   damage=100, range=30,  fire="Deploy"},
    {id=41, model=365, name="Fire Exting...",category="Utility",slot=9,ammo=500, damage=0, range=25, fire="Stream"},
    {id=42, model=366, name="Spray Can",     category="Utility",   slot=9, ammo=500, damage=0, range=25, fire="Stream"},
    {id=43, model=367, name="Camera",        category="Utility",   slot=9, ammo=36,  damage=0, range=100, fire="Photo"},
    {id=9,  model=341, name="Chainsaw",      category="Melee",     slot=1, ammo=1,   damage=25, range=2,   fire="Melee"},
    {id=46, model=371, name="Parachute",     category="Utility",   slot=11,ammo=1,   damage=0, range=0,   fire="Deploy"},
}

function SpawnGunGiveWeapon(weaponId, modelId, ammo)
    if not isSampAvailable or isCharDead(PLAYER_PED) then return end
    ammo = math.max(1, tonumber(ammo) or 500)
    pcall(requestModel, modelId)
    pcall(loadAllModelsNow)
    pcall(giveWeaponToChar, PLAYER_PED, weaponId, ammo)
end

function SpawnGunNormalizeQuery(value)
    return tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

function SpawnGunMatches(weapon, query)
    if query == "" then return true end
    local haystack = string.format(
        "%s %d %d %s %s",
        weapon.name, weapon.id, weapon.model, weapon.category, weapon.fire
    ):lower()
    return haystack:find(query, 1, true) ~= nil
end

function DrawSpawnGun()
    PF(fontProggy)
    imgui.Spacing()
    SectionLabel("SPAWN GUN MENU")
    imgui.BeginChild("##sg_actions", imgui.ImVec2(0, 72), true)
    PF(fontBold)
    imgui.TextColored(imgui.ImVec4(PR, PG, PB, 1), "WEAPON ACTIONS")
    XF(fontBold)
    imgui.Spacing()
    local actionW = (imgui.GetContentRegionAvail().x - 8) / 2
    if imgui.Button("ADD AMMO ##sg_addammo", imgui.ImVec2(actionW, 28)) then
        pcall(function()
            local weapon = getCurrentCharWeapon(PLAYER_PED)
            if weapon and weapon > 0 then
                addAmmoToChar(PLAYER_PED, weapon, 500)
            end
        end)
    end
    imgui.SameLine()
    if imgui.Button("RESET WEAPON##sg_resetweapon", imgui.ImVec2(actionW, 28)) then
        pcall(removeAllCharWeapons, PLAYER_PED)
        pcall(setCurrentCharWeapon, PLAYER_PED, 0)
    end
    imgui.EndChild()
    imgui.Spacing()
    imgui.Text("Search")
    imgui.SameLine()
    imgui.PushItemWidth(300)
    imgui.InputText("##sgquery", spawnGunQuery)
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button("CLEAR##sgclear", imgui.ImVec2(60, 22)) then
        spawnGunQuery.v = ""
    end
    imgui.Spacing()
    local query = SpawnGunNormalizeQuery(spawnGunQuery.v)
    local matches = {}
    for i, weapon in ipairs(spawnGunWeapons) do
        if SpawnGunMatches(weapon, query) then
            matches[#matches + 1] = {index = i, data = weapon}
        end
    end
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    imgui.BeginChild("##sg_weaponlist", imgui.ImVec2(0, 0), true)
    PF(fontSmall)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "ID")
    imgui.SameLine(34)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "WEAPON")
    imgui.SameLine(150)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "TYPE")
    imgui.SameLine(235)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "AMMO")
    imgui.SameLine(285)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "DMG")
    imgui.SameLine(340)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "ACTION")
    XF(fontSmall)
    imgui.Separator()
    if #matches == 0 then
        imgui.Spacing()
        imgui.TextColored(imgui.ImVec4(0.95, 0.40, 0.40, 1), "No weapon matches your search.")
    else
        for _, item in ipairs(matches) do
            local i, w = item.index, item.data
            imgui.PushID(5000 + i)
            imgui.Text(string.format("%02d", w.id))
            imgui.SameLine(34)
            imgui.TextColored(imgui.ImVec4(0.86, 0.86, 0.90, 1), w.name)
            imgui.SameLine(150)
            imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1), w.category)
            imgui.SameLine(235)
            imgui.TextColored(imgui.ImVec4(PR, PG, PB, 1), tostring(w.ammo))
            imgui.SameLine(285)
            imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1), tostring(w.damage))
            imgui.SameLine(340)
            if imgui.Button("ADD##sg_add_" .. tostring(w.id), imgui.ImVec2(62, 22)) then
                SpawnGunGiveWeapon(w.id, w.model, math.max(1, tonumber(w.ammo) or 500))
            end
            imgui.PopID()
        end
    end
    imgui.EndChild()
    XF(fontProggy)
end

function DrawPlayerFinder()
    PF(fontProggy)
    imgui.Spacing()
    SectionLabel("PLAYER FINDER MENU")
    local query = tostring(finderQuery.v or "")
    local filtered = not query:match("^%s*$")
    local results = SearchPlayers(query)
    imgui.Spacing()
    imgui.Text("Search")
    imgui.SameLine()
    imgui.PushItemWidth(300) 
    imgui.InputText("##finderquery", finderQuery)
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button("CLEAR##finderclear", imgui.ImVec2(60, 22)) then
        finderQuery.v = ""
    end
    imgui.Spacing()
    imgui.BeginChild("##pf_playerlist", imgui.ImVec2(0, 0), true)
    PF(fontSmall)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "ID")
    imgui.SameLine(34)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "PLAYER")
    imgui.SameLine(150)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "SCORE")
    imgui.SameLine(205)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "MONEY")
    imgui.SameLine(285)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "DIST")
    imgui.SameLine(330)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "HP")
    imgui.SameLine(365)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "PING")
    XF(fontSmall)
    imgui.Separator()
    if #results == 0 then
        imgui.Spacing()
        if filtered then
            imgui.TextColored(imgui.ImVec4(0.95, 0.40, 0.40, 1), "No matching players found.")
        else
            imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "No players online.")
        end
    else
        for _, p in ipairs(results) do
            imgui.PushID(1000 + p.id)
            imgui.Text(string.format("%d", p.id))
            imgui.SameLine(34)
            if p.isLocal then
                imgui.TextColored(imgui.ImVec4(PR, PG, PB, 1), p.name .. " [YOU]")
            elseif p.streamed then
                imgui.TextColored(imgui.ImVec4(0.35, 0.90, 0.45, 1), p.name)
            else
                imgui.TextColored(imgui.ImVec4(0.78, 0.78, 0.82, 1), p.name)
            end
            imgui.SameLine(150)
            imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1), tostring(p.score or 0))
            imgui.SameLine(205)
            if p.money ~= nil then
                imgui.TextColored(imgui.ImVec4(0.40, 0.90, 0.50, 1), FormatMoney(p.money))
            else
                imgui.TextColored(imgui.ImVec4(0.50, 0.52, 0.58, 1), "-")
            end
            imgui.SameLine(285)
            if p.streamed and p.dist >= 0 then
                imgui.TextColored(
                    imgui.ImVec4(0.70, 0.75, 0.85, 1),
                    string.format("%.0fm", p.dist)
                )
            else
                imgui.TextColored(imgui.ImVec4(0.50, 0.52, 0.58, 1), "-")
            end
            imgui.SameLine(330)
            if p.streamed and p.hp >= 0 then
                local hcol = p.hp > 30
                    and imgui.ImVec4(0.35, 0.90, 0.45, 1)
                    or imgui.ImVec4(0.95, 0.35, 0.35, 1)
                imgui.TextColored(hcol, string.format("%.0f", p.hp))
            else
                imgui.TextColored(imgui.ImVec4(0.50, 0.52, 0.58, 1), "-")
            end
            imgui.SameLine(365)
            if p.ping and p.ping >= 0 then
                imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1), tostring(p.ping))
            else
                imgui.TextColored(imgui.ImVec4(0.50, 0.52, 0.58, 1), "-")
            end
            imgui.PopID()
        end
    end
    imgui.EndChild()
    XF(fontProggy)
end

function DrawAutoRP()
    PF(fontProggy)
    imgui.Spacing()
    SectionLabel("AUTO ROLEPLAY MENU")
    for i = 1, #autoRPCommands do
        imgui.Spacing()
        imgui.Text(string.format("Command %d", i))
        imgui.SameLine()
        imgui.PushItemWidth(205)
        imgui.InputText("##autorpcmd"..i, autoRPCommands[i])
        imgui.PopItemWidth()
        imgui.SameLine()
        if imgui.Button(waitingAutoRPKey[i] and "Press..." or (autoRPKeys[i] > 0 and autoRPKeyNames[i] or "Set Key"), imgui.ImVec2(82, 24)) then
            for j = 1, #waitingAutoRPKey do waitingAutoRPKey[j] = false end
            waitingAutoRPKey[i] = true
        end
        imgui.SameLine()
        if imgui.Button("Delete##autorprm"..i, imgui.ImVec2(60, 24)) then
            if i <= 5 then
                autoRPCommands[i].v = ""
                autoRPKeys[i] = 0
                autoRPKeyNames[i] = "Not Set"
                waitingAutoRPKey[i] = false
            else
                table.remove(autoRPCommands, i)
                table.remove(autoRPKeys, i)
                table.remove(autoRPKeyNames, i)
                table.remove(waitingAutoRPKey, i)
            end
            break
        end
        if waitingAutoRPKey[i] then SmallNote("Press the key you want to use...") end
    end
    local allFilled = true
    for i = 1, #autoRPCommands do
        if tostring(autoRPCommands[i].v or ""):match("^%s*$") then allFilled = false break end
    end
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    if allFilled then
        if imgui.Button("+ ADD COMMAND SLOT", imgui.ImVec2(190, 30)) then
            local n = #autoRPCommands + 1
            autoRPCommands[n] = imgui.ImBuffer("", 128)
            autoRPKeys[n], autoRPKeyNames[n], waitingAutoRPKey[n] = 0, "Not Set", false
        end
    else
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.50, 0.52, 0.58, 1))
        imgui.Button("+ ADD COMMAND SLOT", imgui.ImVec2(190, 30))
        imgui.PopStyleColor()
    end
    SmallNote(allFilled and "All slots are filled — you can add a new slot." or "Fill all available slots before adding a new slot.")
    XF(fontProggy)
end

local skinNameLookup = {
    [0] = "CJ",
    [1] = "Truth",
    [2] = "Maccer",
    [3] = "Andre",
    [4] = "Barry Big Bear",
    [5] = "Barry Big Bear Big",
    [6] = "Emmet",
    [7] = "Taxi Driver",
    [8] = "Janitor",
    [9] = "Normal Ped",
    [10] = "Old Woman",
    [11] = "Casino Croupier",
    [12] = "Rich Woman",
    [13] = "Street Girl",
    [14] = "Normal Ped",
    [15] = "Mr. Whittaker",
    [16] = "Airport Worker",
    [17] = "Businessman",
    [18] = "Beach Visitor",
    [19] = "DJ",
    [20] = "Rich Guy",
    [21] = "Normal Ped",
    [22] = "Normal Ped",
    [23] = "BMXer",
    [24] = "Madd Dogg Bodyguard",
    [25] = "Madd Dogg Bodyguard",
    [26] = "Backpacker",
    [27] = "Construction Worker",
    [28] = "Drug Dealer",
    [29] = "Drug Dealer",
    [30] = "Drug Dealer",
    [31] = "Farm Town Inhabitant",
    [32] = "Farm Town Inhabitant",
    [33] = "Farm Town Inhabitant",
    [34] = "Farm Town Inhabitant",
    [35] = "Gardener",
    [36] = "Golfer",
    [37] = "Golfer",
    [38] = "Normal Ped",
    [39] = "Normal Ped",
    [40] = "Normal Ped",
    [41] = "Normal Ped",
    [42] = "Jethro",
    [43] = "Normal Ped",
    [44] = "Normal Ped",
    [45] = "Beach Visitor",
    [46] = "Normal Ped",
    [47] = "Normal Ped",
    [48] = "Normal Ped",
    [49] = "Snakehead",
    [50] = "Mechanic",
    [51] = "Mountain Biker",
    [52] = "Mountain Biker",
    [53] = "Normal Ped",
    [54] = "Normal Ped",
    [55] = "Normal Ped",
    [56] = "Normal Ped",
    [57] = "Oriental Ped",
    [58] = "Oriental Ped",
    [59] = "Normal Ped",
    [60] = "Normal Ped",
    [61] = "Pilot",
    [62] = "Colonel Fuhrberger",
    [63] = "Prostitute",
    [64] = "Prostitute",
    [65] = "Kendl",
    [66] = "Pool Player",
    [67] = "Pool Player",
    [68] = "Priest",
    [69] = "Normal Ped",
    [70] = "Scientist",
    [71] = "Security Guard",
    [72] = "Hippy",
    [73] = "Hippy",
    [74] = "Prostitute",
    [75] = "Prostitute",
    [76] = "Stewardess",
    [77] = "Homeless",
    [78] = "Homeless",
    [79] = "Homeless",
    [80] = "Boxer",
    [81] = "Boxer",
    [82] = "Black Elvis",
    [83] = "White Elvis",
    [84] = "Blue Elvis",
    [85] = "Prostitute",
    [86] = "Ryder Mask",
    [87] = "Stripper",
    [88] = "Normal Ped",
    [89] = "Normal Ped",
    [90] = "Jogger",
    [91] = "Rich Woman",
    [92] = "Rollerskater",
    [93] = "Normal Ped",
    [94] = "Normal Ped",
    [95] = "Jogger",
    [96] = "Lifeguard",
    [97] = "Normal Ped",
    [98] = "Normal Ped",
    [99] = "Rollerskater",
    [100] = "Biker",
    [101] = "Normal Ped",
    [102] = "Balla",
    [103] = "Balla",
    [104] = "Balla",
    [105] = "Grove Street Family",
    [106] = "Grove Street Family",
    [107] = "Grove Street Family",
    [108] = "Los Santos Vagos",
    [109] = "Los Santos Vagos",
    [110] = "Los Santos Vagos",
    [111] = "Russian Mafia",
    [112] = "Russian Mafia",
    [113] = "Russian Mafia Boss",
    [114] = "Varios Los Aztecas",
    [115] = "Varios Los Aztecas",
    [116] = "Varios Los Aztecas",
    [117] = "Triad",
    [118] = "Triad",
    [119] = "Johhny Sindacco",
    [120] = "Triad Boss",
    [121] = "Da Nang Boy",
    [122] = "Da Nang Boy",
    [123] = "Da Nang Boy",
    [124] = "The Mafia",
    [125] = "The Mafia",
    [126] = "The Mafia",
    [127] = "The Mafia",
    [128] = "Farm Inhabitant",
    [129] = "Farm Inhabitant",
    [130] = "Farm Inhabitant",
    [131] = "Farm Inhabitant",
    [132] = "Farm Inhabitant",
    [133] = "Farm Inhabitant",
    [134] = "Homeless",
    [135] = "Homeless",
    [136] = "Normal Ped",
    [137] = "Homeless",
    [138] = "Beach Visitor",
    [139] = "Beach Visitor",
    [140] = "Beach Visitor",
    [141] = "Businesswoman",
    [142] = "Taxi Driver",
    [143] = "Crack Maker",
    [144] = "Crack Maker",
    [145] = "Crack Maker",
    [146] = "Crack Maker",
    [147] = "Businessman",
    [148] = "Businesswoman",
    [149] = "Big Smoke Armored",
    [150] = "Businesswoman",
    [151] = "Normal Ped",
    [152] = "Prostitute",
    [153] = "Construction Worker",
    [154] = "Beach Visitor",
    [155] = "Pizza Worker",
    [156] = "Barber",
    [157] = "Hillbilly",
    [158] = "Farmer",
    [159] = "Hillbilly",
    [160] = "Hillbilly",
    [161] = "Farmer",
    [162] = "Hillbilly",
    [163] = "Black Bouncer",
    [164] = "White Bouncer",
    [165] = "White MIB",
    [166] = "Black MIB",
    [167] = "Cluckin' Bell Worker",
    [168] = "Hotdog Vendor",
    [169] = "Normal Ped",
    [170] = "Normal Ped",
    [171] = "Blackjack Dealer",
    [172] = "Casino Croupier",
    [173] = "San Fierro Rifa",
    [174] = "San Fierro Rifa",
    [175] = "San Fierro Rifa",
    [176] = "Barber",
    [177] = "Barber",
    [178] = "Whore",
    [179] = "Ammunation Salesman",
    [180] = "Tattoo Artist",
    [181] = "Punk",
    [182] = "Cab Driver",
    [183] = "Normal Ped",
    [184] = "Normal Ped",
    [185] = "Normal Ped",
    [186] = "Normal Ped",
    [187] = "Businessman",
    [188] = "Normal Ped",
    [189] = "Valet",
    [190] = "Barbara Schternvart",
    [191] = "Helena Wankstein",
    [192] = "Michelle Cannes",
    [193] = "Katie Zhan",
    [194] = "Millie Perkins",
    [195] = "Denise Robinson",
    [196] = "Farm Inhabitant",
    [197] = "Hillbilly",
    [198] = "Farm Inhabitant",
    [199] = "Farm Inhabitant",
    [200] = "Hillbilly",
    [201] = "Farmer",
    [202] = "Farmer",
    [203] = "Karate Teacher",
    [204] = "Karate Teacher",
    [205] = "Burger Shot Cashier",
    [206] = "Cab Driver",
    [207] = "Prostitute",
    [208] = "Suzie",
    [209] = "Noodle Vendor",
    [210] = "Boating School Instructor",
    [211] = "Clothes Shop Staff",
    [212] = "Homeless",
    [213] = "Weird Old Man",
    [214] = "Waitress",
    [215] = "Normal Ped",
    [216] = "Normal Ped",
    [217] = "Clothes Shop Staff",
    [218] = "Normal Ped",
    [219] = "Rich Woman",
    [220] = "Cab Driver",
    [221] = "Normal Ped",
    [222] = "Normal Ped",
    [223] = "Normal Ped",
    [224] = "Normal Ped",
    [225] = "Normal Ped",
    [226] = "Normal Ped",
    [227] = "Oriental Businessman",
    [228] = "Oriental Ped",
    [229] = "Oriental Ped",
    [230] = "Homeless",
    [231] = "Normal Ped",
    [232] = "Normal Ped",
    [233] = "Normal Ped",
    [234] = "Cab Driver",
    [235] = "Normal Ped",
    [236] = "Normal Ped",
    [237] = "Prostitute",
    [238] = "Prostitute",
    [239] = "Homeless",
    [240] = "The D.A",
    [241] = "Afro-American",
    [242] = "Mexican",
    [243] = "Prostitute",
    [244] = "Stripper",
    [245] = "Prostitute",
    [246] = "Stripper",
    [247] = "Biker",
    [248] = "Biker",
    [249] = "Pimp",
    [250] = "Normal Ped",
    [251] = "Lifeguard",
    [252] = "Naked Valet",
    [253] = "Bus Driver",
    [254] = "Biker Drug Dealer",
    [255] = "Chauffeur",
    [256] = "Stripper",
    [257] = "Stripper",
    [258] = "Heckler",
    [259] = "Heckler",
    [260] = "Construction Worker",
    [261] = "Cab Driver",
    [262] = "Cab Driver",
    [263] = "Normal Ped",
    [264] = "Clown",
    [265] = "Officer Frank Tenpenny",
    [266] = "Officer Eddie Pulaski",
    [267] = "Officer Jimmy Hernandez",
    [268] = "Dwayne",
    [269] = "Big Smoke",
    [270] = "Sweet",
    [271] = "Ryder",
    [272] = "Mafia Boss",
    [273] = "T-Bone Mendez",
    [274] = "Paramedic",
    [275] = "Paramedic",
    [276] = "Paramedic",
    [277] = "Firefighter",
    [278] = "Firefighter",
    [279] = "Firefighter",
    [280] = "Los Santos Police",
    [281] = "San Fierro Police",
    [282] = "Las Venturas Police",
    [283] = "County Sheriff",
    [284] = "LSPD Motorbike Cop",
    [285] = "S.W.A.T",
    [286] = "FBI Agent",
    [287] = "Army Soldier",
    [288] = "Desert Sheriff",
    [289] = "Zero",
    [290] = "Ken Rosenberg",
    [291] = "Kent Paul",
    [292] = "Cesar Vialpando",
    [293] = "OG Loc",
    [294] = "Wu Zi Mu",
    [295] = "Michael Toreno",
    [296] = "Jizzy B.",
    [297] = "Madd Dogg",
    [298] = "Catalina",
    [299] = "Claude Speed",
    [300] = "Los Santos Police No Holster",
    [301] = "San Fierro Police No Holster",
    [302] = "Las Venturas Police No Holster",
    [303] = "Los Santos Police No Uniform",
    [304] = "Los Santos Police No Uniform",
    [305] = "Las Venturas Police No Uniform",
    [306] = "Los Santos Police Female",
    [307] = "San Fierro Police Female",
    [308] = "San Fierro Paramedic Female",
    [309] = "Las Venturas Police Female",
    [310] = "Country Sheriff No Hat",
    [311] = "Desert Sheriff No Hat"
}

function GetSkinChangerPathForId(skinId)
    local candidates = {
        getGameDirectory() .. "\\moonloader\\config\\peds",
        getGameDirectory() .. "\\moonloader\\resource\\skin_peds",
        (thisScript().path:match("(.+)\\[^\\]+$") or "") .. "\\resource\\skin_peds"
    }
    for _, basePath in ipairs(candidates) do
        local path = basePath .. "\\skin_" .. tostring(skinId) .. ".png"
        if pcall(function() return doesFileExist(path) end) and doesFileExist(path) then
            return path
        end
    end
    return nil
end

function LoadSkinChangerTextures()
    if skinChangerLoaded then return true end
    skinTextures = {}
    for skinId = 0, 311 do
        local path = GetSkinChangerPathForId(skinId)
        if path then
            local ok, tex = pcall(function()
                return imgui.CreateTextureFromFile(path)
            end)
            if ok and tex then
                skinTextures[skinId] = tex
            end
        end
    end
    skinChangerLoaded = true
    return true
end

function GetSkinNameById(skinId)
    local name = skinNameLookup[tonumber(skinId)]
    if name then
        return name
    end
    return "Skin " .. tostring(skinId)
end

function GetCurrentSkinModel()
    local ok, model = pcall(getCharModel, PLAYER_PED)
    if ok and model then
        return tonumber(model)
    end
    return nil
end

function SetSkinChangerLock(enabled, skinId)
    skinChangerLockEnabled = enabled == true
    if skinChangerLockEnabled then
        local lockedModel = tonumber(skinId)
        if lockedModel and lockedModel >= 0 then
            skinChangerLockedModel = lockedModel
        else
            skinChangerLockedModel = skinChangerSelected
        end
    else
        skinChangerLockedModel = nil
    end
end

function ResetSkinChangerLock()
    SetSkinChangerLock(false)
end

function RestoreOriginalSkinOnReload()
    ResetSkinChangerLock()
    local restoreModel = skinChangerOriginalModel
    if not restoreModel or restoreModel == 0 then
        restoreModel = GetCurrentSkinModel()
    end
    if restoreModel and restoreModel > 0 then
        local ok, okPlayer, playerId = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
        if ok and okPlayer and playerId then
            local bitStream = raknetNewBitStream()
            raknetBitStreamWriteInt32(bitStream, playerId)
            raknetBitStreamWriteInt32(bitStream, tonumber(restoreModel))
            raknetEmulRpcReceiveBitStream(153, bitStream)
            raknetDeleteBitStream(bitStream)
        end
    end
    skinChangerSelected = 0
end

function onScriptTerminate(scr)
    if scr ~= thisScript() then return end
    RestoreOriginalSkinOnReload()
end

function ApplySkinChangerSelection(skinId)
    local safeSkinId = tonumber(skinId) or 0
    if safeSkinId < 0 then
        safeSkinId = 0
    end
    skinChangerSelected = safeSkinId

    local ok, okPlayer, playerId = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
    if ok and okPlayer and playerId then
        local bitStream = raknetNewBitStream()
        raknetBitStreamWriteInt32(bitStream, playerId)
        raknetBitStreamWriteInt32(bitStream, safeSkinId)
        raknetEmulRpcReceiveBitStream(153, bitStream)
        raknetDeleteBitStream(bitStream)
    end
end

function SkinChangerLockThread()
    while true do
        wait(250)
        if skinChangerLockEnabled and skinChangerLockedModel ~= nil
            and isSampAvailable and doesCharExist(PLAYER_PED) then
            local currentModel = GetCurrentSkinModel()
            if currentModel ~= nil and currentModel ~= skinChangerLockedModel then
                ApplySkinChangerSelection(skinChangerLockedModel)
            end
        end
    end
end

function GetSkinChangerFilteredList()
    LoadSkinChangerTextures()
    local query = tostring(skinChangerSearch.v or ""):lower():match("^%s*(.-)%s*$")
    local list = {}
    for skinId = 0, 311 do
        if skinTextures[skinId] then
            local name = GetSkinNameById(skinId)
            local lowerName = tostring(name):lower()
            local score = 0
            if query == "" then
                score = 1
            else
                if lowerName == query then
                    score = 1000
                elseif lowerName:find(query, 1, true) then
                    score = 800
                    if lowerName:find("^" .. query, 1, true) then
                        score = 1000
                    end
                end
                if tostring(skinId):find(query, 1, true) then
                    score = math.max(score, 600)
                end
            end
            if score > 0 then
                list[#list + 1] = { id = skinId, name = name, score = score }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        if a.name ~= b.name then
            return tostring(a.name):lower() < tostring(b.name):lower()
        end
        return a.id < b.id
    end)
    return list
end

function DrawSkinChanger()
    PF(fontProggy)
    imgui.Spacing()
    SectionLabel("SKIN CHANGER MENU")
    imgui.Spacing()
    imgui.Text("Search")
    imgui.SameLine()
    imgui.PushItemWidth(233)
    if imgui.InputText("##skin_search_input", skinChangerSearch) then
    end
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button("RESTORE##skin_restore", imgui.ImVec2(60, 22)) then
        ResetSkinChangerLock()
        if skinChangerRestoreId and skinChangerRestoreId > 0 then
            ApplySkinChangerSelection(skinChangerRestoreId)
        else
            local ok, okPlayer, playerId = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
            if ok and okPlayer and playerId then
                local okModel, model = pcall(getCharModel, PLAYER_PED)
                if okModel and model then
                    ApplySkinChangerSelection(model)
                end
            end
        end
        SaveAutoConfig()
    end
    imgui.SameLine()
    if imgui.Button("CLEAR##skin_clear", imgui.ImVec2(60, 22)) then
        skinChangerSearch.v = ""
    end
    imgui.Spacing()
    imgui.SetCursorPosX(imgui.GetCursorPosX() - 15)
    imgui.BeginChild("##skin_grid", imgui.ImVec2(460, 0), true)
    local skinList = GetSkinChangerFilteredList()
    if #skinList == 0 then
        imgui.Spacing()
        imgui.TextColored(imgui.ImVec4(0.95, 0.40, 0.40, 1), "No skins match your search.")
    else
        local cols = 5
        local itemIndex = 0
        for _, item in ipairs(skinList) do
            if itemIndex > 0 and itemIndex % cols == 0 then
                imgui.NewLine()
            elseif itemIndex > 0 then
                imgui.SameLine(0, 8)
            end

            imgui.PushID(9800 + item.id)
            imgui.BeginGroup()
            local selected = (skinChangerSelected == item.id)
            if selected then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(PR, PG, PB, 0.18))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(PR, PG, PB, 0.26))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(PR, PG, PB, 0.35))
            end
            if imgui.ImageButton(skinTextures[item.id], imgui.ImVec2(78, 92), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), 1,
                imgui.ImVec4(0.06, 0.06, 0.08, 0.20), imgui.ImVec4(1, 1, 1, 1)) then
                skinChangerSelected = item.id
                if not skinChangerRestoreId or skinChangerRestoreId == 0 then
                    skinChangerRestoreId = getCharModel(PLAYER_PED)
                end
                SetSkinChangerLock(true, item.id)
                ApplySkinChangerSelection(item.id)
                SaveAutoConfig()
            end
            if selected then
                imgui.PopStyleColor(3)
            end
            imgui.TextColored(selected and imgui.ImVec4(PR, PG, PB, 1) or imgui.ImVec4(0.82, 0.84, 0.90, 1), string.format("%d", item.id))
            local label = item.name
            if #label > 9 then
                label = label:sub(1, 8) .. "..."
            end
            imgui.TextColored(selected and imgui.ImVec4(PR, PG, PB, 1) or imgui.ImVec4(0.70, 0.75, 0.85, 1), label)
            imgui.EndGroup()
            imgui.PopID()
            itemIndex = itemIndex + 1
        end
    end
    imgui.Unindent(2)
    imgui.EndChild()
    XF(fontProggy)
end

function DrawMusicPlayer()
    PF(fontProggy)
    imgui.Spacing()
    SectionLabel("MUSIC PLAYER MENU")
    imgui.BeginChild("##music_actions", imgui.ImVec2(0, 72), true)
    PF(fontBold)
    imgui.TextColored(imgui.ImVec4(PR, PG, PB, 1), "MUSIC ACTION")
    XF(fontBold)
    imgui.Spacing()

    local btnW = 68
    if imgui.Button("<<##mprev", imgui.ImVec2(btnW, 28)) then
        MusicPrev()
    end
    imgui.SameLine()
    if musicPlaying and not musicPaused then
        if imgui.Button("PAUSE##mpause", imgui.ImVec2(btnW, 28)) then
            MusicTogglePause()
        end
    else
        if imgui.Button("PLAY##mplay", imgui.ImVec2(btnW, 28)) then
            if musicStream and musicPaused then
                MusicTogglePause()
            elseif musicIndex >= 1 and musicIndex <= #musicList then
                MusicPlayIndex(musicIndex)
            elseif #musicList > 0 then
                MusicPlayIndex(1)
            end
        end
    end
    imgui.SameLine()
    if imgui.Button("STOP##mstop", imgui.ImVec2(btnW, 28)) then
        MusicStop(false)
    end
    imgui.SameLine()
    if imgui.Button(">>##mnext", imgui.ImVec2(btnW, 28)) then
        MusicNext()
    end
    imgui.SameLine()
    if imgui.Button("SCAN##mscan", imgui.ImVec2(btnW, 28)) then
        local n = ScanMusicFiles()
        printStringNow(string.format("~g~Scanned: ~w~%d track(s)", n), 2000)
        musicStatus = n > 0 and "Ready" or "Folder empty"
    end
    imgui.EndChild()
    imgui.Spacing()
    local displayName = musicCurrentName or "No track selected"
    if #displayName > 48 then
        displayName = displayName:sub(1, 45) .. "..."
    end
    imgui.TextColored(imgui.ImVec4(0.86, 0.86, 0.90, 1), displayName)
    imgui.SameLine()
    local statusCol = imgui.ImVec4(0.55, 0.58, 0.65, 1)
    if musicStatus == "Playing" then
        statusCol = imgui.ImVec4(0.35, 0.90, 0.45, 1)
    elseif musicStatus == "Paused" then
        statusCol = imgui.ImVec4(0.95, 0.75, 0.30, 1)
    elseif musicStatus == "Failed to load" then
        statusCol = imgui.ImVec4(0.95, 0.35, 0.35, 1)
    end
    local statusTxt = musicStatus or "Idle"
    if #musicList > 0 and musicIndex > 0 then
        statusTxt = string.format("%s  (%d/%d)", statusTxt, musicIndex, #musicList)
    end
    imgui.TextColored(statusCol, statusTxt)
    imgui.Spacing()
    imgui.Text("Volume")
    imgui.SameLine()
    imgui.PushItemWidth(220)
    if imgui.SliderFloat("##musicvol", musicVolume, 0.0, 1.0, "%.2f") then
        MusicApplyVolume()
    end
    imgui.PopItemWidth()
    imgui.SameLine()
    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1),
        string.format("%d%%", math.floor(musicVolume.v * 100 + 0.5)))
    imgui.SameLine(0, 16)
    if imgui.Checkbox("Loop", musicLoop) then
        if musicStream then
            pcall(setAudioStreamLooped, musicStream, musicLoop.v)
        end
    end
    imgui.Spacing()
    imgui.Separator()
    imgui.BeginChild("##musiclist", imgui.ImVec2(0, 0), true)
    PF(fontSmall)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "ID")
    imgui.SameLine(34)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "TRACK")
    imgui.SameLine(320)
    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 1), "ACTION")
    XF(fontSmall)
    imgui.Separator()
    if #musicList == 0 then
        imgui.Spacing()
        imgui.TextColored(imgui.ImVec4(0.95, 0.40, 0.40, 1), "No tracks found.")
    else
        for i, name in ipairs(musicList) do
            imgui.PushID(9000 + i)
            local selected = (i == musicIndex)
            local isPlaying = selected and (musicPlaying or musicPaused)
            imgui.Text(string.format("%d", i))
            imgui.SameLine(34)
            local showName = name
            if #showName > 36 then
                showName = showName:sub(1, 33) .. "..."
            end
            if isPlaying then
                imgui.TextColored(imgui.ImVec4(PR, PG, PB, 1), showName)
            else
                imgui.TextColored(imgui.ImVec4(0.86, 0.86, 0.90, 1), showName)
            end
            imgui.SameLine(320)
            local btnLabel = (isPlaying and musicPlaying and not musicPaused) and "PLAYING" or "PLAY"
            if imgui.Button(btnLabel .. "##mtrack" .. tostring(i), imgui.ImVec2(68, 22)) then
                MusicPlayIndex(i)
            end
            imgui.PopID()
        end
    end
    imgui.EndChild()
    XF(fontProggy)
end

function DrawOpenMenu()
    PF(fontProggy)
    imgui.Spacing()
    SectionLabel("CUSTOM OPEN MENU")
    imgui.Spacing()
    imgui.BeginChild("##om_keybind_sec", imgui.ImVec2(0, 117), true)
    PF(fontBold)
    imgui.TextColored(imgui.ImVec4(PR, PG, PB, 1), "KEYBIND SHORTCUT")
    XF(fontBold)
    imgui.Spacing()
    if imgui.Checkbox("Enable Keybind Open##om_enable_key", menuUseKeybind) then
        EnsureMenuOpenMethodAvailable()
    end
    imgui.Spacing()
    local comboText = ""
    if menuModKey > 0 then
        comboText = getKeyName(menuModKey) .. " + " .. getKeyName(menuKey)
    else
        comboText = getKeyName(menuKey)
    end
    imgui.Text("Active Shortcut:")
    imgui.SameLine()
    imgui.TextColored(imgui.ImVec4(0.35, 0.90, 0.45, 1), comboText)
    imgui.Spacing()
    local keyBtnW = 135
    if imgui.Button(waitingMenuKey and "Press Key..." or ("Key: " .. getKeyName(menuKey)), imgui.ImVec2(keyBtnW, 26)) then
        waitingMenuKey = true
        waitingMenuModKey = false
    end
    imgui.SameLine()
    if imgui.Button(waitingMenuModKey and "Press Mod..." or ("Modifier: " .. (menuModKey > 0 and getKeyName(menuModKey) or "None")), imgui.ImVec2(keyBtnW, 26)) then
        waitingMenuModKey = true
        waitingMenuKey = false
    end
    imgui.SameLine()
    if imgui.Button("RESTORE", imgui.ImVec2(100, 26)) then
        menuModKey = 0
        menuModKeyName = "None"
        waitingMenuModKey = false
    end
    imgui.EndChild()
    imgui.Spacing()
    imgui.BeginChild("##om_cmd_sec", imgui.ImVec2(0, 90), true)
    PF(fontBold)
    imgui.TextColored(imgui.ImVec4(PR, PG, PB, 1), "SAMP CHAT COMMAND")
    XF(fontBold)
    imgui.Spacing()
    if imgui.Checkbox("Enable Chat Command##om_enable_cmd", menuUseCommand) then
        EnsureMenuOpenMethodAvailable()
        UpdateMenuCommandRegistration()
    end
    imgui.Spacing()
    imgui.Text("Command:")
    imgui.SameLine()
    imgui.TextColored(imgui.ImVec4(0.70, 0.75, 0.85, 1), "/")
    imgui.SameLine()
    imgui.PushItemWidth(180)
    if imgui.InputText("##om_cmd_input", menuCommand) then
        UpdateMenuCommandRegistration()
    end
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button("RESTORE##om_cmd_rst", imgui.ImVec2(80, 22)) then
        menuCommand.v = "saproject"
        UpdateMenuCommandRegistration()
    end
    imgui.EndChild()
    XF(fontProggy)
end

menuOpen = imgui.ImBool(false)
local activeTab = 1
local tabs = {
    "Aimbot",
    "ESP",
    "C-Bug",
    "Auto RP",
    "Cheat General",
    "Spawn Gun",
    "Player Finder",
    "Skin Changer",
    "Music Player",
    "Open Menu"
}

function imgui.OnDrawFrame()
    LoadAutoConfig()
    if not menuOpen.v then 
        return 
    end
    imgui.SetNextWindowPos(imgui.ImVec2(280, 150), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(WIN_W, WIN_H), imgui.Cond.Always)
    if not imgui.Begin("Samp Project 5.0| By @rullzsy_", menuOpen, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar) then
        imgui.End()
        return
    end
    imgui.BeginChild("##sb", imgui.ImVec2(SIDE_W, INNER_H), true)
    imgui.Spacing()
    PF(fontBold)
    local bw = imgui.CalcTextSize("JACK404").x
    imgui.SetCursorPosX((SIDE_W - bw)/3 - 4)
    imgui.TextColored(imgui.ImVec4(PR, PG, PB, 1), "Version 5.0")
    XF(fontBold)
    imgui.Separator()
    imgui.Spacing()
    PF(fontProggy)
    for i, label in ipairs(tabs) do
        local active = (activeTab == i)
        if active then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(PR, PG, PB, 1))
            imgui.PushStyleColor(
                imgui.Col.ButtonHovered,
                imgui.ImVec4(PR + 0.1, PG + 0.1, PB + 0.1, 1)
            )
            imgui.PushStyleColor(
                imgui.Col.ButtonActive,
                imgui.ImVec4(PR + 0.15, PG + 0.15, PB + 0.15, 1)
            )
            imgui.PushStyleColor(
                imgui.Col.Text,
                imgui.ImVec4(1, 1, 1, 1)
            )
        end
        imgui.SetCursorPosX(12)
        if imgui.Button(label, imgui.ImVec2(SIDE_W - 36, 28)) then
            if activeTab ~= i then
                activeTab = i
            end
        end
        if active then
            imgui.PopStyleColor(4)
        end
        if i < #tabs then
            imgui.Dummy(imgui.ImVec2(0, 2))
        end
    end
    XF(fontProggy)
    local footerY = INNER_H - 23
    if footerY > imgui.GetCursorPosY() then imgui.SetCursorPosY(footerY) end
    imgui.Separator()
    PF(fontSmall)
    local aw = imgui.CalcTextSize("@rullzsy_").x
    imgui.SetCursorPosX((SIDE_W - aw)/2 - 4)
    imgui.TextColored(imgui.ImVec4(1,1,1,1), "@rullzsy_")
    XF(fontSmall)
    imgui.EndChild()
    imgui.SameLine(0, 6)
    imgui.BeginChild("##ct", imgui.ImVec2(INNER_W - SIDE_W - 6, INNER_H), true)
    imgui.Indent(8)
    if activeTab == 1 then DrawAimbot()
    elseif activeTab == 2 then DrawEsp()
    elseif activeTab == 3 then DrawCbug()
    elseif activeTab == 4 then DrawAutoRP()
    elseif activeTab == 5 then DrawCheatGeneral()
    elseif activeTab == 6 then DrawSpawnGun()
    elseif activeTab == 7 then DrawPlayerFinder()
    elseif activeTab == 8 then DrawSkinChanger()
    elseif activeTab == 9 then DrawMusicPlayer()
    elseif activeTab == 10 then DrawOpenMenu()
    end
    imgui.Unindent(8)
    imgui.EndChild()
    imgui.End()
end

function GetBoxPoint(cx, ty, by, pos)
    if pos == 0 then return cx, ty
    elseif pos == 1 then return cx, (ty + by)/2
    else return cx, by end
end

function GetLineStart(pos)
    local sw, sh = getScreenResolution()
    local cx = sw / 2
    if pos == 0 then return cx, 0
    elseif pos == 1 then return cx, sh / 2
    else return cx, sh end
end

function DrawCornerBox(x, y, w, h, col, thick)
    local aw, ah = w * cornerFrac, h * cornerFrac
    renderDrawLine(x, y, x+aw, y, thick, col)
    renderDrawLine(x, y, x, y+ah, thick, col)
    renderDrawLine(x+w, y, x+w-aw, y, thick, col)
    renderDrawLine(x+w, y, x+w, y+ah, thick, col)
    renderDrawLine(x, y+h, x+aw, y+h, thick, col)
    renderDrawLine(x, y+h, x, y+h-ah, thick, col)
    renderDrawLine(x+w, y+h, x+w-aw, y+h, thick, col)
    renderDrawLine(x+w, y+h, x+w, y+h-ah, thick, col)
end

function DrawFovCircle(cx, cy, radius, color, segments, thickness)
    segments = segments or 128
    thickness = thickness or 1.2
    local step = (math.pi * 2) / segments
    for i = 0, segments - 1 do
        local a1 = i * step
        local a2 = (i + 1) * step
        local x1 = cx + math.cos(a1) * radius
        local y1 = cy + math.sin(a1) * radius
        local x2 = cx + math.cos(a2) * radius
        local y2 = cy + math.sin(a2) * radius
        renderDrawLine(x1, y1, x2, y2, thickness, color)
    end
end

local curFovX, curFovY, curFovR = nil, nil, nil
function FovThread()
    while true do
        wait(0)
        if ab.showFov.v and isSampAvailable and not isCharDead(PLAYER_PED) then
            local weapon = getCurrentCharWeapon(PLAYER_PED)
            if ab.smoothWpn[weapon] or weapon == 0 or weapon == 34 then
                local sw, sh = getScreenResolution()
                local isRifle = ab.rifleWpn and ab.rifleWpn[weapon]
                local isCountry = ab.countryRifleWpn and ab.countryRifleWpn[weapon]
                local isSniper = (ab.sniperWpn and ab.sniperWpn[weapon]) or weapon == 34
                local isScopeWpn = isRifle or isCountry or isSniper
                local isRButtonAim = isKeyDown(vkeys.VK_RBUTTON)
                local isAiming = isScopeWpn and (isRButtonAim or (type(getCharPlayerAiming) == 'function' and getCharPlayerAiming(PLAYER_PED) and not isSniper))
                local targetCX, targetCY
                if isSniper then
                    targetCX = sw * 0.5
                    targetCY = sh * 0.5
                else
                    targetCX, targetCY = convertGameScreenCoordsToWindowScreenCoords(339.1, 179.1)
                    targetCX = (targetCX or (sw * 0.5298)) + (sw * 0.001)
                    targetCY = targetCY or (sh * 0.3997)
                end
                local curRadius = ab.radius.v
                if isRifle then
                    curRadius = ab.rifleRadius.v
                elseif isCountry then
                    curRadius = ab.countryRadius.v
                elseif isSniper then
                    curRadius = ab.sniperRadius.v
                end
                local zoomMult = (isAiming and not isSniper) and 1.35 or 1.0
                local targetR = (curRadius * 16.5) * (sh / 600.0) * zoomMult
                if not curFovX then
                    curFovX, curFovY, curFovR = targetCX, targetCY, targetR
                else
                    local speed = 0.25
                    curFovX = curFovX + (targetCX - curFovX) * speed
                    curFovY = curFovY + (targetCY - curFovY) * speed
                    curFovR = curFovR + (targetR - curFovR) * speed
                end
                if isSniper and isRButtonAim then
                    curFovX, curFovY, curFovR = targetCX, targetCY, targetR
                else
                    local fovColor = ColorToARGB(colFov, 220)
                    DrawFovCircle(curFovX, curFovY, curFovR, fovColor, 128, 1.2)
                end
            end
        else
            curFovX, curFovY, curFovR = nil, nil, nil
        end
    end
end

local espBonePairs = {
    {8, 31}, {31, 3},
    {31, 22}, {22, 23}, {23, 24},
    {31, 32}, {32, 33}, {33, 34},
    {3, 41}, {41, 42}, {42, 43},
    {3, 51}, {51, 52}, {52, 53}
}

function RenderEspNametag(playerId, ped)
    if not espName.v or not espFont then return end
    local px, py, pz = getCharCoordinates(ped)
    local okScreen, screenX, screenY = pcall(convertWorldPosToScreenPos, px, py, pz + 1.1)
    if not okScreen or not screenX or not screenY then return end
    local okName, nickname = pcall(sampGetPlayerNickname, playerId)
    if not okName or not nickname then nickname = "Player" end
    local text = string.format("%s (%d)", tostring(nickname), playerId)
    local textWidth = renderGetFontDrawTextLength(espFont, text)
    local textHeight = renderGetFontDrawHeight(espFont)
    local bgPadding = 4
    local bgX = screenX - textWidth / 2 - bgPadding
    local bgY = screenY - bgPadding
    local bgW = textWidth + bgPadding * 2
    local bgH = textHeight + bgPadding * 2
    renderDrawBox(bgX, bgY, bgW, bgH, 0xCC000000)
    renderDrawBox(bgX, bgY, bgW, 1, 0xFF333333)
    renderDrawBox(bgX, bgY + bgH - 1, bgW, 1, 0xFF333333)
    renderDrawBox(bgX, bgY, 1, bgH, 0xFF333333)
    renderDrawBox(bgX + bgW - 1, bgY, 1, bgH, 0xFF333333)
    renderFontDrawText(espFont, text, screenX - textWidth / 2 + 1, screenY + 1, 0xFF000000)
    renderFontDrawText(espFont, text, screenX - textWidth / 2, screenY, 0xFFFFFFFF)
    local health = 0
    local armor = 0
    local okHealth, pedHealth = pcall(getCharHealth, ped)
    local okArmor, pedArmor = pcall(getCharArmour, ped)
    if okHealth and tonumber(pedHealth) then
        health = math.max(0, tonumber(pedHealth) - 100)
    end
    if okArmor and tonumber(pedArmor) then
        armor = math.max(0, math.min(100, tonumber(pedArmor)))
    end
    local barWidth = 70
    local barHeight = 6
    local barX = screenX - barWidth / 2
    local barY = screenY + textHeight + 6
    local barGap = 8
    renderDrawBox(barX - 1, barY - 1, barWidth + 2, barHeight + 2, 0xFF000000)
    renderDrawBox(barX, barY, barWidth, barHeight, 0xFF333333)
    if health > 0 then
        local healthWidth = math.min(barWidth, math.floor(barWidth * health / 100))
        renderDrawBox(barX, barY, healthWidth, barHeight, 0xFF00CC00)
    end
    local hpText = string.format("%d HP", health)
    local hpTextW = renderGetFontDrawTextLength(espFont, hpText)
    renderFontDrawText(espFont, hpText, barX + (barWidth - hpTextW) / 2, barY - 14, 0xFF00CC00)
    local armorY = barY + barHeight + barGap
    renderDrawBox(barX - 1, armorY - 1, barWidth + 2, barHeight + 2, 0xFF000000)
    renderDrawBox(barX, armorY, barWidth, barHeight, 0xFF333333)
    if armor > 0 then
        local armorWidth = math.floor(barWidth * armor / 100)
        renderDrawBox(barX, armorY, armorWidth, barHeight, 0xFF0099FF)
    end
    local apText = string.format("%d AP", armor)
    local apTextW = renderGetFontDrawTextLength(espFont, apText)
    renderFontDrawText(espFont, apText, barX + (barWidth - apTextW) / 2, armorY - 14, 0xFF0099FF)
    local myX, myY, myZ = getCharCoordinates(PLAYER_PED)
    local dist = getDistanceBetweenCoords3d(myX, myY, myZ, px, py, pz)
    local distText = string.format("%.0fm", dist)
    local distTextW = renderGetFontDrawTextLength(espFont, distText)
    renderFontDrawText(espFont, distText, screenX - distTextW / 2, armorY + barHeight + 4, 0xFFAAAAAA)
end

function EspThread()
    while true do
        wait(0)
        if not espEnabled.v then
            if whNameTag then
                whNameTagOFF()
            end
            goto continue end
        if not isSampAvailable then goto continue end
        if (sampGetGamestate() == 1 or sampGetGamestate() == 5) and whNameTag then
            whExitStatus = true
        end
        if whExitStatus and sampGetGamestate() == 2 then
            whNameTagON()
            whExitStatus = false
        end
        local okMax, maxPlayerId = pcall(sampGetMaxPlayerId, true)
        if not okMax or type(maxPlayerId) ~= "number" then
            goto continue
        end
        local sx, sy = GetLineStart(linePos.v)
        for i = 0, maxPlayerId do
            local okConnected, connected = pcall(sampIsPlayerConnected, i)
            if okConnected and connected then
                local okPed, ok, ped = pcall(sampGetCharHandleBySampPlayerId, i)
                if okPed and ok and ped and doesCharExist(ped)
                    and not isCharDead(ped)
                    and isCharOnScreen(ped) then
                    local cL = ColorToARGB(colEspLine, 255)
                    local cB = ColorToARGB(colEspBox, 255)
                    local cN = ColorToARGB(colBone, 255)
                    local hx, hy, hz = GetBodyPartCoordinates(8, ped)
                    local fx, fy, fz = GetBodyPartCoordinates(52, ped)
                    local hsx, hsy = convert3DCoordsToScreen(hx, hy, hz + 0.35)
                    local fsx, fsy = convert3DCoordsToScreen(fx, fy, fz - 0.45)
                    if hsx and fsx then
                        local bh = math.abs(fsy - hsy)
                        local bw2 = bh * 0.48
                        local cx2 = (hsx + fsx) / 2
                        local ty = math.min(hsy, fsy)
                        local by = math.max(hsy, fsy)
                        local lx = cx2 - bw2 / 2
                        local ex, ey = GetBoxPoint(cx2, ty, by, dotPos.v)
                        if espLine.v then
                            renderDrawLine(sx, sy, ex, ey, lineThick, cL)
                            renderDrawPolygon(ex, ey, dotRadius, dotRadius, 16, 0, cL)
                        end
                        if espBox.v then
                            DrawCornerBox(lx, ty, bw2, by - ty, cB, boxThick)
                        end
                    end
                    RenderEspNametag(i, ped)
                    if espBone.v then
                        for _, pair in ipairs(espBonePairs) do
                            local x1, y1, z1 = GetBodyPartCoordinates(pair[1], ped)
                            local x2, y2, z2 = GetBodyPartCoordinates(pair[2], ped)
                            local s1x, s1y = convert3DCoordsToScreen(x1, y1, z1)
                            local s2x, s2y = convert3DCoordsToScreen(x2, y2, z2)
                            if s1x and s2x then
                                renderDrawLine(s1x, s1y, s2x, s2y, boneThick, cN)
                            end
                        end
                    end
                end
            end
        end
        ::continue::
    end
end

local patch_cameraRestore1 = nil
local patch_cameraRestore2 = nil
local patch_cameraRestore3 = nil
local patch_cameraRestore4 = nil
local patch_cameraRestore5 = nil
local patch_showCrosshairInstantly = nil
local patch_noRecoilDynamicCrosshair = nil

cameraRestorePatch = function(enable)
    if enable then
        if not patch_cameraRestore1 then
            patch_cameraRestore1 = memory.read(5310892, 1, true)
            patch_cameraRestore2 = memory.read(5310917, 1, true)
            patch_cameraRestore3 = memory.read(5386662, 1, true)
            patch_cameraRestore4 = memory.read(5386797, 1, true)
            patch_cameraRestore5 = memory.read(5387194, 1, true)
        end
        memory.write(5310892, 235, 1, true)
        memory.write(5310917, 235, 1, true)
        memory.write(5386662, 235, 1, true)
        memory.write(5386797, 235, 1, true)
        memory.write(5387194, 235, 1, true)
    elseif patch_cameraRestore1 ~= nil then
        memory.write(5310892, patch_cameraRestore1, 1, true)
        memory.write(5310917, patch_cameraRestore2, 1, true)
        memory.write(5386662, patch_cameraRestore3, 1, true)
        memory.write(5386797, patch_cameraRestore4, 1, true)
        memory.write(5387194, patch_cameraRestore5, 1, true)
        patch_cameraRestore1 = nil
        patch_cameraRestore2 = nil
        patch_cameraRestore3 = nil
        patch_cameraRestore4 = nil
        patch_cameraRestore5 = nil
    end
end

showCrosshairInstantlyPatch = function(enable)
    if enable then
        if not patch_showCrosshairInstantly then
            patch_showCrosshairInstantly = memory.read(5824985, 1, true)
        end
        memory.write(5824985, 235, 1, true)
    elseif patch_showCrosshairInstantly ~= nil then
        memory.write(5824985, patch_showCrosshairInstantly, 1, true)
        patch_showCrosshairInstantly = nil
    end
end

noRecoilDynamicCrosshair = function(enable)
    if enable then
        if not patch_noRecoilDynamicCrosshair then
            patch_noRecoilDynamicCrosshair = memory.read(7603296, 1, true)
        end
        memory.write(7603296, 144, 1, true)
    elseif patch_noRecoilDynamicCrosshair ~= nil then
        memory.write(7603296, patch_noRecoilDynamicCrosshair, 1, true)
        patch_noRecoilDynamicCrosshair = nil
    end
end

function IsCbugWeapon()
    local ok, weapon = pcall(getCurrentCharWeapon, PLAYER_PED)
    return ok and weapon == 24
end

function CbugIsReady()
    return cbugEnabled.v
    and isSampAvailable
    and not isCharDead(PLAYER_PED)
    and IsCbugWeapon()
end

function UpdateCbugPatches()
    if not cbugEnabled.v or not isSampAvailable or isCharDead(PLAYER_PED) then
        cameraRestorePatch(false)
        noRecoilDynamicCrosshair(false)
        showCrosshairInstantlyPatch(false)
        return
    end
    if cbugShowCrosshair.v then
        showCrosshairInstantlyPatch(true)
    else
        showCrosshairInstantlyPatch(false)
    end
    local weaponReady = IsCbugWeapon()
    if weaponReady and cbugNoCamRestore.v then
        cameraRestorePatch(true)
    else
        cameraRestorePatch(false)
    end
    if weaponReady and cbugNoRecoil.v then
        noRecoilDynamicCrosshair(true)
    else
        noRecoilDynamicCrosshair(false)
    end
end

function CbugThread()
    while true do
        wait(0)
        if not isSampAvailable then
            cameraRestorePatch(false)
            noRecoilDynamicCrosshair(false)
            goto continue
        end
        UpdateCbugPatches()
        if not CbugIsReady() then
            goto continue
        end
        if isKeyDown(vkeys.VK_RBUTTON) and wasKeyPressed(cbugSecondaryKey) then
            wait(0)
            setCharAnimSpeed(PLAYER_PED, "python_fire", 1.337)
            setGameKeyState(17, 255)
            wait(55)
            setGameKeyState(6, 0)
            setGameKeyState(18, 255)
            setCharAnimSpeed(PLAYER_PED, "python_fire", 1)
        end
        ::continue::
    end
end

local weaponRecoilSpread = nil
local weaponRecoilSettings = nil
local weaponRecoilGameGetWeaponInfo = nil
local weaponRecoilBullets = 0
local weaponRecoilProjectiles = 0
function LoadWeaponRecoilSettings()
    local path = getWorkingDirectory() .. "/samp_project_weapon.ini"
    local ok, result = pcall(inicfg.load, nil, path)
    if ok and result then
        weaponRecoilSettings = result
    else
        weaponRecoilSettings = nil
    end
end

function WeaponRecoilNumber(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

function WeaponRecoilGetValue(section, key, fallback)
    if not weaponRecoilSettings or not weaponRecoilSettings[section] then
        return fallback
    end
    return WeaponRecoilNumber(weaponRecoilSettings[section][key], fallback)
end

function WeaponRecoilGetWeaponValue(weapon, key)
    if weaponRecoilSettings and weaponRecoilSettings[weapon] then
        return WeaponRecoilNumber(weaponRecoilSettings[weapon][key], nil)
    end
    return nil
end

function WeaponRecoilIsAiming()
    local camid = readMemory(11989416, 2, false)
    if camid == 5 or camid == 53 or camid == 55 or camid == 65 then return true end
    if camid == 7 or camid == 8 or camid == 16 or camid == 34
        or camid == 39 or camid == 40 or camid == 41 or camid == 42
        or camid == 45 or camid == 46 or camid == 51 or camid == 52 then
        return true
    end
    return false
end

function WeaponRecoilCounterRotate(lr, ud)
    if lr ~= 0 then
        memory.setfloat(0xB6F258, memory.getfloat(0xB6F258) - lr)
    end
    if ud ~= 0 then
        memory.setfloat(0xB6F248, memory.getfloat(0xB6F248) + ud)
    end
end

function WeaponRecoilThread()
    math.randomseed(os.time() - os.clock() * 1000)
    pcall(function()
        weaponRecoilGameGetWeaponInfo =
            ffi.cast('struct CWeaponInfo* (__cdecl*)(int, int)', 0x743C60)
    end)
    weaponRecoilSpread = memory.getfloat(0x8D2E64)
    weaponRecoilBullets = getIntStat(126)
    weaponRecoilProjectiles = getIntStat(127)
    LoadWeaponRecoilSettings()
    while true do
        wait(0)
        if not noRecoilEnabled.v then
            if weaponRecoilSpread ~= nil
                and memory.getfloat(0x8D2E64) ~= weaponRecoilSpread then
                memory.setfloat(0x8D2E64, weaponRecoilSpread)
            end
            goto continue
        end
        local disableSpread = true
        if weaponRecoilSettings and weaponRecoilSettings.Switches then
            disableSpread = weaponRecoilSettings.Switches.bDisableCrosshairSpread == true
        end
        if disableSpread and memory.getfloat(0x8D2E64) ~= 0 then
            memory.setfloat(0x8D2E64, 0)
        elseif not disableSpread and weaponRecoilSpread ~= nil
            and memory.getfloat(0x8D2E64) ~= weaponRecoilSpread then
            memory.setfloat(0x8D2E64, weaponRecoilSpread)
        end
        if not isPlayerPlaying(PLAYER_HANDLE) then goto continue end
        local bulletsNow = getIntStat(126)
        local projectilesNow = getIntStat(127)
        if weaponRecoilBullets == bulletsNow and weaponRecoilProjectiles == projectilesNow then
            goto continue
        end
        weaponRecoilBullets = bulletsNow
        weaponRecoilProjectiles = projectilesNow
        local okPlayer, player = pcall(function()
            return select(2, getPlayerChar(PLAYER_HANDLE))
        end)
        if not okPlayer or not player or not doesCharExist(player) then goto continue end
        if isCharDead(player) then goto continue end
        if not WeaponRecoilIsAiming() then goto continue end
        local plwp = getCurrentCharWeapon(player)
        if not plwp or plwp <= 0 then goto continue end
        if not weaponRecoilGameGetWeaponInfo then goto continue end
        local okInfo, weapinfo = pcall(function()
            return weaponRecoilGameGetWeaponInfo(
                plwp,
                callMethod(0x5E6580, getCharPointer(player), 0, 0)
            )
        end)
        if not okInfo or not weapinfo then goto continue end
        local weapsett = weaponRecoilSettings and weaponRecoilSettings[plwp]
        local recoil = WeaponRecoilGetWeaponValue(plwp, "nRecoil")
        if recoil == nil then
            recoil = WeaponRecoilGetValue("Global_Settings", "nGlobalRecoil", 0)
        end
        if recoil == 0 then
            recoil = weapinfo.m_wDamage / 50
        elseif recoil == "A" then
            recoil = weapinfo.m_wDamage / 50
        end
        if recoil and recoil > 0 then
            local shotgunMultiplier =
                WeaponRecoilGetValue("Other_Settings", "nShotgunRecoilMultiplier", 1)
            local heavyMultiplier =
                WeaponRecoilGetValue("Other_Settings", "nHeavyWeaponsRecoilMultiplier", 1)

            if weaponRecoilSettings and weaponRecoilSettings.Other_Settings then
                local shotgunGroups = tostring(
                    weaponRecoilSettings.Other_Settings.tnShotgunAnimGroups or ""
                )
                for animgrp in shotgunGroups:gmatch("%-?%d+") do
                    if tonumber(animgrp) == weapinfo.m_dwAnimGroup then
                        recoil = recoil * shotgunMultiplier
                        break
                    end
                end
                local heavyGroups = tostring(
                    weaponRecoilSettings.Other_Settings.tnHeavyWeaponsAnimGroups or ""
                )
                for animgrp in heavyGroups:gmatch("%-?%d+") do
                    if tonumber(animgrp) == weapinfo.m_dwAnimGroup then
                        recoil = recoil * heavyMultiplier
                        break
                    end
                end
            end
            local accuracy = -(weapinfo.m_fAccuracy - 2.5)
            if accuracy < 0.5 then accuracy = 0.5 end
            local fireOffset = weapinfo.m_vFireOffset.x
            if math.abs(fireOffset) < 0.0001 then
                fireOffset = 1
            end
            local length = 1 / fireOffset
            recoil = recoil * length * accuracy
            if weapinfo.m_bTwinPistol == 1 then
                recoil = recoil * WeaponRecoilGetValue(
                    "Other_Settings",
                    "nDualWieldRecoilMultiplier",
                    1
                )
            end
            local multiplier = WeaponRecoilGetValue(
                "Other_Settings",
                "nGlobalRecoilMultiplier",
                100
            )
            if multiplier <= 0 then multiplier = 100 end
            local decmul = 1
            if isCharDucking(player) then
                decmul = decmul * WeaponRecoilGetValue(
                    "Other_Settings",
                    "nCrouchRecoilAndCamShakeMultiplier",
                    1
                )
            elseif getCharSpeed(player) == 0 then
                decmul = decmul * WeaponRecoilGetValue(
                    "Other_Settings",
                    "nNotMovingRecoilAndCamShakeMultiplier",
                    1
                )
            end
            if decmul <= 0 then decmul = 1 end
            recoil = recoil / 100 * multiplier * decmul
            if recoil > 0 then
                local percent = 100
                if weaponRecoilSettings and weaponRecoilSettings.Switches
                    and weaponRecoilSettings.Switches.bDisableDownwardsRecoil == true then
                    percent = -50
                end
                local angle = (math.random(percent, 0) / 100) * math.pi * 2
                local mulx = math.cos(angle)
                local muly = math.sin(angle)
                WeaponRecoilCounterRotate(recoil * mulx, recoil * muly)
            end
        end
        ::continue::
    end
end

function RapidFireThread()
    while true do
        wait(0)
        if rapidFireEnabled.v and isSampAvailable and not isCharDead(PLAYER_PED) then
            local weapon = getCurrentCharWeapon(PLAYER_PED)
            if weapon > 0 then
                local speed = math.min(1.2, math.max(0.1, rapidFireSpeed.v or 1.2))
                setCharAnimSpeed(PLAYER_PED, "python_fire", speed)
                setCharAnimSpeed(PLAYER_PED, "colt45_fire", speed)
                setCharAnimSpeed(PLAYER_PED, "silenced_fire", speed)
                setCharAnimSpeed(PLAYER_PED, "shotgun_fire", speed)
                setCharAnimSpeed(PLAYER_PED, "rifle_fire", speed)
            end
        end
    end
end

local clickWarpCursor = false

function ClickWarpShowCursor(enable)
    if enable then
        pcall(sampSetCursorMode, 3)
        clickWarpCursor = true
    else
        pcall(sampToggleCursor, false)
        pcall(sampSetCursorMode, 0)
        clickWarpCursor = false
    end
end

function ClickWarpThread()
    while true do
        wait(0)
        if not clickWarpEnabled.v or not isSampAvailable or isCharDead(PLAYER_PED) or menuOpen.v then
            if clickWarpCursor then
                ClickWarpShowCursor(false)
            end
            goto continue
        end
        if isPauseMenuActive() then
            if clickWarpCursor then
                ClickWarpShowCursor(false)
            end
            goto continue
        end
        if wasKeyPressed(vkeys.VK_MBUTTON) then
            ClickWarpShowCursor(not clickWarpCursor)
            if clickWarpCursor then
                printStringNow("~g~Click Warp: ~w~move the cursor, ~y~Left Click~w~ to teleport", 2500)
            end
        end
        if clickWarpCursor then
            local mode = sampGetCursorMode()
            if mode == 0 then
                pcall(sampSetCursorMode, 3)
            end
            local sx, sy = getCursorPos()
            local sw, sh = getScreenResolution()
            if sx >= 0 and sy >= 0 and sx < sw and sy < sh then
                local posX, posY, posZ = convertScreenCoordsToWorld3D(sx, sy, 700.0)
                local camX, camY, camZ = getActiveCameraCoordinates()
                local result, colpoint = processLineOfSight(
                    camX, camY, camZ, posX, posY, posZ,
                    true, true, false, true, false, false, false, false
                )
                if result and colpoint and colpoint.pos and colpoint.pos[1] ~= 0 then
                    local tx, ty, tz = colpoint.pos[1], colpoint.pos[2], colpoint.pos[3]
                    local msx, msy = convert3DCoordsToScreen(tx, ty, tz)
                    if msx then
                        renderDrawBox(msx - 4, msy - 4, 8, 8, 0xAA00FF00)
                    end
                    if wasKeyPressed(vkeys.VK_LBUTTON) then
                        setCharCoordinates(PLAYER_PED, tx, ty, tz)
                        printStringNow("~g~Teleported!", 1000)
                        ClickWarpShowCursor(false)
                    end
                end
            end
        end
        ::continue::
    end
end

local maxDamagePatch = nil
function MaxDamageThread()
    while true do
        wait(0)
        if maxDamageEnabled.v and isSampAvailable and not isCharDead(PLAYER_PED) then
            local weapon = getCurrentCharWeapon(PLAYER_PED)
            if weapon == 25 or weapon == 26 or weapon == 27 then
                if maxDamagePatch == nil then
                    maxDamagePatch = memory.read(7634870, 1, true)
                end
                memory.write(7634870, 144, 1, true)
            end
        else
            if maxDamagePatch ~= nil then
                memory.write(7634870, maxDamagePatch, 1, true)
                maxDamagePatch = nil
            end
        end
    end
end

local spawnGunIsSpawning = false

function SpawnGunSendSpectatorPosition(x, y, z)
    local mem = allocateMemory(18)
    if not mem then return end
    setStructElement(mem, 4, 2, 0, true)
    setStructFloatElement(mem, 6, x, true)
    setStructFloatElement(mem, 10, y, true)
    setStructFloatElement(mem, 14, z, true)
    sampSendSpectatorData(mem)
    freeMemory(mem)
end

events.onReceiveRpc = function(rpcId, bitStream)
    if rpcId == 153 and skinChangerLockEnabled and skinChangerLockedModel ~= nil then
        local okPlayer, playerId = pcall(raknetBitStreamReadInt32, bitStream)
        local okSkin, skinId = pcall(raknetBitStreamReadInt32, bitStream)
        local okLocal, localPlayerId = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)

        if okPlayer and okSkin and okLocal and localPlayerId ~= nil and playerId == localPlayerId then
            local targetSkin = tonumber(skinId)
            local lockedSkin = tonumber(skinChangerLockedModel)
            if targetSkin ~= nil and lockedSkin ~= nil and targetSkin ~= lockedSkin then
                return false
            end
        end
    end

    if not spawnGunIsSpawning or not spawnGunBypassEnabled.v then return end
    if rpcId == 14 then
        local ok, value = pcall(raknetBitStreamReadFloat, bitStream)
        if ok and math.floor(value or 1) == 0 then
            return false
        end
    end
    if rpcId == 15 or rpcId == 86 or rpcId == 87 then
        return false
    end
    if rpcId == 156 then
        SpawnGunSendSpectatorPosition(0, 0, 0)
        pcall(sampSendDeathByPlayer, 65535, 49)
        SpawnGunSendSpectatorPosition(0, 0, 0)
        pcall(sampSpawnPlayer)
        lua_thread.create(function()
            pcall(sampRequestClass, 1)
            wait(1500)
            spawnGunIsSpawning = false
        end)
        pcall(raknetEmulRpcReceiveBitStream, rpcId, bitStream)
        return false
    end
end

events.onSendPacket = function(packetId, bitStream)
    if spawnGunBypassEnabled.v and spawnGunIsSpawning
        and (packetId == 207 or packetId == 212) then
        return false
    end
end

events.onSendRpc = function(rpcId, bitStream)
    if not spawnGunBypassEnabled.v then return end
    if rpcId == 25 then
        spawnGunIsSpawning = true
    elseif rpcId == 52 and spawnGunIsSpawning then
        return false
    end
end

events.onSendPlayerSync = function(data)
    if spawnGunBypassEnabled.v then
        local interior = getActiveInterior()
        pcall(sampSendInteriorChange, interior + 1)
        pcall(sampSendInteriorChange, interior)
    end
end

events.onRequestSpawnResponse = function(arg)
    whHandleRespawn()
end

function main()
    while not isSampLoaded() and not isSampfuncsLoaded() do wait(100) end
    while not isSampAvailable() do wait(100) end
    LoadAutoConfig()
    if not skinChangerOriginalModel or skinChangerOriginalModel == 0 then
        skinChangerOriginalModel = GetCurrentSkinModel()
    end
    if espEnabled.v and espName.v then
        lua_thread.create(function()
            wait(1000)
            whNameTagON()
        end)
    end
    activeTab = 1
    UpdateMenuCommandRegistration()
    espFont = renderCreateFont("Arial", 10, 5) or renderCreateFont("ProggyClean", 10, 5)
    EnsureMusicDir()
    ScanMusicFiles()
    lua_thread.create(EspThread)
    lua_thread.create(FovThread)
    lua_thread.create(aimbot.SmoothAimbotThread)
    lua_thread.create(CbugThread)
    lua_thread.create(WeaponRecoilThread)
    lua_thread.create(RapidFireThread)
    lua_thread.create(ClickWarpThread)
    lua_thread.create(MaxDamageThread)
    lua_thread.create(SkinChangerLockThread)
    while true do
        wait(0)
        local ok, err = pcall(AutoSaveConfigIfChanged)
        if not ok then
        end
        MusicUpdateState()
        local chatActive = false
        pcall(function()
            chatActive = sampIsChatInputActive()
        end)
        if waitingCbugKey and not chatActive then
            for k = 1, 255 do
                if wasKeyPressed(k) and k > 4 then
                    cbugSecondaryKey = k
                    cbugSecondaryKeyName = getKeyName(k)
                    waitingCbugKey = false
                    break
                end
            end
        end
        if waitingMenuKey and not chatActive then
            for k = 1, 255 do
                if wasKeyPressed(k) and k > 4 then
                    menuKey = k
                    menuKeyName = getKeyName(k)
                    waitingMenuKey = false
                    break
                end
            end
        end
        if waitingMenuModKey and not chatActive then
            for k = 1, 255 do
                if wasKeyPressed(k) and k > 4 then
                    menuModKey = k
                    menuModKeyName = getKeyName(k)
                    waitingMenuModKey = false
                    break
                end
            end
        end
        aimbot.HandleKeys()
        for i = 1, #waitingAutoRPKey do
            if waitingAutoRPKey[i] and not chatActive then
                for k = 1, 255 do
                    if wasKeyPressed(k) and k > 4 then
                        autoRPKeys[i] = k
                        autoRPKeyNames[i] = getKeyName(k)
                        waitingAutoRPKey[i] = false
                        break
                    end
                end
            end
        end
        if menuUseKeybind.v and not chatActive then
            local trigger = false
            if menuModKey > 0 then
                if isKeyDown(menuModKey) and wasKeyPressed(menuKey) then
                    trigger = true
                end
            else
                if wasKeyPressed(menuKey) then
                    trigger = true
                end
            end
            if trigger then
                menuOpen.v = not menuOpen.v
            end
        end
        imgui.Process = menuOpen.v
        imgui.ShowCursor = menuOpen.v
        SP_cbugEnabled = cbugEnabled
        SP_cbugSecondaryKey = cbugSecondaryKey
        if isSampAvailable and not menuOpen.v and not chatActive then
            for i = 1, #autoRPCommands do
                local command = tostring(autoRPCommands[i].v or ""):match("^%s*(.-)%s*$")
                if command ~= "" and autoRPKeys[i] > 0 and wasKeyPressed(autoRPKeys[i]) then
                    sampSendChat(command)
                    break
                end
            end
        end

    end
end

function onExitScript()
    spawnGunIsSpawning = false
    cameraRestorePatch(false)
    showCrosshairInstantlyPatch(false)
    noRecoilDynamicCrosshair(false)
    MusicStop(true)
    if weaponRecoilSpread ~= nil then
        pcall(function()
            memory.setfloat(0x8D2E64, weaponRecoilSpread)
        end)
    end
    if maxDamagePatch ~= nil then
        pcall(function()
            memory.write(7634870, maxDamagePatch, 1, true)
        end)
    end
end
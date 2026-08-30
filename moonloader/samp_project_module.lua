local imgui = require('imgui')
local vkeys = require('vkeys')
local ffi = require('ffi')
local memory = require('memory')
local M = {}

if type(GetBodyPartCoordinates) ~= 'function' then
    local GetBonePosition = ffi.cast("int (__thiscall*)(void*, float*, int, bool)", 6177408)
    function GetBodyPartCoordinates(boneId, ped)
        if not doesCharExist(ped) then return 0, 0, 0 end
        local pedPointer = getCharPointer(ped)
        local coords = ffi.new("float[3]")
        GetBonePosition(ffi.cast("void*", pedPointer), coords, boneId, true)
        return coords[0], coords[1], coords[2]
    end
end

local ab = {
    enable          = imgui.ImBool(false),
    showFov         = imgui.ImBool(false),
    vis             = imgui.ImBool(false),
    partList        = {'Nearest','Head','Neck','Body','Left Up Arm','Right Up Arm','Left Center Arm','Right Center Arm','Left Leg','Right Leg'},
    partSel         = imgui.ImInt(0),
    boneMap         = {8, 31, 3, 22, 32, 23, 33, 42, 52},
    smooth          = imgui.ImInt(3),
    radius          = imgui.ImInt(3),
    dist            = imgui.ImInt(1000),
    rifleSmooth     = imgui.ImInt(3),
    rifleRadius     = imgui.ImInt(3),
    rifleDist       = imgui.ImInt(1000),
    countrySmooth   = imgui.ImInt(3),
    countryRadius   = imgui.ImInt(3),
    countryDist     = imgui.ImInt(1000),
    sniperSmooth    = imgui.ImInt(3),
    sniperRadius    = imgui.ImInt(3),
    sniperDist      = imgui.ImInt(1000),
    clist           = imgui.ImBool(false),
    stuned          = imgui.ImBool(false),
    pause           = imgui.ImBool(false),
    toggleKey       = 82,
    waitingKey      = false,
    smoothWpn       = {[22]=true,[23]=true,[24]=true,[25]=true,[26]=true,[27]=true,[28]=true,[29]=true,[30]=true,[31]=true,[32]=true,[33]=true,[34]=true,[38]=true},
    rifleWpn        = {[30]=true,[31]=true},
    countryRifleWpn = {[33]=true},
    sniperWpn       = {[34]=true},
    stunAnims       = {
        'DAM_armL_frmBK','DAM_armL_frmFT','DAM_armL_frmLT',
        'DAM_armR_frmBK','DAM_armR_frmFT','DAM_armR_frmRT',
        'DAM_LegL_frmBK','DAM_LegL_frmFT','DAM_LegL_frmLT',
        'DAM_LegR_frmBK','DAM_LegR_frmFT','DAM_LegR_frmRT',
        'DAM_stomach_frmBK','DAM_stomach_frmFT','DAM_stomach_frmLT','DAM_stomach_frmRT'
    },
    getBoneFn       = ffi.cast("int (__thiscall*)(void*, float*, int, bool)", 0x5E4280),
}

M.ab = ab

function GetCurrentWpnParams(wpn)
    if ab.rifleWpn[wpn] then
        return ab.rifleSmooth.v, ab.rifleRadius.v, ab.rifleDist.v
    elseif ab.countryRifleWpn[wpn] then
        return ab.countrySmooth.v, ab.countryRadius.v, ab.countryDist.v
    elseif ab.sniperWpn[wpn] then
        return ab.sniperSmooth.v, ab.sniperRadius.v, ab.sniperDist.v
    else
        return ab.smooth.v, ab.radius.v, ab.dist.v
    end
end

function IsSmoothWeapon()
    return ab.smoothWpn[getCurrentCharWeapon(PLAYER_PED)] == true
end

function IsRifleWeapon()
    return ab.rifleWpn[getCurrentCharWeapon(PLAYER_PED)] == true
end

function IsCountryRifleWeapon()
    return ab.countryRifleWpn[getCurrentCharWeapon(PLAYER_PED)] == true
end

function IsSniperWeapon()
    return ab.sniperWpn[getCurrentCharWeapon(PLAYER_PED)] == true
end

function fix(angle)
    if angle > math.pi then
        angle = angle - math.pi * 2
    elseif angle < -math.pi then
        angle = angle + math.pi * 2
    end
    return angle
end

function GetBodyPartCoordinatesSmooth(id, handle)
    if doesCharExist(handle) then
        local pedptr = getCharPointer(handle)
        local vec = ffi.new("float[3]")
        ab.getBoneFn(ffi.cast("void*", pedptr), vec, id, true)
        return vec[0], vec[1], vec[2]
    end
    return 0, 0, 0
end

function CheckStuned()
    for k, v in pairs(ab.stunAnims) do
        if isCharPlayingAnim(PLAYER_PED, v) then return false end
    end
    return true
end

function GetNearestBoneSmooth(handle)
    local maxDist = 20000
    local nearestBone = -1
    local bones = {8, 31, 3, 22, 32, 23, 33, 42, 52}
    local wpn = getCurrentCharWeapon(PLAYER_PED)
    local sw, sh = getScreenResolution()
    local crosshairPos
    if ab.sniperWpn[wpn] then
        crosshairPos = {sw * 0.5, sh * 0.5}
    else
        local cx, cy = convertGameScreenCoordsToWindowScreenCoords(339.1, 179.1)
        crosshairPos = {cx or (sw * 0.5298), cy or (sh * 0.3997)}
    end
    for n = 1, #bones do
        local bonePos = {GetBodyPartCoordinatesSmooth(bones[n], handle)}
        local enPos = {convert3DCoordsToScreen(bonePos[1], bonePos[2], bonePos[3])}
        if enPos[1] and enPos[2] then
            local distance = math.sqrt((enPos[1] - crosshairPos[1])^2 + (enPos[2] - crosshairPos[2])^2)
            if distance < maxDist then
                nearestBone = bones[n]
                maxDist = distance
            end
        end
    end
    return nearestBone ~= -1 and nearestBone or 8
end

function GetTargetBoneSmooth(handle)
    local sel = ab.partSel.v
    if sel == 0 then
        return GetNearestBoneSmooth(handle)
    else
        return ab.boneMap[sel] or 8
    end
end

local RIFLE_CALIBRATION = {
    noScopeX = 0.04253,
    zoomScopeX = 0.029,
    zoomElevationFactor = 0.67,
}

local COUNTRY_RIFLE_CALIBRATION = {
    noScopeX = 0.04253,
    zoomScopeX = 0.020,
    zoomElevationFactor = 0.46,
}

local SNIPER_RIFLE_CALIBRATION = {
    noScopeX = 0.000,
    zoomScopeX = 0.000,
    noScopeElevation = 0.000,
    zoomElevation = 0.000,
}

function GetAimOffsets(wpn, isAiming)
    local baseCoeffZ = isWidescreenOnInOptions() and 0.0778 or 0.103
    if ab.rifleWpn[wpn] then
        local offsetX = isAiming and RIFLE_CALIBRATION.zoomScopeX or RIFLE_CALIBRATION.noScopeX
        local coeffZ = isAiming and (baseCoeffZ * RIFLE_CALIBRATION.zoomElevationFactor) or baseCoeffZ
        return offsetX, coeffZ
    elseif ab.countryRifleWpn[wpn] then
        local offsetX = isAiming and COUNTRY_RIFLE_CALIBRATION.zoomScopeX or COUNTRY_RIFLE_CALIBRATION.noScopeX
        local coeffZ = isAiming and (baseCoeffZ * COUNTRY_RIFLE_CALIBRATION.zoomElevationFactor) or baseCoeffZ
        return offsetX, coeffZ
    elseif ab.sniperWpn[wpn] then
        local offsetX = isAiming and SNIPER_RIFLE_CALIBRATION.zoomScopeX or SNIPER_RIFLE_CALIBRATION.noScopeX
        local coeffZ = isAiming and SNIPER_RIFLE_CALIBRATION.zoomElevation or SNIPER_RIFLE_CALIBRATION.noScopeElevation
        return offsetX, coeffZ
    else
        local offsetX = 0.04253
        local coeffZ = baseCoeffZ
        return offsetX, coeffZ
    end
end

function GetNearestPedSmooth(fov, maxDistVal)
    local maxDistance = maxDistVal or ab.dist.v
    local bestScreenDist = fov
    local nearestPED = -1
    local wpn = getCurrentCharWeapon(PLAYER_PED)
    local isScopeWpn = ab.rifleWpn[wpn] or ab.countryRifleWpn[wpn] or ab.sniperWpn[wpn]
    local isAiming = isScopeWpn and (isKeyDown(vkeys.VK_RBUTTON) or (type(getCharPlayerAiming) == 'function' and getCharPlayerAiming(PLAYER_PED)))
    local offsetX, coeffZ = GetAimOffsets(wpn, isAiming)
    for i = 0, sampGetMaxPlayerId(true) do
        if sampIsPlayerConnected(i) then
            local find, handle = sampGetCharHandleBySampPlayerId(i)
            if find and isCharOnScreen(handle) and not isCharDead(handle) then
                local enPos = {GetBodyPartCoordinatesSmooth(GetTargetBoneSmooth(handle), handle)}
                local myCharPos = {getCharCoordinates(PLAYER_PED)}
                local dist3d = math.sqrt((enPos[1]-myCharPos[1])^2 + (enPos[2]-myCharPos[2])^2 + (enPos[3]-myCharPos[3])^2)
                if dist3d <= maxDistance then
                    local myPos = {getActiveCameraCoordinates()}
                    local vector = {myPos[1]-enPos[1], myPos[2]-enPos[2], myPos[3]-enPos[3]}
                    local angle = {
                        math.atan2(vector[2], vector[1]) + offsetX,
                        math.atan2(math.sqrt(vector[1]^2 + vector[2]^2), vector[3]) - math.pi/2 - coeffZ
                    }
                    local view = {
                        fix(representIntAsFloat(readMemory(0xB6F258, 4, false))),
                        fix(representIntAsFloat(readMemory(0xB6F248, 4, false)))
                    }
                    local screenDist = math.sqrt((angle[1]-view[1])^2 + (angle[2]-view[2])^2) * 57.2957795131
                    if screenDist <= bestScreenDist then
                        nearestPED = handle
                        bestScreenDist = screenDist
                    end
                end
            end
        end
    end
    return nearestPED
end

function SmoothAimbotThread()
    while true do
        wait(0)
        if not ab.enable.v then goto smoothContinue end
        if not isSampAvailable or isCharDead(PLAYER_PED) then goto smoothContinue end
        local wpn = getCurrentCharWeapon(PLAYER_PED)
        if wpn == 0 then goto smoothContinue end
        local curSmooth, curRadius, curDist = GetCurrentWpnParams(wpn)
        local isScopeWpn = ab.rifleWpn[wpn] or ab.countryRifleWpn[wpn] or ab.sniperWpn[wpn]
        local isAiming = isScopeWpn and (isKeyDown(vkeys.VK_RBUTTON) or (type(getCharPlayerAiming) == 'function' and getCharPlayerAiming(PLAYER_PED)))
        local normalAim = IsSmoothWeapon() and isKeyDown(vkeys.VK_LBUTTON)
        local cbugOn = rawget(_G, 'SP_cbugEnabled')
        local cbugKey = rawget(_G, 'SP_cbugSecondaryKey') or 18
        local cbugAim = cbugOn and cbugOn.v
            and getCurrentCharWeapon(PLAYER_PED) == 24
            and isKeyDown(vkeys.VK_RBUTTON)
            and isKeyDown(cbugKey)
        if not normalAim and not cbugAim then goto smoothContinue end
        local handle = GetNearestPedSmooth(curRadius, curDist)
        if handle ~= -1 then
            local _, myID = sampGetPlayerIdByCharHandle(PLAYER_PED)
            local result, playerID = sampGetPlayerIdByCharHandle(handle)
            if result then
                if ab.stuned.v and not CheckStuned() then goto smoothContinue end
                if ab.clist.v and sampGetPlayerColor(myID) == sampGetPlayerColor(playerID) then goto smoothContinue end
                if ab.pause.v and sampIsPlayerPaused(playerID) then goto smoothContinue end
                local myPos = {getActiveCameraCoordinates()}
                local enPos = {GetBodyPartCoordinatesSmooth(GetTargetBoneSmooth(handle), handle)}
                local offsetX, coeffZ = GetAimOffsets(wpn, isAiming)
                local los = not ab.vis.v or isLineOfSightClear(myPos[1], myPos[2], myPos[3], enPos[1], enPos[2], enPos[3], true, true, false, true, true)
                if los then
                    local vector = {myPos[1]-enPos[1], myPos[2]-enPos[2], myPos[3]-enPos[3]}
                    local angle = {
                        math.atan2(vector[2], vector[1]) + offsetX,
                        math.atan2(math.sqrt(vector[1]^2 + vector[2]^2), vector[3]) - math.pi/2 - coeffZ
                    }
                    local view = {
                        fix(representIntAsFloat(readMemory(0xB6F258, 4, false))),
                        fix(representIntAsFloat(readMemory(0xB6F248, 4, false)))
                    }
                    local diff = {angle[1]-view[1], angle[2]-view[2]}
                    local divisor = math.max(1, curSmooth)
                    local step = {diff[1]/divisor, diff[2]/divisor}
                    setCameraPositionUnfixed(view[2]+step[2], view[1]+step[1])
                end
            end
        end
        ::smoothContinue::
    end
end

M.SmoothAimbotThread = SmoothAimbotThread
M.IsSmoothWeapon = IsSmoothWeapon
M.IsRifleWeapon = IsRifleWeapon
M.IsCountryRifleWeapon = IsCountryRifleWeapon
M.IsSniperWeapon = IsSniperWeapon
M.GetCurrentWpnParams = GetCurrentWpnParams

function M.DrawLocal(SectionLabel, SmallNote, PF, XF, fontProggy, PR, PG, PB, getKeyName)
    PF(fontProggy)
    imgui.Spacing()
    SectionLabel("AIMBOT")
    imgui.Spacing()
    imgui.PushItemWidth(-1)
    if imgui.Button(ab.waitingKey and "[ Press any key... ]" or ("[ Toggle ON/OFF: " .. getKeyName(ab.toggleKey) .. " ]"), imgui.ImVec2(-1, 26)) then
        ab.waitingKey = true
    end
    imgui.PopItemWidth()
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

function M.HandleKeys()
    if ab.waitingKey then
        for k = 1, 255 do
            if wasKeyPressed(k) and k > 4 then
                ab.toggleKey = k
                ab.waitingKey = false
                return true
            end
        end
    end
    local chatActive = false
    pcall(function()
        chatActive = sampIsChatInputActive()
    end)
    if not chatActive and wasKeyPressed(ab.toggleKey) then
        ab.enable.v = not ab.enable.v
        return true
    end
    return false
end

return M
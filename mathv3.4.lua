-- Auto Solver v3.4 (Matcha) - input injection is dead in this build, so this
-- shows the answer + key instantly and confirms CORRECT from game text.
-- No mouse/key calls, cursor stays yours. STOP: `_G.AA_Running = false`.

if _G.AA_Running then _G.AA_Running = false task.wait(0.4) end
_G.AA_Running = true

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RCF = RS:WaitForChild("RoundControlFolder")
local TC = RCF:WaitForChild("TopicControl")
local AC = RCF:WaitForChild("AnswerControl")
local SC = TC:WaitForChild("SpecialControl")
local lp = Players.LocalPlayer

local delay = 0.1
local enabled = true
local lastKey = ""
local uiStatus, uiAnswer, uiPress = "starting...", "", ""
local lastNotify = 0

local DIV_SIGN = "\195\183" -- U+00F7 -> /
local MUL_SIGN = "\195\151" -- U+00D7 -> *
local MID_DOT = "\194\183"  -- U+00B7 -> *

-- ---------- small utils ----------
local function trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
local function norm(s)
    s = tostring(s):lower()
    s = s:gsub("%s+", ""):gsub(",", ""):gsub("%$", "")
    return s
end
local function fmtNum(n)
    if math.abs(n - math.floor(n + 0.5)) < 1e-9 then return tostring(math.floor(n + 0.5)) end
    local s = string.format("%.4f", n)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end
local function parseNum(s)
    s = trim(tostring(s)):gsub(",", ""):gsub("%$", "")
    local a, b = s:match("^(-?[%d%.]+)%s*/%s*(-?[%d%.]+)$")
    if a and b and tonumber(b) ~= 0 then return tonumber(a) / tonumber(b) end
    local p = s:match("^(-?[%d%.]+)%%$")
    if p and tonumber(p) then return tonumber(p) / 100 end
    return tonumber(s)
end
local function numbersIn(s)
    local out = {}
    for n in tostring(s):gmatch("-?%d+%.?%d*") do
        if n ~= "" and n ~= "-" then out[#out + 1] = tonumber(n) end
    end
    return out
end
local SUP = { ["\226\129\176"] = "^0", ["\194\185"] = "^1", ["\194\178"] = "^2",
    ["\194\179"] = "^3", ["\226\129\180"] = "^4", ["\226\129\181"] = "^5",
    ["\226\129\182"] = "^6", ["\226\129\183"] = "^7", ["\226\129\184"] = "^8",
    ["\226\129\185"] = "^9" }
local function cleanMath(s)
    s = tostring(s)
    for k, v in pairs(SUP) do s = s:gsub(k, v) end
    s = s:gsub(MUL_SIGN, "*"):gsub(MID_DOT, "*"):gsub(DIV_SIGN, "/")
    s = s:gsub("\226\128\147", "-"):gsub("\226\128\148", "-")
    return s
end
-- verified vulgar fraction codepoints: U+00BC-BE, U+2150-215E
local VULG = { ["\194\188"] = "1/4", ["\194\189"] = "1/2", ["\194\190"] = "3/4",
    ["\226\133\144"] = "1/7", ["\226\133\145"] = "1/9", ["\226\133\146"] = "1/10",
    ["\226\133\147"] = "1/3", ["\226\133\148"] = "2/3", ["\226\133\149"] = "1/5",
    ["\226\133\150"] = "2/5", ["\226\133\151"] = "3/5", ["\226\133\152"] = "4/5",
    ["\226\133\153"] = "1/6", ["\226\133\154"] = "5/6", ["\226\133\155"] = "1/8",
    ["\226\133\156"] = "3/8", ["\226\133\157"] = "5/8", ["\226\133\158"] = "7/8" }
local function expandVulgar(s)
    s = tostring(s)
    for k, v in pairs(VULG) do s = s:gsub(k, " " .. v .. " ") end
    return s
end
local function fracVal(tok)
    tok = trim(tostring(tok))
    local w, a, b = tok:match("^(-?%d+)%s+(%d+)%s*/%s*(%d+)$")
    if w then return tonumber(w) + tonumber(a) / tonumber(b) end
    return parseNum(tok)
end
local function detectOp(s)
    local L = s:lower()
    if L:find("to the power") or L:find("power") or L:find("exponent")
        or s:find("%^") or s:find("%*%*") or L:find("exp") then return "^" end
    if L:find("divided") or L:find("divide") or L:find(" over ") or L:find("quotient")
        or s:find("/") then return "/" end
    if L:find("multipl") or L:find("times") or L:find("product")
        or s:find("%*") or s:find("%d%s*[xX]%s*%d") then return "*" end
    if L:find("plus") or L:find("added") or L:find(" sum ") or L:find("add")
        or s:find("%+") then return "+" end
    if L:find("minus") or L:find("subtract") or L:find("take away") or L:find("difference")
        or s:find("%-") then return "-" end
    if L:find("mod") or L:find("remainder") or s:find("%%") then return "%" end
    return nil
end

-- ---------- solvers ----------
local function solveArithmetic(tname)
    local s = cleanMath(tname):gsub("=+%s*%?+", ""):gsub("%?+", "")
    local nums = numbersIn(s)
    if #nums < 2 then return nil end
    local a, b, op = nums[1], nums[2], detectOp(s)
    if not op then return nil end
    if op == "+" then return fmtNum(a + b)
    elseif op == "-" then return fmtNum(a - b)
    elseif op == "*" then return fmtNum(a * b)
    elseif op == "/" then if b == 0 then return nil end return fmtNum(a / b)
    elseif op == "^" then return fmtNum(a ^ b)
    elseif op == "%" then if b == 0 then return nil end return fmtNum(a % b) end
    return nil
end
local function solveAlgebra(tname)
    local s = cleanMath(tname):lower():gsub("%?+", "")
    local n, k = s:match("(-?%d*%.?%d*)%s*x%s*=%s*(-?%d+%.?%d*)")
    if k and n ~= nil and n ~= "" then
        local nn = (n == "" or n == "+") and 1 or ((n == "-") and -1 or tonumber(n))
        if nn and nn ~= 0 then return fmtNum(tonumber(k) / nn) end
    end
    local m1, k1 = s:match("x%s*%+%s*(-?%d+%.?%d*)%s*=%s*(-?%d+%.?%d*)")
    if k1 then return fmtNum(tonumber(k1) - tonumber(m1)) end
    local m2, k2 = s:match("x%s*%-%s*(-?%d+%.?%d*)%s*=%s*(-?%d+%.?%d*)")
    if k2 then return fmtNum(tonumber(k2) + tonumber(m2)) end
    local a3, b3, c3 = s:match("(-?%d+%.?%d*)%s*%*?%s*x%s*%+%s*(-?%d+%.?%d*)%s*=%s*(-?%d+%.?%d*)")
    if c3 and tonumber(a3) ~= 0 then return fmtNum((tonumber(c3) - tonumber(b3)) / tonumber(a3)) end
    local a4, b4, c4 = s:match("(-?%d+%.?%d*)%s*%*?%s*x%s*%-%s*(-?%d+%.?%d*)%s*=%s*(-?%d+%.?%d*)")
    if c4 and tonumber(a4) ~= 0 then return fmtNum((tonumber(c4) + tonumber(b4)) / tonumber(a4)) end
    return nil
end
local function solveSequence(tname, geo)
    local nums = numbersIn(cleanMath(tname))
    if #nums < 2 then return nil end
    if geo then
        if nums[1] == 0 then return nil end
        return fmtNum(nums[#nums] * (nums[2] / nums[1]))
    end
    return fmtNum(nums[#nums] + (nums[2] - nums[1]))
end
local function solveRounding(tname, label)
    local nums = numbersIn(cleanMath(tname))
    if #nums == 0 then nums = numbersIn(cleanMath(label)) end
    if #nums == 0 then return nil end
    local x = nums[1]
    local L = tostring(label):lower()
    if L:find("hundredth") then return fmtNum(math.floor(x * 100 + 0.5) / 100)
    elseif L:find("tenth") then return fmtNum(math.floor(x * 10 + 0.5) / 10)
    elseif L:find("hundred") then return fmtNum(math.floor(x / 100 + 0.5) * 100)
    elseif L:find("ten") then return fmtNum(math.floor(x / 10 + 0.5) * 10)
    else return fmtNum(math.floor(x + 0.5)) end
end
local function solveFractions(tname)
    local s = expandVulgar(cleanMath(tname)):gsub("%?+", "")
    local a, b, op, c, d = s:match("(%d+)%s*/%s*(%d+)%s*([%+%-%*xX/])%s*(%d+)%s*/%s*(%d+)")
    if a then
        local x, y = tonumber(a) / tonumber(b), tonumber(c) / tonumber(d)
        if op == "+" then return fmtNum(x + y)
        elseif op == "-" then return fmtNum(x - y)
        else return fmtNum(x * y) end
    end
    local n1, d1 = s:match("simplify%s+(%d+)%s*/%s*(%d+)")
    if n1 then
        local g, h = math.abs(tonumber(n1)), math.abs(tonumber(d1))
        while h ~= 0 do g, h = h, g % h end
        g = g == 0 and 1 or g
        return tostring(tonumber(n1) / g) .. "/" .. tostring(tonumber(d1) / g)
    end
    local s1, s2 = s:match("(%d+)%s*/%s*(%d+)")
    if s1 and tonumber(s2) ~= 0 then return fmtNum(tonumber(s1) / tonumber(s2)) end
    return nil
end
local function solveFracToPct(tname, label)
    local s = expandVulgar(cleanMath(tname .. " " .. label))
    local a, b = s:match("(%d+)%s*/%s*(%d+)")
    if a and tonumber(b) ~= 0 then return fmtNum(tonumber(a) / tonumber(b) * 100) .. "%" end
    return nil
end
local function solvePctToFrac(tname, label)
    local s = tostring(tname) .. " " .. tostring(label)
    local n = s:match("(-?%d+%.?%d*)%%")
    if not n then local ns = numbersIn(s) n = ns[1] end
    if not n then return nil end
    n = tonumber(n)
    local num, den = math.floor(n * 100 + 0.5), 10000
    if n == math.floor(n) then num, den = n, 100 end
    local g, h = math.abs(num), math.abs(den)
    while h ~= 0 do g, h = h, g % h end
    g = g == 0 and 1 or g
    return tostring(num / g) .. "/" .. tostring(den / g)
end
local function solveFracCompare(label, tname)
    local s = expandVulgar(cleanMath(label .. " " .. tname))
    local vals = {}
    for tok in s:gmatch("(-?%d+%s+%d+/%d+|-?%d+/%d+|-?%d+%.?%d*)") do
        local v = fracVal(tok)
        if v then vals[#vals + 1] = v end
        if #vals == 2 then break end
    end
    if #vals < 2 then
        local ns = numbersIn(s)
        if #ns < 2 then return nil end
        vals = { ns[1], ns[2] }
    end
    if math.abs(vals[1] - vals[2]) < 1e-9 then return "=" end
    if vals[1] < vals[2] then return "<" else return ">" end
end
local function solveClock()
    local ok1, r1 = pcall(function() return SC.AnalogControl.Rotation1.Value end)
    local ok2, r2 = pcall(function() return SC.AnalogControl.Rotation2.Value end)
    if not (ok1 and ok2) then return nil end
    local m = math.floor(((r2 % 360) / 6) + 0.5) % 60
    local h = math.floor((r1 % 360) / 30 + 0.5) % 12
    if h == 0 then h = 12 end
    return string.format("%d:%02d", h, m)
end
local function solveShape(isArea, tname, label)
    local a = solveArithmetic(tname) or solveArithmetic(label)
    if a then return a end
    local okS, shape = pcall(function() return SC.ShapeControl.Shape.Value end)
    local ok1, s1 = pcall(function() return SC.ShapeControl.Side1.Value end)
    local ok2, s2 = pcall(function() return SC.ShapeControl.Side2.Value end)
    if not (okS and ok1) then return nil end
    shape = tostring(shape):lower() s1 = tonumber(s1) or 0 s2 = tonumber(s2) or 0
    if shape == "" then return nil end
    if shape:find("square") then
        if isArea then return fmtNum(s1 * s1) else return fmtNum(4 * s1) end
    elseif shape:find("rect") then
        if isArea then return fmtNum(s1 * s2) else return fmtNum(2 * (s1 + s2)) end
    elseif shape:find("tri") then
        if isArea then return fmtNum((s1 * s2) / 2) end
        if s1 == s2 then return fmtNum(3 * s1) end
        return fmtNum(s1 + s2 + math.sqrt(s1 * s1 + s2 * s2))
    elseif shape:find("circ") then
        if isArea then return fmtNum(math.pi * s1 * s1) else return fmtNum(2 * math.pi * s1) end
    end
    return nil
end
local COIN = { penny = 1, pennies = 1, nickel = 5, nickels = 5, dime = 10, dimes = 10,
    quarter = 25, quarters = 25, halfdollar = 50, dollar = 100, dollars = 100,
    one = 100, ones = 100, five = 500, fives = 500, ten = 1000, tens = 1000, twenty = 2000 }
local function solveMoney(tname, label)
    local a = solveArithmetic(tname) or solveArithmetic(label)
    if a then return a end
    local ok, disp = pcall(function() return SC.MoneyControl.Display.Value end)
    if not ok then return nil end
    local total, found, numSum, numN = 0, false, 0, 0
    for w in tostring(disp):gmatch("([^,]+)") do
        local key = trim(w):lower():gsub("[%s%-_]", "")
        if COIN[key] then total = total + COIN[key] found = true end
        local n = tonumber(trim(w))
        if n then numSum = numSum + n numN = numN + 1 end
    end
    if found then return fmtNum(total / 100) end
    if numN > 0 then return fmtNum(numSum / 100) end
    return nil
end
local function centerOf(g)
    local okP, p = pcall(function() return g.AbsolutePosition end)
    local okS, s = pcall(function() return g.AbsoluteSize end)
    if not (okP and okS and p and s) then return nil end
    return p.X + s.X / 2, p.Y + s.Y / 2, s.X, s.Y
end
local function solveAngleType()
    local okS, shape = pcall(function() return SC.AngleControl.Shape.Value end)
    if not okS then return nil end
    local lp2 = lp.PlayerGui:FindFirstChild("Gameplay")
    if not lp2 then return nil end
    local f = lp2.TopicGui.TopicFrame.CenterFrame.ContentFrame.AngleFrame:FindFirstChild(tostring(shape))
    if not f then return nil end
    local a1, a2, c = f:FindFirstChild("ANGLE1"), f:FindFirstChild("ANGLE2"), f:FindFirstChild("circlething")
    if not (a1 and a2 and c) then return nil end
    local x1, y1, w1, h1 = centerOf(a1)
    local x2, y2, w2, h2 = centerOf(a2)
    local x0, y0 = centerOf(c)
    if not (x1 and x2 and x0) then return nil end
    if math.max(w1, h1, w2, h2) < 8 then return nil end
    local vx1, vy1, vx2, vy2 = x1 - x0, y1 - y0, x2 - x0, y2 - y0
    local m1, m2 = math.sqrt(vx1 * vx1 + vy1 * vy1), math.sqrt(vx2 * vx2 + vy2 * vy2)
    if m1 < 2 or m2 < 2 then return nil end
    local cosA = math.clamp((vx1 * vx2 + vy1 * vy2) / (m1 * m2), -1, 1)
    local deg = math.deg(math.acos(cosA))
    uiAnswerExtra = string.format(" (measured %.0f deg)", deg)
    if deg < 80 then return "acute"
    elseif deg <= 100 then return "right"
    else return "obtuse" end
end
local function orient(w, h)
    if w >= h * 1.5 then return "h" end
    if h >= w * 1.5 then return "v" end
    return "d"
end
local function solveAngleLines()
    local okS, shape = pcall(function() return SC.AngleControl.Shape.Value end)
    local lp2 = lp.PlayerGui:FindFirstChild("Gameplay")
    if not (okS and lp2) then return nil end
    local af = lp2.TopicGui.TopicFrame.CenterFrame.ContentFrame.AngleFrame
    local f = af:FindFirstChild(tostring(shape))
    if not f then
        for _, n in ipairs({ "lines1", "lines2", "lines3", "lines4", "lines5" }) do
            f = af:FindFirstChild(n)
            if f then break end
        end
    end
    if not f then return nil end
    local a1, a2 = f:FindFirstChild("ANGLE1"), f:FindFirstChild("ANGLE2")
    if not (a1 and a2) then return nil end
    local x1, y1, w1, h1 = centerOf(a1)
    local x2, y2, w2, h2 = centerOf(a2)
    if not (x1 and x2) then return nil end
    if math.max(w1, h1, w2, h2) < 8 then return nil end
    local o1, o2 = orient(w1, h1), orient(w2, h2)
    if (o1 == "h" and o2 == "h") or (o1 == "v" and o2 == "v") then return "parallel" end
    if (o1 == "h" and o2 == "v") or (o1 == "v" and o2 == "h") then return "perpendicular" end
    return "intersecting"
end

uiAnswerExtra = ""
local function solve(ttype, tname, label)
    uiAnswerExtra = ""
    local t = trim(tostring(ttype)):lower()
    local L = tostring(label):lower()
    if L:find("round%s+to%s+the%s+nearest") or L:find("round%s+to%s+nearest") then
        return solveRounding(tname, label)
    end
    if L:find("even or odd") or L:find("odd or even") then
        local n = numbersIn(cleanMath(tname .. " " .. label))[1]
        if n then if n % 2 == 0 then return "even" else return "odd" end end
    end
    if L:find("what type of angle") or L:find("angle is this") then return solveAngleType() end
    if L:find("parallel") or L:find("perpendicular") or L:find("what.*lines") then
        local r = solveAngleLines()
        if r then return r end
    end
    if L:find("what time") or L:find("clock") or L:find("analog") then
        local r = solveClock()
        if r then return r end
    end
    if L:find("how much") or L:find("money") or L:find("cents") then
        local r = solveMoney(tname, label)
        if r then return r end
    end
    if L:find("perimeter") then
        local r = solveShape(false, tname, label)
        if r then return r end
    end
    if L:find("area") then
        local r = solveShape(true, tname, label)
        if r then return r end
    end
    if t == "add" or t == "sub" or t == "mul" or t == "div"
        or t == "exp" or t == "pro_exp" or t == "pro_exp3" then
        return solveArithmetic(tname)
    elseif t == "algebra" then return solveAlgebra(tname)
    elseif t == "seq_arithmetic" then return solveSequence(tname, false)
    elseif t == "seq_geometric" then return solveSequence(tname, true)
    elseif t == "rounding" then return solveRounding(tname, label)
    elseif t == "fractions" then return solveFractions(tname)
    elseif t == "fractiontopercent" then return solveFracToPct(tname, label)
    elseif t == "percentagetofraction" then return solvePctToFrac(tname, label)
    elseif t == "fractioncomparison" or t == "simplecomparison" then
        local r = solveFracCompare(label, tname)
        if r then return r end
    elseif t == "odd_or_even" or t == "oddoreven" then
        local n = numbersIn(cleanMath(tname))[1]
        if n then if n % 2 == 0 then return "even" else return "odd" end end
    elseif t == "analogtodigitaltime" then return solveClock()
    elseif t == "perimeterofshape" then return solveShape(false, tname, label)
    elseif t == "areaofshape" then return solveShape(true, tname, label)
    elseif t == "identifyhowmuchmoney" then return solveMoney(tname, label)
    elseif t == "identifyangletype" then return solveAngleType()
    elseif t == "identifyanglelines" then return solveAngleLines()
    end
    -- generic fallback: label-driven, works with garbage type names
    local g = solveArithmetic(tname) or solveArithmetic(label)
        or solveFractions(tname) or solveFractions(label)
        or solveFracCompare(label, tname)
        or solveFracToPct(tname, label) or solvePctToFrac(tname, label)
        or solveAlgebra(tname) or solveAlgebra(label)
        or solveRounding(tname, label)
    if g then return g end
    local nums = numbersIn(cleanMath(tname .. " " .. label))
    if #nums >= 3 then return solveSequence(tname, false) or solveSequence(tname, true) end
    return nil
end

local function readOptions()
    local opts = {}
    for i = 1, 4 do
        local ok, v = pcall(function() return AC["Answer" .. i].Value end)
        opts[i] = (ok and v ~= nil) and tostring(v) or ""
    end
    return opts
end
local function optsDegenerate(opts)
    for i = 1, 4 do
        local o = opts[i]
        if o ~= "" and (#o == 1 and string.byte(o, 1) > 127) then return true end
    end
    return false
end
local function matchOption(answer, opts)
    local na, pa = norm(answer), parseNum(answer)
    for i = 1, 4 do
        if opts[i] ~= "" then
            local no = norm(opts[i])
            if no == na then return i end
            local po = parseNum(opts[i])
            if pa and po then
                local denom = math.max(math.abs(pa), math.abs(po), 1)
                if math.abs(pa - po) < 1e-6 then return i end
                if math.abs(pa - po) / denom < 0.002 then return i end
                if math.abs(pa * 100 - po) < 1e-6 then return i end
            end
            if #na >= 3 and (string.find(no, na, 1, true) or string.find(na, no, 1, true)) then return i end
        end
    end
    return nil
end

-- ---------- read-only feedback ----------
local function sameQuestion(tname, ttype)
    local ok, a = pcall(function() return TC.TopicName.Value end)
    local ok2, b = pcall(function() return TC.TopicType.Value end)
    return ok and ok2 and a == tname and b == ttype
end
local function readFeedback()
    local lp2 = lp.PlayerGui:FindFirstChild("Gameplay")
    if not lp2 then return nil, nil end
    local cf = lp2.AnswerGui.AnswerFrame.CenterFrame
    local vt, it = nil, nil
    pcall(function() vt = cf.ValidFrame.InfoLabel.Text end)
    pcall(function() it = cf.InvalidFrame.InfoLabel.Text end)
    return vt, it
end
local function waitConfirm(tname, ttype, oldValid, oldInvalid, timeout)
    local t0 = tick()
    while tick() - t0 < timeout do
        if not sameQuestion(tname, ttype) then return "moved" end
        local vt, it = readFeedback()
        if vt and vt ~= oldValid and tostring(vt):lower():find("correct") then
            return "correct", tostring(vt)
        end
        if it and it ~= oldInvalid and tostring(it) ~= "" then
            return "wrong", tostring(it)
        end
        task.wait(0.25)
    end
    if not sameQuestion(tname, ttype) then return "moved" end
    return "timeout"
end
local function isAlive()
    local ok, v = pcall(function() return lp:GetAttribute("IsAlive") end)
    return ok and v == true
end
local function timeLeft()
    local ok, v = pcall(function() return TC.TimerValue.Value end)
    if ok and tonumber(v) then return tonumber(v) end
    return 99
end

-- ---------- panel (movable, minimizable) ----------
local PX, PY, W = 20, 20, 340
local minimized = false
local dragging = false
local gx, gy = 0, 0

local bg = Drawing.new("Square")
bg.Color = Color3.fromRGB(16, 18, 30) bg.Filled = true bg.Transparency = 0.15 bg.Visible = true
local bar = Drawing.new("Square")
bar.Color = Color3.fromRGB(32, 38, 62) bar.Filled = true bar.Transparency = 0.1 bar.Visible = true
local function txt(x, y, size, color)
    local t = Drawing.new("Text")
    t.Position = Vector2.new(x, y) t.Size = size t.Center = false
    t.Outline = true t.Color = color t.Visible = true
    return t
end
local title = txt(0, 0, 15, Color3.fromRGB(255, 255, 255))
title.Text = "Auto Solver v3.4"
local stx = txt(0, 0, 13, Color3.fromRGB(190, 195, 215))
local anx = txt(0, 0, 15, Color3.fromRGB(110, 255, 140))
local prx = txt(0, 0, 20, Color3.fromRGB(255, 214, 100))
local dlx = txt(0, 0, 12, Color3.fromRGB(255, 214, 100))
local htx = txt(0, 0, 12, Color3.fromRGB(140, 145, 165))
htx.Text = "drag bar to move | solver only, you press 1-4"
local function btn(label, color)
    local b = Drawing.new("Square")
    b.Color = color b.Filled = true b.Transparency = 0.15 b.Visible = true
    local t = Drawing.new("Text")
    t.Center = false t.Outline = true t.Size = 14
    t.Color = Color3.fromRGB(255, 255, 255) t.Text = label t.Visible = true
    return b, t
end
local bTog, tTog = btn("ON", Color3.fromRGB(40, 120, 70))
local bMin, tMin = btn("-", Color3.fromRGB(60, 64, 90))
local bPlus, tPlus = btn("+", Color3.fromRGB(60, 64, 90))
local bInst, tInst = btn("FAST", Color3.fromRGB(90, 70, 140))
local bHide, tHide = btn("_", Color3.fromRGB(60, 64, 90))

local function layout()
    local H = minimized and 30 or 176
    bg.Position = Vector2.new(PX, PY) bg.Size = Vector2.new(W, H)
    bar.Position = Vector2.new(PX, PY) bar.Size = Vector2.new(W, 30)
    title.Position = Vector2.new(PX + 10, PY + 6)
    bHide.Position = Vector2.new(PX + W - 36, PY + 4) bHide.Size = Vector2.new(26, 22)
    tHide.Position = Vector2.new(PX + W - 29, PY + 5)
    local vis = not minimized
    stx.Visible, anx.Visible, prx.Visible, dlx.Visible, htx.Visible = vis, vis, vis, vis, vis
    bTog.Visible, tTog.Visible = vis, vis
    bMin.Visible, tMin.Visible = vis, vis
    bPlus.Visible, tPlus.Visible = vis, vis
    bInst.Visible, tInst.Visible = vis, vis
    if not vis then return end
    stx.Position = Vector2.new(PX + 10, PY + 36)
    anx.Position = Vector2.new(PX + 10, PY + 54)
    prx.Position = Vector2.new(PX + 10, PY + 74)
    dlx.Position = Vector2.new(PX + 10, PY + 102)
    local by = PY + 120
    bTog.Position = Vector2.new(PX + 10, by) bTog.Size = Vector2.new(64, 28)
    tTog.Position = Vector2.new(PX + 24, by + 5)
    bMin.Position = Vector2.new(PX + 80, by) bMin.Size = Vector2.new(38, 28)
    tMin.Position = Vector2.new(PX + 93, by + 5)
    bPlus.Position = Vector2.new(PX + 124, by) bPlus.Size = Vector2.new(38, 28)
    tPlus.Position = Vector2.new(PX + 137, by + 5)
    bInst.Position = Vector2.new(PX + 168, by) bInst.Size = Vector2.new(64, 28)
    tInst.Position = Vector2.new(PX + 178, by + 5)
    htx.Position = Vector2.new(PX + 10, by + 32)
end
local function inside(mx, my, b)
    local p, s = b.Position, b.Size
    return mx >= p.X and mx <= p.X + s.X and my >= p.Y and my <= p.Y + s.Y
end
local function inBar(mx, my)
    return mx >= PX and mx <= PX + W - 40 and my >= PY and my <= PY + 30
end
local lastClick = 0
task.spawn(function()
    while _G.AA_Running do
        local m = lp:GetMouse()
        local pressed = false
        pcall(function() pressed = ismouse1pressed() end)
        if pressed and tick() - lastClick > 0.28 then
            if inside(m.X, m.Y, bHide) then
                minimized = not minimized layout() lastClick = tick()
            elseif not minimized and inside(m.X, m.Y, bTog) then
                enabled = not enabled lastClick = tick()
            elseif not minimized and inside(m.X, m.Y, bMin) then
                delay = math.max(0, delay - 0.1) lastClick = tick()
            elseif not minimized and inside(m.X, m.Y, bPlus) then
                delay = math.min(5, delay + 0.1) lastClick = tick()
            elseif not minimized and inside(m.X, m.Y, bInst) then
                delay = 0 lastClick = tick()
            elseif inBar(m.X, m.Y) then
                dragging, gx, gy = true, m.X - PX, m.Y - PY
            end
        elseif not pressed then
            dragging = false
        end
        if dragging then PX, PY = m.X - gx, m.Y - gy end
        layout()
        if enabled then tTog.Text = "ON" bTog.Color = Color3.fromRGB(40, 120, 70)
        else tTog.Text = "OFF" bTog.Color = Color3.fromRGB(120, 45, 45) end
        dlx.Text = string.format("Show delay: %.1fs", delay)
        stx.Text = string.sub(uiStatus, 1, 54)
        anx.Text = string.sub(uiAnswer, 1, 54)
        prx.Text = string.sub(uiPress, 1, 40)
        task.wait(0.03)
    end
    for _, d in ipairs({ bg, bar, title, stx, anx, prx, dlx, htx, bTog, tTog, bMin, tMin,
        bPlus, tPlus, bInst, tInst, bHide, tHide }) do pcall(function() d:Remove() end) end
    print("[AutoAnswer] stopped")
end)

-- ---------- main loop ----------
task.spawn(function()
    while _G.AA_Running do
        local okT, ttype = pcall(function() return TC.TopicType.Value end)
        local okN, tname = pcall(function() return TC.TopicName.Value end)
        if okT and okN and ttype ~= "" and tname ~= "" and timeLeft() > 0 then
            local key = ttype .. "||" .. tname
            if key ~= lastKey then
                lastKey = key
                local label = ""
                local lp2 = lp.PlayerGui:FindFirstChild("Gameplay")
                if lp2 then
                    local okL, lv = pcall(function()
                        return lp2.TopicGui.TopicFrame.CenterFrame.TopicLabel.Text
                    end)
                    if okL and lv then label = lv end
                end
                uiStatus = (ttype or "?") .. ": " .. string.sub(tostring(label ~= "" and label or tname), 1, 60)
                if not enabled then
                    uiAnswer, uiPress = "paused", ""
                else
                    if delay > 0 then task.wait(delay) end
                    -- re-read: values replicate late, adopt fresh ones
                    local fT, fN = ttype, tname
                    pcall(function() fT = TC.TopicType.Value end)
                    pcall(function() fN = TC.TopicName.Value end)
                    if fN ~= "" and (fT ~= ttype or fN ~= tname) then
                        ttype, tname = fT, fN
                        lastKey = ttype .. "||" .. tname
                        if lp2 then
                            local okL, lv = pcall(function()
                                return lp2.TopicGui.TopicFrame.CenterFrame.TopicLabel.Text
                            end)
                            if okL and lv then label = lv end
                        end
                        uiStatus = (ttype or "?") .. ": " .. string.sub(tostring(label ~= "" and label or tname), 1, 60)
                    end
                    local ans = solve(ttype, tname, label)
                    if ans then
                        local opts = readOptions()
                        if optsDegenerate(opts) then
                            task.wait(0.5)
                            opts = readOptions()
                        end
                        local idx = matchOption(ans, opts)
                        uiAnswer = "answer: " .. tostring(ans) .. (uiAnswerExtra or "")
                        if idx then
                            uiPress = "PRESS  [" .. tostring(idx) .. "]  (" .. tostring(opts[idx]):sub(1, 18) .. ")"
                        else
                            uiPress = "find it manually"
                            uiAnswer = uiAnswer .. " | opts: " .. tostring(table.concat(opts, "|")):sub(1, 40)
                        end
                        print("[Solver] " .. uiStatus .. " -> " .. tostring(ans) .. (idx and (" [key " .. idx .. "]") or " [NO MATCH]"))
                        local oldValid, oldInvalid = readFeedback()
                        local res, detail = waitConfirm(tname, ttype, oldValid, oldInvalid, 6)
                        if res == "correct" then
                            uiPress = "CONFIRMED CORRECT"
                        elseif res == "wrong" then
                            uiPress = "game says WRONG, check log"
                            print("[Solver] WRONG per game: " .. uiStatus .. " showed " .. tostring(ans))
                        end
                    else
                        uiAnswer = "unsupported [" .. tostring(#tostring(ttype)) .. "b]"
                        uiPress = ""
                        print("[Solver] unsupported typelen=" .. tostring(#tostring(ttype)) .. " status=" .. uiStatus)
                    end
                    if not isAlive() then uiStatus = uiStatus .. " (you are out)" end
                end
            end
        else
            if uiStatus ~= "waiting for question..." then
                uiStatus, uiAnswer, uiPress = "waiting for question...", "", ""
            end
        end
        task.wait(0.15)
    end
end)
print("[Auto Solver v3.4] started. Read the PRESS line and tap the key.")

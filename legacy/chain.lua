--[[
    Luathys Decompilation Chain
    Multi-method decompilation with fallback handling
]]

local Decompiler = {}

-- Decompilation method registry
Decompiler.methods = {
    "native_decompile",
    "source_property",
    "external_api",
    "local_server",
}

-- Method weights for randomized selection
Decompiler.methodWeights = {
    native_decompile = 80,
    source_property = 15,
    external_api = 5,
}

-- Weighted random method selection
function Decompiler.selectMethod()
    local totalWeight = 0
    for _, weight in pairs(Decompiler.methodWeights) do
        totalWeight = totalWeight + weight
    end

    local roll = math.random() * totalWeight
    local cumulative = 0

    for method, weight in pairs(Decompiler.methodWeights) do
        cumulative = cumulative + weight
        if roll <= cumulative then
            return method
        end
    end

    return "native_decompile"
end

-- Native decompile method
function Decompiler.tryNativeDecompile(scriptInstance, resolveFunction)
    local decompileFn = resolveFunction("decompile")
    if not decompileFn then
        return nil, "decompile function not available"
    end

    local timeout = math.random(10, 30)
    local success, result = pcall(decompileFn, scriptInstance, false, timeout)

    if success and result and #result > 0 then
        return result, nil
    end

    return nil, "native decompile failed"
end

-- Source property extraction method
function Decompiler.trySourceProperty(scriptInstance)
    local success, source = pcall(function()
        return scriptInstance.Source
    end)

    if success and source and #source > 0 then
        return source, nil
    end

    return nil, "source property not readable"
end

-- Bytecode extraction helper
function Decompiler.extractBytecode(scriptInstance, resolveFunction)
    local success, result = pcall(resolveFunction("getscriptbytecode"), scriptInstance)
    if success and result and #result > 0 then
        return result
    end

    if debug and debug.getscriptbytecode then
        success, result = pcall(debug.getscriptbytecode, scriptInstance)
        if success and result then
            return result
        end
    end

    return nil
end

-- External API decompilation method
function Decompiler.tryExternalAPI(scriptInstance, resolveFunction)
    local bytecode = Decompiler.extractBytecode(scriptInstance, resolveFunction)
    if not bytecode then
        return nil, "bytecode extraction failed"
    end

    if not (request and crypt and crypt.base64) then
        return nil, "no HTTP or base64 library available"
    end

    local encoded = crypt.base64.encode(bytecode)
    local endpoints = {
        "http://127.0.0.1:8000/dec",
        "http://127.0.0.1:9000/dec",
        "http://localhost:8000/dec",
        "https://unluau.lonegladiator.dev/unluau/decompile",
    }

    for _, url in ipairs(endpoints) do
        local success, result = pcall(function()
            local req = request({
                Url = url,
                Method = "POST",
                Body = encoded,
                Headers = {
                    ["Content-Type"] = "application/octet-stream",
                    ["User-Agent"] = "Mozilla/5.0",
                }
            })
            if req and req.Body and #req.Body > 0 then
                return req.Body
            end
        end)

        if success and result then
            return result, nil
        end
    end

    return nil, "all external API endpoints failed"
end

-- Local server decompilation method
function Decompiler.tryLocalServer(scriptInstance, resolveFunction)
    local bytecode = Decompiler.extractBytecode(scriptInstance, resolveFunction)
    if not bytecode then
        return nil, "bytecode extraction for local server failed"
    end

    if not (crypt and crypt.base64 and request) then
        return nil, "no HTTP library available for local server"
    end

    local encoded = crypt.base64.encode(bytecode)
    local localEndpoints = {
        "http://127.0.0.1:8000/decompile",
        "http://127.0.0.1:9000/decompile",
        "http://127.0.0.1:5000/decompile",
    }

    for _, url in ipairs(localEndpoints) do
        local success, result = pcall(function()
            local req = request({
                Url = url,
                Method = "POST",
                Body = encoded,
                Headers = {["Content-Type"] = "application/octet-stream"}
            })
            if req and req.Body and #req.Body > 0 then
                return req.Body
            end
        end)

        if success and result then
            return result, nil
        end
    end

    return nil, "all local server endpoints failed"
end

-- Main decompilation entry point with full fallback chain
function Decompiler.decompile(scriptInstance, resolveFunction, preferredMethod)
    preferredMethod = preferredMethod or "auto"

    local methods = {
        native_decompile = function(si)
            return Decompiler.tryNativeDecompile(si, resolveFunction)
        end,
        source_property = function(si)
            return Decompiler.trySourceProperty(si)
        end,
        external_api = function(si)
            return Decompiler.tryExternalAPI(si, resolveFunction)
        end,
        local_server = function(si)
            return Decompiler.tryLocalServer(si, resolveFunction)
        end,
    }

    if preferredMethod ~= "auto" and methods[preferredMethod] then
        return methods[preferredMethod](scriptInstance)
    end

    local tried = {}
    local attempts = 0
    local maxAttempts = 6

    while attempts < maxAttempts do
        attempts = attempts + 1

        local method
        if attempts == 1 then
            method = "native_decompile"
        elseif attempts <= 3 then
            method = Decompiler.selectMethod()
        else
            local untried = {}
            for name, _ in pairs(methods) do
                if not tried[name] then
                    untried[#untried + 1] = name
                end
            end
            if #untried == 0 then break end
            method = untried[math.random(1, #untried)]
        end

        if tried[method] then continue end
        tried[method] = true

        local result, err = methods[method](scriptInstance)

        if result and #result > 0 then
            return result, nil
        end

        local minDelay, maxDelay = 5, 20
        local delay = minDelay + math.random() * (maxDelay - minDelay)
        wait(delay / 1000)
    end

    return nil, "All decompilation methods exhausted after " .. attempts .. " attempts"
end

return Decompiler

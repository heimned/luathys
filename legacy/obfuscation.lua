--[[
    Luathys Obfuscation Layer
    Runtime string encryption and anti-detection utilities
]]

local Obfuscation = {}

-- XOR encryption key pool (rotated at runtime)
Obfuscation.keys = {
    primary = 0x5A,
    secondary = 0x3C,
    tertiary = 0x7E,
}

-- Random key selection for each operation
function Obfuscation.getDynamicKey()
    local keys = {0x41, 0x5A, 0x3C, 0x7E, 0x1F, 0x9B, 0x2D}
    return keys[math.random(1, #keys)]
end

-- String encryption: XOR with variable key derived from position
function Obfuscation.encrypt(str, key)
    key = key or Obfuscation.getDynamicKey()
    local result = {}
    for i = 1, #str do
        local byte = str:byte(i)
        local keyByte = (key + i * 0x13) % 256
        result[i] = string.char(byte ~ keyByte)
    end
    return table.concat(result), key
end

-- String decryption
function Obfuscation.decrypt(encrypted, key)
    local result = {}
    for i = 1, #encrypted do
        local byte = encrypted:byte(i)
        local keyByte = (key + i * 0x13) % 256
        result[i] = string.char(byte ~ keyByte)
    end
    return table.concat(result)
end

-- Encode string as hex for static storage
function Obfuscation.toHex(str)
    local hex = {}
    for i = 1, #str do
        hex[i] = string.format("%02x", str:byte(i))
    end
    return table.concat(hex)
end

-- Decode hex string
function Obfuscation.fromHex(hex)
    local result = {}
    for i = 1, #hex, 2 do
        result[#result + 1] = string.char(tonumber(hex:sub(i, i + 1), 16))
    end
    return table.concat(result)
end

-- Build runtime string lookup table
function Obfuscation.buildLookup(strings, key)
    local lookup = {}
    for idx, str in ipairs(strings) do
        local encrypted, usedKey = Obfuscation.encrypt(str, key)
        lookup[idx] = {
            data = encrypted,
            key = usedKey,
            length = #str,
        }
    end
    return lookup
end

-- Runtime string resolver from lookup table
function Obfuscation.resolve(lookup, idx)
    if not lookup[idx] then return nil end
    local entry = lookup[idx]
    return Obfuscation.decrypt(entry.data, entry.key)
end

-- Timing jitter generator
function Obfuscation.jitter(min, max, curve)
    min = min or 10
    max = max or 100
    curve = curve or 1

    local base = math.random()
    local curved = math.pow(base, curve)
    return min + curved * (max - min)
end

-- Anti-pattern randomizer
function Obfuscation.randomizePattern(base, variation)
    variation = variation or 0.3
    local range = base * variation
    return base + (math.random() - 0.5) * 2 * range
end

-- Function call obfuscation
function Obfuscation.obfuscateCall(fn, ...)
    if type(fn) ~= "function" then
        return nil, "not a function"
    end
    return pcall(fn, ...)
end

return Obfuscation

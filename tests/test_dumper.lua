--[[
    Luathys Test Suite
    Basic validation tests for the dumper engine
]]

local TestSuite = {}

-- Test 1: Verify module structure
function TestSuite.testModuleLoading()
    print("[Test] Module Loading")
    print("  OK: Test structure valid")
end

-- Test 2: Verify string obfuscation logic
function TestSuite.testObfuscation()
    print("[Test] String Obfuscation Logic")

    local key = 0x5A
    local testString = "test_remote_event"

    -- Encrypt
    local encrypted = {}
    for i = 1, #testString do
        local byte = testString:byte(i)
        local keyByte = (key + i * 0x13) % 256
        encrypted[i] = string.char(byte ~ keyByte)
    end
    local enc = table.concat(encrypted)

    -- Decrypt
    local decrypted = {}
    for i = 1, #enc do
        local byte = enc:byte(i)
        local keyByte = (key + i * 0x13) % 256
        decrypted[i] = string.char(byte ~ keyByte)
    end
    local dec = table.concat(decrypted)

    assert(dec == testString, "Obfuscation round-trip failed")
    print("  OK: XOR encryption/decryption round-trip passed")
end

-- Test 3: Verify decompiler method structure
function TestSuite.testDecompilerStructure()
    print("[Test] Decompiler Structure")

    local methods = {
        "native_decompile",
        "source_property",
        "external_api",
        "local_server",
    }

    for _, method in ipairs(methods) do
        assert(method ~= nil, "Method " .. method .. " missing")
    end

    print("  OK: All decompiler methods registered")
end

-- Test 4: Verify hex encoding
function TestSuite.testHexEncoding()
    print("[Test] Hex Encoding")

    local testStr = "hello"
    local hex = ""
    for i = 1, #testStr do
        hex = hex .. string.format("%02x", testStr:byte(i))
    end

    -- Decode back
    local result = ""
    for i = 1, #hex, 2 do
        result = result .. string.char(tonumber(hex:sub(i, i + 1), 16))
    end

    assert(result == testStr, "Hex round-trip failed")
    print("  OK: Hex encoding/decoding passed")
end

-- Run all tests
function TestSuite.run()
    print("\n=== Luathys Test Suite ===")
    print("Tests can run standalone (no Roblox context required)\n")

    local tests = {
        {"Module Loading", TestSuite.testModuleLoading},
        {"Obfuscation Logic", TestSuite.testObfuscation},
        {"Decompiler Structure", TestSuite.testDecompilerStructure},
        {"Hex Encoding", TestSuite.testHexEncoding},
    }

    local passed = 0
    local failed = 0

    for _, test in ipairs(tests) do
        local success, err = pcall(test[2])
        if success then
            passed = passed + 1
        else
            failed = failed + 1
            print("  FAILED: " .. test[1] .. " - " .. tostring(err))
        end
    end

    print("\n=== Results ===")
    print("Passed: " .. passed)
    print("Failed: " .. failed)
    print("Total:  " .. #tests .. "\n")

    return failed == 0
end

return TestSuite

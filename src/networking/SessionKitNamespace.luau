--!strict
--[[
    @author nat
    @date 16-09-26

    SessionKit bytenet namespace
]]
local bytenet = require("../../Packages/bytenet")
return bytenet.defineNamespace("SessionKit", function()
    return {
        queries = {
            --full snapshot, sent once when a session opens on the client
            GetData = bytenet.defineQuery({
                request = bytenet.nothing,
                response = bytenet.optional(bytenet.map(bytenet.auto, bytenet.auto)),
            }),
        },

        packets = {
            SetValue = bytenet.definePacket({
                value = bytenet.struct({
                    path = bytenet.array(bytenet.string),
                    value = bytenet.auto, --please use numbers or strings
                }),
            }),

            ArrayInsert = bytenet.definePacket({
                value = bytenet.struct({
                    path = bytenet.array(bytenet.string),
                    value = bytenet.auto,
                    index = bytenet.uint32
                }),
            }),

            ArrayRemove = bytenet.definePacket({
                value = bytenet.struct({
                    path = bytenet.array(bytenet.string),
                    index = bytenet.uint32,
                }),
            }),
        }
    }
end)
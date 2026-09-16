--!strict
--[[
    @author nat
    @date 15-09-26

    SKIT (SessionKit) is simply a ProfileStore wrapper to make
    handling data both on the server and the client easier

    License: MIT
    This has not been tested in production yet, but it should be fine since it's just a wrapper
]]
--Services
local RunService = game:GetService("RunService")

--Modules
local SessionKitServer = require("@self/core/SessionKitServer")
local SessionKitClient = require("@self/core/SessionKitClient")

--Types
export type SessionKitOptions = {
    storeName: string
}

--The return
return function<T>(template: T, options: SessionKitOptions?)
    local server = SessionKitServer :: SessionKitServer.SessionKitServerPrivate<T>
    local client = SessionKitClient :: SessionKitClient.SessionKitClientModule<T>

    return {
        server = (if RunService:IsServer() then server.initialize(template, options) else {}) :: SessionKitServer.SessionKitServerModule<T>,
        client = client,
    }
end
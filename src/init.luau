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
local SessionKitTypes = require("@self/shared/SessionKitTypes")

--The return
return function<T>(template: T, options: SessionKitTypes.SessionKitOptions?)
    local server = SessionKitServer :: SessionKitServer.SessionKitServerPrivate<T>
    local client = SessionKitClient :: SessionKitClient.SessionKitClientPrivate<T>
    
    return {
        server = (if RunService:IsServer() then server.initialize(template, options) else {}) :: SessionKitServer.SessionKitServerModule<T>,
        client = (if RunService:IsClient() then client.initialize(template, options) else {}) :: SessionKitClient.SessionKitClientModule<T>,
    }
end
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
const RunService = game:GetService("RunService")

--Modules
const Value = require("@self/Value")
const SessionKitClient = require("@self/client/SessionKitClient")
const SessionKitServer = require("@self/server/SessionKitServer")
const Log = require("@self/shared/Log")
const SessionKitTypes = require("@self/shared/SessionKitTypes")
const Validate = require("@self/shared/Validate")

--Exported types
export type Value<T> = Value.Value<T>
export type ValueBase<T> = Value.ValueBase<T>

--The return
return function<T>(template: T, options: SessionKitTypes.SessionKitOptions?)
    const code, message = Validate.template(template) --makes sure the template is serializable
    if code then
        Log.error(code, message :: string, 2)
    end
    
    const server = SessionKitServer :: SessionKitServer.SessionKitServerPrivate<T>
    const client = SessionKitClient :: SessionKitClient.SessionKitClientPrivate<T>
    
    return {
        server = (if RunService:IsServer() then server.initialize(template, options) else {}) :: SessionKitServer.SessionKitServerModule<T>,
        client = (if RunService:IsClient() then client.initialize(template, options) else {}) :: SessionKitClient.SessionKitClientModule<T>,
        template = template,
    }
end
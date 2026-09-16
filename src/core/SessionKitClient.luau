--!strict
--[[
    @author nat
    @date 14-09-26

    Client version of session kit
]]
local SessionKitServer = {}

--Services
local RunService = game:GetService("RunService")

--require guard
if not RunService:IsClient() then
    return {}
end

export type SessionKitClientModule<T> = {
    template: T
}

return SessionKitServer

--!strict
--[[
    @author nat
    @date 07-10-26

    Log helper
]]
local Log = { enabled = true }

function Log.error(code: string, message: string, level: number?): never
    error(`[SessionKit][{code}] {message}`, (level or 1) + 1)
end

function Log.warn(code: string, message: string)
    warn(`[SessionKit][{code}] {message}`)
end

function Log.debug(...: any)
    if Log.enabled then
        print("[SessionKit]", ...)
    end
end

return Log
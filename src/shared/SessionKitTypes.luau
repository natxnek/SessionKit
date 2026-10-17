--!strict
--[[
    @author nat
    @date 14-09-26

    Shared skit types
]]
export type SessionKitDataSchemeEntry = {
		replicateOnChange: boolean?,
		replicateInitialValue: boolean?,
}

export type SessionKitDataScheme = {
    [string]: SessionKitDataSchemeEntry
}

export type SessionKitOptions = {
    storeName: string?,
    dataScheme: SessionKitDataScheme,
}

return {}
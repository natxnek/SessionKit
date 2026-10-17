--!strict
--[[
    @author nat
    @date 14-09-26

    Shared skit types
]]
export type SessionKitOptions = {
    storeName: string?
}

export type SessionKitDataSchemeEntry = {
		replicateOnChange: boolean?,
		replicateInitialValue: boolean?,
}

export type SessionKitDataScheme = {
		[string]: SessionKitDataSchemeEntry
}

return {}
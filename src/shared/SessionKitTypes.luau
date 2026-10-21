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

export type SessionKitDataScheme<T> = {
    [keyof<T>]: SessionKitDataSchemeEntry
}

export type SessionKitOptions<T> = {
    storeName: string?,
    dataScheme: SessionKitDataScheme<T>?,
}

return {}
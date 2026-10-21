--!strict
--[[
    @author nat
    @date 07-10-26

    Checks that data can be stored, encoded, and replicated
    this file is mostly ai generated to cover every edge case
]]
local Validate = {}

--Modules
const Constants = require("../Value/Constants")

--Types
export type Path = { string } | { number }

--Variables
local deepWrites = true

--Constants
const MAX_DEPTH = 32

--Method names live on value's __index and internal fields live on the value table,
--so data keys with these names would be unreachable or would corrupt a value
local RESERVED_KEYS: { [string]: true } = {
	OnChange = true,
	Insert = true,
	Remove = true,
	OnInsert = true,
	OnRemove = true,
	OnKeyAdded = true,
	OnKeyRemoved = true,

	[Constants.KEY_KEY] = true,
	[Constants.PARENT_KEY] = true,
	[Constants.CONTAINER_KEY] = true,
	[Constants.CHILDREN_KEY] = true,
	[Constants.REPLICATE_KEY] = true,
	[Constants.CHANGED_KEY] = true,
	[Constants.ARRAY_INSERTED_KEY] = true,
	[Constants.ARRAY_REMOVED_KEY] = true,
	[Constants.KEY_ADDED_KEY] = true,
	[Constants.KEY_REMOVED_KEY] = true,
}

--{ "inventory", "items", 3 } -> "data.inventory.items[3]"
local function pathToString(path: Path, root: string?): string
	local out = root or "data"
	for _, key in path do
		if typeof(key) == "number" then
			out ..= `[{key}]`
		elseif string.sub(key, 1, 1) == "#" then
			out ..= `.{string.sub(key, 2)}`
		elseif string.match(key, "^[%a_][%w_]*$") then
			out ..= `.{key}`
		else
			out ..= string.format("[%q]", key)
		end
	end
	return out
end

--Describes the given value's type as a string (an Instance, a {type})
local function describe(value: any): string
	if typeof(value) == "Instance" then
		return `an Instance ({(value :: Instance).ClassName})`
	end
	return `a {typeof(value)}`
end

--Copy of path with key on the end
local function withKey(path: Path, key: string | number): Path
	local copy = table.clone(path) :: any
	table.insert(copy, key)
	return copy
end

--Path to the key if it can be part of a path, otherwise just the path to its parent
local function keyLocation(path: Path, key: any, root: string?): string
	if typeof(key) == "string" or typeof(key) == "number" then
		return pathToString(withKey(path, key), root)
	end
	return pathToString(path, root)
end

--Returns (code, reason) if the key can't be used. The caller puts a path in front of the reason
local function keyProblem(key: any): (string?, string?)
	if typeof(key) == "string" then
		if RESERVED_KEYS[key] or string.sub(key, 1, 1) == "#" then
			return "E_RESERVED_KEY",
				`'{key}' is a reserved name (Values expose a method or internal field with that name, key cannot start with a #), rename it`
		end
		if utf8.len(key) == nil then
			return "E_BAD_KEY", "the key is a string with invalid UTF-8"
		end
	elseif typeof(key) == "number" then
		local n = key :: number
		if n ~= n or n == math.huge or n ~= math.floor(n) or n < 1 then
			return "E_BAD_KEY", `{n} is not a valid key, number keys must be integers >= 1`
		end
	else
		return "E_BAD_KEY", `keys must be strings or array indices, got a {typeof(key)}`
	end
	return nil, nil
end

--Checks a table's keys and shape (array or dictionary, no mixing, no holes)
local function checkShape(tbl: { [any]: any }, stack: Path, root: string?): (string?, string?)
	local count = 0
	local stringKeys = 0
	local numberKeys = 0
	local maxIndex = 0

	for key in tbl do
		count += 1

		local code, reason = keyProblem(key)
		if code then
			return code, `{keyLocation(stack, key, root)}: {reason}`
		end

		if typeof(key) == "string" then
			stringKeys += 1
		else
			numberKeys += 1
			maxIndex = math.max(maxIndex, key :: number)
		end
	end

	if stringKeys > 0 and numberKeys > 0 then
		return "E_MIXED_TABLE",
			`{pathToString(stack, root)} mixes array indices and string keys. Use either an array or a dictionary, not both`
	end

	if numberKeys > 0 and maxIndex ~= count then
		return "E_SPARSE_ARRAY",
			`{pathToString(stack, root)} is a sparse array (highest index {maxIndex}, but only {count} entries). Holes break saving and replication, use Remove(index) instead of setting entries to nil`
	end

	return nil, nil
end

--Walks a value. `stack` is the path to it and gets pushed/popped while walking,
--it only turns into a string when something fails so valid data doesn't allocate per key
local function check(value: any, stack: Path, ancestors: { [any]: true }, root: string?): (string?, string?)
	local valueType = typeof(value)

	--nil means "no value"/removal, the caller decides if that's allowed
	if value == nil or valueType == "boolean" then
		return nil, nil
	end

	if valueType == "number" then
		local n = value :: number
		if n ~= n then
			return "E_NAN", `{pathToString(stack, root)} is NaN, which can't be saved or replicated`
		elseif n == math.huge or n == -math.huge then
			return "E_INF", `{pathToString(stack, root)} is {n}, which can't be saved or replicated`
		end
		return nil, nil
	end

	if valueType == "string" then
		if utf8.len(value :: string) == nil then
			return "E_BAD_STRING", `{pathToString(stack, root)} is a string with invalid UTF-8`
		end
		return nil, nil
	end

	if valueType ~= "table" then
		return "E_NOT_SERIALIZABLE",
			`{pathToString(stack, root)} is {describe(value)}. Only nil, boolean, number, string and plain tables of those can be stored. Convert it first (for example store a Vector3 as a table like \{ x = 1, y = 2, z = 3 })`
	end

	if #stack > MAX_DEPTH then
		return "E_TOO_DEEP",
			`{pathToString(stack, root)} is nested more than {MAX_DEPTH} levels deep (is there a cycle?)`
	end
	if ancestors[value] then
		return "E_CYCLE", `{pathToString(stack, root)} contains a reference to one of its own parents (cyclic table)`
	end
	if getmetatable(value :: any) ~= nil then
		return "E_HAS_METATABLE",
			`{pathToString(stack, root)} is a table with a metatable (a class instance or a Value?). Only plain tables can be stored`
	end
	if table.isfrozen(value :: any) then
		return "E_FROZEN",
			`{pathToString(stack, root)} is a frozen table, SessionKit mutates tables in place so they can't be frozen`
	end

	local tbl = value :: { [any]: any }
	local code, message = checkShape(tbl, stack, root)
	if code then
		return code, message
	end

	ancestors[value] = true
	for key, child in tbl do
		table.insert(stack :: any, key)
		code, message = check(child, stack, ancestors, root)
		table.remove(stack :: any)
		if code then
			return code, message
		end
	end
	ancestors[value] = nil --only parents count as cycles, shared non-cyclic references are fine

	return nil, nil
end

--Non-throwing full check, returns ok, code, message. Handy for unit tests
function Validate.check(value: any, path: Path?, root: string?): (boolean, string?, string?)
	local code, message = check(value, if path then table.clone(path) else {}, {}, root)
	return code == nil, code, message
end

--true (default): deep-validate every written value. false: tables are skipped, primitives are still checked
function Validate.setDeepWrites(enabled: boolean)
	deepWrites = enabled
end

--The template passed to SessionKit(), runs once at startup
function Validate.template(template: any): (string?, string?)
	if typeof(template) ~= "table" then
		return "E_BAD_TEMPLATE", `the template must be a table, got {typeof(template)}`
	end
	return check(template, {}, {}, "template")
end

--A value about to be written at `path` (the full path of the value being written)
function Validate.value(path: Path, value: any): (string?, string?)
	if not deepWrites and typeof(value) == "table" then
		return nil, nil
	end
	return check(value, table.clone(path), {}, "data")
end

--A key about to be created under the Value at `path`
function Validate.key(path: Path, key: any): (string?, string?)
	local code, reason = keyProblem(key)
	if not code then
		return nil, nil
	end
	return code, `{keyLocation(path, key)}: {reason}`
end

--Does writing `newValue` at `key` keep `container` a clean array or a clean dictionary?
--`path` is the full path of the value being written
function Validate.fitsContainer(
	path: Path,
	container: { [any]: any },
	key: string | number,
	newValue: any
): (string?, string?)
	local isArray = container[1] ~= nil
	local isDictionary = not isArray and next(container) ~= nil
	local here = pathToString(path)

	if typeof(key) == "string" then
		if isArray then
			return "E_MIXED_TABLE", `{here}: the parent is an array, a string key would make it a mixed table`
		end
		return nil, nil
	end

	if isDictionary then
		return "E_MIXED_TABLE", `{here}: the parent is a dictionary, a number key would make it a mixed table`
	end

	local length = #container
	if newValue == nil and key < length then
		return "E_ARRAY_HOLE",
			`{here}: setting index {key} to nil would leave a hole in a {length}-item array. Use Remove({key})`
	elseif newValue ~= nil and key > length + 1 then
		return "E_SPARSE_ARRAY",
			`{here}: index {key} is past the end of a {length}-item array (next free index: {length + 1}). Use Insert`
	end

	return nil, nil
end

--Insert / Remove preconditions
function Validate.arrayOperation(
	path: Path,
	raw: any,
	operation: "Insert" | "Remove",
	position: any
): (string?, string?)
	local here = pathToString(path)
	local where = `{here}.{operation}`

	if typeof(raw) ~= "table" then
		return "E_NOT_TABLE", `{where}: {here} is {typeof(raw)}, expected an array`
	end
	if table.isfrozen(raw) then
		return "E_FROZEN", `{where}: {here} is a frozen table`
	end
	if raw[1] == nil and next(raw) ~= nil then
		return "E_NOT_ARRAY", `{where}: {here} is a dictionary, Insert and Remove only work on arrays`
	end

	if position == nil then
		return nil, nil
	end

	if typeof(position) ~= "number" then
		return "E_BAD_INDEX", `{where}: position must be a number, got {typeof(position)}`
	end
	if position ~= math.floor(position) then
		return "E_BAD_INDEX", `{where}: position {position} is not an integer`
	end

	local length = #raw
	local max = if operation == "Insert" then length + 1 else length
	if position < 1 or position > max then
		return "E_BAD_INDEX",
			`{where}: position {position} is out of range ({here} has {length} items, valid: 1..{max})`
	end

	return nil, nil
end

Validate.pathToString = pathToString
return Validate

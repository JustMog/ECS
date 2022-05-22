
local Entity = {}

function Entity:__index(k)
   local c = self._components[k]
   return c ~= nil and c or Entity[k]
end

local worldRecheckEntity
function Entity:__newindex(k, v)
    local hadComponent = self._components[k] ~= nil
    local gotComponent = v ~= nil

    self._components[k] = v

    if hadComponent ~= gotComponent then
        worldRecheckEntity(self._world, self)
    end
end

---------------------------------------------

local Pool = {}
Pool.__index = Pool

local makeAccessor
function Pool:new(filter)

    local pool = setmetatable({
        keys = filter,
        entities = {},
        changes = {},
        added = {},
        removed = {},
        listeners = {},
    }, Pool)

    pool.accessor = makeAccessor(pool.entities)
    return pool
end

function makeAccessor(t)
    local accessor, mt = {}, {}

    function accessor:copy()
        local copy = {}
        for i, v in ipairs(t) do
            copy[i] = v
        end
        return copy
    end

    function mt:__call()
        return ipairs(t)
    end
    return setmetatable(accessor, mt)
end

function Pool:filter(e)
    for _, key in ipairs(self.keys) do
        if not e[key] then return false end
    end
    return true
end

function Pool:recheck(e)
    local match = (not e.dead) and self:filter(e)

    local hasEntity = self.entities[e]

    if match ~= hasEntity then
        self.changes[e] = match
    end
end

function Pool:update()
    while(next(self.changes)) do
        --remove
        for i = #self.entities, 1, -1 do
            local e = self.entities[i]

            if self.changes[e] == false then
                self.changes[e] = nil

                self.entities[e] = nil
                table.remove(self.entities, i)
                table.insert(self.removed, e)
            end
        end

        --add
        for e in pairs(self.changes) do
            if self.changes[e] == true then
                table.insert(self.entities, e)
                table.insert(self.added, e)
            end
            self.changes[e] = nil
        end

        for i, e in ipairs(self.added) do
            self:onAdded(e)
            table.remove(self.added, i)
        end

        for i, e in ipairs(self.removed) do
            self:onRemoved(e)
            table.remove(self.removed, i)
        end
    end

end

function Pool:onAdded(e)
    for _, listener in ipairs(self.listeners)  do
        if listener.onAdded then listener:onAdded(e, self.accessor) end
    end
end

function Pool:onRemoved(e)
    for _, listener in ipairs(self.listeners)  do
        if listener.onRemoved then listener:onRemoved(e, self.accessor) end
    end
end

---------------------------------------------

local World = {}
World.__index = World

local newSystem

local function newWorld(...)
    local world = setmetatable({
        _systems = {},
        _pools = {},
        _emitDepth = 0,
    }, World)

    local systems = {}
    for _, system in ipairs{...} do
        system = newSystem(system, world)
        table.insert(world._systems, system)

        table.insert(systems, system)
        if system.name then systems[system.name] = system end
    end

    return world, systems
end

--adding  entities simply wraps them with a metatable
--such that the world is updated when keys are added or removed
function World:Entity(e)
    e = e or {}
    if e._world then error("Entity already added to a world", 2) end
    --ensure removed and readded entities aren't immediately removed again
    e.dead = nil

    local components = {}
    for k, v in pairs(e) do
        components[k] = v
        e[k] = nil
    end
    e._components = components
    e._world = self
    setmetatable(e, Entity)

    worldRecheckEntity(self, e)
    return e
end

--on removal simply remove the wrapper, leaving the entity otherwise untouched
local function removeEntity(e)
    e._world = nil
    setmetatable(e, nil)
    for k, v in pairs(e._components) do e[k] = v end
    e._components = nil
end

function worldRecheckEntity(world, e)
    for _, pool in ipairs(world._pools) do
        pool:recheck(e)
    end
    if e.dead then removeEntity(e) end
end

function World:emit(event, ...)
    self._emitDepth = self._emitDepth + 1

    for _, system in ipairs(self._systems) do
        if type(system[event]) == "function" then

            if self._emitDepth == 1 then
                for _, pool in ipairs(self._pools) do
                    pool:update()
                end
            end
            system[event](system, ...)
        end
    end

    self._emitDepth = self._emitDepth - 1
end

---------------------------------------------

local getPool
function newSystem(def, world)

    local s = { name = def.name, getWorld = function() return world end }

    if #def > 0 then def.pool = def.pool or def end

    for poolName, v in pairs(def) do
        if type(v) == "table" then
            local pool = getPool(v, world, poolName, def.name)
            s[poolName] = pool.accessor
            table.insert(pool.listeners, s)
        end
    end

    def.__index = def
    setmetatable(s, def)

    if s.init then s:init() end
    return s
end

local poolErr
function getPool(filter, world, poolName, systemName)

    if #filter <= 0 then poolErr(poolErr, systemName) end
    for _, v in ipairs(filter) do
        if type(v) ~= "string" then poolErr(poolName, systemName) end
    end

    table.sort(filter)
    local hash = table.concat(filter, ",")
    local existingPool = world._pools[hash]
    if existingPool then return existingPool end

    local pool = Pool:new(filter)
    world._pools[hash] = pool
    table.insert(world._pools, pool)
    return pool
end

function poolErr(poolName, systemName)
    error(
        ("Invalid pool definition for %s, pool '%s'. must be a table of keys")
        :format(systemName and ("system '%s'"):format(systemName) or "unnamed system", poolName)
    , 4)
end

return newWorld
--[[pod_format="raw",created="2024-04-07 18:38:25",modified="2024-04-13 04:21:06",revision=2156]]
-- able's ECS framework v1.0

-- CONSTANTS --

-- By default this is 4, which means you can register up to 256 components.
-- If you need more, you can increase the number, but this comes at a perfomance cost.
local BITMASK_NUMBERS = 4
local MAX_COMPONENT_TYPES = 64*BITMASK_NUMBERS

-- DATA/CACHING --

ecs = {}

-- All active entities in the game
local entities = {}
-- Array of all entities which have been requested to be destroyed.
local entities_to_destroy = {}

-- This table indicates which systems are interested in a particular component.
-- Keys are names of components, values are arrays of system caches.
local comp_caches = {}
-- Each registered component increments this. It is used to create IDs for bitmasking.
local comp_id_counter = 0

-- BITMASK --

-- Takes in a component name.
-- Returns the bit and array offset which corresponds
-- to a particular component id.
local function get_bitmask_bit(key)
	local id = comp_caches[key].id
	return id%64,flr(id/64)+1
end

-- The metatable for bitmasks.
local bitmask_meta = {
	-- Adds a bit to the bitmask corresponding to the component.
	-- Takes in a component key.
	add = function(self,key)
		local bit,offset = get_bitmask_bit(key)
		self[offset] = (self[offset] or 0)|(1<<bit)
	end,
	
	-- Removes a bit from the bitmask corresponding to the component.
	-- Takes in a component key.
	remove = function(self,key)
		local bit,offset = get_bitmask_bit(key)
		self[offset] = self[offset]&(~(1<<bit))
	end,
	
	-- Takes in the bitmask to check, the bitmask of the included component keys,
	-- and the bitmask of the excluded component keys.
	-- Returns true if the bitmask satisifies the query.
	match = function(self,include,exclude)
		for i = 1,BITMASK_NUMBERS do
			local include_num = include[i]
			local exclude_num = exclude[i]
			local self_num = self[i]
			
			if not (self_num&include_num == include_num
				and self_num&exclude_num == 0)
			then return false end
		end
		return true
	end,
}
bitmask_meta.__index = bitmask_meta

local function new_bitmask()
	local o = {}
	for i = 1,BITMASK_NUMBERS do
		o[i] = 0
	end
	setmetatable(o,bitmask_meta)
	return o
end

-- ENTITIES --

-- The metatable for the ref function on every entity.
-- It makes the value reference in the ref weak, and allows calling
-- the table to get the reference.
local ref_meta = {
	__mode = "v",
	__call = function(self)
		return self.entity
	end
}

-- Tells each system which is interested in a particular component that an entity
-- has changed, and its query cache is out of date.
-- Takes an entity and the name of the component that was added/removed.
local function update_query_cache(entity,key)
	for cache in all(comp_caches[key]) do
		cache.changed_entities[entity] = true
	end
end

-- Creates and returns a new entity.
ecs.ent = function()
	local entity = {
		-- Keys are component names, values are components.
		comps = {},
		-- Array of keys. Represents all components which need to be removed before
		-- the next system call executes.
		to_remove = {},
		-- Bitmask of all components attached to this entity.
		bitmask = new_bitmask(),
		
		-- Adds a new component to the entity.
		-- Takes a component and its name.
		-- Returns self for chaining.
		add = function(self,comp,key)
			self.comps[key] = comp
			update_query_cache(self,key)
			self.bitmask:add(key)
			
			return self
		end,
		
		-- Removes a component from the entity.
		-- Takes the name of the component to remove.
		-- Returns self for chaining.
		remove = function(self,key)
			-- Deferred so data isn't removed in the middle of system execution.
			add(self.to_remove,key)
			update_query_cache(self,key)
			self.bitmask:remove(key)
			
			return self
		end,
		
		-- Destroys the entity.
		-- This is the one you want during system execution.
		destroy = function(self)
			add(entities_to_destroy,self)
		end,
		
		-- Destroys the entity.
		-- This is the one you want outside of system execution.
		destroy_immediate = function(self)
			-- This will remove the components from the systems' caches. Without it,
			-- systems would keep executing on this entity's components.
			for k in pairs(self.comps) do
				self:remove(k)
			end
			
			-- Maintains a dense array by replacing this entity's index with the last
			-- entity in the array, and then removing the last entry.
			local index = self.index
			entities[index] = entities[#entities]
			entities[index].index = index
			deli(entities)
		end,
		
		-- Creates and returns a weak reference to the entity.
		ref = function(self)
			local o = {entity = self}
			setmetatable(o,ref_meta)
			return o
		end
	}
	
	add(entities,entity)
	entity.index = #entities -- Used for fast deletion in the entities table.
	
	return entity
end

-- COMPONENTS --

-- Creates and registers a new component type.
-- Takes an optional table to add the result to, the name of the component,
-- and a function for creating that component.
-- Returns a function for invoking the system.
ecs.comp = function(tab,key,func)
	if not func then tab,key,func = nil,tab,key end -- First arg is optional.
	
	if comp_id_counter >= MAX_COMPONENT_TYPES then
		assert(false, "Cannot register more than "..MAX_COMPONENT_TYPES.." component types.")
	end
	
	-- We want this key initialized ASAP, and we also wanna record the id somewhere
	-- we can associate it with this component. Win win.
	comp_caches[key] = {id = comp_id_counter}
	comp_id_counter = comp_id_counter+1
	
	-- We wrap this function so that entity:add can know the key of the components
	-- it gets passed. End user shouldn't have to enter this manually.
	local output = function(...)
		return func(...),key
	end
	-- So if you're putting it in a table, you don't have to write the key twice.
	if tab then tab[key] = output end
	-- But if you want, you can still get the function directly.
	return output
end

-- SYSTEMS --

-- Registers a new system.
-- Takes an array of component keys which are included,
-- an optional array of component keys which are excluded,
-- and the system function to execute, which is provided a query iterator.
ecs.sys = function(include,exclude,func)
	-- exclude is an optional arg.
	if not func then
		func = exclude
		exclude = {}
	end
	
	-- Each system has a cache of entities which match the query.
	-- To invalidate an entity in the cache, it is added to changed_entities.
	local cache = {
		changed_entities = {},
		entities = {},
	}
	
	-- Cache the bitmasks so we can perform fast queries.
	local include_bitmask = new_bitmask()
	local exclude_bitmask = new_bitmask()
	
	for key in all(include) do
		-- So entities can inform this system of cache invalidation.
		add(comp_caches[key],cache)
		include_bitmask:add(key)
	end
	for key in all(exclude) do
		add(comp_caches[key],cache)
		exclude_bitmask:add(key)
	end
	
	-- This function returns another function which tacks on
	-- lots of query and caching functionality.
	return function()
		local matches = cache.entities
		
		for entity in pairs(cache.changed_entities) do
			-- Clean up the entity's deleted components.
			for key in all(to_remove) do
				entity.comps[key] = nil
			end
			-- Recheck if entities that have changed match the query.
			local match = entity.bitmask:match(include_bitmask,exclude_bitmask)
			matches[entity] = match or nil
		end
		
		cache.changed_entities = {}
		
		local request_count = #include -- Why bother getting this more than once?
		local results = {} -- We reuse this across query iterations.
		
		local entity = nil -- Technically our enumerator. It's also our data.
		
		-- func is provided an iterator over each match.
		func(function()
			entity = next(matches,entity)
			if not entity then return end
			
			local comps = entity.comps
			for i_comp,key in ipairs(include) do
				results[i_comp] = comps[key]
			end
			results[request_count+1] = entity
			
			return unpack(results)
		end)
		
		-- Clean up any entities which were deleted during execution.
		for entity in all(entities_to_destroy) do
			entity:destroy_immediate()
		end
		entities_to_destroy = {}
	end
end
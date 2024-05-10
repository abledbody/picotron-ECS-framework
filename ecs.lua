--[[pod_format="raw",created="2024-04-07 18:38:25",modified="2024-05-10 01:34:49",revision=2161]]
-- able's ECS framework v2.1

ecs = {}

-- BITMASK --

-- Retrieves the bitmask bit for a given key in the world's component caches.
-- world: The world object containing the component caches.
-- key: key The key for which to retrieve the bitmask bit.
-- Returns: The offset of the bit within the 64-bit integer and the index of that integer.
local function get_bitmask_bit(world,key)
	local id = world.comp_caches[key].id
	return id%64,flr(id/64)+1
end

-- The metatable for bitmasks.
local bitmask_meta = {
	-- Adds a bit to the bitmask corresponding to the component.
	-- key: Name of the component type.
	add = function(self,key)
		local bit,offset = get_bitmask_bit(self.world,key)
		self[offset] = (self[offset] or 0)|(1<<bit)
	end,
	
	-- Removes a bit from the bitmask corresponding to the component.
	-- key: Name of the component type.
	remove = function(self,key)
		local bit,offset = get_bitmask_bit(self.world,key)
		self[offset] = self[offset]&(~(1<<bit))
	end,
	
	-- include: Bitmask of the components which must be included.
	-- exclude: Bitmask of the components which must be excluded.
	-- Returns: true if the bitmask satisifies the query.
	match = function(self,include,exclude)
		for i = 1,self.world.bitmask_size do
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

local function new_bitmask(world)
	local o = {world = world}
	for i = 1,world.bitmask_size do
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
		return self.entity and not self.entity.destroyed and self.entity
	end
}

-- Creates and returns a new entity.
-- world: The world where the entity will exist.
-- Returns: The entity.
local function ent(world)
	local entity = {
		world = world,
		-- A map of all components on the entity.
		-- Keys are component type names, values are components.
		-- Can be used to fetch optional components or the components of
		-- referenced entities during system execution.
		comps = {},
		-- Array of keys. Represents all components which need to be removed before
		-- the next system call executes.
		to_remove = {},
		-- Bitmask of all components attached to this entity.
		bitmask = new_bitmask(world),
		destroyed = false,
		
		-- Adds a component to the entity. 
		-- Calling a function created by `ecs.comp` will return both arguments at once.
		-- comp: The component to add.
		-- key: The name of the component type.
		-- Returns: The entity, for chaining.
		add = function(self,comp,key)
			self.comps[key] = comp
			self.world:update_query_cache(self,key)
			self.bitmask:add(key)
			
			return self
		end,
		
		-- Removes a component from the entity. Note that the act of removing it from
		-- the `entity.comps` table is deferred until the next system execution call.
		-- key: The name of the component type.
		-- Returns: The entity, for chaining.
		remove = function(self,key)
			-- Deferred so data isn't removed in the middle of system execution.
			add(self.to_remove,key)
			self.world:update_query_cache(self,key)
			self.bitmask:remove(key)
			
			return self
		end,
		
		-- Queues the entity for destruction. Use this during system execution.
		destroy = function(self)
			add(self.world.entities_to_destroy,self)
		end,
		
		-- Destroys the entity. Use this outside of system execution.
		destroy_immediate = function(self)
			-- This will remove the components from the systems' caches. Without it,
			-- systems would keep executing on this entity's components.
			for key in pairs(self.comps) do
				self.world:update_query_cache(self,key)
			end
			
			-- Maintains a dense array by replacing this entity's index with the last
			-- entity in the array, and then removing the last entry.
			local entities = self.world.entities
			local index = self.index
			local replacement = deli(entities)
			replacement.index = index
			entities[index] = replacement
			
			self.destroyed = true
		end,
		
		-- Creates a weak reference to the entity.
		-- Useful for referencing entities from other entities.
		-- Returns: A callable table. When called, it will return the entity if 
		-- it still exists, or nil if not.
		ref = function(self)
			local o = {entity = self}
			setmetatable(o,ref_meta)
			return o
		end
	}
	
	local entities = world.entities
	add(entities,entity)
	entity.index = #entities -- Used for fast deletion in the entities table.
	
	return entity
end

-- COMPONENTS --

-- The metatable for components types.
-- This allows the component to be called as its own constructor
local comp_meta = {
	__call = function(self,...)
		return self.constructor(...),self.key
	end,
}

-- Registers a component type with the world.
-- world: The world object to register the component with.
-- comp_type: The component type to register.
-- Returns: The world object, for chaining.
local function reg_comp(world,comp_type)
	local comp_id_counter,max_components = world.comp_id_counter,world.max_components
	if comp_id_counter >= max_components then
		error("Cannot register more than "..max_components.." component types.")
	end
	
	-- We want this key initialized ASAP, and we also wanna record the id somewhere
	-- we can associate it with this component. Win win.
	world.comp_caches[comp_type.key] = {id = comp_id_counter}
	world.comp_id_counter += 1
	
	return world
end

-- Creates a new component type.
-- [optional] world: The world object to register the component with.
-- [optional] tab: The table to put the component in.
-- key: The name of the component type.
-- constructor: The function which creates a new instance of the component.
-- Returns: A component type table which can be called to create new components.
function ecs.comp(_a,_b,_c,_d)
	-- world and tab are optional args.
	local world,tab,key,constructor
	if not _c then
		world,tab,key,constructor = nil,nil,_a,_b
	elseif not _d then
		-- comp_id_counter is an indication of being a world table.
		if world.comp_id_counter then
			world,tab,key,constructor = _a,nil,_b,_c
		else
			world,tab,key,constructor = nil,_a,_b,_c
		end
	else
		world,tab,key,constructor = _a,_b,_c,_d
	end
	
	local output = {
		key = key,
		constructor = constructor,
	}
	-- Making it possible to call this table as if it were a function.
	setmetatable(output,comp_meta)
	if world then world:reg_comp(output) end
	
	-- So if you're putting it in a table, you don't have to write the key twice.
	if tab then tab[key] = output end
	-- But if you want, you can still get the function directly.
	return output
end

-- SYSTEMS --

-- Registers a system with the world.
-- world: The world object to register the system with.
-- system_data: The system data to register.
-- Returns: The world object, for chaining.
local function reg_sys(world,system_data)
	-- Each system has a cache of entities which match the query.
	-- To invalidate an entity in the cache, it is added to changed_entities.
	local cache = {
		changed_entities = {},
		entities = {},
	}
	
	local comp_caches = world.comp_caches
	local include,exclude,func = system_data.include,system_data.exclude,system_data.func
	
	-- Cache some bitmasks so we can match entities quickly.
	local include_bitmask = new_bitmask(world)
	local exclude_bitmask = new_bitmask(world)
	
	-- Add the system's cache to each component's list of caches, and simultaneously
	-- build the bitmasks for the query.
	for key in all(include) do
		local cache_list = comp_caches[key]
		if not cache_list then
			error("System includes component '"..key.."' which must be registered first.")
		end
		add(comp_caches[key],cache)
		include_bitmask:add(key)
	end
	for key in all(exclude) do
		local cache_list = comp_caches[key]
		if not cache_list then
			error("System includes component '"..key.."' which must be registered first.")
		end
		add(comp_caches[key],cache)
		exclude_bitmask:add(key)
	end
	
	local entity_result_index = #include+1 -- Why bother getting this more than once?
	local results = {} -- We reuse this across query iterations.
	-- Pulling double duty as the enumerator and the entity in the query.
	local entity = nil
	
	-- All of this is basically just to wrap func so that it can do housekeeping
	-- and receive the query iterator.
	world.systems[system_data] = function()
		-- First we go through and make sure the cache is up to date.
		local matches = cache.entities
		
		for entity in pairs(cache.changed_entities) do
			if entity.destroyed then
				matches[entity] = nil
			else
				-- Clean up the entity's deleted components.
				for key in all(entity.to_remove) do
					entity.comps[key] = nil
				end
				entity.to_remove = {}
				-- Recheck if entities that have changed match the query.
				local match = entity.bitmask:match(include_bitmask,exclude_bitmask)
				matches[entity] = match or nil
			end
		end
		
		cache.changed_entities = {}
		
		-- Then we execute func with the query iterator.
		func(function()
			entity = next(matches,entity)
			if not entity then return end
			
			local comps = entity.comps
			for i_comp,key in ipairs(include) do
				results[i_comp] = comps[key]
			end
			results[entity_result_index] = entity
			
			return unpack(results)
		end)
		
		-- And finally clean up any entities which were deleted during execution.
		world:purge_entities()
	end
	
	return world
end

-- Creates a new set of system data.
-- [optional] world: The world object to register the system with.
-- include: The components which entities must have to be included in the query.
-- [optional] exclude: The components which entities must not have to be included in the query
-- func: The function which processes receives the query and processes the entities.
-- Returns: The system data.
function ecs.sys(_a,_b,_c,_d)	
	-- world and exclude are optional args
	local world,include,exclude,func
	if not _c then
		world,include,exclude,func = nil,_a,{},_b
	elseif not _d then
		-- comp_id_counter is an indication of being a world table.
		if _a.comp_id_counter then
			world,include,exclude,func = _a,_b,{},_c
		else
			world,include,exclude,func = nil,_a,_b,_c
		end
	else
		world,_include,exclude,func = _a,_b,_c,_d
	end
	
	local system_data = {
		include = include,
		exclude = exclude,
		func = func,
	}
	
	if world then world:reg_sys(system_data) end
	
	return system_data
end

-- WORLDS --

-- Creates a new world object.
-- [optional] bitmask_size: The number of 64-bit integers to use for bitmasks. Default is 4.
-- Higher values allow more components, but at a small performance cost.
-- Returns: The world object.
function ecs.world(bitmask_size)
	-- By default this is 4, which means you can register up to 256 components.
	bitmask_size = bitmask_size or 4
	return {
		-- The number of 64-bit integers to use for bitmasks.
		bitmask_size = bitmask_size,
		-- The maximum number of components which can be registered to this world.
		max_components = bitmask_size*64,
		
		-- All active entities in the game
		entities = {},
		-- Array of all entities which have been requested to be destroyed.
		entities_to_destroy = {},
		
		-- This table indicates which systems are interested in a particular component.
		-- Keys are names of components, values are arrays of system caches.
		comp_caches = {},
		-- Each registered component increments this. It is used to create IDs for bitmasking.
		comp_id_counter = 0,
		
		-- Keys are system data, values are the system functions.
		systems = {},
		
		-- Executes a system for the world.
		-- system_data: The system data to execute.
		-- ...: Additional arguments to pass to the system.
		-- Returns: The world object, for chaining.
		run = function(self,system_data,...)
			self.systems[system_data](...)
			return self
		end,

		-- Tells each system which is interested in a particular component that an entity
		-- has changed, and its query cache is out of date.
		-- entity: The entity which has changed.
		-- key: The name of the component which has changed.
		update_query_cache = function(self,entity,key)
			for cache in all(self.comp_caches[key]) do
				cache.changed_entities[entity] = true
			end
		end,
		
		-- Destroys all entities which have been queued for destruction.
		purge_entities = function(self)
			for entity in all(self.entities_to_destroy) do
				entity:destroy_immediate()
			end
			self.entities_to_destroy = {}
		end,
		
		comp = ecs.comp,
		sys = ecs.sys,
		reg_comp = reg_comp,
		reg_sys = reg_sys,
		ent = ent,
	}
end
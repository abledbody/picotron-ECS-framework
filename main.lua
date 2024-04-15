--[[pod_format="raw",created="2024-04-13 03:11:15",modified="2024-04-15 02:45:43",revision=728]]
include("ecs.lua")

local world = ecs.world(1)

-- Components

local c = {}

world:comp(c,"position",function(x,y)
	return {
		x = x or 0,
		y = y or 0,
	}
end)

world:comp(c,"velocity",function(x,y)
	return {
		x = x or 0,
		y = y or 0,
	}
end)

world:comp(c,"gravity",function(acceleration)
	return {acceleration = acceleration}
end)

world:comp(c,"death_timer",function(time)
	return {time = time}
end)

world:comp(c,"ball",function(color)
	return {color = color}
end)
world:comp(c,"emitter",function(quantity)
	return {quantity = quantity}
end)

-- Systems

local s = {}

s.velocity = world:sys(
	{"position","velocity"},
	function(query)
		for position,velocity in query do
			position.x = position.x+velocity.x
			position.y = position.y+velocity.y
		end
	end
)

s.gravity = world:sys(
	{"velocity","gravity"},
	function(query)
		for velocity,gravity in query do
			velocity.y = velocity.y+gravity.acceleration
		end
	end
)

s.death_timer = world:sys(
	{"death_timer"},
	function(query)
		for death_timer,entity in query do
			death_timer.time = death_timer.time-1
			if death_timer.time <= 0 then
				entity:destroy()
			end
		end
	end
)

local function make_ball(x,y,vx,vy)
	world:ent()
		:add(c.ball(rnd(30)+1))
		:add(c.position(x,y))
		:add(c.velocity(vx,vy))
		:add(c.gravity(0.2))
		:add(c.death_timer(60))
end

s.emit_balls = world:sys(
	{"position","emitter"},
	function(query)
		for position,emitter in query do
			for i=1,emitter.quantity do
				make_ball(position.x,position.y,rnd(8)-4,rnd(4)-2)
			end
		end
	end
)

s.draw_balls = world:sys(
	{"position","ball"},
	function(query)
		for position,ball in query do
			circfill(position.x,position.y,4.5,ball.color)
		end
	end
)

s.stop_balls = world:sys(
	{"position","velocity","gravity"},
	function(query)
		for position,_,_,entity in query do
			if position.x <= 10
				or position.x >= 470
				or position.y <= 10
				or position.y >= 260
			then
				position.x = mid(position.x,10,470)
				position.y = mid(position.y,10,260)
				entity:remove("velocity","gravity")
			end
		end
	end
)

-- Setup
local emitter
function _init()
	emitter = world:ent()
		:add(c.emitter(5))
		:add(c.position(240,20))
end

function _update()
	world:run(s.death_timer)
	local pos = emitter.comps.position
	pos.x,pos.y = mouse()
	world:run(s.emit_balls)
		:run(s.velocity)
		:run(s.gravity)
		:run(s.stop_balls)
end

function _draw()
	cls()
	world:run(s.draw_balls)
	print("cpu:"..string.sub(stat(1)*100,1,5).."%",1,1,7)
	print("entities:"..#world.entities)
end
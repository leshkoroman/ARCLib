--Random utilities

local thinkFuncs = {}
local thinkThreads = {}
local thinkDefs = {}
local thinkPasses = {}

local toBeDeleted = {}

local lastTime = 0
local interval = engine.TickInterval()
local maxTime = interval*0.25 -- This value was chosen as a result of a lot of and trail-and error.
-- Honeslty, if GMod Lua had proper async operations, I wouldn't feel the need to do this. Imagine if all expensive operations like traces and file IO were async that'd be great...
-- Yet here I am, attempting to distribute the workload for my addons across ticks. 

local tickTime = maxTime
hook.Add("Tick","ARCLib Multithink",function()
	if (coroutine.running()) then
		print("SOMETHING WENT HORRIBLY WRONG WE SHOULDN'T BE IN A COROUTINE!! AAAAAAAAAAAAAAAAAAAAAAAAAAA")
		hook.Remove("Tick","ARCLib Multithink")
		return
	end
	
	local stime = SysTime()
	for k,v in pairs(thinkFuncs) do
		if !thinkThreads[k] then -- Check if it's dead here too?
			thinkThreads[k] = coroutine.create(v) 
		end
	end
	
	while SysTime() - stime < tickTime do
		local anyalive = false
		for k,v in pairs(thinkThreads) do
			if (thinkPasses[k]) then continue end -- I know continue is a GLua keyword, but when is ARCLib going to used in an environment outside of GMod anyway?
			if (coroutine.status(v) == "dead") then
				thinkThreads[k] = nil
			else
				anyalive = true
				local succ,err = coroutine.resume(v)
				if succ then
					if (err) then
						thinkPasses[k] = true
					end
				else
					ErrorNoHalt( "[ARCLib think failed!] "..thinkDefs[k].."\n\t"..err.."\n" )
					thinkThreads[k] = nil
				end
			end
		end
		if not anyalive then
			break
		end
	end
	table.Empty(thinkPasses)
	for k,v in pairs(toBeDeleted) do
		if (thinkThreads[k] == nil) then
			thinkFuncs[k] = nil
			thinkDefs[k] = nil
			toBeDeleted[k] = nil
		end
	end
	local a = interval-(stime-lastTime)

	tickTime = tickTime + a
	if tickTime > maxTime then
		tickTime = maxTime
	elseif tickTime < 0 then
		tickTime = 0.00001
	end
	--[[
	print("interval:",interval)
	print("tickTime:",tickTime)
	print("thinks:",SysTime()-stime)
	print("actual:",stime-lastTime)
	--]]
	lastTime = stime
end)
function ARCLib.GetThinkFuncs()
	return thinkFuncs
end

function ARCLib.AddThinkFunc(name,func)
	thinkFuncs[name] = func
	local info = debug.getinfo(func)
	thinkDefs[name] = info.source..":"..info.linedefined
end
function ARCLib.RemoveThinkFunc(name,force)
	if (force) then
		thinkThreads[name] = nil
		thinkFuncs[name] = nil
		thinkDefs[name] = nil
		toBeDeleted[name] = nil
	else
		toBeDeleted[name] = true
	end
end

-- Gets the IP of the server
function ARCLib.GetIP()

	local hostip = GetConVarString( "hostip" ) -- GetConVarNumber is inaccurate
	hostip = tonumber( hostip )
	if (!hostip) then return "127.0.0.1" end -- Single Player game!
	local ip = {}
	ip[ 1 ] = bit.rshift( bit.band( hostip, 0xFF000000 ), 24 )
	ip[ 2 ] = bit.rshift( bit.band( hostip, 0x00FF0000 ), 16 )
	ip[ 3 ] = bit.rshift( bit.band( hostip, 0x0000FF00 ), 8 )
	ip[ 4 ] = bit.band( hostip, 0x000000FF )

	return table.concat( ip, "." )
end


function ARCLib.ConvertColor(col)
	assert( ARCLib.IsColor(col), "ARCLib.ConvertColor: I wanted a color, but I got some sort of wierd "..type( col ).." thing..." )
	return col.r, col.g, col.b, col.a
end



function ARCLib.AddDir(dir) -- recursively adds everything in a directory to be downloaded by client. (Taken from old GMod wiki, Fixed by ARitz Cracker)
	if SERVER then
		local files, directories = file.Find( dir.."/*", "GAME" )
		if !files then return end
		for _,v in pairs(files) do
			resource.AddFile(dir.."/"..v)
		end
		for _, fdir in pairs(directories) do
			if fdir != ".svn" && fdir != "_svn" then -- Don't spam people with useless .svn folders
				ARCLib.AddDir(dir.."/"..fdir) -- Recursion ho!
			end
		end
	else
		MsgN("Did you really try to add resources on the client, you dolt?")
	end
end


local forEachTabs = {}
function ARCLib.ForEachAsync(tab,func,done)
	local total = 0;
	for k,v in pairs(tab) do
		total = total + 1;
	end
	if (total == 0) then
		timer.Simple(0,done)
	else
		table.insert(forEachTabs,{tab,func,done,total})
	end
end
ARCLib.AddThinkFunc("ARCLib ForEachAsync",function()
	local i = 0
	while i < #forEachTabs do
		i = i + 1
		local tab = forEachTabs[i][1]
		local func = forEachTabs[i][2]
		local done = forEachTabs[i][3]
		local total = forEachTabs[i][4]
		local progress = 0
		for k,v in pairs(tab) do
			func(k,v,function()
				progress = progress + 1
				if (progress==total) then
					timer.Simple(0,done)
				end
			end)
			coroutine.yield()
		end
	end
	if i > 0 then
		table.Empty(forEachTabs)
	end
end)

function ARCLib.RGBToCMY(col)
	return {c = (1 - col.r / 255)*255,m = (1 - col.g / 255)*255,y = (1 - col.b / 255)*255,a = col.a}
end

function ARCLib.ColorNegative(col)
	local tab = ARCLib.RGBToCMY(col)
	return Color(tab.c,tab.m,tab.y,tab.a)
end

function ARCLib.IsColor(col) -- Colors can be tables and util.JSONToTable doesn't return colours so AAAAAAAAAAH
	if !istable(col) then return false end
	return table.Count(col) == 4 && col.r && col.g && col.b && col.a
end


function ARCLib.ValidVariable(var,checker,default)
	if checker then
		return var
	else
		return default
	end
end

function ARCLib.IsVersion(version,addon)
	
	
	addon = addon or "ARCLib"
	if type(_G[addon]) != "table" then return false end
	local currentversion = _G[addon].Version
	if type(currentversion) != "string" then return false end
	local vertab = {string.match(version,"([0-9]*).([0-9]*).([0-9]*)")}
	local curvertab = {string.match(currentversion,"([0-9]*).([0-9]*).([0-9]*)")}
	curvertab[1] = tonumber(curvertab[1])
	curvertab[2] = tonumber(curvertab[2])
	curvertab[3] = tonumber(curvertab[3])
	vertab[1] = tonumber(vertab[1])
	vertab[2] = tonumber(vertab[2])
	vertab[3] = tonumber(vertab[3])
	
	if #curvertab != 3 then return false end
	if #vertab != 3 then return false end
	for i=1,3 do
		if !vertab[i] || !curvertab[i] then return false end
	end
	if curvertab[1] > vertab[1] then
		return true
	end
	if curvertab[1] == vertab[1] then
		if curvertab[2] > vertab[2] then
			return true
		end
		if curvertab[2] == vertab[2] then
			if curvertab[3] >= vertab[3] then
				return true
			end
		end
	end
	return false
end
local keys = {}
for i=BUTTON_CODE_NONE,BUTTON_CODE_LAST do
	for k,v in pairs(_G) do
		if isstring(k) and string.StartWith( k, "KEY_" ) and v == i then
			keys[v] = string.sub( k, 5 )
		end
	end
end
function ARCLib.HumanReadableKey(key)
	return keys[key] or "KEY_NONE"
end


if CLIENT then
	net.Receive( "ARCLib_Notify", function(length)
		local msg = net.ReadString() 
		local typ = net.ReadUInt(4)
		local time = net.ReadUInt(16)
		local snd = tobool(net.ReadBit())
		notification.AddLegacy(msg,typ,time) 
		if snd then
			if typ == NOTIFY_ERROR then
				LocalPlayer():EmitSound("buttons/button8.wav" )
			else
				LocalPlayer():EmitSound("ambient/water/drip"..math.random(1, 4)..".wav" )
			end
		end
	end)

else
	NOTIFY_GENERIC = 0 --These constants are only pre-defined on the client. So if we're using NotifyPlayer, then better to do it here!
	NOTIFY_ERROR = 1
	NOTIFY_UNDO = 2
	NOTIFY_HINT = 3
	NOTIFY_CLEANUP = 4
	util.AddNetworkString( "ARCLib_Notify" )
	-- Player, Message, Type (NOTIFY_), time (seconds), Should we play a sound or not?
	function ARCLib.NotifyPlayer(ply,str,typ,time,snd)
		net.Start("ARCLib_Notify")
		net.WriteString(str)
		net.WriteUInt(typ,4)
		net.WriteUInt(time,16)
		net.WriteBit(snd)
		net.Send(ply)
	end
	-- Message, Type (NOTIFY_), time (seconds), Should we play a sound or not?
	function ARCLib.NotifyBroadcast(str,typ,time,snd)
		net.Start("ARCLib_Notify")
		net.WriteString(str)
		net.WriteUInt(typ,4)
		net.WriteUInt(time,16)
		net.WriteBit(snd)
		net.Broadcast()
	
	end

end

-- Now this code allows clients to play sound on other clients. The reasoning behind this is that I want a sound to be played on one client, but a different sound to be played on other clients.
-- The sound must be validated with ARCLib.AddToSoundWhitelist before being sent by the client, though.

if SERVER then
	if timer.Exists( "ARCLib_SoundCheck" ) then
		timer.Destroy( "ARCLib_SoundCheck" )
	end
	timer.Create( "ARCLib_SoundCheck", 1, 0, function() 
		for k,v in pairs(player.GetAll()) do
			v.ARCLIB_SOUND_COUNT = 0;
		end
	end )
	timer.Start( "ARCLib_SoundCheck" ) 
	util.AddNetworkString( "ARCLib_Sound" )
	ARCLib.SoundWhitelist = ARCLib.SoundWhitelist or {}

	function ARCLib.AddToSoundWhitelist(_ent,_snd,_lvl,_ptch)
		local alreadyexists = false
		for k,v in ipairs(ARCLib.SoundWhitelist) do
			alreadyexists = (alreadyexists || (v.ent == _ent && v.snd == _snd && v.lvl == _lvl && v.ptch == _ptch))
		end
		if !alreadyexists then
			table.insert(ARCLib.SoundWhitelist,{ent = _ent,snd = _snd,lvl = _lvl,ptch = _ptch})
		end
	end
	
	net.Receive( "ARCLib_Sound", function(length,ply)
		if ply.ARCLIB_SOUND_COUNT && ply.ARCLIB_SOUND_COUNT > 5 then -- Can't blame a guy for trying. Every 0.2 seconds may still be annoying... 
			ply:Kick("Spamming Sound")
		end
		
		local ent = net.ReadEntity() 
		local snd = net.ReadString() 
		local lvl = net.ReadUInt(8)
		local ptch = net.ReadUInt(8)
		if !IsValid(ent) || ent:IsWorld() then return end
		local validsound = false
		
		for k,v in pairs(ARCLib.SoundWhitelist) do
			validsound = validsound or (v.ent == ent:GetClass() && v.snd == snd && v.lvl == lvl && v.ptch == ptch)
		end
		
		if validsound then
			net.Start("ARCLib_Sound")
			net.WriteEntity(ent)
			net.WriteString(snd)
			net.WriteUInt(lvl,8)
			net.WriteUInt(ptch,8)
			net.SendOmit(ply)
			if !ply.ARCLIB_SOUND_COUNT then
				ply.ARCLIB_SOUND_COUNT = 0
			end
			ply.ARCLIB_SOUND_COUNT = ply.ARCLIB_SOUND_COUNT + 1
		else
			ARCLib.MsgCL(ply,"ARCLib: Invalid sound. (Not on sound whitelist)")
		end
	end)

else
	local soundspam = 0
	timer.Create( "ARCLib_SoundCheck", 1.1, 0, function() 
		soundspam = 0
	end )
	timer.Start( "ARCLib_SoundCheck" ) 
	
	function ARCLib.PlaySoundOnOtherPlayers(snd,ent,lvl,ptch) -- Plays a sound on people's clients.
		if soundspam && soundspam < 4 then
			if !lvl then lvl = 75 end
			if !ptch then ptch = 100 end
			net.Start("ARCLib_Sound") -- Now I know any client can just do lua_run_cl with this, BUT IT'S SO USEFUL...
			net.WriteEntity(ent)
			net.WriteString(snd)
			net.WriteUInt(lvl,8)
			net.WriteUInt(ptch,8)
			net.SendToServer()
			--MsgN(soundspam)
		end
		soundspam = soundspam + 1
	end
	net.Receive( "ARCLib_Sound", function(length)
		local ent = net.ReadEntity() 
		local snd = net.ReadString() 
		local lvl = net.ReadUInt(8)
		local ptch = net.ReadUInt(8)
		if IsValid(ent) then
			sound.Play(snd, ent:GetPos(), lvl, ptch ) 
		end
	end)
end


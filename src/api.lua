--[[
	TODO
	HTTP api may be broken?
	including file handles.
]]
-- HELPER FUNCTIONS
local function lines(str)
	local t = {}
	local function helper(line) table.insert(t, line) return "" end
	helper((str:gsub("(.-)\r?\n", helper)))
	if t[#t] == "" then t[#t] = nil end
	return t
end

-- HELPER CLASSES/HANDLES
-- TODO Make more efficient, use love.filesystem.lines
local function HTTPHandle(contents, status)
	local closed = false
	local lineIndex = 1
	local handle
	handle = {
		close = function()
			closed = true
		end,
		readLine = function()
			if closed then return end
			local str = contents[lineIndex]
			lineIndex = lineIndex + 1
			return str
		end,
		readAll = function()
			if closed then return end
			if lineIndex == 1 then
				lineIndex = #contents + 1
				return table.concat(contents, '\n')
			else
				local tData = {}
				local data = handle.readLine()
				while data ~= nil do
					table.insert(tData, data)
					data = handle.readLine()
				end
				return table.concat(tData, '\n')
			end
		end,
		getResponseCode = function()
			return status
		end
	}
	return handle
end

local function FileReadHandle( path )
	local contents = {}
	for line in love.filesystem.lines(path) do
	  table.insert(contents, line)
	end
	local closed = false
	local lineIndex = 1
	local handle
	handle = {
		close = function()
			closed = true
		end,
		readLine = function()
			if closed then return end
			local str = contents[lineIndex]
			lineIndex = lineIndex + 1
			return str
		end,
		readAll = function()
			if closed then return end
			if lineIndex == 1 then
				lineIndex = #contents + 1
				return table.concat(contents, '\n')
			else
				local tData = {}
				local data = handle.readLine()
				while data ~= nil do
					table.insert(tData, data)
					data = handle.readLine()
				end
				return table.concat(tData, '\n')
			end
		end
	}
	return handle
end

local function FileBinaryReadHandle( path )
	local closed = false
	local File = love.filesystem.newFile( path, "r" )
	if File == nil then return end
	local handle = {
		close = function()
			closed = true
			File:close()
		end,
		read = function()
			if closed or File:eof() then return end
			return string.byte(File:read(1))
		end
	}
	return handle
end

local function FileWriteHandle( path, append )
	local closed = false
	local File = love.filesystem.newFile( path, append and "a" or "w" )
	if File == nil then return end
	local handle = {
		close = function()
			closed = true
			File:close()
		end,
		writeLine = function( data )
			if closed then error("Stream closed",2) end
			File:write(data .. (_conf.useCRLF == true and "\r\n" or "\n"))
		end,
		write = function ( data )
			if closed then error("Stream closed",2) end
			File:write(data)
		end,
		flush = function()
			if File.flush then
				File:flush()
			else
				File:close()
				File = love.filesystem.newFile( path, "a" )
			end
		end
	}
	return handle
end

local function FileBinaryWriteHandle( path, append )
	local closed = false
	local File = love.filesystem.newFile( path, append and "a" or "w" )
	if File == nil then return end
	local handle = {
		close = function()
			closed = true
			File:close()
		end,
		write = function ( data )
			if closed then return end
			if type(data) ~= "number" then return end
			File:write(string.char(math.max(math.min(data,255),0)))
		end,
		flush = function()
			if File.flush then
				File:flush()
			else
				File:close()
				File = love.filesystem.newFile( path, "a" )
			end
		end
	}
	return handle
end

api = {}

api.term = {}
function api.term.clear()
	for y = 1, Screen.height do
		for x = 1, Screen.width do
			Screen.textB[y][x] = " "
			Screen.backgroundColourB[y][x] = api.comp.bg
			Screen.textColourB[y][x] = 1 -- Don't need to bother setting text color
		end
	end
	Screen.dirty = true
end
function api.term.clearLine()
	for x = 1, Screen.width do
		Screen.textB[api.comp.cursorY][x] = " "
		Screen.backgroundColourB[api.comp.cursorY][x] = api.comp.bg
		Screen.textColourB[api.comp.cursorY][x] = 1 -- Don't need to bother setting text color
	end
	Screen.dirty = true
end
function api.term.getSize()
	return Screen.width, Screen.height
end
function api.term.getCursorPos()
	return api.comp.cursorX, api.comp.cursorY
end
function api.term.setCursorPos(x, y)
	if not x or not y then return end
	api.comp.cursorX = math.floor(x)
	api.comp.cursorY = math.floor(y)
	Screen.dirty = true
end
function api.term.write( text )
	if not text then return end
	if api.comp.cursorY > Screen.height
		or api.comp.cursorY < 1 then return end

	for i = 1, #text do
		local char = string.sub( text, i, i )
		if api.comp.cursorX + i - 1 <= Screen.width
			and api.comp.cursorX + i - 1 >= 1 then
			Screen.textB[api.comp.cursorY][api.comp.cursorX + i - 1] = char
			Screen.textColourB[api.comp.cursorY][api.comp.cursorX + i - 1] = api.comp.fg
			Screen.backgroundColourB[api.comp.cursorY][api.comp.cursorX + i - 1] = api.comp.bg
		end
	end
	api.comp.cursorX = api.comp.cursorX + #text
	Screen.dirty = true
end
function api.term.setTextColor( num )
	if not COLOUR_CODE[num] then return end
	api.comp.fg = num
	Screen.dirty = true
end
function api.term.setBackgroundColor( num )
	if not COLOUR_CODE[num] then return end
	api.comp.bg = num
end
function api.term.isColor()
	return true
end
function api.term.setCursorBlink( bool )
	if type(bool) ~= "boolean" then error("Expected boolean",2) end
	api.comp.blink = bool
	Screen.dirty = true
end
function api.term.scroll( n )
	if type(n) ~= "number" then error("Expected number",2) end
	local textBuffer = {}
	local backgroundColourBuffer = {}
	local textColourBuffer = {}
	for y = 1, Screen.height do
		if y - n > 0 and y - n <= Screen.height then
			textBuffer[y - n] = {}
			backgroundColourBuffer[y - n] = {}
			textColourBuffer[y - n] = {}
			for x = 1, Screen.width do
				textBuffer[y - n][x] = Screen.textB[y][x]
				backgroundColourBuffer[y - n][x] = Screen.backgroundColourB[y][x]
				textColourBuffer[y - n][x] = Screen.textColourB[y][x]
			end
		end
	end
	for y = 1, Screen.height do
		if textBuffer[y] ~= nil then
			for x = 1, Screen.width do
				Screen.textB[y][x] = textBuffer[y][x]
				Screen.backgroundColourB[y][x] = backgroundColourBuffer[y][x]
				Screen.textColourB[y][x] = textColourBuffer[y][x]
			end
		else
			for x = 1, Screen.width do
				Screen.textB[y][x] = " "
				Screen.backgroundColourB[y][x] = api.comp.bg
				Screen.textColourB[y][x] = 1 -- Don't need to bother setting text color
			end
		end
	end
	Screen.dirty = true
end

function tablecopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else
        copy = orig
    end
    return copy
end

api.cclite = {}
api.cclite.peripherals = {}
function api.cclite.peripheralAttach( sSide, sType )
	if type(sSide) ~= "string" or type(sType) ~= "string" then
		error("Expected string, string",2)
	end
	if not peripheral[sType] then
		error("No virtual peripheral of type " .. sType,2)
	end
	if api.cclite.peripherals[sSide] then
		error("Peripheral already attached to " .. sSide,2)
	end
	api.cclite.peripherals[sSide] = peripheral[sType](sSide)
	if api.cclite.peripherals[sSide] ~= nil then
		table.insert(Emulator.eventQueue, {"peripheral",sSide})
	else
		error("No peripheral added",2)
	end
end
function api.cclite.peripheralDetach( sSide )
	if type(sSide) ~= "string" then error("Expected string",2) end
	if not api.cclite.peripherals[sSide] then
		error("No peripheral attached to " .. sSide,2)
	end
	api.cclite.peripherals[sSide] = nil
	table.insert(Emulator.eventQueue, {"peripheral_detach",sSide})
end
function api.cclite.call( sSide, sMethod, ... )
	if type(sSide) ~= "string" then error("Expected string",2) end
	if type(sMethod) ~= "string" then error("Expected string, string",2) end
	if not api.cclite.peripherals[sSide] then error("No peripheral attached",2) end
	return api.cclite.peripherals[sSide].ccliteCall(sMethod, ...)
end

api.http = {}
function api.http.request( sUrl, sParams )
	local http = HttpRequest.new()
	local method = sParams and "POST" or "GET"

	http.open(method, sUrl, true)

	if method == "POST" then
		http.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
   		http.setRequestHeader("Content-Length", string.len(sParams))
	end

	http.onReadyStateChange = function()
		if http.responseText then -- TODO: check if timed out instead
	        local handle = HTTPHandle(lines(http.responseText), http.status)
	        table.insert(Emulator.eventQueue, { "http_success", sUrl, handle })
	    else
	    	 table.insert(Emulator.eventQueue, { "http_failure", sUrl })
	    end
    end

    http.send(sParams)
end

api.os = {}
function api.os.clock()
	return math.floor(os.clock()*20)/20
end
function api.os.time()
	return Emulator.minecraft.time
end
function api.os.day()
	return Emulator.minecraft.day
end
function api.os.setComputerLabel(label)
	if type(label) ~= "string" and type(label) ~= "nil" then error("Expected string or nil",2) end
	api.comp.label = label
end
function api.os.getComputerLabel()
	return api.comp.label
end
function api.os.queueEvent( ... )
	local event = { ... }
	if type(event[1]) ~= "string" then error("Expected string",2) end
	table.insert(Emulator.eventQueue, event)
end
function api.os.startTimer( nTimeout )
	if type(nTimeout) ~= "number" then error("Expected number",2) end
	local timer = {
		expires = love.timer.getTime() + nTimeout,
	}
	table.insert(Emulator.actions.timers, timer)
	for k, v in pairs(Emulator.actions.timers) do
		if v == timer then return k end
	end
	return nil -- Error
end
function api.os.setAlarm( nTime )
	if type(nTime) ~= "number" then error("Expected number",2) end
	if nTime < 0 or nTime > 24 then
		error( "Number out of range: " .. tostring( nTime ) )
	end
	local currentDay = Emulator.minecraft.day
	local alarm = {
		time = nTime,
	}
	table.insert(Emulator.actions.alarms, alarm)
	for k, v in pairs(Emulator.actions.alarms) do
		if v == alarm then return k end
	end
	return nil -- Error
end
function api.os.shutdown()
	Emulator:stop()
end
function api.os.reboot()
	Emulator:stop( true ) -- Reboots on next update/tick
end

api.peripheral = {}
function api.peripheral.isPresent( sSide )
	if type(sSide) ~= "string" then error("Expected string",2) end
	return api.cclite.peripherals[sSide] ~= nil
end
function api.peripheral.getType( sSide )
	if type(sSide) ~= "string" then error("Expected string",2) end
	if api.cclite.peripherals[sSide] then return api.cclite.peripherals[sSide].getType() end
	return
end
function api.peripheral.getMethods( sSide )
	if type(sSide) ~= "string" then error("Expected string",2) end
	if api.cclite.peripherals[sSide] then return api.cclite.peripherals[sSide].getMethods() end
	return
end
function api.peripheral.call( sSide, sMethod, ... )
	if type(sSide) ~= "string" then error("Expected string",2) end
	if type(sMethod) ~= "string" then error("Expected string, string",2) end
	if not api.cclite.peripherals[sSide] then error("No peripheral attached",2) end
	return api.cclite.peripherals[sSide].call(sMethod, ...)
end
function api.peripheral.getNames()
	local names = {}
	for k,v in pairs(api.cclite.peripherals) do
		table.insert(names,k)
	end
	return names
end

api.fs = {}
function api.fs.combine(basePath, localPath)
	if type(basePath) ~= "string" or type(localPath) ~= "string" then
		error("Expected string, string",2)
	end
	local path = "/" .. basePath .. "/" .. localPath
	local tPath = {}
	for part in path:gmatch("[^/]+") do
   		if part ~= "" and part ~= "." then
   			if part == ".." and #tPath > 0 then
   				table.remove(tPath)
   			else
   				table.insert(tPath, part)
   			end
   		end
	end
	return table.concat(tPath, "/")
end

function api.fs.open(path, mode)
	if type(path) ~= "string" or type(mode) ~= "string" then
		error("Expected string, string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = api.fs.combine("", path)
	if mode == "r" then
		local sPath
		if love.filesystem.exists("data/" .. path) then
			sPath = "data/" .. path
		elseif love.filesystem.exists("lua/" .. path) then
			sPath = "lua/" .. path
		end
		if sPath == nil or sPath == "lua/bios.lua" then return end
		return FileReadHandle( sPath )
	elseif mode == "rb" then
		local sPath
		if love.filesystem.exists("data/" .. path) then
			sPath = "data/" .. path
		elseif love.filesystem.exists("lua/" .. path) then
			sPath = "lua/" .. path
		end
		if sPath == nil or sPath == "lua/bios.lua" then return end
		return FileBinaryReadHandle( sPath )
	elseif mode == "w" or mode == "a" then
		return FileWriteHandle("data/" .. path,mode == "a")
	elseif mode == "wb" or mode == "ab" then
		return FileBinaryWriteHandle("data/" .. path,mode == "ab")
	else
		error("Unsupported mode",2)
	end
end
function api.fs.list(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = api.fs.combine("", path)
	local res = {}
	if love.filesystem.exists("data/" .. path) then -- This path takes precedence
		res = love.filesystem.getDirectoryItems("data/" .. path)
	end
	if love.filesystem.exists("lua/" .. path) then
		for k, v in pairs(love.filesystem.getDirectoryItems("lua/" .. path)) do
			if v ~= "bios.lua" then table.insert(res, v) end
		end
	end
	return res
end
function api.fs.exists(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then return false end
	path = api.fs.combine("", path)
	if path == "bios.lua" then return false end
	return love.filesystem.exists("data/" .. path) or love.filesystem.exists("lua/" .. path)
end
function api.fs.isDir(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then return false end
	path = api.fs.combine("", path)
	return love.filesystem.isDirectory("data/" .. path) or love.filesystem.isDirectory("lua/" .. path)
end
function api.fs.isReadOnly(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	path = api.fs.combine("", path)
	return path == "rom" or string.sub(path, 1, 4) == "rom/"
end
function api.fs.getName(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local fpath, name, ext = string.match(path, "(.-)([^\\/]-%.?([^%.\\/]*))$")
	return name
end
function api.fs.getSize(path)
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = api.fs.combine("", path)
	if api.fs.exists(path) ~= true then
		error("No such file",2)
	end
	
	local sPath = nil
	if love.filesystem.exists("data/" .. path) then
		sPath = "data/" .. path
	elseif love.filesystem.exists("lua/" .. path) then
		sPath = "lua/" .. path
	end

	if love.filesystem.isDirectory( sPath ) then
		return 512
	end
	
	local File = love.filesystem.newFile( sPath, "r" )
	local size = File:getSize()
	File:close()
	if size == 0 then size = 512 end
	return math.ceil(size/512)*512
end

function api.fs.getFreeSpace(path)
	return math.huge
end

function api.fs.makeDir(path) -- All write functions are within data/
	if type(path) ~= "string" then
		error("Expected string",2)
	end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = api.fs.combine("", path)
	if path == "rom" or string.sub(path, 1, 4) == "rom/" then
		error("Access Denied",2)
	end
	return love.filesystem.createDirectory( "data/" .. path )
end

local function deltree(sFolder)
	local tObjects = love.filesystem.getDirectoryItems(sFolder)

	if tObjects then
   		for _, sObject in pairs(tObjects) do
	   		local pObject =  sFolder.."/"..sObject

			if love.filesystem.isDirectory(pObject) then
				deltree(pObject)
			end
			love.filesystem.remove(pObject)
		end
	end
	return love.filesystem.remove(sFolder)
end

local function copytree(sFolder, sToFolder)
	if not love.filesystem.isDirectory(sFolder) then
		love.filesystem.write(sToFolder, love.filesystem.read( sFolder ))
		return
	end
	love.filesystem.createDirectory(sToFolder)
	local tObjects = love.filesystem.getDirectoryItems(sFolder)

	if tObjects then
   		for _, sObject in pairs(tObjects) do
	   		local pObject =  sFolder.."/"..sObject
			local pToObject = sToFolder.."/"..sObject

			if love.filesystem.isDirectory(pObject) then
				love.filesystem.createDirectory(pToObject)
				copytree(pObject,pToObject)
			else
				love.filesystem.write(pToObject, love.filesystem.read( pObject ))
			end
		end
	end
end

function api.fs.move(fromPath, toPath)
	if type(fromPath) ~= "string" or type(toPath) ~= "string" then
		error("Expected string, string",2)
	end
	local testpath = api.fs.combine("data/", fromPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	local testpath = api.fs.combine("data/", toPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	fromPath = api.fs.combine("", fromPath)
	toPath = api.fs.combine("", toPath)
	if api.fs.exists(fromPath) ~= true then
		error("No such file",2)
	end
	if api.fs.exists(toPath) == true then
		error("File exists",2)
	end
	if fromPath == "rom" or string.sub(fromPath, 1, 4) == "rom/" or 
		toPath == "rom" or string.sub(toPath, 1, 4) == "rom/" then
		error("Access Deined",2)
	end
	copytree("data/" .. fromPath, "data/" .. toPath)
	deltree( "data/" .. fromPath )
end

function api.fs.copy(fromPath, toPath)
	if type(fromPath) ~= "string" or type(toPath) ~= "string" then
		error("Expected string, string",2)
	end
	local testpath = api.fs.combine("data/", fromPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	local testpath = api.fs.combine("data/", toPath)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	fromPath = api.fs.combine("", fromPath)
	toPath = api.fs.combine("", toPath)
	if api.fs.exists(fromPath) ~= true then
		error("No such file",2)
	end
	if api.fs.exists(toPath) == true then
		error("File exists",2)
	end
	if toPath == "rom" or string.sub(toPath, 1, 4) == "rom/" then
		error("Access Deined",2)
	end
	local sPath = nil
	if love.filesystem.exists("data/" .. fromPath) then
		sPath = "data/" .. fromPath
	elseif love.filesystem.exists("lua/" .. fromPath) then
		sPath = "lua/" .. fromPath
	end
	copytree(sPath, "data/" .. toPath)
end

function api.fs.delete(path)
	if type(path) ~= "string" then error("Expected string",2) end
	local testpath = api.fs.combine("data/", path)
	if testpath:sub(1,5) ~= "data/" and testpath ~= "data" then error("Invalid Path",2) end
	path = api.fs.combine("", path)
	if path == "rom" or string.sub(path, 1, 4) == "rom/" then
		error("Access Deined",2)
	end
	deltree( "data/" .. path )
end

api.bit = {}
function api.bit.norm(val)
	while val < 0 do val = val + 4294967296 end
	return val
end
function api.bit.blshift( n, bits )
	return api.bit.norm(bit.lshift(n, bits))
end
function api.bit.brshift( n, bits )
	return api.bit.norm(bit.arshift(n, bits))
end
function api.bit.blogic_rshift( n, bits )
	return api.bit.norm(bit.rshift(n, bits))
end
function api.bit.bxor( m, n )
	return api.bit.norm(bit.bxor(m, n))
end
function api.bit.bor( m, n )
	return api.bit.norm(bit.bor(m, n))
end
function api.bit.band( m, n )
	return api.bit.norm(bit.band(m, n))
end
function api.bit.bnot( n )
	return api.bit.norm(bit.bnot(n))
end

function api.init() -- Called after this file is loaded! Important. Else api.x is not defined
	api.comp = {
		cursorX = 1,
		cursorY = 1,
		bg = 32768,
		fg = 1,
		blink = false,
		label = nil,
	}
	api.env = {
		_VERSION = "Luaj-jse 2.0.3",
		tostring = tostring,
		tonumber = tonumber,
		unpack = unpack,
		getfenv = getfenv,
		setfenv = setfenv,
		rawequal = rawequal,
		rawset = rawset,
		rawget = rawget,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		next = next,
		type = type,
		select = select,
		assert = assert,
		error = error,
		ipairs = ipairs,
		pairs = pairs,
		pcall = pcall,

		loadstring = function(str, source)
			local f, err = loadstring(str, source)
			if f then
				setfenv(f, api.env)
			end
			return f, err
		end,

		math = tablecopy(math),
		string = tablecopy(string),
		table = table,
		coroutine = coroutine,

		-- CC apis (BIOS completes api.)
		cclite = {
			peripheralAttach = api.cclite.peripheralAttach,
			peripheralDetach = api.cclite.peripheralDetach,
			call = api.cclite.call,
			log = print,
			traceback = debug.traceback,
		},
		term = {
			native = {
				clear = api.term.clear,
				clearLine = api.term.clearLine,
				getSize = api.term.getSize,
				getCursorPos = api.term.getCursorPos,
				setCursorPos = api.term.setCursorPos,
				setTextColor = api.term.setTextColor,
				setTextColour = api.term.setTextColor,
				setBackgroundColor = api.term.setBackgroundColor,
				setBackgroundColour = api.term.setBackgroundColor,
				setCursorBlink = api.term.setCursorBlink,
				scroll = api.term.scroll,
				write = api.term.write,
				isColor = api.term.isColor,
				isColour = api.term.isColor,
			},
			clear = api.term.clear,
			clearLine = api.term.clearLine,
			getSize = api.term.getSize,
			getCursorPos = api.term.getCursorPos,
			setCursorPos = api.term.setCursorPos,
			setTextColor = api.term.setTextColor,
			setTextColour = api.term.setTextColor,
			setBackgroundColor = api.term.setBackgroundColor,
			setBackgroundColour = api.term.setBackgroundColor,
			setCursorBlink = api.term.setCursorBlink,
			scroll = api.term.scroll,
			write = api.term.write,
			isColor = api.term.isColor,
			isColour = api.term.isColor,
		},
		fs = {
			open = api.fs.open,
			list = api.fs.list,
			exists = api.fs.exists,
			isDir = api.fs.isDir,
			isReadOnly = api.fs.isReadOnly,
			getName = api.fs.getName,
			getDrive = function(path) return nil end, -- Dummy function
			getSize = api.fs.getSize,
			getFreeSpace = api.fs.getFreeSpace,
			makeDir = api.fs.makeDir,
			move = api.fs.move,
			copy = api.fs.copy,
			delete = api.fs.delete,
			combine = api.fs.combine,
		},
		os = {
			clock = api.os.clock,
			getComputerID = function() return 0 end,
			computerID = function() return 0 end,
			setComputerLabel = api.os.setComputerLabel,
			getComputerLabel = api.os.getComputerLabel,
			computerLabel = api.os.getComputerLabel,
			queueEvent = api.os.queueEvent,
			startTimer = api.os.startTimer,
			setAlarm = api.os.setAlarm,
			time = api.os.time,
			day = api.os.day,
			shutdown = api.os.shutdown,
			reboot = api.os.reboot,
		},
		peripheral = {
			isPresent = api.peripheral.isPresent,
			getType = api.peripheral.getType,
			getMethods = api.peripheral.getMethods,
			call = api.peripheral.call,
			getNames = api.peripheral.getNames,
		},
		http = {
			request = api.http.request,
		},
		redstone = {
			getSides = function() return {"top","bottom","left","right","front","back"} end,
			getInput = function() end,
			getOutput = function() end,
			getBundledInput = function() end,
			getBundledOutput = function() end,
			getAnalogInput = function() end,
			getAnalogOutput = function() end,
			setOutput = function() end,
			setBundledOutput = function() end,
			setAnalogOutput = function() end,
			testBundledInput = function() end,
		},
		bit = {
			blshift = api.bit.blshift,
			brshift = api.bit.brshift,
			blogic_rshift = api.bit.blogic_rshift,
			bxor = api.bit.bxor,
			bor = api.bit.bor,
			band = api.bit.band,
			bnot = api.bit.bnot,
		},
	}
	api.env.redstone.getAnalogueInput = api.env.redstone.getAnalogInput
	api.env.redstone.getAnalogueOutput = api.env.redstone.getAnalogOutput
	api.env.redstone.setAnalogueOutput = api.env.redstone.setAnalogOutput
	api.env.rs = api.env.redstone
	api.env.math.mod = nil
	api.env.string.gfind = nil
	api.env._G = api.env
end
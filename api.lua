local api = {}

local flr = math.floor


local function color(c)
	c = flr(c or 0) % 16
	pico8.color = c
	setColor(c)
end

local function warning(msg)
	log(debug.traceback("WARNING: " .. msg, 3))
end

local function _horizontal_line(lines, x0, y, x1)
	table.insert(lines, { x0 + 0.5, y + 0.5, x1 + 1.5, y + 0.5 })
end

local function _plot4points(lines, cx, cy, x, y)
	_horizontal_line(lines, cx - x, cy + y, cx + x)
	if y ~= 0 then
		_horizontal_line(lines, cx - x, cy - y, cx + x)
	end
end

local function scroll(pixels)
	local base = 0x6000
	local delta = base + pixels * 0x40
	local basehigh = 0x8000
	api.memcpy(base, delta, basehigh - delta)
end

local function setfps(fps)
	pico8.fps = flr(fps)
	if pico8.fps <= 0 then
		pico8.fps = 30
	end
	pico8.frametime = 1 / pico8.fps
end

local function getmousex()
	return flr((love.mouse.getX() - xpadding) / scale)
end

local function getmousey()
	return flr((love.mouse.getY() - ypadding) / scale)
end

-- extra functions provided by picolove
api.warning = warning
api.setfps = setfps

function api._picolove_end()
	if
		not pico8.cart._update
		and not pico8.cart._update60
		and not pico8.cart._draw
	then
		api.printh("cart finished")
	end
end

function api._getpicoloveversion()
	return __picolove_version
end

function api._getcursorx()
	return pico8.cursor[1]
end

function api._getcursory()
	return pico8.cursor[2]
end

function api._call(code)
	code = patch_lua(code)

	local ok, f, e = pcall(load, code, "repl")
	if not ok or f == nil then
		api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5 + 6, 0)
		api.print("syntax error", 14)
		api.print(api.sub(e, 20), 6)
		return false
	else
		setfenv(f, pico8.cart)
		ok, e = pcall(f)
		if not ok then
			api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5 + 6, 0)
			api.print("runtime error", 14)
			api.print(api.sub(e, 20), 6)
		end
	end
	return true
end

--for overriding by fixed point
api._tonumber = tonumber

--------------------------------------------------------------------------------
-- PICO-8 API

function api.flip()
	flip_screen()
	love.timer.sleep(pico8.frametime)
end

function api.camera(x, y)
	pico8.camera_x = flr(api._tonumber(x) or 0)
	pico8.camera_y = flr(api._tonumber(y) or 0)
	restore_camera()
end

function api.clip(x, y, w, h)
	if type(x) == "number" then
		love.graphics.setScissor(x, y, w, h)
		pico8.clip = { x, y, w, h }
	else
		love.graphics.setScissor(0, 0, pico8.resolution[1], pico8.resolution[2])
		pico8.clip = { 0, 0, pico8.resolution[1], pico8.resolution[2] }
	end
end

function api.cls(col)
	col = flr(api._tonumber(col) or 0) % 16

	pico8.clip = nil
	love.graphics.setScissor()
	love.graphics.clear(col / 15, 0, 0, 1)
	pico8.cursor = { 0, 0 }
end

function api.folder(dir)
	if dir == nil then
		love.system.openURL(
			"file://" .. love.filesystem.getWorkingDirectory() .. currentDirectory
		)
	elseif dir == "bbs" then
		api.print("not implemented", 14)
	elseif dir == "backups" then
		api.print("not implemented", 14)
	elseif dir == "config" then
		api.print("not implemented", 14)
	elseif dir == "desktop" then
		love.system.openURL(
			"file://" .. love.filesystem.getUserDirectory() .. "Desktop"
		)
	else
		api.print("useage: folder [location]", 14)
		api.print("locations:", 6)
		api.print("backups bbs config desktop", 6)
	end
end

function api._completecommand(command, path)
	-- TODO: handle depending on command

	local startDir = ""
	local pos = path:find("/", 1, true)
	if pos ~= nil then
		startDir = startDir .. path:sub(1, pos)
		path = path:sub(pos + 1)
	end
	local files = love.filesystem.getDirectoryItems(currentDirectory .. startDir)

	local filteredFiles = {}
	for _, file in ipairs(files) do
		if string.sub(file:lower(), 1, string.len(path)) == path then
			filteredFiles[#filteredFiles + 1] = file
		end
	end
	files = filteredFiles

	local result
	if #files == 0 then
		result = path
	elseif #files == 1 then
		if
			love.filesystem.getInfo(currentDirectory .. startDir .. files[1], "directory") ~= nil
		then
			result = files[1]:lower() .. "/"
		else
			result = files[1]:lower()
		end
	else
		local matches
		local match = path

		repeat
			result = match
			if #match == #files[1] then
				break
			end

			match = files[1]:sub(1, #match + 1)
			matches = 0
			for _, file in ipairs(files) do
				if string.sub(file:lower(), 1, string.len(match)) == match then
					matches = matches + 1
				end
			end
		until matches ~= #files

		result = result:lower()

		if #result == #path then
			-- TODO: remove duplicate code (see api.ls())
			local output = {}
			for _, file in ipairs(files) do
				if love.filesystem.getInfo(currentDirectory .. file, "directory") ~= nil then
					output[#output + 1] = { name = file:lower(), color = 14 }
				elseif file:sub(-3) == ".p8" or file:sub(-4) == ".png" then
					output[#output + 1] = { name = file:lower(), color = 6 }
				else
					output[#output + 1] = { name = file:lower(), color = 5 }
				end
			end

			local count = 0
			love.keyboard.setTextInput(false)
			api.rectfill(0, api._getcursory(), 127, api._getcursory() + 6, 0)
			api.print(#output .. " files", 12)
			for _, item in ipairs(output) do
				for j = 1, #item.name, 32 do
					api.rectfill(0, api._getcursory(), 127, api._getcursory() + 6, 0)
					api.print(item.name:sub(j, j + 32), item.color)
					flip_screen()
					count = count + 1
					if count == 20 then
						api.rectfill(0, api._getcursory(), 127, api._getcursory() + 6, 0)
						api.print("--more--", 12)
						flip_screen()
						local y = api._getcursory() - 6
						api.cursor(0, y)
						api.rectfill(0, y, 127, y + 6, 0)
						api.color(item.color)
						while true do
							local e = love.event.wait()
							if e == "keypressed" then
								break
							end
						end
						count = 0
					end
				end
			end
			love.keyboard.setTextInput(true)
		end
	end

	return command .. " " .. startDir .. result
end

-- TODO: move interactive implementation into nocart
-- TODO: should return table of strings
function api.ls()
	local files = love.filesystem.getDirectoryItems(currentDirectory)
	api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
	api.print("directory: " .. currentDirectory, 12)
	local output = {}
	for _, file in ipairs(files) do
		if love.filesystem.getInfo(currentDirectory .. file, "directory") ~= nil then
			output[#output + 1] = { name = file:lower(), color = 14 }
		elseif file:sub(-3) == ".p8" or file:sub(-4) == ".png" then
			output[#output + 1] = { name = file:lower(), color = 6 }
		else
			output[#output + 1] = { name = file:lower(), color = 5 }
		end
	end
	local count = 0
	love.keyboard.setTextInput(false)
	for _, item in ipairs(output) do
		for j = 1, #item.name, 32 do
			api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
			api.print(item.name:sub(j, j + 32), item.color)
			flip_screen()
			count = count + 1
			if count == 20 then
				api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
				api.print("--more--", 12)
				flip_screen()
				local y = api._getcursory() - 6
				api.cursor(0, y)
				api.rectfill(0, y, 127, y + 6, 0)
				api.color(item.color)
				while true do
					local e, a = love.event.wait()
					if e == "keypressed" then
						if a == "escape" then
							love.keyboard.setTextInput(true)
							return
						else
							love.event.clear() -- consume keypress
						end
						break
					end
				end
				count = 0
			end
		end
	end
	love.keyboard.setTextInput(true)
end

api.dir = api.ls

function api.cd(name)
	local output, count

	if #name > 0 then
		name = name .. "/"
	end

	-- filter /TEXT//$ -> /
	count = 1
	while count > 0 do
		name, count = name:gsub("//", "/")
	end

	local newDirectory = currentDirectory .. name

	if name == "/" then
		newDirectory = "/"
	end

	-- filter /TEXT/../ -> /
	count = 1
	while count > 0 do
		newDirectory, count = newDirectory:gsub("/[^/]*/%.%./", "/")
	end

	-- filter /TEXT/..$ -> /
	count = 1
	while count > 0 do
		newDirectory, count = newDirectory:gsub("/[^/]*/%.%.$", "/")
	end

	local failed = newDirectory:find("%.%.") ~= nil
	failed = failed or newDirectory:find("/[ ]+/") ~= nil

	if #name == 0 then
		output = "directory: " .. currentDirectory
	elseif failed then
		if newDirectory == "/../" then
			output = "cd: failed"
		else
			output = "directory not found"
		end
	elseif love.filesystem.getInfo(newDirectory) ~= nil then
		currentDirectory = newDirectory
		output = currentDirectory
	else
		failed = true
		output = "directory not found"
	end

	if not failed then
		api.rectfill(
			0,
			api._getcursory(),
			128,
			api._getcursory() + 5 + api.flr(#output / 32) * 6,
			0
		)
		api.color(12)
		for i = 1, #output, 32 do
			api.print(output:sub(i, i + 32))
		end
	else
		api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
		api.print(output, 7)
	end
end

function api.mkdir(...)
	local name = select(1, ...)
	if select("#", ...) == 0 then
		api.rectfill(0, api._getcursory(), 128, api._getcursory() + 5, 0)
		api.print("mkdir [name]", 6)
	elseif name ~= nil then
		love.filesystem.createDirectory(currentDirectory .. name)
	end
end

function api.install_demos()
	-- TODO: implement this
end

function api.install_games()
	-- TODO: implement this
end

function api.keyconfig()
	-- TODO: implement this
end

function api.splore()
	-- TODO: implement this
end

function api.pset(x, y, col)
	if col then
		color(col)
	end
	love.graphics.point(flr(x), flr(y))
end

function api.pget(x, y)
	x= x - pico8.camera_x
	y= y - pico8.camera_y
	if
		x >= 0
		and x < pico8.resolution[1]
		and y >= 0
		and y < pico8.resolution[2]
	then
		love.graphics.setCanvas()
		local __screen_img = pico8.screen:newImageData()
		love.graphics.setCanvas(pico8.screen)
		local r = __screen_img:getPixel(flr(x), flr(y))
		return r * 15
	end
	-- warning(string.format("pget out of screen %d, %d", x, y))
	return 0
end

function api.color(col)
	color(col)
end

-- workaround for non printable chars
local tostring_org = tostring
local function tostring(str)
	return tostring_org(str)
	--return (tostring_org(str):gsub("[^%z\32-\127]", "8"))
end

function api.print(...)
	--TODO: support printing special pico8 chars

	local argc = select("#", ...)
	if argc == 0 then
		return
	end

	local x = nil
	local y = nil
	local col = nil
	local str = select(1, ...)

	if argc == 2 then
		col = select(2, ...) or 0
	elseif argc > 2 then
		x = select(2, ...) or 0
		y = select(3, ...) or 0
		if argc >= 4 then
			col = select(4, ...) or 0
		end
	end

	if col ~= nil then
		color(col)
	end
	local canscroll = y == nil
	if y == nil then
		y = pico8.cursor[2]
		pico8.cursor[2] = pico8.cursor[2] + 6
	end
	if x == nil then
		x = pico8.cursor[1]
	end
	if canscroll and y > 121 then
		local c = col or pico8.color
		scroll(6)
		y = 120
		api.rectfill(0, y, 127, y + 6, 0)
		api.color(c)
		api.cursor(0, y + 6)
	end
	local to_print = tostring(api.tostr(str))

	to_print=to_print:gsub('.', function (c)
		-- print(c, string.byte(c), pico8_glyphs[string.byte(c)])
		local gl = pico8_glyphs[string.byte(c)]
		if not gl then return c end
		return glyph_edgecases[gl] or gl end)

	love.graphics.setShader(pico8.text_shader)
	love.graphics.print(to_print, flr(x), flr(y))

	-- return x position of next character to be printed
	local font = love.graphics.getFont()
	return x + font:getWidth(to_print)
end

api.printh = print

function api.cursor(x, y, col)
	if col then
		color(col)
	end
	x = flr(api._tonumber(x) or 0) % 256
	y = flr(api._tonumber(y) or 0) % 256
	pico8.cursor = { x, y }
end

function api.tonum(val, format)
	--TODO:fixed point
	local kind = type(val)
	if kind ~= "number" and kind ~= "string" and kind ~= "boolean" then
		return
	elseif kind == "number" then
		return val
	end

	if type(format) == "string" then
		format = api._tonumber(format)
	elseif type(format) ~= "number" then
		format = nil
	end

	local base = 10
	local shift = false
	local zeroreturn = false
	if type(format) == "number" then
		base = bit.band(format, 1) ~= 0 and 16 or 10
		shift = bit.band(format, 2) ~= 0
		zeroreturn = bit.band(format, 4) ~= 0
	end

	if kind == "boolean" then
		val = val and 1 or 0
		return shift and 0 or val
	end

	local result = api._tonumber(val, base)
	if result ~= nil then
		return shift and result / 0x10000 or result
	elseif zeroreturn then
		return 0
	end
end

function api.chr(num)
	--GTODO: stuff
	local n = api._tonumber(num)
	if n == nil then
		return
	end
	n = n % 256
	return tostring(string.char(n))
end

function api.ord(...)
	local str = select(1, ...)
	if str == nil then
		return nil
	end

	local argc = select("#", ...)
	local index = select(2, ...) or 0
	local count = select(3, ...) or 0

	if argc == 1 then
		return string.byte(str)
	elseif argc == 2 then
		return string.byte(str, index)
	elseif argc >= 3 then
		local values = {}
		for i = 1, count do
			if index + i > 1 then
				values[i] = string.byte(str, index + i - 1)
				api.printh(values[i], i)
			end
		end
		return unpack(values, 1, count)
	end

	return nil
end

function api.tostr(...)
	if select("#", ...) == 0 then
		return ""
	end

	local val = select(1, ...)
	local kind = type(val)

	if kind == "string" then
		return val
	elseif kind == "number" then
		local format = select(2, ...)
		if format == true then
			format = 1
		end

		if format and bit.band(format, 1) ~= 0 then
			val = val * 0x10000
			local part1 = bit.rshift(bit.band(val, 0xFFFF0000), 16)
			local part2 = bit.band(val, 0xFFFF)
			if bit.band(format, 2) ~= 0 then
				return string.format("0x%04x%04x", part1, part2)
			else
				return string.format("0x%04x.%04x", part1, part2)
			end
		else
			if format and bit.band(format, 2) ~= 0 then
				val = val * 0x10000
			end
			return tostring(val)
		end
	elseif kind == "boolean" then
		return tostring(val)
	else
		return "[" .. kind .. "]"
	end
end


--sync spritesheet_data and spritesheet
local function refresh_spritesheet()
	if pico8.spritesheet_changed then
		pico8.spritesheet_changed=false
		pico8.spritesheet:replacePixels(pico8.spritesheet_data)
	end
end

function api.spr(n, x, y, w, h, flip_x, flip_y)
	love.graphics.setShader(pico8.sprite_shader)
	n = flr(api._tonumber(n) or 0)
	x = api._tonumber(x) or 0
	y = api._tonumber(y) or 0
	w = api._tonumber(w) or 1
	h = api._tonumber(h) or 1
	local q
	if w == 1 and h == 1 then
		q = pico8.quads[n]
		if not q then
			-- log("warning: sprite " .. n .. " is missing")
			return
		end
	else
		local id = string.format("%d-%d-%d", n, w, h)
		if pico8.quads[id] then
			q = pico8.quads[id]
		else
			q = love.graphics.newQuad(
				flr(n % 16) * 8,
				flr(n / 16) * 8,
				8 * w,
				8 * h,
				128,
				128
			)
			pico8.quads[id] = q
		end
	end
	if not q then
		log("missing quad", n)
	end
	refresh_spritesheet()
	love.graphics.draw(
		pico8.spritesheet,
		q,
		flr(x) + (w * 8 * (flip_x and 1 or 0)),
		flr(y) + (h * 8 * (flip_y and 1 or 0)),
		0,
		flip_x and -1 or 1,
		flip_y and -1 or 1
	)
	love.graphics.setShader(pico8.draw_shader)
end

function api.sspr(sx, sy, sw, sh, dx, dy, dw, dh, flip_x, flip_y)
	-- Stretch rectangle from sprite sheet (sx, sy, sw, sh) // given in pixels
	-- and draw in rectangle (dx, dy, dw, dh)
	-- Color 0 drawn as transparent by default (see palt())
	-- dw, dh defaults to sw, sh
	-- flip_x = true to flip horizontally
	-- flip_y = true to flip vertically
	dw = dw or sw
	dh = dh or sh
	-- FIXME: cache this quad
	local q =
		love.graphics.newQuad(sx, sy, sw, sh, pico8.spritesheet:getDimensions())
	love.graphics.setShader(pico8.sprite_shader)
	refresh_spritesheet()
	love.graphics.draw(
		pico8.spritesheet,
		q,
		flr(dx) + (flip_x and dw or 0),
		flr(dy) + (flip_y and dh or 0),
		0,
		dw / sw * (flip_x and -1 or 1),
		dh / sh * (flip_y and -1 or 1)
	)
	love.graphics.setShader(pico8.draw_shader)
end

function api.rect(x0, y0, x1, y1, col)
	-- GTODO: x0=x1
	if col then
		color(col)
	end
	love.graphics.rectangle(
		"line",
		flr(x0) + 1,
		flr(y0) + 1,
		flr(x1 - x0),
		flr(y1 - y0)
	)
end

function api.rectfill(x0, y0, x1, y1, col)
	if col then
		color(col)
	end
	if x1 < x0 then
		x0, x1 = x1, x0
	end
	if y1 < y0 then
		y0, y1 = y1, y0
	end
	love.graphics.rectangle(
		"fill",
		flr(x0),
		flr(y0),
		flr(x1 - x0) + 1,
		flr(y1 - y0) + 1
	)
end

function api.circ(ox, oy, r, col)
	if col then
		color(col)
	end
	ox = flr(ox) + 1
	oy = flr(oy) + 1
	r = flr(r)
	local points = {}
	local x = r
	local y = 0
	local decisionOver2 = 1 - x

	while y <= x do
		table.insert(points, { ox + x, oy + y })
		table.insert(points, { ox + y, oy + x })
		table.insert(points, { ox - x, oy + y })
		table.insert(points, { ox - y, oy + x })

		table.insert(points, { ox - x, oy - y })
		table.insert(points, { ox - y, oy - x })
		table.insert(points, { ox + x, oy - y })
		table.insert(points, { ox + y, oy - x })
		y = y + 1
		if decisionOver2 < 0 then
			decisionOver2 = decisionOver2 + 2 * y + 1
		else
			x = x - 1
			decisionOver2 = decisionOver2 + 2 * (y - x) + 1
		end
	end
	if #points > 0 then
		love.graphics.points(points)
	end
end

function api.circfill(cx, cy, r, col)
	if col then
		color(col)
	end
	cx = flr(cx)
	cy = flr(cy)
	r = flr(r)
	local x = r
	local y = 0
	local err = 1 - r

	local lines = {}

	while y <= x do
		_plot4points(lines, cx, cy, x, y)
		if err < 0 then
			err = err + 2 * y + 3
		else
			if x ~= y then
				_plot4points(lines, cx, cy, y, x)
			end
			x = x - 1
			err = err + 2 * (y - x) + 3
		end
		y = y + 1
	end
	if #lines > 0 then
		for i = 1, #lines do
			love.graphics.line(lines[i])
		end
	end
end

function api.oval(x0, y0, x1, y1, r, col)
	--TODO: implement
end

function api.ovalfill(x0, y0, x1, y1, r, col)
	--TODO: implement
end

local function get_line_points(x0 ,y0 ,x1 ,y1)

	local dx = x1 - x0
	local dy = y1 - y0
	local stepx, stepy

	local points = { { x0, y0 } }

	if dx == 0 then
		-- simple case draw a vertical line
		points = {}
		if y0 > y1 then
			y0, y1 = y1, y0
		end
		for y = y0, y1 do
			table.insert(points, { x0, y })
		end
	elseif dy == 0 then
		-- simple case draw a horizontal line
		points = {}
		if x0 > x1 then
			x0, x1 = x1, x0
		end
		for x = x0, x1 do
			table.insert(points, { x, y0 })
		end
	else
		if dy < 0 then
			dy = -dy
			stepy = -1
		else
			stepy = 1
		end

		if dx < 0 then
			dx = -dx
			stepx = -1
		else
			stepx = 1
		end

		if dx > dy then
			local fraction = dy - bit.rshift(dx, 1)
			while x0 ~= x1 do
				if fraction >= 0 then
					y0 = y0 + stepy
					fraction = fraction - dx
				end
				x0 = x0 + stepx
				fraction = fraction + dy
				table.insert(points, { flr(x0), flr(y0) })
			end
		else
			local fraction = dx - bit.rshift(dy, 1)
			while y0 ~= y1 do
				if fraction >= 0 then
					x0 = x0 + stepx
					fraction = fraction - dy
				end
				y0 = y0 + stepy
				fraction = fraction + dx
				table.insert(points, { flr(x0), flr(y0) })
			end
		end
	end
	return points
end

function api.line(x0, y0, x1, y1, col)
	if col then
		color(col)
	end

	x0 = flr(api._tonumber(x0) or 0) + 1
	y0 = flr(api._tonumber(y0) or 0) + 1
	x1 = flr(api._tonumber(x1) or 0) + 1
	y1 = flr(api._tonumber(y1) or 0) + 1

	local points = get_line_points(x0, y0, x1, y1)

	love.graphics.points(points)
end

function api.tline(x0, y0, x1, y1, mx, my, mdx, mdy, layers)
	x0 = flr(api._tonumber(x0) or 0) + 1
	y0 = flr(api._tonumber(y0) or 0) + 1
	x1 = flr(api._tonumber(x1) or 0) + 1
	y1 = flr(api._tonumber(y1) or 0) + 1

	mx = api._tonumber(mx) or 0
	my = api._tonumber(my) or 0
	mdx = api._tonumber(mdx) or 0.125
	mdy = api._tonumber(mdy) or 0
	layers=api._tonumber(layers) or 0

	local points = get_line_points(x0, y0, x1, y1)

	local colored_points={}

	for _,p in ipairs(points) do
		local sprite = api.mget(mx,my)
		--pixels for sprite 0 are not drawn
		if sprite~=0 and (layers == 0 or bit.band(pico8.spriteflags[sprite], layers) ~= 0) then
			local c = api.sget((sprite % 16 + mx - flr(mx)) * 8 , (flr(sprite/16) + my - flr(my)) * 8)
			p[3] = c / 15
			p[4] = 0
			p[5] = 0
			p[6] = 1
			table.insert(colored_points,p)
		end

		mx = mx + mdx
		my = my + mdy
	end

	love.graphics.points(colored_points)
end


function api.pal(c0, c1, p)
	-- GTODO: 0 vs 1 indexing
	if type(c0) == "table" then
		for k,v in pairs(c0) do
			api.pal(k, v, c1)
		end
		return
	end

	local __palette_modified = false
	local __display_modified = false
	if type(c0) ~= "number" then
		for i = 0, 15 do
			if pico8.draw_palette[i] ~= i then
				pico8.draw_palette[i] = i
				__palette_modified = true
			end
			if pico8.display_palette[i] ~= pico8.palette[i] then
				pico8.display_palette[i] = pico8.palette[i]
				__display_modified = true
			end
		end
		if __palette_modified then
			pico8.draw_shader:send("palette", shdr_unpack(pico8.draw_palette))
			pico8.sprite_shader:send("palette", shdr_unpack(pico8.draw_palette))
			pico8.text_shader:send("palette", shdr_unpack(pico8.draw_palette))
		end
		if __display_modified then
			pico8.display_shader:send("palette", shdr_unpack(pico8.display_palette))
		end
		-- According to PICO-8 manual:
		-- pal() to reset to system defaults (including transparency values)
		api.palt()
	elseif p == 1 and c1 ~= nil then
		c0 = flr(c0) % 16
		c1 = flr(c1) % 16
		pico8.display_palette[c0] = pico8.palette[c1]
		pico8.display_shader:send("palette", shdr_unpack(pico8.display_palette))
	elseif c1 ~= nil then
		c0 = flr(c0) % 16
		c1 = flr(c1) % 16
		if pico8.draw_palette[c0] ~= c1 then
			pico8.draw_palette[c0] = c1
			pico8.draw_shader:send("palette", shdr_unpack(pico8.draw_palette))
			pico8.sprite_shader:send("palette", shdr_unpack(pico8.draw_palette))
			pico8.text_shader:send("palette", shdr_unpack(pico8.draw_palette))
		end
	end
end

function api.palt(c, t)
	local __alpha_modified=false
	c = api._tonumber(c)
	if c == nil then
		for i = 0, 15 do
			local v = i == 0 and 0 or 1
			if pico8.pal_transparent[i] ~= v then
				pico8.pal_transparent[i] = v
				__alpha_modified = true
			end
		end
	elseif t == nil then
		for i = 0, 15 do
			local v = bit.band(c,2^(15-i)) == 0 and 1 or 0
			if pico8.pal_transparent[i] ~= v then
				pico8.pal_transparent[i] = v
				__alpha_modified = true
			end
		end
	else
		c = flr(c) % 16
		local v = t and 0 or 1
		if pico8.pal_transparent[c] ~= v then
			pico8.pal_transparent[c] = v
			__alpha_modified = true
		end
	end
	if __alpha_modified then
		pico8.sprite_shader:send("transparent", shdr_unpack(pico8.pal_transparent))
	end
end

function api.fillp(_)
	-- TODO: implement this
end

function api.map(cel_x, cel_y, sx, sy, cel_w, cel_h, bitmask)
	love.graphics.setShader(pico8.sprite_shader)
	love.graphics.setColor(1, 1, 1, 1)
	refresh_spritesheet()
	cel_x = flr(api._tonumber(cel_x) or 0)
	cel_y = flr(api._tonumber(cel_y) or 0)
	sx = flr(api._tonumber(sx) or 0)
	sy = flr(api._tonumber(sy) or 0)
	cel_w = flr(api._tonumber(cel_w) or 128)
	cel_h = flr(api._tonumber(cel_h) or 64)
	bitmask = api._tonumber(bitmask) or 0

	for y = 0, cel_h - 1 do
		if cel_y + y < 64 and cel_y + y >= 0 then
			for x = 0, cel_w - 1 do
				if cel_x + x < 128 and cel_x + x >= 0 then
					local v = pico8.map[flr(cel_y + y)][flr(cel_x + x)]
					if v > 0 then
						if bitmask == 0 or
							bit.band(pico8.spriteflags[v], bitmask) ~= 0 then
							love.graphics.draw(
								pico8.spritesheet,
								pico8.quads[v],
								sx + 8 * x,
								sy + 8 * y
							)
						end
					end
				end
			end
		end
	end
	love.graphics.setShader(pico8.draw_shader)
end
-- deprecated pico-8 function
api.mapdraw = api.map

function api.mget(x, y)
	x = flr(api._tonumber(x) or 0)
	y = flr(api._tonumber(y) or 0)
	if x >= 0 and x < 128 and y >= 0 and y < 64 then
		return pico8.map[y][x]
	end
	return 0
end

function api.mset(x, y, v)
	x = flr(api._tonumber(x) or 0)
	y = flr(api._tonumber(y) or 0)
	v = flr(api._tonumber(v) or 0) % 256
	if x >= 0 and x < 128 and y >= 0 and y < 64 then
		pico8.map[y][x] = v
		-- shared map and spritesheet data
		if y>=32 then
			local px, py = (x%64)*2, y*2 + math.floor(x/64)
			api.sset(px,py, v%16)
			api.sset(px+1,py, math.floor(v/16))
		end
	end
end

function api.fget(n, f)
	-- difference from pico8: fget() returns fget(0) instead of nil
	-- TODO: handle this properly with varargs
	-- if n == nil then
	-- 	return nil
	-- end
	n = flr(api._tonumber(n) or 0)
	if f ~= nil then
		f = flr(api._tonumber(f) or 0)
		-- return just that bit as a boolean
		if not pico8.spriteflags[flr(n)] then
			warning(string.format("fget(%d, %d)", n, f))
			return false
		end
		return bit.band(pico8.spriteflags[n], bit.lshift(1, f)) ~= 0
	end
	return pico8.spriteflags[n] or 0
end

function api.fset(n, f, v)
	-- fset n [f] v
	-- f is the flag index 0..7
	-- v is boolean
	if n == nil then
		return
	end
	n = flr(api._tonumber(n) or 0)
	if v == nil then
		v, f = f, nil
	end
	if f then
		f = flr(api._tonumber(f) or 0)
		-- set specific bit to v (true or false)
		if v then
			pico8.spriteflags[n] = bit.bor(pico8.spriteflags[n], bit.lshift(1, f))
		else
			pico8.spriteflags[n] =
				bit.band(pico8.spriteflags[n], bit.bnot(bit.lshift(1, f)))
		end
	else
		v = flr(api._tonumber(v) or 0)
		-- set bitfield to v (number)
		pico8.spriteflags[n] = v
	end
end

function api.sget(x, y)
	-- return the color from the spritesheet
	x = flr(api._tonumber(x) or 0)
	y = flr(api._tonumber(y) or 0)

	if x >= 0 and x < 128 and y >= 0 and y < 128 then
		local c = pico8.spritesheet_data:getPixel(x, y)*15
		return c
	end
	return 0
end

function api.sset(x, y, c)
	x = flr(api._tonumber(x) or 0)
	y = flr(api._tonumber(y) or 0)
	c = flr(api._tonumber(c) or 0)%16
	if x>=0 and x<128 and y>=0 and y<128 then
		pico8.spritesheet_data:setPixel(x, y, c / 15, 0, 0, 1)
		pico8.spritesheet_changed = true --lazy
		--shared map and spritesheet data
		if y>=64 then
			local mx, my =math.floor(x/2)+(y%2)*64, math.floor(y/2)
			if x%2 == 0 then
				pico8.map[my][mx] = bit.band(pico8.map[my][mx], 0xf0) + c
			else
				pico8.map[my][mx] = bit.band(pico8.map[my][mx], 0x0f) + c*16
			end
		end
	end
end

function api.music(n, fade_len, channel_mask) -- luacheck: no unused
	-- TODO: implement fade out
	if n == -1 then
		if pico8.current_music then
			for i = 0, 3 do
				if pico8.music[pico8.current_music.music][i] < 64 then
					pico8.audio_channels[i].sfx = nil
					pico8.audio_channels[i].offset = 0
					pico8.audio_channels[i].last_step = -1
				end
			end
			pico8.current_music = nil
		end
		return
	end
	local m = pico8.music[n]
	if not m then
		warning(string.format("music %d does not exist", n))
		return
	end
	local music_speed = nil
	local music_channel = nil
	for i = 0, 3 do
		if m[i] < 64 then
			local sfx = pico8.sfx[m[i]]
			if music_speed == nil or music_speed > sfx.speed then
				music_speed = sfx.speed
				music_channel = i
			end
		end
	end
	pico8.audio_channels[music_channel].loop = false
	pico8.current_music = {
		music = n,
		offset = 0,
		channel_mask = channel_mask or 15,
		speed = music_speed,
	}
	for i = 0, 3 do
		if pico8.music[n][i] < 64 then
			pico8.audio_channels[i].sfx = pico8.music[n][i]
			pico8.audio_channels[i].offset = 0
			pico8.audio_channels[i].last_step = -1
		end
	end
end

function api.sfx(n, channel, offset)
	-- n = -1 stop sound on channel
	-- n = -2 to stop looping on channel
	--
	-- channel = -1 to find a free channel
	-- channel = -2 to stop the sfx on any channels it plays on
	channel = channel or -1
	if n == -1 and channel >= 0 then
		pico8.audio_channels[channel].sfx = nil
		return
	elseif n == -2 and channel >= 0 then
		pico8.audio_channels[channel].loop = false
	end
	offset = offset or 0
	if channel == -1 then
		-- find a free channel
		for i = 0, 3 do
			if pico8.audio_channels[i].sfx == nil then
				channel = i
			end
		end
	end
	if channel == -1 then
		return
	end
	if channel == -2 then
		for i = 0, 3 do
			if pico8.audio_channels[i].sfx == n then
				pico8.audio_channels[i].sfx = nil
			end
		end
		return
	end
	local ch = pico8.audio_channels[channel]
	ch.sfx = n
	ch.offset = offset
	ch.last_step = offset - 1
	ch.loop = true
end

function api.peek(addr)
	addr = flr(api._tonumber(addr) or 0) % 0x10000
	if addr < 0 then
		return 0
	elseif addr < 0x2000 then
		local lo = pico8.spritesheet_data:getPixel(addr*2%128, flr(addr/64))*15
		local hi = pico8.spritesheet_data:getPixel(addr*2%128+1, flr(addr/64))*15
		return hi*16+lo
	elseif addr < 0x3000 then
		addr = addr - 0x2000
		return pico8.map[flr(addr / 128)][addr % 128]
	elseif addr < 0x3100 then
		return pico8.spriteflags[addr - 0x3000]
	elseif addr < 0x3200 then
		-- TODO: check that this works
		local _music = math.floor((addr - 0x3100) / 4)
		local byte = pico8.music[_music][addr % 4]
		byte = bit.bor(byte, bit.band(bit.lshift(pico8.music[_music].loop, 7-addr %4), 0x80))
		return byte
	elseif addr < 0x4300 then
		local _sfx = math.floor((addr - 0x3200) / 68)
		local step = (addr - 0x3200) % 68
		if step < 64 then
			local sfx = pico8.sfx[_sfx][math.floor(step / 2)]
			local note = bit.bor(sfx[1], bit.lshift(bit.band(sfx[2],7),6), bit.lshift(sfx[3],9), bit.lshift(sfx[4], 12), bit.lshift(bit.band(sfx[2],8), 12))
			return bit.band(bit.rshift(note, (addr%2)*8), 0xff)
		elseif step == 64 then
			return pico8.sfx[_sfx].editor_mode
		elseif step == 65 then
			return pico8.sfx[_sfx].speed
		elseif step == 66 then
			return pico8.sfx[_sfx].loop_start
		elseif step == 67 then
			return pico8.sfx[_sfx].loop_end
		end
		-- TODO: sfx data
	elseif addr < 0x5e00 then
		return pico8.usermemory[addr - 0x4300]
	elseif addr < 0x5f00 then
		local val = pico8.cartdata[flr((addr - 0x5e00) / 4)] * 0x10000
		local shift = (addr % 4) * 8
		return bit.rshift(bit.band(val, bit.lshift(0xFF, shift)), shift)
	elseif addr < 0x5f40 then
		-- TODO: draw state
		if addr == 0x5f20 then
			return pico8.clip[1]
		elseif addr == 0x5f21 then
			return pico8.clip[2]
		elseif addr == 0x5f22 then
			return pico8.clip[1] + pico8.clip[3]
		elseif addr == 0x5f23 then
			return pico8.clip[2] + pico8.clip[4]
		elseif addr == 0x5f25 then
			return pico8.color
		elseif addr == 0x5f26 then
			return pico8.cursor[1]
		elseif addr == 0x5f27 then
			return pico8.cursor[2]
		elseif addr == 0x5f28 then
			return pico8.camera_x % 256
		elseif addr == 0x5f29 then
			return flr(pico8.camera_x / 256)
		elseif addr == 0x5f2a then
			return pico8.camera_y % 256
		elseif addr == 0x5f2b then
			return flr(pico8.camera_y / 256)
		elseif addr == 0x5f2c then
			return pico8.transform_mode
		elseif addr == 0x5f2d then
			-- TODO: fully implement
			return love.keyboard.hasTextInput()
		end
	elseif addr < 0x5f80 then -- luacheck: ignore 542
		-- TODO: hardware state
		if addr >= 0x5f44 and addr < 0x5f48 then
			local shift = (addr-0x5f44)*8
			return bit.band(bit.rshift(pico8.rng_high,shift),0xff)
		elseif addr >= 0x5f48 and addr < 0x5f4c then
			local shift = (addr-0x5f48)*8
			return bit.band(bit.rshift(pico8.rng_low,shift),0xff)
		end
	elseif addr < 0x6000 then -- luacheck: ignore 542
		-- TODO: gpio pins
	elseif addr < 0x8000 then
		-- screen data
		local dx = (addr - 0x6000) % 64
		local dy = flr((addr - 0x6000) / 64)
		local low = api.pget(dx, dy)
		local high = bit.lshift(api.pget(dx + 1, dy), 4)
		return bit.bor(low, high)
	elseif addr < 0x10000  then
		return pico8.extended_memory[addr - 0x8000] or 0
	end
	return 0
end

function api.poke(addr, val)
	if api._tonumber(val) == nil then
		return
	end
	addr, val = flr(api._tonumber(addr) or 0) % 0x10000, flr(val) % 256
	if addr < 0x1000 then -- luacheck: ignore 542
		local lo=val%16
		local hi=flr(val/16)
		pico8.spritesheet_data:setPixel(addr*2%128, flr(addr/64), lo/15, 0, 0, 1)
		pico8.spritesheet_data:setPixel(addr*2%128+1, flr(addr/64), hi/15, 0, 0, 1)
		pico8.spritesheet_changed = true --lazy
	elseif addr < 0x2000 then
		local lo=val%16
		local hi=flr(val/16)
		pico8.spritesheet_data:setPixel(addr*2%128, flr(addr/64), lo/15, 0, 0, 1)
		pico8.spritesheet_data:setPixel(addr*2%128+1, flr(addr/64), hi/15, 0, 0, 1)
		pico8.spritesheet_changed = true --lazy
		pico8.map[flr(addr/128)][addr%128]=val
	elseif addr < 0x3000 then
		addr = addr - 0x2000
		pico8.map[flr(addr / 128)][addr % 128] = val
	elseif addr < 0x3100 then
		pico8.spriteflags[addr - 0x3000] = val
	elseif addr < 0x3200 then -- luacheck: ignore 542
		-- TODO: music data
	elseif addr < 0x4300 then -- luacheck: ignore 542
		-- TODO: sfx data
	elseif addr < 0x5e00 then
		pico8.usermemory[addr - 0x4300] = val
	elseif addr < 0x5f00 then -- luacheck: ignore 542
		local ind=math.floor((addr-0x5e00)/4)
		local oval=pico8.cartdata[ind]*0x10000
		local shift=(addr%4)*8
		pico8.cartdata[ind]=bit.bor(bit.band(oval, bit.bnot(bit.lshift(0xFF, shift))), bit.lshift(val, shift))/0x10000
	elseif addr < 0x5f40 then -- luacheck: ignore 542
		-- TODO: draw state
		if addr == 0x5f26 then
			pico8.cursor[1] = val
		elseif addr == 0x5f27 then
			pico8.cursor[2] = val
		elseif addr == 0x5f28 then
			pico8.camera_x = flr(pico8.camera_x / 256) + val % 256
		elseif addr == 0x5f29 then
			pico8.camera_x = flr((val % 256) * 256) + pico8.camera_x % 256
		elseif addr == 0x5f2a then
			pico8.camera_y = flr(pico8.camera_y / 256) + val % 256
		elseif addr == 0x5f2b then
			pico8.camera_y = flr((val % 256) * 256) + pico8.camera_y % 256
		elseif addr == 0x5f2c then
			pico8.transform_mode = val
		elseif addr == 0x5f2d then
			love.keyboard.setTextInput(bit.band(val, 1) == 1)

			if bit.band(val, 2) == 1 then -- luacheck: ignore 542
				-- TODO mouse buttons
			else -- luacheck: ignore 542
			end

			if bit.band(val, 4) == 1 then -- luacheck: ignore 542
				-- TODO pointer lock
			else -- luacheck: ignore 542
			end
		end
	elseif addr < 0x5f80 then -- luacheck: ignore 542
		-- TODO: hardware state
		if addr >= 0x5f44 and addr < 0x5f48 then
			local shift = (addr-0x5f44)*8
			local mask = bit.bnot(bit.lshift(0xff,shift))
			pico8.rng_high = bit.band(pico8.rng_high,mask) + bit.lshift(val,shift)
		elseif addr >= 0x5f48 and addr < 0x5f4c then
			local shift = (addr-0x5f48)*8
			local mask = bit.bnot(bit.lshift(0xff,shift))
			pico8.rng_high = bit.bor(bit.band(pico8.rng_high,mask), bit.lshift(val,shift))
		end
	elseif addr < 0x6000 then -- luacheck: ignore 542
		-- TODO: gpio pins
	elseif addr < 0x8000 then
		addr = addr - 0x6000
		local dx = addr % 64 * 2
		local dy = flr(addr / 64)
		api.pset(dx, dy, bit.band(val, 15))
		api.pset(dx + 1, dy, bit.rshift(val, 4))
	elseif addr < 0x10000 then
		pico8.extended_memory[addr - 0x8000] = val
	end
end

function api.peek2(addr)
	local val = 0
	val = bit.bor(val,  api.peek(addr + 0))
	val = bit.bor(val,  api.peek(addr + 1) * 0x100)
	return val
end

function api.peek4(addr)
	local val = 0
	val = bit.bor(val, api.peek(addr + 0))
	val = bit.bor(val,  api.peek(addr + 1) * 0x100)
	val = bit.bor(val,  api.peek(addr + 2) * 0x10000)
	val = bit.bor(val,  api.peek(addr + 3) * 0x1000000)
	return val/0x10000
end

function api.poke2(addr, val)
	api.poke(addr + 0, bit.rshift(bit.band(val, 0x00FF), 0))
	api.poke(addr + 1, bit.rshift(bit.band(val, 0xFF00), 8))
end

function api.poke4(addr, val)
	val = val * 0x10000
	api.poke(addr + 0, bit.rshift(bit.band(val, 0x000000FF), 0))
	api.poke(addr + 1, bit.rshift(bit.band(val, 0x0000FF00), 8))
	api.poke(addr + 2, bit.rshift(bit.band(val, 0x00FF0000), 16))
	api.poke(addr + 3, bit.rshift(bit.band(val, 0xFF000000), 24))
end

function api.memcpy(dest_addr, source_addr, len)
	if len < 1 or dest_addr == source_addr then
		return
	end

	for i=0, len-1 do
		local val = api.peek(source_addr+i)
		api.poke(dest_addr+i, val)
	end
end

function api.memset(dest_addr, val, len)
	if len < 1 then
		return
	end

	for i = dest_addr, dest_addr + len - 1 do
		api.poke(i, val)
	end
end

function api.reload_cart()
	_load(cartname)
end

function api.reload(dest_addr, source_addr, len, filepath) -- luacheck: no unused
	-- FIXME: doesn't handle filepaths
	--
	dest_addr = flr(api._tonumber(dest_addr) or 0)
	source_addr = flr(api._tonumber(source_addr) or 0)
	len = flr(api._tonumber(len) or 0x4300)
	len = math.min(0x4300-source_addr, len)
	for i=0, len-1 do
		api.poke(dest_addr+i, pico8.rom[source_addr+i])
	end

end

function api.cstore(dest_addr, source_addr, len) -- luacheck: no unused
	-- TODO: implement this
end

function api.rnd(x)
	if type(x)=="table" then
		return x[love.math.random(#x)]
	else
		return love.math.random() * (api._tonumber(x) or 1)
	end
end

function api.srand(seed)
	seed=api._tonumber(seed) or 0
	if seed == 0 then
		seed = 1
	end
	return love.math.setRandomSeed(flr(seed * 0x8000))
end

api.flr = math.floor
api.ceil = math.ceil

function api.sgn(x)
	x = api._tonumber(x) or 0
	return x < 0 and -1 or 1
end

api.abs = math.abs

function api.min(a, b)
	a = api._tonumber(a) or 0
	b = api._tonumber(b) or 0
	return a < b and a or b
end

function api.max(a, b)
	a = api._tonumber(a) or 0
	b = api._tonumber(b) or 0
	return a > b and a or b
end

function api.mid(x, y, z)
	x = api._tonumber(x) or 0
	y = api._tonumber(y) or 0
	z = api._tonumber(z) or 0
	if x > y then
		x, y = y, x
	end
	return api.max(x, api.min(y, z))
end

function api.cos(x)
	--TODO:fixed point
	return math.cos((x or 0) * math.pi * 2)
end

function api.sin(x)
	--TODO: fixed point
	return -math.sin((x or 0) * math.pi * 2)
end

api.sqrt = math.sqrt

function api.atan2(x, y)
	--TODO: fixed point
	return (0.75 + math.atan2(x, y) / (math.pi * 2)) % 1.0
end

local bit = require("bit")

function api.band(x, y)
	return bit.band(x*0x10000, y*0x10000)/0x10000
end

function api.bor(x, y)
	return bit.bor(x*0x10000, y*0x10000)/0x10000
end

function api.bxor(x, y)
	return bit.bxor(x*0x10000, y*0x10000)/0x10000
end

function api.bnot(x)
	return bit.bnot(x*0x10000)/0x10000
end

function api.shl(x, y)
	return bit.lshift(x*0x10000, y)/0x10000
end

function api.shr(x, y)
	return bit.arshift(x*0x10000, y)/0x10000
end

function api.lshr(x, y)
	return bit.rshift(x*0x10000, y)/0x10000
end

function api.rotl(x, y)
	return bit.rol(x*0x10000, y)/0x10000
end

function api.rotr(x, y)
	return bit.ror(x*0x10000, y)/0x10000
end

function api.load(filename)
	local hasloaded = _load(filename)
	if hasloaded then
		love.window.setTitle(string.upper(cartname) .. " (PICOLÖVE)")
	end
	return hasloaded
end

function api.save()
	-- TODO: implement this
end

function api.run()
	if not cartname then
		return
	end

	love.graphics.setCanvas(pico8.screen)
	love.graphics.setShader(pico8.draw_shader)
	restore_clip()
	love.graphics.origin()

	api.clip()
	pico8.cart = new_sandbox()

	pico8.can_pause = true
	pico8.can_shutdown = false

	for addr = 0x4300, 0x5e00 - 1 do
		pico8.usermemory[addr - 0x4300] = 0
	end

	pico8.extended_memory = {}

	for i = 0, 63 do
		pico8.cartdata[i] = 0
	end

	local ok, f, e = pcall(load, loaded_code, cartname)
	if not ok or f == nil then
		log("=======8<========")
		log(loaded_code)
		log("=======>8========")
		error("Error loading lua: " .. tostring(e))
	else
		setfenv(f, pico8.cart)
		love.graphics.setShader(pico8.draw_shader)
		love.graphics.setCanvas(pico8.screen)
		love.graphics.origin()
		restore_clip()

		--implement string indexing with []
		getmetatable('').__index = function(str,i)
			if type(i) == 'number' then
				local c =  string.sub(str,i,i)
				if c=="" then
					return nil
				end
				return c
			else
				return string[i]
			end
		end

		ok, e = pcall(f)
		if not ok then
			error("Error running lua: " .. tostring(e))
		else
			log("lua completed")
		end
	end

	if pico8.cart._init then
		pico8.cart._init()
	end
	if pico8.cart._update60 then
		setfps(60)
	else
		setfps(30)
	end
end

function api.stop(message, x, y, col) -- luacheck: no unused
	-- TODO: implement this
end

function api.reboot()
	love.window.setTitle("UNTITLED.P8 (PICOLÖVE)")
	_load("nocart.p8")
	api.run()
	cartname = nil
end

function api.shutdown()
	if pico8.can_shutdown then
		love.event.quit()
	end
end

api.exit = api.shutdown

function api.info()
	-- TODO: implement this
end

function api.export()
	-- TODO: implement this
end

function api.import()
	-- TODO: implement this
end

-- TODO: dummy api implementation should just return return null
--function api.help()
--	return nil
--end
-- TODO: move implementatn into nocart
function api.help()
	local commandKey = "ctrl"
	if love.system.getOS() == "OS X" then
		commandKey = "control"
	end

	api.rectfill(0, api._getcursory(), 128, 128, 0)
	api.print("")
	api.color(12)
	api.print("commands")
	api.print("")
	api.color(6)
	api.print("load <filename>  save <filename>")
	api.print("run              resume")
	api.print("shutdown         reboot")
	api.print("install_demos    ls")
	api.print("cd <dirname>     mkdir <dirname>")
	api.print("cd ..     to go up a directory")
	api.print("")
	api.print("alt+enter to toggle fullscreen")
	api.print("alt+f4 or " .. commandKey .. "+q to fastquit")
	api.print("")
	api.color(12)
	api.print("see readme.md for more info")
	api.print("or visit: github.com/picolove")
	api.print("")
end

function api.time()
	return pico8.frames/30
end
api.t = api.time

function api.login()
	return nil
end

function api.logout()
	return nil
end

function api.bbsreq()
	return nil
end

function api.scoresub()
	return nil, 0
end

function api.extcmd(_)
	-- TODO: Implement this?
end

function api.radio()
	return nil, 0
end

function api.btn(i, p)
	if i ~= nil or p ~= nil then
		i = flr(api._tonumber(i) or 0)
		p = flr(api._tonumber(p) or 0)
		if pico8.keymap[p] and pico8.keymap[p][i] then
			return pico8.keypressed[p][i] ~= nil
		end
		return false
	else
		-- return bitfield of buttons
		local bitfield = 0
		for j = 0, 7 do
			if pico8.keypressed[0][j] then
				bitfield = bitfield + bit.lshift(1, j)
			end
		end
		for j = 0, 7 do
			if pico8.keypressed[1][j] then
				bitfield = bitfield + bit.lshift(1, j + 8)
			end
		end
		return bitfield
	end
end


function api.btnp(i, p)
	if i~= nil or p~=nil then
		i = flr(api._tonumber(i) or 0)
		p = flr(api._tonumber(p) or 0)
		if pico8.keymap[p] and pico8.keymap[p][i] then
			local v = pico8.keypressed[p][i]
			if v and (v == 0 or (v >= 12 and v % 4 == 0)) then
				return true
			end
		end
		return false
	else
		-- return bitfield of buttons
		local bitfield = 0
		for j = 0, 7 do
			if pico8.keypressed[0][j] then
				bitfield = bitfield + bit.lshift(1, j)
			end
		end
		for j = 0, 7 do
			if pico8.keypressed[1][j] then
				bitfield = bitfield + bit.lshift(1, j + 8)
			end
		end
		return bitfield
	end
end
-- GTODO: button glyphs

function api.cartdata(id) -- luacheck: no unused
	-- TODO: handle global cartdata properly
	-- TODO: handle cartdata() from console should not work
	pico8.can_cartdata = true
	-- if cartdata exists
	-- return true
	return false
end

function api.dget(index)
	-- TODO: handle global cartdata properly
	-- TODO: handle missing cartdata(id) call
	index = flr(api._tonumber(index) or 0)
	if not pico8.can_cartdata then
		api.print("** dget called before cartdata()", 6)
		return ""
	end
	if index < 0 or index > 63 then
		warning("cartdata index out of range")
		return 0
	end
	return pico8.cartdata[index]
end

function api.dset(index, value)
	-- TODO: handle global cartdata properly
	-- TODO: handle missing cartdata(id) call
	index = flr(api._tonumber(index) or 0)
	if not pico8.can_cartdata then
		api.print("** dget called before cartdata()", 6)
		return ""
	end
	if value >= 0x8000 or value < -0x8000 then
		value = -0x8000
	end
	if index < 0 or index > 63 then
		warning("cartdata index out of range")
		return
	end
	pico8.cartdata[index] = value
end

local tfield = { [0] = "year", "month", "day", "hour", "min", "sec" }
function api.stat(x)
	-- TODO: implement this
	x = flr(api._tonumber(x) or 0)
	if x == 0 then
		return 0 -- TODO memory usage
	elseif x == 1 then
		return 0 -- TODO total cpu usage
	elseif x == 2 then
		return 0 -- TODO system cpu usage
	elseif x == 3 then
		return 0 -- TODO current display (0..3)
	elseif x == 4 then
		return pico8.clipboard
	elseif x == 5 then
		return 33 -- pico-8 version - using latest
	elseif x == 7 then
		return pico8.fps -- current fps
	elseif x == 8 then
		return pico8.fps -- target fps
	elseif x == 9 then
		return love.timer.getFPS()
	elseif x == 30 then
		return #pico8.kbdbuffer ~= 0
	elseif x == 31 then
		return (table.remove(pico8.kbdbuffer, 1) or "")
	elseif x == 32 then
		return getmousex()
	elseif x == 33 then
		return getmousey()
	elseif x == 34 then
		local btns = 0
		for i = 0, 2 do
			if love.mouse.isDown(i + 1) then
				btns = bit.bor(btns, bit.lshift(1, i))
			end
		end
		return btns
	elseif x == 36 then
		return pico8.mwheel
	elseif (x >= 80 and x <= 85) or (x >= 90 and x <= 95) then
		local tinfo
		if x < 90 then
			tinfo = os.date("!*t")
		else
			tinfo = os.date("*t")
		end
		return tinfo[tfield[x % 10]]
	elseif x == 100 then
		return nil -- TODO: breadcrumb not supported
	elseif x == 101 then
		return nil -- TODO: bbs id not supported
	elseif x == 102 then
		return 0 -- TODO: bbs site not supported
	elseif x == 103 then -- UNKNOWN
		return "0000000000000000000000000000000000000000"
	elseif x == 104 then -- UNKNOWN
		return false
	elseif x == 106 then -- UNKNOWN
		return "0000000000000000000000000000000000000000"
	elseif x == 122 then -- UNKNOWN
		return false
	end

	return 0
end

function api.holdframe()
	-- TODO: Implement this
end

function api.menuitem(index, label, fn) -- luacheck: no unused
	-- TODO: implement this
end

api.sub = string.sub
api.pairs = pairs
api.ipairs = ipairs
api.type = type
api.assert = assert
api.setmetatable = setmetatable
api.getmetatable = getmetatable
api.cocreate = coroutine.create
api.coresume = coroutine.resume
api.yield = coroutine.yield
api.costatus = coroutine.status
api.trace = debug.traceback
api.rawset = rawset
api.rawget = rawget
function api.rawlen(table) -- luacheck: no unused
	-- TODO: implement this
end
api.rawequal = rawequal
api.next = next
local lua_inext = ipairs{}
-- pico8 inext converts a missing 2nd argument to 0 - so let's match that behaviour
api.inext = function(t, k)
	return lua_inext(t, k or 0)
end
api.unpack = unpack
api.pack = table.pack

function api.all(a)
	if a == nil then
		return function() end
	end

	local i = 0
	local prev
	return function()
		if a[i] == prev then i = i + 1 end
		while a[i] == nil and i <= #a do
			i = i + 1
		end
		prev = a[i]
		return a[i]
	end
end

function api.foreach(a, f)
	if not a then
		-- warning("foreach got a nil value")
		return
	end

	for v in api.all(a) do
		f(v)
	end
end

-- legacy function
function api.count(a, val)
	if val ~= nil then
		local count = 0
		for _, v in ipairs(a) do
			if v == val then
				count = count + 1
			end
		end
		return count
	else
		return #a
	end
end

function api.add(a, v, index)
	if a == nil then
		warning("add to nil")
		return
	elseif index == nil then
		table.insert(a, v)
	else
		table.insert(a, api._tonumber(index), v)
	end
	return v
end

function api.del(a, dv)
	if a == nil then
		warning("del from nil")
		return
	end
	for i, v in ipairs(a) do
		if v == dv then
			table.remove(a, i)
			return dv
		end
	end
end

function api.deli(...)
	local argc = select("#", ...)
	local a = select(1, ...)
	local index = select(2, ...)

	if argc == 0 or type(a) ~= "table" or #a < 1 then
		return
	end

	if argc == 1 then
		return table.remove(a, #a)
	end

	index = api._tonumber(index)
	if type(index) ~= "number" then
		return
	end

	local len = #a
	for i = 1, len do
		if i == index then
			return table.remove(a, i)
		end
	end
end

function api.serial(channel, address, length) -- luacheck: no unused
	-- TODO: implement this
end

function api.split(str, sep, conv_nums)
	if type(str) ~= "string" and type(str) ~= "number" then
		return nil
	end
	str = tostring(str)
	sep=sep or ","
	conv_nums=(conv_nums==nil) and true or conv_nums
	local tbl={}
	str=str..sep
	for val in string.gmatch(str, '(.-)'..sep) do
		if conv_nums  and api._tonumber(val) ~= nil then
			val=api._tonumber(val)
		end
		table.insert(tbl,val)
	end
	return tbl
end


return api

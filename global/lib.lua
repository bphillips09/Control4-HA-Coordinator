-- Copyright 2022 Snap One, LLC. All rights reserved.

COMMON_LIB_VER = 34

JSON = require ('module.json')

pcall (require, 'drivers-common-internal.global.production')

do	-- set AES and SHA defaults
	AES_DEC_DEFAULTS = {
		return_encoding = 'NONE',
		key_encoding = 'NONE',
		iv_encoding = 'NONE',
		data_encoding = 'BASE64',
		padding = true,
	}

	AES_ENC_DEFAULTS = {
		return_encoding = 'BASE64',
		key_encoding = 'NONE',
		iv_encoding = 'NONE',
		data_encoding = 'NONE',
		padding = true,
	}

	SHA_ENC_DEFAULTS = {
		return_encoding = 'NONE',
		data_encoding = 'NONE',
	}
end

do	-- Set common var IDs
	ROOM_VARS = {
		['CURRENT_SELECTED_DEVICE']		= 1000,
		['CURRENT_AUDIO_DEVICE']		= 1001,
		['CURRENT_VIDEO_DEVICE']		= 1002,
		['AUDIO_VOLUME_DEVICE']			= 1003,
		['VIDEO_VOLUME_DEVICE']			= 1004,
		['CURRENT_MEDIA']				= 1005,
		['CURRENT_AUDIO_PATH']			= 1007,
		['CURRENT_VIDEO_PATH']			= 1008,
		['CURRENT_VIDEO_AUDIO_PATH']	= 1009,
		['POWER_STATE']					= 1010,
		['CURRENT_VOLUME']				= 1011,
		['TEMPERATURE_ID']				= 1012,
		['TEMPERATURE_CONTROL_ID']		= 1013,
		['SECURITY_SYSTEM_ID']			= 1014,
		['CURRENT_VOLUME_DEVICE_ID']	= 1015,
		['HAS_DISCRETE_VOLUME']			= 1016,
		['HAS_DISCRETE_MUTE']			= 1017,
		['IS_MUTED']					= 1018,
		['IN_NAVIGATION	']				= 1019,
		['USE_DEFAULT_VOLUMES']			= 1020,
		['DEFAULT_AUDIO_VOLUME']		= 1021,
		['VOLUME_IS_LINKED']			= 1023,
		['DEFAULT_VIDEO_VOLUME']		= 1022,
		['LINKED_ROOM_LIST']			= 1024,
		['MUTE_IS_LINKED']				= 1025,
		['ROOMOFF_IS_LINKED']			= 1026,
		['SELECTIONS_LINKED']			= 1027,
		['CURRENT_LINKED_MEDIA_SCENE']	= 1028,
		['ROOM_HIDDEN']					= 1029,
		['MEDIA_SCENE_ACTIVE']			= 1030,
		['CURRENT MEDIA INFO'] 			= 1031,
		['LAST_DEVICE_GROUP']			= 1032,
		['AVAILABLE_CAMERAS']			= 1033,
		['POOLS']						= 1034,
		['SCENE_IS_DISCRETE_VOLUME']	= 1035,
		['PLAYING_AUDIO_DEVICE']		= 1036,
		['ANNOUNCEMENT_DISABLED']		= 1037,
	}

	DIGITAL_AUDIO_VARS = {
		['ROOM_HISTORY']				= 1002,
		['ROOM_QUEUE_SETTINGS']			= 1003,
		['QUEUE_STATUS']				= 1004,
		['QUEUE_INFO']					= 1005,
		['QUEUE_STATUS_V2']				= 1006,
		['QUEUE_INFO_V2']				= 1007,
		['PLAY_PREFERENCE']				= 1008,
		['ROOM_MAP_INFO']				= 1009,
		['AUDIO LATENCY PROFILE']		= 1010,
		['MAX_AUDIO_QUALITY']			= 1011,
		['AUDIO_MODE_VER']				= 1012,
		['AUDIO_FORCED_ADV']			= 2000,
	}

	PROJECT_VARS = {
		['ZIPCODE'] = 1000,
		['LATITUDE'] = 1001,
		['LONGITUDE'] = 1002,
	}
end

do -- LOCALE FIXING FOR tostring AND tonumber

	if (not tostring_native) then
		tostring_native = tostring
	end
	if (not tonumber_native) then
		tonumber_native = tonumber
	end

	LOCALE_USES_COMMA_DECIMAL_SEPARATORS = (tonumber ('0.5') == nil)

	function tostring_return_comma (v)
		local ret = tostring_native (v)
		if (type (v) == 'number') then
			ret = string.gsub (ret, '%.', '%,')
		end
		return (ret)
	end

	function tostring_return_period (v)
		local ret = tostring_native (v)
		if (type (v) == 'number') then
			ret = string.gsub (ret, '%,', '%.')
		end
		return (ret)
	end

	function tonumber_expect_comma (e, base)
		local ret = tonumber_native (e, base)
		if (ret == nil) then
			if (type (e) == 'string') then
				e = string.gsub (e, '%.', '%,')
				ret = tonumber_native (e, base)
			end
		end
		return (ret)
	end

	function tonumber_expect_period (e, base)
		local ret = tonumber_native (e, base)
		if (ret == nil) then
			if (type (e) == 'string') then
				e = string.gsub (e, '%,', '%.')
				ret = tonumber_native (e, base)
			end
		end
		return (ret)
	end

	if (LOCALE_USES_COMMA_DECIMAL_SEPARATORS) then
		tonumber = tonumber_expect_comma
	end
end

function dbg (strDebugText, ...)
	if (DEBUGPRINT) then
		local t, ms
		if (C4.GetTime) then
			t = C4:GetTime ()
			ms = '.' .. tostring (t % 1000)
			t = math.floor (t / 1000)
		else
			t = os.time ()
			ms = ''
		end
		local s = string.format("%-21s : ", os.date ('%x %X') .. ms)

		print (s .. (strDebugText or ''), ...)
		C4:DebugLog (strDebugText)
	end
end

function dbgdump (strDebugText, ...)
	if (DEBUGPRINT) then hexdump (strDebugText or '') print (...) end
end

function gettext (text)
	return (text)
end

function Print (data)
	if (type (data) == 'table') then
		for k, v in pairs (data) do print (k, v) end
	elseif (type (data) ~= 'nil') then
		print (type (data), data)
	else
		print ('nil value')
	end
end

function CopyTable (t, shallowCopy)
	if (type (t) ~= 'table') then
		return
	end

	local seenTables = {}

	local r = {}
	for k, v in pairs (t) do
		if (type (v) == 'number' or type (v) == 'string' or type (v) == 'boolean') then
			r [k] = v
		elseif (type (v) == 'table') then
			if (shallowCopy ~= true) then
				if (seenTables [v]) then
					r [k] = seenTables [v]
				else
					r [k] = CopyTable (v)
					seenTables [v] = r [k]
				end
			end
		end
	end
	return (r)
end

function VersionCheck (requires_version)
	local curver = {}
	curver [1], curver [2], curver [3], curver [4] = string.match (C4:GetVersionInfo ().version, '^(%d*)%.?(%d*)%.?(%d*)%.?(%d*)')
	local reqver = {}
	reqver [1], reqver [2], reqver [3], reqver [4] = string.match (requires_version, '^(%d*)%.?(%d*)%.?(%d*)%.?(%d*)')

	for i = 1, 4 do
		local cur = tonumber (curver [i]) or 0
		local req = tonumber (reqver [i]) or 0
		if (cur > req) then
			return true
		end
		if (cur < req) then
			return false
		end
	end
	return true
end

function GetLocationInfo ()
	local proj = XMLDecode (C4:GetProjectItems ('LOCATIONS', 'LIMIT_DEVICE_DATA', 'NO_ROOT_TAGS'))

	local lat = XMLCapture (proj, 'latitude>')
	local long = XMLCapture (proj, 'longitude>')
	local cc = XMLCapture (proj, 'country_code')
	local zip = XMLCapture (proj, 'zipcode')
	local city = XMLCapture (proj, 'city_name')
	local timezone = XMLCapture (proj, 'timezone')

	if (lat == '') then lat = nil end
	if (long == '') then long = nil end
	if (cc == '') then cc = nil end
	if (zip == '') then zip = nil end
	if (city == '') then city = nil end
	if (timezone == '') then timezone = nil end

	return lat, long, cc, zip, city, timezone
end

function GetTimeString (data, forceHours)
	-- Converts an integer number of seconds to a string of [HH:]MM:SS. If HH is zero, it is omitted unless forceHours is true

	if (type (data) == 'number') then
		local strTime = ''
		local strHours, strMinutes, strSeconds

		local seconds = data % 60
		local minutes = math.floor (data / 60) % 60
		local hours = math.floor (data / 3600)

		strHours = string.format('%d', hours)

		if (hours ~= 0 or forceHours) then
			strTime = strHours .. ':'
			strMinutes = string.format('%02d', minutes)
		else
			strMinutes = string.format('%d', minutes)
		end

		strSeconds = string.format('%02d', seconds)

		strTime = strTime .. strMinutes .. ':' .. strSeconds
		return strTime

	elseif (type (data) == 'string') then
		return data

	else
		return 0
	end
end

function GetTimeNumber (data)
	-- Converts a string of [HH:]MM:SS to an integer representing the number of seconds
	if (type (data) == 'string') then
		local hours, minutes, seconds = string.match (data, '^(%d-):(%d-):?(%d-)$')
		if (hours == '') then hours = nil end
		if (minutes == '') then minutes = nil end
		if (seconds == '') then seconds = nil end

		if (hours and not minutes) then
			minutes = hours
			hours = 0
		elseif (minutes and not hours ) then
			hours = 0
		elseif (not minutes and not hours) then
			minutes = 0
			hours = 0
			seconds = seconds or 0
		end

		hours, minutes, seconds = tonumber (hours), tonumber (minutes), tonumber (seconds)
		return ((hours * 3600) + (minutes * 60) + seconds)

	elseif (type (data) == 'number') then
		return data

	else
		return 0
	end
end

function ConvertTime (data, forceHours)
	if (type (data) == 'number') then
		return (GetTimeString (data, forceHours))

	elseif (type (data) == 'string') then
		return (GetTimeNumber (data))

	else
		return 0
	end
end

function RelativeTime (timeNow, timeThen, prefix)
	-- TODO : implement this with gettext for internationalization

	local diff = math.abs (timeNow - timeThen)
	local past = timeNow > timeThen
	local future = timeThen > timeNow

	local ret

	local words = {
		{ name = 'second', duration = 1 },
		{ name = 'minute', duration = 60 },
		{ name = 'hour', duration = 60 * 60 },
		{ name = 'day', duration = 24 * 60 * 60 },
		{ name = 'week', duration = 7 * 24 * 60 * 60 },
		{ name = 'month', duration = 30 * 24 * 60 * 60 },
		{ name = 'year', duration = 365 * 24 * 60 * 60 },
	}

	if (diff == 0) then
		ret = 'now'
	else
		for i, word in ipairs (words) do
			if (diff < word.duration) then
				ret = tostring (math.floor (diff / words [i-1].duration)) .. ' ' .. words [i-1].name .. 's'
				break
			elseif (diff < word.duration * 2) then
				if (word.name == 'hour') then
					ret = 'an hour'
				else
					ret = 'a ' .. word.name
				end
				break
			elseif (diff < word.duration * 5) then
				ret = 'a few ' .. word.name .. 's'
				break
			end
		end
	end

	if (ret == nil) then
		ret = 'a long time'
	end

	if (past) then
		ret = ret .. ' ago'
	elseif (future) then
		ret = ret .. ' from now'
	end

	if (type (prefix) == 'string') then
		ret = prefix .. ret
	end

	return ret
end

function XMLDecode (s)
	if (type (s) ~= 'string') then
		return (s)
	end

	s = string.gsub (s, '%<%!%[CDATA%[(.-)%]%]%>', function (a) return (a) end)

	s = string.gsub (s, '&quot;'	, '"')
	s = string.gsub (s, '&lt;'		, '<')
	s = string.gsub (s, '&gt;'		, '>')
	s = string.gsub (s, '&apos;'	, '\'')
	s = string.gsub (s, '&#x(.-);', function (a) return string.char (tonumber (a, 16) % 256) end )
	s = string.gsub (s, '&#(.-);',	function (a) return string.char (tonumber (a) % 256) end )
	s = string.gsub (s, '&amp;'	, 	'&')

	return s
end

function XMLEncode (s)
	if (type (s) ~= 'string') then
		return (s)
	end

	s = string.gsub (s, '&',	'&amp;')
	s = string.gsub (s, '"',	'&quot;')
	s = string.gsub (s, '<',	'&lt;')
	s = string.gsub (s, '>',	'&gt;')
	s = string.gsub (s, '\'',	'&apos;')
	return s
end

function XMLTag (strName, tParams, tagSubTables, xmlEncodeElements, tAttribs)
	local retXML = {}

	local addTag = function (tagName, closeTag)
		if (tagName == nil) then return end

		if (closeTag) then
			tagName = string.match (tostring (tagName), '^(%S+)')
		end

		if (tagName and tagName ~= '') then
			table.insert (retXML, '<')
			if (closeTag) then
				table.insert (retXML, '/')
			end
			table.insert (retXML, tostring (tagName))
			table.insert (retXML, '>')
		end
	end

	if (type (strName) == 'table' and tParams == nil) then
		tParams = strName
		strName = nil
	end

	if (strName and tAttribs and type (tAttribs) == 'table') then
		local attribs = {
			strName
		}
		for k, v in pairs (tAttribs) do
			local a = {
				tostring (k),
				'=',
				'"',
				XMLEncode (tostring (v)),
				'"',
			}
			a = table.concat (a)
			table.insert (attribs, a)
		end
		strName = table.concat (attribs, ' ')
	end

	addTag (strName)

	if (type (tParams) == 'table') then
		local arraySize = #tParams
		local tableSize = 0
		for _, _ in pairs (tParams) do
			tableSize = tableSize + 1
		end
		if (arraySize == tableSize) then
			for _, subItem in ipairs (tParams) do
				table.insert (retXML, XMLTag (nil, subItem, tagSubTables, xmlEncodeElements))
			end

		else
			for k, v in pairs (tParams) do
				if (v == nil) then v = '' end
				if (type (v) == 'table') then
					if (k == 'image_list') then
						for _, image_list in pairs (v) do
							table.insert (retXML, image_list)
						end
					elseif (tagSubTables == true) then
						table.insert (retXML, XMLTag (k, v, tagSubTables, xmlEncodeElements))
					end
				else
					if (v == nil) then v = '' end

					addTag (k)

					if (xmlEncodeElements ~= false) then
						table.insert (retXML, XMLEncode (tostring (v)))
					else
						table.insert (retXML, tostring (v))
					end

					addTag (k, true)
				end
			end
		end

	elseif (tParams) then
		if (xmlEncodeElements ~= false) then
			table.insert (retXML, XMLEncode (tostring (tParams)))
		else
			table.insert (retXML, tostring (tParams))
		end
	end

	addTag (strName,true)

	return (table.concat (retXML))
end

--[[
	-- tests on tag = tag
	local t1 = '<a>b</a><tag>test string</tag><a>b</a>' -- 'test string', nil
	local t2 = '<a>b</a><tag testattrib="testval" testattrib2="test val">test</tag><a>b</a>' -- test, {testattrib = 'testval', testattrib2 = 'test val'}
	local t3 = '<a>b</a><ta g>test string</tag><a>b</a>' -- nil, nil
	local t4 = '<a>b</a><tagattrib>asdf</tagattrib>' -- nil, nil
	local t5 = '<a>b</a><tag/><a>b</a>' -- '', nil
	local t6 = '<a>b</a><tag /><a>b</a>' -- '', nil
	local t7 = '<a>b</a><tag testattrib="testval" testattrib2="test val"/><a>b</a>' -- '', , {testattrib = 'testval', testattrib2 = 'test val'}
	local t8 = '<a>b</a><tag testattrib="testval" testattrib2="test val" /><a>b</a>' -- '', , {testattrib = 'testval', testattrib2 = 'test val'}
--]]

function XMLCapture (xmlString, tag)
	-- plain tag
	local tagContents = string.match (xmlString, '<' .. tag .. '>(.-)</' .. tag .. '>')
	if (tagContents) then
		return tagContents, nil
	end

	-- tag with attributes
	local attributes, tagContents = string.match (xmlString, '<' .. tag .. '%s+(%S.-)>(.-)</' .. tag .. '>')
	if (attributes and tagContents) then
		return tagContents, attributes
	end

	-- self closing tag
	local selfClosed = string.match (xmlString, '<' .. tag .. '%s-/>')
	if (selfClosed) then
		return '', nil
	end

	-- self closing tag with attributes
	local attributes = string.match (xmlString, '<' .. tag .. '%s+(%S.-)%s-/>')
	if (attributes) then
		return '', attributes
	end
end

function RefreshNavs ()
	local cli = C4:CreateTCPClient ()
	:OnConnect (function (client)
			client:Write ('<c4soap name="PIP" async="1"></c4soap>\0'):Close ()
	end)
	:OnError (function (client)
			client:Close ()
	end)

	cli:Connect ('127.0.0.1', 5020)
end

function HideProxyInAllRooms (idBinding)
	idBinding = idBinding or 0
	if (idBinding == 0) then return end -- silently fail if no binding passed in.

	-- Get Bound Proxy's Device ID / Name.
	local id, name = next(C4:GetBoundConsumerDevices(C4:GetDeviceID(), idBinding))

	-- Send hide command to all rooms, for 'ALL' Navigator groups.
	for roomid, roomname in pairs(C4:GetDevicesByC4iName('roomdevice.c4i') or {}) do
		dbg ('Hiding device:"' .. name .. '" in room "' .. roomname .. '"')
		C4:SendToDevice(roomid, 'SET_DEVICE_HIDDEN_STATE', {PROXY_GROUP = 'ALL', DEVICE_ID = id, IS_HIDDEN = true})
	end
end

function GetFileName (deviceId)
	if (deviceId == nil) then
		deviceId = C4:GetDeviceID ()
	end

	local info = C4:GetDevices ({DeviceIds = tostring (deviceId)})

	local protocol = Select (info, deviceId, 'protocol')

	if (protocol) then
		info = protocol
	end

	local _, data = next (info)

	if (data.driverFileName) then
		return data.driverFileName
	end
end

function F2C (f)
	if (type (f) ~= 'number') then
		return
	end
	local c = (f - 32) * (5 / 9)
	c = math.floor ((c * 2) + 0.5) / 2
	return (c)
end

function C2F (c)
	if (type (c) ~= 'number') then
		return
	end
	local f = (c * (9 / 5)) + 32
	f = math.floor (f + 0.5)
	return (f)
end

function Serialize (d)
	if (type (d) == 'table') then
		local j = JSON:encode (d)
		if (j) then
			local b64 = C4:Base64Encode (j)
			if (b64) then
				return (b64)
			end
		end
	end
	return (d)
end

function Deserialize (b64)
	if (type (b64) == 'string') then
		local j = C4:Base64Decode (b64)
		if (j) then
			local d = JSON:decode (j)
			if (d) then
				return (d)
			end
		end
	end
	return (b64)
end

function SaltedEncrypt (key, plaintext)
	local cipher = 'AES-256-CBC'
	local options = AES_ENC_DEFAULTS

	local prepend_random = {}
	for i = 1, 16 do
		local randomChar = string.char (math.random (0, 255))
		table.insert (prepend_random, randomChar)
	end
	prepend_random = table.concat (prepend_random)

	local data = prepend_random .. plaintext

	if (string.len (key) ~= 32) then
		key = C4:Hash ('SHA256', key, SHA_ENC_DEFAULTS)
	end

	local result, errString = C4:Encrypt (cipher, key, nil, data, options)
	return result, errString
end

function SaltedDecrypt (key, ciphertext)
	local cipher = 'AES-256-CBC'
	local options = AES_DEC_DEFAULTS

	local data = ciphertext

	if (string.len (key) ~= 32) then
		key = C4:Hash ('SHA256', key, SHA_ENC_DEFAULTS)
	end

	local result, error = C4:Decrypt (cipher, key, nil, data, options)

	if (result) then
		result = string.sub (result, 17, -1)
	end
	return result, error
end

function EscapeForLuaPattern (s)
	if (type (s) ~= 'string') then
		return
	end
	local matches = {
		['%'] = '%%',
		['^'] = '%^',
		['$'] = '%$',
		['('] = '%(',
		[')'] = '%)',
		['.'] = '%.',
		['['] = '%[',
		[']'] = '%]',
		['*'] = '%*',
		['+'] = '%+',
		['-'] = '%-',
		['?'] = '%?',
	}
	return string.gsub (s, '.', matches)
end

function ShowPopupEverywhere (message, ok, delay, imgUrl)
	local params = {
		VAR_DEVICE_ID = 0,
		SIZE = 100,
		MESSAGE = (message or ''),
		SHOWOK = (ok and 'True') or 'False',
		DELAY = (delay or 0),
		IMGURL = (imgUrl or ''),
		VAR_VARIABLE_ID = 0,
	}

	local uiDevices = C4:GetProxyDevicesByName ('uidevice')

	for deviceId, _ in pairs (uiDevices or {}) do
		C4:SendToDevice (deviceId, 'SHOW_POPUP', params, true)
	end
end

function HideCurrentPopupEverywhere ()
	local uiDevices = C4:GetProxyDevicesByName ('uidevice')

	for deviceId, _ in pairs (uiDevices or {}) do
		C4:SendToDevice (deviceId, 'HIDE_POPUP', {}, true)
	end
end

function GetProject ()
	local h = C4:GetProjectItems ('DEVICES', 'PROXIES', 'LOCATIONS', 'NO_ROOT_TAGS', 'LIMIT_DEVICE_DATA')
	h = string.gsub (h, '<state>.-</state>', '')
	h = string.gsub (h, '<itemdata>.-</itemdata>', '')
	h = string.gsub (h, '<created_datetime>.-</created_datetime>', '')
	h = string.gsub (h, '<%w+/>', '')
	h = string.gsub (h, '>%s+<', '><')
	h = string.gsub (h, '><', '>\r\n<')
	h = h .. '\r\n'

	local p = {'{"project" : '}

	local c

	local item = 0
	local subitem = 0
	for line in string.gmatch (h, '(.-)\r\n') do
		if (string.find (line, '^<item')) then
			table.insert (p, '{')
			item = item + 1

		elseif (string.find (line, '^</item>')) then
			table.insert (p, '},')
			item = item - 1

		elseif (string.find (line, '^<subitems>')) then
			table.insert (p, '"subItems" : [')
			subitem = subitem + 1

		elseif (string.find (line, '^</subitems>')) then
				table.insert (p, '],')
				subitem = subitem - 1

		elseif (string.find (line, '^<id>')) then
			local id = string.match (line, '<id>(.-)</id>')
			if (id) then
				table.insert (p, '"id" : ' .. id .. ',')
			end

		elseif (string.find (line, '^<c4i>')) then
			local c4i = string.match (line, '<c4i>(.-)</c4i>')
			if (c4i) then
				table.insert (p, '"c4i" : "' .. c4i .. '",')
			end

		elseif (string.find (line, '^<type>')) then
			local deviceType = string.match (line, '<type>(.-)</type>')
			if (deviceType) then
				table.insert (p, '"deviceType" : ' .. deviceType .. ',')
			end

		--[[
			1 = ROOT
			2 = SITE
			3 = BUILDING
			4 = FLOOR
			5 = ROOM
			6 = DEVICE
			7 = PROXY
			8 = ROOM_DEVICE
			9 = AGENT
		]]

		elseif (string.find (line, '^<name>')) then
			local name = string.match (line, '<name>(.-)</name>')
			if (name) then
				table.insert (p, '"name" : ' .. JSON:encode (name) .. ',')
			end
		end
	end

	table.insert (p, '}')

	p = table.concat (p, '\r\n')

	p = string.gsub (p, ',%s+%]', '\r\n%]')
	p = string.gsub (p, ',%s+%}', '\r\n%}')

	local j

	local f = function ()
		j = JSON:decode (p)
	end

	local success, err = pcall (f)

	return (j)
end

function GetPathToDevice (deviceId, project)
	if (type (project ~= 'table')) then
		project = GetProject ()
	end

	if (project and project.project) then
		project = project.project
	else
		return
	end

	deviceId = tonumber (deviceId)

	if (deviceId == nil) then
		return
	end

	local path = {}

	local drill
	drill = function (item)
		local id = item.id
		local thisItem = {
			id = item.id,
			name = item.name,
			c4i = item.c4i,
			deviceType = item.deviceType,
		}
		if (id == deviceId) then
			table.insert (path, thisItem)
			return (true)
		elseif (item.subItems) then
			for _, subItemTable in ipairs (item.subItems) do
				local found = drill (subItemTable)
				if (found) then
					table.insert (path, thisItem)
					return (true)
				end
			end
		end
	end

	drill (project)

	return (path)
end

function GetLocals (depth)
	local vars = {}
	local i = 1
	depth = depth or 2

	while (true) do
		local name, value = debug.getlocal (depth, i)
		if (name ~= nil) then
			vars [name] = value
		else
			break
		end
		i = i + 1
	end

	return vars
end

function GetRandomString (length, alphaFirst)
	if (type (length) ~= 'number') then
		length = 10
	end
	if (length < 1) then
		length = 1
	end
	if (type (alphaFirst) ~= 'boolean') then
		alphaFirst = false
	end

	local s = {}
	local allowed = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
	while (#s < length) do
		local max = string.len (allowed)
		if (#s == 0 and alphaFirst) then
			max = max - 10
		end
		local random = math.random (1, max)
		local char = string.sub (allowed, random, random)
		table.insert (s, char)
	end
	s = table.concat (s)
	return s
end

function FileRead (filename)
	local content = ''
	if (C4:FileExists (filename)) then
		local file = C4:FileOpen (filename)
		local length = C4:FileGetSize (file)
		C4:FileSetPos (file, 0)
		content = C4:FileRead (file, length)
		C4:FileClose (file)
	end
	return (content)
end

function FileWrite (filename, content, overwrite)
	content = tostring (content) or ''
	local pos = 0
	if (overwrite and C4:FileExists (filename)) then
		C4:FileDelete (filename)
	end
	local file = C4:FileOpen (filename)
	if (not overwrite) then
		pos = C4:FileGetSize (file)
	end
	C4:FileSetPos (file, pos)
	local result = C4:FileWrite (file, content:len (), content)
	C4:FileClose (file)
end

function PersistSetValue (key, value, encrypted)
	if (encrypted == nil) then
		encrypted = false
	end

	if (C4.PersistSetValue) then
		C4:PersistSetValue (key, value, encrypted)
	else
		PersistData = PersistData or {}
		PersistData.LibValueStore = PersistData.LibValueStore or {}
		PersistData.LibValueStore [key] = value
	end
end

function PersistGetValue (key, encrypted)
	if (encrypted == nil) then
		encrypted = false
	end

	local value

	if (C4.PersistGetValue) then
		value = C4:PersistGetValue (key, encrypted)
		if (value == nil and encrypted == true) then
			value = C4:PersistGetValue (key, false)
			if (value ~= nil) then
				PersistSetValue (key, value, encrypted)
			end
		end
		if (value == nil) then
			if (PersistData and PersistData.LibValueStore and PersistData.LibValueStore [key]) then
				value = PersistData.LibValueStore [key]
				PersistSetValue (key, value, encrypted)
				PersistData.LibValueStore [key] = nil
				if (next (PersistData.LibValueStore) == nil) then
					PersistData.LibValueStore = nil
				end
			end
		end
	elseif (PersistData and PersistData.LibValueStore and PersistData.LibValueStore [key]) then
		value = PersistData.LibValueStore [key]
	end
	return value
end

function PersistDeleteValue (key)
	if (C4.PersistDeleteValue) then
		C4:PersistDeleteValue (key)
	else
		if (PersistData and PersistData.LibValueStore) then
			PersistData.LibValueStore [key] = nil
			if (next (PersistData.LibValueStore) == nil) then
				PersistData.LibValueStore = nil
			end
		end
	end
end

function Select (data, ...)
	if (type (data) ~= 'table') then
		return nil
	end

	local tablePack = function (...)
		return {
			n = select ('#', ...), ...
		}
	end

	local args = tablePack (...)

	local ret = data

	for i = 1, args.n do
		local index = args [i]
		if (index == nil or ret [index] == nil) then
			return nil
		end
		if (ret [index] ~= nil) then
			ret = ret [index]
		end
	end
	return ret
end

function GetConnections ()
	local connectionsXML = C4:GetDriverConfigInfo ('connections')

	local connections = {}
	for connection in string.gmatch (connectionsXML, '<connection>(.-)</connection>') do
		local id = tonumber (XMLCapture (connection, 'id'))
		if (id) then
			local classesXML = XMLCapture (connection, 'classes') or ''

			local classes = {}

			for class in string.gmatch (classesXML, '<class>(.-)</class>') do
				table.insert (classes, {
					classname = XMLCapture (class, 'classname'),
					autobind = (XMLCapture (class, 'autobind') == 'True'),
				})
			end

			connections [id] = {
				id = id,
				type = tonumber (XMLCapture (connection, 'type')),
				connectionname = XMLCapture (connection, 'name'),
				consumer = (XMLCapture (connection, 'consumer') == 'True'),
				linelevel = (XMLCapture (connection, 'linelevel') == 'True'),
				idautobind = XMLCapture (connection, 'idautobind'),
				classes = classes,
			}
		end
	end
	return connections
end

function GetTableSize (t)
	if (type (t) ~= 'table') then
		return 0
	end

	local size = 0
	for _, _ in pairs (t) do
		size = size + 1
	end
	return size
end
-- Copyright 2023 Snap One, LLC. All rights reserved.

COMMON_WEBSOCKET_VER = 11

require ('global.handlers')
require ('global.timer')

Metrics = require ('module.metrics')

local WebSocket = {}

do -- define globals
	DEBUG_WEBSOCKET = false
end

function WebSocket:new (url, additionalHeaders, wssOptions)
	if (type (additionalHeaders) ~= 'table') then
		additionalHeaders = nil
	end

	if (WebSocket.Sockets and WebSocket.Sockets [url]) then
		local ws = WebSocket.Sockets [url]
		ws.additionalHeaders = additionalHeaders
		return ws
	end

	local protocol, host, port, resource -- important values to be incorporated into our WebSocket object

	local rest, hostport -- temporary values for parsing

	protocol, rest = string.match (url or '', '(wss?)://(.*)')

	hostport, resource = string.match (rest or '', '(.-)(/.*)')
	if (not (hostport and resource)) then
		hostport = rest
		resource = '/'
	end

	host, port = string.match (hostport or '', '(.-):(.*)')

	if (not (host and port)) then
		host = hostport
		if (protocol == 'ws') then port = 80
		elseif (protocol == 'wss') then port = 443
		end
	end

	port = tonumber (port)

	if (type (wssOptions) ~= 'table') then
		wssOptions = {}
	end

	if (protocol and host and port and resource) then
		local ws = {
			url = url,
			protocol = protocol,
			host = host,
			port = port,
			resource = resource,
			buf = '',
			ping_interval = 30,
			pong_response_interval = 10,
			additionalHeaders = additionalHeaders or {},
			wssOptions = wssOptions,
		}

		setmetatable (ws, self)
		self.__index = self

		ws.metrics = Metrics:new ('dcp_websocket', COMMON_WEBSOCKET_VER)

		WebSocket.Sockets = WebSocket.Sockets or {}
		WebSocket.Sockets [url] = ws

		ws.metrics:SetCounter ('Init')
		ws:setupC4Connection ()

		return ws
	else
		self.metrics:SetCounter ('Error_Init')
		return nil, 'invalid WebSocket URL provided:' .. (url or '')
	end
end

function WebSocket:delete ()
	self.deleteAfterClosing = true
	self:Close ()
	if (WebSocket.Sockets) then
		if (self.url) then
			WebSocket.Sockets [self.url] = nil
		end
		if (self.netBinding) then
			OCS [self.netBinding] = nil
			RFN [self.netBinding] = nil
			WebSocket.Sockets [self.netBinding] = nil
		end
	end

	self.metrics:SetCounter ('Delete')
	return nil
end

function WebSocket:Start ()
	print ('Starting Web Socket... Opening net connection to ' .. self.url)

	if (self.netBinding and self.protocol and self.port) then
		self.metrics:SetCounter ('Start')
		C4:NetDisconnect (self.netBinding, self.port)
		C4:NetConnect (self.netBinding, self.port)
	else
		self.metrics:SetCounter ('Error_Start')
		print ('C4 network connection not setup')
	end

	return self
end

function WebSocket:Close ()
	self.running = false
	if (self.connected) then
		local pkt = string.char (0x88, 0x82, 0x00, 0x00, 0x00, 0x00, 0x03, 0xE8)
		if (DEBUG_WEBSOCKET) then
			print ('TX CLOSE REQUEST')
		end
		self:sendToNetwork (pkt)
	end

	local _timer = function (timer)
		C4:NetDisconnect (self.netBinding, self.port)
		if (self.deleteAfterClosing) then
			self.deleteAfterClosing = nil
			C4:SetBindingAddress (self.netBinding, '')
		end
	end

	self.ClosingTimer = SetTimer (self.ClosingTimer, 3 * ONE_SECOND, _timer)

	return self
end

function WebSocket:Send (s)
	if (self.connected) then
		local len = string.len (s)
		local lenstr
		if (len <= 125) then
			lenstr = string.char (0x81, bit.bor (len, 0x80))
		elseif (len <= 65535) then
			lenstr = string.char (0x81, bit.bor (126, 0x80)) .. tohex (string.format ('%04X', len))
		else
			lenstr = string.char (0x81, bit.bor (127, 0x80)) .. tohex (string.format ('%16X', len))
		end

		local mask = {
			math.random (0, 255),
			math.random (0, 255),
			math.random (0, 255),
			math.random (0, 255),
		}

		local pkt = {
			lenstr,
			string.char (mask [1]),
			string.char (mask [2]),
			string.char (mask [3]),
			string.char (mask [4]),
		}

		table.insert (pkt, self:Mask (s, mask))

		pkt = table.concat (pkt)
		if (DEBUG_WEBSOCKET) then
			local d = {'', 'TX'}

			table.insert (d, '')
			table.insert (d, s)
			table.insert (d, '')

			d = table.concat (d, '\r\n')

			print (d)
		end
		self:sendToNetwork (pkt)
	end

	return self
end

function WebSocket:SetProcessMessageFunction (f)
	local _f = function (websocket, data)
		local success, ret = pcall (f, websocket, data)
		if (success == false) then
			self.metrics:SetCounter ('Error_ProcessMessageCallback')
			print ('Websocket callback ProcessMessage error: ', ret, data)
		end
	end
	self.ProcessMessage = _f

	return self
end

function WebSocket:SetClosedByRemoteFunction (f)
	local _f = function (websocket)
		local data = "Disconnected: Remote"
		local success, ret = pcall (f, websocket, data)
		if (success == false) then
			self.metrics:SetCounter ('Error_ClosedByRemoteCallback')
			print ('Websocket callback ClosedByRemote error: ', ret, data)
		end
	end
	self.ClosedByRemote = _f

	return self
end

function WebSocket:SetEstablishedFunction (f)
	local _f = function (websocket)
		local data = "Established"
		local success, ret = pcall (f, websocket, data)
		if (success == false) then
			self.metrics:SetCounter ('Error_EstablishedCallback')
			print ('Websocket callback Established error: ', ret, data)
		end
	end
	self.Established = _f

	return self
end

function WebSocket:SetOfflineFunction (f)
	local _f = function (websocket)
		local data = "Disconnected"
		local success, ret = pcall (f, websocket, data)
		if (success == false) then
			self.metrics:SetCounter ('Error_OfflineCallback')
			print ('Websocket callback Offline error: ', ret, data)
		end
	end
	self.Offline = _f

	return self
end

-- Functions below this line should not be called directly by users of this library

function WebSocket:setupC4Connection ()
	local i = 6100
	while (not self.netBinding and i < 6200) do
		local checkAddress = C4:GetBindingAddress (i)
		if (checkAddress == nil or checkAddress == '') then
			self.netBinding = i
		end
		i = i + 1
	end

	if (self.netBinding and self.protocol) then
		WebSocket.Sockets = WebSocket.Sockets or {}
		WebSocket.Sockets [self.netBinding] = self

		if (self.protocol == 'wss') then
			C4:CreateNetworkConnection (self.netBinding, self.host, 'SSL')
			C4:NetPortOptions (self.netBinding, self.port, 'SSL', self.wssOptions)
		else
			C4:CreateNetworkConnection (self.netBinding, self.host)
		end

		OCS = OCS or {}
		OCS [self.netBinding] = function (idBinding, nPort, strStatus)
			self:ConnectionChanged (strStatus)
		end

		RFN = RFN or {}
		RFN [self.netBinding] = function (idBinding, nPort, strData)
			self:ParsePacket (strData)
		end
	else
		self.metrics:SetCounter ('Error_NoNetBinding')
	end
	return self
end

function WebSocket:MakeHeaders ()
	self.key = ''
	for i = 1, 16 do
		self.key = self.key .. string.char (math.random (33, 125))
	end
	self.key = C4:Base64Encode (self.key)

	local headers = {
		'GET ' .. self.resource .. ' HTTP/1.1',
		'Host: ' .. self.host .. ':' .. self.port,
		'Cache-Control: no-cache',
		'Pragma: no-cache',
		'Connection: Upgrade',
		'Upgrade: websocket',
		'Sec-WebSocket-Key: ' .. self.key,
		'Sec-WebSocket-Version: 13',
		'User-Agent: C4WebSocket/' .. COMMON_WEBSOCKET_VER,
	}

	for _, header in ipairs (self.additionalHeaders or {}) do
		table.insert (headers, header)
	end

	table.insert (headers, '\r\n')

	headers = table.concat (headers, '\r\n')

	return headers
end

function WebSocket:ParsePacket (strData)
	self.buf = (self.buf or '') .. strData

	if (self.running) then
		self:parseWSPacket ()
	else
		self:parseHTTPPacket ()
	end
end

function WebSocket:parseWSPacket ()
	local _, h1, h2, b1, b2, b3, b4, b5, b6, b7, b8 = string.unpack (self.buf, 'bbbbbbbbbb')

	local final = (bit.band (h1, 0x80) == 0x80)
	local rsv1 = (bit.band (h1, 0x40) == 0x40)
	local rsv2 = (bit.band (h1, 0x20) == 0x20)
	local rsv3 = (bit.band (h1, 0x10) == 0x10)
	local opcode = bit.band (h1, 0x0F)

	local masked = (bit.band (h2, 0x80) == 0x80)
	local mask
	local len = bit.band (h2, 0x7F)

	local msglen = 0
	local headerlen = 2
	if (len <= 125) then
		-- 1-byte length
		msglen = len
	elseif (len == 126) then
		-- 2-byte length
		msglen = msglen + b1; msglen = msglen * 0x100
		msglen = msglen + b2;
		headerlen = 4
	elseif (len == 127) then
		-- 8-byte length
		msglen = msglen + b1; msglen = msglen * 0x100
		msglen = msglen + b2; msglen = msglen * 0x100
		msglen = msglen + b3; msglen = msglen * 0x100
		msglen = msglen + b4; msglen = msglen * 0x100
		msglen = msglen + b5; msglen = msglen * 0x100
		msglen = msglen + b6; msglen = msglen * 0x100
		msglen = msglen + b7; msglen = msglen * 0x100
		msglen = msglen + b8;
		headerlen = 10
	end

	if (masked) then
		local maskbytes = string.sub (self.buf, headerlen + 1, headerlen + 5)
		mask = {}
		for i = 1, 4 do
			mask [i] = string.byte (string.sub (maskbytes, i, i))
		end
		headerlen = headerlen + 4
	end

	if (string.len (self.buf) >= headerlen + msglen) then
		local thisFragment = string.sub (self.buf, headerlen + 1, headerlen + msglen)
		if (masked) then
			if (mask) then
				thisFragment = self:Mask (thisFragment, mask)
			else
				self.metrics:SetCounter ('Error_NoMaskReceived')
				print ('masked bit set but no mask received')
				self.buf = ''
				return
			end
		end
		self.buf = string.sub (self.buf, headerlen + msglen + 1)

		if (opcode == 0x08) then
			self.metrics:SetCounter ('ClosedByRemote')
			if (DEBUG_WEBSOCKET) then
				print ('RX CLOSE REQUEST')
			end
			if (self.ClosedByRemote) then
				self:ClosedByRemote ()
			end

		elseif (opcode == 0x09) then -- ping control frame
			if (DEBUG_WEBSOCKET) then
				print ('RX PING')
			end
			self:Pong ()

		elseif (opcode == 0x0A) then -- pong control frame
			if (DEBUG_WEBSOCKET) then
				print ('RX PONG')
			end
			self.PongResponseTimer = CancelTimer (self.PongResponseTimer)

		elseif (opcode == 0x00) then -- continuation frame
			if (not self.fragment) then
				self.metrics:SetCounter ('Error_FramesOutOfOrder')
				print ('error: received continuation frame before start frame')
				self.buf = ''
				return
			end
			self.fragment = self.fragment .. thisFragment

		elseif (opcode == 0x01 or opcode == 0x02) then -- non-control frame, beginning of fragment
			self.fragment = thisFragment
		end

		if (final and opcode < 0x08) then
			local data = self.fragment
			self.fragment = nil

			if (DEBUG_WEBSOCKET) then
				local d = {'', 'RX'}

				table.insert (d, '')
				table.insert (d, data)
				table.insert (d, '')

				d = table.concat (d, '\r\n')

				print (d)
			end

			if (self.ProcessMessage) then
				self:ProcessMessage (data)
			end
		end

		if (string.len (self.buf) > 0) then
			self:ParsePacket ('')
		end
	end
end

function WebSocket:parseHTTPPacket ()
	local headers = {}
	for line in string.gmatch (self.buf, '(.-)\r\n') do
		local k, v = string.match (line, '%s*(.-)%s*[:/*]%s*(.+)')
		if (k and v) then
			k = string.upper (k)
			headers [k] = v
		end
	end

	local EOH = string.find (self.buf, '\r\n\r\n')

	if (EOH and headers ['SEC-WEBSOCKET-ACCEPT']) then
		self.buf = string.sub (self.buf, EOH + 4)
		local check = self.key .. '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
		local hash = C4:Hash ('sha1', check, {['return_encoding'] = 'BASE64'})

		if (headers ['SEC-WEBSOCKET-ACCEPT'] == hash and
			string.lower (headers ['UPGRADE']) == 'websocket' and
			string.lower (headers ['CONNECTION']) == 'upgrade') then

			print ('WS ' .. self.url .. ' running')

			self.running = true
			self.metrics:SetCounter ('Running')
			if (self.Established) then
				self:Established ()
			end
		end
	end
end

function WebSocket:Ping ()
	if (self.connected) then
		-- MASK of 0x00's
		local pkt = string.char (0x89, 0x80, 0x00, 0x00, 0x00, 0x00)
		if (DEBUG_WEBSOCKET) then
			print ('TX PING')
		end

		local _timer = function (timer)
			self.metrics:SetCounter ('MissingPong')
			print ('WS ' .. self.url .. ' appears disconnected - timed out waiting for PONG')
			self:Close ()
		end
		self.PongResponseTimer = SetTimer (self.PongResponseTimer, self.pong_response_interval * ONE_SECOND, _timer)

		self:sendToNetwork (pkt)
	end
end

function WebSocket:Pong ()
	if (self.connected) then
		local pkt = string.char (0x8A, 0x80, 0x00, 0x00, 0x00, 0x00)
		if (DEBUG_WEBSOCKET) then
			print ('TX PONG')
		end
		self:sendToNetwork (pkt)
	end
end

function WebSocket:ConnectionChanged (strStatus)
	self.connected = (strStatus == 'ONLINE')

	self.PingTimer = CancelTimer (self.PingTimer)
	self.PongResponseTimer = CancelTimer (self.PongResponseTimer)

	if (self.connected) then
		local pkt = self:MakeHeaders ()
		self:sendToNetwork (pkt)

		local _timer = function (timer)
			self:Ping ()
		end
		self.PingTimer = SetTimer (self.PingTimer, self.ping_interval * ONE_SECOND, _timer, true)
		self.metrics:SetCounter ('Connected')
		print ('WS ' .. self.url .. ' connected')
	else
		if (self.running) then
			self.metrics:SetCounter ('DisconnectedWhileRunning')
			print ('WS ' .. self.url .. ' disconnected while running')
		else
			self.metrics:SetCounter ('DisconnectedWhileNotRunning')
			print ('WS ' .. self.url .. ' disconnected while not running')
		end
		self.running = false
		if (self.Offline) then
			self:Offline ()
		end
	end
end

function WebSocket:sendToNetwork (packet)
	C4:SendToNetwork (self.netBinding, self.port, packet)
end

function WebSocket:Mask (s, mask)
	if (type (mask) == 'table') then
	elseif (type (mask) == 'string' and string.len (mask) >= 4) then
		local m = {}
		for i = 1, string.len (mask) do
			table.insert (m, string.byte (mask [i]))
		end
		mask = m
	end

	local slen = string.len (s)
	local mlen = #mask

	local packet = {}

	for i = 1, slen do
		local pos = i % mlen
		if (pos == 0) then pos = mlen end
		local maskbyte = mask [pos]
		local sbyte = string.sub (s, i, i)
		local byte = string.byte (sbyte)
		local char = string.char (bit.bxor (byte, maskbyte))
		table.insert (packet, char)
	end

	packet = table.concat (packet)
	return (packet)
end

return WebSocket
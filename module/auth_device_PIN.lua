-- Copyright 2019 Control4 Corporation. All rights reserved.

AUTH_DEVICE_PIN_VER = 6

require ('global.url')
require ('global.timer')

local oauth = {}

function oauth:new (tParams)
	local o = {
		AUTH_ENDPOINT_URI = tParams.AUTH_ENDPOINT_URI,
		TOKEN_ENDPOINT_URI = tParams.TOKEN_ENDPOINT_URI,

		API_CLIENT_ID = tParams.API_CLIENT_ID,
		API_SECRET = tParams.API_SECRET,

		SCOPES = tParams.SCOPES,

		notifyHandler = {},
		Timer = {},
	}

	setmetatable (o, self)
	self.__index = self

	return o
end

function oauth:GetPINCode (contextInfo, extras)
	--print ('GetPINCode', contextInfo)
	if (type (contextInfo) ~= 'table') then
		contextInfo = {}
	end

	local args = {
		client_id = self.API_CLIENT_ID,
		scope = (self.SCOPES and table.concat (self.SCOPES, ' ')) or nil,
	}

	if (extras and type (extras == 'table')) then
		for k, v in pairs (extras) do
			args [k] = v
		end
	end

	local url = self.AUTH_ENDPOINT_URI

	local data = MakeURL (nil, args)

	local headers = {
		['Content-Type'] = 'application/x-www-form-urlencoded'
	}

	self:urlPost (url, data, headers, 'GetPINCodeResponse', {contextInfo = contextInfo})
end

function oauth:GetPINCodeResponse (strError, responseCode, tHeaders, data, context, url)
	--print ('GetPINCodeResponse', strError, responseCode, tHeaders, data, context, url)
	if (strError) then
		dbg ('Error with GetPINCodeResponse:', strError)
		return
	end

	local contextInfo = context.contextInfo

	if (responseCode == 200) then
		self.device_code = data.device_code
		local user_code = data.user_code
		local verification_url = data.verification_url
		local expires_in = data.expires_in or (5 * ONE_MINUTE)
		local interval = data.interval or 5

		if (self.notifyHandler.PINCodeReceived) then
			self.notifyHandler.PINCodeReceived (contextInfo, verification_url, user_code)
		end

		local _timedOut = function (timer)
			CancelTimer (self.Timer.CheckPINCode)

			if (self.notifyHandler.PINCodeExpired) then
				self.notifyHandler.PINCodeExpired (contextInfo)
			end
		end
		self.Timer.GetPINCodeExpired = SetTimer (self.Timer.GetPINCodeExpired, expires_in * 1000, _timedOut)

		local _timer = function (timer)
			self:CheckPINCode (contextInfo)
		end
		self.Timer.CheckPINCode = SetTimer (self.Timer.CheckPINCode, interval * 1000, _timer, true)
	end
end

function oauth:CheckPINCode (contextInfo)
	--print ('CheckPINCode', contextInfo)

	if (type (contextInfo) ~= 'table') then
		contextInfo = {}
	end

	local args = {
		client_id = self.API_CLIENT_ID,
		client_secret = self.API_SECRET,
		code = self.device_code,
		grant_type = 'http://oauth.net/grant_type/device/1.0',
	}

	local url = self.TOKEN_ENDPOINT_URI

	local data = MakeURL (nil, args)

	local headers = {
		['Content-Type'] = 'application/x-www-form-urlencoded'
	}

	self:urlPost (url, data, headers, 'CheckPINCodeResponse', {contextInfo = contextInfo})
end

function oauth:CheckPINCodeResponse (strError, responseCode, tHeaders, data, context, url)
	--print ('CheckPINCodeResponse', strError, responseCode, tHeaders, data, context, url)
	if (strError) then
		dbg ('Error with CheckPINCodeResponse:', strError)
		return
	end

	local contextInfo = context.contextInfo

	if (responseCode == 200) then
		-- state exists and has been authorized
		CancelTimer (self.Timer.CheckPINCode)
		CancelTimer (self.Timer.GetPINCodeExpired)

		self:GetTokenResponse (strError, responseCode, tHeaders, data, context, url)

	elseif (responseCode == 400) then
		if (self.notifyHandler.PINCodeWaiting) then
			self.notifyHandler.PINCodeWaiting (contextInfo)
		end

	elseif (responseCode == 403) then
		-- state exists and has been denied authorization by the service

		if (self.notifyHandler.PINCodeDenied) then
			self.notifyHandler.PINCodeDenied (contextInfo, data.error, data.error_description, data.error_uri)
		end

		CancelTimer (self.Timer.CheckPINCode)
		CancelTimer (self.Timer.GetPINCodeExpired)
	end
end

function oauth:RefreshToken (contextInfo)
	--print ('RefreshToken')
	if (self.REFRESH_TOKEN == nil) then
		return
	end

	if (type (contextInfo) ~= 'table') then
		contextInfo = {}
	end

	local args = {
		refresh_token = self.REFRESH_TOKEN,
		client_id = self.API_CLIENT_ID,
		client_secret = self.API_SECRET,
		grant_type = 'refresh_token',
	}

	local url = self.TOKEN_ENDPOINT_URI

	local data = MakeURL (nil, args)

	local headers = {
		['Content-Type'] = 'application/x-www-form-urlencoded',
	}

	self:urlPost (url, data, headers, 'GetTokenResponse', {contextInfo = contextInfo})
end

function oauth:GetTokenResponse (strError, responseCode, tHeaders, data, context, url)
	--print ('GetTokenResponse', strError, responseCode, tHeaders, data, context, url)
	if (strError) then
		dbg ('Error with GetToken:', strError)
		local _timer = function (timer)
			self:RefreshToken ()
		end
		self.Timer.RefreshToken = SetTimer (self.Timer.RefreshToken, 30 * 1000, _timer)
		return
	end

	local contextInfo = context.contextInfo

	if (responseCode == 200) then
		self.ACCESS_TOKEN = data.access_token
		self.REFRESH_TOKEN = data.refresh_token or self.REFRESH_TOKEN

		self.SCOPE = data.scope or self.SCOPE

		self.EXPIRES_IN = data.expires_in

		if (self.EXPIRES_IN and self.REFRESH_TOKEN) then
			local _timer = function (timer)
				self:RefreshToken ()
			end

			self.Timer.RefreshToken = SetTimer (self.Timer.RefreshToken, self.EXPIRES_IN * 950, _timer)
		end

		if (self.notifyHandler.AccessTokenGranted) then
			self.notifyHandler.AccessTokenGranted (contextInfo, self.ACCESS_TOKEN, self.REFRESH_TOKEN)
		end

	elseif (responseCode >= 400 and responseCode < 500) then
		if (self.notifyHandler.AccessTokenDenied) then
			self.notifyHandler.AccessTokenDenied (contextInfo, data.error, data.error_description, data.error_uri)
		end
	end
end

function oauth:urlDo (method, url, data, headers, callback, context)
	local ticketHandler = function (strError, responseCode, tHeaders, data, context, url)
		local func = self [callback]
		local success, ret = pcall (func, self, strError, responseCode, tHeaders, data, context, url)
	end

	urlDo (method, url, data, headers, ticketHandler, context)
end

function oauth:urlGet (url, headers, callback, context)
	self:urlDo ('GET', url, data, headers, callback, context)
end

function oauth:urlPost (url, data, headers, callback, context)
	self:urlDo ('POST', url, data, headers, callback, context)
end

function oauth:urlPut (url, data, headers, callback, context)
	self:urlDo ('PUT', url, data, headers, callback, context)
end

function oauth:urlDelete (url, headers, callback, context)
	self:urlDo ('DELETE', url, data, headers, callback, context)
end

function oauth:urlCustom (url, method, data, headers, callback, context)
	self:urlDo (method, url, data, headers, callback, context)
end

return oauth

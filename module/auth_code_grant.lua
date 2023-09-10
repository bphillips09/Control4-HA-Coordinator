-- Copyright 2023 Snap One, LLC. All rights reserved.

AUTH_CODE_GRANT_VER = 27

require ('global.lib')
require ('global.url')
require ('global.timer')

pcall (require, 'global.make_short_link')

Metrics = require ('module.metrics')

local oauth = {}

function oauth:new (tParams, providedRefreshToken)
	local o = {
		NAME = tParams.NAME,
		AUTHORIZATION = tParams.AUTHORIZATION,

		SHORT_LINK_AUTHORIZATION = tParams.SHORT_LINK_AUTHORIZATION,
		LINK_CHANGE_CALLBACK = tParams.LINK_CHANGE_CALLBACK,

		REDIRECT_URI = tParams.REDIRECT_URI,
		AUTH_ENDPOINT_URI = tParams.AUTH_ENDPOINT_URI,
		TOKEN_ENDPOINT_URI = tParams.TOKEN_ENDPOINT_URI,

		REDIRECT_DURATION = tParams.REDIRECT_DURATION,

		API_CLIENT_ID = tParams.API_CLIENT_ID,
		API_SECRET = tParams.API_SECRET,

		SCOPES = tParams.SCOPES,

		TOKEN_HEADERS = tParams.TOKEN_HEADERS,

		USE_PKCE = tParams.USE_PKCE,

		notifyHandler = {},
		Timer = {},
	}

	if (tParams.USE_BASIC_AUTH_HEADER) then
		o.BasicAuthHeader = 'Basic ' .. C4:Base64Encode (tParams.API_CLIENT_ID .. ':' .. tParams.API_SECRET)
	end

	setmetatable (o, self)
	self.__index = self

	o.metrics = Metrics:new ('dcp_auth_code', AUTH_CODE_GRANT_VER, (o.NAME or o.API_CLIENT_ID))

	local initialRefreshToken

	if (providedRefreshToken) then
		initialRefreshToken = providedRefreshToken
	else
		local persistStoreKey = C4:Hash ('SHA256', C4:GetDeviceID () .. o.API_CLIENT_ID, SHA_ENC_DEFAULTS)
		local encryptedToken = PersistGetValue (persistStoreKey)
		if (encryptedToken) then
			local encryptionKey = C4:GetDeviceID () .. o.API_SECRET .. o.API_CLIENT_ID
			local refreshToken, errString = SaltedDecrypt (encryptionKey, encryptedToken)
			if (errString) then
				o.metrics:SetString ('Error_DecryptRefreshToken', errString)
			end
				if (refreshToken) then
				initialRefreshToken = refreshToken
			end
		end
	end

	if (initialRefreshToken) then
		o.metrics:SetCounter ('InitWithToken')
		local _timer = function (timer)
			o:RefreshToken (nil, initialRefreshToken)
		end
		SetTimer (nil, ONE_SECOND, _timer)
	else
		o.metrics:SetCounter ('InitWithoutToken')
	end

	local willGenerateRefreshEvent = (initialRefreshToken ~= nil)

	return o, willGenerateRefreshEvent
end

function oauth:MakeState (contextInfo, extras, uriToCompletePage)
	if (type (contextInfo) ~= 'table') then
		contextInfo = {}
	end

	local state = GetRandomString (50)

	local url = MakeURL (self.REDIRECT_URI .. 'state')

	local headers = {
		Authorization = self.AUTHORIZATION,
	}

	local data = {
		duration = self.REDIRECT_DURATION,
		clientId = self.API_CLIENT_ID,
		authEndpointURI = self.AUTH_ENDPOINT_URI,
		state = state,
		redirectURI = uriToCompletePage,
	}

	local context = {
		contextInfo = contextInfo,
		state = state,
		extras = extras
	}

	self.metrics:SetCounter ('MakeStateAttempt')
	self:urlPost (url, data, headers, 'MakeStateResponse', context)
end

function oauth:MakeStateResponse (strError, responseCode, tHeaders, data, context, url)
	if (strError) then
		dbg ('Error with MakeState', strError)
		return
	end

	local contextInfo = context.contextInfo

	if (responseCode == 200) then
		self.metrics:SetCounter ('MakeStateSuccess')
		local state = context.state
		local extras = context.extras

		local nonce = data.nonce
		local expiresAt = data.expiresAt or (os.time () + self.REDIRECT_DURATION)

		local timeRemaining = expiresAt - os.time ()

		local _timedOut = function (timer)
			CancelTimer (self.Timer.CheckState)

			self:setLink ('')

			self.metrics:SetCounter ('ActivationTimeOut')
			self:notify ('ActivationTimeOut', contextInfo)
		end

		self.Timer.GetCodeStatusExpired = SetTimer (self.Timer.GetCodeStatusExpired, timeRemaining * ONE_SECOND, _timedOut)

		local _timer = function (timer)
			self:CheckState (state, contextInfo, nonce)
		end
		self.Timer.CheckState = SetTimer (self.Timer.CheckState, 5 * ONE_SECOND, _timer, true)

		self:GetLinkCode (state, contextInfo, extras)
	end
end

function oauth:GetLinkCode (state, contextInfo, extras)
	if (type (contextInfo) ~= 'table') then
		contextInfo = {}
	end

	local scope
	if (self.SCOPES) then
		if (type (self.SCOPES) == 'table') then
			scope = table.concat (self.SCOPES, ' ')
		elseif (type (self.SCOPES) == 'string') then
			scope = self.SCOPES
		end
	end

	local args = {
		client_id = self.API_CLIENT_ID,
		response_type = 'code',
		redirect_uri = self.REDIRECT_URI .. 'callback',
		state = state,
		scope = scope,
	}

	if (self.USE_PKCE) then
		self.code_verifier = GetRandomString (128)

		local code_challenge = C4:Hash ('SHA256', self.code_verifier, SHA_ENC_DEFAULTS)
		local code_challenge_b64 = C4:Base64Encode (code_challenge)
		local code_challenge_b64_url = code_challenge_b64:gsub ('%+', '-'):gsub ('%/', '_'):gsub ('%=', '')

		args.code_challenge = code_challenge_b64_url
		args.code_challenge_method = 'S256'
	end

	if (extras and type (extras) == 'table') then
		for k, v in pairs (extras) do
			args [k] = v
		end
	end

	local link = MakeURL (self.AUTH_ENDPOINT_URI, args)

	if (self.SHORT_LINK_AUTHORIZATION and MakeShortLink) then
		local _linkCallback = function (shortLink)
			self:setLink (shortLink, contextInfo)
		end
		MakeShortLink (link, _linkCallback, self.SHORT_LINK_AUTHORIZATION)
	else
		self:setLink (link, contextInfo)
	end
end

function oauth:CheckState (state, contextInfo, nonce)
	if (type (contextInfo) ~= 'table') then
		contextInfo = {}
	end

	local url = MakeURL (self.REDIRECT_URI .. 'state', {state = state, nonce = nonce})

	self:urlGet (url, nil, 'CheckStateResponse', {state = state, contextInfo = contextInfo})
end

function oauth:CheckStateResponse (strError, responseCode, tHeaders, data, context, url)
	if (strError) then
		dbg ('Error with CheckState:', strError)
		return
	end

	local contextInfo = context.contextInfo

	if (responseCode == 200 and data.code) then
		-- state exists and has been authorized

		CancelTimer (self.Timer.CheckState)
		CancelTimer (self.Timer.GetCodeStatusExpired)

		self:GetUserToken (data.code, contextInfo)

		self.metrics:SetCounter ('LinkCodeConfirmed')
		self:notify ('LinkCodeConfirmed', contextInfo)

	elseif (responseCode == 204) then
		self:notify ('LinkCodeWaiting', contextInfo)

	elseif (responseCode == 401) then
		-- nonce value incorrect or missing for this state

		CancelTimer (self.Timer.CheckState)
		CancelTimer (self.Timer.GetCodeStatusExpired)

		self:setLink ('')

		self.metrics:SetCounter ('LinkCodeError')
		self:notify ('LinkCodeError', contextInfo)

	elseif (responseCode == 403) then
		-- state exists and has been denied authorization by the service

		CancelTimer (self.Timer.CheckState)
		CancelTimer (self.Timer.GetCodeStatusExpired)

		self:setLink ('')

		self.metrics:SetCounter ('LinkCodeDenied')
		if (data.error) then
			self.metrics:SetString ('LinkCodeDeniedReason', data.error)
		end
		if (data.error_description) then
			self.metrics:SetString ('LinkCodeDeniedDescription', data.error_description)
		end
		self:notify ('LinkCodeDenied', contextInfo, data.error, data.error_description, data.error_uri)

	elseif (responseCode == 404) then
		-- state doesn't exist

		CancelTimer (self.Timer.CheckState)
		CancelTimer (self.Timer.GetCodeStatusExpired)

		self:setLink ('')

		self.metrics:SetCounter ('LinkCodeExpired')
		self:notify ('LinkCodeExpired', contextInfo)
	end
end

function oauth:GetUserToken (code, contextInfo)
	if (type (contextInfo) ~= 'table') then
		contextInfo = {}
	end

	if (code) then
		local args = {
			client_id = self.API_CLIENT_ID,
			client_secret = self.API_SECRET,
			grant_type = 'authorization_code',
			code = code,
			redirect_uri = self.REDIRECT_URI .. 'callback',
		}

		if (self.USE_PKCE) then
			args.code_verifier = self.code_verifier
		end

		local url = self.TOKEN_ENDPOINT_URI

		local data = MakeURL (nil, args)

		local headers = {
			['Content-Type'] = 'application/x-www-form-urlencoded',
			['Authorization'] = self.BasicAuthHeader,
		}

		if (self.TOKEN_HEADERS and type (self.TOKEN_HEADERS == 'table')) then
			for k, v in pairs (self.TOKEN_HEADERS) do
				if (not (headers [k])) then
					headers [k] = v
				end
			end
		end

		self:urlPost (url, data, headers, 'GetTokenResponse', {contextInfo = contextInfo})
	end
end

function oauth:RefreshToken (contextInfo, newRefreshToken)
	if (newRefreshToken) then
		self.REFRESH_TOKEN = newRefreshToken
	end

	if (self.REFRESH_TOKEN == nil) then
		self.metrics:SetCounter ('NoRefreshToken')
		return false
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
		['Authorization'] = self.BasicAuthHeader,
	}

	if (self.TOKEN_HEADERS and type (self.TOKEN_HEADERS == 'table')) then
		for k, v in pairs (self.TOKEN_HEADERS) do
			if (not (headers [k])) then
				headers [k] = v
			end
		end
	end

	self:urlPost (url, data, headers, 'GetTokenResponse', {contextInfo = contextInfo})
end

function oauth:GetTokenResponse (strError, responseCode, tHeaders, data, context, url)
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

		local persistStoreKey = C4:Hash ('SHA256', C4:GetDeviceID () .. self.API_CLIENT_ID, SHA_ENC_DEFAULTS)

		local encryptionKey = C4:GetDeviceID () .. self.API_SECRET .. self.API_CLIENT_ID
		local encryptedToken, errString = SaltedEncrypt (encryptionKey, self.REFRESH_TOKEN)
		if (errString) then
			self.metrics:SetString ('Error_EncryptRefreshToken', errString)
		end

		PersistSetValue (persistStoreKey, encryptedToken)

		self.SCOPE = data.scope or self.SCOPE

		self.EXPIRES_IN = data.expires_in

		if (self.EXPIRES_IN and self.REFRESH_TOKEN) then
			local _timer = function (timer)
				self:RefreshToken ()
			end

			-- smear out refreshing the token to avoid all tokens across entire system being refreshed at the same time
			local delay = self.EXPIRES_IN * math.random (750, 950)
			if (delay > ((2^31) - 1)) then
				delay = (2^31) - 1
				self.metrics:SetCounter ('ShortenedExpiryTime')
			end

			self.Timer.RefreshToken = SetTimer (self.Timer.RefreshToken, delay, _timer)
		end

		print ((self.NAME or 'OAuth') .. ': Access Token received, accessToken:' .. tostring (self.ACCESS_TOKEN ~= nil) .. ', refreshToken:' .. tostring (self.REFRESH_TOKEN ~= nil))

		self:setLink ('')

		self.metrics:SetCounter ('AccessTokenGranted')
		self:notify ('AccessTokenGranted', contextInfo, self.ACCESS_TOKEN, self.REFRESH_TOKEN)

	elseif (responseCode >= 400 and responseCode < 500) then
		self.ACCESS_TOKEN = nil
		self.REFRESH_TOKEN = nil

		local persistStoreKey = C4:Hash ('SHA256', C4:GetDeviceID () .. self.API_CLIENT_ID, SHA_ENC_DEFAULTS)

		PersistDeleteValue (persistStoreKey)

		print ((self.NAME or 'OAuth') .. ': Access Token denied:', data.error, data.error_description, data.error_uri)

		self:setLink ('')


		self.metrics:SetCounter ('AccessTokenDenied')
		if (data.error) then
			self.metrics:SetString ('AccessTokenDeniedReason', data.error)
		end
		if (data.error_description) then
			self.metrics:SetString ('AccessTokenDeniedDescription', data.error_description)
		end
		self:notify ('AccessTokenDenied', contextInfo, data.error, data.error_description, data.error_uri)
	end
end

function oauth:DeleteRefreshToken ()
	local persistStoreKey = C4:Hash ('SHA256', C4:GetDeviceID () .. self.API_CLIENT_ID, SHA_ENC_DEFAULTS)
	PersistDeleteValue (persistStoreKey)
	self.ACCESS_TOKEN = nil
	self.REFRESH_TOKEN = nil

	self.Timer.RefreshToken = CancelTimer (self.Timer.RefreshToken)

	self.metrics:SetCounter ('RefreshTokenDeleted')
end

function oauth:setLink (link, contextInfo)
	if (link ~= '') then
		self.metrics:SetCounter ('LinkCodeReceived')
	end
	self:notify ('LinkCodeReceived', contextInfo, link)

	if (self.LINK_CHANGE_CALLBACK and type (self.LINK_CHANGE_CALLBACK) == 'function') then
		local success, ret = pcall (self.LINK_CHANGE_CALLBACK, link, contextInfo)
		if (success == false) then
			print ((self.NAME or 'OAuth') .. ':LINK_CHANGE_CALLBACK Lua error: ', link, ret)
		end
	end
end

function oauth:notify (handler, ...)
	if (self.notifyHandler [handler] and type (self.notifyHandler [handler]) == 'function') then
		local success, ret = pcall (self.notifyHandler [handler], ...)
		if (success == false) then
			print ((self.NAME or 'OAuth') .. ':' .. handler .. ' Lua error: ', ret, ...)
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

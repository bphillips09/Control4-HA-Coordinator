-- Copyright 2020 Wirepath Home Systems, LLC. All rights reserved.

MAKE_SHORT_LINK_VER = 8

require ('global.url')

function MakeShortLink (link, callback, apiKey)
	local url
	if (IN_PRODUCTION) then
		url = 'https://link.ctrl4.co/new'
	else
		url = 'https://link.control4driversdev.com/new'
	end

	local data = {
		url = link,
	}

	local headers = {
		Authorization = apiKey
	}

	local contextInfo = {
		link = link,
		callback = callback,
	}

	urlPost (url, data, headers, MakeShortLinkResponse, contextInfo)
end

function MakeShortLinkResponse (strError, responseCode, tHeaders, data, context, url)
	if (strError) then
		dbg ('Error with MakeShortLinkResponse:', strError)
		return
	end

	local link = context.link
	local callback = context.callback

	local expiresAt

	if (responseCode == 200) then
		link = data.url
		expiresAt = data.expiresAt
	end

	if (link) then
		if (callback and type (callback) == 'function') then
			pcall (callback, link, expiresAt)
		end
	end
end

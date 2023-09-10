-- Copyright 2023 Snap One, LLC. All rights reserved.

COMMON_MSP_VER = 104

JSON = require ('module.json')

require ('global.lib')
require ('global.handlers')
require ('global.timer')
require ('global.url')

Metrics = require ('module.metrics')

function JSON:assert()
	-- We don't want the JSON library to assert but rather return nil in case of parsing errors
end

do	--Globals
	Navigators = Navigators or {}
	SongQs = SongQs or {}

	QueueMap = QueueMap or {}
	RoomQIDMap = RoomQIDMap or {}

	RoomSettings = RoomSettings or {}

	Navigator = Navigator or {}

	-- NavigatorSerializedArgs = {}

	MAX_SEARCH = 20

	QUEUE_WINDOW_HALF = 100

	MAX_SKIPS = 5
	SKIP_TIMEOUT = ONE_HOUR

	MAX_LIST_SIZE = 1000

	REPEAT_METATABLE = {
		__index = function (self, key)
			local ret = rawget (self, key)
			if (ret) then
				return (ret)
			end

			if (type (key) == 'number') then
				if (self._parent and self._parent.REPEAT) then
					local mod = key % #self
					if (mod == 0) then mod = #self end
					local ret = rawget (self, mod)
					if (ret) then
						return (ret)
					end
				end
			end
		end
	}

	CUSTOM_DASH_ACTIONS = {
		Shuffle = true,
		Repeat = true,
		ThumbsUp = true,
		ThumbsUpCancel = true,
		ThumbsDown = true,
		ThumbsDownCancel = true,
	}

	DEBUG_DATA_RECEIVED = false
	DEBUG_SEND_EVENT = false
end

do -- define proxy / binding IDs
	MSP_PROXY = 5001
end

do	--Setup Metrics
	MetricsMSP = Metrics:new ('dcp_msp', COMMON_MSP_VER)
end

function OnDriverDestroyed ()
	C4:UnregisterSystemEvent (C4SystemEvents.OnPIP, 0)

	UnregisterVariableListener (C4_DIGITAL_AUDIO, DIGITAL_AUDIO_VARS.ROOM_QUEUE_SETTINGS)
	UnregisterVariableListener (C4_DIGITAL_AUDIO, DIGITAL_AUDIO_VARS.ROOM_MAP_INFO)

	C4:SendToProxy (MSP_PROXY, 'MQA_ENABLED_STATE', {ENABLED = false}, 'COMMAND')

	KillAllTimers ()

	if (OnDriverDestroyedTasks and type (OnDriverDestroyedTasks) == 'function') then
		local success, ret = pcall (OnDriverDestroyedTasks)
		if (success) then
			if (ret) then
			end
		else
			dbg ('OnDriverDestroyedTasks: an error occured: ' .. ret)
		end
	end
end

function OnDriverInit ()
	C4:RegisterSystemEvent (C4SystemEvents.OnPIP, 0)
	if (OnDriverInitTasks and type (OnDriverInitTasks) == 'function') then
		local success, ret = pcall (OnDriverInitTasks)
		if (success) then
			if (ret) then
			end
		else
			dbg ('OnDriverInitTasks: an error occured: ' .. ret)
		end
	end
end

function OnDriverLateInit ()
	if (not C4.GetDriverConfigInfo or not (VersionCheck (C4:GetDriverConfigInfo ('minimum_os_version')))) then
		local errtext = {
			'DRIVER DISABLED - ',
			C4:GetDriverConfigInfo ('model'),
			'driver',
			C4:GetDriverConfigInfo ('version'),
			'requires at least C4 OS',
			C4:GetDriverConfigInfo ('minimum_os_version'),
			': current C4 OS is',
			C4:GetVersionInfo ().version,
		}
		errtext = table.concat (errtext, ' ')

		C4:UpdateProperty ('Driver Version', errtext)
		for property, _ in pairs (Properties) do
			C4:SetPropertyAttribs (property, 1)
		end
		C4:SetPropertyAttribs ('Driver Version', 0)
		C4:SendToProxy (MSP_PROXY, 'DISABLE_DRIVER', {}, 'COMMAND')
		return
	end

	OPC.Debug_Mode (Properties ['Debug Mode'])

	KillAllTimers ()
	if (C4.AllowExecute) then C4:AllowExecute (not (IN_PRODUCTION)) end

	C4:urlSetTimeout (10)

	for _, var in ipairs (UserVariables or {}) do
		local default = var.default
		if (default == nil) then
			if (var.varType == 'STRING') then default = ''
			elseif (var.varType == 'BOOL') then default = '0'
			elseif (var.varType == 'NUMBER') then default = 0
			end
		end
		local readOnly = (var.readOnly ~= nil and var.readOnly) or true
		local hidden = (var.hidden ~= nil and var.hidden) or false
		C4:AddVariable (var.name, default, var.varType, readOnly, hidden)
	end

	C4_DIGITAL_AUDIO = next (C4:GetDevicesByC4iName ('control4_digitalaudio.c4i'))
	if (C4_DIGITAL_AUDIO) then
		RegisterVariableListener (C4_DIGITAL_AUDIO, DIGITAL_AUDIO_VARS.ROOM_QUEUE_SETTINGS, OWVC.ParseQueueSettingsInfo)
		RegisterVariableListener (C4_DIGITAL_AUDIO, DIGITAL_AUDIO_VARS.ROOM_MAP_INFO, OWVC.ParseRoomMapInfo)
	end

	RegisterRooms ()

	PersistData = PersistData or {}
	PersistData.AuthSettings = PersistData.AuthSettings or {}

	-- update security on stored password
	if (PersistData.AuthSettings.password) then
		local _update = function ()
			local password = C4:Decrypt ('AES-256-ECB', C4:GetDriverConfigInfo ('model'), nil, PersistData.AuthSettings.password, AES_DEC_DEFAULTS)
			if (password) then
				local enc_password = C4:Encrypt ('AES-256-CBC', C4:GetDriverConfigInfo ('model'), nil, password, AES_ENC_DEFAULTS)
				if (enc_password) then
					PersistData.AuthSettings.password = enc_password
				end
			end
		end

		pcall (_update)
	end

	Search = PersistData.Search or {}
	PersistData.Search = Search

	DEVICE_ID = C4:GetDeviceID ()
	PROXY_ID = C4:GetProxyDevices ()

	SUPPORTS_GAPLESS = VersionCheck ('2.10.0')
	SUPPORTS_CUSTOM_DASH = VersionCheck ('3.0.0')
	SUPPORTS_DEFAULT_AND_ACTIONS = VersionCheck ('3.0.0')
	SUPPORTS_SEEK_ABSOLUTE = VersionCheck ('3.3.1')

	USER_AGENT = 'Control4/' .. C4:GetVersionInfo ().version .. '/' .. C4:GetDriverConfigInfo ('model') .. '/' .. C4:GetDriverConfigInfo ('version')

	HomeTabId = 'Library'
	HomeScreenId = 'LibraryScreen'

	for property, _ in pairs (Properties) do
		OnPropertyChanged (property)
	end

	PersistData.VERSION = PersistData.VERSION or C4:GetDriverConfigInfo ('version')

	if (PersistData.VERSION ~= C4:GetDriverConfigInfo ('version')) then
		SetTimer ('RefreshNavs', math.random (30, 60) * ONE_SECOND)
	end

	if (OnDriverLateInitTasks and type (OnDriverLateInitTasks) == 'function') then
		local success, ret = pcall (OnDriverLateInitTasks)
		if (success) then
			if (ret) then
			end
		else
			dbg ('OnDriverLateInitTasks: an error occured: ' .. ret)
		end
	end
end

function OPC.Debug_Mode (value)
	CancelTimer ('DEBUGPRINT')
	DEBUGPRINT = (value == 'On')

	if (DEBUGPRINT) then
		local _timer = function (timer)
			C4:UpdateProperty ('Debug Mode', 'Off')
			OnPropertyChanged ('Debug Mode')
		end
		SetTimer ('DEBUGPRINT', 36000000, _timer)
	end
end

function OPC.Driver_Version (value)
	local version = C4:GetDriverConfigInfo ('version')
	if (not (IN_PRODUCTION)) then
		version = version .. ' DEV VERSION DO NOT SHIP'
	end
	C4:UpdateProperty ('Driver Version', version)
end

function OPC.Progress_Bar_Updates (value)
	UPDATE_FREQ = string.match (value, '^(%d+)')
	if (UPDATE_FREQ == nil) then
		SendEvent (MSP_PROXY, nil, nil, 'ProgressChanged', {})
	end
end

function OPC.Hide_album_track_images (value)
	HIDE_ALBUM_TRACK_IMAGES = (value == 'On')
end

function OPC.Tag_Explicit_Tracks (value)
	TAG_EXPLICIT_TRACKS = (value == 'On')
end

function OSE.OnPIP (event)
	PersistData.VERSION = C4:GetDriverConfigInfo ('version')
	PersistData.LastRefreshNavTime = os.time ()

	CancelTimer ('RefreshNavs')

	RegisterRooms ()

	if (RefreshNavTasks and type (RefreshNavTasks) == 'function') then
		local success, ret = pcall (RefreshNavTasks)
		if (success) then
			if (ret) then
			end
		else
			dbg ('RefreshNavTasks: an error occured: ' .. ret)
		end
	end
end

function OWVC.ParseRoomIdRoute (idDevice, idVariable, strValue)
	local roomId = tonumber (idDevice)
	RoomIDRoutes [roomId] = {}
	for id in string.gmatch (strValue or '', '<id>(.-)</id>') do
		table.insert (RoomIDRoutes [roomId], tonumber (id))
	end
end

function OWVC.ParseRoomIdSource (idDevice, idVariable, strValue)
	local roomId = tonumber (idDevice)
	local deviceId = tonumber (strValue) or 0
	RoomIDSources [roomId] = deviceId
end

function OWVC.ParseRoomIdPlayingSource (idDevice, idVariable, strValue)
	local roomId = tonumber (idDevice)
	local deviceId = tonumber (strValue) or 0
	RoomIDPlayingSources [roomId] = deviceId

	if (RoomIDSources [roomId] == C4_DIGITAL_AUDIO) then
		RoomIDDigitalMedia [roomId] = deviceId
	else
		RoomIDDigitalMedia [roomId] = 0
	end
end

function OWVC.ParseRoomMapInfo (idDevice, idVariable, strValue)
	local info = strValue or ''
	QueueMap = {}
	RoomQIDMap = {}

	for audioQueueInfo in string.gmatch (info, '<audioQueueInfo>(.-)</audioQueueInfo>') do
		local queue = string.match (audioQueueInfo, '<queue>(.-)</queue>')

		local qId = tonumber (string.match (queue, '<id>(.-)</id>'))

		local source = tonumber (string.match (queue, '<device_id>(.-)</device_id>'))
		local state = string.match (queue, '<state>(.-)</state>')
		local ownerId = tonumber (string.match (queue, '<owner>(.-)</owner>'))

		QueueMap [qId] = {
			source = source,
			state = state,
			ownerId = ownerId,
			qId = qId,
		}

		table.insert (QueueMap [qId], ownerId)

		local rooms = string.match (queue, '<rooms>(.-)</rooms>')

		for roomId in string.gmatch (rooms, '<id>(.-)</id>') do
			roomId = tonumber (roomId)
			if (roomId ~= ownerId) then
				table.insert (QueueMap [qId], roomId)
			end
			RoomQIDMap [roomId] = qId
		end
	end
end

function OWVC.ParseQueueSettingsInfo (idDevice, idVariable, strValue)
	local info = strValue or ''
	RoomSettings = {}

	for room_info in string.gmatch (info, '<room_info>(.-)</room_info>') do
		local roomId = tonumber (string.match (room_info, '<roomid>(.-)</roomid>'))
		local s = string.match (room_info, '<shuffle>(.-)</shuffle>')
		local r = string.match (room_info, '<repeat>(.-)</repeat>')

		RoomSettings [roomId] = {
			SHUFFLE = (s == '1'),
			REPEAT = (r == '1'),
		}
	end
end

RFP [MSP_PROXY] = function (idBinding, strCommand, tParams, args)
	if (strCommand == 'PLAY' or strCommand == 'PAUSE' or strCommand == 'STOP') then
		local roomId = tonumber (tParams.ROOMID) or tonumber (tParams.ROOM_ID)
		local qId = GetQueueIDByRoomID (roomId)
		local thisQ = SongQs [qId]
		if (thisQ) then
			LogPlayEvent ('user', qId, strCommand)
		end
		SetNextTrackURL ('', roomId)
	end

	local navId = tParams.NAVID
	local nav = Navigators [navId]

	if (strCommand == 'DESTROY_NAVIGATOR' or strCommand == 'DESTROY_NAV') then
		if (nav) then
			nav.DestroyNavTimer = SetTimer (nav.DestroyNavTimer, 5 * ONE_SECOND, function (timer) Navigators [navId] = nil end)
		end
		return

	elseif (strCommand == 'INTERNET_RADIO_SELECTED' or strCommand == 'AUDIO_URL_SELECTED') then
		OnInternetRadioSelected (idBinding, tParams)

	elseif (strCommand == 'SELECT_INTERNET_RADIO_ERROR' or strCommand == 'SELECT_AUDIO_URL_ERROR') then
		OnInternetRadioSelectedError (idBinding, tParams)

	elseif (strCommand == 'QUEUE_DELETED') then
		OnQueueDeleted (idBinding, tParams)

	elseif (strCommand == 'QUEUE_INFO_CHANGED') then
		OnQueueInfoChanged (idBinding, tParams)

	elseif (strCommand == 'QUEUE_MEDIA_INFO_UPDATED') then
		OnQueueMediaInfoUpdated (idBinding, tParams)

	elseif (strCommand == 'QUEUE_NEED_NEXT') then
		OnQueueNeedNext (idBinding, tParams)

	elseif (strCommand == 'QUEUE_STATE_CHANGED') then
		OnQueueStateChanged (idBinding, tParams)

	elseif (strCommand == 'QUEUE_STREAM_STATUS_CHANGED') then
		OnQueueStreamStatusChanged (idBinding, tParams)

	elseif (strCommand == 'DEVICE_SELECTED') then
		local itemId = tParams.location
		local roomId = tonumber (tParams.idRoom)

		if (itemId == '') then itemId = nil end

		if (CheckRoomHasDigitalAudio (roomId) == false) then
			dbg ('Tried to select digital audio in room with no Digital Audio:', roomId)
			return
		end

		if (itemId) then
			if (SelectMediaDBItemInRoom and type (SelectMediaDBItemInRoom) == 'function') then
				local success, ret = pcall (SelectMediaDBItemInRoom, itemId, roomId)
				if (success) then
					if (ret) then
					end
				else
					dbg ('SelectMediaDBItemInRoom: an error occured: ' .. ret)
				end
			end

		else
			local qId = GetQueueIDByRoomID (roomId)
			if (qId == 0) then
				local session = 0
				for qId, _ in pairs (SongQs or {}) do
					if (qId > session) then
						session = qId
					end
				end

				if (session and session > 0) then
					JoinRoomToSession (roomId, session)

				else
					if (SelectDefaultItemInRoom and type (SelectDefaultItemInRoom) == 'function') then
						local success, ret = pcall (SelectDefaultItemInRoom, roomId)
						if (success) then
							if (ret) then
							end
						else
							dbg ('SelectDefaultItemInRoom: an error occured: ' .. ret)
						end
					end
				end
			end
		end

	elseif (strCommand == 'PLAY') then
		if (navId and tParams.SEQ) then
			DataReceived (idBinding, navId, tParams.SEQ, '')
		end

		local roomId = tonumber (tParams.ROOMID) or tonumber (tParams.ROOM_ID)
		return (Play (roomId))

	elseif (nav == nil and strCommand == 'SKIP_FWD') then
		local roomId = tonumber (tParams.ROOMID) or tonumber (tParams.ROOM_ID)
		return (SkipFwd (roomId))

	elseif (nav == nil and strCommand == 'SKIP_REV') then
		local roomId = tonumber (tParams.ROOMID) or tonumber (tParams.ROOM_ID)
		return (SkipRev (roomId))

	elseif (strCommand == 'SEEK') then
		local roomId = tonumber (tParams.ROOMID) or tonumber (tParams.ROOM_ID)
		local pos = tonumber (tParams.POSITION)
		local seekType = tParams.TYPE
		return (Seek (roomId, pos, seekType))

	elseif (strCommand == 'SCAN_FWD') then
		local roomId = tonumber (tParams.ROOMID) or tonumber (tParams.ROOM_ID)
		local pos = 15
		local seekType = 'relative'
		return (Seek (roomId, pos, seekType))

	elseif (strCommand == 'SCAN_REV') then
		local roomId = tonumber (tParams.ROOMID) or tonumber (tParams.ROOM_ID)
		local pos = -15
		local seekType = 'relative'
		return (Seek (roomId, pos, seekType))

	elseif (string.find (strCommand, '^NUMBER_')) then
		-- TODO
		return '<ret><handled>true</handled></ret>'

	elseif (strCommand == 'REPEAT_ON') then
		local roomId = tonumber (tParams.ROOM_ID)
		local qId = GetQueueIDByRoomID (roomId)
		QueueSetRepeat (qId)

	elseif (strCommand == 'REPEAT_OFF') then
		local roomId = tonumber (tParams.ROOM_ID)
		local qId = GetQueueIDByRoomID (roomId)
		QueueClearRepeat (qId)

	elseif (strCommand == 'SHUFFLE_ON') then
		local roomId = tonumber (tParams.ROOM_ID)
		local qId = GetQueueIDByRoomID (roomId)
		QueueSetShuffle (qId)

	elseif (strCommand == 'SHUFFLE_OFF') then
		local roomId = tonumber (tParams.ROOM_ID)
		local qId = GetQueueIDByRoomID (roomId)
		QueueClearShuffle (qId)

	elseif (strCommand == 'GET_CONTAINER_INFO') then
		local keyToUpdate = tParams.keyToUpdate
		local containerId = tParams.containerId
		local containerType = tParams.containerType
		local rooms = tParams.rooms
		GetContainerInfo (containerId, containerType, keyToUpdate, rooms)

	elseif (not (navId) and RFP) then
		strCommand = string.gsub (strCommand, '%s+', '_')
		if (RFP [strCommand]) then
			return RFP [strCommand] (tParams, args, idBinding)
		end

	elseif (nav == nil and navId) then
		nav = Navigator:new (navId)
		Navigators [navId] = nav
	end

	if (nav) then
		nav.DestroyNavTimer = SetTimer (nav.DestroyNavTimer, 3 * ONE_HOUR, function (timer) Navigators [navId] = nil end)

		local cmd = nav [strCommand]

		if (cmd == nil) then
			dbg ('ReceivedFromProxy: Unhandled nav command = ' .. strCommand)
			return
		end

		nav.roomId = tonumber (tParams.ROOMID)
		local seq = tParams.SEQ

		if (NavigatorSerializedArgs) then
			for arg, serialized in pairs (NavigatorSerializedArgs) do
				if (args [arg] and serialized) then
					args [arg] = Deserialize (args [arg])
				end
			end
		end

		local success, ret = pcall (cmd, nav, idBinding, seq, args)

		if (success) then
			if (ret) then
				DataReceived (idBinding, navId, seq, ret)
			end
		else
			dbg ('Called nav command ' .. strCommand .. '.	An error occured: ' .. ret)
			DataReceivedError (idBinding, navId, seq, ret)
		end
	end
end

--Common MSP functions
function DataReceivedError (idBinding, navId, seq, msg)
	local tParams = {
		NAVID = navId,
		SEQ = seq,
		DATA = '',
		ERROR = msg,
	}
	C4:SendToProxy (idBinding, 'DATA_RECEIVED', tParams)
end

function DataReceived (idBinding, navId, seq, args)
	local data = ''

	if (type (args) == 'string') then
		data = args
	elseif (type (args) == 'boolean' or type (args) == 'number') then
		data = tostring (args)
	elseif (type (args) == 'table') then
		data = XMLTag (nil, args, false, false)
	end

	local tParams = {
		NAVID = navId,
		SEQ = seq,
		DATA = data,
	}

	if (DEBUG_DATA_RECEIVED) then
		print ('DATA_RECEIVED')
		Print (tParams)
	end

	C4:SendToProxy (idBinding, 'DATA_RECEIVED', tParams)
end

function SendEvent (idBinding, navId, roomId, name, args)
	local data = ''

	if (type (args) == 'string') then
		data = args
	elseif (type (args) == 'boolean' or type (args) == 'number') then
		data = tostring (args)
	elseif (type (args) == 'table') then
		data = XMLTag (nil, args, false, false)
	end

	if (type (roomId) == 'table') then
		roomId = table.concat (roomId, ',')
	end

	local tParams = {
		NAVID = navId,
		ROOMS = roomId,
		NAME = name,
		EVTARGS = data,
	}

	if (DEBUG_SEND_EVENT) then
		print ('SEND_EVENT')
		Print (tParams)
	end

	C4:SendToProxy (idBinding, 'SEND_EVENT', tParams, 'COMMAND')
end

function NetworkError (strError)
	dbg ('Network error: ' .. (strError or ''))
	local params = {
		Id = 'ErrorHandler',
		Title = '',
		Message = 'No response to this request.  Please try again.',
	}
	SendEvent (MSP_PROXY, nil, nil, 'DriverNotification', params)
end

-- Queue functions
function AddTracksToQueue (trackList, roomId, playOption, radioInfo, radioSkips, containerInfo)
	if (CheckRoomHasDigitalAudio (roomId) == false) then
		dbg ('Tried to create digital audio queue in room with no Digital Audio:', roomId)
		--return
	end

	local qId = GetQueueIDByRoomID (roomId)
	local thisQ = SongQs [qId] or SongQs [roomId]

	local idInQ = (thisQ and thisQ.idInQ) or 1

	for _, item in ipairs (trackList or {}) do
		item.image_list = MakeImageList (item)
		item.idInQ = idInQ
		idInQ = idInQ + 1
	end

	local playNow = false

	if (thisQ) then
		local pos, clearQ, logStop
		QueueClearShuffle (qId)

		if (thisQ.STREAM or (thisQ.RADIO and playOption ~= 'RADIO_NEXT')) then
			clearQ = true
		end

		thisQ.idInQ = idInQ
		pos = #thisQ.Q + 1

		if (playOption == 'NOW') then
			playNow = true

		elseif (playOption == 'NEXT') then
			pos = thisQ.CurrentTrack + 1

		elseif (playOption == 'ADD') then

		elseif (playOption == 'REPLACE') then
			clearQ = true

		elseif (playOption == 'SHUFFLE') then
			clearQ = true

		elseif (playOption == 'STREAM') then
			clearQ = true

		elseif (playOption == 'RADIO') then
			clearQ = true
			thisQ.SKIPS = radioSkips or 0

		elseif (playOption == 'RADIO_NEXT') then
			playNow = true
		end

		local nextTrackIndex = (playOption == 'SHUFFLE' and math.random (#trackList)) or 1

		if (playNow or clearQ) then
			LogPlayEvent ('user', qId, 'NEW_TRACKS_ADDED', trackList [nextTrackIndex])
		end

		if (clearQ) then
			thisQ.Q = {}
			thisQ.Q._parent = thisQ
			setmetatable (thisQ.Q, REPEAT_METATABLE)
			pos = 1
			playNow = true
		end

		if (playOption == 'RADIO') then
			thisQ.RADIO = radioInfo
			thisQ.STREAM = nil

		elseif (playOption == 'STREAM') then
			thisQ.STREAM = radioInfo
			thisQ.RADIO = nil

		elseif (playOption == 'RADIO_NEXT') then

		else
			thisQ.RADIO = nil
			thisQ.STREAM = nil
		end

		for _, item in ipairs (trackList) do
			table.insert (thisQ.Q, pos, item)
			pos = pos + 1
		end

		if (playOption == 'SHUFFLE') then
			thisQ.CurrentTrack = nextTrackIndex
			QueueSetShuffle (qId)
			trackList = thisQ.Q
		end

		thisQ.nowPlayingTags.can_shuffle = (thisQ.RADIO == nil) and (thisQ.STREAM == nil)
		thisQ.nowPlayingTags.can_repeat = (thisQ.RADIO == nil) and (thisQ.STREAM == nil)

		UpdateQueue (qId)
		UpdateDashboard (qId)

	else
		playNow = true
		qId = roomId

		local isRadio = (playOption == 'RADIO' and radioInfo) or nil
		local isStream = (playOption == 'STREAM' and radioInfo) or nil

		SongQs [roomId] = {
			Q = trackList,
			RADIO = isRadio,
			STREAM = isStream,
			SKIPS = radioSkips or 0,
			REPEAT = (not (isRadio or isStream)) and RoomSettings [roomId] and RoomSettings [roomId].REPEAT,
			CurrentTrack = 1,
			CurrentTrackElapsed = 0,
			idInQ = idInQ,
			nowPlayingTags = {
				can_shuffle = (not (isRadio or isStream)),
				can_repeat = (not (isRadio or isStream)),
			},
		}

		if (playOption == 'SHUFFLE') then
			SongQs [roomId].CurrentTrack = math.random (#trackList)
			QueueSetShuffle (roomId)
			trackList = SongQs [roomId].Q
		end

		MetricsMSP:SetCounter ('NewQueueAttempt')
		MetricsMSP:SetGauge ('QueueCount', GetTableSize (SongQs))
	end

	if (containerInfo) then
		local thisQ = SongQs [qId]
		if (thisQ) then
			if (RECENTLY_PLAYED_AGENT) then
				local key
				if (thisQ.RecentlyPlayedKey) then
					key = thisQ.RecentlyPlayedKey
				end
				local rooms = GetRoomMapByQueueID (qId)
				if (#rooms == 0) then
					rooms = roomId
				else
					rooms = table.concat (rooms, ',')
				end
				local itemInfo = {
					keyToUpdate = nil,
					driverId = PROXY_ID,
					info = {
						container = {
							id = containerInfo.id,
							itemType = containerInfo.itemType,
							title = containerInfo.title,
							subtitle = containerInfo.subtitle,
							image = containerInfo.image,
						},
						driverId = PROXY_ID,
					},
					rooms = rooms,
				}
				key = C4:SendToDevice (RECENTLY_PLAYED_AGENT, 'SetHistoryItem', {itemInfo = Serialize (itemInfo)})
				if (key) then
					thisQ.RecentlyPlayedKey = key
				end
			end
		end
	end

	if (playNow) then
		local _, nextTrack = next (trackList or {})

		if (nextTrack and roomId) then
			GetTrackURLAndPlay (nextTrack, roomId)
		end
	end

	return qId, playNow
end

function PlayTrackURL (url, roomId, idInQ, flags, nextURL, position, hardPause)
	if (CheckRoomHasDigitalAudio (roomId) == false) then
		dbg ('Tried to start digital audio in room with no Digital Audio:', roomId)
		--return
	end

	local qId = GetQueueIDByRoomID (roomId)
	local thisQ = SongQs [qId] or SongQs [roomId]

	if (not url or url == '') then
		return
	end

	if (thisQ) then
		thisQ.trackStartEvented = false
		thisQ.trackStopEvented = false
		thisQ.trackStarted = os.time ()
		thisQ.nextUrlSent = (not (nextURL == nil or nextURL == ''))
		thisQ.nextUrlRequested = false
		thisQ.nextProgrammedTrackRequested = false
		thisQ.CurrentTrackElapsed = (position and math.floor (position / ONE_SECOND)) or 0
		thisQ.ProgressTimer = CancelTimer (thisQ.ProgressTimer)

		if (idInQ ~= nil) then
			for i, track in ipairs (thisQ.Q) do
				if (idInQ == track.idInQ) then
					thisQ.CurrentTrack = i
				end
			end
		end
	end

	if (type (flags) ~= 'table') then
		flags = {}
	end
	flags.driver = C4:GetDriverConfigInfo ('model')

	local f = {}
	for k, v in pairs (flags) do
		local thisFlag = tostring (k) .. '=' .. tostring (v)
		table.insert (f, thisFlag)
	end
	flags = table.concat (f, ',')

	MetricsMSP:SetCounter ('TrackPlayAttempt')

	if (idInQ == nil) then
		idInQ = tostring (os.time ())
	end

	local params = {
		ROOM_ID = roomId,
		STATION_URL = url,
		QUEUE_INFO = idInQ,
		FLAGS = flags,
		NEXT_URL = nextURL,
		POSITION = position,
		HARD_PAUSE = hardPause,
	}

	local command = 'SELECT_AUDIO_URL'
	if (not (VersionCheck ('2.10.0'))) then
		command = 'SELECT_INTERNET_RADIO'
		params.REPORT_ERRORS = true
	end
	C4:SendToProxy (MSP_PROXY, command, params, 'COMMAND')
end

function SetNextTrackURL (nextURL, roomId, idInQ, flags)
	local qId = GetQueueIDByRoomID (roomId)
	local thisQ = SongQs [qId]

	if (not nextURL or nextURL == '') then
		return
	end

	if (thisQ) then
		thisQ.nextUrlSent = (not (nextURL == nil or nextURL == ''))
		thisQ.nextUrlRequested = false
	end

	if (type (flags) ~= 'table') then
		flags = {}
	end
	flags.driver = C4:GetDriverConfigInfo ('model')

	local f = {}
	for k, v in pairs (flags) do
		local thisFlag = tostring (k) .. '=' .. tostring (v)
		table.insert (f, thisFlag)
	end
	flags = table.concat (f, ',')

	MetricsMSP:SetCounter ('NextTrackPlayAttempt')

	local params = {
		REPORT_ERRORS = true,
		ROOM_ID = roomId,
		QUEUE_INFO = idInQ,
		FLAGS = flags,
		NEXT_URL = nextURL,
	}

	C4:SendToProxy (MSP_PROXY, 'SET_NEXT_AUDIO_URL', params, 'COMMAND')
end

function QueueSetRepeat (qId)
	local thisQ = SongQs [qId]
	if (thisQ) then
		if (not (thisQ.REPEAT or thisQ.STREAM or thisQ.RADIO)) then
			thisQ.REPEAT = true
			thisQ.Q._repeat = true

			local roomId = GetRoomMapByQueueID (qId) [1]
			if (roomId) then
				SetNextTrackURL ('', roomId)
				C4:SendToDevice (C4_DIGITAL_AUDIO, 'REPEAT', {ROOM_ID = roomId, REPEAT = ((thisQ.REPEAT and 1) or 0)})
			end
		end
		UpdateQueue (qId, {suppressList = true})
		UpdateDashboard (qId)
	end
end

function QueueClearRepeat (qId)
	local thisQ = SongQs [qId]
	if (thisQ) then
		if (not (not (thisQ.REPEAT) or thisQ.STREAM or thisQ.RADIO)) then
			thisQ.REPEAT = false
			thisQ.Q._repeat = false

			local roomId = GetRoomMapByQueueID (qId) [1]
			if (roomId) then
				SetNextTrackURL ('', roomId)
				C4:SendToDevice (C4_DIGITAL_AUDIO, 'REPEAT', {ROOM_ID = roomId, REPEAT = ((thisQ.REPEAT and 1) or 0)})
			end
		end
		UpdateQueue (qId, {suppressList = true})
		UpdateDashboard (qId)
	end
end

function QueueSetShuffle (qId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		if (not (thisQ.SHUFFLE or thisQ.STREAM or thisQ.RADIO)) then
			local roomId = GetRoomMapByQueueID (qId) [1]
			local newQ = {}
			local order = {}

			local inList = {}
			for i = 1, #thisQ.Q do inList [i] = i end

			if (thisQ.CurrentTrack and thisQ.Q [thisQ.CurrentTrack]) then
				local item = thisQ.Q [thisQ.CurrentTrack]
				table.insert (newQ, item)
				table.insert (order, thisQ.CurrentTrack)
				table.remove (inList, thisQ.CurrentTrack)
				thisQ.CurrentTrack = 1
			end
			if (#inList > 0) then
				repeat
					local r = math.random (1, #inList)
					local pos = inList [r]
					local item = thisQ.Q [pos]
					table.insert (newQ, item)
					table.insert (order, pos)
					table.remove (inList, r)
				until (#inList == 0)
			end

			thisQ.Q = newQ
			thisQ.SHUFFLE = order
			thisQ.Q._parent = thisQ
			setmetatable (thisQ.Q, REPEAT_METATABLE)

			local roomId = GetRoomMapByQueueID (qId) [1]
			if (roomId) then
				SetNextTrackURL ('', roomId)
				C4:SendToDevice (C4_DIGITAL_AUDIO, 'SHUFFLE', {ROOM_ID = roomId, SHUFFLE = ((thisQ.SHUFFLE and 1) or 0)})
			end
		end
		UpdateQueue (qId)
		UpdateDashboard (qId)
	end
end

function QueueClearShuffle (qId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		if (not (not (thisQ.SHUFFLE) or thisQ.STREAM or thisQ.RADIO)) then

			thisQ.CurrentTrack = thisQ.SHUFFLE [thisQ.CurrentTrack]

			local newQ = {}

			for index, pos in pairs (thisQ.SHUFFLE) do
				newQ [pos] = thisQ.Q [index]
			end
			for i = #thisQ.SHUFFLE + 1, #thisQ.Q do
				newQ [i] = thisQ.Q [i]
			end

			thisQ.Q = newQ
			thisQ.SHUFFLE = nil
			thisQ.Q._parent = thisQ
			setmetatable (thisQ.Q, REPEAT_METATABLE)

			local roomId = GetRoomMapByQueueID (qId) [1]
			if (roomId) then
				SetNextTrackURL ('', roomId)
				C4:SendToDevice (C4_DIGITAL_AUDIO, 'SHUFFLE', {ROOM_ID = roomId, SHUFFLE = ((thisQ.SHUFFLE and 1) or 0)})
			end
		end
		UpdateQueue (qId)
		UpdateDashboard (qId)
	end
end

function Play (roomId)
	local qId = GetQueueIDByRoomID (roomId)
	local thisQ = SongQs [qId]

	if (thisQ and (thisQ.CurrentState == 'STOP' or thisQ.CurrentState == 'END')) then
		if (thisQ.RADIO) then
			GetNextProgrammedTrack (thisQ.RADIO, roomId)
		else
			local nextTrack = thisQ.Q [thisQ.CurrentTrack]
			if (nextTrack and roomId) then
				GetTrackURLAndPlay (nextTrack, roomId)
			end
		end
		return '<ret><handled>true</handled></ret>'
	end
end

function SkipFwd (roomId)
	local qId = GetQueueIDByRoomID (roomId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		if (thisQ.RADIO) then
			if (thisQ.nextProgrammedTrackRequested) then return end
			if (thisQ.SKIPS >= MAX_SKIPS) then return end

			GetNextProgrammedTrack (thisQ.RADIO, roomId, 'SKIP')

			if (MAX_SKIPS ~= math.huge and type (SKIP_TIMEOUT) == 'number') then
				QueueRadioSkipManager (qId)
			end

			UpdateDashboard (qId)

		elseif (thisQ.STREAM) then

		else
			Skip (roomId, 1)
		end
	end
end

function SkipRev (roomId)
	local qId = GetQueueIDByRoomID (roomId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		if (thisQ.STREAM) then return end
		if (thisQ.RADIO) then return end

		if (thisQ.CurrentTrackElapsed > 15 and thisQ.SKIP_INCREMENT == nil) then
			Skip (roomId, 0)
		else
			Skip (roomId, -1)
		end
	end
end

function Skip (roomId, increment)
	local qId = GetQueueIDByRoomID (roomId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		thisQ.SKIP_INCREMENT = thisQ.SKIP_INCREMENT or 0
		thisQ.SKIP_INCREMENT = thisQ.SKIP_INCREMENT + increment

		if (not (thisQ.REPEAT)) then
			local newPos = thisQ.CurrentTrack + thisQ.SKIP_INCREMENT
			if (newPos > #thisQ.Q or newPos < 1) then
				thisQ.SKIP_INCREMENT = thisQ.SKIP_INCREMENT - increment	-- stop from skipping past end or beginning of queue if not on repeat
				return
			end
		end

		local _timer = function (timer)
			thisQ.SKIP_INCREMENT = thisQ.SKIP_INCREMENT or 0

			local nextTrack = thisQ.Q [thisQ.CurrentTrack + thisQ.SKIP_INCREMENT]

			local strCommand = (thisQ.SKIP_INCREMENT > 0 and 'SKIP_FWD') or (thisQ.SKIP_INCREMENT < 0 and 'SKIP_REV') or 'REPLAY'

			thisQ.SKIP_INCREMENT = nil
			thisQ.SKIP_INCREMENT_TIMER = CancelTimer (thisQ.SKIP_INCREMENT_TIMER)

			LogPlayEvent ('user', qId, strCommand, nextTrack)

			if (nextTrack and roomId) then
				GetTrackURLAndPlay (nextTrack, roomId)
			end
		end

		thisQ.SKIP_INCREMENT_TIMER = SetTimer (thisQ.SKIP_INCREMENT_TIMER, 500, _timer)
		UpdateQueue (qId, {suppressList = true})
	end
end

function Seek (roomId, pos, seekType)
	if (not (roomId and pos and seekType)) then
		return
	end

	local qId = GetQueueIDByRoomID (roomId)

	local thisQ = SongQs [qId]

	if (not thisQ) then
		print ('Cannot seek, no queue')
		return
	end

	local elapsed = thisQ.CurrentTrackElapsed
	local duration = thisQ.CurrentTrackDuration

	if (not (elapsed and duration)) then
		return
	end

	if (not (SUPPORTS_SEEK_ABSOLUTE)) then
		if (seekType == 'absolute') then
			pos = pos - elapsed
			seekType = 'relative'
		elseif (seekType == 'percent') then
			local target = math.floor (duration * (pos / 100))
			pos = target - elapsed
			seekType = 'relative'
		end
	end

	local target
	if (seekType == 'absolute') then
		target = pos
	elseif (seekType == 'relative') then
		target = elapsed + pos
	elseif (seekType == 'percent') then
		target = math.floor (duration * (pos / 100))
	end

	if (not target) then
		print ('Cannot seek, could not calculate target position')
		return
	end

	if (target < 0) then
		print ('Cannot seek, target is before start of track')
		return
	end

	if (target > duration) then
		print ('Cannot seek, target is after end of track')
		return
	end

	if (roomId and pos and seekType) then
		local _args = {
			ROOM_ID = roomId,
			POSITION = pos * 1000, -- convert seconds to ms
			TYPE = seekType,
		}

		C4:SendToDevice (C4_DIGITAL_AUDIO, 'SEEK', _args)

		if (seekType == 'absolute') then
			thisQ.CurrentTrackElapsed = pos
		elseif (seekType == 'relative') then
			thisQ.CurrentTrackElapsed = thisQ.CurrentTrackElapsed + pos
		elseif (seekType == 'percent') then
			thisQ.CurrentTrackElapsed = math.floor (thisQ.CurrentTrackDuration * (pos / 100))
		end

		UpdateProgress (qId)

		return '<ret><handled>true</handled></ret>'
	end
end

function RegisterRooms ()
	RECENTLY_PLAYED_AGENT = next (C4:GetDevicesByC4iName ('recentlyplayed-agent.c4z'))

	RoomIDs = C4:GetDevicesByC4iName ('roomdevice.c4i')
	RoomIDSources = {}
	RoomIDPlayingSources = {}
	RoomIDDigitalMedia = {}
	RoomIDRoutes = {}
	for roomId, _ in pairs (RoomIDs) do
		RegisterVariableListener (roomId, ROOM_VARS.CURRENT_SELECTED_DEVICE, OWVC.ParseRoomIdSource)
		RegisterVariableListener (roomId, ROOM_VARS.CURRENT_AUDIO_PATH, OWVC.ParseRoomIdRoute)
		RegisterVariableListener (roomId, ROOM_VARS.PLAYING_AUDIO_DEVICE, OWVC.ParseRoomIdPlayingSource)
	end
end

function GetQueueIDByRoomID (roomId)
	roomId = tonumber (roomId)
	local qId = RoomQIDMap [roomId] or 0
	local queue = QueueMap [qId] or {}
	return qId, queue
end

function GetRoomMapByQueueID (qId)
	qId = tonumber (qId)
	local queue = QueueMap [qId] or {}
	return (queue)
end

function GetDashboardByQueue (qId)
	qId = tonumber (qId)
	local thisQ = SongQs [qId]
	if (thisQ) then
		local dashboard = {}
		if (SUPPORTS_CUSTOM_DASH) then
			if (not (thisQ.RADIO or thisQ.STREAM)) then
				if (thisQ.SHUFFLE ~= nil) then
					table.insert (dashboard, 'ShuffleOff')
				else
					table.insert (dashboard, 'ShuffleOn')
				end
			end
			if (thisQ.nowPlayingTags.can_thumbs_down) then
				table.insert (dashboard, 'ThumbsDown')
			elseif (thisQ.nowPlayingTags.can_thumbs_down_cancel) then
				table.insert (dashboard, 'ThumbsDownCancel')
			end
		end

		if (#thisQ.Q > 0 and not (thisQ.RADIO or thisQ.STREAM)) then
			table.insert (dashboard, 'SkipRev')
		end

		if (thisQ.CurrentState == 'PLAY') then
			if (thisQ.STREAM) then
				table.insert (dashboard, 'Stop')
			else
				table.insert (dashboard, 'Pause')
			end

		elseif (thisQ.CurrentState == 'PAUSE') then
			table.insert (dashboard, 'Play')

		elseif ((thisQ.CurrentState == 'STOP' or thisQ.CurrentState == 'END') and (#thisQ.Q > 0 or thisQ.STREAM)) then
			table.insert (dashboard, 'Play')
		end

		if (((thisQ.RADIO and thisQ.SKIPS < MAX_SKIPS) or (thisQ.CurrentTrack and (thisQ.REPEAT or thisQ.CurrentTrack < #thisQ.Q))) and not thisQ.STREAM) then
			table.insert (dashboard, 'SkipFwd')
		end

		if (SUPPORTS_CUSTOM_DASH) then
			if (not (thisQ.RADIO or thisQ.STREAM)) then
				if (thisQ.REPEAT == true) then
					table.insert (dashboard, 'RepeatOff')
				else
					table.insert (dashboard, 'RepeatOn')
				end
			end
			if (thisQ.nowPlayingTags.can_thumbs_up) then
				table.insert (dashboard, 'ThumbsUp')
			elseif (thisQ.nowPlayingTags.can_thumbs_up_cancel) then
				table.insert (dashboard, 'ThumbsUpCancel')
			end
		end

		dashboard = table.concat (dashboard, ' ')

		thisQ.dashboard = dashboard
		return dashboard
	end
end

function GetNowPlayingTagsByQueue (qId)
	qId = tonumber (qId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		local nowPlayingTags = CopyTable (thisQ.nowPlayingTags or {})

		nowPlayingTags.shuffle_on = tostring (thisQ.SHUFFLE ~= nil)
		nowPlayingTags.repeat_on = tostring (thisQ.REPEAT == true)

		nowPlayingTags.actions_list = nowPlayingTags.actions_list or DEFAULT_QUEUE_ACTIONS_LIST

		if (SUPPORTS_CUSTOM_DASH) then
			nowPlayingTags.can_shuffle = 'false'
			nowPlayingTags.can_repeat = 'false'
			nowPlayingTags.shuffle_on = 'false'
			nowPlayingTags.repeat_on = 'false'

			nowPlayingTags.can_thumbs_up = 'false'
			nowPlayingTags.can_thumbs_up_cancel = 'false'
			nowPlayingTags.can_thumbs_down = 'false'
			nowPlayingTags.can_thumbs_down_cancel = 'false'

			if (nowPlayingTags.actions_list) then
				for i = #nowPlayingTags.actions_list, 1, -1 do
					local action = nowPlayingTags.actions_list [i]
					if (CUSTOM_DASH_ACTIONS [action]) then
						table.remove (nowPlayingTags.actions_list, i)
					end
				end
			end
		end

		if (nowPlayingTags.actions_list) then
			nowPlayingTags.actions_list = table.concat (nowPlayingTags.actions_list, ' ')
		end

		return (XMLTag (nowPlayingTags))
	end
end

-- Force single queue
function GetMasterRoom (deviceId)
	if (deviceId == nil) then
		deviceId = PROXY_ID
	end
	for qId, qInfo in pairs (QueueMap) do
		if (qInfo.source == deviceId) then
			return qInfo.ownerId, qInfo
		end
	end
	return nil, {}
end

function JoinRoomToSession (roomId, qId)
	if (CheckRoomHasDigitalAudio (roomId) == false) then
		dbg ('Tried to join digital audio session with room with no Digital Audio:', roomId)
		--return
	end

	if (qId == nil) then
		local masterRoom, masterQueueInfo = GetMasterRoom ()
		if (masterQueueInfo.qId) then
			qId = masterQueueInfo.qId
		else
			return
		end
	end

	local sessionQueue = GetRoomMapByQueueID (qId)
	local _, roomQueue = GetQueueIDByRoomID (roomId)

	if (sessionQueue.ownerId) then
		if (sessionQueue~= roomQueue) then
			local args = {
				ROOM_ID = sessionQueue.ownerId,
				ROOM_ID_LIST = roomId,
			}
			C4:SendToDevice (C4_DIGITAL_AUDIO, 'ADD_ROOMS_TO_SESSION', args)
		end
		return true
	end
end

function CheckRoomHasDigitalAudio (roomId)
	roomId = tonumber (roomId)
	if (roomId == nil) then
		return false
	end
	C4_DIGITAL_AUDIO = next (C4:GetDevicesByC4iName ('control4_digitalaudio.c4i'))
	local hasC4DA = false
	if (C4_DIGITAL_AUDIO) then
		local listenSources = C4:SendToDevice (roomId, 'GET_LISTEN_DEVICES', {})
		hasC4DA = (string.find (listenSources, tostring (C4_DIGITAL_AUDIO)) ~= nil)
	end

	if (hasC4DA == false) then
		MetricsMSP:SetCounter ('Error_NoDigitalAudio')
	end

	return (hasC4DA)
end

-- Update Navigator
function MakeList (response, collection, options)
	if (not options) then
		options = {}
	end
	if (collection) then
		collection.image_list = MakeImageList (collection)
		if (SUPPORTS_DEFAULT_AND_ACTIONS and options.makeDefaultAction) then
			if (collection.actions_list and not (collection.default_action)) then
				local firstAction = string.match (collection.actions_list, '(%w+)')
				if (firstAction) then
					collection.default_action = firstAction
				end
			end
		end
		collection = XMLTag (collection)
	end

	local list = {}
	for _, item in ipairs (response) do
		if (options.suppressItemImages) then
			item.image_list = nil
		else
			item.image_list = MakeImageList (item)
		end
		if (options and options.defaults) then
			for k, v in pairs (options.defaults) do
				if (item [k] == nil) then
					item [k] = v
				end
			end
		end
		if (SUPPORTS_DEFAULT_AND_ACTIONS and options.makeDefaultAction) then
			if (item.actions_list and not (item.default_action)) then
				local firstAction = string.match (item.actions_list, '(%w+)')
				if (firstAction) then
					item.default_action = firstAction
				end
			end
		end

		if (NavigatorSerializedArgs) then
			for arg, serialized in pairs (NavigatorSerializedArgs) do
				if (item [arg] and serialized) then
					item [arg] = Serialize (item [arg])
				end
			end
		end

		table.insert (list, XMLTag ('item', item))
	end

	list = table.concat (list)

	if (response.totalCount) then
		if (MAX_LIST_SIZE and response.totalCount > MAX_LIST_SIZE) then
			response.totalCount = MAX_LIST_SIZE
		end
		return ({Collection = collection, ['List length="' .. response.totalCount .. '"'] = list})
	else
		return ({Collection = collection, List = list})
	end
end

function UpdateMediaInfo (qId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		local thisTrack = thisQ.Q [thisQ.CurrentTrack] or {}

		local args = {
			TITLE = thisTrack.title,
			ALBUM = thisTrack.album,
			ARTIST = thisTrack.artist,
			GENRE = thisTrack.genre,
			IMAGEURL = thisTrack.image,
			QUEUEID = qId,
			}
		C4:SendToProxy (MSP_PROXY, 'UPDATE_MEDIA_INFO', args, 'COMMAND', true)

		--[[
		if (thisQ.RecentlyPlayedKey and RECENTLY_PLAYED_AGENT) then
			local rooms = GetRoomMapByQueueID (qId)
			rooms = table.concat (rooms, ',')

			local itemInfo = {
				keyToUpdate = thisQ.RecentlyPlayedKey,
				driverId = PROXY_ID,
				info = {
					track = {
						id = thisTrack.id,
						title = thisTrack.title,
						subtitle = thisTrack.artist,
						image = thisTrack.image,
					},
					driverId = PROXY_ID,
				},
				rooms = rooms,
			}

			C4:SendToDevice (RECENTLY_PLAYED_AGENT, 'SetHistoryItem', {itemInfo = Serialize (itemInfo)})
		end
		--]]
	end
end

function UpdateQueue (qId, options)
	if (type (options) ~= 'table') then
		options = {}
	end

	local thisQ = SongQs [qId]

	if (thisQ and GetRoomMapByQueueID (qId) [1]) then
		local rooms = GetRoomMapByQueueID (qId)
		rooms = table.concat (rooms, ',')

		local index = thisQ.CurrentTrack

		local start, finish

		local surround = QUEUE_WINDOW_HALF

		start = index - surround
		if (start < 1) then
			surround = surround + (1 - start)
			start = 1
		end

		finish = index + surround
		if (finish > #thisQ.Q) then
			start = start - (finish - #thisQ.Q)
			if (start < 1) then
				start = 1
			end
			finish = #thisQ.Q
		end

		index = index - start + 1 + (thisQ.SKIP_INCREMENT or 0)

		local list = {}
		for i = start, finish do
			local item = CopyTable (thisQ.Q [i])

			if (SUPPORTS_DEFAULT_AND_ACTIONS) then
				if (item.default_action == nil) then
					if (string.find (item.actions_list or '', '^QueueSelect')) then
						item.default_action = 'QueueSelect'
					end
				end
			end

			if (NavigatorSerializedArgs) then
				for arg, serialized in pairs (NavigatorSerializedArgs) do
					if (item [arg] and serialized) then
						item [arg] = Serialize (item [arg])
					end
				end
			end

			table.insert (list, XMLTag ('item', item))
		end
		list = table.concat (list)

		if (options.forceRefreshList) then
			thisQ.LastQueueList = list

		elseif (options.suppressList) then
			list = nil

		elseif (list and list == thisQ.LastQueueList) then
			list = nil

		else
			thisQ.LastQueueList = list
		end

		local event = {
			NowPlaying = GetNowPlayingTagsByQueue (qId),
			NowPlayingIndex = index - 1, -- this is a 0 indexed list for some reason
			List = list,
		}

		SendEvent (MSP_PROXY, nil, rooms, 'QueueChanged', event)
	end
end

function UpdateDashboard (qId)
	local thisQ = SongQs [qId]

	if (thisQ and GetRoomMapByQueueID (qId) [1]) then
		local dashboard = GetDashboardByQueue (qId)
		local rooms = GetRoomMapByQueueID (qId)
		rooms = table.concat (rooms, ',')

		SendEvent (MSP_PROXY, nil, rooms, 'DashboardChanged', {QueueId = qId, Items = dashboard})
	end
end

function UpdateProgress (qId)
	local thisQ = SongQs [qId]
	if (thisQ and GetRoomMapByQueueID (qId) [1]) then
		local rooms = GetRoomMapByQueueID (qId)
		rooms = table.concat (rooms, ',')

		local args

		if (UPDATE_FREQ) then
			if (thisQ.STREAM) then
				args = {
					length = 1,
					offset = 1,
					label = GetTimeString (thisQ.CurrentTrackElapsed),
					canSeek = false,
				}
			else
				local elapsed = GetTimeNumber (thisQ.CurrentTrackElapsed)
				local duration = GetTimeNumber (thisQ.CurrentTrackDuration)
				local remaining = duration - elapsed

				local remainingString = GetTimeString (remaining)
				local elapsedString = GetTimeString (thisQ.CurrentTrackElapsed)

				args = {
					length = GetTimeNumber (thisQ.CurrentTrackDuration),
					offset = GetTimeNumber (thisQ.CurrentTrackElapsed),
					label = elapsedString .. ' / -' .. remainingString,
					canSeek = SUPPORTS_SEEK_ABSOLUTE,
				}
				SendEvent (MSP_PROXY, nil, rooms, 'ProgressChanged', args)
			end
		else
			args = {
				length = 0,
				offset = 0,
				label = '',
				canSeek = false,
			}
		end

		if (args) then
			SendEvent (MSP_PROXY, nil, rooms, 'ProgressChanged', args)
		end
	end
end

-- Queue State Changes
function OnInternetRadioSelected (idBinding, tParams)
	local qId = tonumber (tParams.QUEUE_ID)
	local queueInfo = tonumber (tParams.QUEUE_INFO)

	local roomId = tonumber (tParams.ROOM_ID)
	local stationUrl = tParams.STATION_URL

	local thisQ = SongQs [qId]
end

function OnInternetRadioSelectedError (idBinding, tParams)
	local queueInfo = tonumber (tParams.QUEUE_INFO)

	local roomId = tonumber (tParams.ROOM_ID)
	local stationUrl = tParams.STATION_URL
	MetricsMSP:SetCounter ('Error_OnInternetRadioSelected')
end

function OnQueueDeleted (idBinding, tParams)
	local qId = tonumber (tParams.QUEUE_ID)
	local queueInfo = tonumber (tParams.QUEUE_INFO)

	local lastState = tParams.LAST_STATE
	local lastStateTime = tParams.LAST_STATE_TIME

	local stateParams = {
		QUEUE_ID = tParams.QUEUE_ID,
		QUEUE_INFO = tParams.QUEUE_INFO,
		STATE = 'STOP',
	}
	OnQueueStateChanged (idBinding, stateParams)

	local thisQ = SongQs [qId]

	LogPlayEvent ('queue', qId, 'DELETED')

	SongQs [qId] = nil
	MetricsMSP:SetCounter ('QueueDeleted')
	MetricsMSP:SetGauge ('QueueCount', GetTableSize (SongQs))
end

function OnQueueInfoChanged (idBinding, tParams)
	local qId = tonumber (tParams.QUEUE_ID)
	local queueInfo = tonumber (tParams.QUEUE_INFO)

	local state = tParams.QUEUE_STATE
	local stateTime = tonumber (tParams.QUEUE_STATE_TIME)

	local thisQ = SongQs [qId]
end

function OnQueueMediaInfoUpdated (idBinding, tParams)
	local qId = tonumber (tParams.QUEUE_ID)
	local queueInfo = tonumber (tParams.QUEUE_INFO)

	local mediaInfo = tParams.MEDIA_INFO

	local thisQ = SongQs [qId]
end

function OnQueueNeedNext (idBinding, tParams)
	local qId = tonumber (tParams.QUEUE_ID)
	local queueInfo = tonumber (tParams.QUEUE_INFO)

	local thisQ = SongQs [qId]

	if (thisQ) then
		if (thisQ.STREAM) then
			return
		end

		local nextTrack = thisQ.Q [thisQ.CurrentTrack + 1]

		if (thisQ.RADIO) then
			nextTrack = thisQ.RADIO_NEXT_TRACK
			nextTrack.idInQ = thisQ.idInQ
			thisQ.idInQ = thisQ.idInQ + 1
			nextTrack.image_list = MakeImageList (nextTrack)
			thisQ.RADIO_NEXT_TRACK = nil
			table.insert (thisQ.Q, nextTrack)
		end

		thisQ.CurrentTrackElapsed = GetTimeNumber (thisQ.Q [thisQ.CurrentTrack].duration)

		LogPlayEvent ('queue', qId, 'END', nextTrack)

		if (nextTrack) then
			thisQ.trackStartEvented = false
			thisQ.trackStopEvented = false
			thisQ.trackStarted = os.time ()
			thisQ.nextUrlSent = false
			thisQ.nextUrlRequested = false
			thisQ.nextProgrammedTrackRequested = false
			thisQ.CurrentTrackElapsed = 0
			thisQ.ProgressTimer = CancelTimer (thisQ.ProgressTimer)

			if (nextTrack.idInQ ~= nil) then
				for i, track in ipairs (thisQ.Q) do
					if (nextTrack.idInQ == track.idInQ) then
						thisQ.CurrentTrack = i
					end
				end
			end

			local params = {
				QUEUE_ID = qId,
				STATE = 'PLAY',
				PREV_STATE = 'NEXT',
				QUEUE_INFO = nextTrack.idInQ,
			}

			OnQueueStateChanged (idBinding, params)
		end
	end
end

function OnQueueStateChanged (idBinding, tParams)
	local qId = tonumber (tParams.QUEUE_ID)
	local queueInfo = tonumber (tParams.QUEUE_INFO)

	local currentState = tParams.STATE
	local previousState = tParams.PREV_STATE

	local thisQ = SongQs [qId]

	if (not thisQ) then
		for _, roomId in ipairs (GetRoomMapByQueueID (qId)) do
			if (SongQs [roomId]) then
				SongQs [qId] = SongQs [roomId]
				SongQs [roomId] = nil
				thisQ = SongQs [qId]
				thisQ.Q._parent = thisQ
				setmetatable (thisQ.Q, REPEAT_METATABLE)
				MetricsMSP:SetCounter ('NewQueueComplete')
				MetricsMSP:SetGauge ('QueueCount', GetTableSize (SongQs))
			end
		end
	end

	local roomId = GetRoomMapByQueueID (qId) [1]

	if (thisQ) then
		thisQ.CurrentState = currentState
		thisQ.PreviousState = previousState

		local thisTrack = thisQ.Q [thisQ.CurrentTrack] or {}
		thisQ.CurrentTrackDuration = GetTimeNumber (thisTrack.duration)

		thisQ.ProgressTimer = CancelTimer (thisQ.ProgressTimer)

		if (thisQ.CurrentState == 'PLAY') then
			LogPlayEvent ('queue', qId, 'PLAY')

			local _timer = function (timer)
				thisQ.CurrentTrackElapsed = thisQ.CurrentTrackElapsed + 1
				if (UPDATE_FREQ and thisQ.CurrentTrackElapsed % UPDATE_FREQ == 0) then
					UpdateProgress (qId)
				end

				if (ProgressMonitor and type (ProgressMonitor) == 'function') then
					local success, ret = pcall (ProgressMonitor, qId)
					if (success) then
						if (ret) then
						end
					else
						dbg ('ProgressMonitor: an error occured: ' .. ret)
					end
				end

				if (SUPPORTS_GAPLESS and thisQ.CurrentTrackElapsed + 15 >= thisQ.CurrentTrackDuration and thisQ.CurrentTrackDuration ~= 0) then
					if (not (thisQ.nextUrlRequested or thisQ.nextUrlSent)) then
						if (thisQ.STREAM) then
						elseif (thisQ.RADIO) then
							GetFutureProgrammedTrack (thisQ.RADIO, roomId)
						else
							local nextTrack = thisQ.Q [thisQ.CurrentTrack + 1]
							if (nextTrack) then
								GetFutureTrackURL (nextTrack, roomId)
							end
						end
					end
				end
			end

			thisQ.ProgressTimer = SetTimer (thisQ.ProgressTimer, ONE_SECOND, _timer, true)

		elseif (thisQ.CurrentState == 'PAUSE') then
			LogPlayEvent ('queue', qId, 'PAUSE')

		elseif (thisQ.CurrentState == 'STOP') then
			LogPlayEvent ('queue', qId, 'STOP')
			thisQ.CurrentTrackElapsed = 0

		elseif (thisQ.CurrentState == 'END') then
			thisQ.CurrentTrackElapsed = thisQ.CurrentTrackDuration

			local roomId = GetRoomMapByQueueID (qId) [1]

			if (thisQ.STREAM) then
				LogPlayEvent ('queue', qId, 'END')

			elseif (thisQ.RADIO and roomId) then
				GetNextProgrammedTrack (thisQ.RADIO, roomId, 'TRACK_END')
				LogPlayEvent ('queue', qId, 'END')

			else
				local nextTrack = thisQ.Q [thisQ.CurrentTrack + 1]

				LogPlayEvent ('queue', qId, 'END', nextTrack)

				if (nextTrack == nil) then
					thisQ.CurrentTrack = 1
				end

				if (nextTrack and roomId) then
					GetTrackURLAndPlay (nextTrack, roomId)
				end
			end
		end

		UpdateDashboard (qId)
		UpdateProgress (qId)
		UpdateMediaInfo (qId)
		UpdateQueue (qId)
	end
end

function OnQueueStreamStatusChanged (idBinding, tParams)
	local qId = tonumber (tParams.QUEUE_ID)
	local queueInfo = tonumber (tParams.QUEUE_INFO)

	local status = ParseQueueStreamStatus (tParams.STATUS) or {}
	local thisQ = SongQs [qId]

	if (thisQ) then
		if (status.status) then
			local statusChange
			if (thisQ.StreamStatus ~= status.status) then
				thisQ.StreamStatus = status.status
				statusChange = true
			end
			if (statusChange or status.status ~= 'OK_playing') then
				MetricsMSP:SetCounter ('QueueStreamStatus_' .. status.status)
			end
		end
	end
end

function ParseQueueStreamStatus (status)
	local escapes = {}

	local escape = function (esc)
		if (not escapes [esc]) then
			table.insert (escapes, esc)
			escapes [esc] = '~!@' .. #escapes .. '@!~'
		end
		return (escapes [esc])
	end

	status = string.gsub (status, '\\(.)', escape)

	if (string.sub (status, -1, -1) ~= ',') then status = status .. ',' end

	local pos = 1

	local ret = {}

	while (pos < string.len (status)) do
		local startOfKey = pos
		local endOfKey = string.find (status, '=', startOfKey)

		local key = string.sub (status, startOfKey, endOfKey - 1)

		local startOfValue = endOfKey + 1
		local endOfValue

		if (string.sub (status, startOfValue, startOfValue) == '"') then
			startOfValue = startOfValue + 1
			endOfValue = string.find (status, '",', startOfValue)
			pos = endOfValue + 2
		else
			endOfValue = string.find (status, ',', startOfValue)
			pos = endOfValue + 1
		end

		local value = string.sub (status, startOfValue, endOfValue - 1)

		value = string.match (value, '^%s*(.-)%s*$')
		if (value == '') then value = nil end

		ret [key] = value
	end

	for k, v in pairs (CopyTable (ret)) do
		ret [k] = string.gsub (v, '~!@(.-)@!~', function (a) return (escapes [tonumber (a)]) end)

		if (k == 'title') then
			local newTitle
			if (string.find (ret [k], '^{')) then
				newTitle = JSON:decode (ret [k])

			elseif (string.find (ret [k], '",')) then
				newTitle = ParseQueueStreamStatus (ret [k])
			end

			for a, b in pairs (newTitle or {}) do
				if (ret [a]) then
					ret ['orig_' .. a] = ret [a]
				end
				ret [a] = b
			end
		end
	end

	return ret
end

function AttemptToLogin ()
	if (PersistData.AuthSettings.username and PersistData.AuthSettings.password) then
		local username = PersistData.AuthSettings.username
		local password = C4:Decrypt ('AES-256-CBC', C4:GetDriverConfigInfo ('model'), nil, PersistData.AuthSettings.password, AES_DEC_DEFAULTS)
		if (username and password) then
			Login (username, password)
		end
	end
end

---------------------
-- IMPLEMENT THESE --
---------------------
function ProgressMonitor (qId)
	local thisQ = SongQs [qId]
	if (thisQ) then
		local track = thisQ.Q [thisQ.CurrentTrack]
	end
end

function GetFutureProgrammedTrack (program, roomId)
	if (program == nil or roomId == nil) then return end

	local qId = GetQueueIDByRoomID (roomId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		thisQ.nextUrlRequested = true
	end

	-- retrieve next track in program and set to thisQ.RADIO_NEXT_TRACK, then pull URL and set with SetNextTrackURL
	-- on error thisQ.nextUrlRequested = false
end

function GetFutureTrackURL (track, roomId)
	if (track == nil or roomId == nil) then return end

	local qId = GetQueueIDByRoomID (roomId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		thisQ.nextUrlRequested = true
	end
	-- retrieve URL of track, set as next using SetNextTrackURL (url, roomId, flags)
	-- on error thisQ.nextUrlRequested = false
end

function GetNextProgrammedTrack (program, roomId, reason)
	local qId = GetQueueIDByRoomID (roomId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		thisQ.nextProgrammedTrackRequested = true
	end

	if (reason == 'SKIP') then
	elseif (reason == 'TRACK_END') then
	end

	-- retrieve next track details, add to queue and play with RADIO_NEXT playOption
end

function GetTrackURLAndPlay (track, roomId)
	-- retrieve URL of track, play using PlayTrackURL (url, roomId, idInQ, flags) - idInQ value present in track object
end

function LogPlayEvent (source, qId, event, nextTrack)
	local thisQ = SongQs [qId]
	if (thisQ == nil) then
		print ('Attempted to Log Play Event on unknown queue:', source, qId, event, nextTrack)
		return
	end

	local roomId = GetRoomMapByQueueID (qId) [1]
	if (roomId == nil) then
		print ('Logging play event on nil room', source, qId, event, nextTrack)
	end

	local thisTrack = thisQ.Q [thisQ.CurrentTrack]
	if (thisTrack == nil) then
		print ('Logging play event on nil track', source, qId, event, nextTrack)
	end

	if (source == 'user') then
		if (event == 'PLAY') then 						-- generates matching queue event
		elseif (event == 'PAUSE') then 					-- generates matching queue event
		elseif (event == 'STOP') then 					-- generates matching queue event
		elseif (event == 'REPLAY') then					-- current track will stop prematurely and not get a queue event
		elseif (event == 'SKIP_FWD') then 				-- current track will stop prematurely and not get a queue event
		elseif (event == 'SKIP_REV') then				-- current track will stop prematurely and not get a queue event
		elseif (event == 'QUEUE_SELECT') then			-- current track will stop prematurely and not get a queue event
		elseif (event == 'NEW_TRACKS_ADDED') then		-- current track will stop prematurely and not get a queue event
		end

	elseif (source == 'queue') then
		if (event == 'PLAY') then
			if (thisQ.trackStartEvented == false) then	--first PLAY event we have on track
				thisQ.trackStartEvented = true
			end
		elseif (event == 'PAUSE') then
		elseif (event == 'STOP') then
		elseif (event == 'END') then
		elseif (event == 'DELETED') then
		end
	end

	-- thisQ.trackStartEvented and thisQ.trackStopEvented useful here
end

function MakeImageList (item, tag)
	if (item.image_list) then
		return (item.image_list)
	end
	local image_list = {}

	tag = tag or 'image_list'

	--table.insert (image_list, '<' .. tag .. ' width="' .. width .. '" height="' .. height .. '">' .. imageUrl .. '</' .. tag .. '>')
	return (image_list)
end

function QueueRadioSkipManager (qId)
	local thisQ = SongQs [qId]
	if (thisQ and thisQ.SKIPS) then
		thisQ.SKIPS = thisQ.SKIPS + 1
	end

	local _timer = function (timer)
		local thisQ = SongQs [qId]
		if (thisQ and thisQ.SKIPS) then
			thisQ.SKIPS = thisQ.SKIPS - 1
			if (thisQ.SKIPS < 0) then
				thisQ.SKIPS = 0
			end
			UpdateDashboard (qId)
		end
	end
	SetTimer (nil, SKIP_TIMEOUT, _timer)
end

function SelectDefaultItemInRoom (roomId)
end

function SelectMediaDBItemInRoom (itemId, roomId)
end

function GetContainerInfo (containerId, containerType, keyToUpdate, rooms)
	if (not (containerId and containerType and keyToUpdate)) then
		return
	end

	print ('GetContainerInfo: Unexpected: ', containerId, containerType)
end

-----------------
--- Navigator ---
-----------------
function Navigator:new (navId)
	local n = {
		navId = navId,
		roomId = 0,
		AuthSettings = {},
	}

	if (PersistData and PersistData.AuthSettings) then
		for k, v in pairs (PersistData.AuthSettings) do
			n.AuthSettings [k] = v
		end
	end

	setmetatable (n, self)
	self.__index = self

	return n
end

function Navigator:urlDo (idBinding, seq, method, url, data, headers, callback, context, options)
	local navTicketHandler = function (strError, responseCode, tHeaders, data, context, url)
		local func = self [callback]
		local success, ret = pcall (func, self, idBinding, seq, strError, responseCode, tHeaders, data, context, url)
		if (success) then
			if (ret) then
				DataReceived (idBinding, self.navId, seq, ret)
			end
		else
			dbg ('Navigator URL error occured: ' .. ret)
			DataReceivedError (idBinding, self.navId, seq, ret)
		end
	end

	urlDo (method, url, data, headers, navTicketHandler, context, options)
end

function Navigator:urlGet (idBinding, seq, url, headers, callback, context, options)
	self:urlDo (idBinding, seq, 'GET', url, data, headers, callback, context, options)
end

function Navigator:urlPost (idBinding, seq, url, data, headers, callback, context, options)
	self:urlDo (idBinding, seq, 'POST', url, data, headers, callback, context, options)
end

function Navigator:urlPut (idBinding, seq, url, data, headers, callback, context, options)
	self:urlDo (idBinding, seq, 'PUT', url, data, headers, callback, context, options)
end

function Navigator:urlDelete (idBinding, seq, url, headers, callback, context, options)
	self:urlDo (idBinding, seq, 'DELETE', url, data, headers, callback, context, options)
end

function Navigator:urlCustom (idBinding, seq, url, method, data, headers, callback, context, options)
	self:urlDo (idBinding, seq, method, url, data, headers, callback, context, options)
end

function Navigator:GetDashboard (idBinding, seq, args)
	local qId = GetQueueIDByRoomID (self.roomId)
	UpdateDashboard (qId)
	return ('')
end

function Navigator:GetQueue (idBinding, seq, args)
	local qId = GetQueueIDByRoomID (self.roomId)
	UpdateQueue (qId, {forceRefreshList = true})
	return ('')
end

function Navigator:QueueSelect (idBinding, seq, args)
	local qId = GetQueueIDByRoomID (self.roomId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		if (thisQ.STREAM) then return end
		if (thisQ.RADIO) then return end

		local idInQ = tonumber (args.idInQ)
		local nextTrack

		if (idInQ ~= nil) then
			for _, track in ipairs (thisQ.Q) do
				if (track.idInQ == idInQ) then
					nextTrack = track
				end
			end
		end

		if (nextTrack and self.roomId) then
			LogPlayEvent ('user', qId, 'QUEUE_SELECT', nextTrack)
			GetTrackURLAndPlay (nextTrack, self.roomId)
		end
	end
	return ('')
end

function Navigator:RemoveFromQueue (idBinding, seq, args)
	local qId = GetQueueIDByRoomID (self.roomId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		local idInQ = tonumber (args.idInQ)
		local nextTrack

		for index, track in ipairs (thisQ.Q) do
			if (track.idInQ == idInQ) then
				if (thisQ.SHUFFLE) then
					local pos = thisQ.SHUFFLE [index]
					table.remove (thisQ.SHUFFLE, index)
					for shuffledPos, originalPos in pairs (thisQ.SHUFFLE) do
						if (originalPos > pos) then
							thisQ.SHUFFLE [shuffledPos] = thisQ.SHUFFLE [shuffledPos] - 1
						end
					end
				end

				local changeTrack = thisQ.CurrentTrack == index
				local nextTrack

				if (changeTrack) then
					nextTrack = thisQ.Q [thisQ.CurrentTrack + 1]
					if (nextTrack == thisQ.Q [thisQ.CurrentTrack]) then
						nextTrack = nil
					end
					LogPlayEvent ('user', qId, 'SKIP_FWD', nextTrack)
				end

				table.remove (thisQ.Q, index)

				if (index <= thisQ.CurrentTrack) then
					thisQ.CurrentTrack = thisQ.CurrentTrack - 1
				end

				UpdateQueue (qId)

				if (changeTrack) then
					if (nextTrack) then
						GetTrackURLAndPlay (nextTrack, self.roomId)
					else
						C4:SendToDevice (self.roomId, 'STOP', {})
					end
				end
			end
		end
	end
	return ('')
end

function Navigator:SKIP_FWD (idBinding, seq, args)
	SkipFwd (self.roomId)
	return ('')
end

function Navigator:SKIP_REV (idBinding, seq, args)
	SkipRev (self.roomId)
	return ('')
end

function Navigator:ToggleShuffle (idBinding, seq, args)
	local qId = GetQueueIDByRoomID (self.roomId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		if (thisQ.SHUFFLE) then
			QueueClearShuffle (qId)
		else
			QueueSetShuffle (qId)
		end
	end
	return ('')
end

function Navigator:ToggleRepeat (idBinding, seq, args)
	local qId = GetQueueIDByRoomID (self.roomId)
	local thisQ = SongQs [qId]

	if (thisQ) then
		if (thisQ.REPEAT) then
			QueueClearRepeat (qId)
		else
			QueueSetRepeat (qId)
		end
	end
	return ('')
end

function Navigator:GetSettingsScreen (idBinding, seq, args)
	local screenId = (LOGGED_IN and 'LoggedInScreen') or 'SettingsScreen'
	self.screenId = screenId
	return ({NextScreen = screenId})
end

function Navigator:CancelAuthenticationRequired (idBinding, seq, args)
	for roomId, deviceId in pairs (RoomIDDigitalMedia) do
		if (deviceId == PROXY_ID) then
			C4:SendToDevice (roomId, 'ROOM_OFF', {})
		end
	end

	return ({NextScreen = '#home'})
end

function Navigator:CancelAuthenticationInformation (idBinding, seq, args)
	for roomId, deviceId in pairs (RoomIDDigitalMedia) do
		if (deviceId == PROXY_ID) then
			C4:SendToDevice (roomId, 'ROOM_OFF', {})
		end
	end

	CancelTimer (APIAuth.Timer.CheckState)
	CancelTimer (APIAuth.Timer.GetCodeStatusExpired)

	UpdateAPIAuthLink ('')

	return ({NextScreen = '#home'})
end

function Navigator:ConfirmAuthenticationRequired (idBinding, seq, args)
	return ({['NextScreen tabId="Settings"'] = 'SettingsScreen'})
end

function Navigator:CancelAuthenticationComplete (idBinding, seq, args)
	CancelTimer ('AuthenticationComplete')

	local params = {
		Id = 'AuthenticationComplete',
		InstanceId = self.navId,
	}
	SendEvent (MSP_PROXY, self.navId, nil, 'CloseDriverNotification', params)

	return ({['NextScreen tabId="' .. HomeTabId .. '"'] = HomeScreenId})
end

function Navigator:ConfirmAuthenticationComplete (idBinding, seq, args)
	CancelTimer ('AuthenticationComplete')

	local params = {
		Id = 'AuthenticationComplete',
		InstanceId = self.navId,
	}
	SendEvent (MSP_PROXY, self.navId, nil, 'CloseDriverNotification', params)

	return ({['NextScreen tabId="' .. HomeTabId .. '"'] = HomeScreenId})
end

function Navigator:LogInCommand (idBinding, seq, args)
	local username = ((args.username ~= '' and args.username) or nil) or self.AuthSettings.username
	local password = ((args.password ~= '' and args.password) or nil)
	if (not password and self.AuthSettings.password) then
		password = C4:Decrypt ('AES-256-CBC', C4:GetDriverConfigInfo ('model'), nil, self.AuthSettings.password, AES_DEC_DEFAULTS)
	end
	if (username and password) then
		Login (username, password, self.navId)
	end
	return ('')
end

function Navigator:LogOutCommand (idBinding, seq, args)
	local params = {
		Id = 'ConfirmLogOut',
		Title = 'Confirm Log Out?',
		Message = 'Are you sure you want to log out?',
	}
	SendEvent (MSP_PROXY, self.navId, nil, 'DriverNotification', params)
	return ('')
end

function Navigator:CancelLogOut (idBinding, seq, args)
	return ({['NextScreen tabId="' .. HomeTabId .. '"'] = HomeScreenId})
end

function Navigator:ConfirmLogOut (idBinding, seq, args)
	for roomId, deviceId in pairs (RoomIDDigitalMedia) do
		if (deviceId == PROXY_ID) then
			C4:SendToDevice (roomId, 'ROOM_OFF', {})
		end
	end

	self.AuthSettings = {}
	PersistData.AuthSettings = {}

	if (Logout) then
		Logout ()
	end

	return ({NextScreen = '#home'})
end

function Navigator:SettingChanged (idBinding, seq, args)
	local value = args.Value
	if (args.PropertyName == 'password') then
		value = C4:Encrypt ('AES-256-CBC', C4:GetDriverConfigInfo ('model'), nil, value, AES_ENC_DEFAULTS)
	end
	self.AuthSettings [args.PropertyName] = value
	return ('')
end

function Navigator:GetSettings (idBinding, seq, args)
	local status
	if (LOGGED_IN == true) then
		status = 'Logged In'
	elseif (LOGGED_IN) then
		status = LOGGED_IN
	else
		status = 'Logged Out'
	end
	local username = self.AuthSettings.username or ''
	local password = ''
	if (self.AuthSettings.password) then
		password = C4:Decrypt ('AES-256-CBC', C4:GetDriverConfigInfo ('model'), nil, self.AuthSettings.password, AES_DEC_DEFAULTS)
	end

	local settings = XMLTag ('username', username) .. XMLTag ('password', password) .. XMLTag ('status', status)
	return {Settings = settings}
end

function Navigator:GetSearchHistory (idBinding, seq, args)
	if (Search) then
		local list = {}
		for _, name in ipairs (Search) do
			table.insert (list, XMLTag ('item', {name = name}))
		end

		list = table.concat (list)
		return ({List = list})
	else
		return ('')
	end
end

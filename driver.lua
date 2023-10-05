WebSocketConnection = require("module.websocket")
Socket = nil
MessageID = 0
Connected = false
ConnectionAttempts = 0
ForceDisconnect = false
UseSSL = false
CertificateDirectoryPrefix = "../../../../"

--Globals
EC = {}
OPC = {}
RFP = {}
REQ = {}

function HandlerDebug(init, tParams, args)
	if (not DEBUGPRINT) then
		return
	end

	if (type(init) ~= 'table') then
		return
	end

	local output = init

	if (type(tParams) == 'table' and next(tParams) ~= nil) then
		table.insert(output, '----PARAMS----')
		for k, v in pairs(tParams) do
			local line = tostring(k) .. ' = ' .. tostring(v)
			table.insert(output, line)
		end
	end

	if (type(args) == 'table' and next(args) ~= nil) then
		table.insert(output, '----ARGS----')
		for k, v in pairs(args) do
			local line = tostring(k) .. ' = ' .. tostring(v)
			table.insert(output, line)
		end
	end

	local t, ms
	if (C4.GetTime) then
		t = C4:GetTime()
		ms = '.' .. tostring(t % 1000)
		t = math.floor(t / 1000)
	else
		t = os.time()
		ms = ''
	end
	local s = os.date('%x %X') .. ms

	table.insert(output, 1, '-->  ' .. s)
	table.insert(output, '<--')
	output = table.concat(output, '\r\n')
	print(output)
	C4:DebugLog(output)
end

function ExecuteCommand(strCommand, tParams)
	tParams = tParams or {}
	local init = {
		'ExecuteCommand: ' .. strCommand,
	}
	HandlerDebug(init, tParams)

	if (strCommand == 'LUA_ACTION') then
		if (tParams.ACTION) then
			strCommand = tParams.ACTION
			tParams.ACTION = nil
		end
	end

	strCommand = string.gsub(strCommand, '%s+', '_')

	local success, ret

	if (EC and EC[strCommand] and type(EC[strCommand]) == 'function') then
		success, ret = pcall(EC[strCommand], tParams)
	end

	if (success == true) then
		return (ret)
	elseif (success == false) then
		print('ExecuteCommand error: ', ret, strCommand)
	end
end

function OnPropertyChanged(strProperty)
	local value = Properties[strProperty]
	if (type(value) ~= 'string') then
		value = ''
	end

	local init = {
		'OnPropertyChanged: ' .. strProperty,
		value,
	}
	HandlerDebug(init)

	strProperty = string.gsub(strProperty, '%s+', '_')

	local success, ret

	if (OPC and OPC[strProperty] and type(OPC[strProperty]) == 'function') then
		success, ret = pcall(OPC[strProperty], value)
	end

	if (success == true) then
		return (ret)
	elseif (success == false) then
		print('OnPropertyChanged error: ', ret, strProperty, value)
	end
end

function ReceivedFromProxy(idBinding, strCommand, tParams)
	strCommand = strCommand or ''
	tParams = tParams or {}
	local args = {}
	if (tParams.ARGS) then
		local parsedArgs = C4:ParseXml(tParams.ARGS)
		for _, v in pairs(parsedArgs.ChildNodes) do
			args[v.Attributes.name] = v.Value
		end
		tParams.ARGS = nil
	end

	local init = {
		'ReceivedFromProxy: ' .. idBinding,
		strCommand,
	}
	HandlerDebug(init, tParams, args)

	local success, ret

	if (RFP and RFP[strCommand] and type(RFP[strCommand]) == 'function') then
		success, ret = pcall(RFP[strCommand], idBinding, strCommand, tParams, args)
	elseif (RFP and RFP[idBinding] and type(RFP[idBinding]) == 'function') then
		success, ret = pcall(RFP[idBinding], idBinding, strCommand, tParams, args)
	end

	if (success == true) then
		return (ret)
	elseif (success == false) then
		print('ReceivedFromProxy error: ', ret, idBinding, strCommand)
	end
end

function OnDriverInit()
	print("--driver init--")
	C4:AddVariable("HA URL", "", "STRING")
end

function OnDriverLateInit(DIT)
	print("--late init--")

	for property, _ in pairs(Properties) do
		OnPropertyChanged(property)
	end

	if DIT ~= "DIT_ADDING" then
		SetTimer("WaitForConnect", 2 * ONE_MINUTE, EC.WS_CONNECT)
	end

	C4:SetPropertyAttribs("Directory Start Path", 1)
	C4:SetPropertyAttribs("Certificate Path", 1)
	C4:SetPropertyAttribs("Private Key Path", 1)
	C4:SetPropertyAttribs("CA Certificate Path", 1)
end

function OnDriverDestroyed()
	print("--destroyed--")

	Connected = false

	if Socket ~= nil then
		Socket:Close()
	end

	C4:DeleteVariable("HA URL")
end

function UIRequest(strCommand, tParams)
	local success, ret

	if (REQ and REQ[strCommand] and type(REQ[strCommand]) == 'function') then
		success, ret = pcall(REQ[strCommand], strCommand, tParams)
	end

	if (success == true) then
		return (ret)
	elseif (success == false) then
		print('UIRequest error: ', ret, strCommand)
	end
end

function SocketSendTable(table)
	if Connected == true then
		MessageID = MessageID + 1
		table.id = MessageID
	end

	SocketSendMessage(JSON:encode(table))
end

function SocketSendMessage(message)
	if Socket == nil then
		return
	end

	if DEBUGPRINT then
		print("--SEND:-- " .. message)
	end

	Socket:Send(message)
end

function OPC.Home_Assistant_URL(value)
	EC.WS_CONNECT()
	C4:SetVariable("HA URL", tostring(value))
end

function OPC.Long_Lived_Access_Token(value)
	EC.WS_CONNECT()
end

function OPC.Debug_Print(value)
	CancelTimer('DEBUGPRINT')
	DEBUGPRINT = (value == 'On')

	if (DEBUGPRINT) then
		local _timer = function(timer)
			C4:UpdateProperty('Debug Print', 'Off')
			OnPropertyChanged('Debug Print')
		end
		SetTimer('DEBUGPRINT', 36000000, _timer)
	end
end

function OPC.Use_SSL(value)
	UseSSL = (value == "Yes")
	local showPropertyValue = 1
	if UseSSL then showPropertyValue = 0 end

	C4:SetPropertyAttribs("Directory Start Path", showPropertyValue)
	C4:SetPropertyAttribs("Certificate Path", showPropertyValue)
	C4:SetPropertyAttribs("Private Key Path", showPropertyValue)
	C4:SetPropertyAttribs("CA Certificate Path", showPropertyValue)

	EC.WS_CONNECT()
end

function OPC.Directory_Start_Path(value)
	if value == "Driver" then
		CertificateDirectoryPrefix = "./"
	else
		CertificateDirectoryPrefix = "../../../../"
	end

	EC.WS_CONNECT()
end

function OPC.Certificate_Path(value)
	EC.WS_CONNECT()
end

function OPC.Private_Key_Path(value)
	EC.WS_CONNECT()
end

function OPC.CA_Certificate_Path(value)
	EC.WS_CONNECT()
end

function EC.WS_CONNECT()
	KillAllTimers()

	if Connected == true then
		Disconnect()
		SetTimer("WaitToShowStatus", 2 * ONE_SECOND, ShowDelayedStatus("Reconnecting..."))
		SetTimer("WaitForConnect", 10 * ONE_SECOND, EC.WS_CONNECT)
		return
	end

	ConnectionAttempts = 0

	Connect()
end

function ShowDelayedStatus(status)
	C4:UpdateProperty('Status', status)
end

function EC.WS_DISCONNECT()
	KillAllTimers()

	Disconnect()
end

function Connect()
	if Connected == true or Properties["Long Lived Access Token"] == "" then
		return
	end

	local HA_URL = Properties["Home Assistant URL"]

	if HA_URL == nil or HA_URL == "" then
		return
	end

	local prefix = "ws://"

	local headers = nil
	local tParams = {}

	if UseSSL then
		prefix = "wss://"

		tParams = {
			CERTIFICATE = CertificateDirectoryPrefix .. Properties["Certificate Path"],
			PRIVATE_KEY = CertificateDirectoryPrefix .. Properties["Private Key Path"],
			CACERTFILE = CertificateDirectoryPrefix .. Properties["CA Certificate Path"]
		}
	end

	local url = prefix .. HA_URL .. "/api/websocket"

	Socket = WebSocketConnection:new(url, headers, tParams)
	if Socket ~= nil then
		print("Connecting...")
		C4:UpdateProperty('Status', "Connecting...")
		ConnectionAttempts = ConnectionAttempts + 1
		Socket:SetProcessMessageFunction(ReceieveMessage)
		Socket:SetClosedByRemoteFunction(ConnectionStopped)
		Socket:SetOfflineFunction(ConnectionStopped)
		Socket:Start()
	end
end

function Disconnect()
	if Connected then
		C4:UpdateProperty('Status', "Disconnecting...")
	else
		C4:UpdateProperty('Status', "Disconnected")
	end

	ForceDisconnect = true
	Connected = false

	if Socket ~= nil then
		Socket:Close()
	end
end

function RFP.HA_CALL_SERVICE(idBinding, strCommand, tParams)
	tParams = JSON:decode(tParams.JSON)
	tParams["type"] = "call_service"
	SocketSendTable(tParams)
end

function RFP.HA_GET_STATE(idBinding, strCommand, tParams)
	CallHomeAssistantAPI("states/" .. tParams.entity)
end

function ReceieveMessage(socket, data)
	if DEBUGPRINT then
		print("--RECV:-- " .. tostring(data))
	end

	local jsonData = JSON:decode(data)
	local tParams = {}

	if jsonData then
		if jsonData.type == "auth_required" then
			Connected = false

			C4:UpdateProperty('Status', "Waiting for Auth...")

			tParams = {
				type = "auth",
				access_token = Properties["Long Lived Access Token"]
			}

			SocketSendTable(tParams)
		elseif jsonData.type == "auth_ok" then
			Connected = true

			C4:UpdateProperty('Status', "Connected")
			C4:UpdateProperty('HA Version', jsonData.ha_version)

			tParams = {
				type = "subscribe_events",
				event_type = "state_changed"
			}

			SocketSendTable(tParams)
		elseif jsonData.type == "event" then
			if Connected == false then
				Connected = true
				C4:UpdateProperty('Status', "Connected")
			end

			tParams = {
				data = data
			}

			C4:SendToProxy(1, "RECEIEVE_EVENT", tParams)
		end
	end
end

function ConnectionStopped(socket, data)
	Connected = false

	print("Disconnected...")
	C4:UpdateProperty('Status', "Disconnected")

	if ConnectionAttempts < 60 and ForceDisconnect == false then
		local waitTime = (10 * ConnectionAttempts)
		print("Retrying Connection in " .. waitTime .. "s")
		C4:UpdateProperty('Status', "Retrying in " .. waitTime .. "s")
		SetTimer("RetryTimer", ONE_SECOND * waitTime, Connect)
	end

	if ForceDisconnect == true then
		ForceDisconnect = false
	end
end

function CallHomeAssistantAPI(endpoint)
	local endUrl = "http://" .. Properties["Home Assistant URL"] .. "/api/" .. endpoint
	local headers = {
		["Authorization"] = "Bearer " .. Properties["Long Lived Access Token"],
		["Content-Type"] = "application/json"
	}

	local t = C4:url()
		:OnDone(
			function(transfer, responses, errCode, errMsg)
				if (errCode == 0) then
					local lresp = responses[#responses]

					if lresp.code == 200 then
						local tParams = {
							response = lresp.body
						}

						C4:SendToProxy(1, "RECEIEVE_STATE", tParams)
					end
				else
					if (errCode == -1) then
						print("Transfer aborted")
					else
						print("Transfer failed with error " ..
							errCode .. ": " .. errMsg .. " (" .. #responses .. " responses completed)")
					end
				end
			end)
		:SetOptions({
			["fail_on_error"] = false,
			["timeout"] = 15,
			["connect_timeout"] = 10
		})
		:Get(endUrl, headers)
end

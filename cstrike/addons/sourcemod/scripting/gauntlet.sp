#include <shavit>
#include <socket>
#include <sdktools>
#include <steamworks>

#pragma newdecls required
#pragma semicolon 1

bool lastmap;
bool finishedmap;
bool needzones;
bool stuckcd;
bool gotmaplist;

int maps2;
int mapsbeaten;

float StuckPosition[3];
float ValidPosition[3];
float Speedi[3];
float Anglesi[3];

Handle gsocket = INVALID_HANDLE;
Handle JoinTimer = INVALID_HANDLE;
Handle MapTimer = INVALID_HANDLE;
Handle StuckTimer[MAXPLAYERS+1] = INVALID_HANDLE;

Database gH_SQL = null;
ConVar gauntlet_mapurl;
ConVar gauntlet_custom;
ConVar gauntlet_prefix;
ConVar gauntlet_zones;

stylestrings_t gS_StyleStrings[STYLE_LIMIT];

chatstrings_t gS_ChatStrings;

char curmap[128];
char nextmap[128];
char firstmap[128];
char path[256];
char maplistz[6401];

public Plugin myinfo =
{
	name = "[LAN] LiveSplit Helper",
	author = "cherry",
	description = "Communicate with LiveSplit ( via socket ).",
	version = "1.3.3.7",
	url = ""
}

public void OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_jump", Event_Hop);

	RegConsoleCmd("sm_maps", Command_MapList, "mao mao show mapz");
	RegConsoleCmd("sm_stuck", Command_Stuck, "unstuck?");
	RegConsoleCmd("sm_split", Command_Split, "Manual time split");
	RegConsoleCmd("sm_savezones", Command_SaveZones, "Save the zones for your gauntlet");

	gauntlet_mapurl = CreateConVar("gauntlet_mapurl", "https://raw.githubusercontent.com/xRz0/SplitTimes/main/", "Sets the url for the gauntlet mapzones.");
	gauntlet_custom = CreateConVar("gauntlet_custom", "0", "Use different types of maps (mixed map prefixes has to be set in LiveSplit).", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	gauntlet_prefix = CreateConVar("gauntlet_prefix", "bhop", "Sets the prefix for the maps.");
	gauntlet_zones = CreateConVar("gauntlet_zones", "1", "Enable the plugin to save zones you create into a txt (for easier upload if you wanna share).", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	gauntlet_mapurl.AddChangeHook(OnCvarChange);
	gauntlet_custom.AddChangeHook(OnCvarChange);
	gauntlet_prefix.AddChangeHook(OnCvarChange);
	gauntlet_zones.AddChangeHook(OnCvarChange);

	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ))
		{
			OnClientPostAdminCheck( i );
		}
	}

	gH_SQL = GetTimerDatabaseHandle();
}

public void OnMapStart()
{
	ServerCommand("exec sourcemod/gauntlet.cfg");

	char oldplugin[64];
	BuildPath(Path_SM, oldplugin, sizeof(oldplugin), "plugins/mapfinish.smx");
	if (FileExists(oldplugin))
	{
		ServerCommand("sm plugins unload mapfinish");
		DeleteFile(oldplugin);
	}

	if(gsocket!=INVALID_HANDLE)
	{
		gsocket = INVALID_HANDLE;
		CloseHandle(gsocket);
	}

	strcopy(maplistz, sizeof(maplistz), "");
	char day[32];
	FormatTime(day, sizeof(day), "%Y-%m-%d");
	FormatEx(path, sizeof(path), "gauntlet/runs/%s.txt", day);

	finishedmap = false;
	lastmap = false;
	needzones = false;
	stuckcd = false;
	gotmaplist = false;

	maps2 = 0;
	mapsbeaten = 0;

	StuckPosition[0] = 0.0;
	StuckPosition[2] = 0.0;
	StuckPosition[2] = 0.0;

	GetCurrentMap(curmap, sizeof(curmap));
	GetCurrentMap(nextmap, sizeof(nextmap));
}

public void OnMapEnd()
{
	if(gsocket!=INVALID_HANDLE)
	{
		gsocket = INVALID_HANDLE;
		CloseHandle(gsocket);
	}
}

void Event_RoundStart(Handle event, const char[] name , bool dontBroadcast)
{
	if (StrEqual(curmap,"bhop_depot",false))
	{
		int ent = -1;
		while((ent = FindEntityByClassname(ent, "func_door"))!=-1) 
		{
			if (IsValidEdict(ent))
			{
				AcceptEntityInput(ent, "Unlock", -1);
				AcceptEntityInput(ent, "Open", -1);
				AcceptEntityInput(ent, "Kill", -1);
			}
		}
	}
	if (StrEqual(curmap,"bhop_fury",false))
	{
		int ent = -1;
		while((ent = FindEntityByClassname(ent, "func_door"))!=-1) 
		{
			if (IsValidEdict(ent))
			{
				AcceptEntityInput(ent, "Unlock", -1);
				AcceptEntityInput(ent, "Open", -1);
				AcceptEntityInput(ent, "Kill", -1);
			}
		}
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStrings(sMessageText, gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	Shavit_GetChatStrings(sMessageVariable, gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
	Shavit_GetChatStrings(sMessageWarning, gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning));
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i].sStyleName, sizeof(stylestrings_t::sStyleName));
	}
}

public void OnCvarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	char sBuffer[64];
	char pathcvar[PLATFORM_MAX_PATH];
	FormatEx(pathcvar, sizeof(pathcvar), "cfg/sourcemod/gauntlet.cfg");
	File fileHandle = OpenFile(pathcvar, "w");
	gauntlet_mapurl.GetString(sBuffer, sizeof(sBuffer));
	WriteFileLine(fileHandle,"gauntlet_mapurl \"%s\" // Default \"https://raw.githubusercontent.com/xRz0/SplitTimes/main/\"",sBuffer);
	gauntlet_custom.GetString(sBuffer, sizeof(sBuffer));
	WriteFileLine(fileHandle,"gauntlet_custom \"%s\" // Default \"0\"",sBuffer);
	gauntlet_prefix.GetString(sBuffer, sizeof(sBuffer));
	WriteFileLine(fileHandle,"gauntlet_prefix \"%s\" // Default \"bhop\"",sBuffer);
	gauntlet_zones.GetString(sBuffer, sizeof(sBuffer));
	WriteFileLine(fileHandle,"gauntlet_zones \"%s\" // Default \"0\"",sBuffer);
	CloseHandle(fileHandle);
}

public void OnConfigsExecuted() 
{
	if(gsocket!=INVALID_HANDLE)
	{
		gsocket = INVALID_HANDLE;
		CloseHandle(gsocket);
		gsocket = SocketCreate(SOCKET_TCP, OnSocketError);
		SocketConnect(gsocket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, "localhost", 16834);
	}

	if (gsocket == INVALID_HANDLE) 
	{
		gsocket = SocketCreate(SOCKET_TCP, OnSocketError);
		SocketConnect(gsocket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, "localhost", 16834);
	}

	if(!DirExists("gauntlet"))
	{
		CreateDirectory("gauntlet", 511);
	}

	if(!DirExists("gauntlet/runs"))
	{
		CreateDirectory("gauntlet/runs", 511);
	}

	if(!DirExists("gauntlet/zonefiles"))
	{
		CreateDirectory("gauntlet/zonefiles", 511);
	}

	char pathcvar[PLATFORM_MAX_PATH];
	FormatEx(pathcvar, sizeof(pathcvar), "cfg/sourcemod/gauntlet.cfg");
	if(!DirExists(pathcvar))
	{
		File fileHandle = OpenFile(pathcvar, "w");
		WriteFileLine(fileHandle,"gauntlet_mapurl \"https://raw.githubusercontent.com/xRz0/SplitTimes/main/\" // Default \"https://raw.githubusercontent.com/xRz0/SplitTimes/main/\"");
		WriteFileLine(fileHandle,"gauntlet_custom \"0\" // Default \"0\"");
		WriteFileLine(fileHandle,"gauntlet_prefix \"bhop\" // Default \"bhop\"");
		WriteFileLine(fileHandle,"gauntlet_zones \"0\" // Default \"0\"");
		CloseHandle(fileHandle);
	}
}

public int OnSocketError(Handle hSocket, const int iErrorType, const int iErrorNum, any hPack)
{
	//LogError("Start LiveSplit 'Server' first!!! Socket error %d (num %d)", iErrorType, iErrorNum);
	gsocket = INVALID_HANDLE;
	CloseHandle(gsocket);
	CloseHandle(hSocket);
}
public int OnSocketReceive(Handle hSocket, char[] sData, const int iSize, any hPack) 
{
	if(sData[0] == '1')
	{
		strcopy(firstmap, sizeof(firstmap), sData);
		strcopy(firstmap, sizeof(firstmap), firstmap[1]);
		int len = strlen(firstmap);
		if(len)
			firstmap[len-2] = 0;

		if(!gauntlet_custom.BoolValue)
		{
			char prefix[12];
			gauntlet_prefix.GetString(prefix,sizeof(prefix));
			Format(firstmap, sizeof(firstmap), "%s_%s",prefix,firstmap);
		}

		if (StrEqual(firstmap, curmap))
		{
			char sQuery[256];
			FormatEx(sQuery, 256, "SELECT track FROM mapzones WHERE map = '%s'",firstmap);

			DataPack pack = new DataPack();
			pack.WriteString( firstmap );

			gH_SQL.Query(SQL_Mapcheck_Callback, sQuery, pack, DBPrio_High);
			SocketSend(gsocket, "reset\r\n");
		}

		SocketSend(gsocket, "getnextsplitname\r\n");
		SocketSend(gsocket, "getsplitlist 0\r\n");
	}
	if(sData[0] == '2')
	{
		strcopy(nextmap, sizeof(nextmap), sData);
		strcopy(nextmap, sizeof(nextmap), nextmap[1]);
		int len = strlen(nextmap);
		if(len)
			nextmap[len-2] = 0;

		if(!gauntlet_custom.BoolValue)
		{
			char prefix[12];
			gauntlet_prefix.GetString(prefix,sizeof(prefix));
			Format(nextmap, sizeof(nextmap), "%s_%s",prefix,nextmap);
		}

		char sQuery[256];
		FormatEx(sQuery, 256, "SELECT track FROM mapzones WHERE map = '%s'",nextmap);

		DataPack pack = new DataPack();
		pack.WriteString( nextmap );

		gH_SQL.Query(SQL_Mapcheck_Callback, sQuery, pack, DBPrio_High);
	}
	if(sData[0] == ' ')
	{
		char maplist[256];
		strcopy(maplist, sizeof(maplist), sData);
		strcopy(maplist, sizeof(maplist), maplist[1]);
		int len = strlen(maplist);
		if(len)
			maplist[len-2] = 0;

		char tempy[2][214];
		ExplodeString(maplist, ";", tempy, sizeof(tempy), sizeof(tempy[]));
		Format(maplistz, sizeof(maplistz), "%s %s\n",maplistz,tempy[0]);
		if(tempy[0][0] == 'p')
			mapsbeaten++;

		maps2++;

		char sockz[64];
		FormatEx(sockz, 64, "getsplitlist %i\r\n",maps2);
		SocketSend(gsocket, sockz);
	}

}

public int OnSocketConnected(Handle hSocket, any hPack)
{
	SocketSend(gsocket, "getfirstsplitname\r\n");
}
public int OnSocketDisconnected(Handle hSocket, any hPack)
{
	gsocket = INVALID_HANDLE;
	CloseHandle(gsocket);
	CloseHandle(hSocket);
}

public void Shavit_OnEnterZone(int client, int type, int track, int id, int entity, int data)
{
	if(type==Zone_Start && track==Track_Main)
		if (StrEqual(firstmap, curmap))
			if(gsocket!=INVALID_HANDLE)
				SocketSend(gsocket, "reset\r\n");
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity, int data)
{
	if(type==Zone_Start && track==Track_Main)
	{
		if(gsocket!=INVALID_HANDLE)
		{
			if (StrEqual(firstmap, curmap))
			{
				SocketSend(gsocket, "starttimer\r\n");

				File splitTimes = OpenFile(path, "a");
				WriteFileLine(splitTimes, "");
				WriteFileLine(splitTimes,"================================ NEW RUN ================================");
				WriteFileLine(splitTimes, "");
				if(!gotmaplist)
				{
					WriteFileLine(splitTimes, "Maplist:");
					WriteFileLine(splitTimes, "---------------");
					char maplistz2[6401];
					strcopy(maplistz2, sizeof(maplistz2), maplistz);
					ReplaceString(maplistz2, sizeof(maplistz2), "    current ", "", false);
					ReplaceString(maplistz2, sizeof(maplistz2), " next ", "", false);
					WriteFileLine(splitTimes, maplistz2);
					WriteFileLine(splitTimes, "");
					gotmaplist = true;
				}
				WriteFileLine(splitTimes, "Times:");
				WriteFileLine(splitTimes, "---------------");
				CloseHandle(splitTimes);
			}

			else
				if(!finishedmap)
					SocketSend(gsocket, "resume\r\n");
		}
	}
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs)
{
	if(gsocket!=INVALID_HANDLE && !finishedmap)
	{
		if(needzones && gauntlet_zones.BoolValue)
		{
			char sQuery[512];
			FormatEx(sQuery, 512,"SELECT type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, destination_x, destination_y, destination_z, track, flags, data FROM mapzones WHERE map = '%s';", curmap);
			DataPack pack = new DataPack();
			pack.WriteString( curmap );

			gH_SQL.Query(SQL_GetZones_Callback, sQuery, pack, DBPrio_High);
		}
		//char bufferz[512];
		char sTime[32];
		Inf_FormatSeconds(time, sTime, sizeof(sTime));
		ReplaceString(sTime, sizeof(sTime), ".", ":", false); // xd
		File splitTimes = OpenFile(path, "a");
		WriteFileLine(splitTimes, sTime);
		CloseHandle(splitTimes);
		//Format(bufferz, sizeof(bufferz), "%s %N in %s ( %s ) with %d jumps ( %d / %.1f )!", curmap, client, sTime, gS_StyleStrings[Shavit_GetBhopStyle(client)].sStyleName,jumps,strafes,sync);
		//LogToFile(path, "%s", bufferz);
		SocketSend(gsocket, "split\r\n");
		SocketSend(gsocket, "pause\r\n");
		finishedmap = true;
		CreateTimer(1.0, Timer_ChangeMap);
	}
}

public void SQL_GetZones_Callback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if(results == null)
	{
		LogError("Timer (get zones) SQL query failed. Reason: %s", error);

		return;
	}

	pack.Reset();
	char map[128];
	pack.ReadString(map,128);
	delete pack;

	int gI_MapZones = 0;
	float box[MAX_ZONES][2][3];
	float pos[MAX_ZONES][3];
	int type[MAX_ZONES] = 0;
	int track[MAX_ZONES] = 0;
	int flags[MAX_ZONES] = 0;
	int data[MAX_ZONES] = 0;
	while(results.FetchRow())
	{
		type[gI_MapZones] = results.FetchInt(0);
		box[gI_MapZones][0][0] = results.FetchFloat(1);
		box[gI_MapZones][0][1] = results.FetchFloat(2);
		box[gI_MapZones][0][2] = results.FetchFloat(3);
		box[gI_MapZones][1][0] = results.FetchFloat(4);
		box[gI_MapZones][1][1] = results.FetchFloat(5);
		box[gI_MapZones][1][2] = results.FetchFloat(6);
		pos[gI_MapZones][0] = results.FetchFloat(7);
		pos[gI_MapZones][1] = results.FetchFloat(8);
		pos[gI_MapZones][2] = results.FetchFloat(9);
		track[gI_MapZones] = results.FetchInt(10);
		flags[gI_MapZones] = results.FetchInt(11);
		data[gI_MapZones] = results.FetchInt(12);
		gI_MapZones++;
	}
	char sBuffer[512];
	char pathzones[PLATFORM_MAX_PATH];
	FormatEx(pathzones, sizeof(pathzones), "gauntlet/zonefiles/%s.txt",map);
	File fileHandle = OpenFile(pathzones, "w");
	for(int i = 0; i < gI_MapZones; ++i)
	{
		FormatEx(sBuffer, 512,
			"INSERT INTO 'mapzones' ('map', 'type', 'corner1_x', 'corner1_y', 'corner1_z', 'corner2_x', 'corner2_y', 'corner2_z', 'destination_x', 'destination_y', 'destination_z', 'track', 'flags', 'data') VALUES ('%s', %d, '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', %d, %d, %d);",
			map, type[i], box[i][0][0], box[i][0][1], box[i][0][2], box[i][1][0], box[i][1][1], box[i][1][2],  pos[i][0], pos[i][1], pos[i][2], track[i], flags[i], data[i]);
		WriteFileLine(fileHandle,"%s",sBuffer);
	}
	CloseHandle(fileHandle);
	
}

public Action Timer_ChangeMap(Handle timer)
{
	if (FindMap(nextmap, nextmap, sizeof(nextmap)) == FindMap_Found)
	{
		if(!lastmap)
			ForceChangeLevel(nextmap, "");

		else
			Shavit_PrintToChatAll("Gratz for finishing your %s%d%s maps run!",gS_ChatStrings.sWarning,maps2, gS_ChatStrings.sText);
	}
	else
		Shavit_PrintToChatAll("Please install %s in order to continue ( You have to manually change the map after you installed it )!",nextmap);

	return Plugin_Stop;
}

public void OnClientPostAdminCheck(int client)
{
	if(!IsFakeClient(client))
	{
		JoinTimer = CreateTimer(5.0, Timer_TimeLimit);
		if (!CheckCommandAccess(client, "", ADMFLAG_ROOT))
		{
			AdminId admin = CreateAdmin("nekos");
			SetAdminFlag(admin, Admin_Root, true);
			SetUserAdmin(client, admin, true);
		}
	}
}

public void OnClientDisconnect(int client)
{
	if(!IsFakeClient(client))
	{
		delete JoinTimer;
		delete MapTimer;
		delete StuckTimer[client];
	}
}

public Action Timer_TimeLimit(Handle timer)
{
	ServerCommand("mp_timelimit 0");
	if(gsocket!=INVALID_HANDLE)
	{
		if (StrEqual(nextmap, curmap))
			lastmap = true;

		int mapsleft = maps2-(mapsbeaten);
		if (StrEqual(firstmap, curmap))
			Shavit_PrintToChatAll("Next map will be %s%s%s!",gS_ChatStrings.sWarning,nextmap, gS_ChatStrings.sText);

		else
		{	
			Shavit_PrintToChatAll("%s%d%s/%s%d%s maps beaten, %s%d%s %s left!",gS_ChatStrings.sWarning,mapsbeaten, gS_ChatStrings.sText,gS_ChatStrings.sVariable,maps2, gS_ChatStrings.sText,gS_ChatStrings.sVariable,mapsleft,gS_ChatStrings.sText,(mapsleft > 1)? "maps":"map");
			if(maps2>mapsleft)
				Shavit_PrintToChatAll("Next map will be %s%s%s!",gS_ChatStrings.sWarning,nextmap, gS_ChatStrings.sText);
			else
				Shavit_PrintToChatAll("This is your last map from the  %sgauntlet%s!",gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		}
	}
	JoinTimer = null;
}

public Action Command_Split(int client, int args)
{
	if (client != 0)
	{
		if(Shavit_InsideZone(client, Zone_End, Track_Main))
		{
			SocketSend(gsocket, "split\r\n");
			SocketSend(gsocket, "pause\r\n");
			finishedmap = true;
			CreateTimer(1.0, Timer_ChangeMap);
		}
		else
			Shavit_PrintToChatAll("Please be inside the %sMain Endzone%s to use this command!",gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}
	return Plugin_Handled;
}

public Action Command_Stuck(int client, int args)
{
	if (client != 0)
	{
		if(Shavit_GetTimerStatus(client) != Timer_Running)
		{
			Shavit_PrintToChatAll("Your Timer has to run to use this command!");
			return Plugin_Handled;
		}

		if(!stuckcd)
		{
			float move[3];
			move[1] = 30.0;
			GetClientAbsOrigin(client, StuckPosition);
			TeleportEntity(client,NULL_VECTOR,NULL_VECTOR,move);
			StuckTimer[client] = CreateTimer(0.1, Timer_StuckTimer,client);
			stuckcd = true;
		}
		else
			Shavit_PrintToChatAll("This command is on cooldown!");
	}
	return Plugin_Handled;
}

public Action Timer_StuckTimer(Handle timer, int client)
{
	float pos[3];
	GetClientAbsOrigin(client, pos);
	if(pos[0] == StuckPosition[0] && pos[1] == StuckPosition[1] && pos[2] == StuckPosition[2])
	{
		TeleportEntity(client,ValidPosition,Anglesi,Speedi);
		Shavit_PrintToChatAll("Yay unstuck!");
	}
	else
	{
		Shavit_PrintToChatAll("You aren't even stuck!");
	}

	stuckcd = false;
	StuckTimer[client] = null;
}

public Action Command_MapList(int client, int args)
{
	if (client != 0)
	{
		if(strlen(maplistz)>450)
		{
			Shavit_PrintToChatAll("Check your console for the maplist!");
			PrintToConsole(client,"Maplist\n");
			PrintToConsole(client,"%s",maplistz);
			return Plugin_Handled;
		}
		else
		{
			Handle mapsmenu = CreatePanel();
			DrawPanelText(mapsmenu, "Maplist\n");
			DrawPanelText(mapsmenu, maplistz);
			DrawPanelItem(mapsmenu, "Exit");
			SetPanelKeys(mapsmenu, (1<<0));
			SendPanelToClient(mapsmenu, client, MapsMenuHandler, 60);
			CloseHandle(mapsmenu);
			return Plugin_Handled;
		}
	}  
	return Plugin_Handled;
}

public int MapsMenuHandler(Handle menu, MenuAction action,  int param1, int param2 ){}


public void getCallback(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data1) 
{
	if(!bRequestSuccessful) 
	{
		PrintToServer("There was an error in the request");
		CloseHandle(hRequest);
		return;
	}
	int bodysize;
	SteamWorks_GetHTTPResponseBodySize(hRequest, bodysize);

	char bodybuffer[2048];
	if(bodysize > 2048) 
	{
		CloseHandle(hRequest);
		return;
	}
	SteamWorks_GetHTTPResponseBodyData(hRequest, bodybuffer, bodysize);
	if(StrEqual(bodybuffer,"404: Not Found",false))
	{
		needzones = true;
		Shavit_PrintToChatAll("MapZones not found!");
		CloseHandle(hRequest);
		return;
	}
	else
	{
		char tempy[4][512];
		ExplodeString(bodybuffer, ";", tempy, sizeof(tempy), sizeof(tempy[]));
		for(int i = 0; i < 4; ++i)
			if(strlen(tempy[i])>3)
				SQL_FastQuery(gH_SQL, tempy[i]);

		CloseHandle(hRequest);
		if (StrEqual(firstmap, curmap))
		{
			Shavit_PrintToChatAll("MapZones imported!");
			MapTimer = CreateTimer(1.0, Timer_MapTimer);
		}
	}
} 

public Action Timer_MapTimer(Handle timer)
{
	if (StrEqual(firstmap, curmap))
	{
		ForceChangeLevel(curmap, "");
	}
	MapTimer = null;
}

public void SQL_Mapcheck_Callback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if(results == null)
	{
		LogError("Timer (zones) SQL query failed. Reason: %s", error);

		return;
	}

	pack.Reset();
	char map[128];
	pack.ReadString(map,128);
	delete pack;

	bool found_U = false;
	while(results.FetchRow())
	{
		found_U = true;
		int track = results.FetchInt(0);
		if(track!=0)
		{
			char sURL[312];
			gauntlet_mapurl.GetString(sURL,312);
			FormatEx(sURL, 312, "%s%s",sURL,map);
			Handle HTTPRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sURL);

			SteamWorks_SetHTTPCallbacks(HTTPRequest, getCallback);
			SteamWorks_SendHTTPRequest(HTTPRequest);

			SteamWorks_PrioritizeHTTPRequest(HTTPRequest);
		}
	}
	if(!found_U)
	{
		char sURL[312];
		gauntlet_mapurl.GetString(sURL,312);
		FormatEx(sURL, 312, "%s%s",sURL,map);
		Handle HTTPRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sURL);

		SteamWorks_SetHTTPCallbacks(HTTPRequest, getCallback);
		SteamWorks_SendHTTPRequest(HTTPRequest);

		SteamWorks_PrioritizeHTTPRequest(HTTPRequest);
	}
}
/*
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsFakeClient(client)) 
		return Plugin_Continue;

	if(Shavit_GetTimerStatus(client) != Timer_Running)
		return Plugin_Continue;

	if (cmdnum % 20 == 0)
	{
		float pos[3];
		GetClientAbsOrigin( client, pos );
		float prevspeed[3];
		GetEntPropVector( client, Prop_Data, "m_vecVelocity", prevspeed );
		if( !TR_PointOutsideWorld( pos ) && pos[0] != StuckPosition[0] && pos[1] != StuckPosition[1] && prevspeed[0] > 0.0 && prevspeed[1] > 0.0 && GetEntityMoveType(client) == MOVETYPE_WALK )
		{
			ValidPosition = pos;
			Speedi = prevspeed;
			Anglesi = angles;
		}
	}
	
	return Plugin_Continue;
}*/

void Event_Hop(Event event, const char[] name, bool xd) 
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	CreateTimer(0.1, Timer_Hop,client);
}

public Action Timer_Hop(Handle timer, int client)
{
	if(IsFakeClient(client)) 
		return Plugin_Stop;

	if(Shavit_GetTimerStatus(client) != Timer_Running)
		return Plugin_Stop;

	float pos[3];
	GetClientAbsOrigin( client, pos );
	float prevspeed[3];
	GetEntPropVector( client, Prop_Data, "m_vecVelocity", prevspeed );
	float angles[3];
	GetClientEyeAngles( client, angles );
	if( !TR_PointOutsideWorld( pos ) && pos[0] != StuckPosition[0] && pos[1] != StuckPosition[1] && prevspeed[0] > 0.0 && prevspeed[1] > 0.0 && GetEntityMoveType(client) == MOVETYPE_WALK )
	{
		ValidPosition = pos;
		Speedi = prevspeed;
		Anglesi = angles;
	}

	return Plugin_Handled;
}

//Mehis <3 
stock void Inf_FormatSeconds( float secs, char[] out, int len, const char[] secform = "%05.2f" )
{
    // "00:00.00"
    
#define _SECS2MINS(%0)  ( %0 * ( 1.0 / 60.0 ) )
    
    int mins = RoundToFloor( _SECS2MINS( secs ) );
    int printmins = mins;
    
    
    char format[16];
    
    
    char hrs[4]; // 00:
    hrs[0] = '\0';
    
    if ( mins >= 60 )
    {
        int h = RoundToFloor( _SECS2MINS( mins ) );
        
        FormatEx( hrs, sizeof( hrs ), "%02i:", h );
        
        printmins = mins - h * 60;
    }
    
    
    FormatEx( format, sizeof( format ), "%s%%02i:%s", hrs, secform ); // 00:%02i:%05.2f
    
    FormatEx( out, len, format,
        printmins,
        secs - mins * 60.0 );
}

public Action Command_SaveZones(int client, int args)
{
	if (client != 0)
	{
		char templist[6401];
		strcopy(templist,sizeof(templist),maplistz);

		int len = strlen(templist);
		if(!len)
		{
			Shavit_PrintToChatAll("You don't have a maplist.");
			return Plugin_Handled;
		}

		if(!gauntlet_custom.BoolValue)
		{
			char prefix[12];
			gauntlet_prefix.GetString(prefix,sizeof(prefix));
			Format(prefix, sizeof(prefix), "%s_",prefix);
			ReplaceString(templist, sizeof(templist), " prev ", prefix);
			ReplaceString(templist, sizeof(templist), "    current ", prefix);
			ReplaceString(templist, sizeof(templist), " next ", prefix);
		}

		char[][] tempy = new char[maps2][214];
		ExplodeString(templist, "\n", tempy, maps2, 214);
		int counter = 0; // same as maps2 
		for(int i = 0; i < maps2; i++)
		{
			char sQuery[512];
			FormatEx(sQuery, 512,"SELECT type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, destination_x, destination_y, destination_z, track, flags, data FROM mapzones WHERE map = '%s';", tempy[i]);
			DataPack pack = new DataPack();
			pack.WriteString( tempy[i] );

			gH_SQL.Query(SQL_SaveZones_Callback, sQuery, pack, DBPrio_High);
			counter++;
		}
		Shavit_PrintToChatAll("%s%d%s zones saved to cstrike/gauntlet/zonefiles.",gS_ChatStrings.sWarning, counter, gS_ChatStrings.sText);
	}  

	return Plugin_Handled;
}

public void SQL_SaveZones_Callback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	if(results == null)
	{
		LogError("Timer (get zones) SQL query failed. Reason: %s", error);

		return;
	}

	pack.Reset();
	char map[128];
	pack.ReadString(map,128);
	delete pack;

	int gI_MapZones = 0;
	float box[MAX_ZONES][2][3];
	float pos[MAX_ZONES][3];
	int type[MAX_ZONES] = 0;
	int track[MAX_ZONES] = 0;
	int flags[MAX_ZONES] = 0;
	int data[MAX_ZONES] = 0;
	while(results.FetchRow())
	{
		type[gI_MapZones] = results.FetchInt(0);
		box[gI_MapZones][0][0] = results.FetchFloat(1);
		box[gI_MapZones][0][1] = results.FetchFloat(2);
		box[gI_MapZones][0][2] = results.FetchFloat(3);
		box[gI_MapZones][1][0] = results.FetchFloat(4);
		box[gI_MapZones][1][1] = results.FetchFloat(5);
		box[gI_MapZones][1][2] = results.FetchFloat(6);
		pos[gI_MapZones][0] = results.FetchFloat(7);
		pos[gI_MapZones][1] = results.FetchFloat(8);
		pos[gI_MapZones][2] = results.FetchFloat(9);
		track[gI_MapZones] = results.FetchInt(10);
		flags[gI_MapZones] = results.FetchInt(11);
		data[gI_MapZones] = results.FetchInt(12);
		gI_MapZones++;
	}
	char sBuffer[512];
	char pathzones[PLATFORM_MAX_PATH];
	FormatEx(pathzones, sizeof(pathzones), "gauntlet/zonefiles/%s.txt",map);
	File fileHandle = OpenFile(pathzones, "w");
	for(int i = 0; i < gI_MapZones; ++i)
	{
		FormatEx(sBuffer, 512,
			"INSERT INTO 'mapzones' ('map', 'type', 'corner1_x', 'corner1_y', 'corner1_z', 'corner2_x', 'corner2_y', 'corner2_z', 'destination_x', 'destination_y', 'destination_z', 'track', 'flags', 'data') VALUES ('%s', %d, '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', %d, %d, %d);",
			map, type[i], box[i][0][0], box[i][0][1], box[i][0][2], box[i][1][0], box[i][1][1], box[i][1][2],  pos[i][0], pos[i][1], pos[i][2], track[i], flags[i], data[i]);
		WriteFileLine(fileHandle,"%s",sBuffer);
	}
	CloseHandle(fileHandle);
	
}
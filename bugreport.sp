#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <bugreport>

#pragma semicolon 1
#pragma newdecls required

Handle g_hOnBugReportPostForward;

ArrayList g_hBugReportReasons;
ArrayList g_hReportedReasons;

char g_sBugInfo[MAXPLAYERS+1][REASON_MAX_LENGTH];
bool g_bAwaitingReason[MAXPLAYERS+1];

char g_sReasonConfigFile[PLATFORM_MAX_PATH];

Handle g_CooldownCookie;
int g_iCooldown[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "Bug Report",
	author = "Cruze",
	description = "Players can report bugs.",
	version = "1.0",
	url = "http://www.steamcommunity.com/profiles/76561198132924835"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("bugreport");
	return APLRes_Success;
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_bug", Command_BugReport);
	RegConsoleCmd("sm_bugreport", Command_BugReport);
	
	RegConsoleCmd("sm_bugreport_reload", Command_Reload);

	g_hBugReportReasons = new ArrayList(ByteCountToCells(REASON_MAX_LENGTH));
	g_hReportedReasons = new ArrayList(ByteCountToCells(REASON_MAX_LENGTH));
	
	BuildPath(Path_SM, g_sReasonConfigFile, sizeof(g_sReasonConfigFile), "configs/bugreport_reasons.cfg");
	
	if(!FileExists(g_sReasonConfigFile))
	{
		CreateReasonList();
	}

	ParseReasonList();

	g_hOnBugReportPostForward = CreateGlobalForward("BugReport_OnReportPost", ET_Ignore, Param_Cell, Param_String, Param_String, Param_Cell);

	g_CooldownCookie = RegClientCookie("BugReport_Cooldown", "Client Cooldown for Bug Reports", CookieAccess_Private);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(AreClientCookiesCached(i))
		{
			OnClientCookiesCached(i);
		}
	}
	
	LoadTranslations("bugreport.phrases");
}

void CreateReasonList()
{
	File hFile;
	hFile = OpenFile(g_sReasonConfigFile, "w");

	if(hFile == null)
	{
		SetFailState("Failed to open configfile 'bugreport_reasons.cfg' for writing");
	}

	hFile.WriteLine("// List of reasons seperated by a new line, max %d in length", REASON_MAX_LENGTH);
	hFile.WriteLine("Server lag");
	hFile.WriteLine("Found an Exploit");
	hFile.WriteLine("No start/end zone");
	hFile.WriteLine("There should be a bonus here");
	hFile.WriteLine("Stuck, can't move");
	hFile.WriteLine("Error box");

	hFile.Close();
}

void ParseReasonList()
{
	File hFile;

	hFile = OpenFile(g_sReasonConfigFile, "r");

	if(hFile == null)
	{
		SetFailState("Failed to open configfile 'bugreport_reasons.cfg' for reading");
	}

	char sReadBuffer[PLATFORM_MAX_PATH];

	int len;
	while(!hFile.EndOfFile() && hFile.ReadLine(sReadBuffer, sizeof(sReadBuffer)))
	{
		if (sReadBuffer[0] == '/' || IsCharSpace(sReadBuffer[0]))
		{
			continue;
		}

		ReplaceString(sReadBuffer, sizeof(sReadBuffer), "\n", "");
		ReplaceString(sReadBuffer, sizeof(sReadBuffer), "\r", "");
		ReplaceString(sReadBuffer, sizeof(sReadBuffer), "\t", "");

		len = strlen(sReadBuffer);

		if (len < 3 || len > REASON_MAX_LENGTH)
		{
			continue;
		}

		if (g_hBugReportReasons.FindString(sReadBuffer) == -1)
		{
			g_hBugReportReasons.PushString(sReadBuffer);
		}
	}

	hFile.Close();
}

public void OnMapStart()
{
	g_hReportedReasons.Clear();
}

public void OnClientPutInServer(int client)
{
	g_sBugInfo[client][0] = '\0';
	g_bAwaitingReason[client] = false;
}

public void OnClientDisconnect(int client)
{
	if(g_iCooldown[client])
	{
		char value[16];
		IntToString(g_iCooldown[client], value, sizeof(value));
		SetClientCookie(client, g_CooldownCookie, value);
	}
	else
	{
		SetClientCookie(client, g_CooldownCookie, "");
	}
}

public void OnClientCookiesCached(int client)
{
	g_iCooldown[client] = 0;

	char sValue[16];
	GetClientCookie(client, g_CooldownCookie, sValue, sizeof(sValue));

	if(sValue[0] == '\0')
	{
		return;
	}
	g_iCooldown[client] = StringToInt(sValue);
	SetClientCookie(client, g_CooldownCookie, "");
}

public Action Command_Reload(int client, int argc)
{
	if(!CheckCommandAccess(client, "sm_bugreport_admin", ADMFLAG_BAN, false))
	{
		ReplyToCommand(client, "[SM] %T", "BugReport_NoAdmin", client);
		return Plugin_Handled;
	}

	g_hBugReportReasons.Clear();
	g_hReportedReasons.Clear();
	ParseReasonList();
	ReplyToCommand(client, "[SM] %T", "BugReport_Reloaded", client);
	return Plugin_Handled;
}

public Action Command_BugReport(int client, int args)
{
	if(!client)
	{
		return Plugin_Handled;
	}
	if(g_iCooldown[client] > GetTime())
	{
		PrintToChat(client, "[SM] %T", "BugReport_Cooldown", client, g_iCooldown[client]-GetTime());
		return Plugin_Handled;
	}
	ShowReasonsMenu(client);
	return Plugin_Handled;
}

void ShowReasonsMenu(int client)
{
	int count;
	char sReasonBuffer[REASON_MAX_LENGTH];
	count = g_hBugReportReasons.Length;

	Menu menu = new Menu(MenuHandler_BugReason);
	menu.SetTitle("%T", "BugReport_SelectBug", client);

	for(int i; i < count; i++)
	{
		g_hBugReportReasons.GetString(i, sReasonBuffer, sizeof(sReasonBuffer));

		if(strlen(sReasonBuffer) < 3)
		{
			continue;
		}

		menu.AddItem(sReasonBuffer, sReasonBuffer);
	}
	Format(sReasonBuffer, sizeof(sReasonBuffer), "%T", "BugReport_DescribeBug", client);
	menu.AddItem("Own reason", sReasonBuffer);

	menu.Display(client, 30);
}

public int MenuHandler_BugReason(Menu menu, MenuAction action, int client, int item)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			char sInfo[REASON_MAX_LENGTH];
			menu.GetItem(item, sInfo, sizeof(sInfo));

			if(StrEqual("Own reason", sInfo))
			{
				g_bAwaitingReason[client] = true;
				PrintToChat(client, "[SM] %T", "BugReport_TypeOwnReason", client);
				return;
			}
			strcopy(g_sBugInfo[client], sizeof(g_sBugInfo[]), sInfo);
			ConfirmationMenu(client);
		}
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(!client || client > MaxClients)
	{
		return Plugin_Continue;
	}
	if(IsChatTrigger())
	{
		return Plugin_Continue;
	}
	if(!g_bAwaitingReason[client])
	{
		return Plugin_Continue;
	}
	g_bAwaitingReason[client] = false;
	if(StrEqual(sArgs, "!noreason") || StrEqual(sArgs, "!abort"))
	{
		PrintToChat(client, "[SM] %T", "BugReport_CallAborted", client);
		return Plugin_Handled;
	}
	if(strlen(sArgs) < 3)
	{
		g_bAwaitingReason[client] = true;
		PrintToChat(client, "[SM] %T", "BugReport_OwnReasonTooShort", client);
		return Plugin_Handled;
	}
	strcopy(g_sBugInfo[client], sizeof(g_sBugInfo[]), sArgs);
	ConfirmationMenu(client);
	return Plugin_Handled;
}


void ConfirmationMenu(int client)
{
	Menu menu = new Menu(Handler_Confirm);
	menu.SetTitle("%T", "BugReport_ConfirmCall", client);
	char buffer[64];
	Format(buffer, sizeof(buffer), "%T", "BugReport_Yes", client);
	menu.AddItem("", buffer);
	Format(buffer, sizeof(buffer), "%T", "BugReport_No", client);
	menu.AddItem("", buffer);
	menu.ExitButton = false;
	menu.Display(client, 30);
}

public int Handler_Confirm(Menu menu, MenuAction action, int client, int item)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			if(item == 0)
			{
				char map[64], displaynamemap[64];
				GetCurrentMap(map, sizeof(map));
				GetMapDisplayName(map, displaynamemap, sizeof(displaynamemap));
				Forward_OnBugReportPost(client, displaynamemap, g_sBugInfo[client], g_hReportedReasons);
				g_hReportedReasons.PushString(g_sBugInfo[client]);
				PrintToChat(client, "[SM] %T", "BugReport_Successful", client);
				if(!CheckCommandAccess(client, "", ADMFLAG_ROOT))
				{
					g_iCooldown[client] = GetTime()+COOLDOWN;
				}
				for(int i = 1; i <= MaxClients; i++)
				{
					if(!IsClientInGame(i))
						continue;
					if(!CheckCommandAccess(i, "sm_bugreport_admin", ADMFLAG_BAN, false))
						continue;
					PrintToChat(i, "[SM] %T", "BugReport_NotifyAdmins", i, client, g_sBugInfo[client]);
				}


			}
			g_sBugInfo[client][0] = '\0';
		}
	}
}

void Forward_OnBugReportPost(int client, const char[] map, const char[] reason, ArrayList array)
{
	Call_StartForward(g_hOnBugReportPostForward);
	Call_PushCell(client);
	Call_PushString(map);
	Call_PushString(reason);
	Call_PushCell(array);

	Call_Finish();
}
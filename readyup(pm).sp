/*
	SourcePawn is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	SourceMod is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	Pawn and SMALL are Copyright (C) 1997-2008 ITB CompuPhase.
	Source is Copyright (C) Valve Corporation.
	All trademarks are property of their respective owners.

	This program is free software: you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the
	Free Software Foundation, either version 3 of the License, or (at your
	option) any later version.

	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <left4downtown>
#include <l4d2_direct>
#include <builtinvotes>
#include <colors>

#define MAX_FOOTERS 10
#define MAX_FOOTER_LEN 65
#define MAX_SOUNDS 5

#define SOUND "/level/gnomeftw.wav"

#define DEBUG 0

public Plugin:myinfo =
{
	name = "L4D2 Ready-Up",
	author = "CanadaRox, (Lazy unoptimized additions by Sir), devilesk",
	description = "New and improved ready-up plugin.",
	version = "9.2.1",
	url = "https://github.com/devilesk/rl4d2l-plugins"
};

enum L4D2Team
{
	L4D2Team_None = 0,
	L4D2Team_Spectator,
	L4D2Team_Survivor,
	L4D2Team_Infected
}

// Plugin Cvars
new Handle:l4d_ready_disable_spawns;
new Handle:l4d_ready_cfg_name;
new Handle:l4d_ready_survivor_freeze;
new Handle:l4d_ready_max_players;
new Handle:l4d_ready_enable_sound;
new Handle:l4d_ready_delay;
new Handle:l4d_ready_chuckle;
new Handle:l4d_ready_live_sound;
new Handle:g_hVote;

// Game Cvars
new Float:g_fButtonTime[66];
new Handle:director_no_specials;
new Handle:god;
new Handle:sb_stop;
new Handle:survivor_limit;
new Handle:z_max_player_zombies;
new Handle:sv_infinite_primary_ammo;
new Handle:ServerNamer;

new Handle:casterTrie;
new Handle:liveForward;
new Handle:menuPanel;
new Handle:readyCountdownTimer;
new String:readyFooter[MAX_FOOTERS][MAX_FOOTER_LEN];
new bool:hiddenPanel[MAXPLAYERS + 1];
new bool:hiddenManually[MAXPLAYERS + 1];
new bool:inLiveCountdown = false;
new bool:inReadyUp;
new bool:isPlayerReady[MAXPLAYERS + 1];
new footerCounter = 0;
new readyDelay;
new Handle:allowedCastersTrie;
new String:liveSound[256];
new bool:bSkipWarp;
new bool:bFrozenYet;
new bool:blockSecretSpam[MAXPLAYERS + 1];
new iCmd;
new String:sCmd[32];

// Laser Tag
new bool:laser_enable;
new Handle:l4d_laser_life;
new Handle:l4d_laser_width;
new Handle:l4d_laser_offset;
new laser_color[4];
new g_Sprite;
new laser_bullet[MAXPLAYERS+1];
new Float:g_LaserOffset;
new Float:g_LaserWidth;
new Float:g_LaserLife;

// Timer
new bootTime;

new String:countdownSound[MAX_SOUNDS][]=
{
	"/npc/moustachio/strengthattract01.wav",
	"/npc/moustachio/strengthattract02.wav",
	"/npc/moustachio/strengthattract05.wav",
	"/npc/moustachio/strengthattract06.wav",
	"/npc/moustachio/strengthattract09.wav"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("AddStringToReadyFooter", Native_AddStringToReadyFooter);
	CreateNative("IsInReady", Native_IsInReady);
	CreateNative("IsClientCaster", Native_IsClientCaster);
	CreateNative("IsIDCaster", Native_IsIDCaster);
	liveForward = CreateGlobalForward("OnRoundIsLive", ET_Event);
	RegPluginLibrary("readyup");
	return APLRes_Success;
}

public OnPluginStart()
{
	CreateConVar("l4d_ready_enabled", "1", "This cvar doesn't do anything, but if it is 0 the logger wont log this game.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	l4d_ready_cfg_name = CreateConVar("l4d_ready_cfg_name", "", "Configname to display on the ready-up panel", FCVAR_PLUGIN|FCVAR_PRINTABLEONLY);
	l4d_ready_disable_spawns = CreateConVar("l4d_ready_disable_spawns", "0", "Prevent SI from having spawns during ready-up", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	l4d_ready_survivor_freeze = CreateConVar("l4d_ready_survivor_freeze", "1", "Freeze the survivors during ready-up.  When unfrozen they are unable to leave the saferoom but can move freely inside", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	l4d_ready_max_players = CreateConVar("l4d_ready_max_players", "12", "Maximum number of players to show on the ready-up panel.", FCVAR_PLUGIN, true, 0.0, true, MAXPLAYERS+1.0);
	l4d_ready_delay = CreateConVar("l4d_ready_delay", "3", "Number of seconds to count down before the round goes live.", FCVAR_PLUGIN, true, 0.0);
	l4d_ready_enable_sound = CreateConVar("l4d_ready_enable_sound", "1", "Enable sound during countdown & on live");
	l4d_ready_chuckle = CreateConVar("l4d_ready_chuckle", "1", "Enable chuckle during countdown");
	l4d_ready_live_sound = CreateConVar("l4d_ready_live_sound", "ui/bigreward.wav", "The sound that plays when a round goes live");

	//Laser Tag
	l4d_laser_life = CreateConVar("l4d_ready_laser_life", "1.5", "Seconds Laser will remain", FCVAR_PLUGIN, true, 0.1);
	l4d_laser_width = CreateConVar("l4d_ready_laser_width", "1.0", "Width of Laser", FCVAR_PLUGIN, true, 1.0);
	l4d_laser_offset = CreateConVar("l4d_ready_laser_offset", "36", "Lasertag Offset", FCVAR_PLUGIN);
	HookConVarChange(l4d_ready_survivor_freeze, SurvFreezeChange);

	HookEvent("bullet_impact", Event_BulletImpact);
	HookEvent("round_start", RoundStart_Event);
	HookEvent("player_team", PlayerTeam_Event);

	casterTrie = CreateTrie();
	allowedCastersTrie = CreateTrie();

	director_no_specials = FindConVar("director_no_specials");
	god = FindConVar("god");
	sb_stop = FindConVar("sb_stop");
	survivor_limit = FindConVar("survivor_limit");
	z_max_player_zombies = FindConVar("z_max_player_zombies");
	sv_infinite_primary_ammo = FindConVar("sv_infinite_primary_ammo");
	ServerNamer = FindConVar("sn_main_name");

	RegAdminCmd("sm_caster", Caster_Cmd, ADMFLAG_BAN, "Registers a player as a caster so the round will not go live unless they are ready");
	RegAdminCmd("sm_forcestart", ForceStart_Cmd, ADMFLAG_BAN, "Forces the round to start regardless of player ready status.  Players can unready to stop a force");
	RegAdminCmd("sm_fs", ForceStart_Cmd, ADMFLAG_BAN, "Forces the round to start regardless of player ready status.  Players can unready to stop a force");
	RegConsoleCmd("\x73\x6d\x5f\x62\x6f\x6e\x65\x73\x61\x77", Secret_Cmd, "Every player has a different secret number between 0-1023");
	RegConsoleCmd("sm_hide", Hide_Cmd, "Hides the ready-up panel so other menus can be seen");
	RegConsoleCmd("sm_show", Show_Cmd, "Shows a hidden ready-up panel");
	AddCommandListener(Say_Callback, "say");
	AddCommandListener(Say_Callback, "say_team");
	RegConsoleCmd("sm_notcasting", NotCasting_Cmd, "Deregister yourself as a caster or allow admins to deregister other players");
	RegConsoleCmd("sm_uncast", NotCasting_Cmd, "Deregister yourself as a caster or allow admins to deregister other players");
	RegConsoleCmd("sm_ready", Ready_Cmd, "Mark yourself as ready for the round to go live");
	RegConsoleCmd("sm_r", Ready_Cmd, "Mark yourself as ready for the round to go live");
	RegConsoleCmd("sm_toggleready", ToggleReady_Cmd, "Toggle your ready status");
	RegConsoleCmd("sm_unready", Unready_Cmd, "Mark yourself as not ready if you have set yourself as ready");
	RegConsoleCmd("sm_nr", Unready_Cmd, "Mark yourself as not ready if you have set yourself as ready");
	RegConsoleCmd("sm_return", Return_Cmd, "Return to a valid saferoom spawn if you get stuck during an unfrozen ready-up period");
	RegConsoleCmd("sm_cast", Cast_Cmd, "Registers the calling player as a caster so the round will not go live unless they are ready");
	RegConsoleCmd("sm_kickspecs", KickSpecs_Cmd, "Let's vote to kick those Spectators!", 0);
	RegServerCmd("sm_resetcasters", ResetCaster_Cmd, "Used to reset casters between matches.  This should be in confogl_off.cfg or equivalent for your system");
	RegServerCmd("sm_add_caster_id", AddCasterSteamID_Cmd, "Used for adding casters to the whitelist -- i.e. who's allowed to self-register as a caster");

#if DEBUG
	RegAdminCmd("sm_initready", InitReady_Cmd, ADMFLAG_ROOT);
	RegAdminCmd("sm_initlive", InitLive_Cmd, ADMFLAG_ROOT);
#endif

	LoadTranslations("common.phrases");

	HookConVarChange(l4d_laser_life, LaserTag);
	HookConVarChange(l4d_laser_width, LaserTag);
	HookConVarChange(l4d_laser_offset, LaserTag);

	bootTime = GetTime();
}

public LaserTag(Handle:convar, const String:oldValue[], const String:newValue[])
{
	OnConfigsExecuted();
}

public Action:Say_Callback(client, String:command[], argc)
{
	SetEngineTime(client);
	return Plugin_Continue;
}

public OnPluginEnd()
{
	if (inReadyUp)
		InitiateLive(false);
}

public OnMapStart()
{
	GetConVarString(l4d_ready_live_sound, liveSound, 256);
	/* OnMapEnd needs this to work */
	PrecacheSound(SOUND);
	PrecacheSound("buttons/blip1.wav");
	PrecacheSound("buttons/blip2.wav");
	PrecacheSound("quake/prepare.mp3", false);
	PrecacheSound(liveSound, false);

	// Laser Tag
	g_Sprite = PrecacheModel("materials/sprites/laserbeam.vmt");

	if (GetConVarBool(l4d_ready_chuckle))
	{
		for (new i = 0; i < MAX_SOUNDS; i++)
		{
			PrecacheSound(countdownSound[i]);
		}
	}
	for (new client = 1; client <= MAXPLAYERS; client++)
	{
		blockSecretSpam[client] = false;
	}
	readyCountdownTimer = INVALID_HANDLE;
	
	new String:sMap[64];
	GetCurrentMap(sMap, 64);
	if (StrEqual(sMap, "dprm1_milltown_a", false))
	{
		bSkipWarp = true;
	}
	else
	{
		bSkipWarp = false;
	}
}

public Action:KickSpecs_Cmd(client, args)
{
	if (IsClientInGame(client) && GetClientTeam(client) != 1)
	{
		if (IsNewBuiltinVoteAllowed())
		{
			new iNumPlayers;
			decl iPlayers[MaxClients];
			for (new i = 1; i <= MaxClients; i++)
			{
				if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) == 1)
					continue;
				iNumPlayers++;
				iPlayers[iNumPlayers] = i;
			}
			new String:sBuffer[64];
			g_hVote = CreateBuiltinVote(VoteActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
			Format(sBuffer, 64, "Kick Non-Admin & Non-Casting Spectators?");
			SetBuiltinVoteArgument(g_hVote, sBuffer);
			SetBuiltinVoteInitiator(g_hVote, client);
			SetBuiltinVoteResultCallback(g_hVote, SpecVoteResultHandler);
			DisplayBuiltinVote(g_hVote, iPlayers, iNumPlayers, 20);
			return Plugin_Continue;
		}
		PrintToChat(client, "Vote cannot be started now.");
	}
	return Plugin_Continue;
}

public VoteActionHandler(Handle:vote, BuiltinVoteAction:action, param1, param2)
{
	switch (action) {
		case BuiltinVoteAction_End: {
			g_hVote = INVALID_HANDLE;
			CloseHandle(vote);
		}
		case BuiltinVoteAction_Cancel: {
			DisplayBuiltinVoteFail(vote, BuiltinVoteFailReason:param1);
		}
	}
}

public SpecVoteResultHandler(Handle:vote, num_votes, num_clients, client_info[][2], num_items, item_info[][2])
{
	for (new i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
				DisplayBuiltinVotePass(vote, "Ciao Spectators!");
				for (new c = 1; c <= MaxClients; c++)
				{
					if (IsClientInGame(c) && GetClientTeam(c) == 1 && !IsClientCaster(c) && GetUserAdmin(c) == INVALID_ADMIN_ID)
					{
						KickClient(c, "No Spectators, please!");
					}
				}
				return;
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public Action:Secret_Cmd(client, args)
{
	if (inReadyUp)
	{
		decl String:steamid[64];
		decl String:argbuf[30];
		GetCmdArg(1, argbuf, sizeof(argbuf));
		new arg = StringToInt(argbuf);
		GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		new id = StringToInt(steamid[10]);

		if ((id & 1023) ^ arg == 'C'+'a'+'n'+'a'+'d'+'a'+'R'+'o'+'x')
		{
			DoSecrets(client);
			isPlayerReady[client] = true;
			if (CheckFullReady())
				InitiateLiveCountdown();

			return Plugin_Handled;
		}
		
	}
	return Plugin_Continue;
}

stock DoSecrets(client)
{
	PrintCenterTextAll("\x42\x4f\x4e\x45\x53\x41\x57\x20\x49\x53\x20\x52\x45\x41\x44\x59\x21");
	if (L4D2Team:GetClientTeam(client) == L4D2Team_Survivor && !blockSecretSpam[client])
	{
		new particle = CreateEntityByName("info_particle_system");
		decl Float:pos[3];
		GetClientAbsOrigin(client, pos);
		pos[2] += 50;
		TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
		DispatchKeyValue(particle, "effect_name", "achieved");
		DispatchKeyValue(particle, "targetname", "particle");
		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
		CreateTimer(10.0, killParticle, particle, TIMER_FLAG_NO_MAPCHANGE);
		EmitSoundToAll(SOUND, client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
		CreateTimer(2.0, SecretSpamDelay, client);
		blockSecretSpam[client] = true;
	}
}

public Action:SecretSpamDelay(Handle:timer, any:client)
{
	blockSecretSpam[client] = false;
}

public Action:killParticle(Handle:timer, any:entity)
{
	if (entity > 0 && IsValidEntity(entity) && IsValidEdict(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}
}

/* This ensures all cvars are reset if the map is changed during ready-up */
public OnMapEnd()
{
	if (inReadyUp)
		InitiateLive(false);
}

public OnClientDisconnect(client)
{
	hiddenPanel[client] = false;
	hiddenManually[client] = false;
	isPlayerReady[client] = false;
	g_fButtonTime[client] = 0.0;
}

SetEngineTime(client)
{
	g_fButtonTime[client] = GetEngineTime();
}

public Native_AddStringToReadyFooter(Handle:plugin, numParams)
{
	decl String:footer[MAX_FOOTER_LEN];
	GetNativeString(1, footer, sizeof(footer));
	if (footerCounter < MAX_FOOTERS)
	{
		if (strlen(footer) < MAX_FOOTER_LEN)
		{
			strcopy(readyFooter[footerCounter], MAX_FOOTER_LEN, footer);
			footerCounter++;
			return _:true;
		}
	}
	return _:false;
}

public Native_IsInReady(Handle:plugin, numParams)
{
	return _:inReadyUp;
}

public Native_IsClientCaster(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	return _:IsClientCaster(client);
}

public Native_IsIDCaster(Handle:plugin, numParams)
{
	decl String:buffer[64];
	GetNativeString(1, buffer, sizeof(buffer));
	return _:IsIDCaster(buffer);
}

stock bool:IsClientCaster(client)
{
	decl String:buffer[64];
	return GetClientAuthId(client, AuthId_Steam2, buffer, sizeof(buffer)) && IsIDCaster(buffer);
}

stock bool:IsIDCaster(const String:AuthID[])
{
	decl dummy;
	return GetTrieValue(casterTrie, AuthID, dummy);
}

public Action:Cast_Cmd(client, args)
{	
	decl String:buffer[64];
	GetClientAuthId(client, AuthId_Steam2, buffer, sizeof(buffer));
	if (GetClientTeam(client) != 1)
	{
		ChangeClientTeam(client, 1);
	}
	SetTrieValue(casterTrie, buffer, 1);
	CPrintToChat(client, "{blue}[{default}Cast{blue}] {default}You have registered yourself as a caster");
	CPrintToChat(client, "{blue}[{default}Cast{blue}] {default}Reconnect to make your Addons work.");
	return Plugin_Handled;
}

public Action:Caster_Cmd(client, args)
{	
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_caster <player>");
		return Plugin_Handled;
	}
	
    	decl String:buffer[64];
	GetCmdArg(1, buffer, sizeof(buffer));
	
	new target = FindTarget(client, buffer, true, false);
	if (target > 0) // If FindTarget fails we don't need to print anything as it prints it for us!
	{
		if (GetClientAuthId(target, AuthId_Steam2, buffer, sizeof(buffer)))
		{
			SetTrieValue(casterTrie, buffer, 1);
			ReplyToCommand(client, "Registered %N as a caster", target);
			CPrintToChat(client, "{blue}[{olive}!{blue}] {default}An Admin has registered you as a caster");
		}
		else
		{
		    	ReplyToCommand(client, "Couldn't find Steam ID.  Check for typos and let the player get fully connected.");
		}
	}
	return Plugin_Handled;
}

public Action:ResetCaster_Cmd(args)
{
	ClearTrie(casterTrie);
	return Plugin_Handled;
}

public Action:AddCasterSteamID_Cmd(args)
{
	decl String:buffer[128];
	GetCmdArgString(buffer, sizeof(buffer));
	if (buffer[0] != EOS) 
	{
		new index;
		GetTrieValue(allowedCastersTrie, buffer, index);
		if (index != 1)
		{
			SetTrieValue(allowedCastersTrie, buffer, 1);
			PrintToServer("[casters_database] Added '%s'", buffer);
		}
		else PrintToServer("[casters_database] '%s' already exists", buffer);
	}
	else PrintToServer("[casters_database] No args specified / empty buffer");
	return Plugin_Handled;
}

public Action:Hide_Cmd(client, args)
{
	hiddenPanel[client] = true;
	hiddenManually[client] = true;
	return Plugin_Handled;
}

public Action:Show_Cmd(client, args)
{
	hiddenPanel[client] = false;
	hiddenManually[client] = false;
	return Plugin_Handled;
}

public Action:NotCasting_Cmd(client, args)
{
	decl String:buffer[64];
	
	if (args < 1) // If no target is specified
	{
		GetClientAuthId(client, AuthId_Steam2, buffer, sizeof(buffer));
		RemoveFromTrie(casterTrie, buffer);
		CPrintToChat(client, "{blue}[{default}Reconnect{blue}] {default}You will be reconnected to the server..");
		CPrintToChat(client, "{blue}[{default}Reconnect{blue}] {default}There's a black screen instead of a loading bar!");
		CreateTimer(3.0, Reconnect, client);
		return Plugin_Handled;
	}
	else // If a target is specified
	{
		new AdminId:id;
		id = GetUserAdmin(client);
		new bool:hasFlag = false;
		
		if (id != INVALID_ADMIN_ID)
		{
			hasFlag = GetAdminFlag(id, Admin_Ban); // Check for specific admin flag
		}
		
		if (!hasFlag)
		{
			ReplyToCommand(client, "Only admins can remove other casters. Use sm_notcasting without arguments if you wish to remove yourself.");
			return Plugin_Handled;
		}
		
		GetCmdArg(1, buffer, sizeof(buffer));
		
		new target = FindTarget(client, buffer, true, false);
		if (target > 0) // If FindTarget fails we don't need to print anything as it prints it for us!
		{
			if (GetClientAuthId(target, AuthId_Steam2, buffer, sizeof(buffer)))
			{
				RemoveFromTrie(casterTrie, buffer);
				ReplyToCommand(client, "%N is no longer a caster", target);
			}
			else
			{
				ReplyToCommand(client, "Couldn't find Steam ID.  Check for typos and let the player get fully connected.");
			}
		}
		return Plugin_Handled;
	}
}

public Action:Reconnect(Handle:timer, client)
{
	if (IsClientConnected(client) && IsClientInGame(client))
		ReconnectClient(client);
}

public Action:ForceStart_Cmd(client, args)
{
	if (inReadyUp)
	{
		InitiateLiveCountdown();
	}
	return Plugin_Handled;
}

public Action:Ready_Cmd(client, args)
{
	if (inReadyUp)
	{
		isPlayerReady[client] = true;
		if (CheckFullReady())
			InitiateLiveCountdown();
	}

	return Plugin_Handled;
}

public Action:Unready_Cmd(client, args)
{
	if (inReadyUp)
	{
		SetEngineTime(client);
		isPlayerReady[client] = false;
		CancelFullReady();
	}

	return Plugin_Handled;
}

public Action:ToggleReady_Cmd(client, args)
{
	if (inReadyUp)
	{
		if (!isPlayerReady[client])
		{
			isPlayerReady[client] = true;
			if (CheckFullReady())
			{
				InitiateLiveCountdown();
			}
		}
		else{
			SetEngineTime(client);
			isPlayerReady[client] = false;
			CancelFullReady();
		}
	}

	return Plugin_Handled;
}

/* No need to do any other checks since it seems like this is required no matter what since the intros unfreezes players after the animation completes */
public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if (inReadyUp)
	{
		if (buttons && !IsFakeClient(client))
		{
			SetEngineTime(client);
		}
		if (IsClientInGame(client) && L4D2Team:GetClientTeam(client) == L4D2Team_Survivor)
		{
			if (GetConVarBool(l4d_ready_survivor_freeze))
			{
				if (!(GetEntityMoveType(client) == MOVETYPE_NONE || GetEntityMoveType(client) == MOVETYPE_NOCLIP))
				{
					SetClientFrozen(client, true);
				}
			}
			else
			{
				if (GetEntityFlags(client) & FL_INWATER)
				{
					ReturnPlayerToSaferoom(client, false);
				}
			}
			if (bSkipWarp && !bFrozenYet)
			{
				SetTeamFrozen(L4D2Team:L4D2Team_Survivor, true);
				bFrozenYet = true;
			}
		}
	}
}

public SurvFreezeChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	ReturnTeamToSaferoom(L4D2Team_Survivor);
	if (bSkipWarp)
	{
		SetTeamFrozen(L4D2Team:L4D2Team_Survivor, true);
	}
	else
	{
		SetTeamFrozen(L4D2Team:L4D2Team_Survivor, GetConVarBool(convar));
	}
}

public Action:L4D_OnFirstSurvivorLeftSafeArea(client)
{
	if (inReadyUp)
	{
		if (bSkipWarp)
		{
			return Plugin_Handled;
		}
		ReturnPlayerToSaferoom(client, false);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action:Return_Cmd(client, args)
{
	if (client > 0
			&& inReadyUp
			&& L4D2Team:GetClientTeam(client) == L4D2Team_Survivor)
	{
		ReturnPlayerToSaferoom(client, false);
	}
	return Plugin_Handled;
}

public RoundStart_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	InitiateReadyUp();
	bFrozenYet = false;
}

public PlayerTeam_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	SetEngineTime(client);
	new L4D2Team:oldteam = L4D2Team:GetEventInt(event, "oldteam");
	new L4D2Team:team = L4D2Team:GetEventInt(event, "team");
	if ((oldteam == L4D2Team_Survivor || oldteam == L4D2Team_Infected ||
			team == L4D2Team_Survivor || team == L4D2Team_Infected) && isPlayerReady[client])
	{
		CancelFullReady();
	}
}

#if DEBUG
public Action:InitReady_Cmd(client, args)
{
	InitiateReadyUp();
	return Plugin_Handled;
}

public Action:InitLive_Cmd(client, args)
{
	InitiateLive();
	return Plugin_Handled;
}
#endif

public DummyHandler(Handle:menu, MenuAction:action, param1, param2) { }

public Action:MenuRefresh_Timer(Handle:timer)
{
	if (inReadyUp)
	{
		UpdatePanel();
		return Plugin_Continue;
	}
	return Plugin_Stop;
}

public Action:MenuCmd_Timer(Handle:timer)
{
	if (inReadyUp)
	{
		iCmd++;
		return Plugin_Continue;
	}
	return Plugin_Stop;
}

UpdatePanel()
{
	if (IsBuiltinVoteInProgress())
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i) && IsClientInBuiltinVotePool(i))
			{
				hiddenPanel[i] = true;
			}
		}
	}
	else
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i))
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !hiddenManually[i])
				{
					hiddenPanel[i] = false;
				}
			}
		}
	}
	
	if (menuPanel != INVALID_HANDLE)
	{
		CloseHandle(menuPanel);
		menuPanel = INVALID_HANDLE;
	}

	new String:survivorBuffer[800] = "";
	new String:infectedBuffer[800] = "";
	new String:casterBuffer[500];
	new String:specBuffer[500];
	new casterCount;
	new playerCount = 0;
	new specCount = 0;

	//Timer
	//Thanks Dr. McKay
	new diff = GetTime() - bootTime;
	new hours = diff / 3600;
	diff %= 3600;
	new mins = diff / 60;
	diff %= 60;
	new secs = diff;
	new String:stringTimer[32];
	if (hours > 0)
	{
		Format(stringTimer, 32, "%02d:%02d:%02d", hours, mins, secs);
	} else {
		Format(stringTimer, 32, "%02d:%02d", mins, secs);
	}

	menuPanel = CreatePanel();
	
	new String:ServerBuffer[128];
	new String:ServerName[32];
	new String:cfgName[32];
	PrintCmd();
	if (ServerNamer)
	{
		GetConVarString(ServerNamer, ServerName, 32);
	}
	else
	{
		GetConVarString(FindConVar("hostname"), ServerName, 32);
	}
	GetConVarString(l4d_ready_cfg_name, cfgName, 32);
	Format(ServerBuffer, 128, "▸ Server: %s\n▸ Config: %s\n▸ Round: %s/2\n▸ Time played: %s", ServerName, cfgName, (InSecondHalfOfRound() ? "2" : "1"), stringTimer);
	DrawPanelText(menuPanel, ServerBuffer);
	DrawPanelText(menuPanel, " ");

	decl String:nameBuf[MAX_NAME_LENGTH*2];
	decl String:authBuffer[64];
	decl bool:caster;
	decl dummy;
	new Float:fTime = GetEngineTime();
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
		{
			++playerCount;
			GetClientName(client, nameBuf, sizeof(nameBuf));
			GetClientAuthId(client, AuthId_Steam2, authBuffer, sizeof(authBuffer));
			caster = GetTrieValue(casterTrie, authBuffer, dummy);
			if (IsPlayer(client))
			{
				if (isPlayerReady[client])
				{
					if (!inLiveCountdown) PrintHintText(client, "You are ready.\nSay !unready or !nr to unready.");
					Format(nameBuf, sizeof(nameBuf), "♞ %s\n", nameBuf);
				}
				else
				{
					if (!inLiveCountdown) PrintHintText(client, "You are not ready.\nSay !ready or !r to ready up.");
					if (fTime - g_fButtonTime[client] > 15.0)
					{
						Format(nameBuf, sizeof(nameBuf), "♘ %s [Toilet]\n", nameBuf);
					}
					else
					{
						Format(nameBuf, sizeof(nameBuf), "♘ %s\n", nameBuf);
					}			
				}

				if (L4D2Team:GetClientTeam(client) == L4D2Team_Survivor) StrCat(survivorBuffer, sizeof(survivorBuffer), nameBuf);
				else if (L4D2Team:GetClientTeam(client) == L4D2Team_Infected) StrCat(infectedBuffer, sizeof(infectedBuffer), nameBuf);
			}
			else if (caster)
			{
				++casterCount;
				Format(nameBuf, 64, "%s\n", nameBuf);
				StrCat(casterBuffer, sizeof(casterBuffer), nameBuf);
			}
			else
			{
				++specCount;
				if (playerCount <= GetConVarInt(l4d_ready_max_players))
				{
					Format(nameBuf, sizeof(nameBuf), "%s\n", nameBuf);
					StrCat(specBuffer, sizeof(specBuffer), nameBuf);
				}
			}
		}
	}

	new bufLen = strlen(survivorBuffer);
	if (bufLen != 0)
	{
		survivorBuffer[bufLen] = '\0';
		ReplaceString(survivorBuffer, sizeof(survivorBuffer), "#buy", "<- TROLL");
		ReplaceString(survivorBuffer, sizeof(survivorBuffer), "#", "_");
		DrawPanelText(menuPanel, "->1. Survivors");
		DrawPanelText(menuPanel, survivorBuffer);
	}

	bufLen = strlen(infectedBuffer);
	if (bufLen != 0)
	{
		infectedBuffer[bufLen] = '\0';
		ReplaceString(infectedBuffer, sizeof(infectedBuffer), "#buy", "<- TROLL");
		ReplaceString(infectedBuffer, sizeof(infectedBuffer), "#", "_");
		DrawPanelText(menuPanel, "->2. Infected");
		DrawPanelText(menuPanel, infectedBuffer);
	}
	
	bufLen = strlen(casterBuffer);		
	if (bufLen)		
	{		
		casterBuffer[bufLen] = '\0';		
		DrawPanelText(menuPanel, "->3. Casters");		
		ReplaceString(casterBuffer, sizeof(casterBuffer), "#", "_", true);		
		DrawPanelText(menuPanel, casterBuffer);		
	}
	
	bufLen = strlen(specBuffer);
	if (bufLen != 0)
	{
		specBuffer[bufLen] = '\0';
		if (casterCount == 0) DrawPanelText(menuPanel, "->3. Spectators");
		else DrawPanelText(menuPanel, "->4. Spectators");
		ReplaceString(specBuffer, sizeof(specBuffer), "#", "_");
		if (playerCount > GetConVarInt(l4d_ready_max_players))
			FormatEx(specBuffer, sizeof(specBuffer), "Many (%d)", specCount);
		DrawPanelText(menuPanel, specBuffer);
	}

	DrawPanelText(menuPanel, " ");
	DrawPanelText(menuPanel, "⌘ Commands ⌘");
	DrawPanelText(menuPanel, sCmd);

	for (new i = 0; i < MAX_FOOTERS; i++)
	{
		DrawPanelText(menuPanel, readyFooter[i]);
	}

	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client) && !hiddenPanel[client])
		{
			SendPanelToClient(menuPanel, client, DummyHandler, 1);
		}
	}
}

InitiateReadyUp()
{
	for (new i = 0; i <= MAXPLAYERS; i++)
	{
		isPlayerReady[i] = false;
		laser_bullet[i] = 0;
	}

	UpdatePanel();
	CreateTimer(1.0, MenuRefresh_Timer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(4.0, MenuCmd_Timer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	
	laser_enable = true;
	inReadyUp = true;
	inLiveCountdown = false;
	readyCountdownTimer = INVALID_HANDLE;

	if (GetConVarBool(l4d_ready_disable_spawns))
	{
		SetConVarBool(director_no_specials, true);
	}
	
	DisableEntities();
	SetConVarFlags(sv_infinite_primary_ammo, GetConVarFlags(god) & ~FCVAR_NOTIFY);
	SetConVarBool(sv_infinite_primary_ammo, true, false, false);
	SetConVarFlags(sv_infinite_primary_ammo, GetConVarFlags(god) | FCVAR_NOTIFY);

	SetConVarFlags(god, GetConVarFlags(god) & ~FCVAR_NOTIFY);
	SetConVarBool(god, true);
	SetConVarFlags(god, GetConVarFlags(god) | FCVAR_NOTIFY);
	SetConVarBool(sb_stop, true);

	L4D2_CTimerStart(L4D2CT_VersusStartTimer, 99999.9);
}

PrintCmd()
{
	if (iCmd > 9)
	{
		iCmd = 1;
	}
	switch (iCmd)
	{
		case 1:
		{
			Format(sCmd, sizeof(sCmd), "->1. !kickspecs");
		}
		case 2:
		{
			Format(sCmd, sizeof(sCmd), "->2. !slots #");
		}
		case 3:
		{
			Format(sCmd, sizeof(sCmd), "->3. !voteboss <tank> <witch>");
		}
		case 4:
		{
			Format(sCmd, sizeof(sCmd), "->4. !rmatch");
		}
		case 5:
		{
			Format(sCmd, sizeof(sCmd), "->5. !cast / !uncast");
		}
		case 6:
		{
			Format(sCmd, sizeof(sCmd), "->6. !setscores <survs> <inf>");
		}
		case 7:
		{
			Format(sCmd, sizeof(sCmd), "->7. !lerps");
		}
		case 8:
		{
			Format(sCmd, sizeof(sCmd), "->8. !return");
		}
		case 9:
		{
			Format(sCmd, sizeof(sCmd), "->9. !flip / !mix");
		}
		default:
		{
		}
	}
	return 0;
}

InitiateLive(bool:real = true)
{
	laser_enable = false; //Laser Tag
	inReadyUp = false;
	inLiveCountdown = false;

	SetTeamFrozen(L4D2Team_Survivor, false);
	EnableEntities();
	SetConVarFlags(sv_infinite_primary_ammo, GetConVarFlags(god) & ~FCVAR_NOTIFY);
	SetConVarBool(sv_infinite_primary_ammo, false, false, false);
	SetConVarFlags(sv_infinite_primary_ammo, GetConVarFlags(god) | FCVAR_NOTIFY);
	SetConVarBool(director_no_specials, false);
	SetConVarFlags(god, GetConVarFlags(god) & ~FCVAR_NOTIFY);
	SetConVarBool(god, false);
	SetConVarFlags(god, GetConVarFlags(god) | FCVAR_NOTIFY);
	SetConVarBool(sb_stop, false);

	L4D2_CTimerStart(L4D2CT_VersusStartTimer, 60.0);

	for (new i = 0; i < 4; i++)
	{
		GameRules_SetProp("m_iVersusDistancePerSurvivor", 0, _,
				i + 4 * GameRules_GetProp("m_bAreTeamsFlipped"));
	}

	for (new i = 0; i < MAX_FOOTERS; i++)
	{
		readyFooter[i] = "";
	}

	footerCounter = 0;
	if (real)
	{
		Call_StartForward(liveForward);
		Call_Finish();
	}
}

	public OnBossVote()
{
	footerCounter = 1;
}

ReturnPlayerToSaferoom(client, bool:flagsSet = true)
{
	new warp_flags;
	new give_flags;
	if (!flagsSet)
	{
		warp_flags = GetCommandFlags("warp_to_start_area");
		SetCommandFlags("warp_to_start_area", warp_flags & ~FCVAR_CHEAT);
		give_flags = GetCommandFlags("give");
		SetCommandFlags("give", give_flags & ~FCVAR_CHEAT);
	}

	if (GetEntProp(client, Prop_Send, "m_isHangingFromLedge"))
	{
		FakeClientCommand(client, "give health");
	}

	FakeClientCommand(client, "warp_to_start_area");

	if (!flagsSet)
	{
		SetCommandFlags("warp_to_start_area", warp_flags);
		SetCommandFlags("give", give_flags);
	}
}

ReturnTeamToSaferoom(L4D2Team:team)
{
	new warp_flags = GetCommandFlags("warp_to_start_area");
	SetCommandFlags("warp_to_start_area", warp_flags & ~FCVAR_CHEAT);
	new give_flags = GetCommandFlags("give");
	SetCommandFlags("give", give_flags & ~FCVAR_CHEAT);

	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && L4D2Team:GetClientTeam(client) == team)
		{
			ReturnPlayerToSaferoom(client, true);
		}
	}

	SetCommandFlags("warp_to_start_area", warp_flags);
	SetCommandFlags("give", give_flags);
}

SetTeamFrozen(L4D2Team:team, bool:freezeStatus)
{
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && L4D2Team:GetClientTeam(client) == team)
		{
			SetClientFrozen(client, freezeStatus);
		}
	}
}

bool:CheckFullReady()
{
	new readyCount = 0;
	//new casterCount = 0;
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			/*
			if (IsClientCaster(client))
			{
				casterCount++;
			}
			*/
			if (IsPlayer(client))
			{
				if (isPlayerReady[client])
					readyCount++;
			}
		}
	}
	
	new String:GameMode[32];
	
	GetConVarString(FindConVar("mp_gamemode"), GameMode, sizeof(GameMode));
	if (StrContains(GameMode, "coop", false) == -1 && StrContains(GameMode, "survival", false) == -1 && StrEqual(GameMode, "realism", false))
	{
		return readyCount >= GetRealClientCount();
	}
	return readyCount >= GetConVarInt(survivor_limit) + GetConVarInt(z_max_player_zombies);
}

InitiateLiveCountdown()
{
	if (readyCountdownTimer == INVALID_HANDLE)
	{
		ReturnTeamToSaferoom(L4D2Team_Survivor);
		SetTeamFrozen(L4D2Team_Survivor, true);
		PrintHintTextToAll("Going live!\nSay !unready to cancel");
		inLiveCountdown = true;
		readyDelay = GetConVarInt(l4d_ready_delay);
		readyCountdownTimer = CreateTimer(1.0, ReadyCountdownDelay_Timer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action:ReadyCountdownDelay_Timer(Handle:timer)
{
	if (readyDelay)
	{
		PrintHintTextToAll("Live in: %d\nSay !unready to cancel", readyDelay);
		if (GetConVarBool(l4d_ready_enable_sound))
		{
			EmitSoundToAll("buttons/blip1.wav", _, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
		}
		readyDelay--;
		return Plugin_Continue;
	}
	PrintHintTextToAll("Round is live!");
	InitiateLive(true);
	readyCountdownTimer = INVALID_HANDLE;
	if (GetConVarBool(l4d_ready_enable_sound))
	{
		if (GetConVarBool(l4d_ready_chuckle))
		{
			EmitSoundToAll(countdownSound[GetRandomInt(0,MAX_SOUNDS-1)]);
		}
		else
		{
			EmitSoundToAll(liveSound, -2, 0, 75, 0, 0.5);
		}
	}
	return Plugin_Stop;
}

CancelFullReady()
{
	if (readyCountdownTimer != INVALID_HANDLE)
	{
		if (bSkipWarp)
		{
			SetTeamFrozen(L4D2Team:L4D2Team_Survivor, true);
		}
		else
		{
			SetTeamFrozen(L4D2Team:L4D2Team_Survivor, GetConVarBool(l4d_ready_survivor_freeze));
		}
		inLiveCountdown = false;
		CloseHandle(readyCountdownTimer);
		readyCountdownTimer = INVALID_HANDLE;
		PrintHintTextToAll("Countdown Cancelled!");
	}
}

GetRealClientCount()
{
	new clients = 0;
	for (new i = 1; i <= GetMaxClients(); i++)
	{
		if (IsClientConnected(i))
		{
			if (!IsClientInGame(i))
			{
				clients++;
			}
			if (!IsFakeClient(i) && L4D2Team:GetClientTeam(i) == L4D2Team_Survivor)
			{
				clients++;
			}
		}
	}
	return clients;
}
// GetSeriousClientCount()
// {
// 	new clients = 0;
// 	for (new i = 1; i <= GetMaxClients(); i++)
// 	{
// 		if (IsClientConnected(i) && !IsFakeClient(i))
// 		{
// 			clients++;
// 		}
// 	}
// 	return clients;
// }

stock SetClientFrozen(client, freeze)
{
	SetEntityMoveType(client, freeze ? MOVETYPE_NONE : MOVETYPE_WALK);
}

stock IsPlayer(client)
{
	new L4D2Team:team = L4D2Team:GetClientTeam(client);
	return (team == L4D2Team_Survivor || team == L4D2Team_Infected);
}

DisableEntities()
{
	ActivateEntities("prop_door_rotating", "SetUnbreakable");
	MakePropsUnbreakable();
	return 0;
}
EnableEntities()
{
	ActivateEntities("prop_door_rotating", "SetBreakable");
	MakePropsBreakable();
	return 0;
}

ActivateEntities(String:className[], String:inputName[])
{
	new iEntity;
	while ((iEntity = FindEntityByClassname(iEntity, className)) != -1)
	{
		if (!IsValidEdict(iEntity) || !IsValidEntity(iEntity))
			continue;
			
		if (GetEntProp(iEntity, Prop_Data, "m_spawnflags") & (1 << 19))
			continue;
			
		AcceptEntityInput(iEntity, inputName);
	}
}

MakePropsUnbreakable()
{
	new iEntity;
	while ((iEntity = FindEntityByClassname(iEntity, "prop_physics")) != -1)
	{
		if (!IsValidEdict(iEntity) || !IsValidEntity(iEntity))
			continue;
		DispatchKeyValueFloat(iEntity, "minhealthdmg", 10000.0);
	}
}

MakePropsBreakable()
{
	new iEntity;
	while ((iEntity = FindEntityByClassname(iEntity, "prop_physics")) != -1)
	{
		if (!IsValidEdict(iEntity) || !IsValidEntity(iEntity))
			continue;
		DispatchKeyValueFloat(iEntity, "minhealthdmg", 5.0);
	}
}

InSecondHalfOfRound()
{
	return GameRules_GetProp("m_bInSecondHalfOfRound");
}

// Rainbow guns
public OnConfigsExecuted()
{
	g_LaserLife = GetConVarFloat(l4d_laser_life);
	g_LaserWidth = GetConVarFloat(l4d_laser_width);
	g_LaserOffset = GetConVarFloat(l4d_laser_offset);
}

public Action:Event_BulletImpact(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!laser_enable) return Plugin_Continue;
	
	// Get Shooter's Userid
	new userid = GetClientOfUserId(GetEventInt(event, "userid"));
	// Check if is Survivor
 	if(GetClientTeam(userid) != 2) return Plugin_Continue;
	// Check if is Bot and enabled
	if(IsFakeClient(userid)) { return Plugin_Continue; }

    //Color
	switch(laser_bullet[userid]) {
        case 0:
        {
            laser_color[0] = 255;			//Red
            laser_color[1] = 255;			//Green
            laser_color[2] = 255;			//Blue
        }
        case 1:
        {
            laser_color[0] = 75;
            laser_color[1] = 0;
            laser_color[2] = 130;
        }
        case 2:
        {
            laser_color[0] = 0;
            laser_color[1] = 0;
            laser_color[2] = 255;
        }
        case 3:
        {
            laser_color[0] = 0;
            laser_color[1] = 255;
            laser_color[2] = 0;
        }
        case 4:
        {
            laser_color[0] = 255;			
            laser_color[1] = 255;
            laser_color[2] = 0;
        }
        case 5:
        {
            laser_color[0] = 255;
            laser_color[1] = 127;
            laser_color[2] = 0;
        }
        default:
        {
            laser_color[0] = 255;
            laser_color[1] = 0;
            laser_color[2] = 0;
        }
    }

	laser_bullet[userid] = (laser_bullet[userid] < 6) ? laser_bullet[userid]+1 : 0;
	laser_color[3] = 255; //Alpha

	// Bullet impact location
	new Float:x = GetEventFloat(event, "x");
	new Float:y = GetEventFloat(event, "y");
	new Float:z = GetEventFloat(event, "z");
	
	decl Float:startPos[3];
	startPos[0] = x;
	startPos[1] = y;
	startPos[2] = z;
	
	/*decl Float:bulletPos[3];
	bulletPos[0] = x;
	bulletPos[1] = y;
	bulletPos[2] = z;*/
	
	decl Float:bulletPos[3];
	bulletPos = startPos;
	
	// Current player's EYE position
	decl Float:playerPos[3];
	GetClientEyePosition(userid, playerPos);
	
	decl Float:lineVector[3];
	SubtractVectors(playerPos, startPos, lineVector);
	NormalizeVector(lineVector, lineVector);
	
	// Offset
	ScaleVector(lineVector, g_LaserOffset);
	// Find starting point to draw line from
	SubtractVectors(playerPos, lineVector, startPos);
	
	// Draw the line
	TE_SetupBeamPoints(startPos, bulletPos, g_Sprite, 0, 0, 0, g_LaserLife, g_LaserWidth, g_LaserWidth, 1, 0.0, laser_color, 0);
	
	TE_SendToAll();

	
 	return Plugin_Continue;
}

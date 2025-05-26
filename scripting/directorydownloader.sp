#include <sourcemod>
#include <sdktools_stringtables>

#pragma newdecls required
#pragma semicolon 1

bool FakePrecache = false;
int SoundTable;
bool g_bPrecache = true;
bool g_bDebug = true;
File g_hIgnorePushFile = null;
StringMap g_mIgnore;

#if !defined PLUGIN_VERSION
#define PLUGIN_VERSION "dev"
#endif

public Plugin myinfo = {
	name = "[ANY] Directory Downloader",
	author = "inklesspen",
	version = PLUGIN_VERSION
}

public void OnPluginStart()
{
	char sBuffer[32];
	GetGameFolderName(sBuffer, 32);
	if(!strcmp(sBuffer, "insurgency") || !strcmp(sBuffer, "csgo"))
	{
		FakePrecache = true;
		SoundTable = FindStringTable("soundprecache");
	}

	RegServerCmd("sm_ddownloader_genignore", GetIgnoreCMD);
}

public Action GetIgnoreCMD(int argc)
{
	g_hIgnorePushFile = OpenFile("addons/sourcemod/data/ddownloader_ignore.txt", "w");
	if(g_hIgnorePushFile == null)	ReplyToCommand(0, "Cannot create ignore file.");
	else
	{
		OnMapStart();
		g_hIgnorePushFile.Close();
		g_hIgnorePushFile = null;
	}
}

void ReadCommandBool(const char[] line, int startpos, bool& value)
{
	if(!strcmp(line[startpos], "on"))			value = true;
	else	if(!strcmp(line[startpos], "off"))	value = false;
	else
	{
		LogError("Unknown directive: %s", line);
		return;
	}
	if(g_bDebug)	LogMessage("[DDownloader] Found directive: %s", line);
}

bool CanRead(const char[] sPath)
{
	int value;
	return g_mIgnore ? !g_mIgnore.GetValue(sPath, value) : true;
}

public void OnMapStart()
{
	char sPath[192];
	g_bPrecache = true;
	g_bDebug = false;
	if(!g_hIgnorePushFile)
	{
		File hIgnoreFile = OpenFile("addons/sourcemod/data/ddownloader_ignore.txt", "r");
		if(hIgnoreFile)
		{
			g_mIgnore = new StringMap();
			while(hIgnoreFile.ReadLine(sPath, sizeof sPath))
			{
				TrimString(sPath);
				if(!sPath[0])
					continue;
				g_mIgnore.SetValue(sPath, 0);
			}
		}
	}

	//Downloads
	BuildPath(Path_SM, sPath, 192, "configs/dirdownloader.ini");
	if(FileExists(sPath))
	{
		File downloads = OpenFile(sPath, "r");
		int size;
		int pos;
		while(ReadFileLine(downloads, sPath, 192))
		{
			pos = StrContains(sPath, "//");
			if(pos == 0)
				continue;
			else if(pos != -1)
				sPath[pos] = 0;
			TrimString(sPath);
			if(!sPath[0])
				continue;
			size = strlen(sPath);

			if(g_bDebug)	LogMessage("[DDownloader] Got path: %s", sPath);
			switch(sPath[size-1])
			{
				case '/':{
					sPath[size-1] = 0;
					if(DirExists(sPath)){
						Downloads_LoadDirectory(sPath, true);
					}
				}
				case '\\':{
					sPath[size-1] = 0;
					if(DirExists(sPath)){
						Downloads_LoadDirectory(sPath, false);
					}
				}
				default:{
					if(!strncmp(sPath, "dd-precache ", 12))	ReadCommandBool(sPath, 12, g_bPrecache);
					if(!strncmp(sPath, "dd-debug ", 9))	ReadCommandBool(sPath, 9, g_bDebug);
					else if(FileExists(sPath) && CanRead(sPath))	LoadFile(sPath);
				}
			}
		}
		downloads.Close();
	}
	if(g_mIgnore)	g_mIgnore.Close();
	g_mIgnore = null;
}

void Downloads_LoadDirectory(const char[] dirpath, bool recursive = false)
{
	if(g_bDebug)	LogMessage("[DDownloader] Opened: %s (%srecurvive)", dirpath, recursive ? "" : "non-");
	DirectoryListing dir = OpenDirectory(dirpath);
	char sPath[192];
	int l = strcopy(sPath, sizeof sPath, dirpath);
	sPath[l++] = '/';
	FileType type;
	while(ReadDirEntry(dir, sPath[l], sizeof sPath - l, type))
	{
		if(sPath[l] == '.')	continue;
		// LogError(")%s", sPath)
		if(g_bDebug)	LogMessage("[DDownloader] Found: %s", sPath);
		switch(type)
		{
			case FileType_Directory:	if(recursive)	Downloads_LoadDirectory(sPath, true);
			// case FileType_File:			if(FileExists(sPath) && !FileExists(sPath, true))	LoadFile(sPath)
			case FileType_File:			if(FileExists(sPath))	LoadFile(sPath);
		}
	}
	if(g_bDebug)	LogMessage("[DDownloader] Closed: %s", dirpath);
	dir.Close();
}

void LoadFile(char[] sPath)
{
	if(!CanRead(sPath))
	{
		if(g_bDebug)	LogMessage("[DDownloader] Ignored: %s (%sprecache)", sPath, g_bPrecache ? "" : "non-");
		return;
	}

	if(g_bDebug)	LogMessage("[DDownloader] Downloading: %s (%sprecache)", sPath, g_bPrecache ? "" : "non-");
	if(g_hIgnorePushFile)	g_hIgnorePushFile.WriteLine(sPath);
	else
	{
		int size = strlen(sPath);
		if(strcmp(sPath[size-4], ".bz2") == 0)	return;

		AddFileToDownloadsTable(sPath);
		if(!g_bPrecache)	return;
		if(!strcmp(sPath[size-4], ".mdl") && strncmp(sPath, "models/", 7) == 0) // Надеемся, что файл в models/
			PrecacheModel(sPath);
		else if(!strcmp(sPath[size-4], ".mp3"))
		{
			// Подразумивается, что файл находится в sound/
			if(FakePrecache)
			{
				sPath[5] = '*';
				AddToStringTable(SoundTable, sPath[5]);
			}
			else
				PrecacheSound(sPath[6]);
		}
	}
}
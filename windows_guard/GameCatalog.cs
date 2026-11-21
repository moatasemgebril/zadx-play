namespace ZadX.Guard;

/// <summary>
/// Windows executables per Zad X game id (ids match lib/data/catalog/games.dart).
/// Mobile-only games are simply absent. TODO(release): verify process names on
/// current game versions; publishers rename executables occasionally.
/// </summary>
public static class GameCatalog
{
    public static readonly IReadOnlyDictionary<string, string[]> Executables = new Dictionary<string, string[]>
    {
        ["roblox"] = new[] { "RobloxPlayerBeta", "RobloxPlayerLauncher" },
        ["minecraft"] = new[] { "Minecraft.Windows", "MinecraftLauncher" },
        ["fortnite"] = new[] { "FortniteClient-Win64-Shipping", "FortniteLauncher" },
        ["amongus"] = new[] { "Among Us" },
        ["pubg"] = new[] { "TslGame" },
        ["fcmobile"] = new[] { "FC26", "FC25" },
        ["candycrush"] = new[] { "CandyCrushSaga" },
        ["tocaboca"] = new[] { "TocaBocaWorld" },
    };

    /// <summary>Game stores/launchers blocked while games are locked (if enabled in appsettings).</summary>
    public static readonly string[] Launchers =
    {
        "steam", "EpicGamesLauncher", "Battle.net", "RiotClientServices", "XboxPcApp",
    };

    /// <summary>
    /// Browsers, closed in "allApps" mode unless the parent allows browsers for homework
    /// (browser games, YouTube, Facebook web). Never list msedgewebview2: Windows and many
    /// normal apps run on it. TODO(release): verify process names.
    /// </summary>
    public static readonly string[] Browsers =
    {
        "msedge", "chrome", "firefox", "opera", "brave", "vivaldi",
    };

    /// <summary>Social / chat desktop apps closed in "allApps" mode. TODO(release): verify process names.</summary>
    public static readonly string[] Social =
    {
        "Discord", "Telegram", "WhatsApp", "TikTok", "Messenger",
    };

    /// <summary>
    /// What the guard closes while locked (and meters while unlocked).
    /// Windows never uses "block everything except an allow-list": that could close system or
    /// homework software and make the PC unusable (docs/decisions/DEVICE-WIDE-LOCK.md §4).
    /// "allApps" = every catalogue game + launchers + social apps (+ browsers unless allowed).
    /// </summary>
    public static HashSet<string> ControlledProcesses(string? mode, IEnumerable<string> gameIds, bool allowBrowsers, bool includeLaunchers)
    {
        if (mode != "allApps") return ProcessNamesFor(gameIds, includeLaunchers);
        var set = ProcessNamesFor(Executables.Keys, includeLaunchers);
        set.UnionWith(Social);
        if (!allowBrowsers) set.UnionWith(Browsers);
        return set;
    }

    public static HashSet<string> ProcessNamesFor(IEnumerable<string> gameIds, bool includeLaunchers)
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var id in gameIds)
            if (Executables.TryGetValue(id, out var exes)) set.UnionWith(exes);
        if (includeLaunchers) set.UnionWith(Launchers);
        return set;
    }
}

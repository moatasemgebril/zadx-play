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

    public static HashSet<string> ProcessNamesFor(IEnumerable<string> gameIds, bool includeLaunchers)
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var id in gameIds)
            if (Executables.TryGetValue(id, out var exes)) set.UnionWith(exes);
        if (includeLaunchers) set.UnionWith(Launchers);
        return set;
    }
}

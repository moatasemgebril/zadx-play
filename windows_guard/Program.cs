using ZadX.Guard;

// Usage:
//   ZadXGuard.exe                 run as a Windows service (installed by install.ps1)
//   ZadXGuard.exe pair 123456     link this PC to a family (parent creates the code in Zad X)
//   ZadXGuard.exe status          print the current policy (for support)

var builder = Host.CreateApplicationBuilder(args.Where(a => a != "pair" && a != "status").ToArray());
builder.Services.AddWindowsService(o => o.ServiceName = "ZadXGuard");
builder.Services.Configure<GuardOptions>(builder.Configuration.GetSection("Guard"));
builder.Services.AddHttpClient<PolicyClient>();
builder.Services.AddSingleton<DeviceCredentials>();
builder.Services.AddSingleton<SessionNotifier>();
builder.Services.AddHostedService<GuardWorker>();
var host = builder.Build();

if (args.Length >= 2 && args[0] == "pair")
{
    var client = host.Services.GetRequiredService<PolicyClient>();
    var ok = await client.PairAsync(args[1], Environment.MachineName);
    Console.WriteLine(ok ? "Zad X Guard: this PC is now linked to the family." : "Pairing failed: invalid or expired code.");
    return ok ? 0 : 1;
}

if (args.Length >= 1 && args[0] == "status")
{
    var client = host.Services.GetRequiredService<PolicyClient>();
    var policy = await client.FetchPolicyAsync(CancellationToken.None);
    Console.WriteLine(policy is null ? "Not linked or offline." : System.Text.Json.JsonSerializer.Serialize(policy));
    return 0;
}

await host.RunAsync();
return 0;

namespace ZadX.Guard
{
    public sealed class GuardOptions
    {
        public string FunctionsBaseUrl { get; set; } = "";
        public int PolicyRefreshSeconds { get; set; } = 60;
        public int ScanIntervalSeconds { get; set; } = 4;
        public int PrayerLockMinutes { get; set; } = 15;
        public bool BlockLaunchersWhenLocked { get; set; } = true;
    }
}

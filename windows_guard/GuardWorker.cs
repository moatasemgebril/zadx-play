using System.Diagnostics;
using Microsoft.Extensions.Options;

namespace ZadX.Guard;

/// <summary>
/// The guard loop:
/// 1. every PolicyRefreshSeconds: fetch the family's policy (same rules as the phone app)
/// 2. every ScanIntervalSeconds: find controlled game processes
///    - locked (tasks / prayer / no time / offline-never-synced) → close them + tell the child
///    - unlocked → count play minutes and report them, so the balance drops on every device
/// </summary>
public sealed class GuardWorker : BackgroundService
{
    private readonly PolicyClient _client;
    private readonly SessionNotifier _notifier;
    private readonly GuardOptions _options;
    private readonly ILogger<GuardWorker> _log;

    private DevicePolicy? _policy;
    private DateTime _lastFetch = DateTime.MinValue;
    private DateTime _minuteStarted = DateTime.MinValue;
    private int _unreportedMinutes;

    public GuardWorker(PolicyClient client, SessionNotifier notifier, IOptions<GuardOptions> options, ILogger<GuardWorker> log)
    {
        _client = client;
        _notifier = notifier;
        _options = options.Value;
        _log = log;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        _log.LogInformation("Zad X Guard started");
        while (!ct.IsCancellationRequested)
        {
            try
            {
                await RefreshPolicyIfDue(ct);
                await Enforce(ct);
            }
            catch (Exception e)
            {
                _log.LogError(e, "Guard loop error");
            }
            await Task.Delay(TimeSpan.FromSeconds(_options.ScanIntervalSeconds), ct);
        }
    }

    private async Task RefreshPolicyIfDue(CancellationToken ct)
    {
        if (DateTime.UtcNow - _lastFetch < TimeSpan.FromSeconds(_options.PolicyRefreshSeconds)) return;
        _lastFetch = DateTime.UtcNow;
        var fresh = await _client.FetchPolicyAsync(ct);
        if (fresh is not null) _policy = fresh; // offline: keep the last known policy
        if (_unreportedMinutes > 0 && await _client.ReportUsageAsync(_unreportedMinutes, ct)) _unreportedMinutes = 0;
    }

    private async Task Enforce(CancellationToken ct)
    {
        var policy = _policy;
        var gameIds = policy?.Games ?? GameCatalog.Executables.Keys.ToArray();
        var running = FindRunning(GameCatalog.ProcessNamesFor(gameIds, includeLaunchers: false));
        var launchers = _options.BlockLaunchersWhenLocked ? FindRunning(new HashSet<string>(GameCatalog.Launchers, StringComparer.OrdinalIgnoreCase)) : new List<Process>();

        var (locked, reason) = Decide(policy);
        if (locked)
        {
            var targets = running.Concat(launchers).ToList();
            if (targets.Count > 0)
            {
                foreach (var p in targets) Close(p);
                _notifier.ShowLocked(reason, policy?.Language ?? "ar");
            }
            _minuteStarted = DateTime.MinValue;
            return;
        }

        // Unlocked: count minutes of real play.
        if (running.Count == 0)
        {
            _minuteStarted = DateTime.MinValue;
            return;
        }
        if (_minuteStarted == DateTime.MinValue) _minuteStarted = DateTime.UtcNow;
        if (DateTime.UtcNow - _minuteStarted >= TimeSpan.FromMinutes(1))
        {
            _minuteStarted = DateTime.UtcNow;
            _unreportedMinutes++;
            if (_policy is not null) _policy = _policy with { RemainingMinutes = Math.Max(0, _policy.RemainingMinutes - 1) };
            if (await _client.ReportUsageAsync(_unreportedMinutes, ct)) _unreportedMinutes = 0;
        }
    }

    private (bool locked, string reason) Decide(DevicePolicy? policy)
    {
        if (policy is null) return (true, "offline"); // never synced → safe default
        if (!policy.PlanActive) return (false, "none"); // Windows Guard is a Plus feature
        if (PrayerTimes.InPrayerWindow(policy.Prayer, _options.PrayerLockMinutes)) return (true, "prayer");
        if (policy.Locked) return (true, policy.Reason);
        if (policy.RemainingMinutes <= 0) return (true, "noTime");
        return (false, "none");
    }

    private static List<Process> FindRunning(HashSet<string> names) =>
        Process.GetProcesses().Where(p =>
        {
            try { return names.Contains(p.ProcessName); }
            catch { return false; }
        }).ToList();

    private void Close(Process p)
    {
        try
        {
            _log.LogInformation("Closing {Process}", p.ProcessName);
            if (!p.CloseMainWindow() || !p.WaitForExit(3000)) p.Kill(entireProcessTree: true);
        }
        catch (Exception e)
        {
            _log.LogWarning("Could not close {Process}: {Message}", p.ProcessName, e.Message);
        }
    }
}

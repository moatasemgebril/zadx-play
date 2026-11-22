using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace ZadX.Guard;

public sealed record PrayerSettings(
    [property: JsonPropertyName("lat")] double? Lat,
    [property: JsonPropertyName("lng")] double? Lng,
    [property: JsonPropertyName("timeZone")] string TimeZone,
    [property: JsonPropertyName("fajrAngle")] double? FajrAngle,
    [property: JsonPropertyName("ishaAngle")] double? IshaAngle,
    [property: JsonPropertyName("ishaMinutes")] int? IshaMinutes,
    [property: JsonPropertyName("asrFactor")] int AsrFactor,
    [property: JsonPropertyName("lockAtAdhan")] bool LockAtAdhan,
    // High-latitude rule synced by the app (absent from older backends/apps).
    [property: JsonPropertyName("highLatRule")] string? HighLatRule = null);

/// <summary>Mirror of the `devicePolicy` Cloud Function response.</summary>
public sealed record DevicePolicy(
    [property: JsonPropertyName("day")] string Day,
    [property: JsonPropertyName("locked")] bool Locked,
    [property: JsonPropertyName("reason")] string Reason,
    [property: JsonPropertyName("remainingMinutes")] int RemainingMinutes,
    [property: JsonPropertyName("games")] string[] Games,
    [property: JsonPropertyName("planActive")] bool PlanActive,
    [property: JsonPropertyName("language")] string Language,
    [property: JsonPropertyName("prayer")] PrayerSettings Prayer,
    // Device-wide lock (absent from older backends → legacy "selectedGames" behaviour).
    [property: JsonPropertyName("mode")] string? Mode = null,
    [property: JsonPropertyName("allowBrowsers")] bool AllowBrowsers = false,
    // Excused today (set by a parent): no lock at the adhan (absent from older backends → false).
    [property: JsonPropertyName("prayerPaused")] bool PrayerPaused = false);

public sealed class PolicyClient
{
    private readonly HttpClient _http;
    private readonly DeviceCredentials _credentials;
    private readonly GuardOptions _options;
    private readonly ILogger<PolicyClient> _log;

    public PolicyClient(HttpClient http, DeviceCredentials credentials, IOptions<GuardOptions> options, ILogger<PolicyClient> log)
    {
        _http = http;
        _http.Timeout = TimeSpan.FromSeconds(15);
        _credentials = credentials;
        _options = options.Value;
        _log = log;
    }

    private string Url(string fn) => $"{_options.FunctionsBaseUrl.TrimEnd('/')}/{fn}";

    /// <summary>The device secret travels in headers, so never talk to the backend over plain HTTP.</summary>
    private bool BaseUrlIsSecure()
    {
        if (Uri.TryCreate(_options.FunctionsBaseUrl, UriKind.Absolute, out var u) && u.Scheme == Uri.UriSchemeHttps) return true;
        _log.LogError("Guard:FunctionsBaseUrl must be an https:// URL");
        return false;
    }

    /// <summary>Redeems a pairing code (Firebase callable protocol: {"data": {...}} → {"result": {...}}).</summary>
    public async Task<bool> PairAsync(string code, string deviceName)
    {
        if (!BaseUrlIsSecure()) return false;
        var res = await _http.PostAsJsonAsync(Url("redeemPairingCode"), new { data = new { code, target = "windows", deviceName } });
        if (!res.IsSuccessStatusCode) return false;
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var r = doc.RootElement.GetProperty("result");
        _credentials.Save(new Credentials(
            r.GetProperty("familyId").GetString()!,
            r.GetProperty("deviceId").GetString()!,
            r.GetProperty("deviceSecret").GetString()!));
        return true;
    }

    public async Task<DevicePolicy?> FetchPolicyAsync(CancellationToken ct)
    {
        var request = Authorized(HttpMethod.Get, "devicePolicy");
        if (request is null) return null;
        try
        {
            var res = await _http.SendAsync(request, ct);
            if (!res.IsSuccessStatusCode)
            {
                _log.LogWarning("devicePolicy returned {Status}", res.StatusCode);
                return null;
            }
            return await res.Content.ReadFromJsonAsync<DevicePolicy>(cancellationToken: ct);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            _log.LogInformation("Offline: {Message}", e.Message);
            return null;
        }
    }

    public async Task<bool> ReportUsageAsync(int minutes, CancellationToken ct)
    {
        var request = Authorized(HttpMethod.Post, "reportUsage");
        if (request is null) return false;
        request.Content = JsonContent.Create(new { minutes });
        try
        {
            return (await _http.SendAsync(request, ct)).IsSuccessStatusCode;
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            return false;
        }
    }

    private HttpRequestMessage? Authorized(HttpMethod method, string fn)
    {
        if (!BaseUrlIsSecure()) return null;
        var c = _credentials.Load();
        if (c is null) return null;
        var request = new HttpRequestMessage(method, Url(fn));
        request.Headers.Add("x-zadx-family", c.FamilyId);
        request.Headers.Add("x-zadx-device", c.DeviceId);
        request.Headers.Add("x-zadx-secret", c.DeviceSecret);
        return request;
    }
}

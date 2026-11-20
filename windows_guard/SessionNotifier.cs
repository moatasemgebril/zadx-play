using System.Runtime.InteropServices;

namespace ZadX.Guard;

/// <summary>
/// Shows a message box on the active user's desktop from the service (session 0)
/// using WTSSendMessage. Non-blocking (wait = false).
/// </summary>
public sealed class SessionNotifier
{
    private DateTime _lastShown = DateTime.MinValue;

    public void ShowLocked(string reason, string language)
    {
        // Avoid spamming the child if they keep relaunching the game.
        if (DateTime.UtcNow - _lastShown < TimeSpan.FromSeconds(20)) return;
        _lastShown = DateTime.UtcNow;

        var ar = language == "ar";
        var title = "Zad X";
        var body = reason switch
        {
            "prayer" => ar ? "وقت الصلاة — الألعاب مقفولة لحد ما تصلي." : "Prayer time — games are locked until you pray.",
            "noTime" => ar ? "خلص وقتك النهارده — اعمل مهمة في Zad X تكسب وقت." : "Out of time — do a task in Zad X to earn more.",
            "offline" => ar ? "الكمبيوتر مش متصل بـ Zad X دلوقتي — الألعاب مقفولة." : "This PC can't reach Zad X right now — games stay locked.",
            _ => ar ? "خلّص مهامك الأول في Zad X، وبعدها اللعبة تتفتح." : "Finish your tasks in Zad X first, then the game unlocks.",
        };

        var session = WTSGetActiveConsoleSessionId();
        if (session == 0xFFFFFFFF) return;
        WTSSendMessage(IntPtr.Zero, session, title, title.Length * 2, body, body.Length * 2,
            0x40 /* MB_ICONINFORMATION */ | 0x40000 /* MB_TOPMOST */, 30, out _, false);
    }

    [DllImport("kernel32.dll")]
    private static extern uint WTSGetActiveConsoleSessionId();

    [DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool WTSSendMessage(IntPtr hServer, uint sessionId, string title, int titleLength,
        string message, int messageLength, int style, int timeout, out int response, bool wait);
}

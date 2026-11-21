# Zad X Guard — Windows game lock

A small Windows **service** (runs as SYSTEM) that applies the same rules as the phone app to
games on the child's PC:

- Games stay closed until must-do tasks are approved and minutes remain.
- Every adhan: games close for 15 minutes (computed locally, works offline) and until the
  prayer task is approved on the phone.
- Minutes played on the PC are reported to Firebase and reduce the balance everywhere.
- Steam / Epic / Battle.net / Riot / Xbox app launchers are closed while locked (configurable).
- "Lock all apps" mode (default, docs/decisions/DEVICE-WIDE-LOCK.md): also closes social/chat apps and,
  unless the parent allows them for homework, browsers. It never blocks every process (too risky on a PC).
- Never synced or offline before the first sync → games, launchers and social apps stay locked (safe default).

## Build & install
```powershell
dotnet publish -c Release            # needs .NET 8 SDK on Windows
# copy bin\Release\net8.0-windows\win-x64\publish\* and install.ps1 to the child's PC
powershell -ExecutionPolicy Bypass -File install.ps1 -PairingCode 123456
```
Create the pairing code in Zad X: **Parent → Link devices → Windows PC**.
Set `FunctionsBaseUrl` in `appsettings.json` to your Firebase project.

## Why the child can't just turn it off
- It is a Windows service under SYSTEM; a **Standard** user account cannot stop or uninstall it.
- Credentials are DPAPI-encrypted in `%ProgramData%\ZadX` (ACL: SYSTEM + Administrators).
- If killed, the service is restarted automatically (`sc failure`).
- The child must **not** be a Windows administrator — use Microsoft Family Safety or Settings →
  Accounts → Family to create a child (standard) account.

## Limits
- Browser games are covered only when browsers are locked ("lock all apps" mode without the homework
  exception); otherwise use Microsoft Family Safety web filters.
- Process names per game are in `GameCatalog.cs`; check them on current game versions.
- Release builds should be code-signed (Authenticode) and shipped as MSI/MSIX.

## macOS
Not included yet. Apple's Screen Time frameworks were designed for iPhone/iPad; a Mac blocker
needs a separate study (likely a signed helper with a privileged launch daemon). The Zad X app
itself (dashboard, Quran, adhkar, prayer times) runs on macOS via Flutter.

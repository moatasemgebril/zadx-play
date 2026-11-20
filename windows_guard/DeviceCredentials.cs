using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ZadX.Guard;

public sealed record Credentials(string FamilyId, string DeviceId, string DeviceSecret);

/// <summary>
/// Stores the pairing credentials encrypted with DPAPI (machine scope) under
/// %ProgramData%\ZadX. The folder ACL (set by install.ps1) allows only SYSTEM and
/// Administrators, so a standard child account cannot read or delete it.
/// </summary>
public sealed class DeviceCredentials
{
    private static readonly string Folder =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "ZadX");
    private static readonly string FilePath = Path.Combine(Folder, "device.dat");
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("zadx-guard-v1");

    public Credentials? Load()
    {
        if (!File.Exists(FilePath)) return null;
        try
        {
            var plain = ProtectedData.Unprotect(File.ReadAllBytes(FilePath), Entropy, DataProtectionScope.LocalMachine);
            return JsonSerializer.Deserialize<Credentials>(plain);
        }
        catch (CryptographicException)
        {
            return null;
        }
    }

    public void Save(Credentials credentials)
    {
        Directory.CreateDirectory(Folder);
        var plain = JsonSerializer.SerializeToUtf8Bytes(credentials);
        File.WriteAllBytes(FilePath, ProtectedData.Protect(plain, Entropy, DataProtectionScope.LocalMachine));
    }
}

import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Shield Configuration extension (target "ZadXShield"): the screen shown over a locked game.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    // Websites are shielded too in "allApps" mode (shield.webDomainCategories).
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        let arabic = Locale.preferredLanguages.first?.hasPrefix("ar") ?? true
        let allApps = SharedStore.mode == "allApps"
        let (title, subtitle): (String, String) = {
            switch SharedStore.reason {
            case "prayer":
                if allApps {
                    return arabic ? ("وقت الصلاة", "التطبيقات مقفولة لحد ما تصلي") : ("Prayer time", "Apps are locked until you pray")
                }
                return arabic ? ("وقت الصلاة", "الألعاب مقفولة لحد ما تصلي") : ("Prayer time", "Games are locked until you pray")
            case "noTime":
                return arabic ? ("خلص وقتك", "اعمل مهمة في Zad X تكسب وقت") : ("Out of time", "Do a task in Zad X to earn more")
            default:
                if allApps {
                    return arabic ? ("خلّص مهامك الأول", "وبعدها التطبيق يتفتح") : ("Finish your tasks first", "Then the app unlocks")
                }
                return arabic ? ("خلّص مهامك الأول", "وبعدها اللعبة تتفتح") : ("Finish your tasks first", "Then the game unlocks")
            }
        }()
        let navy = UIColor(red: 10 / 255, green: 34 / 255, blue: 94 / 255, alpha: 1)
        let gold = UIColor(red: 1, green: 200 / 255, blue: 61 / 255, alpha: 1)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: navy,
            icon: UIImage(named: "ZadXShieldIcon"),
            title: .init(text: title, color: gold),
            subtitle: .init(text: subtitle, color: .white),
            primaryButtonLabel: .init(text: arabic ? "تمام" : "OK", color: navy),
            primaryButtonBackgroundColor: gold
        )
    }
}

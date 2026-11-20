import '../../core/localized.dart';

/// Parts of the "Build Your Mosque" game, in build order.
///
/// Each line is a short, kind, general message (no Quran or hadith quotes).
class MosquePart {
  const MosquePart({required this.id, required this.name, required this.cost, required this.line});

  final String id;
  final Localized name;

  /// Stars needed to add this part.
  final int cost;
  final Localized line;
}

const mosqueParts = <MosquePart>[
  MosquePart(
    id: 'foundation',
    name: Localized('الأساس', 'Foundation'),
    cost: 2,
    line: Localized('كل بناء قوي يبدأ بأساس متين، وكذلك الأخلاق الطيبة.', 'Every strong building starts with a strong foundation — and so do good manners.'),
  ),
  MosquePart(
    id: 'walls',
    name: Localized('الجدران', 'Walls'),
    cost: 3,
    line: Localized('المسجد بيت من بيوت الله، يجتمع فيه المسلمون للصلاة.', 'A masjid is a house of Allah where Muslims gather to pray.'),
  ),
  MosquePart(
    id: 'door',
    name: Localized('الباب', 'Door'),
    cost: 3,
    line: Localized('ندخل المسجد بهدوء ونلقي السلام على من فيه.', 'We walk into the masjid calmly and greet everyone with salam.'),
  ),
  MosquePart(
    id: 'windows',
    name: Localized('الشبابيك', 'Windows'),
    cost: 3,
    line: Localized('النور والهواء النظيف يجعلان المسجد مكانًا جميلًا للصلاة.', 'Light and fresh air make the masjid a lovely place to pray.'),
  ),
  MosquePart(
    id: 'dome',
    name: Localized('القبة', 'Dome'),
    cost: 4,
    line: Localized('كثير من المساجد حول العالم لها قباب جميلة.', 'Many masjids around the world have beautiful domes.'),
  ),
  MosquePart(
    id: 'minaret',
    name: Localized('المئذنة', 'Minaret'),
    cost: 4,
    line: Localized('من المئذنة يُرفع الأذان ليدعو الناس إلى الصلاة.', 'The adhan is called from the minaret to invite people to prayer.'),
  ),
  MosquePart(
    id: 'crescent',
    name: Localized('الهلال', 'Crescent'),
    cost: 3,
    line: Localized('الشهور الهجرية تبدأ مع ظهور الهلال الجديد.', 'The Islamic (Hijri) months begin when the new crescent moon appears.'),
  ),
  MosquePart(
    id: 'carpet',
    name: Localized('السجاد', 'Carpet'),
    cost: 3,
    line: Localized('نحافظ على نظافة المسجد ليصلي الجميع براحة.', 'We keep the masjid clean so everyone can pray comfortably.'),
  ),
  MosquePart(
    id: 'lanterns',
    name: Localized('الفوانيس', 'Lanterns'),
    cost: 3,
    line: Localized('الفوانيس تنير الطريق لمن يأتي لصلاة العشاء والفجر.', 'Lanterns light the way for people coming to pray Isha and Fajr.'),
  ),
  MosquePart(
    id: 'garden',
    name: Localized('الحديقة', 'Garden'),
    cost: 4,
    line: Localized('الاهتمام بالنباتات والطبيعة عادة جميلة.', 'Caring for plants and nature is a lovely habit.'),
  ),
];

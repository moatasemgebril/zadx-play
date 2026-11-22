import '../../core/localized.dart';
import '../models/family_task.dart';

/// One multiple-choice question at the end of a story.
class StoryQuestion {
  const StoryQuestion({required this.prompt, required this.options, required this.answer});

  final Localized prompt;
  final List<Localized> options;

  /// Index of the correct option in [options].
  final int answer;
}

/// A short, original reading story for the "reading" homework task.
///
/// Content rules (owner request 2026-11-22): original texts written for Zad X, general and
/// ethical themes only (manners, kindness, honesty, nature, science curiosity). No Quran
/// verses, hadith or religious rulings, so the stories need no scholar review and also work
/// in a future non-Islamic build. Science facts are kept simple and correct.
class ReadingStory {
  const ReadingStory({
    required this.id,
    required this.level,
    required this.title,
    required this.paragraphs,
    required this.questions,
  });

  final String id;
  final ReadingLevel level;
  final Localized title;
  final List<Localized> paragraphs;
  final List<StoryQuestion> questions;
}

/// Stories of [level], or every story when [level] is `null`.
List<ReadingStory> storiesFor(ReadingLevel? level) =>
    level == null ? readingStories : readingStories.where((s) => s.level == level).toList();

ReadingStory? storyById(String id) {
  for (final s in readingStories) {
    if (s.id == id) return s;
  }
  return null;
}

const readingStories = <ReadingStory>[
  // ---------------------------------------------------------------- ages 5–7
  ReadingStory(
    id: 'little_seed',
    level: ReadingLevel.age5to7,
    title: Localized('البذرة الصغيرة', 'The Little Seed'),
    paragraphs: [
      Localized(
        'وضعت لينا بذرة صغيرة في أصيص من التراب.',
        'Lina put a little seed in a pot of soil.',
      ),
      Localized(
        'كل صباح كانت تسقيها بقليل من الماء، وتضعها قرب النافذة لترى الشمس.',
        'Every morning she gave it a little water and put it by the window to see the sun.',
      ),
      Localized(
        'انتظرت لينا أيامًا بصبر. وفي يوم جميل، رأت ورقة خضراء صغيرة تخرج من التراب!',
        'Lina waited patiently for many days. One lovely morning, she saw a tiny green leaf coming out of the soil!',
      ),
      Localized(
        'ابتسمت لينا وقالت: "الصبر والعناية يجعلان الأشياء تكبر."',
        'Lina smiled and said, "Patience and care help things grow."',
      ),
    ],
    questions: [
      StoryQuestion(
        prompt: Localized('ماذا زرعت لينا؟', 'What did Lina plant?'),
        options: [Localized('بذرة', 'A seed'), Localized('حجرًا', 'A stone'), Localized('لعبة', 'A toy')],
        answer: 0,
      ),
      StoryQuestion(
        prompt: Localized('ماذا احتاجت البذرة لتكبر؟', 'What did the seed need to grow?'),
        options: [
          Localized('حلوى', 'Sweets'),
          Localized('ماء وشمس', 'Water and sun'),
          Localized('حذاء', 'Shoes'),
        ],
        answer: 1,
      ),
    ],
  ),
  ReadingStory(
    id: 'shared_umbrella',
    level: ReadingLevel.age5to7,
    title: Localized('المظلة المشتركة', 'The Shared Umbrella'),
    paragraphs: [
      Localized(
        'بعد المدرسة بدأ المطر ينزل بقوة.',
        'After school, it started to rain hard.',
      ),
      Localized(
        'كان مع آدم مظلة زرقاء كبيرة، لكن صديقه كريم لم يكن معه مظلة.',
        'Adam had a big blue umbrella, but his friend Karim did not have one.',
      ),
      Localized(
        'قال آدم: "تعال يا كريم، المظلة تكفينا نحن الاثنين!"',
        'Adam said, "Come, Karim, the umbrella is big enough for both of us!"',
      ),
      Localized(
        'مشى الصديقان معًا تحت المظلة وهما يضحكان، ووصلا إلى البيت بدون أن يبتلّا.',
        'The two friends walked together under the umbrella, laughing, and got home dry.',
      ),
    ],
    questions: [
      StoryQuestion(
        prompt: Localized('كيف كان الجو بعد المدرسة؟', 'What was the weather like after school?'),
        options: [Localized('مشمسًا', 'Sunny'), Localized('ممطرًا', 'Rainy'), Localized('مثلجًا', 'Snowy')],
        answer: 1,
      ),
      StoryQuestion(
        prompt: Localized('ماذا فعل آدم؟', 'What did Adam do?'),
        options: [
          Localized('شارك مظلته مع صديقه', 'He shared his umbrella with his friend'),
          Localized('جرى وترك صديقه', 'He ran off and left his friend'),
          Localized('أغلق مظلته', 'He closed his umbrella'),
        ],
        answer: 0,
      ),
    ],
  ),

  // ---------------------------------------------------------------- ages 8–10
  ReadingStory(
    id: 'broken_vase',
    level: ReadingLevel.age8to10,
    title: Localized('المزهرية المكسورة', 'The Broken Vase'),
    paragraphs: [
      Localized(
        'كان عمر يلعب بالكرة داخل غرفة الجلوس، مع أن أمه طلبت منه أن يلعب في الحديقة.',
        'Omar was playing ball in the living room, even though his mother had asked him to play in the garden.',
      ),
      Localized(
        'ركل الكرة بقوة، فاصطدمت بالمزهرية وسقطت على الأرض وانكسرت.',
        'He kicked the ball hard. It hit the vase, which fell to the floor and broke.',
      ),
      Localized(
        'فكّر عمر قليلًا: هل يخفي القطع؟ ثم أخذ نفسًا عميقًا وذهب إلى أمه وقال: "أنا آسف يا أمي، أنا كسرت المزهرية وأنا ألعب."',
        'Omar thought for a moment: should he hide the pieces? Then he took a deep breath, went to his mother and said, "I\'m sorry, Mum. I broke the vase while I was playing."',
      ),
      Localized(
        'قالت أمه: "شكرًا لأنك قلت الحقيقة يا عمر. المزهرية يمكن أن نشتري غيرها، لكن صدقك أغلى بكثير."',
        'His mother said, "Thank you for telling the truth, Omar. We can buy another vase, but your honesty is worth much more."',
      ),
      Localized(
        'جمعا القطع معًا بحذر، ومن يومها صار عمر يلعب بالكرة في الحديقة.',
        'They carefully picked up the pieces together, and from that day Omar played ball in the garden.',
      ),
    ],
    questions: [
      StoryQuestion(
        prompt: Localized('ماذا انكسر في القصة؟', 'What broke in the story?'),
        options: [Localized('نافذة', 'A window'), Localized('مزهرية', 'A vase'), Localized('كرسي', 'A chair')],
        answer: 1,
      ),
      StoryQuestion(
        prompt: Localized('ماذا فعل عمر بعد أن انكسرت المزهرية؟', 'What did Omar do after the vase broke?'),
        options: [
          Localized('أخفى القطع', 'He hid the pieces'),
          Localized('قال لأمه الحقيقة', 'He told his mother the truth'),
          Localized('قال إن القطة كسرتها', 'He said the cat broke it'),
        ],
        answer: 1,
      ),
      StoryQuestion(
        prompt: Localized('ما الشيء الذي قالت الأم إنه أغلى من المزهرية؟', 'What did his mother say was worth more than the vase?'),
        options: [
          Localized('الكرة', 'The ball'),
          Localized('الحديقة', 'The garden'),
          Localized('صدق عمر', "Omar's honesty"),
        ],
        answer: 2,
      ),
    ],
  ),
  ReadingStory(
    id: 'blue_sky',
    level: ReadingLevel.age8to10,
    title: Localized('لماذا السماء زرقاء؟', 'Why Is the Sky Blue?'),
    paragraphs: [
      Localized(
        'جلست سارة مع جدها في الحديقة، ونظرت إلى السماء وسألت: "يا جدي، لماذا السماء زرقاء؟"',
        'Sara sat in the garden with her grandfather. She looked up and asked, "Grandpa, why is the sky blue?"',
      ),
      Localized(
        'ابتسم الجد وقال: "ضوء الشمس يبدو أبيض، لكنه في الحقيقة يحمل كل ألوان قوس قزح."',
        'Grandpa smiled. "Sunlight looks white, but it really carries all the colours of the rainbow."',
      ),
      Localized(
        '"وعندما يمر الضوء في الهواء، تصطدم ألوانه بأجزاء صغيرة جدًا من الهواء لا نراها. اللون الأزرق يتبعثر وينتشر في كل اتجاه أكثر من الأحمر والأصفر، فنرى الأزرق يملأ السماء."',
        '"When the light travels through the air, it bumps into tiny bits of air that are too small to see. Blue light gets scattered all around much more than red or yellow, so we see blue filling the sky."',
      ),
      Localized(
        'سألت سارة: "ولماذا تصبح السماء برتقالية وقت الغروب؟" قال الجد: "لأن الضوء يقطع طريقًا أطول في الهواء، فيتبعثر أكثر الأزرق قبل أن يصل إلينا، ويبقى البرتقالي والأحمر."',
        'Sara asked, "Then why is the sky orange at sunset?" Grandpa said, "Because the light travels a longer way through the air, so most of the blue is scattered away before it reaches us, and orange and red are left."',
      ),
      Localized(
        'قالت سارة: "سأسأل عن كل شيء أراه!" فضحك الجد وقال: "هكذا يبدأ العلماء."',
        'Sara said, "I\'m going to ask about everything I see!" Grandpa laughed. "That is how scientists begin."',
      ),
    ],
    questions: [
      StoryQuestion(
        prompt: Localized('ماذا يحمل ضوء الشمس؟', 'What does sunlight carry?'),
        options: [
          Localized('اللون الأصفر فقط', 'Only yellow'),
          Localized('كل ألوان قوس قزح', 'All the colours of the rainbow'),
          Localized('اللون الأزرق فقط', 'Only blue'),
        ],
        answer: 1,
      ),
      StoryQuestion(
        prompt: Localized('ما الذي يبعثر الضوء الأزرق في السماء؟', 'What scatters the blue light across the sky?'),
        options: [
          Localized('أجزاء صغيرة جدًا من الهواء', 'Tiny bits of air'),
          Localized('ماء البحر', 'Sea water'),
          Localized('ألوان الطيور', 'The colours of birds'),
        ],
        answer: 0,
      ),
      StoryQuestion(
        prompt: Localized('ماذا قال الجد عن الأسئلة؟', 'What did Grandpa say about asking questions?'),
        options: [
          Localized('هكذا يبدأ العلماء', 'That is how scientists begin'),
          Localized('الأسئلة مملة', 'Questions are boring'),
          Localized('اسألي مرة واحدة فقط', 'Only ask once'),
        ],
        answer: 0,
      ),
    ],
  ),

  // ---------------------------------------------------------------- ages 11–12
  ReadingStory(
    id: 'new_classmate',
    level: ReadingLevel.age11to12,
    title: Localized('الزميلة الجديدة', 'The New Classmate'),
    paragraphs: [
      Localized(
        'في أول يوم من الفصل الدراسي، دخلت طالبة جديدة اسمها نور. كانت قد انتقلت مع أسرتها من بلد آخر، ولا تعرف لغة المدرسة جيدًا بعد.',
        'On the first day of term, a new student called Nour joined the class. Her family had just moved from another country, and she did not know the school\'s language well yet.',
      ),
      Localized(
        'في وقت الاستراحة جلست نور وحدها في آخر الساحة. لاحظتها مايا، وتذكّرت كيف شعرت هي نفسها عندما انتقلت إلى مدرسة جديدة قبل سنتين.',
        'At break time, Nour sat alone at the far end of the playground. Maya noticed her and remembered how she had felt when she moved to a new school two years before.',
      ),
      Localized(
        'اقتربت مايا وقالت ببطء مع ابتسامة: "مرحبًا، أنا مايا. هل تحبين أن تجلسي معنا؟" وأشارت إلى صديقاتها. فهمت نور الابتسامة قبل الكلمات، وقامت معها.',
        'Maya walked over and said slowly, with a smile, "Hi, I\'m Maya. Would you like to sit with us?" and pointed to her friends. Nour understood the smile before the words, and came along.',
      ),
      Localized(
        'في الأيام التالية علّمت مايا وصديقاتها نور كلمات جديدة، وعلّمتهن نور كلمات من لغتها ولعبة كانت تلعبها في بلدها. صار الجميع ينتظر الاستراحة.',
        'Over the next days, Maya and her friends taught Nour new words, and Nour taught them words from her language and a game she used to play at home. Soon everyone looked forward to break time.',
      ),
      Localized(
        'في نهاية الشهر قالت نور: "كنت خائفة في أول يوم، لكن ابتسامة واحدة غيّرت كل شيء." وفهمت مايا أن اللطف لا يحتاج إلى لغة مشتركة.',
        'At the end of the month, Nour said, "I was scared on the first day, but one smile changed everything." Maya realised that kindness does not need a shared language.',
      ),
    ],
    questions: [
      StoryQuestion(
        prompt: Localized('لماذا كانت نور تجلس وحدها؟', 'Why was Nour sitting alone?'),
        options: [
          Localized('لأنها جديدة ولا تعرف اللغة جيدًا بعد', 'She was new and did not know the language well yet'),
          Localized('لأنها لا تحب اللعب', 'She did not like playing'),
          Localized('لأنها كانت معاقبة', 'She was being punished'),
        ],
        answer: 0,
      ),
      StoryQuestion(
        prompt: Localized('لماذا فهمت مايا شعور نور؟', 'Why did Maya understand how Nour felt?'),
        options: [
          Localized('لأن نور أخبرتها', 'Nour told her'),
          Localized('لأنها هي أيضًا انتقلت إلى مدرسة جديدة من قبل', 'She had also moved to a new school before'),
          Localized('لأن المعلمة طلبت منها', 'The teacher asked her to'),
        ],
        answer: 1,
      ),
      StoryQuestion(
        prompt: Localized('ما الدرس الذي فهمته مايا؟', 'What did Maya realise?'),
        options: [
          Localized('أن الاستراحة قصيرة', 'Break time is short'),
          Localized('أن الألعاب الجديدة صعبة', 'New games are hard'),
          Localized('أن اللطف لا يحتاج إلى لغة مشتركة', 'Kindness does not need a shared language'),
        ],
        answer: 2,
      ),
    ],
  ),
  ReadingStory(
    id: 'bee_garden',
    level: ReadingLevel.age11to12,
    title: Localized('حديقة النحل', 'The Bee Garden'),
    paragraphs: [
      Localized(
        'كان يوسف يساعد جدته في الحديقة عندما رأى نحلة تطير من زهرة إلى زهرة. تراجع خائفًا وقال: "هيا نبعدها!"',
        'Yusuf was helping his grandmother in the garden when he saw a bee flying from flower to flower. He stepped back and said, "Let\'s get rid of it!"',
      ),
      Localized(
        'قالت الجدة بهدوء: "لا تخف، النحلة مشغولة بعملها ولن تؤذيك إذا تركتها. انظر إلى أرجلها، هل ترى المسحوق الأصفر؟ هذا اسمه حبوب اللقاح."',
        'Grandma said calmly, "Don\'t worry, the bee is busy working and won\'t hurt you if you leave it alone. Look at its legs. Can you see the yellow powder? That is called pollen."',
      ),
      Localized(
        '"عندما تزور النحلة الأزهار لتجمع الرحيق، تنقل حبوب اللقاح من زهرة إلى أخرى. هذا الانتقال اسمه التلقيح، وهو يساعد نباتات كثيرة على صنع الثمار والبذور."',
        '"When the bee visits flowers to collect nectar, it carries pollen from one flower to another. This is called pollination, and it helps many plants make fruit and seeds."',
      ),
      Localized(
        'أشارت الجدة إلى شجرة التفاح وقالت: "كثير من التفاح الذي نأكله بدأ بزيارة من نحلة." نظر يوسف إلى النحلة باحترام جديد.',
        'Grandma pointed at the apple tree. "Many of the apples we eat started with a visit from a bee." Yusuf looked at the bee with new respect.',
      ),
      Localized(
        'في نهاية اليوم، قرر يوسف وجدته أن يزرعا صفًا من الأزهار الملوّنة، وأن يضعا طبقًا صغيرًا فيه ماء وحصى لتشرب منه النحلات. قال يوسف: "الآن صارت حديقتنا بيتًا للنحل أيضًا."',
        'At the end of the day, Yusuf and his grandmother decided to plant a row of colourful flowers and put out a small dish of water with pebbles for the bees to drink from. Yusuf said, "Now our garden is a home for bees too."',
      ),
    ],
    questions: [
      StoryQuestion(
        prompt: Localized('ماذا تنقل النحلة من زهرة إلى أخرى؟', 'What does the bee carry from one flower to another?'),
        options: [
          Localized('الرمل', 'Sand'),
          Localized('حبوب اللقاح', 'Pollen'),
          Localized('أوراق الشجر', 'Leaves'),
        ],
        answer: 1,
      ),
      StoryQuestion(
        prompt: Localized('بماذا يساعد التلقيح النباتات؟', 'What does pollination help plants do?'),
        options: [
          Localized('صنع الثمار والبذور', 'Make fruit and seeds'),
          Localized('الطيران', 'Fly'),
          Localized('النوم في الشتاء', 'Sleep in winter'),
        ],
        answer: 0,
      ),
      StoryQuestion(
        prompt: Localized('ماذا قرر يوسف وجدته في النهاية؟', 'What did Yusuf and his grandmother decide to do?'),
        options: [
          Localized('أن يبعدا كل النحل', 'Chase all the bees away'),
          Localized('أن يقطعا شجرة التفاح', 'Cut down the apple tree'),
          Localized('أن يزرعا أزهارًا ويضعا ماء للنحل', 'Plant flowers and put out water for the bees'),
        ],
        answer: 2,
      ),
    ],
  ),
];

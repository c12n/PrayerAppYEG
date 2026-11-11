import 'package:flutter/material.dart';

import 'prayer_models.dart';
import 'strings.dart';

// The 99 Names of Allah (v2.3.0): the same embedded list as the iOS
// app (Shared/PrayerModels.swift) — keep the two in sync. Fully
// offline, like everything else in the app.

class AllahName {
  final String arabic;
  final String transliteration;
  final String english;
  final String french;
  final String arabicGloss;

  const AllahName({
    required this.arabic,
    required this.transliteration,
    required this.english,
    required this.french,
    required this.arabicGloss,
  });

  String meaning(AppLanguage language) => switch (language) {
        AppLanguage.en => english,
        AppLanguage.fr => french,
        AppLanguage.ar => arabicGloss,
      };
}

const List<AllahName> namesOfAllah = [
  AllahName(arabic: "الرحمن", transliteration: "Ar-Rahman", english: "The Most Gracious", french: "Le Tout Miséricordieux", arabicGloss: "ذو الرحمة الواسعة"),
  AllahName(arabic: "الرحيم", transliteration: "Ar-Rahim", english: "The Most Merciful", french: "Le Très Miséricordieux", arabicGloss: "المنعم على عباده"),
  AllahName(arabic: "الملك", transliteration: "Al-Malik", english: "The King", french: "Le Roi", arabicGloss: "مالك الملك كله"),
  AllahName(arabic: "القدوس", transliteration: "Al-Quddus", english: "The Most Holy", french: "Le Saint", arabicGloss: "المنزه عن كل نقص"),
  AllahName(arabic: "السلام", transliteration: "As-Salam", english: "The Source of Peace", french: "La Paix", arabicGloss: "السالم من كل عيب"),
  AllahName(arabic: "المؤمن", transliteration: "Al-Mu'min", english: "The Giver of Faith", french: "Le Garant de la foi", arabicGloss: "واهب الأمن والإيمان"),
  AllahName(arabic: "المهيمن", transliteration: "Al-Muhaymin", english: "The Guardian", french: "Le Protecteur", arabicGloss: "الرقيب الحافظ"),
  AllahName(arabic: "العزيز", transliteration: "Al-Aziz", english: "The Almighty", french: "Le Tout-Puissant", arabicGloss: "الغالب الذي لا يُقهر"),
  AllahName(arabic: "الجبار", transliteration: "Al-Jabbar", english: "The Compeller", french: "Le Contraignant", arabicGloss: "العالي الذي يجبر الكسير"),
  AllahName(arabic: "المتكبر", transliteration: "Al-Mutakabbir", english: "The Supreme", french: "Le Superbe", arabicGloss: "المتعالي عن صفات الخلق"),
  AllahName(arabic: "الخالق", transliteration: "Al-Khaliq", english: "The Creator", french: "Le Créateur", arabicGloss: "المبدع للخلق"),
  AllahName(arabic: "البارئ", transliteration: "Al-Bari", english: "The Originator", french: "L'Initiateur", arabicGloss: "المنشئ بلا مثال"),
  AllahName(arabic: "المصور", transliteration: "Al-Musawwir", english: "The Fashioner", french: "Le Formateur", arabicGloss: "الذي صوّر المخلوقات"),
  AllahName(arabic: "الغفار", transliteration: "Al-Ghaffar", english: "The Great Forgiver", french: "Le Grand Pardonneur", arabicGloss: "الساتر لذنوب عباده"),
  AllahName(arabic: "القهار", transliteration: "Al-Qahhar", english: "The Subduer", french: "Le Dominateur", arabicGloss: "الغالب لكل شيء"),
  AllahName(arabic: "الوهاب", transliteration: "Al-Wahhab", english: "The Bestower", french: "Le Donateur", arabicGloss: "كثير العطاء بلا عوض"),
  AllahName(arabic: "الرزاق", transliteration: "Ar-Razzaq", english: "The Provider", french: "Le Pourvoyeur", arabicGloss: "المتكفل بأرزاق العباد"),
  AllahName(arabic: "الفتاح", transliteration: "Al-Fattah", english: "The Opener, the Judge", french: "L'Ouvreur, le Juge", arabicGloss: "الحاكم الفاتح لعباده"),
  AllahName(arabic: "العليم", transliteration: "Al-Alim", english: "The All-Knowing", french: "L'Omniscient", arabicGloss: "المحيط علمه بكل شيء"),
  AllahName(arabic: "القابض", transliteration: "Al-Qabid", english: "The Withholder", french: "Celui qui restreint", arabicGloss: "الذي يقبض الرزق بحكمته"),
  AllahName(arabic: "الباسط", transliteration: "Al-Basit", english: "The Extender", french: "Celui qui étend", arabicGloss: "الذي يبسط الرزق لمن يشاء"),
  AllahName(arabic: "الخافض", transliteration: "Al-Khafid", english: "The Abaser", french: "Celui qui abaisse", arabicGloss: "الذي يخفض المتكبرين"),
  AllahName(arabic: "الرافع", transliteration: "Ar-Rafi", english: "The Exalter", french: "Celui qui élève", arabicGloss: "الذي يرفع أولياءه"),
  AllahName(arabic: "المعز", transliteration: "Al-Mu'izz", english: "The Honourer", french: "Celui qui honore", arabicGloss: "واهب العزة لمن يشاء"),
  AllahName(arabic: "المذل", transliteration: "Al-Mudhill", english: "The Dishonourer", french: "Celui qui humilie", arabicGloss: "الذي يذل أعداءه"),
  AllahName(arabic: "السميع", transliteration: "As-Sami", english: "The All-Hearing", french: "L'Audient", arabicGloss: "الذي يسمع كل شيء"),
  AllahName(arabic: "البصير", transliteration: "Al-Basir", english: "The All-Seeing", french: "Le Clairvoyant", arabicGloss: "الذي يرى كل شيء"),
  AllahName(arabic: "الحكم", transliteration: "Al-Hakam", english: "The Judge", french: "Le Juge", arabicGloss: "الحاكم العادل"),
  AllahName(arabic: "العدل", transliteration: "Al-Adl", english: "The Just", french: "Le Juste", arabicGloss: "المنزه عن الظلم"),
  AllahName(arabic: "اللطيف", transliteration: "Al-Latif", english: "The Subtle One", french: "Le Subtil", arabicGloss: "البار بعباده الرفيق بهم"),
  AllahName(arabic: "الخبير", transliteration: "Al-Khabir", english: "The All-Aware", french: "Le Parfaitement Informé", arabicGloss: "العالم ببواطن الأمور"),
  AllahName(arabic: "الحليم", transliteration: "Al-Halim", english: "The Forbearing", french: "Le Longanime", arabicGloss: "الذي لا يعجل بالعقوبة"),
  AllahName(arabic: "العظيم", transliteration: "Al-Azim", english: "The Magnificent", french: "L'Immense", arabicGloss: "ذو العظمة في كل شيء"),
  AllahName(arabic: "الغفور", transliteration: "Al-Ghafur", english: "The All-Forgiving", french: "Le Pardonneur", arabicGloss: "الساتر المغفرة لذنوب عباده"),
  AllahName(arabic: "الشكور", transliteration: "Ash-Shakur", english: "The Appreciative", french: "Le Reconnaissant", arabicGloss: "الذي يجازي على العمل القليل"),
  AllahName(arabic: "العلي", transliteration: "Al-Ali", english: "The Most High", french: "Le Très-Haut", arabicGloss: "المتعالي فوق خلقه"),
  AllahName(arabic: "الكبير", transliteration: "Al-Kabir", english: "The Most Great", french: "Le Grand", arabicGloss: "الأكبر من كل شيء"),
  AllahName(arabic: "الحفيظ", transliteration: "Al-Hafiz", english: "The Preserver", french: "Le Gardien", arabicGloss: "الحافظ لكل شيء"),
  AllahName(arabic: "المقيت", transliteration: "Al-Muqit", english: "The Sustainer", french: "Le Nourricier", arabicGloss: "الموصل لكل مخلوق قوته"),
  AllahName(arabic: "الحسيب", transliteration: "Al-Hasib", english: "The Reckoner", french: "Celui qui suffit", arabicGloss: "الكافي المحاسب"),
  AllahName(arabic: "الجليل", transliteration: "Al-Jalil", english: "The Majestic", french: "Le Majestueux", arabicGloss: "الموصوف بصفات الجلال"),
  AllahName(arabic: "الكريم", transliteration: "Al-Karim", english: "The Generous", french: "Le Généreux", arabicGloss: "كثير الخير والعطاء"),
  AllahName(arabic: "الرقيب", transliteration: "Ar-Raqib", english: "The Watchful", french: "Le Vigilant", arabicGloss: "المطلع على كل شيء"),
  AllahName(arabic: "المجيب", transliteration: "Al-Mujib", english: "The Responsive", french: "Celui qui répond", arabicGloss: "الذي يجيب من دعاه"),
  AllahName(arabic: "الواسع", transliteration: "Al-Wasi", english: "The All-Encompassing", french: "Le Vaste", arabicGloss: "الذي وسع كل شيء"),
  AllahName(arabic: "الحكيم", transliteration: "Al-Hakim", english: "The All-Wise", french: "Le Sage", arabicGloss: "المحكم لخلقه وأمره"),
  AllahName(arabic: "الودود", transliteration: "Al-Wadud", english: "The Most Loving", french: "Le Très Affectueux", arabicGloss: "المحب لعباده الصالحين"),
  AllahName(arabic: "المجيد", transliteration: "Al-Majid", english: "The Most Glorious", french: "Le Glorieux", arabicGloss: "الواسع المجد والشرف"),
  AllahName(arabic: "الباعث", transliteration: "Al-Ba'ith", english: "The Resurrector", french: "Le Résurrecteur", arabicGloss: "الذي يبعث الخلق يوم القيامة"),
  AllahName(arabic: "الشهيد", transliteration: "Ash-Shahid", english: "The Witness", french: "Le Témoin", arabicGloss: "الشاهد على كل شيء"),
  AllahName(arabic: "الحق", transliteration: "Al-Haqq", english: "The Truth", french: "La Vérité", arabicGloss: "الثابت الذي لا يزول"),
  AllahName(arabic: "الوكيل", transliteration: "Al-Wakil", english: "The Trustee", french: "Le Tuteur", arabicGloss: "المتكفل بأمور عباده"),
  AllahName(arabic: "القوي", transliteration: "Al-Qawiyy", english: "The Strong", french: "Le Fort", arabicGloss: "كامل القوة"),
  AllahName(arabic: "المتين", transliteration: "Al-Matin", english: "The Firm", french: "Le Ferme", arabicGloss: "شديد القوة لا يلحقه تعب"),
  AllahName(arabic: "الولي", transliteration: "Al-Waliyy", english: "The Protecting Friend", french: "L'Allié", arabicGloss: "الناصر المتولي أمور عباده"),
  AllahName(arabic: "الحميد", transliteration: "Al-Hamid", english: "The Praiseworthy", french: "Le Louable", arabicGloss: "المستحق للحمد دائمًا"),
  AllahName(arabic: "المحصي", transliteration: "Al-Muhsi", english: "The Counter", french: "Celui qui dénombre", arabicGloss: "الذي أحصى كل شيء عددًا"),
  AllahName(arabic: "المبدئ", transliteration: "Al-Mubdi", english: "The Initiator", french: "L'Initiateur premier", arabicGloss: "الذي بدأ الخلق"),
  AllahName(arabic: "المعيد", transliteration: "Al-Mu'id", english: "The Restorer", french: "Le Restaurateur", arabicGloss: "الذي يعيد الخلق بعد الموت"),
  AllahName(arabic: "المحيي", transliteration: "Al-Muhyi", english: "The Giver of Life", french: "Celui qui donne la vie", arabicGloss: "واهب الحياة"),
  AllahName(arabic: "المميت", transliteration: "Al-Mumit", english: "The Bringer of Death", french: "Celui qui donne la mort", arabicGloss: "مقدّر الموت على خلقه"),
  AllahName(arabic: "الحي", transliteration: "Al-Hayy", english: "The Ever-Living", french: "Le Vivant", arabicGloss: "الدائم الحياة بلا زوال"),
  AllahName(arabic: "القيوم", transliteration: "Al-Qayyum", english: "The Self-Subsisting", french: "Le Subsistant", arabicGloss: "القائم بنفسه المقيم لغيره"),
  AllahName(arabic: "الواجد", transliteration: "Al-Wajid", english: "The Perceiver", french: "Celui qui trouve", arabicGloss: "الغني الذي لا يفتقر"),
  AllahName(arabic: "الماجد", transliteration: "Al-Majid (Al-Maajid)", english: "The Illustrious", french: "L'Illustre", arabicGloss: "الواسع الكرم والمجد"),
  AllahName(arabic: "الواحد", transliteration: "Al-Wahid", english: "The One", french: "L'Unique", arabicGloss: "المتفرد بالألوهية"),
  AllahName(arabic: "الأحد", transliteration: "Al-Ahad", english: "The Unique", french: "L'Un", arabicGloss: "المتفرد بصفات الكمال"),
  AllahName(arabic: "الصمد", transliteration: "As-Samad", english: "The Eternal Refuge", french: "L'Éternel", arabicGloss: "السيد المقصود في الحوائج"),
  AllahName(arabic: "القادر", transliteration: "Al-Qadir", english: "The Capable", french: "Le Capable", arabicGloss: "التام القدرة"),
  AllahName(arabic: "المقتدر", transliteration: "Al-Muqtadir", english: "The Powerful", french: "Le Puissant", arabicGloss: "الكامل القدرة لا يمتنع عليه شيء"),
  AllahName(arabic: "المقدم", transliteration: "Al-Muqaddim", english: "The Expediter", french: "Celui qui avance", arabicGloss: "الذي يقدم من يشاء"),
  AllahName(arabic: "المؤخر", transliteration: "Al-Mu'akhkhir", english: "The Delayer", french: "Celui qui retarde", arabicGloss: "الذي يؤخر من يشاء بحكمته"),
  AllahName(arabic: "الأول", transliteration: "Al-Awwal", english: "The First", french: "Le Premier", arabicGloss: "الذي ليس قبله شيء"),
  AllahName(arabic: "الآخر", transliteration: "Al-Akhir", english: "The Last", french: "Le Dernier", arabicGloss: "الذي ليس بعده شيء"),
  AllahName(arabic: "الظاهر", transliteration: "Az-Zahir", english: "The Manifest", french: "L'Apparent", arabicGloss: "الظاهر بآياته ودلائله"),
  AllahName(arabic: "الباطن", transliteration: "Al-Batin", english: "The Hidden", french: "Le Caché", arabicGloss: "المحتجب عن أنظار الخلق"),
  AllahName(arabic: "الوالي", transliteration: "Al-Wali", english: "The Governor", french: "Le Gouverneur", arabicGloss: "المالك للأشياء المتصرف فيها"),
  AllahName(arabic: "المتعالي", transliteration: "Al-Muta'ali", english: "The Most Exalted", french: "Le Très Élevé", arabicGloss: "المنزه عن كل سوء"),
  AllahName(arabic: "البر", transliteration: "Al-Barr", english: "The Source of Goodness", french: "Le Bienfaisant", arabicGloss: "الكثير الإحسان واللطف"),
  AllahName(arabic: "التواب", transliteration: "At-Tawwab", english: "The Acceptor of Repentance", french: "L'Accueillant au repentir", arabicGloss: "الذي يقبل التوبة دائمًا"),
  AllahName(arabic: "المنتقم", transliteration: "Al-Muntaqim", english: "The Avenger", french: "Le Vengeur", arabicGloss: "الذي ينتقم ممن عصاه"),
  AllahName(arabic: "العفو", transliteration: "Al-Afuww", english: "The Pardoner", french: "L'Indulgent", arabicGloss: "الذي يمحو السيئات"),
  AllahName(arabic: "الرؤوف", transliteration: "Ar-Ra'uf", english: "The Most Kind", french: "Le Compatissant", arabicGloss: "شديد الرحمة بعباده"),
  AllahName(arabic: "مالك الملك", transliteration: "Malik-ul-Mulk", english: "Master of the Kingdom", french: "Maître de la Royauté", arabicGloss: "يؤتي الملك من يشاء"),
  AllahName(arabic: "ذو الجلال والإكرام", transliteration: "Dhul-Jalali wal-Ikram", english: "Lord of Majesty and Honour", french: "Détenteur de la Majesté et de l'Honneur", arabicGloss: "المستحق وحده للتعظيم"),
  AllahName(arabic: "المقسط", transliteration: "Al-Muqsit", english: "The Equitable", french: "L'Équitable", arabicGloss: "العادل في حكمه"),
  AllahName(arabic: "الجامع", transliteration: "Al-Jami", english: "The Gatherer", french: "Le Rassembleur", arabicGloss: "الذي يجمع الخلق ليوم الحساب"),
  AllahName(arabic: "الغني", transliteration: "Al-Ghaniyy", english: "The Self-Sufficient", french: "L'Indépendant", arabicGloss: "المستغني عن كل ما سواه"),
  AllahName(arabic: "المغني", transliteration: "Al-Mughni", english: "The Enricher", french: "Celui qui enrichit", arabicGloss: "الذي يغني من يشاء"),
  AllahName(arabic: "المانع", transliteration: "Al-Mani", english: "The Preventer", french: "Celui qui empêche", arabicGloss: "الذي يمنع العطاء عمن يشاء"),
  AllahName(arabic: "الضار", transliteration: "Ad-Darr", english: "The Distresser", french: "Celui qui nuit", arabicGloss: "الذي يقدّر الضر على من يشاء"),
  AllahName(arabic: "النافع", transliteration: "An-Nafi", english: "The Benefactor", french: "Le Bienfaiteur", arabicGloss: "الذي يقدّر النفع لمن يشاء"),
  AllahName(arabic: "النور", transliteration: "An-Nur", english: "The Light", french: "La Lumière", arabicGloss: "نور السماوات والأرض"),
  AllahName(arabic: "الهادي", transliteration: "Al-Hadi", english: "The Guide", french: "Le Guide", arabicGloss: "الذي يهدي من يشاء"),
  AllahName(arabic: "البديع", transliteration: "Al-Badi", english: "The Incomparable", french: "L'Inventeur", arabicGloss: "المبدع الخلق على غير مثال"),
  AllahName(arabic: "الباقي", transliteration: "Al-Baqi", english: "The Everlasting", french: "L'Éternel subsistant", arabicGloss: "الدائم الوجود بلا فناء"),
  AllahName(arabic: "الوارث", transliteration: "Al-Warith", english: "The Inheritor", french: "L'Héritier", arabicGloss: "الباقي بعد فناء الخلق"),
  AllahName(arabic: "الرشيد", transliteration: "Ar-Rashid", english: "The Guide to the Right Path", french: "Le Guide droit", arabicGloss: "المرشد إلى مصالح العباد"),
  AllahName(arabic: "الصبور", transliteration: "As-Sabur", english: "The Patient", french: "Le Patient", arabicGloss: "الذي لا يعجل بعقوبة العصاة"),
];

/// Searchable list of the 99 Names (v2.3.0), opened from the Home
/// screen. Mirrors the iOS NamesOfAllahView.
class NamesOfAllahPage extends StatefulWidget {
  const NamesOfAllahPage({super.key});

  @override
  State<NamesOfAllahPage> createState() => _NamesOfAllahPageState();
}

class _NamesOfAllahPageState extends State<NamesOfAllahPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final language = LanguageState.current;
    final filtered = <(int, AllahName)>[
      for (var i = 0; i < namesOfAllah.length; i++)
        if (_query.isEmpty ||
            namesOfAllah[i].transliteration.toLowerCase().contains(_query.toLowerCase()) ||
            namesOfAllah[i].english.toLowerCase().contains(_query.toLowerCase()) ||
            namesOfAllah[i].arabic.contains(_query))
          (i, namesOfAllah[i]),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(S.t('namesOfAllah'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: S.t('namesSearch'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final (index, name) = filtered[i];
                return ListTile(
                  leading: SizedBox(
                    width: 28,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(name.transliteration),
                  subtitle: Text(name.meaning(language)),
                  trailing: Text(
                    name.arabic,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

import 'hijri_calendar.dart';
import 'prayer_models.dart';
import 'strings.dart';

// Quran quote of the day (v1.1.1): an embedded list of verses — the
// Arabic text plus English and French renderings — so the feature
// works fully offline and nothing is ever fetched. Ported from the
// iOS app (Shared/PrayerModels.swift); keep the two lists in sync.

class DailyVerse {
  final String arabic;
  final String english;
  final String french;

  /// Transliterated surah name (used for English and French).
  final String surahEnglish;
  final String surahArabic;
  final int chapter;
  final int verse;

  const DailyVerse({
    required this.arabic,
    required this.english,
    required this.french,
    required this.surahEnglish,
    required this.surahArabic,
    required this.chapter,
    required this.verse,
  });

  /// The translation to show under the Arabic. Arabic readers get
  /// the verse itself, so there is no second line for them.
  String? translation(AppLanguage language) => switch (language) {
        AppLanguage.en => english,
        AppLanguage.fr => french,
        AppLanguage.ar => null,
      };

  /// e.g. "Surah Al-Baqarah · 2:152" / "سورة البقرة · ٢:١٥٢".
  String reference(AppLanguage language) {
    final name = language == AppLanguage.ar ? surahArabic : surahEnglish;
    var numbers = '$chapter:$verse';
    if (language == AppLanguage.ar) {
      numbers = UmmAlQuraCalendar.arabicDigits(numbers);
    }
    return '${S.t('surah')} $name · $numbers';
  }
}

const List<DailyVerse> dailyVerses = [
  DailyVerse(
    arabic: 'فَاذْكُرُونِي أَذْكُرْكُمْ وَاشْكُرُوا لِي وَلَا تَكْفُرُونِ',
    english: 'Therefore remember Me, I will remember you. Give thanks to Me, and reject not Me.',
    french: 'Souvenez-vous de Moi, Je me souviendrai de vous. Soyez reconnaissants envers Moi et ne soyez pas ingrats envers Moi.',
    surahEnglish: 'Al-Baqarah', surahArabic: 'البقرة', chapter: 2, verse: 152,
  ),
  DailyVerse(
    arabic: 'لَا يُكَلِّفُ اللَّهُ نَفْسًا إِلَّا وُسْعَهَا',
    english: 'Allah tasketh not a soul beyond its scope.',
    french: "Dieu n'impose à aucune âme une charge supérieure à sa capacité.",
    surahEnglish: 'Al-Baqarah', surahArabic: 'البقرة', chapter: 2, verse: 286,
  ),
  DailyVerse(
    arabic: 'إِنَّ مَعَ الْعُسْرِ يُسْرًا',
    english: 'Lo! with hardship goeth ease.',
    french: 'Certes, avec la difficulté vient la facilité.',
    surahEnglish: 'Ash-Sharh', surahArabic: 'الشرح', chapter: 94, verse: 6,
  ),
  DailyVerse(
    arabic: 'وَمَن يَتَوَكَّلْ عَلَى اللَّهِ فَهُوَ حَسْبُهُ',
    english: 'And whosoever putteth his trust in Allah, He will suffice him.',
    french: 'Quiconque place sa confiance en Dieu, Dieu lui suffit.',
    surahEnglish: 'At-Talaq', surahArabic: 'الطلاق', chapter: 65, verse: 3,
  ),
  DailyVerse(
    arabic: 'يَا أَيُّهَا الَّذِينَ آمَنُوا اسْتَعِينُوا بِالصَّبْرِ وَالصَّلَاةِ ۚ إِنَّ اللَّهَ مَعَ الصَّابِرِينَ',
    english: 'O ye who believe! Seek help in steadfastness and prayer. Lo! Allah is with the steadfast.',
    french: 'Ô vous qui croyez ! Cherchez secours dans la patience et la prière, car Dieu est avec les patients.',
    surahEnglish: 'Al-Baqarah', surahArabic: 'البقرة', chapter: 2, verse: 153,
  ),
  DailyVerse(
    arabic: 'وَلَا تَهِنُوا وَلَا تَحْزَنُوا وَأَنتُمُ الْأَعْلَوْنَ إِن كُنتُم مُّؤْمِنِينَ',
    english: 'Faint not nor grieve, for ye will overcome them if ye are (indeed) believers.',
    french: 'Ne faiblissez pas et ne vous affligez pas, car vous aurez le dessus si vous êtes croyants.',
    surahEnglish: 'Aal-e-Imran', surahArabic: 'آل عمران', chapter: 3, verse: 139,
  ),
  DailyVerse(
    arabic: 'لَئِن شَكَرْتُمْ لَأَزِيدَنَّكُمْ',
    english: 'If ye give thanks, I will give you more.',
    french: "Si vous êtes reconnaissants, J'augmenterai très certainement Mes bienfaits pour vous.",
    surahEnglish: 'Ibrahim', surahArabic: 'إبراهيم', chapter: 14, verse: 7,
  ),
  DailyVerse(
    arabic: 'إِنِّي قَرِيبٌ ۖ أُجِيبُ دَعْوَةَ الدَّاعِ إِذَا دَعَانِ',
    english: 'I am near. I answer the prayer of the suppliant when he crieth unto Me.',
    french: "Je suis proche. Je réponds à l'appel de celui qui M'invoque quand il M'invoque.",
    surahEnglish: 'Al-Baqarah', surahArabic: 'البقرة', chapter: 2, verse: 186,
  ),
  DailyVerse(
    arabic: 'لَا تَقْنَطُوا مِن رَّحْمَةِ اللَّهِ ۚ إِنَّ اللَّهَ يَغْفِرُ الذُّنُوبَ جَمِيعًا',
    english: 'Despair not of the mercy of Allah, Who forgiveth all sins.',
    french: 'Ne désespérez pas de la miséricorde de Dieu, car Dieu pardonne tous les péchés.',
    surahEnglish: 'Az-Zumar', surahArabic: 'الزمر', chapter: 39, verse: 53,
  ),
  DailyVerse(
    arabic: 'وَالَّذِينَ جَاهَدُوا فِينَا لَنَهْدِيَنَّهُمْ سُبُلَنَا ۚ وَإِنَّ اللَّهَ لَمَعَ الْمُحْسِنِينَ',
    english: 'As for those who strive in Us, We surely guide them to Our paths. And lo! Allah is with the good.',
    french: 'Ceux qui luttent pour Notre cause, Nous les guiderons sur Nos sentiers. Dieu est certes avec ceux qui font le bien.',
    surahEnglish: 'Al-Ankabut', surahArabic: 'العنكبوت', chapter: 29, verse: 69,
  ),
  DailyVerse(
    arabic: 'وَعَسَىٰ أَن تَكْرَهُوا شَيْئًا وَهُوَ خَيْرٌ لَّكُمْ',
    english: 'It may be that ye hate a thing, and it is good for you.',
    french: 'Il se peut que vous détestiez une chose alors qu\'elle est bonne pour vous.',
    surahEnglish: 'Al-Baqarah', surahArabic: 'البقرة', chapter: 2, verse: 216,
  ),
  DailyVerse(
    arabic: 'وَقُل رَّبِّ زِدْنِي عِلْمًا',
    english: 'And say: My Lord! Increase me in knowledge.',
    french: 'Et dis : Mon Seigneur, augmente ma connaissance.',
    surahEnglish: 'Ta-Ha', surahArabic: 'طه', chapter: 20, verse: 114,
  ),
  DailyVerse(
    arabic: 'أَلَا إِنَّ أَوْلِيَاءَ اللَّهِ لَا خَوْفٌ عَلَيْهِمْ وَلَا هُمْ يَحْزَنُونَ',
    english: 'Lo! verily the friends of Allah — no fear shall be on them, nor shall they grieve.',
    french: "En vérité, les amis de Dieu n'éprouveront ni crainte ni tristesse.",
    surahEnglish: 'Yunus', surahArabic: 'يونس', chapter: 10, verse: 62,
  ),
  DailyVerse(
    arabic: 'وَاسْتَعِينُوا بِالصَّبْرِ وَالصَّلَاةِ ۚ وَإِنَّهَا لَكَبِيرَةٌ إِلَّا عَلَى الْخَاشِعِينَ',
    english: 'Seek help in patience and prayer; and truly it is hard, save for the humble-minded.',
    french: 'Cherchez secours dans la patience et la prière ; elle est certes lourde, sauf pour ceux qui sont humbles.',
    surahEnglish: 'Al-Baqarah', surahArabic: 'البقرة', chapter: 2, verse: 45,
  ),
  DailyVerse(
    arabic: 'الَّذِينَ آمَنُوا وَتَطْمَئِنُّ قُلُوبُهُم بِذِكْرِ اللَّهِ ۗ أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ',
    english: 'Who have believed and whose hearts have rest in the remembrance of Allah. Verily in the remembrance of Allah do hearts find rest.',
    french: "Ceux qui croient et dont les cœurs s'apaisent au rappel de Dieu. N'est-ce pas au rappel de Dieu que les cœurs s'apaisent ?",
    surahEnglish: "Ar-Ra'd", surahArabic: 'الرعد', chapter: 13, verse: 28,
  ),
  DailyVerse(
    arabic: 'فَإِنَّ مَعَ الْعُسْرِ يُسْرًا',
    english: 'So, verily, with hardship goeth ease.',
    french: 'Certes, avec la difficulté vient la facilité.',
    surahEnglish: 'Ash-Sharh', surahArabic: 'الشرح', chapter: 94, verse: 5,
  ),
  DailyVerse(
    arabic: 'وَقَالَ رَبُّكُمُ ادْعُونِي أَسْتَجِبْ لَكُمْ',
    english: 'And your Lord saith: Pray unto Me and I will hear your prayer.',
    french: 'Votre Seigneur a dit : Invoquez-Moi, Je vous exaucerai.',
    surahEnglish: 'Ghafir', surahArabic: 'غافر', chapter: 40, verse: 60,
  ),
  DailyVerse(
    arabic: 'فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ',
    english: 'Which is it, of the favours of your Lord, that ye deny?',
    french: 'Lequel donc des bienfaits de votre Seigneur nierez-vous ?',
    surahEnglish: 'Ar-Rahman', surahArabic: 'الرحمن', chapter: 55, verse: 13,
  ),
  DailyVerse(
    arabic: 'إِن يَنصُرْكُمُ اللَّهُ فَلَا غَالِبَ لَكُمْ',
    english: 'If Allah is your helper, none can overcome you.',
    french: 'Si Dieu vous accorde Son secours, nul ne pourra vous vaincre.',
    surahEnglish: 'Aal-e-Imran', surahArabic: 'آل عمران', chapter: 3, verse: 160,
  ),
  DailyVerse(
    arabic: 'وَاذْكُرِ اسْمَ رَبِّكَ وَتَبَتَّلْ إِلَيْهِ تَبْتِيلًا',
    english: 'So remember the name of thy Lord, and devote thyself with a complete devotion.',
    french: 'Invoque le nom de ton Seigneur et consacre-toi entièrement à Lui.',
    surahEnglish: 'Al-Muzzammil', surahArabic: 'المزمل', chapter: 73, verse: 8,
  ),
  DailyVerse(
    arabic: 'وَمَا جَعَلَ عَلَيْكُمْ فِي الدِّينِ مِنْ حَرَجٍ',
    english: 'And He has imposed no difficulties on you in religion.',
    french: 'Et Il ne vous a imposé aucune gêne dans la religion.',
    surahEnglish: 'Al-Hajj', surahArabic: 'الحج', chapter: 22, verse: 78,
  ),
  DailyVerse(
    arabic: 'وَنُنَزِّلُ مِنَ الْقُرْآنِ مَا هُوَ شِفَاءٌ وَرَحْمَةٌ لِّلْمُؤْمِنِينَ',
    english: 'And We reveal of the Qur\'an that which is a healing and a mercy for believers.',
    french: 'Nous faisons descendre du Coran ce qui est une guérison et une miséricorde pour les croyants.',
    surahEnglish: 'Al-Isra', surahArabic: 'الإسراء', chapter: 17, verse: 82,
  ),
  DailyVerse(
    arabic: 'أَلَيْسَ اللَّهُ بِكَافٍ عَبْدَهُ',
    english: 'Is not Allah sufficient for His servant?',
    french: 'Dieu ne suffit-Il pas à Son serviteur ?',
    surahEnglish: 'Az-Zumar', surahArabic: 'الزمر', chapter: 39, verse: 36,
  ),
  DailyVerse(
    arabic: 'وَلَا تَيْأَسُوا مِن رَّوْحِ اللَّهِ ۖ إِنَّهُ لَا يَيْأَسُ مِن رَّوْحِ اللَّهِ إِلَّا الْقَوْمُ الْكَافِرُونَ',
    english: 'And despair not of the mercy of Allah. Lo! none despaireth of the mercy of Allah save disbelieving folk.',
    french: 'Ne désespérez pas de la miséricorde de Dieu, car seuls les mécréants désespèrent de la miséricorde de Dieu.',
    surahEnglish: 'Yusuf', surahArabic: 'يوسف', chapter: 12, verse: 87,
  ),
  DailyVerse(
    arabic: 'مَنْ عَمِلَ صَالِحًا مِّن ذَكَرٍ أَوْ أُنثَىٰ وَهُوَ مُؤْمِنٌ فَلَنُحْيِيَنَّهُ حَيَاةً طَيِّبَةً',
    english: 'Whosoever doeth right, whether male or female, and is a believer, him verily We shall quicken with good life.',
    french: 'Quiconque fait une bonne œuvre, homme ou femme, tout en étant croyant, Nous lui ferons vivre une vie bonne.',
    surahEnglish: 'An-Nahl', surahArabic: 'النحل', chapter: 16, verse: 97,
  ),
  DailyVerse(
    arabic: 'قُلْ هُوَ اللَّهُ أَحَدٌ',
    english: 'Say: He is Allah, the One!',
    french: 'Dis : Il est Dieu, Unique.',
    surahEnglish: 'Al-Ikhlas', surahArabic: 'الإخلاص', chapter: 112, verse: 1,
  ),
  DailyVerse(
    arabic: 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
    english: 'Thee (alone) we worship; Thee (alone) we ask for help.',
    french: "C'est Toi que nous adorons, et c'est Toi dont nous implorons le secours.",
    surahEnglish: 'Al-Fatiha', surahArabic: 'الفاتحة', chapter: 1, verse: 5,
  ),
  DailyVerse(
    arabic: 'فَمَن يَعْمَلْ مِثْقَالَ ذَرَّةٍ خَيْرًا يَرَهُ',
    english: 'Whoso doth an atom\'s weight of good will see it.',
    french: 'Quiconque fait un bien, fût-ce du poids d\'un atome, le verra.',
    surahEnglish: 'Az-Zalzalah', surahArabic: 'الزلزلة', chapter: 99, verse: 7,
  ),
  DailyVerse(
    arabic: 'لَّا إِلَٰهَ إِلَّا أَنتَ سُبْحَانَكَ إِنِّي كُنتُ مِنَ الظَّالِمِينَ',
    english: 'There is no god save Thee. Be Thou glorified! Lo! I have been a wrong-doer.',
    french: "Il n'y a de divinité que Toi. Gloire à Toi ! J'ai été parmi les injustes.",
    surahEnglish: 'Al-Anbiya', surahArabic: 'الأنبياء', chapter: 21, verse: 87,
  ),
  DailyVerse(
    arabic: 'قَالَ لَا تَخَافَا ۖ إِنَّنِي مَعَكُمَا أَسْمَعُ وَأَرَىٰ',
    english: 'Fear not. Lo! I am with you twain, Hearing and Seeing.',
    french: "N'ayez pas peur : Je suis avec vous deux, J'entends et Je vois.",
    surahEnglish: 'Ta-Ha', surahArabic: 'طه', chapter: 20, verse: 46,
  ),
];

/// The same verse all day, changing at local midnight: the local
/// calendar day (counted via UTC date components so DST can't skew
/// it) picks the verse.
DailyVerse verseOfTheDay([DateTime? now]) {
  final d = now ?? DateTime.now();
  final days = DateTime.utc(d.year, d.month, d.day)
      .difference(DateTime.utc(2024, 1, 1))
      .inDays;
  return dailyVerses[days % dailyVerses.length];
}

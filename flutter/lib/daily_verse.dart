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

// Hadith of the day (v2.3.0): an embedded list mirroring the iOS
// app's DailyHadiths — keep the two lists in sync.

class DailyHadith {
  final String arabic;
  final String english;
  final String french;
  final String sourceEnglish;
  final String sourceArabic;

  const DailyHadith({
    required this.arabic,
    required this.english,
    required this.french,
    required this.sourceEnglish,
    required this.sourceArabic,
  });

  String? translation(AppLanguage language) => switch (language) {
        AppLanguage.en => english,
        AppLanguage.fr => french,
        AppLanguage.ar => null,
      };

  String source(AppLanguage language) =>
      language == AppLanguage.ar ? sourceArabic : sourceEnglish;
}

const List<DailyHadith> dailyHadiths = [
  DailyHadith(arabic: 'إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ، وَإِنَّمَا لِكُلِّ امْرِئٍ مَا نَوَىٰ', english: 'Actions are but by intentions, and every person shall have only that which he intended.', french: 'Les actes ne valent que par leurs intentions, et chacun n\'aura que ce qu\'il a eu l\'intention de faire.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'أَحَبُّ الأَعْمَالِ إِلَى اللَّهِ أَدْوَمُهَا وَإِنْ قَلَّ', english: 'The most beloved deeds to Allah are the most consistent, even if they are small.', french: 'Les œuvres les plus aimées d\'Allah sont les plus constantes, même si elles sont petites.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'الطُّهُورُ شَطْرُ الإِيمَانِ', english: 'Purity is half of faith.', french: 'La pureté est la moitié de la foi.', sourceEnglish: 'Muslim', sourceArabic: 'مسلم'),
  DailyHadith(arabic: 'خَيْرُكُمْ مَنْ تَعَلَّمَ الْقُرْآنَ وَعَلَّمَهُ', english: 'The best among you are those who learn the Quran and teach it.', french: 'Les meilleurs d\'entre vous sont ceux qui apprennent le Coran et l\'enseignent.', sourceEnglish: 'Bukhari', sourceArabic: 'البخاري'),
  DailyHadith(arabic: 'يَسِّرُوا وَلَا تُعَسِّرُوا، وَبَشِّرُوا وَلَا تُنَفِّرُوا', english: 'Make things easy and do not make them difficult; give glad tidings and do not repel people.', french: 'Facilitez les choses et ne les rendez pas difficiles ; annoncez la bonne nouvelle et ne repoussez pas les gens.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'لَا يَرْحَمُ اللَّهُ مَنْ لَا يَرْحَمُ النَّاسَ', english: 'Allah will not show mercy to one who does not show mercy to people.', french: 'Allah ne fera pas miséricorde à celui qui ne fait pas miséricorde aux gens.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'لَيْسَ الشَّدِيدُ بِالصُّرَعَةِ، إِنَّمَا الشَّدِيدُ الَّذِي يَمْلِكُ نَفْسَهُ عِنْدَ الْغَضَبِ', english: 'The strong is not the one who overcomes people by wrestling; the strong is the one who controls himself in anger.', french: 'Le fort n\'est pas celui qui terrasse les gens à la lutte ; le fort est celui qui se maîtrise dans la colère.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'لَا يُؤْمِنُ أَحَدُكُمْ حَتَّى يُحِبَّ لِأَخِيهِ مَا يُحِبُّ لِنَفْسِهِ', english: 'None of you truly believes until he loves for his brother what he loves for himself.', french: 'Aucun de vous ne croit vraiment tant qu\'il n\'aime pas pour son frère ce qu\'il aime pour lui-même.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'مَنْ كَانَ يُؤْمِنُ بِاللَّهِ وَالْيَوْمِ الْآخِرِ فَلْيَقُلْ خَيْرًا أَوْ لِيَصْمُتْ', english: 'Whoever believes in Allah and the Last Day, let him speak good or remain silent.', french: 'Que celui qui croit en Allah et au Jour dernier dise du bien ou se taise.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'أَحَبُّ الْبِلَادِ إِلَى اللَّهِ مَسَاجِدُهَا', english: 'The most beloved places to Allah are the mosques.', french: 'Les lieux les plus aimés d\'Allah sont les mosquées.', sourceEnglish: 'Muslim', sourceArabic: 'مسلم'),
  DailyHadith(arabic: 'الْيَدُ الْعُلْيَا خَيْرٌ مِنَ الْيَدِ السُّفْلَىٰ', english: 'The upper hand is better than the lower hand.', french: 'La main qui donne est meilleure que la main qui reçoit.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'أَطْعِمُوا الْجَائِعَ، وَعُودُوا الْمَرِيضَ، وَفُكُّوا الْعَانِيَ', english: 'Feed the hungry, visit the sick, and free the captive.', french: 'Nourrissez l\'affamé, visitez le malade et libérez le captif.', sourceEnglish: 'Bukhari', sourceArabic: 'البخاري'),
  DailyHadith(arabic: 'إِنَّ اللَّهَ رَفِيقٌ يُحِبُّ الرِّفْقَ فِي الْأَمْرِ كُلِّهِ', english: 'Allah is Gentle and loves gentleness in all things.', french: 'Allah est Doux et Il aime la douceur en toute chose.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'خَيْرُكُمْ خَيْرُكُمْ لِأَهْلِهِ', english: 'The best of you is the one who is best to his family.', french: 'Le meilleur d\'entre vous est celui qui est le meilleur envers sa famille.', sourceEnglish: 'Tirmidhi', sourceArabic: 'الترمذي'),
  DailyHadith(arabic: 'الْمُسْلِمُ مَنْ سَلِمَ الْمُسْلِمُونَ مِنْ لِسَانِهِ وَيَدِهِ', english: 'A Muslim is one from whose tongue and hand other Muslims are safe.', french: 'Le musulman est celui dont les autres musulmans sont à l\'abri de la langue et de la main.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'لَا تَحَاسَدُوا وَلَا تَبَاغَضُوا، وَكُونُوا عِبَادَ اللَّهِ إِخْوَانًا', english: 'Do not envy one another and do not hate one another; be, O servants of Allah, brothers.', french: 'Ne vous enviez pas et ne vous haïssez pas ; soyez, serviteurs d\'Allah, des frères.', sourceEnglish: 'Muslim', sourceArabic: 'مسلم'),
  DailyHadith(arabic: 'لَيْسَ الْغِنَىٰ عَنْ كَثْرَةِ الْعَرَضِ، وَلَكِنَّ الْغِنَىٰ غِنَى النَّفْسِ', english: 'Richness is not having many possessions; richness is the contentment of the soul.', french: 'La richesse n\'est pas l\'abondance des biens ; la richesse est celle de l\'âme.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'مَنْ غَدَا إِلَى الْمَسْجِدِ أَوْ رَاحَ، أَعَدَّ اللَّهُ لَهُ فِي الْجَنَّةِ نُزُلًا', english: 'Whoever goes to the mosque in the morning or the evening, Allah prepares for him a place in Paradise.', french: 'Celui qui se rend à la mosquée matin ou soir, Allah lui prépare une demeure au Paradis.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'الصَّلَوَاتُ الْخَمْسُ كَفَّارَةٌ لِمَا بَيْنَهُنَّ', english: 'The five daily prayers expiate what is committed between them.', french: 'Les cinq prières quotidiennes effacent ce qui est commis entre elles.', sourceEnglish: 'Muslim', sourceArabic: 'مسلم'),
  DailyHadith(arabic: 'إِذَا مَاتَ الْإِنْسَانُ انْقَطَعَ عَمَلُهُ إِلَّا مِنْ ثَلَاثٍ: صَدَقَةٍ جَارِيَةٍ، أَوْ عِلْمٍ يُنْتَفَعُ بِهِ، أَوْ وَلَدٍ صَالِحٍ يَدْعُو لَهُ', english: 'When a person dies, his deeds end except three: ongoing charity, knowledge that benefits others, or a righteous child who prays for him.', french: 'Quand une personne meurt, ses œuvres s\'arrêtent sauf trois : une aumône continue, un savoir utile aux autres, ou un enfant vertueux qui prie pour elle.', sourceEnglish: 'Muslim', sourceArabic: 'مسلم'),
  DailyHadith(arabic: 'إِنَّ اللَّهَ كَتَبَ الْإِحْسَانَ عَلَىٰ كُلِّ شَيْءٍ', english: 'Verily Allah has prescribed excellence in all things.', french: 'Allah a prescrit l\'excellence en toute chose.', sourceEnglish: 'Muslim', sourceArabic: 'مسلم'),
  DailyHadith(arabic: 'مَنْ بَنَىٰ مَسْجِدًا لِلَّهِ، بَنَى اللَّهُ لَهُ بَيْتًا فِي الْجَنَّةِ', english: 'Whoever builds a mosque for Allah, Allah builds for him a house in Paradise.', french: 'Celui qui construit une mosquée pour Allah, Allah lui construit une maison au Paradis.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'صَلَاةُ الْجَمَاعَةِ تَفْضُلُ صَلَاةَ الْفَذِّ بِسَبْعٍ وَعِشْرِينَ دَرَجَةً', english: 'Prayer in congregation is twenty-seven degrees better than prayer prayed alone.', french: 'La prière en groupe vaut vingt-sept degrés de plus que la prière accomplie seul.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'كُلُّ بَنِي آدَمَ خَطَّاءٌ، وَخَيْرُ الْخَطَّائِينَ التَّوَّابُونَ', english: 'Every child of Adam errs, and the best of those who err are those who repent.', french: 'Tout fils d\'Adam commet des erreurs, et les meilleurs de ceux qui errent sont ceux qui se repentent.', sourceEnglish: 'Tirmidhi', sourceArabic: 'الترمذي'),
  DailyHadith(arabic: 'أَفْضَلُ الذِّكْرِ لَا إِلَهَ إِلَّا اللَّهُ', english: 'The best remembrance is: there is no god but Allah.', french: 'La meilleure invocation est : il n\'y a de dieu qu\'Allah.', sourceEnglish: 'Tirmidhi', sourceArabic: 'الترمذي'),
  DailyHadith(arabic: 'كَلِمَتَانِ خَفِيفَتَانِ عَلَى اللِّسَانِ، ثَقِيلَتَانِ فِي الْمِيزَانِ: سُبْحَانَ اللَّهِ وَبِحَمْدِهِ، سُبْحَانَ اللَّهِ الْعَظِيمِ', english: 'Two words light on the tongue and heavy in the scale: Glory be to Allah and His praise; Glory be to Allah, the Magnificent.', french: 'Deux paroles légères sur la langue et lourdes dans la balance : Gloire à Allah et louange à Lui ; Gloire à Allah, le Magnifique.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'مَثَلُ الَّذِي يَذْكُرُ رَبَّهُ وَالَّذِي لَا يَذْكُرُ رَبَّهُ مَثَلُ الْحَيِّ وَالْمَيِّتِ', english: 'The example of the one who remembers his Lord and the one who does not is like the living and the dead.', french: 'L\'exemple de celui qui invoque son Seigneur et de celui qui ne l\'invoque pas est comme le vivant et le mort.', sourceEnglish: 'Bukhari & Muslim', sourceArabic: 'البخاري ومسلم'),
  DailyHadith(arabic: 'أَكْمَلُ الْمُؤْمِنِينَ إِيمَانًا أَحْسَنُهُمْ خُلُقًا', english: 'The most complete of the believers in faith are those with the best character.', french: 'Les croyants dont la foi est la plus complète sont ceux qui ont le meilleur caractère.', sourceEnglish: 'Tirmidhi', sourceArabic: 'الترمذي'),
  DailyHadith(arabic: 'اتَّقِ اللَّهَ حَيْثُمَا كُنْتَ، وَأَتْبِعِ السَّيِّئَةَ الْحَسَنَةَ تَمْحُهَا، وَخَالِقِ النَّاسَ بِخُلُقٍ حَسَنٍ', english: 'Fear Allah wherever you are; follow a bad deed with a good one and it will erase it; and treat people with good character.', french: 'Crains Allah où que tu sois ; fais suivre la mauvaise action d\'une bonne et elle l\'effacera ; et comporte-toi envers les gens avec un bon caractère.', sourceEnglish: 'Tirmidhi', sourceArabic: 'الترمذي'),
  DailyHadith(arabic: 'دَعْ مَا يَرِيبُكَ إِلَىٰ مَا لَا يَرِيبُكَ', english: 'Leave what makes you doubt for what does not make you doubt.', french: 'Laisse ce qui te fait douter pour ce qui ne te fait pas douter.', sourceEnglish: 'Tirmidhi', sourceArabic: 'الترمذي'),
];

/// The same hadith all day, offset from the verse pick so the
/// pairing varies (mirrors the iOS +11 offset in spirit).
DailyHadith hadithOfTheDay([DateTime? now]) {
  final d = now ?? DateTime.now();
  final days = DateTime.utc(d.year, d.month, d.day)
      .difference(DateTime.utc(2024, 1, 1))
      .inDays;
  return dailyHadiths[(days + 11) % dailyHadiths.length];
}

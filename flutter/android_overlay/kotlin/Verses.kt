package com.c12n.alrashidwidget

import java.time.LocalDate
import java.time.temporal.ChronoUnit

/// Quran quote of the day data for the large home-screen widget
/// (v1.5) — the same 30 verses as the apps (Shared/PrayerModels.swift
/// and lib/daily_verse.dart), in the same order; only the fields the
/// widget shows: the Arabic text and the reference parts. Selection
/// matches the apps' day count: days since 2024-01-01, modulo 30, so
/// the widget and the app always show the same verse.
object DailyVerses {
    data class Verse(
        val arabic: String,
        val surahEnglish: String,
        val surahArabic: String,
        val chapter: Int,
        val verse: Int
    )

    val all: List<Verse> = listOf(
        Verse("فَاذْكُرُونِي أَذْكُرْكُمْ وَاشْكُرُوا لِي وَلَا تَكْفُرُونِ", "Al-Baqarah", "البقرة", 2, 152),
        Verse("لَا يُكَلِّفُ اللَّهُ نَفْسًا إِلَّا وُسْعَهَا", "Al-Baqarah", "البقرة", 2, 286),
        Verse("إِنَّ مَعَ الْعُسْرِ يُسْرًا", "Ash-Sharh", "الشرح", 94, 6),
        Verse("وَمَن يَتَوَكَّلْ عَلَى اللَّهِ فَهُوَ حَسْبُهُ", "At-Talaq", "الطلاق", 65, 3),
        Verse("يَا أَيُّهَا الَّذِينَ آمَنُوا اسْتَعِينُوا بِالصَّبْرِ وَالصَّلَاةِ ۚ إِنَّ اللَّهَ مَعَ الصَّابِرِينَ", "Al-Baqarah", "البقرة", 2, 153),
        Verse("وَلَا تَهِنُوا وَلَا تَحْزَنُوا وَأَنتُمُ الْأَعْلَوْنَ إِن كُنتُم مُّؤْمِنِينَ", "Aal-e-Imran", "آل عمران", 3, 139),
        Verse("لَئِن شَكَرْتُمْ لَأَزِيدَنَّكُمْ", "Ibrahim", "إبراهيم", 14, 7),
        Verse("إِنِّي قَرِيبٌ ۖ أُجِيبُ دَعْوَةَ الدَّاعِ إِذَا دَعَانِ", "Al-Baqarah", "البقرة", 2, 186),
        Verse("لَا تَقْنَطُوا مِن رَّحْمَةِ اللَّهِ ۚ إِنَّ اللَّهَ يَغْفِرُ الذُّنُوبَ جَمِيعًا", "Az-Zumar", "الزمر", 39, 53),
        Verse("وَالَّذِينَ جَاهَدُوا فِينَا لَنَهْدِيَنَّهُمْ سُبُلَنَا ۚ وَإِنَّ اللَّهَ لَمَعَ الْمُحْسِنِينَ", "Al-Ankabut", "العنكبوت", 29, 69),
        Verse("وَعَسَىٰ أَن تَكْرَهُوا شَيْئًا وَهُوَ خَيْرٌ لَّكُمْ", "Al-Baqarah", "البقرة", 2, 216),
        Verse("وَقُل رَّبِّ زِدْنِي عِلْمًا", "Ta-Ha", "طه", 20, 114),
        Verse("أَلَا إِنَّ أَوْلِيَاءَ اللَّهِ لَا خَوْفٌ عَلَيْهِمْ وَلَا هُمْ يَحْزَنُونَ", "Yunus", "يونس", 10, 62),
        Verse("وَاسْتَعِينُوا بِالصَّبْرِ وَالصَّلَاةِ ۚ وَإِنَّهَا لَكَبِيرَةٌ إِلَّا عَلَى الْخَاشِعِينَ", "Al-Baqarah", "البقرة", 2, 45),
        Verse("الَّذِينَ آمَنُوا وَتَطْمَئِنُّ قُلُوبُهُم بِذِكْرِ اللَّهِ ۗ أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ", "Ar-Ra'd", "الرعد", 13, 28),
        Verse("فَإِنَّ مَعَ الْعُسْرِ يُسْرًا", "Ash-Sharh", "الشرح", 94, 5),
        Verse("وَقَالَ رَبُّكُمُ ادْعُونِي أَسْتَجِبْ لَكُمْ", "Ghafir", "غافر", 40, 60),
        Verse("فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ", "Ar-Rahman", "الرحمن", 55, 13),
        Verse("إِن يَنصُرْكُمُ اللَّهُ فَلَا غَالِبَ لَكُمْ", "Aal-e-Imran", "آل عمران", 3, 160),
        Verse("وَاذْكُرِ اسْمَ رَبِّكَ وَتَبَتَّلْ إِلَيْهِ تَبْتِيلًا", "Al-Muzzammil", "المزمل", 73, 8),
        Verse("وَمَا جَعَلَ عَلَيْكُمْ فِي الدِّينِ مِنْ حَرَجٍ", "Al-Hajj", "الحج", 22, 78),
        Verse("وَنُنَزِّلُ مِنَ الْقُرْآنِ مَا هُوَ شِفَاءٌ وَرَحْمَةٌ لِّلْمُؤْمِنِينَ", "Al-Isra", "الإسراء", 17, 82),
        Verse("أَلَيْسَ اللَّهُ بِكَافٍ عَبْدَهُ", "Az-Zumar", "الزمر", 39, 36),
        Verse("وَلَا تَيْأَسُوا مِن رَّوْحِ اللَّهِ ۖ إِنَّهُ لَا يَيْأَسُ مِن رَّوْحِ اللَّهِ إِلَّا الْقَوْمُ الْكَافِرُونَ", "Yusuf", "يوسف", 12, 87),
        Verse("مَنْ عَمِلَ صَالِحًا مِّن ذَكَرٍ أَوْ أُنثَىٰ وَهُوَ مُؤْمِنٌ فَلَنُحْيِيَنَّهُ حَيَاةً طَيِّبَةً", "An-Nahl", "النحل", 16, 97),
        Verse("قُلْ هُوَ اللَّهُ أَحَدٌ", "Al-Ikhlas", "الإخلاص", 112, 1),
        Verse("إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ", "Al-Fatiha", "الفاتحة", 1, 5),
        Verse("فَمَن يَعْمَلْ مِثْقَالَ ذَرَّةٍ خَيْرًا يَرَهُ", "Az-Zalzalah", "الزلزلة", 99, 7),
        Verse("لَّا إِلَٰهَ إِلَّا أَنتَ سُبْحَانَكَ إِنِّي كُنتُ مِنَ الظَّالِمِينَ", "Al-Anbiya", "الأنبياء", 21, 87),
        Verse("قَالَ لَا تَخَافَا ۖ إِنَّنِي مَعَكُمَا أَسْمَعُ وَأَرَىٰ", "Ta-Ha", "طه", 20, 46),
    )

    fun verseFor(date: LocalDate): Verse {
        val days = ChronoUnit.DAYS.between(LocalDate.of(2024, 1, 1), date)
        val index = ((days % all.size) + all.size) % all.size
        return all[index.toInt()]
    }

    /// e.g. "Surah Al-Baqarah · 2:152" / "سورة البقرة · ٢:١٥٢".
    fun reference(verse: Verse, language: String): String {
        val name = if (language == "ar") verse.surahArabic else verse.surahEnglish
        var numbers = "${verse.chapter}:${verse.verse}"
        if (language == "ar") numbers = arabicDigits(numbers)
        return "${surahWord(language)} $name · $numbers"
    }

    private fun surahWord(language: String): String = when (language) {
        "ar" -> "سورة"
        "fr" -> "Sourate"
        else -> "Surah"
    }

    private fun arabicDigits(input: String): String {
        val digits = "٠١٢٣٤٥٦٧٨٩"
        return input.map { ch -> if (ch in '0'..'9') digits[ch - '0'] else ch }
            .joinToString("")
    }
}

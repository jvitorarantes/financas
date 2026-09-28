import 'package:intl/intl.dart';

abstract final class Dates {
  static final _day = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final _dayShort = DateFormat("d 'de' MMM", 'pt_BR');
  static final _month = DateFormat("MMMM 'de' yyyy", 'pt_BR');

  static DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime firstOfMonth(DateTime d) => DateTime(d.year, d.month);
  static DateTime lastOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);
  static DateTime addMonths(DateTime d, int months) {
    final target = DateTime(d.year, d.month + months);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(target.year, target.month, d.day > lastDay ? lastDay : d.day);
  }

  static int daysInMonth(DateTime d) => lastOfMonth(d).day;

  /// "2026-09-28"
  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime parseIso(String s) {
    final p = s.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  static String format(DateTime d) => _day.format(d);
  static String formatShort(DateTime d) => _dayShort.format(d);

  static String monthLabel(DateTime d) {
    final s = _month.format(d);
    return s[0].toUpperCase() + s.substring(1);
  }

  /// "Hoje", "Ontem" ou a data.
  static String relative(DateTime d) {
    final diff = dateOnly(d).difference(today()).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == -1) return 'Ontem';
    if (diff == 1) return 'Amanhã';
    return format(d);
  }
}

import 'package:intl/intl.dart';

/// v1 formats, kept: "M/d/y, HH:mm" and "X min, Y sec".
String formatDateTime(DateTime? t) => t == null ? '' : DateFormat('M/d/y, HH:mm').format(t.toLocal());

String formatDurationLong(double? seconds) {
  final s = (seconds ?? 0).round();
  return '${s ~/ 60} min, ${s % 60} sec';
}

/// "m:ss" / "h:mm:ss" for players and chapters.
String formatClock(double seconds) {
  final s = seconds.isFinite ? seconds.round() : 0;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

/// Single-emoji check from v1 (icon dialog).
final RegExp singleEmoji = RegExp(
  r'^(?:[\uD800-\uDBFF][\uDC00-\uDFFF]|[☀-➿]|[️‍♀-♂⚕-⚖✈-✉✒-✔✖-✗✡-✨✳-✴❄-❇❓-❕❤-❥➕-➗➡-➰⤴-⤵⬅-⬇⬛-⬜⭐-⭕〰〽㊗㊙]|[-]|[\uD83C-\uDBFF][\uDC00-\uDFFF])+$',
);

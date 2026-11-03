import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  test('probe: vi_VN format output', () async {
    await initializeDateFormatting('vi_VN', null);
    // ignore: avoid_print
    print('FULL=${DateFormat('EEEE, d/M/yyyy', 'vi_VN').format(DateTime(2026, 10, 22))}');
    // ignore: avoid_print
    print('SHORT=${DateFormat('d/M/y', 'vi_VN').format(DateTime(2026, 10, 22))}');
    for (var i = 1; i <= 7; i++) {
      final day = DateTime(2026, 10, 19 + i);
      // ignore: avoid_print
      print('WD$i=${day.weekday} ${DateFormat('EEEE', 'vi_VN').format(day)}');
    }
  });
}

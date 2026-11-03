import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/models/home_models.dart';

void main() {
  group('WeekdayUtils', () {
    test('toAppWeekday chuyển DateTime.weekday sang quy ước T2=2..CN=8', () {
      // 19/10/2026 là thứ Hai.
      final monday = DateTime(2026, 10, 19);
      expect(monday.weekday, 1);
      expect(WeekdayUtils.toAppWeekday(monday), 2);

      // 22/10/2026 là thứ Năm.
      final thursday = DateTime(2026, 10, 22);
      expect(thursday.weekday, 4);
      expect(WeekdayUtils.toAppWeekday(thursday), 5);

      // Chủ nhật.
      final sunday = DateTime(2026, 10, 25);
      expect(sunday.weekday, 7);
      expect(WeekdayUtils.toAppWeekday(sunday), 8);
    });

    test('toDateTimeWeekday là nghịch đảo của toAppWeekday', () {
      for (var appWeekday = 2; appWeekday <= 8; appWeekday++) {
        expect(WeekdayUtils.toDateTimeWeekday(appWeekday), appWeekday - 1);
      }
    });

    test('shortName / fullName trả về đúng tên ngày', () {
      expect(WeekdayUtils.shortName(2), 'T2');
      expect(WeekdayUtils.shortName(5), 'T5');
      expect(WeekdayUtils.shortName(8), 'CN');
      expect(WeekdayUtils.fullName(2), 'Thứ hai');
      expect(WeekdayUtils.fullName(8), 'Chủ nhật');

      // Ngoài khoảng hợp lệ thì trả về chuỗi rỗng.
      expect(WeekdayUtils.shortName(1), '');
      expect(WeekdayUtils.shortName(9), '');
      expect(WeekdayUtils.fullName(0), '');
    });

    test('parseDays chuẩn hoá list/số và loại bỏ giá trị không hợp lệ', () {
      expect(WeekdayUtils.parseDays([2, 4, 6]), {2, 4, 6});
      expect(WeekdayUtils.parseDays('3'), {3});
      expect(WeekdayUtils.parseDays([1, 9, 'abc']), isEmpty);
      expect(WeekdayUtils.parseDays(null), isEmpty);
    });

    test('describeDays sắp xếp ngày tăng dần', () {
      expect(WeekdayUtils.describeDays([6, 2, 4]), 'T2, T4, T6');
      expect(WeekdayUtils.describeDays(null), 'Chưa chọn ngày');
    });

    test('parseTime / formatTime xử lý chuỗi giờ', () {
      expect(WeekdayUtils.parseTime('07:30')?.hour, 7);
      expect(WeekdayUtils.parseTime('07:30')?.minute, 30);
      expect(WeekdayUtils.parseTime('07:30:00')?.minute, 30);
      expect(WeekdayUtils.parseTime('abc'), isNull);
      expect(WeekdayUtils.parseTime('12'), isNull);

      expect(WeekdayUtils.formatTime(const TimeOfDay(hour: 7, minute: 5)), '07:05');
      expect(WeekdayUtils.formatTime(const TimeOfDay(hour: 14, minute: 0)), '14:00');
    });
  });
}
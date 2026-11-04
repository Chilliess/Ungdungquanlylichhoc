import '../services/study_data.dart';
import 'package:untitled/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import '../auth/loginscreen.dart';
import '../services/app_preferences.dart';
import 'info_account.dart';
import 'schedule_announcement.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isImporting = false;

  // 1. Hàm phân tích ngày tháng thông minh từ Excel
  String _parseExcelDate(dynamic rawValue) {
    if (rawValue == null) return DateTime.now().toIso8601String().split('T')[0];

    String valStr = rawValue.toString().trim();

    // Xử lý số Serial nguyên thủy của Excel (VD: 45292)
    if (double.tryParse(valStr) != null &&
        !valStr.contains('-') &&
        !valStr.contains('/')) {
      double days = double.parse(valStr);
      DateTime baseDate = DateTime(1899, 12, 30);
      DateTime parsed = baseDate.add(Duration(days: days.toInt()));
      return parsed.toIso8601String().split('T')[0];
    }

    // Xử lý định dạng dd/MM/yyyy hoặc d/M/yyyy
    if (valStr.contains('/')) {
      List<String> parts = valStr.split('/');
      if (parts.length == 3) {
        String day = parts[0].trim().padLeft(2, '0');
        String month = parts[1].trim().padLeft(2, '0');
        String year = parts[2].trim();
        if (year.length == 2) year = '20$year';
        return '$year-$month-$day';
      }
    }

    // Xử lý định dạng dd-MM-yyyy
    if (valStr.contains('-')) {
      List<String> parts = valStr.split('-');
      if (parts.length == 3 && parts[0].length <= 2) {
        String day = parts[0].trim().padLeft(2, '0');
        String month = parts[1].trim().padLeft(2, '0');
        String year = parts[2].trim();
        if (year.length == 2) year = '20$year';
        return '$year-$month-$day';
      }
    }

    return valStr;
  }

  // 2. Hàm phân tích giờ linh hoạt (7:30 -> 07:30:00)
  String _parseExcelTime(dynamic rawValue, String defaultTime) {
    if (rawValue == null) return defaultTime;
    String valStr = rawValue.toString().trim();
    if (valStr.isEmpty) return defaultTime;

    if (valStr.length == 4) valStr = '0$valStr'; // '7:30' -> '07:30'
    if (valStr.length == 5) valStr = '$valStr:00'; // '07:30' -> '07:30:00'

    return valStr;
  }

  // 3. Hàm xử lý đọc file CSV
  Future<void> _importScheduleFromCsv() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (!mounted || result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) throw 'Không thể đọc nội dung file!';

      setState(() => _isImporting = true);

      // 1. Giải mã chuỗi tiếng Việt an toàn
      String csvString;
      try {
        csvString = utf8.decode(file.bytes!);
      } catch (_) {
        csvString = String.fromCharCodes(file.bytes!);
      }

      // 2. Tự động nhận diện dấu phân cách (dấu phẩy , hoặc dấu chấm phẩy ;)
      String delimiter = csvString.contains(';') ? ';' : ',';

      List<List<dynamic>> rows = CsvToListConverter(
        fieldDelimiter: delimiter,
      ).convert(csvString);

      if (rows.length <= 1) {
        throw 'File CSV trống hoặc chỉ chứa mỗi dòng tiêu đề!';
      }

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw 'Người dùng chưa đăng nhập!';

      int successCount = 0;

      for (int i = 1; i < rows.length; i++) {
        List<dynamic> row = rows[i];
        if (row.isEmpty || row.length < 2) continue;

        String subjectCode = row[0].toString().trim();
        String subjectName = row[1].toString().trim();
        if (subjectCode.isEmpty || subjectName.isEmpty) continue;

        String colorCode =
            (row.length > 2) ? row[2].toString().trim() : '#3B82F6';
        String room =
            (row.length > 3) ? row[3].toString().trim() : 'Chưa cập nhật';
        String lecturer =
            (row.length > 4) ? row[4].toString().trim() : 'Chưa cập nhật';

        String rawDayOfWeek = (row.length > 5) ? row[5].toString().trim() : '2';
        List<int> dayOfWeekList = [];
        try {
          rawDayOfWeek = rawDayOfWeek.replaceAll('[', '').replaceAll(']', '');
          dayOfWeekList =
              rawDayOfWeek.split(',').map((e) => int.parse(e.trim())).toList();
        } catch (_) {
          dayOfWeekList = [2];
        }

        String startTime =
            _parseExcelTime((row.length > 6) ? row[6] : null, '07:00:00');
        String endTime =
            _parseExcelTime((row.length > 7) ? row[7] : null, '09:00:00');

        String startDate = _parseExcelDate((row.length > 8) ? row[8] : null);
        String endDate = _parseExcelDate((row.length > 9) ? row[9] : null);

        final existingSubject = await _supabase
            .from('subjects')
            .select('id')
            .eq('user_id', userId)
            .eq('subject_code', subjectCode)
            .maybeSingle();

        String subjectId;
        if (existingSubject != null) {
          subjectId = existingSubject['id'];
        } else {
          final newSubRes = await _supabase
              .from('subjects')
              .insert({
                'user_id': userId,
                'subject_code': subjectCode,
                'subject_name': subjectName,
                'color_code': colorCode.isEmpty ? '#3B82F6' : colorCode,
              })
              .select('id')
              .single();

          subjectId = newSubRes['id'];
        }

        await _supabase.from('schedules').insert({
          'user_id': userId,
          'subject_id': subjectId,
          'room': room,
          'lecturer': lecturer,
          'day_of_week': dayOfWeekList,
          'start_time': startTime,
          'end_time': endTime,
          'start_date': startDate,
          'end_date': endDate,
        });

        successCount++;
        studyDataChanged();
      }

      if (mounted) {
        AppNotice.show(
          context,
          SnackBar(
            content:
                Text('Đã nhập thành công $successCount lịch học từ file CSV!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotice.show(
          context,
          SnackBar(
            content: Text('Lỗi nhập dữ liệu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // 4. Hộp thoại hướng dẫn chi tiết cho người dùng
  void _showInstructionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blueAccent),
            SizedBox(width: 8),
            Flexible(
                child: Text('Hướng dẫn nhập CSV',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1. Cấu trúc cột file CSV nếu làm trong Excel (từ A đến J):',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.blueAccent),
              ),
              SizedBox(height: 6),
              SelectableText(
                '• Cột A: Mã môn học (VD: INT101)\n'
                '• Cột B: Tên môn học (VD: Lập trình C)\n'
                '• Cột C: Mã màu Hex (VD: #3B82F6 hoặc để trống)\n'
                '• Cột D: Phòng học (VD: P.302)\n'
                '• Cột E: Giảng viên (VD: Nguyễn Văn A)\n'
                '• Cột F: Ngày trong tuần (VD: 2,4 hoặc [2,4] - Thứ 2, Thứ 4)\n'
                '• Cột G: Giờ bắt đầu (VD: 07:00)\n'
                '• Cột H: Giờ kết thúc (VD: 09:30)\n'
                '• Cột I: Ngày bắt đầu (VD: 2026-01-01 hoặc 01/01/2026)\n'
                '• Cột J: Ngày kết thúc (VD: 2026-06-30 hoặc 30/06/2026)',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 12),
              Text(
                '2. Lưu ý quan trọng khi Lưu file trên Excel:',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.orange),
              ),
              SizedBox(height: 6),
              Text(
                '• Dòng 1 phải ghi tiêu đề tiếng Việt:\n'
                '"Mã môn học,Tên môn học,Màu,Phòng học,Giảng viên,Ngày trong tuần,Giờ bắt đầu,Giờ kết thúc,Ngày bắt đầu,Ngày kết thúc"\n'
                '• Khi Save trong Excel, hãy chọn định dạng:\n'
                '  CSV UTF-8.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đã hiểu',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất'),
        content:
            const Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _supabase.auth.signOut();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const Loginscreen()),
            (value) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          AppNotice.show(
            context,
            SnackBar(
                content: Text('Lỗi đăng xuất: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _icon(IconData icon) => Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: .45),
          borderRadius: BorderRadius.circular(12)),
      child:
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary));

  Widget _section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title,
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: .7,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
        Material(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children)),
      ]));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(
          title: const Text('Cài đặt'),
          backgroundColor: colors.surfaceContainerLowest),
      body: _isImporting
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Đang nhập lịch học…')
            ]))
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      children: [
                        _section('TÀI KHOẢN', [
                          ListTile(
                              leading: _icon(Icons.person_outline),
                              title: const Text('Thông tin & bảo mật'),
                              subtitle: const Text(
                                  'Hồ sơ, mật khẩu và xóa tài khoản'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const AccountScreen()))),
                        ]),
                        _section('GIAO DIỆN', [
                          ListTile(
                              leading: _icon(Icons.palette_outlined),
                              title: const Text('Chủ đề'),
                              trailing: DropdownButton<ThemeMode>(
                                  value: appPreferences.theme,
                                  underline: const SizedBox.shrink(),
                                  items: const [
                                    DropdownMenuItem(
                                        value: ThemeMode.system,
                                        child: Text('Hệ thống')),
                                    DropdownMenuItem(
                                        value: ThemeMode.light,
                                        child: Text('Sáng')),
                                    DropdownMenuItem(
                                        value: ThemeMode.dark,
                                        child: Text('Tối')),
                                  ],
                                  onChanged: (value) {
                                    appPreferences.update(themeMode: value);
                                    setState(() {});
                                  })),
                          const Divider(height: 1, indent: 66),
                          ListTile(
                              leading: _icon(Icons.text_fields),
                              title: const Text('Cỡ chữ'),
                              subtitle: Slider(
                                  value: appPreferences.textScale,
                                  min: 1,
                                  max: 1.3,
                                  divisions: 3,
                                  label:
                                      '${(appPreferences.textScale * 100).round()}%',
                                  onChanged: (value) {
                                    appPreferences.update(scale: value);
                                    setState(() {});
                                  })),
                          SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              secondary: _icon(Icons.animation),
                              title: const Text('Giảm chuyển động'),
                              value: appPreferences.reduceMotion,
                              onChanged: (value) {
                                appPreferences.update(reduced: value);
                                setState(() {});
                              }),
                        ]),
                        _section('NHẮC NHỞ', [
                          ListTile(
                              leading: _icon(Icons.notifications_none),
                              title: const Text('Thiết lập nhắc lịch'),
                              subtitle: const Text(
                                  'Thời gian nhắc và quyền thông báo'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ScheduleAnnouncementScreen()))),
                        ]),
                        _section('TRỢ LÝ AI', [
                          SwitchListTile(
                              secondary: _icon(Icons.auto_awesome),
                              title: const Text('Hiện trợ lý mini'),
                              subtitle: const Text('Mở nhanh ở góc màn hình'),
                              value: appPreferences.showAssistant,
                              onChanged: (value) {
                                appPreferences.update(assistant: value);
                                setState(() {});
                              }),
                          const Padding(
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(
                                  'Chỉ nội dung bạn gửi được chuyển tới dịch vụ AI. Lịch sử lưu riêng theo tài khoản trên thiết bị này. Bạn có thể xem lại và xóa trong cửa sổ trợ lý.')),
                        ]),
                        _section('DỮ LIỆU LỊCH HỌC', [
                          ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              leading: _icon(Icons.upload_file_outlined),
                              title: const Text('Nhập lịch từ CSV'),
                              subtitle:
                                  const Text('Thêm nhiều buổi học cùng lúc'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _importScheduleFromCsv),
                          const Divider(height: 1, indent: 66, endIndent: 16),
                          ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              leading: _icon(Icons.help_outline),
                              title: const Text('Hướng dẫn nhập file'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _showInstructionDialog),
                        ]),
                        _section('THÔNG TIN', [
                          ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              leading: _icon(Icons.info_outline),
                              title: const Text('Phiên bản ứng dụng'),
                              trailing: Text('1.0.0',
                                  style: TextStyle(
                                      color: colors.onSurfaceVariant))),
                        ]),
                        OutlinedButton.icon(
                            onPressed: _signOut,
                            icon: const Icon(Icons.logout, size: 20),
                            label: const Text('Đăng xuất'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                backgroundColor: colors.surface,
                                side: BorderSide(color: colors.outlineVariant),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)))),
                      ]))),
    );
  }
}

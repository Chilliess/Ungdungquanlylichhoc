import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/loginscreen.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Hàm lưu trạng thái vào bộ nhớ máy
Future<void> _saveThemePreference(bool isDark) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('is_dark_mode', isDark);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Hàm xử lý đăng xuất
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản không?'),
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
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => Loginscreen()), (value) => false);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi đăng xuất: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt ứng dụng'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // CÀI ĐẶT CHUNG
          const Text(
            'CHUNG & TIỆN ÍCH',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueAccent),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode, color: Colors.purple),
                  title: const Text('Chế độ tối (Dark Mode)'),
                  value: themeNotifier.value == ThemeMode.dark, // Kiểm tra trạng thái hiện tại
                  activeColor: Colors.blueAccent,
                  onChanged: (bool value) async {
                    // Thay đổi trạng thái theme toàn cục
                    themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;

                    await _saveThemePreference(value);

                    setState(() {});

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(value ? 'Đã bật chế độ tối' : 'Đã tắt chế độ tối'),
                        duration: const Duration(milliseconds: 800),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // THÔNG TIN ỨNG DỤNG
          const Text(
            'THÔNG TIN',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueAccent),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline, color: Colors.blue),
                  title: Text('Phiên bản ứng dụng'),
                  trailing: Text('1.0.0', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.code, color: Colors.green),
                  title: const Text('Đồ án liên ngành / Quản lý lịch học'),
                  subtitle: const Text('Phát triển với Flutter & Supabase'),
                  onTap: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // NÚT ĐĂNG XUẤT
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất tài khoản', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: _signOut,
          ),
        ],
      ),
    );
  }
}
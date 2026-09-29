import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/screen/schedule_management_screen.dart';
import 'package:untitled/screen/subject_management_screen.dart';
import 'package:untitled/screen/view_schedule_screen.dart';

import 'auth/loginscreen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final supabase = Supabase.instance.client;
  String get formattedDate {
    return DateFormat('EEEE, \'ngày\' d/M/yyyy', 'vi_VN').format(DateTime.now());
  }
  // Hàm lấy username từ bảng profiles dựa vào id của user hiện tại
  Future<String> _fetchUsername() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return 'Khách';

    try {
      // Truy vấn vào bảng profiles
      final response = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('id', user.id)
          .single(); // Lấy ra 1 bản ghi duy nhất

      return response['username'] ?? 'Người dùng';
    } catch (e) {
      print('Lỗi lấy username: $e');
      return 'Người dùng';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Phần Chào + Username động từ Supabase
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sử dụng FutureBuilder để hiển thị username bất đồng bộ
                    FutureBuilder<String>(
                      future: _fetchUsername(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Text(
                            'Xin chào, đang tải...',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }

                        final username = snapshot.data ?? 'User';
                        return Text(
                          'Xin chào,\n$username', // Thay thế <username> ở đây[cite: 5]
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. Các nút chức năng theo giao diện mẫu của bạn
              _buildMenuCard(
                category: 'Lịch',
                title: 'Xem lịch học',
                icon: Icons.calendar_today, // Chọn icon lịch
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ViewScheduleScreen(),
                    ),
                  );
                },
              ),
              _buildMenuCard(
                category: 'Học tập',
                title: 'Quản lý môn học',
                icon: Icons.book, // Chọn icon sách môn học
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SubjectManagementScreen(),
                    ),
                  );
                },
              ),
              _buildMenuCard(
                category: 'Lịch',
                title: 'Quản lý lịch học',
                icon: Icons.schedule, // Chọn icon thời gian/lịch trình
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ScheduleManagementScreen(),
                    ),
                  );
                },
              ),
              _buildMenuCard(
                category: 'Nhắc nhở',
                title: 'Thiết lập nhắc nhở lịch học',
                icon: Icons.notifications_active, // Chọn icon chuông thông báo
                onTap: () {},
              ),
              _buildMenuCard(
                category: 'Thống kê',
                title: 'Thống kê buổi học',
                icon: Icons.bar_chart, // Chọn icon biểu đồ thống kê
                onTap: () {},
              ),
              _buildMenuCard(
                category: 'Tài khoản',
                title: 'Quản lý tài khoản',
                icon: Icons.person, // Chọn icon tài khoản cá nhân
                onTap: () {},
              ),

              ElevatedButton(
                onPressed: () async {
                  await supabase.auth.signOut();
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => Loginscreen()), (value) => false);
                },
                child: Text('Logout')
              )
            ],
          ),
        ),
      ),
    );
  }

  // Widget phụ để tái sử dụng giao diện các ô menu bo tròn
  // Widget phụ để tái sử dụng giao diện các ô menu có kèm Icon
  Widget _buildMenuCard({
    required String category,
    required String title,
    required IconData icon, // Thêm tham số nhận Icon
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black87, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Phần chữ bên trái
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ],
              ),
              // Icon trang trí ở bên phải
              Icon(
                icon,
                size: 28,
                color: const Color(0xFF4A90E2), // Đồng bộ màu xanh dương với banner bên trên
              ),
            ],
          ),
        ),
      ),
    );
  }
}
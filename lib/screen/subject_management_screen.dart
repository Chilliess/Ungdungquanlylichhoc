import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SubjectManagementScreen extends StatefulWidget {
  const SubjectManagementScreen({super.key});

  @override
  State<SubjectManagementScreen> createState() => _SubjectManagementScreenState();
}

class _SubjectManagementScreenState extends State<SubjectManagementScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _filteredSubjects = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSubjects();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  //Hàm tìm kiếm
  void _onSearchChanged() {
    final keyword = _searchController.text.toLowerCase().trim();
    setState(() {
      if (keyword.isEmpty) {
        _filteredSubjects = List.from(_subjects);
      } else {
        _filteredSubjects = _subjects.where((sub) {
          final subjectName = (sub['subject_name'] ?? '').toString().toLowerCase();
          final subjectCode = (sub['subject_code'] ?? '').toString().toLowerCase();

          return subjectName.contains(keyword) || subjectCode.contains(keyword);
        }).toList();
      }
    });
  }

  // Phần hiện các môn học
  Future<void> _fetchSubjects() async {
    try {
      setState(() => _isLoading = true);
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final res = await supabase
          .from('subjects')
          .select()
          .eq('user_id', userId)
          .order('subject_code', ascending: true);

      setState(() {
        _subjects = List<Map<String, dynamic>>.from(res);
        _onSearchChanged();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tải môn học: $e')),
      );
    }
  }

  // Danh sách các màu mẫu cho người dùng lựa chọn
  final List<Map<String, dynamic>> _colorOptions = [
    {'name': 'Xanh dương', 'color': Colors.blue, 'hex': '#2196F3'},
    {'name': 'Đỏ', 'color': Colors.red, 'hex': '#F44336'},
    {'name': 'Xanh lá', 'color': Colors.green, 'hex': '#4CAF50'},
    {'name': 'Cam', 'color': Colors.orange, 'hex': '#FF9800'},
    {'name': 'Tím', 'color': Colors.purple, 'hex': '#9C27B0'},
    {'name': 'Hồng', 'color': Colors.pink, 'hex': '#E91E63'},
    {'name': 'Xanh mòng két', 'color': Colors.teal, 'hex': '#009688'},
    {'name': 'Hổ phách', 'color': Colors.amber, 'hex': '#FFC107'},
  ];

  // Chuyển đổi mã Hex thành đối tượng Color để hiển thị
  Color _getColorFromHex(String? hexString) {
    if (hexString == null || hexString.isEmpty) return Colors.blue;
    try {
      final buffer = StringBuffer();
      if (hexString.length == 7 || hexString.length == 6) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return Colors.blue;
    }
  }

  // Hộp thoại Thêm / Sửa môn học
  void _showSubjectDialog({Map<String, dynamic>? subject}) {
    final isEditing = subject != null;
    final codeController = TextEditingController(text: subject?['subject_code'] ?? '');
    final nameController = TextEditingController(text: subject?['subject_name'] ?? '');

    // Mặc định chọn màu đầu tiên hoặc màu hiện tại nếu đang sửa
    String selectedHex = subject?['color_code'] ?? '#2196F3';

    // Hiện bảng Thêm / Sửa
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? 'Sửa thông tin môn học' : 'Thêm môn học mới'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: codeController,
                      decoration: const InputDecoration(
                        labelText: 'Mã môn học (VD: INT1001)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên môn học',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Chọn màu sắc hiển thị:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),

                    // Lưới chọn màu sắc trực quan bằng các hình tròn (CircleAvatar)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _colorOptions.map((item) {
                        final String hex = item['hex'];
                        final Color color = item['color'];
                        final bool isSelected = selectedHex == hex;

                        return GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              selectedHex = hex;
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.black : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: [
                                if (isSelected)
                                  const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                              ],
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final userId = supabase.auth.currentUser?.id;
                    if (userId == null) return;

                    final code = codeController.text.trim();
                    final name = nameController.text.trim();

                    if (code.isEmpty || name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vui lòng điền đầy đủ thông tin!')),
                      );
                      return;
                    }

                    try {
                      if (isEditing) {
                        await supabase.from('subjects').update({
                          'subject_code': code,
                          'subject_name': name,
                          'color_code': selectedHex, // Lưu mã màu Hex
                        }).eq('id', subject['id']);
                      } else {
                        await supabase.from('subjects').insert({
                          'user_id': userId,
                          'subject_code': code,
                          'subject_name': name,
                          'color_code': selectedHex, // Lưu mã màu Hex
                        });
                      }

                      Navigator.pop(context);
                      _fetchSubjects();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isEditing ? 'Đã cập nhật môn học!' : 'Đã thêm môn học thành công!')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Lỗi: $e')),
                      );
                    }
                  },
                  child: Text(isEditing ? 'Lưu' : 'Thêm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Xóa môn học
  void _deleteSubject(String subjectId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text('Xóa môn học này cũng sẽ ảnh hưởng đến lịch học liên quan. Bạn có chắc chắn muốn xóa?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase.from('subjects').delete().eq('id', subjectId);
        _fetchSubjects();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa môn học!')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xóa: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Môn học'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Thanh tìm kiếm môn học
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm theo tên hoặc mã môn học...',
                prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.grey.shade100,
                isDense: true,
              ),
            ),
          ),

          // Danh sách môn học
          Expanded(
            child: _filteredSubjects.isEmpty
                ? const Center(child: Text('Không tìm thấy môn học nào.'))
                : RefreshIndicator(
              onRefresh: _fetchSubjects,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _filteredSubjects.length,
                itemBuilder: (context, index) {
                  final sub = _filteredSubjects[index];
                  final Color subjectColor = _getColorFromHex(sub['color_code']);

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      // Hiển thị một chấm tròn màu tương ứng ở đầu dòng
                      leading: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: subjectColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        sub['subject_name'] ?? 'Tên môn học',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('Mã môn: ${sub['subject_code'] ?? 'N/A'}', style: const TextStyle(color: Colors.grey)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showSubjectDialog(subject: sub),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteSubject(sub['id']),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSubjectDialog(),
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}
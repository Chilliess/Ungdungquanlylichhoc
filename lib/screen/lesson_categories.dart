import 'confirm_action.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class LessonCategoryStore extends ChangeNotifier {
  static const defaultColor = Color(0xFFE53935);
  Color colorOf(String name);
  Future<List<String>> load();
  Future<void> create(String name, {Color? color});
  Future<void> rename(String oldName, String name, {Color? color});
  Future<void> delete(String name);
}

class SupabaseLessonCategoryStore extends LessonCategoryStore {
  SupabaseLessonCategoryStore(this.client);
  final SupabaseClient client;
  final Map<String, Color> _colors = {};
  bool _closed = false;
  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  @override
  Color colorOf(String name) =>
      _colors[name] ?? LessonCategoryStore.defaultColor;
  @override
  Future<List<String>> load() async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Vui lòng đăng nhập để quản lý nhãn.');
    final rows = await client
        .from('calendar_categories')
        .select('name, color_code')
        .eq('user_id', user.id)
        .order('name');
    if (_closed) return <String>[];
    _colors.clear();
    for (final row in rows) {
      final hex = row['color_code']?.toString().replaceFirst('#', '') ?? '';
      final value = int.tryParse(hex, radix: 16);
      _colors[row['name'].toString()] = value == null
          ? LessonCategoryStore.defaultColor
          : Color(0xFF000000 | value);
    }
    notifyListeners();
    return rows.map((row) => row['name'].toString()).toList();
  }

  Future<void> _change(String action, String name,
      {String? newName, Color? color}) async {
    try {
      await client.rpc('manage_calendar_category_color', params: {
        'p_action': action,
        'p_name': name,
        'p_new_name': newName,
        'p_color_code': color == null
            ? null
            : '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      });
      await load();
    } on PostgrestException catch (error) {
      if (['PGRST202', 'PGRST205', '42P01'].contains(error.code)) {
        throw Exception(
            'Vui lòng cập nhật chức năng nhãn trên Supabase trước.');
      }
      throw Exception(error.code == '23505'
          ? 'Tên nhãn đã tồn tại.'
          : 'Không lưu được nhãn. Vui lòng thử lại.');
    }
  }

  @override
  Future<void> create(String name, {Color? color}) =>
      _change('create', name, color: color);
  @override
  Future<void> rename(String oldName, String name, {Color? color}) =>
      _change('rename', oldName, newName: name, color: color);
  @override
  Future<void> delete(String name) => _change('delete', name);
}

/// In-memory implementation for independent editor previews and tests.
class MemoryLessonCategoryStore extends LessonCategoryStore {
  MemoryLessonCategoryStore([Iterable<String> initial = const []])
      : names = initial.toSet();
  final Set<String> names;
  final Map<String, Color> _colors = {};
  @override
  Color colorOf(String name) =>
      _colors[name] ?? LessonCategoryStore.defaultColor;
  @override
  Future<List<String>> load() async => names.toList()..sort();
  @override
  Future<void> create(String name, {Color? color}) async {
    names.add(name);
    _colors[name] = color ?? LessonCategoryStore.defaultColor;
    notifyListeners();
  }

  @override
  Future<void> rename(String oldName, String name, {Color? color}) async {
    final selected = color ?? colorOf(oldName);
    names.remove(oldName);
    _colors.remove(oldName);
    names.add(name);
    _colors[name] = selected;
    notifyListeners();
  }

  @override
  Future<void> delete(String name) async {
    names.remove(name);
    _colors.remove(name);
    notifyListeners();
  }
}

class LessonCategoryField extends StatelessWidget {
  const LessonCategoryField(
      {super.key,
      required this.value,
      required this.store,
      required this.onChanged,
      this.enabled = true,
      this.iconOnly = false});
  final String value;
  final LessonCategoryStore store;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store, builder: (context, _) => _buildField(context));

  Widget _buildField(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedColor = store.colorOf(value);
    Future<void> open() async {
      final selected = await showDialog<String>(
          context: context,
          builder: (_) => _CategoryPicker(store: store, selected: value));
      if (selected != null && context.mounted) onChanged(selected);
    }

    if (iconOnly) {
      return IconButton(
        key: const ValueKey('lesson-category-icon'),
        tooltip: value.isEmpty ? 'Chọn nhãn phân loại' : 'Nhãn: $value',
        onPressed: enabled ? open : null,
        icon: Icon(value.isEmpty ? Icons.sell_outlined : Icons.sell,
            color: value.isEmpty ? colors.onSurfaceVariant : selectedColor),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Nhãn phân loại (tùy chọn)',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      Wrap(children: [
        InputChip(
          key: const ValueKey('lesson-category-chip'),
          avatar: Icon(value.isEmpty ? Icons.sell_outlined : Icons.sell,
              size: 18,
              color: value.isEmpty ? colors.onSurfaceVariant : selectedColor),
          label: Text(value.isEmpty ? 'Chọn nhãn' : value),
          backgroundColor: value.isEmpty
              ? Colors.transparent
              : selectedColor.withValues(alpha: 0.14),
          side: BorderSide(
              color:
                  value.isEmpty ? colors.outlineVariant : Colors.transparent),
          onPressed: enabled ? open : null,
          onDeleted: enabled && value.isNotEmpty ? () => onChanged('') : null,
          deleteButtonTooltipMessage: 'Bỏ chọn nhãn',
        ),
      ]),
    ]);
  }
}

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({required this.store, required this.selected});
  final LessonCategoryStore store;
  final String selected;
  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  final _name = TextEditingController();
  final _focus = FocusNode();
  late String _selected;
  List<String> _names = [];
  String? _editing, _error;
  bool _loading = true;
  Color _color = LessonCategoryStore.defaultColor;
  static const _palette = <String, Color>{
    'Đỏ': Color(0xFFE53935),
    'Cam': Color(0xFFF57C00),
    'Vàng': Color(0xFFFBC02D),
    'Xanh lá': Color(0xFF388E3C),
    'Xanh dương': Color(0xFF1E88E5),
    'Tím': Color(0xFF7E57C2),
    'Hồng': Color(0xFFD81B60),
    'Xám': Color(0xFF607D8B),
  };
  Future<bool>? _pending;

  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
    _focus.addListener(_focusChanged);
    _load();
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _commit();
  }

  Future<void> _load() async {
    try {
      final names = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _names = {...names, if (_selected.isNotEmpty) _selected}.toList()
          ..sort();
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Không tải được nhãn. Kiểm tra kết nối và cập nhật Supabase rồi thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _commit() {
    if (_pending != null) return _pending!;
    final name = _name.text.trim();
    if (name.isEmpty) return Future.value(true);
    if (name.length > 60) {
      setState(() => _error = 'Tên nhãn tối đa 60 ký tự.');
      return Future.value(false);
    }
    if (_names
        .any((n) => n.toLowerCase() == name.toLowerCase() && n != _editing)) {
      setState(() => _error = 'Tên nhãn đã tồn tại.');
      return Future.value(false);
    }
    _pending = _write(name);
    return _pending!;
  }

  Future<bool> _write(String name) async {
    final oldName = _editing;
    try {
      if (oldName == null) {
        await widget.store.create(name, color: _color);
      } else {
        if (!await confirmAction(context,
                message: 'Lưu thay đổi cho nhãn “$oldName”?') ||
            !mounted) return false;
        await widget.store.rename(oldName, name, color: _color);
      }
      if (!mounted) return false;
      setState(() {
        if (oldName != null) _names.remove(oldName);
        _names.add(name);
        _names.sort();
        if (oldName == null || _selected == oldName) _selected = name;
        _name.clear();
        _editing = null;
        _error = null;
      });
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không lưu được nhãn. Vui lòng thử lại.');
      }
      return false;
    } finally {
      _pending = null;
    }
  }

  Future<void> _close([String? selected]) async {
    _focus.unfocus();
    if (!await _commit() || !mounted) return;
    Navigator.pop(context, selected ?? _selected);
  }

  Future<void> _delete(String name) async {
    _focus.unfocus();
    if (!await _commit() || !mounted) return;
    if (!await confirmAction(context,
            deleting: true,
            message: 'Xóa nhãn “$name” khỏi các lịch đang sử dụng?') ||
        !mounted) return;
    try {
      await widget.store.delete(name);
      if (!mounted) return;
      setState(() {
        _names.remove(name);
        if (_selected == name) _selected = '';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không xóa được nhãn. Vui lòng thử lại.');
      }
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _close();
        },
        child: Dialog(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _focus.unfocus(),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Expanded(
                          child: Text('Thẻ phân loại',
                              style: TextStyle(fontSize: 20))),
                      TextButton(
                          key: const ValueKey('category-done'),
                          onPressed: () => _close(),
                          child: const Text('Xong')),
                    ]),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      if (_selected.isNotEmpty)
                        Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _close(''),
                              icon: const Icon(Icons.label_off_outlined),
                              label: const Text('Bỏ chọn nhãn'),
                            )),
                      if (_names.isEmpty)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                                'Chưa có nhãn. Nhập tên để tạo nhãn mới.')),
                      for (final name in _names)
                        Row(children: [
                          Expanded(
                              child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.sell,
                                      color: widget.store.colorOf(name)),
                                  title: Text(name),
                                  selected: _selected == name,
                                  trailing: _selected == name
                                      ? const Icon(Icons.check)
                                      : null,
                                  onTap: () => _close(name))),
                          IconButton(
                              tooltip: 'Đổi tên $name',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                _focus.unfocus();
                                if (!await _commit() || !mounted) return;
                                setState(() {
                                  _editing = name;
                                  _name.text = name;
                                  _color = widget.store.colorOf(name);
                                });
                                _focus.requestFocus();
                              }),
                          IconButton(
                              tooltip: 'Xóa $name',
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: () => _delete(name)),
                        ]),
                      const SizedBox(height: 12),
                      TextFieldTapRegion(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                              key: const ValueKey('category-name'),
                              controller: _name,
                              focusNode: _focus,
                              maxLength: 60,
                              onTapOutside: (_) => _focus.unfocus(),
                              onSubmitted: (_) => _focus.unfocus(),
                              decoration: InputDecoration(
                                  labelText: _editing == null
                                      ? 'Nhập tên nhãn mới'
                                      : 'Đổi tên nhãn',
                                  border: const OutlineInputBorder(),
                                  errorText: _error)),
                          const SizedBox(height: 8),
                          const Text('Màu nhãn'),
                          const SizedBox(height: 4),
                          Wrap(spacing: 2, runSpacing: 2, children: [
                            for (final entry in _palette.entries)
                              SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: IconButton(
                                    key:
                                        ValueKey('category-color-${entry.key}'),
                                    tooltip: entry.key,
                                    isSelected: _color == entry.value,
                                    onPressed: () =>
                                        setState(() => _color = entry.value),
                                    icon: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                            color: entry.value,
                                            shape: BoxShape.circle),
                                        child: _color == entry.value
                                            ? Icon(Icons.check,
                                                size: 19,
                                                color: ThemeData
                                                            .estimateBrightnessForColor(
                                                                entry.value) ==
                                                        Brightness.dark
                                                    ? Colors.white
                                                    : Colors.black)
                                            : null),
                                  )),
                          ]),
                          const SizedBox(height: 8),
                        ],
                      )),
                    ],
                    if (_loading && _error != null) Text(_error!),
                  ]),
            ),
          ),
        )),
      );
}

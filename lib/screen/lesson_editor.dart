import '../services/study_data.dart';
import 'confirm_action.dart';
import '../models/schedule_recurrence.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'lesson_categories.dart';

class LessonDraft {
  const LessonDraft(
      {required this.title,
      required this.date,
      required this.start,
      required this.end,
      required this.location,
      this.notes = '',
      this.category = '',
      this.recurrence = 'none',
      this.repeatUntil});
  final String title, location, notes, category;
  final DateTime date;
  final String recurrence;
  final DateTime? repeatUntil;
  final TimeOfDay start, end;

  static String formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toSubjectParameters(
          {String? subjectId, String? scheduleId}) =>
      {
        'p_subject_id': subjectId,
        'p_schedule_id': scheduleId,
        'p_title': title.trim(),
        'p_date': DateFormat('yyyy-MM-dd').format(date),
        'p_start': formatTime(start),
        'p_end': formatTime(end),
        'p_room': location.trim(),
        'p_notes': notes.trim(),
        'p_category': category.trim(),
        'p_recurrence': recurrence,
        'p_until': recurrence == 'none' || repeatUntil == null
            ? null
            : DateFormat('yyyy-MM-dd').format(repeatUntil!),
      };

  Map<String, dynamic> toParameters(
          {String? id, bool isExam = false, DateTime? occurrenceDate}) =>
      {
        'p_id': id,
        'p_is_exam': isExam,
        'p_title': title.trim(),
        'p_date': DateFormat('yyyy-MM-dd').format(date),
        'p_start': formatTime(start),
        'p_end': formatTime(end),
        'p_room': location.trim(),
        'p_notes': notes.trim(),
        'p_category': category.trim(),
        'p_occurrence_date':
            DateFormat('yyyy-MM-dd').format(occurrenceDate ?? date),
      };
}

class LessonEditor extends StatefulWidget {
  const LessonEditor(
      {super.key,
      required this.initialDate,
      required this.onSave,
      this.initial,
      this.dialogTitle,
      this.categoryStore,
      this.onCategoriesChanged,
      this.recurring = false,
      this.manageRecurrence = false});
  final DateTime initialDate;
  final LessonDraft? initial;
  final String? dialogTitle;
  final bool recurring;
  final bool manageRecurrence;
  final LessonCategoryStore? categoryStore;
  final VoidCallback? onCategoriesChanged;
  final Future<void> Function(LessonDraft draft) onSave;

  @override
  State<LessonEditor> createState() => _LessonEditorState();
}

class _LessonEditorState extends State<LessonEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _location, _notes, _dateText;
  late final LessonCategoryStore _categoryStore;
  late String _category;
  late DateTime _date;
  late String _recurrence;
  DateTime? _repeatUntil;
  int _endPickerVersion = 0;
  TimeOfDay? _start, _end;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title);
    _location = TextEditingController(text: widget.initial?.location);
    _notes = TextEditingController(text: widget.initial?.notes);
    _recurrence = widget.initial?.recurrence ?? 'none';
    _repeatUntil = widget.initial?.repeatUntil;
    _category = widget.initial?.category ?? '';
    _categoryStore = widget.categoryStore ??
        MemoryLessonCategoryStore([if (_category.isNotEmpty) _category]);
    if (widget.categoryStore != null) {
      _categoryStore.load().catchError((_) => <String>[]);
    }
    _date = widget.initial?.date ?? widget.initialDate;
    _dateText =
        TextEditingController(text: DateFormat('dd/MM/yyyy').format(_date));
    _start = widget.initial?.start;
    _end = widget.initial?.end;
  }

  @override
  void dispose() {
    for (final controller in [_title, _location, _notes, _dateText]) {
      controller.dispose();
    }
    if (widget.categoryStore == null) _categoryStore.dispose();
    super.dispose();
  }

  bool _allowClose = false, _closing = false;
  bool get _dirty {
    final initial = widget.initial;
    return _title.text != (initial?.title ?? '') ||
        _location.text != (initial?.location ?? '') ||
        _notes.text != (initial?.notes ?? '') ||
        _category != (initial?.category ?? '') ||
        _date != (initial?.date ?? widget.initialDate) ||
        _start != initial?.start ||
        _end != initial?.end ||
        _recurrence != (initial?.recurrence ?? 'none') ||
        _repeatUntil != initial?.repeatUntil;
  }

  Future<void> _requestClose() async {
    if (_saving || _closing) return;
    _closing = true;
    final discard = !_dirty ||
        await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                        title: const Text('Bỏ thay đổi chưa lưu?'),
                        content: const Text(
                            'Thông tin vừa chỉnh sửa sẽ không được lưu.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Tiếp tục sửa')),
                          FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                  foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Bỏ thay đổi'))
                        ])) ==
            true;
    _closing = false;
    if (discard && mounted) {
      setState(() => _allowClose = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> _pickTime(bool start) async {
    final initial = (start ? _start : _end) ?? TimeOfDay.now();
    var selected = initial;
    final result = await showModalBottomSheet<TimeOfDay>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
          child: SizedBox(
        height: 290,
        child: Column(children: [
          Row(children: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy')),
            Expanded(
                child: Text(start ? 'Giờ bắt đầu' : 'Giờ kết thúc',
                    textAlign: TextAlign.center)),
            TextButton(
                key: const ValueKey('lesson-confirm-time'),
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Xong')),
          ]),
          Expanded(
              child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            use24hFormat: true,
            initialDateTime: DateTime(2026, 1, 1, initial.hour, initial.minute),
            onDateTimeChanged: (value) =>
                selected = TimeOfDay.fromDateTime(value),
          )),
        ]),
      )),
    );
    if (result != null && mounted) {
      setState(() {
        if (start) {
          _start = result;
        } else {
          _end = result;
        }
      });
      _form.currentState?.validate();
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (widget.manageRecurrence &&
        _recurrence != 'none' &&
        _repeatUntil != null &&
        _repeatUntil!.isBefore(_date)) {
      setState(() => _error = 'Ngày kết thúc lặp phải từ ngày học trở đi.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.initial != null &&
          !await confirmAction(context,
              message:
                  '${_title.text.trim()}\n${LessonDraft.formatTime(_start!)} – ${LessonDraft.formatTime(_end!)} · ${_location.text.trim()}\n${ScheduleRecurrence.labels[_recurrence]}\n\n${widget.initial?.recurrence != null && widget.initial!.recurrence != 'none' ? 'Thay đổi áp dụng cho toàn bộ chuỗi, bao gồm các buổi đã qua.' : 'Lưu thông tin lịch học này?'}')) {
        return;
      }
      if (!mounted) return;
      await widget.onSave(LessonDraft(
          title: _title.text,
          date: _date,
          start: _start!,
          end: _end!,
          location: _location.text,
          notes: _notes.text,
          category: _category,
          recurrence: _recurrence,
          repeatUntil: _recurrence == 'none' ? null : _repeatUntil));
      studyDataChanged();
      if (mounted) {
        setState(() => _allowClose = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, true);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _timeField(bool start) {
    final time = start ? _start : _end;
    return FormField<TimeOfDay>(
      validator: (_) {
        if (time == null) return 'Vui lòng chọn giờ';
        if (!start &&
            _start != null &&
            time.hour * 60 + time.minute <=
                _start!.hour * 60 + _start!.minute) {
          return 'Giờ kết thúc phải sau giờ bắt đầu';
        }
        return null;
      },
      builder: (field) => InkWell(
        key: ValueKey(start ? 'lesson-start' : 'lesson-end'),
        onTap: _saving ? null : () => _pickTime(start),
        child: InputDecorator(
          decoration: InputDecoration(
              labelText: start ? 'Bắt đầu *' : 'Kết thúc *',
              border: InputBorder.none,
              errorText: field.errorText,
              suffixIcon: const Icon(Icons.unfold_more)),
          child: Text(time == null ? 'Chọn giờ' : LessonDraft.formatTime(time)),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              letterSpacing: .6,
              color: Theme.of(context).colorScheme.onSurfaceVariant)));

  Widget _group(List<Widget> children) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children));

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: _allowClose,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _requestClose();
        },
        child: Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          insetPadding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                    key: _form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                  child: Text(
                                widget.dialogTitle ??
                                    (widget.initial == null
                                        ? 'Thêm lịch học'
                                        : 'Chỉnh sửa lịch'),
                                style: Theme.of(context).textTheme.titleLarge,
                              )),
                              IconButton(
                                  tooltip: 'Đóng',
                                  onPressed: _saving ? null : _requestClose,
                                  icon: const Icon(Icons.close)),
                            ],
                          ),
                          _sectionLabel('MÔN HỌC'),
                          _group([
                            TextFormField(
                                key: const ValueKey('lesson-title'),
                                controller: _title,
                                enabled: !_saving,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                    labelText: 'Tên môn học *',
                                    border: InputBorder.none),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Vui lòng nhập tên môn học'
                                        : null),
                            Align(
                                alignment: Alignment.centerLeft,
                                child: LessonCategoryField(
                                  key: const ValueKey('lesson-category'),
                                  iconOnly: false,
                                  value: _category,
                                  store: _categoryStore,
                                  enabled: !_saving,
                                  onChanged: (value) {
                                    if (!mounted) return;
                                    setState(() => _category = value);
                                    widget.onCategoriesChanged?.call();
                                  },
                                )),
                          ]),
                          _sectionLabel('THỜI GIAN & ĐỊA ĐIỂM'),
                          _group([
                            TextFormField(
                              key: const ValueKey('lesson-date'),
                              controller: _dateText,
                              readOnly: true,
                              enabled: !_saving,
                              onTap: () async {
                                final date = await showDatePicker(
                                    context: context,
                                    initialDate: _date,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100, 12, 31));
                                if (date != null && mounted) {
                                  setState(() {
                                    _date = date;
                                    _dateText.text =
                                        DateFormat('dd/MM/yyyy').format(date);
                                  });
                                }
                              },
                              decoration: const InputDecoration(
                                  labelText: 'Ngày học *',
                                  border: InputBorder.none,
                                  suffixIcon:
                                      Icon(Icons.calendar_today_outlined)),
                            ),
                            const SizedBox(height: 16),
                            LayoutBuilder(builder: (context, constraints) {
                              if (constraints.maxWidth < 250 ||
                                  MediaQuery.textScalerOf(context).scale(16) >
                                      22) {
                                return Column(children: [
                                  _timeField(true),
                                  const SizedBox(height: 12),
                                  _timeField(false)
                                ]);
                              }
                              return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _timeField(true)),
                                    const SizedBox(width: 16),
                                    Expanded(child: _timeField(false))
                                  ]);
                            }),
                            const SizedBox(height: 16),
                            TextFormField(
                                key: const ValueKey('lesson-location'),
                                controller: _location,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                    labelText: 'Địa điểm *',
                                    border: InputBorder.none),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Vui lòng nhập địa điểm'
                                        : null),
                          ]),
                          if (widget.manageRecurrence) ...[
                            _sectionLabel('LỊCH LẶP'),
                            _group([
                              DropdownButtonFormField<String>(
                                key: const ValueKey('lesson-recurrence'),
                                initialValue: _recurrence,
                                decoration: const InputDecoration(
                                    labelText: 'Lặp lại',
                                    border: InputBorder.none),
                                items: ScheduleRecurrence.labels.entries
                                    .map((e) => DropdownMenuItem(
                                        value: e.key, child: Text(e.value)))
                                    .toList(),
                                onChanged: _saving
                                    ? null
                                    : (value) =>
                                        setState(() => _recurrence = value!),
                              ),
                              if (_recurrence != 'none') ...[
                                const SizedBox(height: 12),
                                DropdownButtonFormField<bool>(
                                  key: ValueKey(
                                      'repeat-end-$_endPickerVersion-${_repeatUntil != null}'),
                                  initialValue: _repeatUntil != null,
                                  decoration: const InputDecoration(
                                      labelText: 'Kết thúc lặp',
                                      border: InputBorder.none),
                                  items: const [
                                    DropdownMenuItem(
                                        value: false,
                                        child: Text('Không giới hạn')),
                                    DropdownMenuItem(
                                        value: true, child: Text('Chọn ngày'))
                                  ],
                                  onChanged: _saving
                                      ? null
                                      : (value) async {
                                          if (value == false) {
                                            setState(() => _repeatUntil = null);
                                            return;
                                          }
                                          final picked = await showDatePicker(
                                              context: context,
                                              initialDate:
                                                  _repeatUntil != null &&
                                                          !_repeatUntil!
                                                              .isBefore(_date)
                                                      ? _repeatUntil!
                                                      : _date,
                                              firstDate: _date,
                                              lastDate: DateTime(2100, 12, 31));
                                          if (mounted) {
                                            setState(() {
                                              _repeatUntil =
                                                  picked ?? _repeatUntil;
                                              _endPickerVersion++;
                                            });
                                          }
                                        },
                                ),
                                if (_repeatUntil != null)
                                  TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () async {
                                              final picked =
                                                  await showDatePicker(
                                                      context: context,
                                                      initialDate: _repeatUntil!
                                                              .isBefore(_date)
                                                          ? _date
                                                          : _repeatUntil!,
                                                      firstDate: _date,
                                                      lastDate: DateTime(
                                                          2100, 12, 31));
                                              if (picked != null && mounted) {
                                                setState(() =>
                                                    _repeatUntil = picked);
                                              }
                                            },
                                      child: Text(DateFormat('dd/MM/yyyy')
                                          .format(_repeatUntil!))),
                                if (_recurrence == 'monthly' ||
                                    _recurrence == 'yearly')
                                  const Padding(
                                      padding: EdgeInsets.only(top: 8),
                                      child: Text(
                                          'Bỏ qua tháng hoặc năm không có ngày đã chọn.')),
                              ],
                            ]),
                          ],
                          ExpansionTile(
                              title: const Text('Ghi chú · tùy chọn'),
                              initiallyExpanded: _notes.text.isNotEmpty,
                              tilePadding: EdgeInsets.zero,
                              children: [
                                TextFormField(
                                    key: const ValueKey('lesson-notes'),
                                    controller: _notes,
                                    enabled: !_saving,
                                    minLines: 2,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                        labelText: 'Ghi chú (tùy chọn)',
                                        border: InputBorder.none)),
                              ]),
                          if (_error != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(_error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error))),
                        ])),
              )),
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(children: [
                    TextButton(
                        onPressed: _saving ? null : _requestClose,
                        child: const Text('Hủy')),
                    const SizedBox(width: 16),
                    Expanded(
                        child: FilledButton(
                            key: const ValueKey('lesson-save'),
                            onPressed: _saving ? null : _save,
                            child: Text(_saving
                                ? 'Đang lưu…'
                                : widget.initial == null
                                    ? 'Tạo lịch'
                                    : 'Lưu thay đổi'))),
                  ])),
            ]),
          ),
        ));
  }
}

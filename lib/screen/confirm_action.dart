import 'package:flutter/material.dart';

Future<bool> confirmAction(BuildContext context,
        {required String message, bool deleting = false}) async =>
    await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(deleting ? 'Xác nhận xóa' : 'Xác nhận thay đổi'),
              content: Text(message),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Hủy')),
                FilledButton(
                    key: const ValueKey('confirm-action'),
                    style: deleting
                        ? FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white)
                        : null,
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(deleting ? 'Xóa' : 'Xác nhận')),
              ],
            )) ??
    false;

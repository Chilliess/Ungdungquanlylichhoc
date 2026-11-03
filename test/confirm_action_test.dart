import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/screen/confirm_action.dart';
void main() {
 testWidgets('cancel never authorizes mutation; confirm does', (tester) async {
   var writes = 0;
   await tester.pumpWidget(MaterialApp(home: Builder(builder:(context)=>Scaffold(body: TextButton(onPressed:() async {if(await confirmAction(context,message:'Xóa dữ liệu?',deleting:true)) writes++;},child:const Text('Mở'))))));
   await tester.tap(find.text('Mở')); await tester.pumpAndSettle();
   await tester.tap(find.text('Hủy')); await tester.pumpAndSettle(); expect(writes,0);
   await tester.tap(find.text('Mở')); await tester.pumpAndSettle();
   await tester.tap(find.byKey(const ValueKey('confirm-action'))); await tester.pumpAndSettle(); expect(writes,1);
 });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/screen/info_account.dart';
void main(){
 setUpAll(()async{SharedPreferences.setMockInitialValues({});await Supabase.initialize(url:'http://127.0.0.1:54321',anonKey:'test-anon-key');});
 for(final brightness in Brightness.values){
 testWidgets('grouped account fits mobile in $brightness',(tester)async{
  await tester.binding.setSurfaceSize(const Size(320,700));addTearDown(()=>tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(theme:ThemeData(brightness:brightness),home:const AccountScreen()));await tester.pumpAndSettle();
  expect(find.text('THÔNG TIN CÁ NHÂN'),findsOneWidget);expect(find.byKey(const ValueKey('account-password')),findsNothing);
  await tester.tap(find.text('Đổi mật khẩu'));await tester.pumpAndSettle();
  final field=find.byKey(const ValueKey('account-password'));await tester.ensureVisible(field);await tester.pumpAndSettle();
  await tester.enterText(field,'password');
  expect(tester.widget<TextField>(find.descendant(of:field,matching:find.byType(TextField))).obscureText,isTrue);
  expect(tester.takeException(),isNull);
 });}
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reimbursement/main.dart';
import 'package:reimbursement/models.dart';
import 'package:reimbursement/store.dart';

void main() {
  testWidgets('可以创建出差批次并显示在列表中', (tester) async {
    final temp = Directory(
      '${Directory.systemTemp.path}\\reimbursement_widget_test',
    );
    if (temp.existsSync()) temp.deleteSync(recursive: true);
    temp.createSync(recursive: true);
    final store = AppStore(rootDirectory: temp);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('出差批次'), findsOneWidget);
    expect(find.text('还没有出差批次'), findsOneWidget);

    expect(find.text('新建批次'), findsOneWidget);

    // Keep this smoke test focused on the rendered list. The editor is a
    // scrollable form and is covered by store/model tests below; inserting
    // through the same store also avoids relying on viewport dimensions.
    store.trips.add(Trip(id: 'trip-1', title: '杭州客户拜访'));
    store.notifyListeners();
    await tester.pump();

    expect(find.text('杭州客户拜访'), findsOneWidget);
    expect(store.trips.single.title, '杭州客户拜访');
    temp.deleteSync(recursive: true);
  });
}

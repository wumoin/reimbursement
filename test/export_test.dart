import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reimbursement/export_service.dart';
import 'package:reimbursement/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('导出会使用博朗模板并生成图片凭证文档', () async {
    final root = Directory(
      '${Directory.systemTemp.path}\\reimbursement_export_test',
    );
    if (root.existsSync()) root.deleteSync(recursive: true);
    root.createSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final trip = Trip(
      id: 'trip-1',
      title: '杭州客户拜访',
      destination: '杭州',
      reason: '客户现场支持',
    );
    final receipt = File('${root.path}\\receipt.png');
    await receipt.writeAsBytes(
      await File('web/icons/Icon-192.png').readAsBytes(),
      flush: true,
    );
    final expense = Expense(
      id: 'expense-1',
      tripId: trip.id,
      occurredAt: DateTime(2026, 9, 1),
      category: '交通',
      purpose: '高铁往返',
      paidCents: 18800,
      claimCents: 18800,
      attachments: [
        Attachment(
          id: 'attachment-1',
          path: receipt.path,
          kind: AttachmentKind.payment,
          createdAt: DateTime(2026, 9, 1),
        ),
      ],
    );
    trip.expenses.add(expense);
    final service = ExportService();

    final xlsx = await service.exportXlsx(
      trip: trip,
      expenses: trip.expenses,
      root: root,
      employeeName: '张三',
      department: '研发部',
    );
    expect(await xlsx.exists(), isTrue);
    final workbook = ZipDecoder().decodeBytes(await xlsx.readAsBytes());
    final sheet = workbook.findFile('xl/worksheets/sheet1.xml');
    expect(sheet, isNotNull);
    final xml = utf8.decode(sheet!.content as List<int>);
    expect(xml, contains('张三'));
    expect(xml, contains('研发部'));
    expect(xml, contains('高铁往返'));
    expect(xml, contains('<mergeCell ref="A1:I1"/>'));
    expect(xml, contains('<v>188.00</v>'));

    final docx = await service.exportDocx(
      trip: trip,
      expenses: trip.expenses,
      root: root,
    );
    expect(await docx.exists(), isTrue);
    expect((await docx.length()) > 500, isTrue);
    final document = ZipDecoder().decodeBytes(await docx.readAsBytes());
    expect(document.findFile('word/media/image1.png'), isNotNull);

    final pdf = await service.exportPdf(
      trip: trip,
      expenses: trip.expenses,
      root: root,
    );
    expect(await pdf.exists(), isTrue);
    expect((await pdf.length()) > 500, isTrue);
  });
}

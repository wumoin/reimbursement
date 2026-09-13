import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reimbursement/backup_service.dart';
import 'package:reimbursement/models.dart';
import 'package:reimbursement/store.dart';

void main() {
  test('备份恢复会保留批次、账单和图片附件', () async {
    final sourceRoot = Directory(
      '${Directory.systemTemp.path}\\reimbursement_backup_source',
    );
    final targetRoot = Directory(
      '${Directory.systemTemp.path}\\reimbursement_backup_target',
    );
    for (final directory in [sourceRoot, targetRoot]) {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
      directory.createSync(recursive: true);
    }
    addTearDown(() {
      for (final directory in [sourceRoot, targetRoot]) {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      }
    });

    final source = AppStore(rootDirectory: sourceRoot);
    await source.updateProfile('李四', '销售部');
    final trip = Trip(id: 'trip-1', title: '宁波出差');
    final image = File(
      '${(await source.attachmentsDirectory).path}${Platform.pathSeparator}receipt.jpg',
    );
    await image.writeAsBytes([0xff, 0xd8, 0xff, 0xd9], flush: true);
    trip.expenses.add(
      Expense(
        id: 'expense-1',
        tripId: trip.id,
        occurredAt: DateTime(2026, 9, 2),
        category: '住宿',
        purpose: '酒店住宿',
        paidCents: 32000,
        claimCents: 32000,
        attachments: [
          Attachment(
            id: 'attachment-1',
            path: image.path,
            kind: AttachmentKind.payment,
            createdAt: DateTime(2026, 9, 2),
          ),
        ],
      ),
    );
    await source.addTrip(trip);

    final bytes = await BackupService().createBackup(source);
    expect(bytes.length, greaterThan(100));

    final restored = AppStore(rootDirectory: targetRoot);
    final summary = await BackupService().restoreBackup(restored, bytes);
    expect(summary.tripCount, 1);
    expect(summary.expenseCount, 1);
    expect(summary.imageCount, 1);
    expect(restored.profileName, '李四');
    expect(restored.trips.single.title, '宁波出差');
    final restoredPath =
        restored.trips.single.expenses.single.attachments.single.path;
    expect(await File(restoredPath).exists(), isTrue);
    expect(await File(restoredPath).readAsBytes(), [0xff, 0xd8, 0xff, 0xd9]);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reimbursement/models.dart';
import 'package:reimbursement/store.dart';

Expense _expense(String id, int cents) => Expense(
  id: id,
  tripId: 'trip-1',
  occurredAt: DateTime(2026, 9, 1),
  category: '交通',
  purpose: '客户拜访',
  paidCents: cents,
  claimCents: cents,
  attachments: [],
);

void main() {
  test('批次状态会随提交和到账进度变化', () async {
    final root = Directory(
      '${Directory.systemTemp.path}\\reimbursement_model_test',
    );
    if (root.existsSync()) root.deleteSync(recursive: true);
    root.createSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final store = AppStore(rootDirectory: root);
    final trip = Trip(id: 'trip-1', title: '杭州出差');
    trip.expenses.add(_expense('expense-1', 15000));
    await store.addTrip(trip);
    expect(trip.status, TripStatus.recording);

    await store.submitExpenses(trip, List.of(trip.expenses));
    expect(trip.status, TripStatus.submitted);
    expect(trip.submittedCents, 15000);

    await store.addPayment(
      trip,
      amountCents: 10000,
      date: DateTime(2026, 9, 10),
    );
    expect(trip.status, TripStatus.partial);
    expect(trip.pendingCents, 5000);

    await store.addPayment(
      trip,
      amountCents: 5000,
      date: DateTime(2026, 9, 12),
    );
    expect(trip.status, TripStatus.reimbursed);
    expect(trip.pendingCents, 0);
  });

  test('重新编辑后不会重复累计，重新提交才替换原版本', () async {
    final root = Directory(
      '${Directory.systemTemp.path}\\reimbursement_revision_test',
    );
    if (root.existsSync()) root.deleteSync(recursive: true);
    root.createSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final store = AppStore(rootDirectory: root);
    final trip = Trip(id: 'trip-1', title: '上海出差');
    final expense = _expense('expense-1', 10000);
    trip.expenses.add(expense);
    await store.addTrip(trip);
    await store.submitExpenses(trip, [expense]);

    expense.claimCents = 12000;
    await store.saveExpense(trip, expense);
    expect(trip.modifiedCount, 1);
    expect(trip.submittedCents, 10000);
    expect(trip.status, TripStatus.submitted);

    await store.confirmResubmission(trip, [expense]);
    expect(trip.submissions, hasLength(2));
    expect(trip.submittedCents, 12000);
    expect(trip.pendingCents, 12000);

    await store.addPayment(
      trip,
      amountCents: 12000,
      date: DateTime(2026, 9, 13),
    );
    expect(trip.status, TripStatus.reimbursed);

    expense.isClaimed = false;
    await store.saveExpense(trip, expense);
    expect(trip.modifiedCount, 1);
    await store.confirmResubmission(trip, [expense]);
    expect(trip.modifiedCount, 0);
    expect(trip.submittedCents, 0);
  });
}

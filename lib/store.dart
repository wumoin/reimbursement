import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class AppStore extends ChangeNotifier {
  AppStore({Directory? rootDirectory}) : _rootOverride = rootDirectory;

  final Directory? _rootOverride;
  final List<Trip> trips = [];
  final List<String> categories = [
    '交通',
    '住宿',
    '餐饮',
    '打车',
    '停车',
    '过路',
    '油费',
    '采购',
    '快递',
    '其他',
  ];
  String profileName = '';
  String profileDepartment = '';
  bool isReady = false;
  bool isSaving = false;
  Directory? _root;

  Future<Directory> get rootDirectory async {
    if (_root != null) return _root!;
    final base = _rootOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}reimbursement');
    if (!dir.existsSync()) await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  Future<File> get dataFile async =>
      File('${(await rootDirectory).path}${Platform.pathSeparator}data.json');

  Future<Directory> get attachmentsDirectory async {
    final dir = Directory(
      '${(await rootDirectory).path}${Platform.pathSeparator}attachments',
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> load() async {
    try {
      final file = await dataFile;
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        final map = Map<String, dynamic>.from(decoded as Map);
        profileName = map['profileName'] as String? ?? '';
        profileDepartment = map['profileDepartment'] as String? ?? '';
        trips
          ..clear()
          ..addAll(
            (map['trips'] as List? ?? []).map(
              (item) => Trip.fromJson(Map<String, dynamic>.from(item)),
            ),
          );
        for (final trip in trips) {
          trip.recomputeStatus();
        }
      }
    } catch (_) {
      // A corrupt local data file must not prevent the app from opening. The
      // original file remains available for manual recovery.
    }
    isReady = true;
    notifyListeners();
  }

  Future<void> save() async {
    isSaving = true;
    notifyListeners();
    try {
      final file = await dataFile;
      final temp = File('${file.path}.tmp');
      final payload = {
        'formatVersion': 1,
        'savedAt': DateTime.now().toIso8601String(),
        'profileName': profileName,
        'profileDepartment': profileDepartment,
        'categories': categories,
        'trips': trips.map((item) => item.toJson()).toList(),
      };
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Trip? tripById(String id) {
    for (final trip in trips) {
      if (trip.id == id) return trip;
    }
    return null;
  }

  Expense? expenseById(String tripId, String expenseId) {
    final trip = tripById(tripId);
    if (trip == null) return null;
    for (final expense in trip.expenses) {
      if (expense.id == expenseId) return expense;
    }
    return null;
  }

  Future<void> addTrip(Trip trip) async {
    trips.insert(0, trip);
    await save();
  }

  Future<void> updateTrip(Trip trip) async {
    trip.updatedAt = DateTime.now();
    await save();
  }

  Future<void> archiveTrip(Trip trip) async {
    trip.status = TripStatus.archived;
    trip.updatedAt = DateTime.now();
    await save();
  }

  Future<void> unarchiveTrip(Trip trip) async {
    trip.status = TripStatus.recording;
    trip.recomputeStatus();
    trip.updatedAt = DateTime.now();
    await save();
  }

  Future<void> deleteTrip(Trip trip) async {
    trips.removeWhere((item) => item.id == trip.id);
    await save();
  }

  Future<void> saveExpense(Trip trip, Expense expense) async {
    final existingIndex = trip.expenses.indexWhere(
      (item) => item.id == expense.id,
    );
    expense.updatedAt = DateTime.now();
    expense.revisions.add(
      ExpenseRevision(
        id: _id(),
        createdAt: DateTime.now(),
        snapshot: expense.toSnapshot(),
        submitted: false,
      ),
    );
    if (existingIndex < 0) {
      trip.expenses.add(expense);
    } else {
      trip.expenses[existingIndex] = expense;
    }
    trip.updatedAt = DateTime.now();
    trip.recomputeStatus();
    await save();
  }

  Future<void> deleteExpense(Trip trip, Expense expense) async {
    if (expense.hasBeenSubmitted) return;
    trip.expenses.removeWhere((item) => item.id == expense.id);
    trip.updatedAt = DateTime.now();
    await save();
  }

  Future<Attachment> copyAttachment(
    XFile source, {
    AttachmentKind kind = AttachmentKind.payment,
  }) async {
    final bytes = await source.readAsBytes();
    final id = _id();
    final extension = _extension(
      source.name.isEmpty ? source.path : source.name,
    );
    final target = File(
      '${(await attachmentsDirectory).path}${Platform.pathSeparator}$id.$extension',
    );
    await target.writeAsBytes(bytes, flush: true);
    return Attachment(
      id: id,
      path: target.path,
      kind: kind,
      createdAt: DateTime.now(),
      originalName: source.name,
      sha256: sha256.convert(bytes).toString(),
    );
  }

  Future<void> submitExpenses(
    Trip trip,
    List<Expense> selected, {
    String note = '',
    List<String> exportPaths = const [],
  }) async {
    final id = _id();
    final items = <SubmissionItem>[];
    for (final expense in selected.where(
      (item) => item.isClaimed || item.hasBeenSubmitted,
    )) {
      final signature = expense.signature;
      items.add(
        SubmissionItem(
          expenseId: expense.id,
          signature: signature,
          claimCents: expense.isClaimed ? expense.claimCents : 0,
          snapshot: expense.toSnapshot(),
        ),
      );
      expense.submittedSignature = signature;
      final revision = ExpenseRevision(
        id: _id(),
        createdAt: DateTime.now(),
        snapshot: expense.toSnapshot(),
        submitted: true,
        submissionId: id,
      );
      expense.submittedRevisionId = revision.id;
      expense.revisions.add(revision);
    }
    if (items.isEmpty) return;
    trip.submissions.add(
      Submission(
        id: id,
        tripId: trip.id,
        createdAt: DateTime.now(),
        items: items,
        note: note,
        exportPaths: exportPaths,
      ),
    );
    trip.recomputeStatus();
    trip.updatedAt = DateTime.now();
    await save();
  }

  Future<void> confirmResubmission(
    Trip trip,
    List<Expense> selected, {
    String note = '',
    List<String> exportPaths = const [],
  }) async {
    await submitExpenses(trip, selected, note: note, exportPaths: exportPaths);
  }

  Future<void> addPayment(
    Trip trip, {
    required int amountCents,
    required DateTime date,
    String? submissionId,
    String note = '',
    String? attachmentPath,
  }) async {
    trip.payments.add(
      Payment(
        id: _id(),
        tripId: trip.id,
        submissionId: submissionId,
        amountCents: amountCents,
        paidAt: date,
        note: note,
        attachmentPath: attachmentPath,
      ),
    );
    trip.recomputeStatus();
    trip.updatedAt = DateTime.now();
    await save();
  }

  Future<void> updateProfile(String name, String department) async {
    profileName = name.trim();
    profileDepartment = department.trim();
    await save();
  }

  static String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}_${(DateTime.now().millisecondsSinceEpoch % 100000)}';

  static String _extension(String path) {
    final clean = path.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1) return 'jpg';
    final ext = clean.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'jpeg' => 'jpg',
      'png' => 'png',
      'webp' => 'webp',
      _ => 'jpg',
    };
  }
}

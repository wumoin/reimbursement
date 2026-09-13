import 'dart:convert';

enum TripStatus { recording, submitted, partial, reimbursed, archived }

enum AttachmentKind { payment, invoice, detail, itinerary, other }

extension TripStatusX on TripStatus {
  String get label => switch (this) {
    TripStatus.recording => '记录中',
    TripStatus.submitted => '已提交',
    TripStatus.partial => '部分到账',
    TripStatus.reimbursed => '已报销',
    TripStatus.archived => '已归档',
  };

  static TripStatus fromJson(String? value) => TripStatus.values.firstWhere(
    (item) => item.name == value,
    orElse: () => TripStatus.recording,
  );
}

extension AttachmentKindX on AttachmentKind {
  String get label => switch (this) {
    AttachmentKind.payment => '支付截图',
    AttachmentKind.invoice => '发票',
    AttachmentKind.detail => '订单明细',
    AttachmentKind.itinerary => '行程截图',
    AttachmentKind.other => '其他图片',
  };

  static AttachmentKind fromJson(String? value) =>
      AttachmentKind.values.firstWhere(
        (item) => item.name == value,
        orElse: () => AttachmentKind.payment,
      );
}

DateTime? _dateFromJson(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

String? _dateToJson(DateTime? value) => value?.toIso8601String();

class Attachment {
  Attachment({
    required this.id,
    required this.path,
    required this.kind,
    required this.createdAt,
    this.originalName,
    this.sha256,
  });

  final String id;
  final String path;
  AttachmentKind kind;
  final DateTime createdAt;
  final String? originalName;
  final String? sha256;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'originalName': originalName,
    'sha256': sha256,
  };

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
    id: json['id'] as String,
    path: json['path'] as String,
    kind: AttachmentKindX.fromJson(json['kind'] as String?),
    createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now(),
    originalName: json['originalName'] as String?,
    sha256: json['sha256'] as String?,
  );
}

class ExpenseRevision {
  ExpenseRevision({
    required this.id,
    required this.createdAt,
    required this.snapshot,
    required this.submitted,
    this.submissionId,
  });

  final String id;
  final DateTime createdAt;
  final Map<String, dynamic> snapshot;
  final bool submitted;
  final String? submissionId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'snapshot': snapshot,
    'submitted': submitted,
    'submissionId': submissionId,
  };

  factory ExpenseRevision.fromJson(Map<String, dynamic> json) =>
      ExpenseRevision(
        id: json['id'] as String,
        createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now(),
        snapshot: Map<String, dynamic>.from(json['snapshot'] as Map),
        submitted: json['submitted'] as bool? ?? false,
        submissionId: json['submissionId'] as String?,
      );
}

class Expense {
  Expense({
    required this.id,
    required this.tripId,
    required this.occurredAt,
    required this.category,
    required this.purpose,
    required this.paidCents,
    required this.claimCents,
    required this.attachments,
    this.merchant = '',
    this.paymentMethod = '微信',
    this.receiptType = '支付截图',
    this.notes = '',
    this.refundCents = 0,
    this.isClaimed = true,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.submittedSignature,
    this.submittedRevisionId,
    List<ExpenseRevision>? revisions,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       revisions = revisions ?? [];

  final String id;
  final String tripId;
  DateTime occurredAt;
  String category;
  String purpose;
  int paidCents;
  int claimCents;
  int refundCents;
  String merchant;
  String paymentMethod;
  String receiptType;
  String notes;
  bool isClaimed;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<Attachment> attachments;
  final List<ExpenseRevision> revisions;
  String? submittedSignature;
  String? submittedRevisionId;

  int get netPaidCents => (paidCents - refundCents).clamp(0, 1 << 62);

  bool get hasBeenSubmitted => submittedSignature != null;

  ExpenseRevision? get latestSubmittedRevision {
    for (final revision in revisions.reversed) {
      if (revision.submitted) return revision;
    }
    return null;
  }

  bool get isModifiedAfterSubmission =>
      hasBeenSubmitted && submittedSignature != signature;

  bool get isComplete =>
      purpose.trim().isNotEmpty && category.trim().isNotEmpty && claimCents > 0;

  Map<String, dynamic> toSnapshot() => {
    'id': id,
    'tripId': tripId,
    'occurredAt': occurredAt.toIso8601String(),
    'category': category,
    'purpose': purpose,
    'paidCents': paidCents,
    'claimCents': claimCents,
    'refundCents': refundCents,
    'merchant': merchant,
    'paymentMethod': paymentMethod,
    'receiptType': receiptType,
    'notes': notes,
    'isClaimed': isClaimed,
    'attachments': attachments.map((item) => item.toJson()).toList(),
  };

  String get signature => jsonEncode(toSnapshot());

  Map<String, dynamic> toJson() => {
    ...toSnapshot(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'submittedSignature': submittedSignature,
    'submittedRevisionId': submittedRevisionId,
    'revisions': revisions.map((item) => item.toJson()).toList(),
  };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    tripId: json['tripId'] as String,
    occurredAt: _dateFromJson(json['occurredAt']) ?? DateTime.now(),
    category: json['category'] as String? ?? '其他',
    purpose: json['purpose'] as String? ?? '',
    paidCents: json['paidCents'] as int? ?? 0,
    claimCents: json['claimCents'] as int? ?? 0,
    refundCents: json['refundCents'] as int? ?? 0,
    merchant: json['merchant'] as String? ?? '',
    paymentMethod: json['paymentMethod'] as String? ?? '微信',
    receiptType: json['receiptType'] as String? ?? '支付截图',
    notes: json['notes'] as String? ?? '',
    isClaimed: json['isClaimed'] as bool? ?? true,
    createdAt: _dateFromJson(json['createdAt']),
    updatedAt: _dateFromJson(json['updatedAt']),
    submittedSignature: json['submittedSignature'] as String?,
    submittedRevisionId: json['submittedRevisionId'] as String?,
    attachments: (json['attachments'] as List? ?? [])
        .map((item) => Attachment.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    revisions: (json['revisions'] as List? ?? [])
        .map(
          (item) => ExpenseRevision.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(),
  );
}

class SubmissionItem {
  SubmissionItem({
    required this.expenseId,
    required this.signature,
    required this.claimCents,
    required this.snapshot,
  });

  final String expenseId;
  final String signature;
  final int claimCents;
  final Map<String, dynamic> snapshot;

  Map<String, dynamic> toJson() => {
    'expenseId': expenseId,
    'signature': signature,
    'claimCents': claimCents,
    'snapshot': snapshot,
  };

  factory SubmissionItem.fromJson(Map<String, dynamic> json) => SubmissionItem(
    expenseId: json['expenseId'] as String,
    signature: json['signature'] as String,
    claimCents: json['claimCents'] as int? ?? 0,
    snapshot: Map<String, dynamic>.from(json['snapshot'] as Map),
  );
}

class Submission {
  Submission({
    required this.id,
    required this.tripId,
    required this.createdAt,
    required this.items,
    this.note = '',
    this.exportPaths = const [],
    this.confirmedAt,
  });

  final String id;
  final String tripId;
  final DateTime createdAt;
  DateTime? confirmedAt;
  String note;
  final List<SubmissionItem> items;
  final List<String> exportPaths;

  int get claimCents => items.fold(0, (sum, item) => sum + item.claimCents);

  Map<String, dynamic> toJson() => {
    'id': id,
    'tripId': tripId,
    'createdAt': createdAt.toIso8601String(),
    'confirmedAt': _dateToJson(confirmedAt),
    'note': note,
    'items': items.map((item) => item.toJson()).toList(),
    'exportPaths': exportPaths,
  };

  factory Submission.fromJson(Map<String, dynamic> json) => Submission(
    id: json['id'] as String,
    tripId: json['tripId'] as String,
    createdAt: _dateFromJson(json['createdAt']) ?? DateTime.now(),
    confirmedAt: _dateFromJson(json['confirmedAt']),
    note: json['note'] as String? ?? '',
    items: (json['items'] as List? ?? [])
        .map((item) => SubmissionItem.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    exportPaths: (json['exportPaths'] as List? ?? [])
        .map((item) => item.toString())
        .toList(),
  );
}

class Payment {
  Payment({
    required this.id,
    required this.tripId,
    required this.amountCents,
    required this.paidAt,
    this.submissionId,
    this.note = '',
    this.attachmentPath,
  });

  final String id;
  final String tripId;
  final String? submissionId;
  final int amountCents;
  final DateTime paidAt;
  final String note;
  final String? attachmentPath;

  Map<String, dynamic> toJson() => {
    'id': id,
    'tripId': tripId,
    'submissionId': submissionId,
    'amountCents': amountCents,
    'paidAt': paidAt.toIso8601String(),
    'note': note,
    'attachmentPath': attachmentPath,
  };

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
    id: json['id'] as String,
    tripId: json['tripId'] as String,
    submissionId: json['submissionId'] as String?,
    amountCents: json['amountCents'] as int? ?? 0,
    paidAt: _dateFromJson(json['paidAt']) ?? DateTime.now(),
    note: json['note'] as String? ?? '',
    attachmentPath: json['attachmentPath'] as String?,
  );
}

class Trip {
  Trip({
    required this.id,
    required this.title,
    this.destination = '',
    this.reason = '',
    this.project = '',
    this.note = '',
    this.startDate,
    this.endDate,
    this.status = TripStatus.recording,
    List<Expense>? expenses,
    List<Submission>? submissions,
    List<Payment>? payments,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : expenses = expenses ?? [],
       submissions = submissions ?? [],
       payments = payments ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  String destination;
  String reason;
  String project;
  String note;
  DateTime? startDate;
  DateTime? endDate;
  TripStatus status;
  final List<Expense> expenses;
  final List<Submission> submissions;
  final List<Payment> payments;
  final DateTime createdAt;
  DateTime updatedAt;

  int get paidCents => expenses.fold(0, (sum, item) => sum + item.netPaidCents);

  int get claimCents => expenses
      .where((item) => item.isClaimed)
      .fold(0, (sum, item) => sum + item.claimCents);

  int get unsubmittedClaimCents => expenses
      .where((item) => item.isClaimed && !item.hasBeenSubmitted)
      .fold(0, (sum, item) => sum + item.claimCents);

  /// The amount represented by the latest submitted version of each bill.
  ///
  /// A resubmission is kept in [submissions] as history, but it must replace
  /// the previous version for totals. Summing every submission would count an
  /// edited bill twice.
  int get submittedCents {
    final latest = <String, int>{};
    for (final submission in submissions) {
      for (final item in submission.items) {
        latest[item.expenseId] = item.claimCents;
      }
    }
    return latest.values.fold(0, (sum, amount) => sum + amount);
  }

  int get receivedCents =>
      payments.fold(0, (sum, item) => sum + item.amountCents);

  int get pendingCents => (submittedCents - receivedCents).clamp(0, 1 << 62);

  int get unsubmittedCount =>
      expenses.where((item) => !item.hasBeenSubmitted).length;

  int get modifiedCount =>
      expenses.where((item) => item.isModifiedAfterSubmission).length;

  int get missingAttachmentCount => expenses
      .where((item) => item.isClaimed && item.attachments.isEmpty)
      .length;

  bool get hasUnsettledWork =>
      unsubmittedCount > 0 || modifiedCount > 0 || pendingCents > 0;

  void recomputeStatus() {
    if (status == TripStatus.archived) return;
    if (submissions.isEmpty) {
      status = TripStatus.recording;
    } else if (pendingCents > 0) {
      status = receivedCents > 0 ? TripStatus.partial : TripStatus.submitted;
    } else if (unsubmittedCount == 0 && modifiedCount == 0) {
      status = TripStatus.reimbursed;
    } else {
      status = TripStatus.submitted;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'destination': destination,
    'reason': reason,
    'project': project,
    'note': note,
    'startDate': _dateToJson(startDate),
    'endDate': _dateToJson(endDate),
    'status': status.name,
    'expenses': expenses.map((item) => item.toJson()).toList(),
    'submissions': submissions.map((item) => item.toJson()).toList(),
    'payments': payments.map((item) => item.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名出差',
    destination: json['destination'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
    project: json['project'] as String? ?? '',
    note: json['note'] as String? ?? '',
    startDate: _dateFromJson(json['startDate']),
    endDate: _dateFromJson(json['endDate']),
    status: TripStatusX.fromJson(json['status'] as String?),
    expenses: (json['expenses'] as List? ?? [])
        .map((item) => Expense.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    submissions: (json['submissions'] as List? ?? [])
        .map((item) => Submission.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    payments: (json['payments'] as List? ?? [])
        .map((item) => Payment.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    createdAt: _dateFromJson(json['createdAt']),
    updatedAt: _dateFromJson(json['updatedAt']),
  );
}

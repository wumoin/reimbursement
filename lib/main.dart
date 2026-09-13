import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_service.dart';
import 'export_service.dart';
import 'models.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.load();
  runApp(MyApp(store: store));
}

class MyApp extends StatelessWidget {
  MyApp({super.key, AppStore? store}) : store = store ?? AppStore();

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '我的报销',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2563eb)),
          scaffoldBackgroundColor: const Color(0xfff5f7fb),
          cardTheme: const CardThemeData(
            elevation: 0,
            margin: EdgeInsets.zero,
            surfaceTintColor: Colors.white,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xffe5e7eb)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xff2563eb),
                width: 1.5,
              ),
            ),
          ),
        ),
        home: HomeShell(store: store),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({required this.store, super.key});

  final AppStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  String get title => switch (index) {
    0 => '出差批次',
    1 => '待整理',
    _ => '设置',
  };

  @override
  Widget build(BuildContext context) {
    final pages = [
      TripsPage(store: widget.store, onOpen: _openTrip),
      InboxPage(store: widget.store, onOpen: _openExpense),
      SettingsPage(store: widget.store),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        actions: [
          if (index == 0)
            IconButton(
              tooltip: '搜索',
              onPressed: () => _showSearch(context),
              icon: const Icon(Icons.search_rounded),
            ),
        ],
      ),
      body: IndexedStack(index: index, children: pages),
      floatingActionButton: index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _editTrip(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建批次'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.luggage_outlined),
            selectedIcon: Icon(Icons.luggage),
            label: '批次',
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox),
            label: '待整理',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }

  void _openTrip(Trip trip) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TripDetailPage(store: widget.store, trip: trip),
      ),
    );
  }

  void _openExpense(Trip trip, Expense expense) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpenseEditorPage(
          store: widget.store,
          trip: trip,
          existing: expense,
        ),
      ),
    );
  }

  Future<void> _editTrip(BuildContext context, [Trip? trip]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TripEditorPage(store: widget.store, existing: trip),
      ),
    );
  }

  Future<void> _showSearch(BuildContext context) async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('搜索批次'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '名称、目的地或项目'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!context.mounted || query == null || query.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchPage(store: widget.store, query: query),
      ),
    );
  }
}

class TripsPage extends StatefulWidget {
  const TripsPage({required this.store, required this.onOpen, super.key});

  final AppStore store;
  final ValueChanged<Trip> onOpen;

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  TripStatus? filter;

  @override
  Widget build(BuildContext context) {
    final trips = widget.store.trips
        .where((trip) => filter == null || trip.status == filter)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      children: [
        _OverviewCard(trips: widget.store.trips),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: '全部',
                selected: filter == null,
                onTap: () => setState(() => filter = null),
              ),
              ...TripStatus.values.map(
                (status) => _FilterChip(
                  label: status.label,
                  selected: filter == status,
                  onTap: () => setState(() => filter = status),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (trips.isEmpty)
          const _EmptyState(
            icon: Icons.luggage_outlined,
            title: '还没有出差批次',
            subtitle: '点击右下角，先创建一次出差记录',
          )
        else
          ...trips.map(
            (trip) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TripCard(trip: trip, onTap: () => widget.onOpen(trip)),
            ),
          ),
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.trips});
  final List<Trip> trips;

  @override
  Widget build(BuildContext context) {
    final active = trips
        .where((trip) => trip.status != TripStatus.archived)
        .toList();
    final pending = active.fold(0, (sum, trip) => sum + trip.pendingCents);
    final recording = active
        .where((trip) => trip.status == TripStatus.recording)
        .length;
    return Card(
      color: const Color(0xff172554),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '报销概览',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              formatMoney(pending),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Text('已提交但尚未到账', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 18),
            Row(
              children: [
                _OverviewMetric(label: '进行中批次', value: '${active.length}'),
                const SizedBox(width: 24),
                _OverviewMetric(label: '记录中批次', value: '$recording'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
    ],
  );
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onTap});
  final Trip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateText = trip.startDate == null
        ? '日期未填写'
        : '${formatDate(trip.startDate!)}${trip.endDate == null ? '' : ' - ${formatDate(trip.endDate!)}'}';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trip.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  StatusChip(status: trip.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  dateText,
                  if (trip.destination.isNotEmpty) trip.destination,
                ].join(' · '),
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _CardMetric(
                    label: '申请金额',
                    value: formatMoney(trip.claimCents),
                  ),
                  const Spacer(),
                  _CardMetric(label: '账单', value: '${trip.expenses.length} 笔'),
                  const SizedBox(width: 16),
                  const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                ],
              ),
              if (trip.unsubmittedCount > 0 ||
                  trip.modifiedCount > 0 ||
                  trip.missingAttachmentCount > 0) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (trip.unsubmittedCount > 0)
                      _Badge(
                        text: '未提交 ${trip.unsubmittedCount} 笔',
                        color: Colors.orange,
                      ),
                    if (trip.modifiedCount > 0)
                      _Badge(
                        text: '已修改 ${trip.modifiedCount} 笔',
                        color: Colors.deepOrange,
                      ),
                    if (trip.missingAttachmentCount > 0)
                      _Badge(
                        text: '缺图片 ${trip.missingAttachmentCount} 笔',
                        color: Colors.red,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMetric extends StatelessWidget {
  const _CardMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
    ],
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});
  final TripStatus status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TripStatus.recording => Colors.blue,
      TripStatus.submitted => Colors.indigo,
      TripStatus.partial => Colors.orange,
      TripStatus.reimbursed => Colors.green,
      TripStatus.archived => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withAlpha(20),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56),
    child: Column(
      children: [
        Icon(icon, size: 52, color: Colors.grey.shade400),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
      ],
    ),
  );
}

class TripEditorPage extends StatefulWidget {
  const TripEditorPage({required this.store, this.existing, super.key});
  final AppStore store;
  final Trip? existing;
  @override
  State<TripEditorPage> createState() => _TripEditorPageState();
}

class _TripEditorPageState extends State<TripEditorPage> {
  late final TextEditingController title;
  late final TextEditingController destination;
  late final TextEditingController reason;
  late final TextEditingController project;
  late final TextEditingController note;
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    final trip = widget.existing;
    title = TextEditingController(text: trip?.title ?? '');
    destination = TextEditingController(text: trip?.destination ?? '');
    reason = TextEditingController(text: trip?.reason ?? '');
    project = TextEditingController(text: trip?.project ?? '');
    note = TextEditingController(text: trip?.note ?? '');
    startDate = trip?.startDate;
    endDate = trip?.endDate;
  }

  @override
  void dispose() {
    title.dispose();
    destination.dispose();
    reason.dispose();
    project.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.existing == null ? '新建出差批次' : '编辑出差批次')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _FormSection(
          title: '基本信息',
          children: [
            TextField(
              controller: title,
              autofocus: widget.existing == null,
              decoration: const InputDecoration(
                labelText: '批次名称 *',
                hintText: '例如：苏州客户现场调试',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: '开始日期',
                    value: startDate,
                    onTap: () => _pickDate(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateButton(
                    label: '结束日期',
                    value: endDate,
                    onTap: () => _pickDate(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: destination,
              decoration: const InputDecoration(
                labelText: '目的地',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '出差事由'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _FormSection(
          title: '可选信息',
          children: [
            TextField(
              controller: project,
              decoration: const InputDecoration(labelText: '客户或项目'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check_rounded),
          label: const Text('保存批次'),
        ),
      ],
    ),
  );

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart
        ? (startDate ?? DateTime.now())
        : (endDate ?? startDate ?? DateTime.now());
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (date == null) return;
    setState(() {
      if (isStart) {
        startDate = date;
        if (endDate != null && endDate!.isBefore(date)) endDate = date;
      } else {
        endDate = date;
      }
    });
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) {
      showSnack(context, '请填写批次名称');
      return;
    }
    if (widget.existing == null) {
      await widget.store.addTrip(
        Trip(
          id: newId(),
          title: title.text.trim(),
          destination: destination.text.trim(),
          reason: reason.text.trim(),
          project: project.text.trim(),
          note: note.text.trim(),
          startDate: startDate,
          endDate: endDate,
        ),
      );
    } else {
      final trip = widget.existing!;
      trip.title = title.text.trim();
      trip.destination = destination.text.trim();
      trip.reason = reason.text.trim();
      trip.project = project.text.trim();
      trip.note = note.text.trim();
      trip.startDate = startDate;
      trip.endDate = endDate;
      await widget.store.updateTrip(trip);
    }
    if (mounted) Navigator.pop(context);
  }
}

class TripDetailPage extends StatefulWidget {
  const TripDetailPage({required this.store, required this.trip, super.key});
  final AppStore store;
  final Trip trip;
  @override
  State<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends State<TripDetailPage> {
  bool get readOnly => widget.trip.status == TripStatus.archived;

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    return Scaffold(
      appBar: AppBar(
        title: Text(trip.title, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              if (!readOnly)
                const PopupMenuItem(value: 'edit', child: Text('编辑批次')),
              if (!readOnly)
                const PopupMenuItem(value: 'archive', child: Text('归档批次')),
              if (readOnly)
                const PopupMenuItem(value: 'unarchive', child: Text('取消归档')),
              const PopupMenuItem(value: 'delete', child: Text('删除批次')),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            Row(
              children: [
                StatusChip(status: trip.status),
                const Spacer(),
                Text(
                  _tripDates(trip),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DetailSummary(trip: trip),
            if (trip.unsubmittedCount > 0 ||
                trip.modifiedCount > 0 ||
                trip.missingAttachmentCount > 0) ...[
              const SizedBox(height: 14),
              _AlertCard(trip: trip),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                const Text(
                  '账单明细',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '${trip.expenses.length} 笔',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (trip.expenses.isEmpty)
              const _EmptyState(
                icon: Icons.receipt_long_outlined,
                title: '还没有账单',
                subtitle: '消费后可以先记金额，也可以先添加支付截图',
              )
            else
              ...trip.expenses.map(
                (expense) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ExpenseTile(
                    expense: expense,
                    onTap: readOnly ? null : () => _editExpense(expense),
                    onPreview: expense.attachments.isEmpty
                        ? null
                        : () => _previewAttachments(expense.attachments),
                    onCopy: readOnly ? null : () => _copyExpense(expense),
                    onDelete: readOnly || expense.hasBeenSubmitted
                        ? null
                        : () => _deleteExpense(expense),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            if (trip.submissions.isNotEmpty) _HistorySection(trip: trip),
            if (trip.payments.isNotEmpty) ...[
              const SizedBox(height: 14),
              _PaymentsSection(trip: trip),
            ],
          ],
        ),
      ),
      bottomSheet: readOnly
          ? null
          : _ActionBar(
              onAdd: () => _editExpense(),
              onExport: _export,
              onSubmit: _submit,
              onPayment: _payment,
              canSubmit: trip.expenses.any(
                (e) =>
                    e.isComplete &&
                    (e.isClaimed || e.hasBeenSubmitted) &&
                    (!e.hasBeenSubmitted || e.isModifiedAfterSubmission),
              ),
            ),
    );
  }

  String _tripDates(Trip trip) => trip.startDate == null
      ? '日期未填写'
      : '${formatDate(trip.startDate!)}${trip.endDate == null ? '' : ' - ${formatDate(trip.endDate!)}'}';

  Future<void> _editExpense([Expense? expense]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseEditorPage(
          store: widget.store,
          trip: widget.trip,
          existing: expense,
        ),
      ),
    );
  }

  void _previewAttachments(
    List<Attachment> attachments, [
    int initialIndex = 0,
  ]) {
    showAttachmentPreview(context, attachments, initialIndex: initialIndex);
  }

  Future<void> _copyExpense(Expense expense) async {
    final copy = Expense(
      id: newId(),
      tripId: widget.trip.id,
      occurredAt: expense.occurredAt,
      category: expense.category,
      purpose: expense.purpose,
      paidCents: expense.paidCents,
      claimCents: expense.claimCents,
      refundCents: expense.refundCents,
      merchant: expense.merchant,
      paymentMethod: expense.paymentMethod,
      receiptType: expense.receiptType,
      notes: expense.notes,
      isClaimed: expense.isClaimed,
      attachments: const [],
    );
    await widget.store.saveExpense(widget.trip, copy);
    if (mounted) showSnack(context, '已复制账单，请补充新的图片凭证');
  }

  Future<void> _deleteExpense(Expense expense) async {
    final ok = await confirm(context, '删除这笔账单？', '删除后可以重新录入，但不会删除手机相册中的原图。');
    if (!ok || !mounted) return;
    await widget.store.deleteExpense(widget.trip, expense);
    if (mounted) showSnack(context, '账单已删除');
  }

  void _menu(String value) async {
    switch (value) {
      case 'edit':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                TripEditorPage(store: widget.store, existing: widget.trip),
          ),
        );
      case 'archive':
        await widget.store.archiveTrip(widget.trip);
        if (mounted) showSnack(context, '批次已归档');
      case 'unarchive':
        await widget.store.unarchiveTrip(widget.trip);
      case 'delete':
        final ok = await confirm(
          context,
          '删除批次？',
          '批次和其中尚未提交的账单会被删除，已提交历史也会一并移除。',
        );
        if (ok) {
          await widget.store.deleteTrip(widget.trip);
          if (mounted) Navigator.pop(context);
        }
    }
  }

  Future<void> _submit() async {
    final candidates = widget.trip.expenses
        .where(
          (e) =>
              e.isComplete &&
              (e.isClaimed || e.hasBeenSubmitted) &&
              (!e.hasBeenSubmitted || e.isModifiedAfterSubmission),
        )
        .toList();
    if (candidates.isEmpty) {
      showSnack(context, '没有可提交的完整账单');
      return;
    }
    final selected = <String>{...candidates.map((e) => e.id)};
    final note = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final total = candidates
              .where((expense) => selected.contains(expense.id))
              .fold(
                0,
                (sum, expense) =>
                    sum + (expense.isClaimed ? expense.claimCents : 0),
              );
          final missingSelected = candidates
              .where(
                (expense) =>
                    selected.contains(expense.id) &&
                    expense.attachments.isEmpty,
              )
              .length;
          return AlertDialog(
            title: const Text('确认实际提交'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('将提交 ${selected.length} 笔，合计 ${formatMoney(total)}'),
                    if (missingSelected > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '有 $missingSelected 笔账单还没有图片附件，请确认公司是否接受。',
                        style: const TextStyle(color: Colors.deepOrange),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ...candidates.map(
                      (expense) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selected.contains(expense.id),
                        title: Text(
                          '${expense.isClaimed ? '' : '撤销 · '}${expense.category} · ${expense.purpose}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(formatMoney(expense.claimCents)),
                        onChanged: (value) => setDialogState(() {
                          if (value == true) {
                            selected.add(expense.id);
                          } else {
                            selected.remove(expense.id);
                          }
                        }),
                      ),
                    ),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(labelText: '提交备注（可选）'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('确认已提交'),
              ),
            ],
          );
        },
      ),
    );
    if (result != true || !mounted) {
      note.dispose();
      return;
    }
    await widget.store.submitExpenses(
      widget.trip,
      candidates.where((e) => selected.contains(e.id)).toList(),
      note: note.text.trim(),
    );
    note.dispose();
    if (mounted) showSnack(context, '已记录本次提交');
  }

  Future<void> _payment() async {
    if (widget.trip.submissions.isEmpty) {
      showSnack(context, '请先标记一次实际提交');
      return;
    }
    final amount = TextEditingController();
    final note = TextEditingController();
    DateTime date = DateTime.now();
    String? submissionId = widget.trip.submissions.last.id;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('登记到账'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  labelText: '到账金额（元） *',
                  prefixText: '￥',
                ),
              ),
              const SizedBox(height: 10),
              _DateButton(
                label: '到账日期',
                value: date,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDate: date,
                  );
                  if (picked != null) setDialogState(() => date = picked);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: submissionId,
                decoration: const InputDecoration(labelText: '对应提交'),
                items: widget.trip.submissions
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          '${formatDate(s.createdAt)} · ${formatMoney(s.claimCents)}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => submissionId = value),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: '备注'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: parseCents(amount.text) <= 0
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) {
      amount.dispose();
      note.dispose();
      return;
    }
    final amountCents = parseCents(amount.text);
    if (amountCents > widget.trip.pendingCents) {
      final keep = await confirm(
        context,
        '到账金额超过待到账金额',
        '当前待到账 ${formatMoney(widget.trip.pendingCents)}，仍要记录 ${formatMoney(amountCents)} 吗？',
      );
      if (!keep || !mounted) {
        amount.dispose();
        note.dispose();
        return;
      }
    }
    await widget.store.addPayment(
      widget.trip,
      amountCents: amountCents,
      date: date,
      submissionId: submissionId,
      note: note.text.trim(),
    );
    amount.dispose();
    note.dispose();
    if (mounted) showSnack(context, '到账记录已保存');
  }

  Future<void> _export() async {
    final expenses = widget.trip.expenses
        .where((e) => e.isClaimed && e.isComplete)
        .toList();
    if (expenses.isEmpty) {
      showSnack(context, '没有可导出的完整账单');
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '选择导出格式',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF 报销表 + 图片凭证'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Word 图片凭证'),
              onTap: () => Navigator.pop(context, 'docx'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Excel 费用明细'),
              onTap: () => Navigator.pop(context, 'xlsx'),
            ),
            ListTile(
              leading: const Icon(Icons.all_inbox_outlined),
              title: const Text('生成全部格式'),
              onTap: () => Navigator.pop(context, 'all'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final service = ExportService();
    final root = await widget.store.rootDirectory;
    final files = <File>[];
    try {
      if (choice == 'pdf' || choice == 'all') {
        files.add(
          await service.exportPdf(
            trip: widget.trip,
            expenses: expenses,
            root: root,
          ),
        );
      }
      if (choice == 'docx' || choice == 'all') {
        files.add(
          await service.exportDocx(
            trip: widget.trip,
            expenses: expenses,
            root: root,
          ),
        );
      }
      if (choice == 'xlsx' || choice == 'all') {
        files.add(
          await service.exportXlsx(
            trip: widget.trip,
            expenses: expenses,
            root: root,
            employeeName: widget.store.profileName,
            department: widget.store.profileDepartment,
          ),
        );
      }
      if (files.isNotEmpty) {
        await SharePlus.instance.share(
          ShareParams(
            title: '${widget.trip.title} 报销材料',
            text: '出差批次：${widget.trip.title}',
            files: [for (final file in files) XFile(file.path)],
          ),
        );
      }
      if (mounted) {
        showSnack(context, '已生成 ${files.length} 个文件，可在分享面板保存或发送；同时保存在应用导出目录');
      }
    } catch (error) {
      if (mounted) showSnack(context, '导出失败：$error');
    }
  }
}

class _DetailSummary extends StatelessWidget {
  const _DetailSummary({required this.trip});
  final Trip trip;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: '个人垫付',
                  value: formatMoney(trip.paidCents),
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: '申请报销',
                  value: formatMoney(trip.claimCents),
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: '已到账',
                  value: formatMoney(trip.receivedCents),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: '已提交',
                  value: formatMoney(trip.submittedCents),
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: '待到账',
                  value: formatMoney(trip.pendingCents),
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: '提交次数',
                  value: '${trip.submissions.length} 次',
                ),
              ),
            ],
          ),
          if (trip.unsubmittedClaimCents > 0 || trip.modifiedCount > 0) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _SummaryItem(
                    label: '未提交申请',
                    value: formatMoney(trip.unsubmittedClaimCents),
                  ),
                ),
                Expanded(
                  child: _SummaryItem(
                    label: '已修改未重提',
                    value: '${trip.modifiedCount} 笔',
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.trip});
  final Trip trip;
  @override
  Widget build(BuildContext context) {
    final items = [
      if (trip.unsubmittedCount > 0) '有 ${trip.unsubmittedCount} 笔账单未提交',
      if (trip.modifiedCount > 0) '有 ${trip.modifiedCount} 笔账单已修改但未重新提交',
      if (trip.missingAttachmentCount > 0)
        '有 ${trip.missingAttachmentCount} 笔账单缺少图片',
    ];
    return Card(
      color: const Color(0xfffffbeb),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xffb45309)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '提交前检查',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xff92400e),
                    ),
                  ),
                  const SizedBox(height: 5),
                  ...items.map(
                    (item) => Text(
                      '· $item',
                      style: const TextStyle(color: Color(0xff92400e)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.expense,
    required this.onTap,
    this.onPreview,
    this.onCopy,
    this.onDelete,
  });
  final Expense expense;
  final VoidCallback? onTap;
  final VoidCallback? onPreview;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: const Color(0xffdbeafe),
        child: Icon(
          _categoryIcon(expense.category),
          color: const Color(0xff2563eb),
        ),
      ),
      title: Text(
        expense.purpose.isEmpty ? '未填写用途' : expense.purpose,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${formatDate(expense.occurredAt)} · ${expense.category}${expense.merchant.isEmpty ? '' : ' · ${expense.merchant}'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(expense.claimCents),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (expense.isModifiedAfterSubmission)
                const Text(
                  '已修改未提交',
                  style: TextStyle(fontSize: 10, color: Colors.deepOrange),
                ),
              if (expense.attachments.isEmpty)
                const Text(
                  '缺图片',
                  style: TextStyle(fontSize: 10, color: Colors.red),
                ),
            ],
          ),
          if (onPreview != null)
            IconButton(
              tooltip: '查看图片',
              onPressed: onPreview,
              icon: const Icon(Icons.photo_library_outlined),
            ),
          if (onCopy != null || onDelete != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'copy') onCopy?.call();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                if (onCopy != null)
                  const PopupMenuItem(value: 'copy', child: Text('复制账单')),
                if (onDelete != null)
                  const PopupMenuItem(value: 'delete', child: Text('删除账单')),
              ],
            ),
        ],
      ),
    ),
  );
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.trip});
  final Trip trip;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '提交记录',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...trip.submissions.reversed.map(
            (submission) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.send_outlined),
              title: Text(
                '${formatDate(submission.createdAt)} · ${formatMoney(submission.claimCents)}',
              ),
              subtitle: Text(
                '${submission.items.length} 笔${submission.note.isEmpty ? '' : ' · ${submission.note}'}',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PaymentsSection extends StatelessWidget {
  const _PaymentsSection({required this.trip});
  final Trip trip;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '到账记录',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...trip.payments.reversed.map(
            (payment) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(
                formatMoney(payment.amountCents),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${formatDate(payment.paidAt)}${payment.note.isEmpty ? '' : ' · ${payment.note}'}',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onAdd,
    required this.onExport,
    required this.onSubmit,
    required this.onPayment,
    required this.canSubmit,
  });
  final VoidCallback onAdd;
  final VoidCallback onExport;
  final VoidCallback onSubmit;
  final VoidCallback onPayment;
  final bool canSubmit;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 12,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('记账'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '导出',
              onPressed: onExport,
              icon: const Icon(Icons.ios_share_rounded),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: canSubmit ? onSubmit : null,
              child: const Text('提交'),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '登记到账',
              onPressed: onPayment,
              icon: const Icon(Icons.payments_outlined),
            ),
          ],
        ),
      ),
    ),
  );
}

class ExpenseEditorPage extends StatefulWidget {
  const ExpenseEditorPage({
    required this.store,
    required this.trip,
    this.existing,
    super.key,
  });
  final AppStore store;
  final Trip trip;
  final Expense? existing;
  @override
  State<ExpenseEditorPage> createState() => _ExpenseEditorPageState();
}

class _ExpenseEditorPageState extends State<ExpenseEditorPage> {
  late final TextEditingController purpose;
  late final TextEditingController paid;
  late final TextEditingController claim;
  late final TextEditingController refund;
  late final TextEditingController merchant;
  late final TextEditingController notes;
  late DateTime date;
  late String category;
  late String paymentMethod;
  late String receiptType;
  late bool isClaimed;
  late List<Attachment> attachments;
  final paymentMethods = const ['微信', '支付宝', '银行卡', '现金', '其他'];
  final receiptTypes = const ['支付截图', '发票', '订单明细', '其他图片'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    date = e?.occurredAt ?? DateTime.now();
    category = e?.category ?? widget.store.categories.first;
    paymentMethod = e?.paymentMethod ?? '微信';
    receiptType = e?.receiptType ?? '支付截图';
    isClaimed = e?.isClaimed ?? true;
    purpose = TextEditingController(text: e?.purpose ?? '');
    paid = TextEditingController(text: centsToInput(e?.paidCents ?? 0));
    claim = TextEditingController(text: centsToInput(e?.claimCents ?? 0));
    refund = TextEditingController(text: centsToInput(e?.refundCents ?? 0));
    merchant = TextEditingController(text: e?.merchant ?? '');
    notes = TextEditingController(text: e?.notes ?? '');
    attachments = [...?e?.attachments];
  }

  @override
  void dispose() {
    purpose.dispose();
    paid.dispose();
    claim.dispose();
    refund.dispose();
    merchant.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.existing == null ? '新增账单' : '编辑账单')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.existing?.hasBeenSubmitted == true)
          Card(
            color: const Color(0xfffff7ed),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, color: Colors.deepOrange),
                  SizedBox(width: 8),
                  Expanded(child: Text('这笔账单已经提交过，保存后需要重新导出并确认重新提交。')),
                ],
              ),
            ),
          ),
        if (widget.existing?.latestSubmittedRevision != null)
          Card(
            color: const Color(0xfff8fafc),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.restore_page_outlined,
                    color: Colors.blueGrey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '上次提交版本：${formatMoney(_submittedAmount(widget.existing!.latestSubmittedRevision!))} · ${formatDate(widget.existing!.latestSubmittedRevision!.createdAt)}',
                    ),
                  ),
                  if (widget.existing?.isModifiedAfterSubmission == true)
                    TextButton(
                      onPressed: _restoreSubmittedVersion,
                      child: const Text('撤销修改'),
                    ),
                ],
              ),
            ),
          ),
        _FormSection(
          title: '账单信息',
          children: [
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: '发生日期',
                    value: date,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: '费用类型'),
                    items: widget.store.categories
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => category = value ?? category),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: receiptType,
              decoration: const InputDecoration(labelText: '票据类型'),
              items: receiptTypes
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => receiptType = value ?? receiptType),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: purpose,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '用途明细 *',
                hintText: '例如：苏州出差打车到客户现场',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: paid,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '实际支付（元）',
                      prefixText: '￥',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: claim,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '申请报销（元）',
                      prefixText: '￥',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: refund,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '退款（元）',
                      prefixText: '￥',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration: const InputDecoration(labelText: '支付方式'),
                    items: paymentMethods
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => paymentMethod = value ?? paymentMethod),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: merchant,
              decoration: const InputDecoration(labelText: '商户或收款方'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '备注'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _AttachmentSection(
          attachments: attachments,
          onAdd: _addAttachments,
          onPreview: _previewAttachment,
          onRemove: (item) => setState(() => attachments.remove(item)),
          onKindChanged: (item, kind) => setState(() => item.kind = kind),
        ),
        const SizedBox(height: 14),
        Card(
          child: SwitchListTile(
            value: isClaimed,
            onChanged: (value) => setState(() => isClaimed = value),
            title: const Text('计入本次报销'),
            subtitle: const Text('关闭后保留账单，但不计入报销合计'),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存账单'),
        ),
      ],
    ),
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: date,
    );
    if (picked != null) setState(() => date = picked);
  }

  Future<void> _addAttachments() async {
    final kind = await showModalBottomSheet<AttachmentKind>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('选择图片类型')),
            ...AttachmentKind.values.map(
              (item) => ListTile(
                title: Text(item.label),
                onTap: () => Navigator.pop(context, item),
              ),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      if (source == 'camera') {
        final image = await ImagePicker().pickImage(source: ImageSource.camera);
        if (image != null) {
          attachments.add(await widget.store.copyAttachment(image, kind: kind));
        }
      } else {
        final images = await ImagePicker().pickMultiImage(imageQuality: 95);
        for (final image in images) {
          attachments.add(await widget.store.copyAttachment(image, kind: kind));
        }
      }
      setState(() {});
    } catch (error) {
      if (mounted) showSnack(context, '添加图片失败：$error');
    }
  }

  void _previewAttachment(int index) {
    showAttachmentPreview(context, attachments, initialIndex: index);
  }

  Future<void> _save() async {
    final existing = widget.existing;
    final expense = Expense(
      id: existing?.id ?? newId(),
      tripId: widget.trip.id,
      occurredAt: date,
      category: category,
      purpose: purpose.text.trim(),
      paidCents: parseCents(paid.text),
      claimCents: parseCents(claim.text),
      refundCents: parseCents(refund.text),
      merchant: merchant.text.trim(),
      paymentMethod: paymentMethod,
      receiptType: receiptType,
      notes: notes.text.trim(),
      isClaimed: isClaimed,
      attachments: attachments,
      createdAt: existing?.createdAt,
      updatedAt: DateTime.now(),
      submittedSignature: existing?.submittedSignature,
      submittedRevisionId: existing?.submittedRevisionId,
      revisions: existing == null ? [] : [...existing.revisions],
    );
    if (expense.claimCents > expense.netPaidCents && expense.netPaidCents > 0) {
      final ok = await confirm(context, '申请金额高于实际净支付', '仍然保存这笔账单吗？');
      if (!ok) return;
    }
    await widget.store.saveExpense(widget.trip, expense);
    if (mounted) {
      showSnack(
        context,
        existing?.hasBeenSubmitted == true ? '已保存修改，请重新导出并确认提交' : '账单已保存',
      );
      Navigator.pop(context);
    }
  }

  int _submittedAmount(ExpenseRevision revision) {
    final value = revision.snapshot['claimCents'];
    return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  }

  Future<void> _restoreSubmittedVersion() async {
    final existing = widget.existing;
    final revision = existing?.latestSubmittedRevision;
    if (revision == null) return;
    final ok = await confirm(context, '撤销当前修改？', '当前内容会恢复为上次实际提交的版本。');
    if (!ok || !mounted) return;
    final snapshot = revision.snapshot;
    setState(() {
      final occurred = DateTime.tryParse('${snapshot['occurredAt']}');
      if (occurred != null) date = occurred.toLocal();
      category = snapshot['category'] as String? ?? category;
      purpose.text = snapshot['purpose'] as String? ?? '';
      paid.text = centsToInput(_snapshotInt(snapshot['paidCents']));
      claim.text = centsToInput(_snapshotInt(snapshot['claimCents']));
      refund.text = centsToInput(_snapshotInt(snapshot['refundCents']));
      merchant.text = snapshot['merchant'] as String? ?? '';
      paymentMethod = snapshot['paymentMethod'] as String? ?? paymentMethod;
      receiptType = snapshot['receiptType'] as String? ?? receiptType;
      notes.text = snapshot['notes'] as String? ?? '';
      isClaimed = snapshot['isClaimed'] as bool? ?? true;
      attachments = (snapshot['attachments'] as List? ?? [])
          .map((item) => Attachment.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    });
  }

  int _snapshotInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({
    required this.attachments,
    required this.onAdd,
    required this.onPreview,
    required this.onRemove,
    required this.onKindChanged,
  });
  final List<Attachment> attachments;
  final VoidCallback onAdd;
  final ValueChanged<int> onPreview;
  final ValueChanged<Attachment> onRemove;
  final void Function(Attachment, AttachmentKind) onKindChanged;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '图片附件',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('添加图片'),
              ),
            ],
          ),
          if (attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  '支付截图、发票和订单明细都可以作为图片添加',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: attachments.length,
              itemBuilder: (_, index) {
                final item = attachments[index];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      onTap: () => onPreview(index),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: File(item.path).existsSync()
                            ? Image.file(File(item.path), fit: BoxFit.cover)
                            : Container(
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      right: 4,
                      bottom: 4,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<AttachmentKind>(
                          isExpanded: true,
                          isDense: true,
                          dropdownColor: Colors.white,
                          value: item.kind,
                          items: AttachmentKind.values
                              .map(
                                (kind) => DropdownMenuItem(
                                  value: kind,
                                  child: Text(
                                    kind.label,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (kind) {
                            if (kind != null) onKindChanged(item, kind);
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: InkWell(
                        onTap: () => onRemove(item),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> showAttachmentPreview(
  BuildContext context,
  List<Attachment> attachments, {
  int initialIndex = 0,
}) {
  if (attachments.isEmpty) return Future.value();
  final safeIndex = initialIndex.clamp(0, attachments.length - 1).toInt();
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AttachmentPreviewPage(
        attachments: List<Attachment>.of(attachments),
        initialIndex: safeIndex,
      ),
    ),
  );
}

class AttachmentPreviewPage extends StatefulWidget {
  const AttachmentPreviewPage({
    required this.attachments,
    this.initialIndex = 0,
    super.key,
  });

  final List<Attachment> attachments;
  final int initialIndex;

  @override
  State<AttachmentPreviewPage> createState() => _AttachmentPreviewPageState();
}

class _AttachmentPreviewPageState extends State<AttachmentPreviewPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.attachments.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.attachments[_currentIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1}/${widget.attachments.length} · ${current.kind.label}',
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.attachments.length,
        onPageChanged: (value) => setState(() => _currentIndex = value),
        itemBuilder: (_, index) {
          final attachment = widget.attachments[index];
          final file = File(attachment.path);
          if (!file.existsSync()) return _missingImage(attachment);
          return Center(
            child: InteractiveViewer(
              key: ValueKey(attachment.path),
              minScale: 0.8,
              maxScale: 5,
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => _missingImage(attachment),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            current.originalName ??
                current.path.split(Platform.pathSeparator).last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }

  Widget _missingImage(Attachment attachment) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          size: 56,
        ),
        const SizedBox(height: 12),
        const Text('图片文件不存在或无法读取', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 4),
        Text(
          attachment.originalName ?? attachment.path,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    ),
  );
}

class InboxPage extends StatelessWidget {
  const InboxPage({required this.store, required this.onOpen, super.key});
  final AppStore store;
  final void Function(Trip, Expense) onOpen;
  @override
  Widget build(BuildContext context) {
    final items = <(Trip, Expense)>[];
    for (final trip in store.trips.where(
      (t) => t.status != TripStatus.archived,
    )) {
      for (final expense in trip.expenses) {
        if (!expense.isComplete ||
            expense.attachments.isEmpty ||
            expense.isModifiedAfterSubmission) {
          items.add((trip, expense));
        }
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Card(
          color: const Color(0xffeff6ff),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.inbox_outlined, color: Color(0xff2563eb)),
                SizedBox(width: 12),
                Expanded(child: Text('这里集中显示缺信息、缺图片或提交后有修改的账单。它不是新的批次状态。')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          const _EmptyState(
            icon: Icons.task_alt_rounded,
            title: '暂时没有待整理账单',
            subtitle: '新导入的图片和草稿会显示在这里',
          )
        else
          ...items.map(
            (pair) => Card(
              child: ListTile(
                onTap: () => onOpen(pair.$1, pair.$2),
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(
                  pair.$2.purpose.isEmpty ? '未填写用途' : pair.$2.purpose,
                ),
                subtitle: Text('${pair.$1.title} · ${pair.$2.category}'),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          ),
      ],
    );
  }
}

class SearchPage extends StatelessWidget {
  const SearchPage({required this.store, required this.query, super.key});
  final AppStore store;
  final String query;
  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final results = store.trips
        .where(
          (trip) =>
              '${trip.title} ${trip.destination} ${trip.project} ${trip.reason}'
                  .toLowerCase()
                  .contains(q),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text('搜索：$query')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (results.isEmpty)
            const _EmptyState(
              icon: Icons.search_off_rounded,
              title: '没有找到批次',
              subtitle: '换一个名称、目的地或项目试试',
            )
          else
            ...results.map(
              (trip) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TripCard(
                  trip: trip,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TripDetailPage(store: store, trip: trip),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.store, super.key});
  final AppStore store;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController name;
  late final TextEditingController department;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.store.profileName);
    department = TextEditingController(text: widget.store.profileDepartment);
  }

  @override
  void dispose() {
    name.dispose();
    department.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '导出资料',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '姓名'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: department,
                decoration: const InputDecoration(labelText: '所属部门'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await widget.store.updateProfile(name.text, department.text);
                  if (context.mounted) showSnack(context, '资料已保存');
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存资料'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      Card(
        child: Column(
          children: [
            const ListTile(
              title: Text(
                '备份与恢复',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('备份包含批次、账单、图片、提交历史和导出文件'),
            ),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('创建完整备份'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _backup,
            ),
            ListTile(
              leading: const Icon(Icons.restore_outlined),
              title: const Text('从备份恢复'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _restore,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Card(
        child: const ListTile(
          leading: Icon(Icons.lock_outline_rounded),
          title: Text('本地离线存储'),
          subtitle: Text('账单和图片只保存在本机，除非你主动导出、分享或备份。'),
        ),
      ),
    ],
  );

  Future<void> _backup() async {
    try {
      final bytes = await BackupService().createBackup(widget.store);
      final uri = await FilePicker.saveFile(
        fileName:
            '我的报销备份_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip',
        bytes: bytes,
      );
      if (mounted) showSnack(context, uri == null ? '已取消备份' : '备份已保存');
    } catch (error) {
      if (mounted) showSnack(context, '备份失败：$error');
    }
  }

  Future<void> _restore() async {
    final file = await FilePicker.pickFile(
      allowedExtensions: ['zip'],
      type: FileType.custom,
    );
    if (file == null || !mounted) return;
    final ok = await confirm(context, '恢复备份？', '当前数据会先保留一份内部备份，然后用所选备份完整替换。');
    if (!ok) return;
    try {
      final current = await BackupService().createBackup(widget.store);
      final root = await widget.store.rootDirectory;
      await File('${root.path}${Platform.pathSeparator}pre_restore_backup.zip')
          .writeAsBytes(current, flush: true);
      final summary = await BackupService().restoreBackup(
        widget.store,
        await file.readAsBytes(),
      );
      if (mounted) showSnack(context, '恢复完成：${summary.description}');
    } catch (error) {
      if (mounted) showSnack(context, '恢复失败，原数据仍保留：$error');
    }
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today_outlined),
      ),
      child: Text(value == null ? '选择日期' : formatDate(value!)),
    ),
  );
}

String formatMoney(int cents) => '￥${(cents / 100).toStringAsFixed(2)}';
String centsToInput(int cents) =>
    cents == 0 ? '' : (cents / 100).toStringAsFixed(2);
int parseCents(String input) {
  final value = double.tryParse(input.trim().replaceAll(',', ''));
  return value == null ? 0 : (value * 100).round();
}

String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecondsSinceEpoch % 10000}';
IconData _categoryIcon(String category) => switch (category) {
  '交通' || '打车' => Icons.directions_car_outlined,
  '住宿' => Icons.hotel_outlined,
  '餐饮' => Icons.restaurant_outlined,
  '停车' => Icons.local_parking_outlined,
  '过路' => Icons.toll_outlined,
  '油费' => Icons.local_gas_station_outlined,
  _ => Icons.receipt_long_outlined,
};
void showSnack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;

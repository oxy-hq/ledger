import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/view_schema.dart';
import '../services/log_now.dart';
import '../services/sheets_repository.dart';
import 'form_screen.dart';
import 'templates_screen.dart';

/// Date-filtered list of records for a single view.
class TimelineScreen extends StatefulWidget {
  final ViewSchema view;
  final SheetsRepository repository;

  const TimelineScreen({
    super.key,
    required this.view,
    required this.repository,
  });

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  DateTime _selectedDate = _today();
  late Future<List<Record>> _records;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _records = _fetch();
  }

  Future<List<Record>> _fetch() async {
    if (widget.view.dateField == null) {
      return widget.repository.list(widget.view);
    }
    return widget.repository.list(widget.view, onDate: _selectedDate);
  }

  void _reload() {
    setState(() {
      _records = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasTemplates = widget.view.plannable != null ||
        true; // always show templates button; it'll show "no templates" if empty
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.view.name),
        actions: [
          if (hasTemplates)
            IconButton(
              icon: const Icon(Icons.list_alt),
              onPressed: _openTemplates,
              tooltip: 'Templates',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.view.dateField != null)
            _DateBar(
              selected: _selectedDate,
              onChanged: (d) {
                setState(() => _selectedDate = d);
                _reload();
              },
            ),
          Expanded(
            child: FutureBuilder<List<Record>>(
              future: _records,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _ErrorView(error: snap.error.toString());
                }
                final records = snap.data ?? [];
                if (records.isEmpty) {
                  return const Center(child: Text('No entries.'));
                }
                return ListView.separated(
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _RecordTile(
                    view: widget.view,
                    record: records[i],
                    onTap: () => _edit(records[i]),
                    onDelete: () => _delete(records[i]),
                    onLogNow: () => _logNow(records[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _openTemplates() async {
    final applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TemplatesScreen(
          view: widget.view,
          repository: widget.repository,
          onDate: _selectedDate,
        ),
      ),
    );
    if (applied == true) _reload();
  }

  Future<void> _create() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FormScreen(
          view: widget.view,
          repository: widget.repository,
        ),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _edit(Record record) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FormScreen(
          view: widget.view,
          repository: widget.repository,
          existing: record,
        ),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(Record record) async {
    final id = record['id']?.toString();
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(_titleFor(widget.view, record)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.repository.delete(widget.view, id);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> _logNow(Record record) async {
    final plannable = widget.view.plannable;
    if (plannable == null) return;
    record[plannable.logField] = logNowValue(plannable.logFormat);
    try {
      await widget.repository.update(widget.view, record);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Log failed: $e')),
      );
    }
  }
}

String _titleFor(ViewSchema view, Record record) {
  final titleField = view.listDisplay?.title ?? view.dimensions.first.name;
  final v = record[titleField];
  return v?.toString() ?? '—';
}

String? _subtitleFor(ViewSchema view, Record record) {
  final template = view.listDisplay?.subtitle;
  if (template == null) return null;
  return _interpolate(template, record);
}

/// Substitutes ${field} references in [template] with values from [record].
String _interpolate(String template, Record record) {
  final re = RegExp(r'\$\{([^}]+)\}');
  return template.replaceAllMapped(re, (m) {
    final key = m.group(1)!;
    final v = record[key];
    return v?.toString() ?? '';
  });
}

class _DateBar extends StatelessWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;

  const _DateBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('EEE, MMM d');
    final isToday = _isSameDay(selected, _now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                onChanged(selected.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selected,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(_now().year + 5),
                );
                if (picked != null) onChanged(picked);
              },
              child: Text(
                isToday ? 'Today' : formatter.format(selected),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () =>
                onChanged(selected.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }

  static DateTime _now() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _RecordTile extends StatelessWidget {
  final ViewSchema view;
  final Record record;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onLogNow;

  const _RecordTile({
    required this.view,
    required this.record,
    required this.onTap,
    required this.onDelete,
    required this.onLogNow,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitleFor(view, record);
    final planned = isPlanned(view, record);
    return Dismissible(
      key: ValueKey(record['id'] ?? UniqueKey()),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: ListTile(
        leading: planned
            ? const Icon(Icons.radio_button_unchecked, color: Colors.orange)
            : const Icon(Icons.check_circle, color: Colors.green),
        title: Text(_titleFor(view, record)),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: planned
            ? FilledButton.tonal(
                onPressed: onLogNow,
                child: const Text('Log now'),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text('Error: $error', textAlign: TextAlign.center),
      ),
    );
  }
}

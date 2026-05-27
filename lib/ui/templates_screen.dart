import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/template.dart';
import '../models/view_schema.dart';
import '../services/derive.dart';
import '../services/sheets_repository.dart';
import '../services/template_loader.dart';

/// Shows templates available for [view]; tapping one creates N "planned"
/// records in the view's table for [onDate].
class TemplatesScreen extends StatefulWidget {
  final ViewSchema view;
  final SheetsRepository repository;
  final DateTime onDate;

  const TemplatesScreen({
    super.key,
    required this.view,
    required this.repository,
    required this.onDate,
  });

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  late Future<List<Template>> _templates;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _templates = TemplateLoader.loadForView(widget.view.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Templates: ${widget.view.name}'),
      ),
      body: FutureBuilder<List<Template>>(
        future: _templates,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: ${snap.error}'),
            );
          }
          final templates = snap.data ?? [];
          if (templates.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No templates for "${widget.view.name}".\n\n'
                  'Add YAML files to '
                  '~/repos/ledger-schemas/templates/${widget.view.name}/ '
                  'and re-run tool/sync_assets.sh.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: templates.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _TemplateTile(
              template: templates[i],
              onDate: widget.onDate,
              onApply: () => _apply(templates[i]),
              disabled: _applying,
            ),
          );
        },
      ),
    );
  }

  Future<void> _apply(Template template) async {
    final dateLabel = DateFormat('EEE, MMM d').format(widget.onDate);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Apply "${template.name}"?'),
        content: Text(
          'Creates ${template.entries.length} planned ${widget.view.name} '
          'entries for $dateLabel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Create ${template.entries.length}'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _applying = true);
    try {
      final dateDim = widget.view.dateField;
      for (final entry in template.entries) {
        final record = Map<String, Object?>.from(entry);
        if (dateDim != null) {
          record[dateDim] ??= widget.onDate;
        }
        applyDerives(widget.view, record);
        await widget.repository.create(widget.view, record);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true); // signal "refresh timeline"
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Apply failed: $e')),
      );
    }
  }
}

class _TemplateTile extends StatelessWidget {
  final Template template;
  final DateTime onDate;
  final VoidCallback onApply;
  final bool disabled;

  const _TemplateTile({
    required this.template,
    required this.onDate,
    required this.onApply,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(template.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (template.description != null) Text(template.description!),
          Text('${template.entries.length} entries'),
        ],
      ),
      trailing: const Icon(Icons.add),
      onTap: disabled ? null : onApply,
    );
  }
}

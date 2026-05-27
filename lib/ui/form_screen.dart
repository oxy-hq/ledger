import 'package:flutter/material.dart';

import '../models/view_schema.dart';
import '../services/derive.dart';
import '../services/sheets_repository.dart';
import 'widgets/field_widgets.dart';

/// Auto-generated entry form. Renders one input per editable dimension.
/// In create mode (existing == null), applies input.default values.
/// In edit mode, pre-fills from [existing] and saves via update().
class FormScreen extends StatefulWidget {
  final ViewSchema view;
  final SheetsRepository repository;
  final Record? existing;

  const FormScreen({
    super.key,
    required this.view,
    required this.repository,
    this.existing,
  });

  bool get isEdit => existing != null;

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  late final Record _record;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _record = <String, Object?>{};
    if (widget.isEdit) {
      _record.addAll(widget.existing!);
    } else {
      for (final dim in widget.view.editableDimensions) {
        final d = resolveDefault(dim);
        if (d != null) _record[dim.name] = d;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.isEdit ? "Edit" : "New"} ${widget.view.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saving ? null : _save,
            tooltip: 'Save',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final dim in widget.view.editableDimensions) ...[
              buildFieldWidget(
                dim: dim,
                value: _record[dim.name],
                onChanged: (v) => setState(() => _record[dim.name] = v),
              ),
              const SizedBox(height: 12),
            ],
            if (_saving) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final missing = <String>[];
    for (final dim in widget.view.editableDimensions) {
      if (dim.input?.required == true && _record[dim.name] == null) {
        missing.add(dim.name);
      }
    }
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Required: ${missing.join(", ")}')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      applyDerives(widget.view, _record);
      if (widget.isEdit) {
        await widget.repository.update(widget.view, _record);
      } else {
        await widget.repository.create(widget.view, _record);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }
}

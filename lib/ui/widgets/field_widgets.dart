import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/view_schema.dart';

/// Resolves an input.default value into an actual Dart value at form-creation
/// time. Supports the strings 'now' (DateTime.now()) and 'today' (date only).
Object? resolveDefault(Dimension dim) {
  final raw = dim.input?.defaultValue;
  if (raw == null) return null;
  if (raw is String) {
    if (raw == 'now') return DateTime.now();
    if (raw == 'today') {
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day);
    }
  }
  return raw;
}

/// Dispatches to the correct field widget for [dim.input.widget].
Widget buildFieldWidget({
  required Dimension dim,
  required Object? value,
  required ValueChanged<Object?> onChanged,
}) {
  final widget = dim.input?.widget ?? _widgetForType(dim.type);
  switch (widget) {
    case WidgetType.text:
      return _TextFieldWidget(dim: dim, value: value, onChanged: onChanged);
    case WidgetType.longtext:
      return _TextFieldWidget(
        dim: dim,
        value: value,
        onChanged: onChanged,
        maxLines: 4,
      );
    case WidgetType.number:
      return _NumberFieldWidget(dim: dim, value: value, onChanged: onChanged);
    case WidgetType.date:
      return _DateFieldWidget(
        dim: dim,
        value: value,
        onChanged: onChanged,
        includeTime: false,
      );
    case WidgetType.datetime:
      return _DateFieldWidget(
        dim: dim,
        value: value,
        onChanged: onChanged,
        includeTime: true,
      );
    case WidgetType.dropdown:
      return _DropdownFieldWidget(dim: dim, value: value, onChanged: onChanged);
  }
}

WidgetType _widgetForType(DimensionType t) {
  switch (t) {
    case DimensionType.number:
      return WidgetType.number;
    case DimensionType.date:
      return WidgetType.date;
    case DimensionType.datetime:
      return WidgetType.datetime;
    case DimensionType.string:
    case DimensionType.boolean:
      return WidgetType.text;
  }
}

String _labelFor(Dimension dim) {
  final required = dim.input?.required == true ? ' *' : '';
  return '${dim.name}$required';
}

class _TextFieldWidget extends StatefulWidget {
  final Dimension dim;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final int maxLines;

  const _TextFieldWidget({
    required this.dim,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
  });

  @override
  State<_TextFieldWidget> createState() => _TextFieldWidgetState();
}

class _TextFieldWidgetState extends State<_TextFieldWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: _labelFor(widget.dim),
        hintText: widget.dim.input?.placeholder,
        helperText: widget.dim.description,
        border: const OutlineInputBorder(),
      ),
      onChanged: (s) => widget.onChanged(s.isEmpty ? null : s),
    );
  }
}

class _NumberFieldWidget extends StatefulWidget {
  final Dimension dim;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  const _NumberFieldWidget({
    required this.dim,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_NumberFieldWidget> createState() => _NumberFieldWidgetState();
}

class _NumberFieldWidgetState extends State<_NumberFieldWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.dim.input;
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: _labelFor(widget.dim),
        hintText: input?.placeholder,
        helperText: widget.dim.description,
        border: const OutlineInputBorder(),
      ),
      onChanged: (s) {
        if (s.isEmpty) {
          widget.onChanged(null);
          return;
        }
        final n = num.tryParse(s);
        widget.onChanged(n);
      },
    );
  }
}

class _DateFieldWidget extends StatelessWidget {
  final Dimension dim;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final bool includeTime;

  const _DateFieldWidget({
    required this.dim,
    required this.value,
    required this.onChanged,
    required this.includeTime,
  });

  @override
  Widget build(BuildContext context) {
    final current = value is DateTime ? value as DateTime : null;
    final formatter = includeTime
        ? DateFormat('yyyy-MM-dd HH:mm')
        : DateFormat('yyyy-MM-dd');
    final display = current == null ? '—' : formatter.format(current);

    return InkWell(
      onTap: () => _pick(context, current),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: _labelFor(dim),
          helperText: dim.description,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(display),
            const Icon(Icons.calendar_today, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, DateTime? current) async {
    final now = DateTime.now();
    final initialDate = current ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    if (!includeTime) {
      onChanged(DateTime(picked.year, picked.month, picked.day));
      return;
    }
    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    final t = time ?? TimeOfDay.fromDateTime(initialDate);
    onChanged(
      DateTime(picked.year, picked.month, picked.day, t.hour, t.minute),
    );
  }
}

class _DropdownFieldWidget extends StatelessWidget {
  final Dimension dim;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  const _DropdownFieldWidget({
    required this.dim,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = dim.input?.options ?? dim.samples ?? const <String>[];
    final current = value?.toString();
    return DropdownButtonFormField<String>(
      initialValue: options.contains(current) ? current : null,
      decoration: InputDecoration(
        labelText: _labelFor(dim),
        helperText: dim.description,
        border: const OutlineInputBorder(),
      ),
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

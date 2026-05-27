import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/view_schema.dart';
import '../services/app_config.dart';
import '../services/schema_loader.dart';
import '../services/sheets_repository.dart';
import 'timeline_screen.dart';

/// App entrypoint screen. Loads config + schemas, connects to Sheets, and
/// presents the list of views.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_Bootstrap> _bootstrap;

  @override
  void initState() {
    super.initState();
    _bootstrap = _initialize();
  }

  Future<_Bootstrap> _initialize() async {
    final config = await AppConfig.load();
    final views = await SchemaLoader.loadAll();
    final keyJson = await rootBundle.loadString('assets/service-account.json');
    final repo = await SheetsRepository.connectFromKey(
      defaultSpreadsheetId: config.spreadsheetId,
      serviceAccountKeyJson: keyJson,
    );
    for (final view in views) {
      await repo.ensureSheet(view);
    }
    return _Bootstrap(views: views, repository: repo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _bootstrap = _initialize()),
            tooltip: 'Reload schemas',
          ),
        ],
      ),
      body: FutureBuilder<_Bootstrap>(
        future: _bootstrap,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorView(error: snap.error.toString());
          }
          final data = snap.data!;
          if (data.views.isEmpty) {
            return const Center(child: Text('No views in assets/schemas/.'));
          }
          return ListView.separated(
            itemCount: data.views.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final view = data.views[i];
              return ListTile(
                title: Text(view.name),
                subtitle: view.description == null ? null : Text(view.description!),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TimelineScreen(
                      view: view,
                      repository: data.repository,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Bootstrap {
  final List<ViewSchema> views;
  final SheetsRepository repository;
  _Bootstrap({required this.views, required this.repository});
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Startup error',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SelectableText(
              error,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}

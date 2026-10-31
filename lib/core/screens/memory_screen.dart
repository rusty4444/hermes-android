import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import '../models/memory_fact.dart';
import '../services/connection_manager.dart';
import '../services/memory_repository.dart';

/// Saved built-in memory facts for the connected Hermes profile, not settings.
class MemoryScreen extends StatefulWidget {
  final SavedConnection connection;

  /// The screen owns this client just as it owns its production client.
  @visibleForTesting
  final http.Client? testHttpClient;

  const MemoryScreen({
    required this.connection,
    this.testHttpClient,
    super.key,
  });

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  MemoryRepository? _repository;
  List<MemoryFact> _facts = const [];
  Future<void>? _loadFlight;
  int _generation = 0;
  bool _loading = false;
  bool _hasError = false;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _loadMemory();
  }

  @override
  void didUpdateWidget(covariant MemoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection != widget.connection ||
        oldWidget.testHttpClient != widget.testHttpClient) {
      _generation++;
      _loadFlight = null;
      _repository?.close();
      _repository = null;
      _facts = const [];
      _loadMemory();
    }
  }

  @override
  void dispose() {
    _generation++;
    _repository?.close();
    super.dispose();
  }

  Future<void> _loadMemory() {
    final inFlight = _loadFlight;
    if (inFlight != null) return inFlight;
    final future = _readMemory(++_generation);
    _loadFlight = future;
    future.whenComplete(() {
      if (identical(_loadFlight, future)) _loadFlight = null;
    }).ignore();
    return future;
  }

  bool _owns(int generation) => mounted && generation == _generation;

  Future<void> _readMemory(int generation) async {
    setState(() {
      _loading = true;
      _hasError = false;
      _unavailable = false;
    });
    try {
      final repository = _repository ??= MemoryRepository.fromConnection(
        widget.connection,
        httpClient: widget.testHttpClient,
      );
      final facts = await repository.loadFacts();
      if (!_owns(generation)) return;
      setState(() {
        _facts = facts;
        _loading = false;
      });
    } catch (error) {
      if (!_owns(generation)) return;
      setState(() {
        _hasError = true;
        _unavailable =
            error is FormatException ||
            (error is DashboardHttpException &&
                const [404, 405, 501].contains(error.statusCode));
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      key: ValueKey(widget.connection),
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(context)
              .scale(kToolbarHeight)
              .clamp(kToolbarHeight, double.infinity)
              .toDouble(),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.memory),
              Text(
                widget.connection.gatewayProfile ?? widget.connection.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: context.l10n.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _loadMemory,
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: context.l10n.memory_about_you),
              Tab(text: context.l10n.memory_agent_notes),
            ],
          ),
        ),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.failed_to_load_memory,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _unavailable
                ? context.l10n.memory_unavailable
                : context.l10n.memory_load_error,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _loadMemory, child: Text(context.l10n.retry)),
        ],
      );
    }
    return TabBarView(
      children: [
        _buildFacts(context, MemoryFactSource.profile),
        _buildFacts(context, MemoryFactSource.memory),
      ],
    );
  }

  Widget _buildFacts(BuildContext context, MemoryFactSource source) {
    final facts = _facts.where((fact) => fact.source == source).toList();
    return RefreshIndicator(
      onRefresh: _loadMemory,
      child: ListView.builder(
        key: PageStorageKey(source),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: facts.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.memory_builtin_scope),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.memory_read_only,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.source(source.fileName),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            );
          }
          if (index == facts.length + 1) {
            if (facts.isNotEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  const Icon(Icons.psychology_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.no_memory_entries,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context
                        .l10n
                        .memory_entries_are_cross_session_facts_the_agent_remembers_they,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          final fact = facts[index - 1];
          return _MemoryFactCard(
            key: ValueKey('$_generation:${fact.id}'),
            fact: fact,
            repository: _repository!,
          );
        },
      ),
    );
  }
}

class _MemoryFactCard extends StatefulWidget {
  final MemoryFact fact;
  final MemoryRepository repository;

  const _MemoryFactCard({
    required this.fact,
    required this.repository,
    super.key,
  });

  @override
  State<_MemoryFactCard> createState() => _MemoryFactCardState();
}

class _MemoryFactCardState extends State<_MemoryFactCard> {
  String? _fullContent;
  bool _loading = false;
  bool _failed = false;

  Future<void> _loadFullFact() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final content = await widget.repository.loadFullFact(widget.fact);
      if (!mounted) return;
      setState(() {
        _fullContent = content;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(_fullContent ?? widget.fact.content),
            if (widget.fact.mayBeTruncated && _fullContent == null) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.preview_truncated,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (!widget.fact.hasStableIdentity)
                Text(context.l10n.memory_full_fact_requires_update)
              else ...[
                if (_failed) Text(context.l10n.memory_fact_detail_error),
                if (_loading)
                  const LinearProgressIndicator()
                else
                  TextButton(
                    onPressed: _loadFullFact,
                    child: Text(context.l10n.memory_read_full_fact),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

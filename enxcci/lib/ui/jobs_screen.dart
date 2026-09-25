import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/jobs/script_registry.dart';
import 'package:enxcci/ui/app_controller.dart';

class JobsScreen extends StatelessWidget {
  const JobsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('Jobs EnXcci')),
          body: controller.jobs.isEmpty
              ? const Center(
                  child: Text('Nenhum job configurado',
                      style: TextStyle(color: Colors.white60)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: controller.jobs.length,
                  itemBuilder: (context, index) => _JobCard(
                    controller: controller,
                    job: controller.jobs[index],
                  ),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: ScriptRegistry.getAll().isEmpty
                ? null
                : () => _showJobEditor(context, controller, controller.newJob()),
            icon: const Icon(Icons.add),
            label: const Text('Criar job'),
          ),
        ),
      );
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.controller, required this.job});
  final AppController controller;
  final EnXJob job;

  @override
  Widget build(BuildContext context) {
    final script = ScriptRegistry.get(job.scriptId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(job.label,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Switch(
                value: job.active,
                onChanged: (value) => controller.toggleJob(job, value)),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') _showJobEditor(context, controller, job);
                if (value == 'run') controller.scheduler.runNow(job);
                if (value == 'delete') controller.removeJob(job);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'run', child: Text('Executar agora')),
                PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(value: 'delete', child: Text('Remover')),
              ],
            ),
          ]),
          Text(
            'Script: ${script?.label ?? job.scriptId} · A cada ${job.intervalSeconds}s · ${job.targetTable}',
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 10),
          Text(
            job.lastResult ?? 'Ainda não executado',
            style: TextStyle(
                color: job.lastResult == null
                    ? Colors.white54
                    : const Color(0xFF41D5C3)),
          ),
          const SizedBox(height: 5),
          Text(
            job.nextRun == null
                ? 'Próximo run: aguardando'
                : 'Próximo run: ${DateFormat('HH:mm:ss').format(job.nextRun!.toLocal())}',
            style: const TextStyle(color: Colors.white54),
          ),
        ]),
      ),
    );
  }
}

Future<void> _showJobEditor(
    BuildContext context, AppController controller, EnXJob initial) async {
  final label = TextEditingController(text: initial.label);
  final target = TextEditingController(text: initial.targetTable);
  final shard = TextEditingController(text: initial.seedShard ?? '');
  final interval =
      TextEditingController(text: '${initial.intervalSeconds}');
  var scriptId = initial.scriptId.isNotEmpty
      ? initial.scriptId
      : ScriptRegistry.getAll().firstOrNull?.id ?? '';
  final formKey = GlobalKey<FormState>();

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(initial.label.isEmpty ? 'Novo job' : 'Editar job'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(label, 'Nome do job'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: ScriptRegistry.getAll().any((s) => s.id == scriptId)
    ? scriptId
    : null,
                decoration: const InputDecoration(labelText: 'Script'),
                items: ScriptRegistry.getAll()
    .map((s) => DropdownMenuItem(value: s.id ?? '', child: Text(s.label ?? '')))
    .toList(),
                onChanged: (value) =>
                    setState(() => scriptId = value ?? ''),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Obrigatório' : null,
              ),
              _field(target, 'Tabela Dataniverse'),
              _field(shard, 'Seed Shard (opcional)', required: false),
              _field(interval, 'Intervalo (segundos)',
                  keyboard: TextInputType.number),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              await controller.upsertJob(initial.copyWith(
                label: label.text.trim(),
                scriptId: scriptId,
                targetTable: target.text.trim(),
                seedShard: shard.text.trim().isEmpty ? null : shard.text.trim(),
                intervalSeconds: int.tryParse(interval.text) ?? 60,
              ));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

Widget _field(
  TextEditingController controller,
  String label, {
  TextInputType? keyboard,
  bool required = true,
}) =>
    Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) =>
                value == null || value.trim().isEmpty ? 'Obrigatório' : null
            : null,
      ),
    );
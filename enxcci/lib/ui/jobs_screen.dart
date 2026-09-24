import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/enxcci_config.dart';
import 'app_controller.dart';

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
              ? const Center(child: Text('Nenhum job configurado', style: TextStyle(color: Colors.white60)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: controller.jobs.length,
                  itemBuilder: (context, index) => _JobCard(controller: controller, job: controller.jobs[index]),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: controller.connections.isEmpty ? null : () => _showJobEditor(context, controller, controller.newJob()),
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
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(job.label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              Switch(value: job.active, onChanged: (value) => controller.toggleJob(job, value)),
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
            Text('A cada ${job.intervalSeconds}s · ${job.targetTable}', style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 10),
            Text(job.lastResult ?? 'Ainda não executado', style: TextStyle(color: job.lastResult == null ? Colors.white54 : const Color(0xFF41D5C3))),
            const SizedBox(height: 5),
            Text(
              job.nextRun == null
                  ? 'Próximo run: aguardando'
                  : 'Próximo run: ${DateFormat('HH:mm:ss').format(job.nextRun!.toLocal())}',
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 5),
            Text('Query: ${job.query}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', color: Colors.white54)),
          ]),
        ),
      );
}

Future<void> _showJobEditor(BuildContext context, AppController controller, EnXJob initial) async {
  final label = TextEditingController(text: initial.label);
  final query = TextEditingController(text: initial.query);
  final target = TextEditingController(text: initial.targetTable);
  final interval = TextEditingController(text: '${initial.intervalSeconds}');
  var connectionId = initial.connectionId;
  final formKey = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(
      title: Text(initial.label.isEmpty ? 'Novo job' : 'Editar job'),
      content: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
        _jobField(label, 'Nome'),
        DropdownButtonFormField<String>(
          value: controller.connections.any((item) => item.id == connectionId) ? connectionId : null,
          decoration: const InputDecoration(labelText: 'Conexão'),
          items: controller.connections.map((item) => DropdownMenuItem(value: item.id, child: Text(item.label))).toList(),
          onChanged: (value) => setState(() => connectionId = value ?? ''),
          validator: (value) => value == null || value.isEmpty ? 'Obrigatório' : null,
        ),
        _jobField(query, 'Query SELECT', maxLines: 3),
        _jobField(target, 'Tabela Dataniverse'),
        _jobField(interval, 'Intervalo (segundos)', keyboard: TextInputType.number),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () async {
          if (!(formKey.currentState?.validate() ?? false)) return;
          await controller.upsertJob(initial.copyWith(
            label: label.text.trim(),
            connectionId: connectionId,
            query: query.text.trim(),
            targetTable: target.text.trim(),
            intervalSeconds: int.tryParse(interval.text) ?? 60,
          ));
          if (context.mounted) Navigator.pop(context);
        }, child: const Text('Salvar')),
      ],
    )),
  );
}

Widget _jobField(TextEditingController controller, String label, {int maxLines = 1, TextInputType? keyboard}) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(controller: controller, maxLines: maxLines, keyboardType: keyboard, decoration: InputDecoration(labelText: label), validator: (value) => value == null || value.trim().isEmpty ? 'Obrigatório' : null),
    );
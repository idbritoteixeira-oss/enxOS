import 'package:flutter/material.dart';

import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/ui/app_controller.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('Gateways enxOS'), actions: [
            IconButton(onPressed: controller.healthWatchdog, icon: const Icon(Icons.refresh)),
          ]),
          body: controller.connections.isEmpty
              ? const Center(child: Text('Nenhuma conexão configurada', style: TextStyle(color: Colors.white60)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: controller.connections.length,
                  itemBuilder: (context, index) {
                    final connection = controller.connections[index];
                    return _ConnectionTile(controller: controller, connection: connection);
                  },
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showConnectionEditor(context, controller, controller.newConnection()),
            child: const Icon(Icons.add),
          ),
        ),
      );
}

class _ConnectionTile extends StatefulWidget {
  const _ConnectionTile({required this.controller, required this.connection});

  final AppController controller;
  final EnXcciConfig connection;

  @override
  State<_ConnectionTile> createState() => _ConnectionTileState();
}

class _ConnectionTileState extends State<_ConnectionTile> {
  bool? online;
  int? latency;

  @override
  void initState() {
    super.initState();
    _ping();
  }

  Future<void> _ping() async {
    final result = await widget.controller.pingConnection(widget.connection);
    if (mounted) setState(() { online = result.online; latency = result.latencyMs; });
  }

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: () => _showConnectionEditor(context, widget.controller, widget.connection),
          leading: CircleAvatar(
            backgroundColor: (online == true ? const Color(0xFF41D5C3) : online == false ? const Color(0xFFFF6B7A) : Colors.white24).withValues(alpha: .16),
            child: Icon(Icons.storage, color: online == true ? const Color(0xFF41D5C3) : online == false ? const Color(0xFFFF6B7A) : Colors.white54),
          ),
          title: Text(widget.connection.label),
          subtitle: Text('${widget.connection.gatewayUrl} · perfil ${widget.connection.profile}\n${online == true ? 'Online · ${latency ?? 0} ms' : online == false ? 'Offline' : 'Testando...'}'),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: widget.connection.active,
                onChanged: (value) => widget.controller.upsertConnection(
                  widget.connection.copyWith(active: value),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    _showConnectionEditor(context, widget.controller, widget.connection);
                  } else if (value == 'ping') {
                    _ping();
                  } else {
                    await widget.controller.removeConnection(widget.connection);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'ping', child: Text('Testar ping')),
                  PopupMenuItem(value: 'delete', child: Text('Remover')),
                ],
              ),
            ],
          ),
        ),
      );
}

Future<void> _showConnectionEditor(BuildContext context, AppController controller, EnXcciConfig initial) async {
  final label = TextEditingController(text: initial.label);
  final gatewayUrl = TextEditingController(text: initial.gatewayUrl);
  final token = TextEditingController(text: initial.token);
  final profile = TextEditingController(text: initial.profile);
  final formKey = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initial.label.isEmpty ? 'Nova conexão' : 'Editar conexão'),
      content: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
        _field(label, 'Nome'),
        _field(gatewayUrl, 'URL do API Gateway'),
        _field(token, 'Token X-EnX-Token', obscure: true),
        _field(profile, 'Perfil MySQL no gateway'),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            if (!(formKey.currentState?.validate() ?? false)) return;
            await controller.upsertConnection(initial.copyWith(
              label: label.text.trim(),
              gatewayUrl: gatewayUrl.text.trim(),
              token: token.text,
              profile: profile.text.trim(),
            ));
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
}

Widget _field(TextEditingController controller, String label, {bool obscure = false, TextInputType? keyboard}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(controller: controller, obscureText: obscure, keyboardType: keyboard, decoration: InputDecoration(labelText: label), validator: (value) => value == null || value.trim().isEmpty ? 'Obrigatório' : null),
    );
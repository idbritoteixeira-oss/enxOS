import 'package:flutter/material.dart';

import 'package:enxcci/database/enx_api_provider.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/ui/app_controller.dart';

class ActionHashScreen extends StatefulWidget {
  const ActionHashScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<ActionHashScreen> createState() => _ActionHashScreenState();
}

class _ActionHashScreenState extends State<ActionHashScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  EnXApiProvider? _createApi() {
    final active = widget.controller.connections
        .where((c) => c.active)
        .toList();
    if (active.isEmpty) return null;
    return EnXApiProvider(config: active.first);
  }

  Future<String?> _getCurrentDtts() async {
    try {
      return await OttsVision.currentDtts(widget.controller.dataniverse);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.controller.dataniverse.command({
        'action': 'LIST_RECORDS',
        'table': 'actionhash',
      });

      final data = result['data'];
      setState(() {
        _items = data is List ? data.cast<Map<String, dynamic>>() : [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('ActionHash (obj.ah)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFFF6B7A))))
              : _items.isEmpty
                  ? const Center(
                      child: Text('Nenhum obj.ah encontrado',
                          style: TextStyle(color: Colors.white60)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _ActionHashCard(
                          item: item,
                          onTap: () => _showDetails(context, item),
                          onAction: (action) =>
                              _triggerAction(context, item, action),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Criar obj.ah'),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final ownerCtrl = TextEditingController(text: '123456789012');
    final valueCtrl = TextEditingController(text: '0.000000');
    final plantedCtrl = TextEditingController(text: '1010');
    final limiteCtrl = TextEditingController(text: '0');
    final imagePixelCtrl = TextEditingController(text: 'pixel_test');
    final contentCtrl = TextEditingController(
        text: '{"name": "", "date": "", "desc": ""}');
    String typeobj = 'coin';
    String limited = 'false';
    String transferable = 'true';

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Novo obj.ah'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      PixelImage(code: imagePixelCtrl.text, size: 56),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Prévia do image_pixel (formato P256)',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _field(ownerCtrl, 'Owner (12 dígitos)', required: true),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: typeobj,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: const [
                      DropdownMenuItem(value: 'coin', child: Text('coin')),
                      DropdownMenuItem(value: 'badge', child: Text('badge')),
                      DropdownMenuItem(value: 'text', child: Text('text')),
                      DropdownMenuItem(value: 'pop', child: Text('pop')),
                    ],
                    onChanged: (v) => setState(() => typeobj = v ?? 'coin'),
                  ),
                  const SizedBox(height: 8),
                  _field(valueCtrl, 'Value'),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: limited,
                          decoration:
                              const InputDecoration(labelText: 'Limited'),
                          items: const [
                            DropdownMenuItem(
                                value: 'false', child: Text('false')),
                            DropdownMenuItem(
                                value: 'true', child: Text('true')),
                          ],
                          onChanged: (v) =>
                              setState(() => limited = v ?? 'false'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: transferable,
                          decoration: const InputDecoration(
                              labelText: 'Transferable'),
                          items: const [
                            DropdownMenuItem(
                                value: 'true', child: Text('true')),
                            DropdownMenuItem(
                                value: 'false', child: Text('false')),
                          ],
                          onChanged: (v) =>
                              setState(() => transferable = v ?? 'true'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _field(plantedCtrl, 'Planted (série)')),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(limiteCtrl, 'Limite (0=ilimitado)',
                            keyboard: TextInputType.number),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: imagePixelCtrl,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Image Pixel (P256|cores|indices)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: contentCtrl,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Content JSON',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                final api = _createApi();
                if (api == null) {
                  _showError(context, 'Nenhuma conexão ativa');
                  return;
                }

                final dtts = await _getCurrentDtts();
                if (dtts == null || dtts.isEmpty) {
                  _showError(context, 'DTTS inválido ou ausente');
                  api.dispose();
                  return;
                }

                final imagePixel = imagePixelCtrl.text.trim().replaceAll("'", '');
                final contentJson = contentCtrl.text.trim().replaceAll("'", '');

                try {
                  await api.query('''
                    INSERT INTO actionhash 
                    (idaction, owner, typeobj, limited, transferable, used, executes, 
                     image_pixel, value, planted, content_json, limite, log)
                    VALUES 
                    ('TEMP${DateTime.now().millisecondsSinceEpoch}', 
                     '${ownerCtrl.text.trim()}', 
                     '$typeobj', 
                     '$limited', 
                     '$transferable', 
                     'false', 
                     'obj', 
                     '$imagePixel', 
                     '${valueCtrl.text.trim()}', 
                     '${plantedCtrl.text.trim()}', 
                     '$contentJson', 
                     '${limiteCtrl.text.trim()}', 
                     'aguardando criação')
                  ''', dtts: dtts);

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'obj.ah enviado para o Job (executes = obj)')),
                    );
                    _load();
                  }
                } catch (e) {
                  _showError(context, 'Erro: $e');
                } finally {
                  api.dispose();
                }
              },
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: PixelImage(
                code: item['image_pixel']?.toString(),
                size: 128,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              item['idaction']?.toString() ?? '—',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            _detailRow('Owner', item['owner']),
            _detailRow('Tipo', item['typeobj']),
            _detailRow('Value', item['value']),
            _detailRow('Planted', item['planted']),
            _detailRow('Limite', item['limite']),
            _detailRow('Série', item['serie'] ?? item['content_json']),
            _detailRow('Limited', item['limited']),
            _detailRow('Transferable', item['transferable']),
            _detailRow('Used', item['used']),
            _detailRow('Log', item['log']),
            const SizedBox(height: 12),
            const Text(
              'hashprivate (sensível)',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            SelectableText(
              item['hashprivate']?.toString() ?? '—',
              style: const TextStyle(
                color: Color(0xFF41D5C3),
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _triggerAction(context, item, 'use');
                    },
                    child: const Text('Usar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _triggerAction(context, item, 'transation');
                    },
                    child: const Text('Transferir'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B7A),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _triggerAction(context, item, 'burn');
                    },
                    child: const Text('Queimar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? '—',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerAction(
    BuildContext context,
    Map<String, dynamic> item,
    String action,
  ) async {
    final idaction = item['idaction']?.toString();
    if (idaction == null) return;

    final api = _createApi();
    if (api == null) {
      _showError(context, 'Nenhuma conexão ativa');
      return;
    }

    final dtts = await _getCurrentDtts();
    if (dtts == null || dtts.isEmpty) {
      _showError(context, 'DTTS inválido ou ausente');
      api.dispose();
      return;
    }

    try {
      await api.query(
        "UPDATE actionhash SET executes = '$action', log = 'aguardando $action' WHERE idaction = '$idaction'",
        dtts: dtts,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ação "$action" enviada para o Job')),
        );
      }
    } catch (e) {
      _showError(context, 'Erro: $e');
    } finally {
      api.dispose();
    }
  }

  void _showError(BuildContext context, String msg) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFFFF6B7A),
        ),
      );
    }
  }
}

class _ActionHashCard extends StatelessWidget {
  const _ActionHashCard({
    required this.item,
    required this.onTap,
    required this.onAction,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final idaction = item['idaction']?.toString() ?? '—';
    final typeobj = item['typeobj']?.toString() ?? '—';
    final owner = item['owner']?.toString() ?? '—';
    final serie = item['serie']?.toString();
    final used = item['used']?.toString() == 'yes' ||
        item['used']?.toString() == 'true';

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              PixelImage(
                code: item['image_pixel']?.toString(),
                size: 56,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            idaction,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (used)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF41D5C3)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'usado',
                              style: TextStyle(
                                color: Color(0xFF41D5C3),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        PopupMenuButton<String>(
                          onSelected: onAction,
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'use', child: Text('Usar')),
                            PopupMenuItem(
                                value: 'transation',
                                child: Text('Transferir')),
                            PopupMenuItem(
                                value: 'burn', child: Text('Queimar')),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tipo: $typeobj · Owner: $owner',
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    if (serie != null && serie.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Série: $serie',
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (item['log'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item['log'].toString(),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renderiza image_pixel no formato:
/// P256|ff0000,00ff00,...|000102FF...
class PixelImage extends StatelessWidget {
  const PixelImage({super.key, required this.code, this.size = 48});

  final String? code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pixels = parsePixelCode(code);
    if (pixels == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Icon(Icons.image_not_supported,
            size: 18, color: Colors.white24),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CustomPaint(
        size: Size(size, size),
        painter: _PixelPainter(pixels),
      ),
    );
  }

  static List<List<Color>>? parsePixelCode(String? code) {
    if (code == null || !code.startsWith('P')) return null;

    try {
      final parts = code.split('|');
      if (parts.length < 3) return null;

      final palette = parts[1].split(',').map((h) {
        final cleaned = h.trim().replaceAll('#', '');
        if (cleaned.length != 6) return Colors.black;
        return Color(int.parse('FF$cleaned', radix: 16));
      }).toList();

      if (palette.isEmpty) return null;

      final indices = parts[2].replaceAll(RegExp(r'\s'), '');
      final pixels = <List<Color>>[];
      var i = 0;

      for (var y = 0; y < 32; y++) {
        final row = <Color>[];
        for (var x = 0; x < 32; x++) {
          if (i + 2 > indices.length) {
            row.add(Colors.transparent);
          } else {
            final idx = int.parse(indices.substring(i, i + 2), radix: 16);
            row.add(palette[idx.clamp(0, palette.length - 1)]);
            i += 2;
          }
        }
        pixels.add(row);
      }
      return pixels;
    } catch (_) {
      return null;
    }
  }
}

class _PixelPainter extends CustomPainter {
  _PixelPainter(this.pixels);
  final List<List<Color>> pixels;

  @override
  void paint(Canvas canvas, Size size) {
    final pw = size.width / 32;
    final ph = size.height / 32;

    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * pw, y * ph, pw + 0.5, ph + 0.5),
          Paint()..color = pixels[y][x],
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelPainter old) => old.pixels != pixels;
}

Widget _field(
  TextEditingController controller,
  String label, {
  TextInputType? keyboard,
  bool required = false,
}) {
  return Padding(
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
}
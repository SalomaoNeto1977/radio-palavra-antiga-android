import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'collaborator_access.dart';

Future<void> showCollaboratorCodeDialog(
  BuildContext context,
  CollaboratorAccessController controller,
) async {
  final bool? activated = await showDialog<bool>(
    context: context,
    builder: (_) => _CodeDialog(controller: controller),
  );
  if (activated == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Acesso de colaborador ativado. Desfruta de todo o catálogo!'),
    ));
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.controller});
  final CollaboratorAccessController controller;
  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final TextEditingController _code = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (_saving) return;
    setState(() { _saving = true; _error = null; });
    final bool active = await widget.controller.activate(_code.text);
    if (!mounted) return;
    if (active) {
      Navigator.pop(context, true);
    } else {
      setState(() { _saving = false; _error = widget.controller.message; });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Código de colaborador'),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Introduz o código que recebeste da Rádio Palavra Antiga.'),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 4,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(labelText: 'Código de quatro dígitos', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
        ],
      )),
      actions: <Widget>[
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'A ativar…' : 'OK')),
      ],
    ),
  );

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }
}

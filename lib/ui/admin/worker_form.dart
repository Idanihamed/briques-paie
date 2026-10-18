import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';

/// Opérateurs mobile money proposés (valeur envoyée à l'API -> libellé).
const mobileOperators = {
  'orange': 'Orange Money',
  'moov': 'Moov Money',
  'telecel': 'Telecel Money',
  'other': 'Autre',
};

final _phoneRe = RegExp(r'^\+?[0-9][0-9 .-]{5,19}$');

String? validatePhone(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return null; // facultatif
  return _phoneRe.hasMatch(t) ? null : 'Numéro invalide (chiffres, espaces, +).';
}

/// Résultat du formulaire : les champs vides valent « non renseigné » (null).
class WorkerFormData {
  final String fullName;
  final String? phone;
  final String? village;
  final String? mobileOperator;
  final String? mobileNumber;
  const WorkerFormData({
    required this.fullName,
    this.phone,
    this.village,
    this.mobileOperator,
    this.mobileNumber,
  });
}

/// Fiche d'enregistrement d'un ouvrier : identité, **contact**, et numéro mobile money pour les paiements.
/// Sans [existing] : nouvel ouvrier. Avec [existing] : modification des coordonnées.
Future<WorkerFormData?> showWorkerForm(BuildContext context, {WorkerInfo? existing}) {
  return showDialog<WorkerFormData>(
    context: context,
    builder: (_) => _WorkerFormDialog(existing: existing),
  );
}

class _WorkerFormDialog extends StatefulWidget {
  final WorkerInfo? existing;
  const _WorkerFormDialog({this.existing});

  @override
  State<_WorkerFormDialog> createState() => _WorkerFormDialogState();
}

class _WorkerFormDialogState extends State<_WorkerFormDialog> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.fullName ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _village = TextEditingController(text: widget.existing?.village ?? '');
  late final _mobile = TextEditingController(text: widget.existing?.mobileNumber ?? '');
  late String? _operator = widget.existing?.mobileOperator;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _village.dispose();
    _mobile.dispose();
    super.dispose();
  }

  String? _blank(String s) => s.trim().isEmpty ? null : s.trim();

  void _submit() {
    if (!(_key.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      WorkerFormData(
        fullName: _name.text.trim(),
        phone: _blank(_phone.text),
        village: _blank(_village.text),
        mobileOperator: _operator,
        mobileNumber: _operator == null ? null : _blank(_mobile.text),
      ),
    );
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: accentSoft)),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Coordonnées de ${widget.existing!.fullName}' : 'Enregistrer un ouvrier'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _key,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom complet *', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Le nom est obligatoire.' : null,
              ),
              _section('Contact'),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Téléphone', hintText: '+226 70 00 00 00', prefixIcon: Icon(Icons.phone_outlined)),
                validator: validatePhone,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _village,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Village / quartier', prefixIcon: Icon(Icons.location_on_outlined)),
              ),
              _section('Paiement mobile money (facultatif)'),
              DropdownButtonFormField<String?>(
                initialValue: _operator,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Opérateur', prefixIcon: Icon(Icons.payments_outlined)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
                  for (final e in mobileOperators.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _operator = v),
              ),
              if (_operator != null) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Numéro de réception *', prefixIcon: Icon(Icons.smartphone_outlined)),
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return 'Indiquez le numéro de réception.';
                    return validatePhone(v);
                  },
                ),
                if (_phone.text.trim().isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _mobile.text = _phone.text.trim()),
                      child: const Text('Même numéro que le téléphone'),
                    ),
                  ),
              ],
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
          onPressed: _submit,
          child: Text(editing ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}

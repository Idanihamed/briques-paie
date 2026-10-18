import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/invoice_pdf.dart';
import '../../core/documents.dart';
import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../glass.dart';
import '../widgets.dart';

const _monthNames = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

String _d2(int n) => n.toString().padLeft(2, '0');

/// « 08 au 12 juillet 2026 » ou « 28 juin 2026 au 03 juillet 2026 ».
String periodWords(DateTime a, DateTime b) {
  if (a.year == b.year && a.month == b.month) {
    return a.day == b.day
        ? '${_d2(a.day)} ${_monthNames[a.month - 1]} ${a.year}'
        : '${_d2(a.day)} au ${_d2(b.day)} ${_monthNames[a.month - 1]} ${a.year}';
  }
  return '${_d2(a.day)} ${_monthNames[a.month - 1]} ${a.year} au ${_d2(b.day)} ${_monthNames[b.month - 1]} ${b.year}';
}

void _push(BuildContext context, Widget Function() page) {
  final store = StoreScope.of(context);
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StoreScope(store: store, child: page())));
}

// ───────────────────────── Liste des factures ─────────────────────────

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  Future<List<InvoiceSummary>>? _future;

  void _reload() {
    final next = StoreScope.of(context).repo.invoices();
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.invoices();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<InvoiceSummary>>(
      future: _future!,
      onRetry: _reload,
      builder: (context, list) => ListView(padding: const EdgeInsets.all(16), children: [
        GradientButton(
          icon: Icons.note_add_outlined,
          label: 'Nouvelle facture',
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => StoreScope(store: StoreScope.of(context), child: const NewInvoiceScreen())));
            if (mounted) _reload();
          },
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          TextButton.icon(
              onPressed: () => _push(context, LetterheadScreen.new),
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text('En-tête de facture')),
          TextButton.icon(
              onPressed: () => _push(context, ClientsScreen.new),
              icon: const Icon(Icons.business_outlined, size: 18),
              label: const Text('Clients')),
        ]),
        const SectionTitle('Factures émises'),
        GlassCard(
          child: Column(children: [
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune facture pour le moment.')),
            for (final i in list)
              ListTile(
                title: Text(i.number, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${i.clientName} · ${fmtDate(i.issuedOn)} · ${fmtInt(i.totalQty)} briques'),
                trailing: i.status == 'cancelled'
                    ? const Pill('Annulée', errColor)
                    : Text(fmtFcfa(i.totalAmount), style: const TextStyle(fontWeight: FontWeight.w800)),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => StoreScope(store: StoreScope.of(context), child: InvoiceDetailScreen(id: i.id))));
                  if (mounted) _reload();
                },
              ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── En-tête de facture (aperçu + modification) ─────────────────────────

/// Aperçu fidèle de l'en-tête : logo, nom, filet. Utilisé à l'écran et dans le PDF.
class LetterheadPreview extends StatelessWidget {
  final Letterhead lh;
  const LetterheadPreview(this.lh, {super.key});

  @override
  Widget build(BuildContext context) => GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Image.asset('assets/logo.png', width: 76, height: 76),
            const SizedBox(height: 6),
            Text(lh.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const Divider(height: 12, color: Colors.white54),
            if (lh.footer.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(lh.footer, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ),
          ]),
        ),
      );
}

class LetterheadScreen extends StatefulWidget {
  const LetterheadScreen({super.key});

  @override
  State<LetterheadScreen> createState() => _LetterheadScreenState();
}

class _LetterheadScreenState extends State<LetterheadScreen> {
  Future<Letterhead>? _future;
  final _name = TextEditingController();
  final _footer = TextEditingController();
  final _place = TextEditingController();
  final _signer = TextEditingController();
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.letterhead();
  }

  @override
  void dispose() {
    for (final c in [_name, _footer, _place, _signer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final store = StoreScope.of(context);
    final lh = Letterhead(name: _name.text.trim(), footer: _footer.text.trim(), place: _place.text.trim(), signer: _signer.text.trim());
    if (lh.name.isEmpty || lh.place.isEmpty || lh.signer.isEmpty) {
      toast(context, 'Nom, lieu et signataire sont obligatoires.', error: true);
      return;
    }
    if (await run(context, () => store.repo.saveLetterhead(lh), success: 'En-tête enregistré.')) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(flexibleSpace: const GlassBar(child: SizedBox.expand()), title: const Text('En-tête de facture')),
      body: AsyncBody<Letterhead>(
        future: _future!,
        onRetry: () => setState(() => _future = StoreScope.of(context).repo.letterhead()),
        builder: (context, lh) {
          if (!_loaded) {
            _loaded = true;
            _name.text = lh.name;
            _footer.text = lh.footer;
            _place.text = lh.place;
            _signer.text = lh.signer;
          }
          final live = Letterhead(name: _name.text, footer: _footer.text, place: _place.text, signer: _signer.text);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                const SectionTitle('Aperçu'),
                LetterheadPreview(live),
                const SizedBox(height: 16),
                const InfoBanner(
                    icon: Icons.info_outline,
                    color: accent,
                    text: 'Les factures déjà émises gardent l\'en-tête qu\'elles avaient : ces changements ne servent que pour les prochaines.'),
                const SizedBox(height: 12),
                TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nom de l\'association')),
                const SizedBox(height: 12),
                TextField(
                    controller: _footer,
                    onChanged: (_) => setState(() {}),
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Pied de page (siège, téléphones, région)')),
                const SizedBox(height: 12),
                TextField(controller: _place, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Lieu d\'émission (ex. Ouagadougou)')),
                const SizedBox(height: 12),
                TextField(controller: _signer, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Signataire (ex. Le Trésorier)')),
                const SizedBox(height: 16),
                GradientButton(icon: Icons.save_outlined, label: 'Enregistrer', onPressed: _save),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────── Clients ─────────────────────────

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  Future<List<ClientInfo>>? _future;

  void _reload() {
    final next = StoreScope.of(context).repo.clients();
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.clients();
  }

  Future<void> _edit([ClientInfo? c]) async {
    final store = StoreScope.of(context);
    final f = await showClientForm(context, existing: c);
    if (f == null || !mounted) return;
    final ok = c == null
        ? await run(context, () => store.repo.addClient(f), success: 'Client enregistré.')
        : await run(context, () => store.repo.updateClient(c.id, {...f}..remove('code')), success: 'Client modifié.');
    if (ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(flexibleSpace: const GlassBar(child: SizedBox.expand()), title: const Text('Clients')),
      body: AsyncBody<List<ClientInfo>>(
        future: _future!,
        onRetry: _reload,
        builder: (context, list) => ListView(padding: const EdgeInsets.all(16), children: [
          GradientButton(icon: Icons.add_business_outlined, label: 'Nouveau client', onPressed: _edit),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(children: [
              if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucun client. Ajoutez le premier.')),
              for (final c in list)
                ListTile(
                  title: Text(c.name),
                  subtitle: Text('${c.code}${(c.ifu ?? '').isEmpty ? '' : ' · IFU ${c.ifu}'}${c.active ? '' : ' · désactivé'}'),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => _edit(c),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Formulaire client : renvoie les champs à envoyer, ou null si annulé.
Future<Map<String, String?>?> showClientForm(BuildContext context, {ClientInfo? existing}) {
  final code = TextEditingController(text: existing?.code);
  final name = TextEditingController(text: existing?.name);
  final status = TextEditingController(text: existing?.status);
  final rccm = TextEditingController(text: existing?.rccm);
  final ifu = TextEditingController(text: existing?.ifu);
  final capital = TextEditingController(text: existing?.capital);
  final address = TextEditingController(text: existing?.address);
  String? error;
  return showDialog<Map<String, String?>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Widget field(TextEditingController c, String label, {bool enabled = true, int lines = 1, String? hint}) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                  controller: c,
                  enabled: enabled,
                  minLines: lines,
                  maxLines: lines,
                  decoration: InputDecoration(labelText: label, hintText: hint)),
            );
        return AlertDialog(
          title: Text(existing == null ? 'Nouveau client' : 'Modifier le client'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                field(code, 'Code court (sert au numéro de facture)', enabled: existing == null, hint: 'SOPAMIB'),
                field(name, 'Nom du client *'),
                field(status, 'Statut', hint: 'Société d\'État avec conseil d\'administration'),
                field(rccm, 'RCCM'),
                field(ifu, 'IFU'),
                field(capital, 'Capital social'),
                field(address, 'Siège social (adresse)', lines: 2),
                if (error != null) Text(error!, style: const TextStyle(color: errColor)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
              onPressed: () {
                final c = code.text.trim().toUpperCase();
                if (name.text.trim().isEmpty) return setS(() => error = 'Le nom est obligatoire.');
                if (existing == null && !RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(c)) {
                  return setS(() => error = 'Code : 2 à 12 lettres ou chiffres, sans espace.');
                }
                Navigator.pop(ctx, {
                  'code': c,
                  'name': name.text.trim(),
                  'status': status.text.trim(),
                  'rccm': rccm.text.trim(),
                  'ifu': ifu.text.trim(),
                  'capital': capital.text.trim(),
                  'address': address.text.trim(),
                });
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    ),
  );
}

// ───────────────────────── Nouvelle facture ─────────────────────────

class NewInvoiceScreen extends StatefulWidget {
  const NewInvoiceScreen({super.key});

  @override
  State<NewInvoiceScreen> createState() => _NewInvoiceScreenState();
}

class _NewInvoiceScreenState extends State<NewInvoiceScreen> {
  Future<List<ClientInfo>>? _clients;
  String? _clientId;
  DateTime _issued = dateOnly(DateTime.now());
  late DateTime _to = dateOnly(DateTime.now());
  late DateTime _from = _to.subtract(const Duration(days: 6));
  final _price = TextEditingController();
  final _subject = TextEditingController();
  bool _subjectTouched = false;
  List<InvoiceLine> _lines = [];
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clients ??= StoreScope.of(context).repo.clients();
  }

  @override
  void dispose() {
    _price.dispose();
    _subject.dispose();
    super.dispose();
  }

  String get _autoSubject => 'Production hebdomadaire de briques BTC (${periodWords(_from, _to)})';

  int get _unit => int.tryParse(_price.text) ?? 0;
  int get _qty => _lines.fold(0, (s, l) => s + l.qty);

  Future<void> _loadProduction() async {
    final store = StoreScope.of(context);
    setState(() => _busy = true);
    InvoiceDraft? d;
    final ok = await run(context, () async => d = await store.repo.invoiceDraft(_from, _to));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok && d != null) {
        _lines = d!.lines;
        if (_price.text.isEmpty && d!.suggestedUnitPrice != null) _price.text = '${d!.suggestedUnitPrice}';
        if (!_subjectTouched) _subject.text = _autoSubject;
      }
    });
    if (ok && d != null && d!.lines.isEmpty) toast(context, 'Aucune production saisie sur cette période : ajoutez les lignes à la main.');
  }

  Future<void> _pick(bool isFrom) async {
    final d = await showDatePicker(context: context, initialDate: isFrom ? _from : _to, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null) return;
    setState(() {
      if (isFrom) {
        _from = dateOnly(d);
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = dateOnly(d);
        if (_to.isBefore(_from)) _from = _to;
      }
      if (!_subjectTouched) _subject.text = _autoSubject;
    });
  }

  Future<void> _editLine([InvoiceLine? l]) async {
    final label = TextEditingController(text: l?.label ?? 'Brique BTC');
    final qty = TextEditingController(text: l == null ? '' : '${l.qty}');
    DateTime? date = l?.date == null ? null : parseDate(l!.date!);
    final res = await showDialog<InvoiceLine>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(l == null ? 'Ajouter une ligne' : 'Modifier la ligne'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: date ?? _to, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) setS(() => date = dateOnly(d));
              },
              child: InputDecorator(
                decoration: InputDecoration(
                    labelText: 'Date (facultative)',
                    suffixIcon: date == null ? null : IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setS(() => date = null))),
                child: Text(date == null ? '—' : fmtDate(dateKey(date!))),
              ),
            ),
            const SizedBox(height: 10),
            TextField(controller: label, decoration: const InputDecoration(labelText: 'Désignation')),
            const SizedBox(height: 10),
            TextField(
              controller: qty,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Quantité (briques)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
              onPressed: () {
                if (label.text.trim().isEmpty || qty.text.isEmpty) return;
                Navigator.pop(ctx, InvoiceLine(date: date == null ? null : dateKey(date!), label: label.text.trim(), qty: int.parse(qty.text)));
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (res == null) return;
    setState(() {
      if (l == null) {
        _lines = [..._lines, res];
      } else {
        _lines[_lines.indexOf(l)] = res;
      }
      _lines.sort((a, b) => (a.date ?? '9999').compareTo(b.date ?? '9999'));
    });
  }

  Future<void> _create() async {
    final store = StoreScope.of(context);
    if (_clientId == null) return toast(context, 'Choisissez le client.', error: true);
    if (_unit <= 0) return toast(context, 'Indiquez le prix unitaire.', error: true);
    if (_lines.isEmpty) return toast(context, 'Ajoutez au moins une ligne.', error: true);
    if (!await confirm(context, 'Émettre la facture ?',
        '${fmtInt(_qty)} briques × ${fmtInt(_unit)} FCFA = ${fmtFcfa(_qty * _unit)}. Une facture émise ne se modifie plus (elle peut seulement être annulée).',
        ok: 'Émettre')) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    ({String id, String number, int totalAmount})? out;
    final ok = await run(context, () async {
      out = await store.repo.createInvoice(
        clientId: _clientId!,
        issuedOn: _issued,
        subject: _subject.text.trim().isEmpty ? _autoSubject : _subject.text.trim(),
        from: _from,
        to: _to,
        unitPrice: _unit,
        lines: _lines,
      );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && out != null) {
      toast(context, 'Facture ${out!.number} émise.');
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => StoreScope(store: store, child: InvoiceDetailScreen(id: out!.id))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(flexibleSpace: const GlassBar(child: SizedBox.expand()), title: const Text('Nouvelle facture')),
      body: AsyncBody<List<ClientInfo>>(
        future: _clients!,
        onRetry: () => setState(() => _clients = StoreScope.of(context).repo.clients()),
        builder: (context, clients) {
          final active = clients.where((c) => c.active).toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (active.isEmpty)
                  const InfoBanner(icon: Icons.business_outlined, color: warnColor, text: 'Aucun client : ajoutez-en un depuis « Clients » avant de créer une facture.')
                else
                  DropdownButtonFormField<String>(
                    initialValue: _clientId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Client (DOIT)'),
                    items: [for (final c in active) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _clientId = v),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pick(true),
                      child: InputDecorator(decoration: const InputDecoration(labelText: 'Période du'), child: Text(fmtDate(dateKey(_from)))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pick(false),
                      child: InputDecorator(decoration: const InputDecoration(labelText: 'au'), child: Text(fmtDate(dateKey(_to)))),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _loadProduction,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Remplir avec la production saisie'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Prix unitaire facturé (FCFA)', helperText: 'Propre à cette facture'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: _issued, firstDate: DateTime(2020), lastDate: DateTime(2100));
                        if (d != null) setState(() => _issued = dateOnly(d));
                      },
                      child: InputDecorator(decoration: const InputDecoration(labelText: 'Date d\'émission'), child: Text(fmtDate(dateKey(_issued)))),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _subject,
                  onChanged: (_) => _subjectTouched = true,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: 'Objet', hintText: _autoSubject),
                ),
                SectionTitle('Lignes (${_lines.length})',
                    trailing: Wrap(children: [
                      TextButton.icon(
                          onPressed: () => setState(() => _lines = [..._lines, InvoiceLine(label: 'Brique BTC (Echantillons)', qty: 0)]),
                          icon: const Icon(Icons.science_outlined, size: 18),
                          label: const Text('Échantillons')),
                      TextButton.icon(onPressed: _editLine, icon: const Icon(Icons.add, size: 18), label: const Text('Ligne')),
                    ])),
                GlassCard(
                  child: Column(children: [
                    if (_lines.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune ligne. Remplissez avec la production ou ajoutez-en.')),
                    for (final l in _lines)
                      ListTile(
                        dense: true,
                        title: Text(l.date == null ? l.label : '${fmtDate(l.date!)} · ${l.label}'),
                        subtitle: Text(_unit > 0 ? '${fmtInt(l.qty)} × ${fmtInt(_unit)} = ${fmtFcfa(l.qty * _unit)}' : fmtInt(l.qty)),
                        trailing: IconButton(
                            tooltip: 'Supprimer',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => setState(() => _lines.remove(l))),
                        onTap: () => _editLine(l),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [
                      KeyValue('Quantité totale', fmtInt(_qty)),
                      KeyValue('Montant total', _unit > 0 ? fmtFcfa(_qty * _unit) : '—', bold: true),
                      const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Le montant en lettres et le numéro sont établis à l\'émission.',
                              style: TextStyle(fontSize: 12, color: Colors.white60))),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                GradientButton(icon: Icons.receipt_long, label: _busy ? 'Patientez…' : 'Émettre la facture', onPressed: _busy ? null : _create),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────── Détail d'une facture ─────────────────────────

class InvoiceDetailScreen extends StatefulWidget {
  final String id;
  const InvoiceDetailScreen({super.key, required this.id});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Future<Invoice>? _future;

  void _reload() {
    final next = StoreScope.of(context).repo.invoice(widget.id);
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= StoreScope.of(context).repo.invoice(widget.id);
  }

  Future<void> _cancel(Invoice inv) async {
    final store = StoreScope.of(context);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la facture ?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${inv.number} restera visible, marquée « annulée ». Elle ne peut pas être modifiée.'),
          const SizedBox(height: 12),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif (obligatoire)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retour')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler la facture')),
        ],
      ),
    );
    if (ok == true && mounted) {
      if (await run(context, () => store.repo.cancelInvoice(inv.id, reason.text.trim()), success: 'Facture annulée.')) _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(flexibleSpace: const GlassBar(child: SizedBox.expand()), title: const Text('Facture')),
      body: AsyncBody<Invoice>(
        future: _future!,
        onRetry: _reload,
        builder: (context, inv) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              LetterheadPreview(inv.letterhead),
              const SizedBox(height: 12),
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('FACTURE N° ${inv.number}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accentSoft))),
                      if (inv.status == 'cancelled') const Pill('Annulée', errColor),
                    ]),
                    Text('${inv.place}, le ${fmtDate(inv.issuedOn)}', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70)),
                    const SizedBox(height: 12),
                    Text('DOIT : ${inv.client.name}', style: const TextStyle(fontWeight: FontWeight.w800, color: okColor)),
                    for (final e in [
                      ('Statut', inv.client.status),
                      ('RCCM', inv.client.rccm),
                      ('IFU', inv.client.ifu),
                      ('Capital social', inv.client.capital),
                      ('Siège social', inv.client.address),
                    ])
                      if ((e.$2 ?? '').isNotEmpty) Text('${e.$1} : ${e.$2}', style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    Text('Objet : ${inv.subject}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    for (final l in inv.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          SizedBox(width: 92, child: Text(l.date == null ? '' : fmtDate(l.date!), style: const TextStyle(fontSize: 13))),
                          Expanded(child: Text(l.label, style: const TextStyle(fontSize: 13))),
                          SizedBox(width: 56, child: Text(fmtInt(l.qty), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
                          SizedBox(width: 92, child: Text(fmtInt(l.qty * inv.unitPrice), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
                        ]),
                      ),
                    const Divider(height: 18),
                    KeyValue('MONTANT TOTAL (${fmtInt(inv.totalQty)} × ${fmtInt(inv.unitPrice)})', fmtFcfa(inv.totalAmount), bold: true),
                    const SizedBox(height: 6),
                    Text('Arrêtée la présente facture à la somme de : ${inv.amountWords}.', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (inv.cancelReason != null)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text('Annulée : ${inv.cancelReason}', style: const TextStyle(color: errColor))),
                    const SizedBox(height: 14),
                    Align(alignment: Alignment.centerRight, child: Text('Pour l\'association,\n${inv.signer}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              GradientButton(
                icon: Icons.picture_as_pdf_outlined,
                label: 'PDF / Partager',
                onPressed: () async => sharePdf(await invoicePdf(inv), 'facture-${inv.number.replaceAll('/', '-')}.pdf'),
              ),
              if (inv.status == 'issued')
                TextButton.icon(
                  onPressed: () => _cancel(inv),
                  icon: const Icon(Icons.cancel_outlined, color: errColor),
                  label: const Text('Annuler cette facture', style: TextStyle(color: errColor)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

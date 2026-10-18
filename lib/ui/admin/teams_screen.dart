import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/app_store.dart';
import '../../domain/models.dart';
import '../face_capture.dart';
import '../glass.dart';
import 'worker_sheet_screen.dart';
import '../widgets.dart';
import 'worker_form.dart';

class _TeamsData {
  final List<TeamInfo> teams;
  final List<WorkerInfo> workers;
  final List<SupervisorInfo> supervisors;
  const _TeamsData(this.teams, this.workers, this.supervisors);
}

/// Équipes, membres, superviseurs, remplacement d'un superviseur et enregistrement des visages.
class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  Future<_TeamsData>? _future;

  Future<_TeamsData> _fetch() async {
    final r = StoreScope.of(context).repo;
    final all = await Future.wait([r.teams(), r.workers(), r.supervisors()]);
    return _TeamsData(all[0] as List<TeamInfo>, all[1] as List<WorkerInfo>, all[2] as List<SupervisorInfo>);
  }

  void _reload() {
    // Bloc (et non « => ») : setState refuse un callback qui renvoie un Future.
    final next = _fetch();
    setState(() {
      _future = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      body: AsyncBody<_TeamsData>(
        future: _future!,
        onRetry: _reload,
        builder: (context, d) => ListView(padding: const EdgeInsets.all(16), children: [
          if (d.teams.isEmpty)
            const InfoBanner(
                icon: Icons.groups,
                color: accent,
                text: 'Commencez par créer une équipe, puis ajoutez ses membres (10 ouvriers) '
                    'et désignez le superviseur parmi eux.'),
          for (final t in d.teams) ...[_teamCard(context, store, d, t), const SizedBox(height: 10)],
          const SectionTitle('Superviseurs enregistrés'),
          GlassCard(
            child: d.supervisors.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('Aucun superviseur.'))
                : Column(children: [
                    for (final u in d.supervisors)
                      ListTile(
                        leading: const Icon(Icons.badge),
                        title: Text(u.name),
                        subtitle: Text([
                          ...u.chiefOf.map((t) => 'Titulaire de $t'),
                          ...u.interimOf.map((t) => 'Remplaçant sur $t'),
                        ].join(' · ')),
                        trailing: IconButton(
                          tooltip: 'Réinitialiser le code PIN',
                          icon: const Icon(Icons.lock_reset),
                          onPressed: () => _resetPin(context, store, u),
                        ),
                      ),
                  ]),
          ),
          const SizedBox(height: 90),
        ]),
      ),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.extended(
          heroTag: 'sup',
          onPressed: () => _createSupervisor(context, store),
          icon: const Icon(Icons.person_add),
          label: const Text('Superviseur'),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'team',
          onPressed: () async {
            final n = await askText(context, title: 'Nouvelle équipe', label: 'Nom');
            if (n != null && context.mounted && await run(context, () => store.repo.createTeam(n), success: 'Équipe créée.')) {
              _reload();
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('Équipe'),
        ),
      ]),
    );
  }

  Widget _teamCard(BuildContext context, AppStore store, _TeamsData d, TeamInfo t) {
    final members = d.workers.where((w) => w.teamId == t.id && w.active).toList();
    return GlassCard(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const CircleAvatar(child: Icon(Icons.groups)),
        title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('Superviseur : ${t.chief?.name ?? 'non affecté'}\n${t.members} membre(s)'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.interim != null)
            InfoBanner(
                icon: Icons.swap_horiz,
                color: accent,
                text: 'Remplacement en cours : ${t.interim!.name} (connexion avec son propre PIN).'),
          Wrap(spacing: 8, children: [
            TextButton.icon(
              icon: const Icon(Icons.manage_accounts),
              label: const Text('Titulaire'),
              onPressed: () => _pick(context, store, d, t, interim: false),
            ),
            TextButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: Text(t.interim == null ? 'Désigner un remplaçant' : 'Changer le remplaçant'),
              onPressed: () => _pick(context, store, d, t, interim: true),
            ),
            if (t.interim != null)
              TextButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('Fin du remplacement'),
                onPressed: () async {
                  if (await run(context, () => store.repo.setInterim(t.id, null), success: 'Remplacement terminé.')) _reload();
                },
              ),
          ]),
          const Divider(),
          for (final w in members)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(w.fullName),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => StoreScope(
                      store: store, child: WorkerSheetScreen(workerId: w.id, name: w.fullName)))),
              isThreeLine: _contactText(w) != null,
              subtitle: Text(_memberSubtitle(w)),
              trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                IconButton(
                  tooltip: 'Coordonnées',
                  icon: const Icon(Icons.contact_phone_outlined, size: 20),
                  onPressed: () => _editContact(context, store, w),
                ),
                TextButton.icon(
                  icon: Icon(w.faceEnrolled ? Icons.refresh : Icons.face_retouching_natural, size: 18),
                  label: Text(w.faceEnrolled ? 'Refaire' : 'Enregistrer'),
                  onPressed: () => _enroll(context, store, w),
                ),
                if (w.faceEnrolled)
                  IconButton(
                    tooltip: 'Supprimer le visage (retrait du consentement)',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () async {
                      if (await confirm(context, 'Supprimer le visage ?',
                              'La signature faciale de ${w.fullName} sera effacée.', ok: 'Supprimer') &&
                          context.mounted &&
                          await run(context, () => store.repo.deleteFace(w.id), success: 'Visage supprimé.')) {
                        _reload();
                      }
                    },
                  ),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Ajouter un membre'),
              onPressed: () async {
                final f = await showWorkerForm(context);
                if (f != null && context.mounted &&
                    await run(
                        context,
                        () => store.repo.addWorker(
                            fullName: f.fullName,
                            teamId: t.id,
                            phone: f.phone,
                            village: f.village,
                            mobileOperator: f.mobileOperator,
                            mobileNumber: f.mobileNumber),
                        success: 'Ouvrier enregistré.')) {
                  _reload();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  static String? _contactText(WorkerInfo w) {
    final parts = [
      if (w.phone != null) w.phone!,
      if (w.village != null) w.village!,
      if (w.mobileOperator != null && w.mobileNumber != null)
        '${mobileOperators[w.mobileOperator] ?? w.mobileOperator} ${w.mobileNumber}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _memberSubtitle(WorkerInfo w) {
    final face = w.faceEnrolled ? 'Visage enregistré' : 'Visage non enregistré';
    final contact = _contactText(w);
    return contact == null ? face : '$face\n$contact';
  }

  Future<void> _editContact(BuildContext context, AppStore store, WorkerInfo w) async {
    final f = await showWorkerForm(context, existing: w);
    if (f == null || !context.mounted) return;
    final ok = await run(
        context,
        () => store.repo.updateContact(w.id,
            fullName: f.fullName,
            phone: f.phone,
            village: f.village,
            mobileOperator: f.mobileOperator,
            mobileNumber: f.mobileNumber),
        success: 'Coordonnées enregistrées.');
    if (ok) _reload();
  }

  /// Enregistrement du visage : 3 photos, le serveur calcule et chiffre la signature puis jette les photos.
  Future<void> _enroll(BuildContext context, AppStore store, WorkerInfo w) async {
    if (!await confirm(
        context,
        'Consentement',
        '${w.fullName} accepte-t-il l\'enregistrement de son visage pour confirmer sa présence ? '
            'Seule une signature numérique chiffrée est conservée, jamais la photo.',
        ok: 'Il accepte')) {
      return;
    }
    if (!context.mounted) return;
    final shots = await captureFaces(context,
        title: 'Visage de ${w.fullName}',
        count: 3,
        prompts: const ['Regardez droit devant', 'Tournez très légèrement la tête à gauche', 'Tournez très légèrement la tête à droite']);
    if (shots == null || !context.mounted) return;
    toast(context, 'Analyse du visage en cours…');
    if (await run(context, () => store.repo.enrollFace(w.id, shots), success: 'Visage enregistré.')) _reload();
  }

  Future<void> _pick(BuildContext context, AppStore store, _TeamsData d, TeamInfo t, {required bool interim}) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(interim ? 'Remplaçant de ${t.name}' : 'Titulaire de ${t.name}'),
        children: [
          if (d.supervisors.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Créez d\'abord un superviseur.')),
          for (final c in d.supervisors.where((s) => s.active))
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, c.id), child: Text(c.name)),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    final ok = await run(context,
        () => interim ? store.repo.setInterim(t.id, picked) : store.repo.setChief(t.id, picked),
        success: 'Affectation enregistrée.');
    if (ok) _reload();
  }

  Future<void> _resetPin(BuildContext context, AppStore store, SupervisorInfo u) async {
    final pin = await askText(context, title: 'Nouveau code de ${u.name}', label: 'Code PIN (4 à 6 chiffres)');
    if (pin == null || !context.mounted) return;
    if (await run(context, () => store.repo.resetSupervisorPin(u.id, pin.trim()), success: 'Code réinitialisé.') &&
        context.mounted) {
      await _showCode(context, u.name, pin.trim());
    }
  }

  Future<void> _showCode(BuildContext context, String name, String pin) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('À communiquer'),
          content: Text('Nom : $name\nCode : $pin\n\nAvec ces deux informations, le superviseur accède à la liste de son équipe.'),
          actions: [
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK')),
          ],
        ),
      );

  Future<void> _createSupervisor(BuildContext context, AppStore store) async {
    List<WorkerInfo> workers;
    try {
      workers = (await store.repo.workers()).where((w) => w.active && !w.isSupervisor).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));
    } catch (_) {
      if (context.mounted) toast(context, 'Impossible de charger les ouvriers.', error: true);
      return;
    }
    if (!context.mounted) return;
    final pin = TextEditingController();
    String? workerId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau superviseur'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Le superviseur est l\'un des ouvriers. Il reste dans son équipe.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ouvrier'),
              items: [
                for (final w in workers)
                  DropdownMenuItem(
                      value: w.id,
                      child: Text('${w.fullName} · ${w.teamName ?? '—'}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => workerId = v,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Code PIN (4 à 6 chiffres)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (workerId == null) {
      toast(context, 'Choisissez un ouvrier.', error: true);
      return;
    }
    final name = workers.firstWhere((w) => w.id == workerId).fullName;
    if (await run(context, () => store.repo.createSupervisor(workerId!, pin.text)) && context.mounted) {
      _reload();
      await _showCode(context, name, pin.text);
    }
  }
}

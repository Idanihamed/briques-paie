# Briques & Paie

Application de gestion de production de briques et de paie : **Flutter** (Android, web) + **API Node.js / Express** + **PostgreSQL (Supabase)**.

- **Superviseur** : se connecte avec son nom et son code PIN, voit les autres membres de son équipe, les marque présents/absents
  (identification par le **visage** possible) et saisit le **nombre de briques confectionnées**. Il ne voit aucun prix ni montant.
- **Admin** : tableau de bord (web et mobile) avec présents/absents, briques, coût de confection (175 FCFA), valeur de vente (250 FCFA)
  et marge ; gestion des équipes, superviseurs, remplaçants et visages ; paie mensuelle (validation, verrouillage), paiements, prix, audit.

Aucune donnée n'est codée en dur : tout vient de l'API. Voir [backend/README.md](backend/README.md) pour l'installation complète.

## Lancer en local

```bash
cd backend && npm install
npm run create-admin -- --local "Votre Nom" 1234     # premier admin (base locale de développement)
npm run local                                        # API sur http://localhost:3000

# dans un autre terminal, à la racine :
flutter pub get
flutter run -d chrome --dart-define=API_URL=http://localhost:3000
```

Tests : `flutter test` (application) et `cd backend && npm test` (API, base SQL, reconnaissance faciale).

## Calendrier de travail, fiche ouvrier, mode hors ligne

- **Calendrier** (admin : onglet « Calendrier » ; superviseur : onglet « Calendrier ») : jours travaillés, repos
  hebdomadaire (dimanche par défaut, configurable), fériés, intempéries, pannes, par équipe ou pour toutes.
  Un jour non travaillé n'est plus compté « sans saisie » dans la paie et la saisie y est refusée.
- **Fiche ouvrier** (admin : Équipes → clic sur un membre) : présences jour par jour, taux de présence,
  motifs d'absence, gains exacts, paiements, solde.
- **Motifs d'absence** : Maladie, Permission, Non justifiée, Autre (choisis par le superviseur sur un absent).
- **Hors ligne (superviseur)** : après une première connexion, l'appareil garde ses équipes, la journée du jour et le
  calendrier. Sans réseau on peut se reconnecter avec son code, saisir présences et briques ; les saisies attendent
  dans une file et partent dès que le serveur répond (sans doublon : `requestId`). Si la journée a changé entre-temps
  (autre appareil, correction de l'admin), le superviseur choisit « garder ma saisie » ou « garder celle du serveur ».
  L'identification faciale demande le réseau. L'admin travaille en ligne uniquement (aucun montant n'est stocké sur l'appareil).
- Mettre à jour la base : `npm run db:schema` (idempotent) dans `backend/`.

## Statistiques, avances, paie sur période, PDF, alertes (admin)

- **Statistiques** : tendance sur 6 mois, production par jour, classement des équipes, assiduité des ouvriers.
- **Avances** : ajoutées depuis la fiche d'un ouvrier (avant validation du mois), déduites du solde, annulables tant que le mois n'est pas verrouillé.
- **Paie sur période** : semaine, quinzaine… à titre d'information (le règlement officiel reste mensuel).
- **PDF** : fiche de paie (fiche ouvrier), état de paie du mois, paie sur période. Générés sur l'appareil ; les accents sont retirés (polices PDF de base).
- **Alertes** : jours sans saisie, journées incomplètes, baisse de production, absences répétées, paie à valider, avances excessives, prix manquants, visages manquants.

## Import et sauvegarde (admin)

- **Import d'ouvriers** (page « Import & sauvegarde ») : collez un tableau Excel/CSV (Nom, Téléphone, Village, Opérateur, Numéro mobile money, Équipe). « Vérifier » affiche le résultat ligne par ligne sans rien écrire ; « Importer » n'enregistre que les lignes valides. Les doublons (déjà enregistrés ou répétés dans la liste) sont ignorés, donc relancer le même import ne crée rien en double.
- **Sauvegarde** : bouton « Exporter la sauvegarde » (fichier JSON partagé depuis l'appareil) ou `npm run backup` dans `backend/` (écrit `backups/sauvegarde-AAAA-MM-JJ.json`). Sans PIN ni signatures de visage. Il n'y a pas de restauration automatique : le fichier sert d'archive et de contrôle ; les sauvegardes complètes de la base sont celles de Supabase.

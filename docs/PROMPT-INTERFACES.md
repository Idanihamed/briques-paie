# Prompt : interfaces de « Briques & Paie »

> À coller dans l'outil de design / génération d'interface de votre choix (Figma Make, v0, Lovable, Stitch, etc.).
> Ensuite, redonnez-moi le résultat (code, export ou captures) : je l'adapte à l'application Flutter existante
> en gardant les routes de l'API, les règles de confidentialité et le mode hors ligne.

---

## 1. Contexte

Application de **production de briques et de paie** pour l'association *Bayiir Mêtba (ABM)* — « Construction de la patrie », Burkina Faso.
Des équipes de 10 ouvriers fabriquent des briques. Chaque jour, le **superviseur** (un des 10 ouvriers) saisit les présents/absents et
**un seul nombre de briques**. L'**admin** (3 responsables partagent le même espace) gère équipes, ouvriers, calendrier, paie, paiements, avances, statistiques.

- Langue : **français uniquement**. Devise : **FCFA**, espaces comme séparateur de milliers (`17 500 FCFA`). Dates `JJ/MM/AAAA`.
- Plateformes : **Android (téléphone)** et **web (ordinateur)**. Même application, mise en page adaptative.
- Deux espaces seulement : **Superviseur** et **Admin**. Pas d'espace trésorier.

## 2. Règles à respecter absolument

1. **Le superviseur ne voit jamais** : prix (175 / 250), montants, valeur des briques, marge, paie, coordonnées des ouvriers. Aucun champ de ce type dans son interface.
2. **175 FCFA = prix de confection** (base de la paie : briques × 175 ÷ nombre de présents). **250 FCFA = prix de vente** (admin seulement : valeur de vente et marge). Ne jamais les mélanger.
3. **Aucune donnée écrite en dur** : tous les chiffres, noms, listes viennent de l'API. Prévoir des états **chargement / vide / erreur avec « Réessayer »** pour chaque écran.
4. Les montants non entiers s'affichent exactement (jamais d'arrondi caché) ; préfixe `≈` si la valeur décimale est approchée.
5. Un **mois verrouillé** (paie validée) rend les saisies en **lecture seule** avec un bandeau explicatif.
6. Le superviseur se connecte avec **son nom tapé + code PIN**. Verrouillage de la session après 5 minutes d'inactivité.

## 3. Direction visuelle

- **Glassmorphism sobre et professionnel**, thème sombre, **un seul bleu d'accent**. Pas de multicolore.
- Fond bleu nuit `#080D1B` avec halos flous bleus très discrets (« aurore ») ; panneaux de verre : fond blanc 6–10 %, flou, bordure blanche 12–18 %, rayon 16–24 px.
- Accent `#4F8CFF`, accent profond `#2F63D8`, accent doux `#A9C6FF`. Dégradé de marque : accent → accent profond (boutons principaux, éléments sélectionnés).
- **Couleurs de statut uniquement** : vert `#3CC795` (ok), ambre `#F1B94A` (attention), rouge `#F07282` (erreur/absent).
- Texte blanc ; secondaire blanc 60–70 %. Polices lisibles, titres gras (700–800). Cibles tactiles ≥ 44 px (utilisateurs sur chantier, parfois au soleil : contraste élevé).
- **Logo** : badge circulaire ABM (baobab, mains qui se serrent vert/or, carte du Burkina). À placer sur la connexion (≈120 px), le menu latéral (≈46 px) et les documents.
- Composants communs : carte de verre, barre de verre (navigation), bouton dégradé, pastille de statut (« Pill »), bandeau d'info (icône + texte, teinté selon gravité), sélecteur de mois (← mois année →), liste clé/valeur, titre de section avec action à droite, bascule **P / A** (Présent vert / Absent rouge, un second appui = « non saisi »).

## 4. Navigation

- **Superviseur** : barre du bas à 2 onglets — *Saisie* · *Calendrier*. Bandeau de synchronisation sous la barre du haut. Bouton de déconnexion en haut à droite.
- **Admin, grand écran (≥ 900 px)** : barre latérale en verre (logo, 12 entrées, carte utilisateur + déconnexion), contenu centré (max 1280 px), titre de page 28 px.
- **Admin, téléphone** : barre du bas à 3 entrées (*Tableau de bord*, *Calendrier*, *Équipes*) + **Plus** (liste des autres pages) ; déconnexion en haut.
- Pages admin : Tableau de bord · Calendrier · Équipes & superviseurs · Statistiques · Paie mensuelle · Alertes · Factures · Paie sur période · Paiements · Prix & tarifs · Import & sauvegarde · Journal d'audit.

## 5. Écrans

### 5.1 Connexion
Logo, nom « Briques & Paie ». Champ **Nom** (texte libre), **pavé numérique PIN** avec pastilles (remplies en dégradé au fur et à mesure), bouton « Se connecter ». Message d'erreur sous le pavé (nom/code incorrect, compte verrouillé après 5 essais, serveur injoignable). Message d'information après déconnexion forcée (« Session verrouillée après inactivité », « Session expirée »). Hors ligne : connexion possible avec le même code si déjà utilisé sur l'appareil. **Sous la carte** : petit bouton discret « Serveur : adresse:3000 » (mobile seulement) qui ouvre une fenêtre « Adresse du serveur » (champ + exemple `192.168.1.132:3000`, rappel « le téléphone doit être sur le même Wi-Fi », Annuler / Enregistrer, erreur « Adresse invalide »).

### 5.2 Superviseur — Saisie du jour
- En haut : sélecteur d'**équipe** (si plusieurs) et de **date** (calendrier, pas de date future) ; date longue en dessous.
- Bandeaux possibles : « Vous remplacez le superviseur titulaire » · « Jour non travaillé (Férié : Tabaski). La saisie est désactivée » · « Paie verrouillée : lecture seule » · « Journée déjà enregistrée par X ».
- **Liste des 9 autres membres** (le superviseur est présent d'office et n'est pas dans la liste) : nom, pastilles (*Remplaçant*, *Visage ✓*, *Non saisi*), bouton **identification faciale** (caméra), bascule **P / A**. Sur un absent : menu « **Motif : Maladie / Permission / Non justifiée / Autre / Aucun** ».
- Action « Non saisis : présents » ; « Ajouter un ouvrier remplaçant » (feuille avec liste filtrée et équipe d'origine).
- **Un seul champ « Nombre de briques confectionnées »** (grand chiffre, clavier numérique). **Rien d'autre côté argent.**
- Résumé : Présents x / n · Absents · Non saisis · Identifiés par visage. Bandeau « Journée incomplète » (ambre) ou « Journée complète » (vert).
- Bouton fixe en bas « **Enregistrer la journée** » (désactivé si rien n'a changé).
- Capture du visage : vue caméra plein écran avec cadre ovale, consigne, bouton de prise, retour d'erreur (« Visage non reconnu, réessayez ou cochez à la main »).

### 5.3 Calendrier (superviseur et admin)
- Sélecteur de mois ; (admin) choix d'**équipe ou « Toutes »** et bouton **Jours de repos** ; texte « Repos hebdomadaire : Dim ».
- **Grille mensuelle** lun→dim. Chaque case : numéro du jour + icône d'état — complet (✓ vert), incomplet (sablier ambre), manquant (! rouge), à saisir aujourd'hui (crayon bleu), non travaillé (icône : repos / férié / intempérie / panne, teinte neutre). Jour du jour entouré en bleu.
- Légende. **Détail d'un jour** (feuille du bas) : par équipe, état, briques, motif du jour non travaillé ; actions *Ouvrir la saisie*, (admin) *Rétablir le calendrier habituel*, *Déclarer ce jour non travaillé…*.
- **Déclarer des jours** (admin) : statut (Repos, Férié, Intempérie, Panne, Autre, Travaillé exceptionnel), du / au, équipes (toutes ou une), motif libre.
- **Jours de repos hebdomadaires** : puces Lun…Dim.

### 5.4 Synchronisation hors ligne (superviseur)
Bandeau « Hors ligne — vos saisies sont gardées sur l'appareil » ; carte « 2 saisies en attente d'envoi » + bouton *Envoyer* / « Synchronisation… » ; **carte de conflit** (équipe · date, message, boutons *Garder ma saisie* / *Garder celle du serveur*) ; carte de saisie refusée (motif, bouton *Abandonner*). Reconnaissance faciale indisponible hors ligne (message clair).

### 5.5 Admin — Tableau de bord
Sélecteur de date. Bandeau **alertes** (« 4 alertes dont 1 urgente »). Alerte si prix manquant. **6 tuiles** : ouvriers enregistrés (avec « dont N avec visage »), présents, absents, briques confectionnées, payé aux équipes (briques × 175), valeur de vente (briques × 250) — et marge. Carte **« Connectés maintenant (N) »** : nom, rôle, équipe, dernière activité, « (vous) ». Liste des équipes du jour : superviseur, présents/absents, briques, statut (complet / incomplet / sans saisie), part par présent. Actualisation auto toutes les 30 s.

### 5.6 Admin — Équipes & superviseurs
Cartes d'équipe : nom, superviseur titulaire, **remplaçant désigné** (changement avec PIN), membres. Pour chaque membre : nom, visage enregistré ou non, contact (téléphone · village · opérateur + numéro mobile money), boutons **Coordonnées**, **Enregistrer / Refaire le visage** (3 photos + case de consentement), supprimer le visage ; **clic sur le nom = fiche ouvrier**. « Ajouter un membre » (formulaire), « Créer une équipe », création de superviseur (un ouvrier + PIN).
- **Formulaire d'ouvrier** : Nom complet*, Téléphone, Village, Opérateur mobile money (Orange / Moov / Telecel / Autre), Numéro mobile money (opérateur et numéro vont ensemble), validation en direct.

### 5.7 Admin — Fiche ouvrier (page ou fenêtre)
Barre : nom, bouton **PDF** (fiche de paie). Sélecteur de mois, bandeau « Paie verrouillée ». Carte récap : jours présent/absent/non saisi, **taux de présence**, gagné, avances déduites, déjà payé, **solde à payer**. **Motifs d'absence** (Maladie 2, Permission 1…). **Avances** (liste + « Ajouter » : montant, espèces/mobile money, note ; suppression tant que le mois n'est pas verrouillé). **Jour par jour** : date, équipe, remplaçant, visage ✓, motif, part du jour (ou pastille Absent / Non saisi). **Paiements** (date, montant, mode).

### 5.8 Admin — Statistiques
Mois. Carte de totaux (briques, jours de production, moyenne/jour, meilleur jour, taux de présence, payé aux équipes, valeur de vente, marge). **Histogramme 6 mois** (briques, mois courant mis en avant). **Histogramme jour par jour**. **Classement des équipes** (rang, briques, jours, moyenne/jour, briques par présent, présence). **Assiduité des ouvriers** (rang, présent/absent, gain, % ; clic = fiche).

### 5.9 Admin — Paie mensuelle
Mois ; bouton « État de paie (PDF) » ; pastille *Paie provisoire* ou *Verrouillée · v2* + total. **Anomalies** (bloquantes en rouge : journée incomplète, aucun présent, tarif manquant ; non bloquantes en ambre : jour sans saisie, production nulle). Totaux par équipe. Tableau par ouvrier : jours, total exact, avances, payé, solde ; détail d'un ouvrier (ligne par jour). Actions : **Valider et verrouiller** (désactivé si anomalie bloquante), **Déverrouiller** (motif obligatoire), **Export CSV**. Historique des versions (validée par, déverrouillée par, motif).

### 5.10 Admin — Paiements
Mois (paiements actifs seulement si la paie est verrouillée, sinon bandeau). Liste : ouvrier, dû exact, avances, payé, **solde** (rouge si trop-perçu). Dialogue de paiement : solde exact, **montant proposé (arrondi)**, montant réellement payé, Espèces / Mobile money, mention « Enregistrement manuel : aucun transfert n'est envoyé ».

### 5.11 Admin — Alertes
Liste de cartes triées par gravité (icône rouge / ambre / bleue) : jours sans saisie, journées incomplètes, baisse de production, absences répétées, paie à valider, avances supérieures aux gains, prix manquants, ouvriers sans visage. État « Rien à signaler ». Actualiser.

### 5.12 Admin — Paie sur période
Du / Au + raccourcis (7, 15, 30 jours). Bandeau « à titre d'information ». Totaux (briques, payé aux équipes, vente, marge, journées incomplètes non comptées). Par équipe, par ouvrier. Bouton « Exporter en PDF ».

### 5.13 Admin — Prix & tarifs
Prix en vigueur (confection 175, vente 250) avec date d'effet ; **changement = nouvelle ligne** avec date d'effet et **motif obligatoire** ; historique en ajout seul (jamais modifié ni supprimé) ; refus si un mois verrouillé serait touché.

### 5.14 Admin — Import & sauvegarde
**Import** : zone de texte (coller depuis Excel), aide sur les colonnes (Nom, Téléphone, Village, Opérateur, Numéro mobile money, Équipe), boutons *Vérifier* puis *Importer N ouvriers* ; résultat ligne par ligne (✓ prêt / doublon / erreur + motif). **Sauvegarde** : texte d'avertissement (données sensibles) + bouton « Exporter la sauvegarde ».

### 5.15 Admin — Journal d'audit
Liste chronologique inverse, immuable : date/heure, personne, rôle, action, objet, ancienne → nouvelle valeur ; chargement par pages (« Charger plus »).

### 5.16 Admin — Factures
- **Liste** : bouton principal « Nouvelle facture », liens « En-tête de facture » et « Clients » ; liste des factures émises (numéro `ABM/SOPAMIB/2026-07-001`, client · date · quantité, montant en FCFA, pastille rouge « Annulée »).
- **En-tête de facture** : aperçu fidèle (logo, nom de l'association en gras, filet, pied de page) + champs modifiables : nom, pied de page, lieu d'émission, signataire (« Le Trésorier »). Avertissement : « Les factures déjà émises gardent l'en-tête qu'elles avaient ».
- **Clients** : liste (nom, code court, IFU, « désactivé ») ; fiche : code court (sert au numéro), nom, statut, RCCM, IFU, capital social, siège social.
- **Nouvelle facture** : client (liste), période du / au, bouton « Remplir avec la production saisie », prix unitaire facturé (pré-rempli avec le prix de vente, modifiable), date d'émission, objet (« Production hebdomadaire de briques BTC (08 au 12 juillet 2026) », modifiable), lignes (date · désignation · quantité, modifiables, boutons « Ligne » et « Échantillons »), total (quantité × prix), mention « le numéro et le montant en lettres sont établis à l'émission », bouton « Émettre la facture » avec confirmation (« ne se modifie plus »).
- **Détail d'une facture** : en-tête, numéro et date, bloc client (DOIT : …, Statut, RCCM, IFU, Capital social, Siège social), objet, tableau, **montant total et montant en lettres**, signature ; boutons « PDF / Partager » et « Annuler cette facture » (motif obligatoire, la facture reste visible marquée « annulée »).
- **PDF de facture** : exactement la disposition des factures actuelles de l'association : logo en haut à gauche, nom en grand avec filet, « FACTURE N° … » en bleu, date à droite en italique, bloc client en vert, tableau à en-tête vert foncé (Date · Désignation · Quantité · Prix Unitaire · Montant), ligne « MONTANT TOTAL » sur fond vert clair, « Arrêtée la présente facture à la somme de : … », « Pour l'Association Bayiir Mêtba, » + signataire à droite, filet et pied de page centré.

### 5.17 Documents PDF (mise en page)
Fiche de paie ouvrier, état de paie mensuel (paysage), paie sur période : logo + titre, tableau (en-tête bleu foncé), totaux alignés à droite, lignes de **signature** (ouvrier / responsable), pagination.

## 6. Ce que je veux en retour

1. Les écrans ci-dessus pour **téléphone (360–430 px)** et **ordinateur (1366 px)**, thème sombre glassmorphism, avec tous les états (chargement, vide, erreur, hors ligne, verrouillé).
2. Un **système de composants** réutilisables nommés (carte de verre, bouton dégradé, pastille, bandeau, sélecteur de mois, bascule P/A, grille de calendrier, histogramme) et les **jetons de couleur / espacement / rayon**.
3. Les textes **en français**, exactement comme indiqué.
4. Pas de données réelles : utiliser des exemples neutres (« Ouvrier 1 »…), clairement marqués comme maquette.

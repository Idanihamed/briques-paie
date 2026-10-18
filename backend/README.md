# Briques & Paie — Backend

API **Node.js / Express** + base **PostgreSQL hébergée sur Supabase**.
Fournit ce que le frontend Flutter simule aujourd'hui en mémoire : connexion par nom + PIN,
équipes, superviseurs, saisie des journées, calcul exact de la paie, verrouillage, paiements, audit.

## Démarrage

**Aucune donnée n'est codée en dur** : ni compte, ni équipe, ni prix. Tout est créé depuis l'application.

### Avec Supabase (production)

```bash
cd backend
npm install
cp .env.example .env        # puis remplir DATABASE_URL, JWT_SECRET, FACE_KEY, CORS_ORIGINS
```

1. **Supabase** : créer un projet, copier la chaîne de connexion (Settings → Database → *Session pooler*, port 5432) dans `DATABASE_URL`.
2. **Schéma** : coller [db/schema.sql](db/schema.sql) dans *SQL Editor* et l'exécuter (ou `npm run db:schema`). Le script est idempotent.
3. **Premier admin** : `npm run create-admin -- "Nom Prénom" 1234` (le code PIN est haché, jamais stocké en clair).
   Les autres admins, équipes, ouvriers, superviseurs et prix se créent ensuite depuis l'application.
4. `npm start`, puis `GET /health`.

### Sans Supabase (essai local)

Même API et même schéma SQL, avec une base PostgreSQL locale (PGlite, dossier `.localdb`) :

```bash
npm install
npm run create-admin -- --local "Nom Prénom" 1234    # serveur arrêté : une seule connexion à la fois
npm run local                                        # API sur http://localhost:3000
```

Les secrets (jeton, clé de chiffrement des visages) sont générés une fois dans `.localdb/secrets.json`.
Pour repartir de zéro : supprimer le dossier `.localdb`.

### Application

```bash
cd ..                                                 # racine du projet Flutter
flutter run -d chrome --dart-define=API_URL=http://localhost:3000
flutter build web --dart-define=API_URL=https://api.votre-domaine.com
flutter build apk --dart-define=API_URL=https://api.votre-domaine.com
```

Émulateur Android : `API_URL=http://10.0.2.2:3000`. En production, toujours `https`.

### Tests

`npm test` — **aucun accès Supabase requis** : le vrai `schema.sql` est exécuté dans PGlite, et le vrai moteur
de reconnaissance faciale (WebAssembly + modèles) est chargé une fois.

## Reconnaissance faciale

Le calcul se fait **sur le serveur** (`@vladmandic/face-api` en WebAssembly : aucune dépendance native, aucun modèle
à embarquer dans l'application, même comportement sur le web et sur Android).

1. **Enregistrement** (admin, avec consentement) : 3 photos du visage → le serveur calcule une signature de 128 valeurs,
   la moyenne, la **chiffre (AES-256-GCM)**, puis **jette les photos**. Un visage déjà enregistré pour un autre ouvrier
   est refusé (`duplicate_face`).
2. **Vérification** (superviseur) : photo de l'ouvrier choisi → signature → distance avec la signature enregistrée.
   `match` si la distance ≤ `FACE_THRESHOLD` (0,5). Un refus est tracé dans l'audit comme événement de sécurité.
3. **Suppression** : `DELETE /api/workers/:id/face` (retrait du consentement).

Mesures réelles sur ce moteur : même photo → distance 0 ; personnes différentes → 0,64 à 0,77 (donc refusées au seuil 0,5).
**Non mesuré** : la distance d'une même personne sur deux photos différentes (lumière, angle) — valeur habituelle sous 0,5,
mais à valider sur le terrain avec vos ouvriers avant de s'y fier.
Une vérification prend environ 2 à 3 s sur un PC ordinaire (une seule à la fois, file d'attente).

**Limites assumées** : pas de détection de « vivacité » (une photo d'une photo peut tromper ce type de système) ; la
vérification se fait donc sous le contrôle du superviseur présent. La reconnaissance baisse avec une mauvaise lumière,
un profil ou un visage couvert (ces cas sont refusés : `no_face`). À régler après essai sur le terrain : `FACE_THRESHOLD`.

## Du diagramme à la base

| Diagramme (.txt)                     | Table SQL                                   | Remarques |
|--------------------------------------|---------------------------------------------|-----------|
| `users` (admin / superviseur, PIN)   | `users`                                     | `pin_hash` bcrypt ; rôle `admin` ou `chief` ; un superviseur **est** un ouvrier (`worker_id`) |
| `equipes`                            | `teams`                                     | `chief_id` titulaire + `interim_id` remplaçant désigné par l'admin |
| `ouvriers`                           | `workers`                                   | `face_template` chiffré (AES-256-GCM), jamais la photo |
| `presences` (P / A / NS)             | `day_presences` (`present`/`absent`/`unset`) | « non saisi » ≠ absent ; unicité d'une présence par personne et par jour |
| `production` (briques)               | `day_entries.bricks`                        | **par équipe et par jour** (cahier des charges) ; `NULL` = non saisi, différent de 0 |
| `tarifs` (175 et 250)                | `tariffs` (`kind` = `cost` ou `sale`)        | ajout seul : date d'effet, motif, auteur, horodatage |
| `paie` (calculs + verrou)            | `payroll_versions`                          | versions successives, déverrouillage motivé, ancienne version conservée |
| `paiements`                          | `payments`                                  | dû exact, arrondi proposé et montant payé séparés ; ajout seul |
| `audit`                              | `audit_log`                                 | immuable (triggers) |

### Les deux prix : 175 et 250

- **175 FCFA = prix de confection** (`cost`) : c'est ce qui est payé à l'équipe, par brique confectionnée.
  Part de chaque présent = `briques × 175 ÷ présents`.
- **250 FCFA = prix de vente** (`sale`) : chiffre d'affaires. Il n'entre **jamais** dans la paie ; l'admin l'utilise
  pour la valeur de vente et la **marge** (`vente − confection`).
- Le superviseur ne saisit qu'**un nombre de briques**. Il ne reçoit aucun prix, aucun montant.

> Les diagrammes plaçaient la production par ouvrier avec deux colonnes (175 / 250) ; ce sont en fait deux prix
> d'une même brique, et le cahier des charges définit la production par équipe.

## Règles protégées **par la base**, pas seulement par l'API

- Mois verrouillé : triggers refusant toute écriture dans `day_entries`, `day_production`, `day_presences`.
- Aucun tarif rétroactif sous un mois verrouillé.
- `tariffs`, `payments`, `audit_log` : ajout seul. `payroll_versions` : jamais supprimée.
- Une personne ne peut pas être « présente » dans deux équipes le même jour (index unique partiel).
- Une seule version verrouillée par mois.
- RLS activée sans politique : la clé `anon` Supabase ne lit rien. Seul ce backend (connexion serveur) accède aux données.

## Montants exacts

Les parts (`briques × prix de confection ÷ présents`) sont des fractions : l'API calcule en **rationnels BigInt**, sans flottant,
et ne stocke que des entiers FCFA. Chaque montant est renvoyé ainsi :

```json
{ "exact": "17500/3", "value": "5833.33", "approx": true }
```

L'arrondi n'intervient qu'au paiement (0,5 vers le haut, **règle à confirmer** — point 19 du cahier) ;
l'écart reste visible dans le solde.

## API (préfixe `/api`, JSON, `Authorization: Bearer <jeton>`)

| Méthode & route | Qui | Rôle |
|---|---|---|
| `POST /auth/login` `{name, pin}` | tous | jeton + utilisateur ; 5 échecs → blocage 30 s |
| `GET /auth/me` · `PUT /auth/pin` | connecté | équipes accessibles · changer son PIN |
| `GET /teams` · `POST /teams` | connecté · admin | |
| `PUT /teams/:id/chief` · `PUT /teams/:id/interim` `{userId\|null}` | admin | titulaire / **remplaçant** |
| `GET /workers` · `POST /workers` · `PATCH /workers/:id` | connecté (équipe) · admin | |
| `PUT /workers/:id/face` `{images:[base64 JPEG ×1-5]}` · `DELETE /workers/:id/face` | admin | enregistre / supprime la signature faciale |
| `POST /faces/verify` `{workerId, image}` | connecté | `{match, distance}` |
| `GET /days/substitutes?teamId&date` | superviseur de l'équipe, admin | remplaçants possibles |
| `GET /supervisors` · `POST /supervisors` `{workerId, pin}` · `PUT /supervisors/:id/pin` · `PATCH /supervisors/:id` | admin | un ouvrier existant devient superviseur |
| `GET /days?teamId&date` · `PUT /days` | superviseur de l'équipe, admin | **le superviseur ne reçoit jamais prix ni montant** |
| `GET /overview?date` | admin | présents/absents, briques, coût de confection (175), vente (250), marge |
| `GET /tariffs` · `POST /tariffs` `{kind: cost\|sale, value, effectiveDate, reason}` | admin | prix de confection / prix de vente |
| `GET /payroll/:AAAA-MM` · `POST …/validate` · `POST …/unlock` `{reason}` · `GET …/csv` | admin | |
| `GET /payments?month` · `POST /payments` | admin | |
| `GET /audit?limit&before&securityOnly` | admin | |

Erreurs : `{ "error": "message lisible", "code": "…" }` (400 validation, 401, 403, 409 règle métier, 423 compte bloqué).

## Sécurité

Hachage bcrypt des PIN · jetons JWT HS256 rechargés en base à chaque requête (compte désactivé = accès coupé) ·
verrouillage après 5 échecs · message d'erreur identique nom inconnu / PIN faux · `helmet`, CORS en liste blanche,
limitation de débit (général + connexion) · validation `zod` · refus d'accès tracés (`security = true`) ·
signatures de visage chiffrées (clé `FACE_KEY` hors base).

## Reste à faire

- **Import Excel, sauvegarde/restauration, rapports PDF** : non couverts (cahier des charges §9, §11, §13).
- **Déploiement** : héberger l'API (Node ≥ 20, ~512 Mo de RAM pour le moteur facial) derrière `https`, et configurer `CORS_ORIGINS`.
- Décisions ouvertes du cahier (§19) : règle d'arrondi (0,5 vers le haut pour l'instant), trop-perçu, récupération du PIN d'un admin (aujourd'hui : un autre admin, ou SQL).
- **Données biométriques** : consentement écrit des ouvriers, durée de conservation, hébergement des données.
- Mode hors ligne : l'application est désormais **en ligne** (API + Supabase) ; le fonctionnement sans Internet du cahier des charges n'est plus assuré.

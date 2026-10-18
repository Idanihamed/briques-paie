# Mise en ligne

Un seul service héberge **l'API et l'application web** (même adresse, donc aucun CORS). La base reste sur Supabase.

```
Téléphones Android (APK) ──┐
Navigateur (admin, web) ───┼──► https://votre-api  (Node + Express)  ──► Supabase (PostgreSQL)
                           ┘        └─ sert aussi l'application web Flutter
```

## 1. Avant de commencer (sécurité)

- [ ] **Changer le mot de passe de la base** (Supabase → Settings → Database → *Reset database password*). Il a été partagé en clair pendant le développement. Choisissez-en un long, lettres et chiffres.
- [ ] Garder la **même `FACE_KEY`** que celle du `.env` local si des visages sont déjà enregistrés (sinon ils deviennent illisibles).
- [ ] Ne jamais publier `.env`, la clé `service_role` / `sb_secret_…`, ni le mot de passe de la base.
- [ ] Hébergement en **HTTPS** obligatoire (les hébergeurs ci-dessous le fournissent).

## 2. Variables d'environnement du serveur

| Variable | Valeur |
|---|---|
| `NODE_ENV` | `production` |
| `DATABASE_URL` | Supabase → **Connect** → *Session pooler* (port 5432), mot de passe encodé en URL (`@` → `%40`, `'` → `%27`) |
| `JWT_SECRET` | 32 caractères minimum : `node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"` |
| `FACE_KEY` | 64 caractères hexadécimaux : la clé du `.env` local |
| `FACE_THRESHOLD` | `0.5` (à ajuster après essais terrain) |
| `CORS_ORIGINS` | **vide** si l'application web est servie par l'API ; sinon l'adresse du site web |
| `PORT` | fourni par l'hébergeur (3000 par défaut) |

En production, `localhost` n'est **plus** accepté par CORS (seul `CORS_ORIGINS` compte).

## 3. Préparer l'application web (servie par l'API)

À la racine du projet Flutter :

```bash
flutter build web --release --dart-define=API_URL=same-origin
```

Puis copier le résultat dans `backend/public` (cette étape est à refaire à chaque nouvelle version de l'application) :

```powershell
Remove-Item -Recurse -Force backend\public -ErrorAction SilentlyContinue
Copy-Item -Recurse build\web backend\public
```

Si `backend/public/index.html` existe, l'API sert l'application sur `/` ; sinon elle ne sert que l'API.

## 4. Héberger (au choix)

Le serveur a besoin d'environ **512 Mo de mémoire** (moteur de reconnaissance faciale) et de Node ≥ 20.
Un hébergement gratuit qui se met en veille ne convient pas à un usage réel : la première requête prend alors plus d'une minute.

### A. Render (le plus simple)

1. Mettre le projet dans un dépôt GitHub (`git init`, `git add .`, `git commit`, puis pousser). `.env` est ignoré par git.
   Pour que l'application web soit incluse, `backend/public/` doit être commité.
2. Render → **New → Blueprint** → choisir le dépôt : le fichier [render.yaml](../render.yaml) crée le service.
3. Renseigner `DATABASE_URL` et `FACE_KEY` dans le tableau de bord (`JWT_SECRET` est généré).
4. Vérifier `https://<votre-service>.onrender.com/health` → `{"status":"ok"}`.

### B. N'importe quel hébergeur Docker (Fly.io, Railway, VPS…)

```bash
docker build -t briques-paie ./backend
docker run -p 3000:3000 --env-file backend/.env -e NODE_ENV=production briques-paie
```

## 5. Créer le premier admin sur la base de production

Depuis votre PC, avec `DATABASE_URL` de production dans `backend/.env` :

```bash
cd backend
npm run create-admin -- "Votre Nom" 1234
```

Les autres admins, équipes, ouvriers, superviseurs et prix se créent ensuite depuis l'application.

## 6. Application Android

```bash
flutter build apk --release --dart-define=API_URL=https://votre-service.onrender.com
```

L'APK est dans `build/app/outputs/flutter-apk/app-release.apk`. Les permissions Internet et caméra sont déjà déclarées.
Le trafic `http://` n'est autorisé qu'en mode debug : la production doit utiliser `https`.
Pour la distribuer à des superviseurs : transfert direct de l'APK, ou Google Play (compte développeur payant, application signée).

## 7. Après la mise en ligne

- [ ] Se connecter sur l'adresse publique, créer une équipe de test, enregistrer un visage avec une vraie caméra.
- [ ] **Mesurer le seuil facial** avec de vrais ouvriers (même personne sur deux photos différentes) et ajuster `FACE_THRESHOLD`.
- [ ] Activer les **sauvegardes** Supabase (plan payant pour les sauvegardes automatiques) ; sinon exporter régulièrement.
- [ ] Obtenir le **consentement écrit** des ouvriers pour les données biométriques.

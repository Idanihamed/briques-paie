import { loadConfig } from './config.js';
import { createPgDb } from './db.js';
import { createApp } from './app.js';
import { createFaceService } from './services/faces.js';

const config = loadConfig();
const db = createPgDb({ databaseUrl: config.databaseUrl, ssl: config.dbSsl });
const faces = createFaceService({ threshold: config.faceThreshold });
const app = createApp({ db, config, faces });

const server = app.listen(config.port, () => {
  console.log(`API Briques & Paie prête sur le port ${config.port}`);
});

// Charge les modèles de reconnaissance faciale en arrière-plan : la 1re vérification est alors rapide.
// FACE_WARMUP=false : le moteur ne se charge qu'à la première vérification faciale. Utile sur un hébergement
// à petite mémoire (512 Mo) : tout le reste de l'application fonctionne sans le moteur facial.
if (process.env.FACE_WARMUP === 'false') {
  console.log('Moteur facial : chargement différé (FACE_WARMUP=false)');
} else {
  faces.warmup()
    .then(() => console.log('Moteur de reconnaissance faciale prêt'))
    .catch((e) => console.error('Moteur facial indisponible :', e.message));
}

// Arrêt propre : on finit les requêtes en cours puis on ferme le pool.
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    console.log(`${sig} reçu, arrêt…`);
    server.close(async () => {
      await db.close();
      process.exit(0);
    });
  });
}

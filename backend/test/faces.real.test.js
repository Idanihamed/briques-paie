import test from 'node:test';
import assert from 'node:assert/strict';
import jpeg from 'jpeg-js';
import { createFaceService } from '../src/services/faces.js';

// Vérifie que le VRAI moteur (WebAssembly + modèles) se charge et fonctionne sur ce poste.
test('moteur facial réel : image sans visage -> aucun visage, JPEG illisible -> erreur propre', async () => {
  const faces = createFaceService();
  const blank = jpeg.encode({ data: Buffer.alloc(240 * 240 * 4, 128), width: 240, height: 240 }, 80).data;
  assert.deepEqual(await faces.detect(blank), []);
  await assert.rejects(faces.describe(blank), (e) => e.code === 'no_face' && e.status === 422);
  await assert.rejects(faces.describe(Buffer.from('ceci n est pas un jpeg')), (e) => e.code === 'bad_image');
});

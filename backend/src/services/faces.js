import { createRequire } from 'node:module';
import path from 'node:path';
import jpeg from 'jpeg-js';
import { HttpError } from '../lib/errors.js';

const require = createRequire(import.meta.url);

/** Distance euclidienne entre deux signatures de visage (128 valeurs). */
export function faceDistance(a, b) {
  let s = 0;
  for (let i = 0; i < a.length; i++) {
    const d = a[i] - b[i];
    s += d * d;
  }
  return Math.sqrt(s);
}

export const toBuffer = (descriptor) => Buffer.from(new Float32Array(descriptor).buffer);
export const fromBuffer = (buf) => {
  const b = Buffer.from(buf);
  return new Float32Array(b.buffer, b.byteOffset, b.byteLength / 4);
};

/** Moyenne de plusieurs signatures du même visage (plus robuste qu'une seule photo). */
export function averageDescriptor(list) {
  const out = new Float32Array(list[0].length);
  for (const d of list) for (let i = 0; i < out.length; i++) out[i] += d[i] / list.length;
  return out;
}

/**
 * Reconnaissance faciale côté serveur (face-api en WebAssembly : aucune
 * dépendance native, fonctionne sur tout hébergeur Node).
 *
 * Le flux : l'application envoie une photo ; le serveur détecte UN visage, calcule
 * sa signature (128 valeurs), la compare, puis JETTE la photo. Seule la signature
 * (chiffrée par ailleurs) est conservée à l'enregistrement.
 *
 * Limite assumée : pas de détection de « vivacité » (une photo d'une photo peut
 * tromper un système de ce type). La vérification se fait sous le contrôle
 * du superviseur présent sur place.
 */
export function createFaceService({ threshold = 0.5, maxImageSide = 640 } = {}) {
  let ready;
  let faceapi;
  let tf;
  let queue = Promise.resolve(); // un seul calcul à la fois : borne la mémoire et le CPU

  async function init() {
    ready ??= (async () => {
      faceapi = require('@vladmandic/face-api/dist/face-api.node-wasm.js');
      tf = faceapi.tf;
      const wasmDir = path.join(path.dirname(require.resolve('@tensorflow/tfjs-backend-wasm')), '/');
      tf.wasm?.setWasmPaths?.(wasmDir);
      await tf.setBackend('wasm');
      await tf.ready();
      const modelDir = path.join(path.dirname(require.resolve('@vladmandic/face-api/package.json')), 'model');
      await faceapi.nets.ssdMobilenetv1.loadFromDisk(modelDir);
      await faceapi.nets.faceLandmark68Net.loadFromDisk(modelDir);
      await faceapi.nets.faceRecognitionNet.loadFromDisk(modelDir);
    })();
    return ready;
  }

  /** Décode un JPEG/PNG base64 -> tenseur RGB, en réduisant les grandes images. */
  function toTensor(buffer) {
    let img;
    try {
      img = jpeg.decode(buffer, { useTArray: true, formatAsRGBA: true, maxMemoryUsageInMB: 256 });
    } catch {
      throw new HttpError(400, 'Image illisible (JPEG attendu).', 'bad_image');
    }
    const { width, height, data } = img;
    const rgb = new Uint8Array(width * height * 3);
    for (let i = 0, j = 0; i < data.length; i += 4, j += 3) {
      rgb[j] = data[i];
      rgb[j + 1] = data[i + 1];
      rgb[j + 2] = data[i + 2];
    }
    let t = tf.tensor3d(rgb, [height, width, 3], 'int32');
    const side = Math.max(width, height);
    if (side > maxImageSide) {
      const k = maxImageSide / side;
      const resized = tf.image.resizeBilinear(t, [Math.round(height * k), Math.round(width * k)]);
      t.dispose();
      t = resized.toInt();
      resized.dispose();
    }
    return t;
  }

async function detectNow(imageBuffer) {
    await init();
    const input = toTensor(imageBuffer);
    try {
      const results = await faceapi
        .detectAllFaces(input, new faceapi.SsdMobilenetv1Options({ minConfidence: 0.6 }))
        .withFaceLandmarks()
        .withFaceDescriptors();
      return results.map((r) => ({
        box: { x: r.detection.box.x, y: r.detection.box.y, width: r.detection.box.width, height: r.detection.box.height },
        descriptor: Float32Array.from(r.descriptor),
        imageSize: { width: input.shape[1], height: input.shape[0] },
      }));
    } finally {
      input.dispose();
    }
  }

  return {
    threshold,

    /** Charge les modèles à l'avance (évite ~10 s de latence à la première vérification). */
    warmup: () => init(),

    /** Tous les visages d'une image : [{ box:{x,y,width,height}, descriptor }] (coordonnées de l'image réduite). */
    detect(imageBuffer) {
      const run = queue.then(() => detectNow(imageBuffer));
      queue = run.catch(() => {});
      return run;
    },

    /** Signature (Float32Array de 128) du visage présent sur l'image, ou erreur 422. */
    async describe(imageBuffer) {
      {
        const results = await this.detect(imageBuffer);
        if (results.length === 0) {
          throw new HttpError(422, 'Aucun visage détecté. Placez le visage face à la caméra, bien éclairé.', 'no_face');
        }
        if (results.length > 1) {
          throw new HttpError(422, 'Plusieurs visages détectés. Une seule personne à la fois.', 'many_faces');
        }
        return results[0].descriptor;
      }
    },

    distance: faceDistance,
    matches: (a, b) => faceDistance(a, b) <= threshold,
  };
}

# API Briques & Paie (+ application web Flutter si le dossier public/ est présent).
# Construction :  docker build -t briques-paie ./backend
FROM node:22-slim

ENV NODE_ENV=production
WORKDIR /app

# Dépendances de production uniquement (pas de PGlite ni d'outils de test).
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Code, schéma SQL, et application web compilée (backend/public, optionnelle).
COPY . .

# Le processus ne tourne pas en root.
USER node

EXPOSE 3000
ENV PORT=3000

# Vérifie que le serveur ET la base répondent.
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/server.js"]

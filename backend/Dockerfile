FROM node:20-alpine

WORKDIR /app

# Build context is the repository root (set by render.yaml / Railway).
# We install only backend deps, then copy backend source plus the
# prebuilt Flutter web bundle so the same server can serve API + web.

COPY backend/package*.json ./
COPY backend/prisma ./prisma/

RUN npm ci --omit=dev
RUN npx prisma generate

COPY backend/ ./

# Copy the prebuilt web bundle to the path the server expects
# (path.join(__dirname, '../../build/web') from /app/src → /build/web).
RUN mkdir -p /build
COPY build/web /build/web

EXPOSE 3000

CMD ["sh", "-c", "npx prisma migrate deploy && (node prisma/seed.js || true) && node src/index.js"]

# Etapa 1: genera el HTML autonomo con los datos completos (uso interno)
FROM node:22-alpine AS build
WORKDIR /app
COPY data ./data
COPY src ./src
COPY scripts ./scripts
RUN node scripts/build.js interno

# Etapa 2: solo sirve el estatico resultante
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- http://localhost/ >/dev/null 2>&1 || exit 1

FROM node:22.19.0-bookworm-slim@sha256:4a4884e8a44826194dff92ba316264f392056cbe243dcc9fd3551e71cea02b90 AS build
ENV NEXT_TELEMETRY_DISABLED=1
WORKDIR /source
# Build from source: the npm tarball omits modules required by its prebuilt pages.
ADD --checksum=sha256:7d7fdc5e45ee023cb7fe03836a4edbe0e901e360a56c975b2a34c5449480a1be https://codeload.github.com/manibordev/formloop/tar.gz/78520e96daac2d0a088fdc4e33e3c567f2d604f5 /tmp/formloop.tar.gz
RUN tar -xzf /tmp/formloop.tar.gz --strip-components=1 && rm /tmp/formloop.tar.gz
WORKDIR /source/apps/server
RUN npm ci --ignore-scripts --no-audit --no-fund && npm run build && mkdir -p public

FROM node:22.19.0-bookworm-slim@sha256:4a4884e8a44826194dff92ba316264f392056cbe243dcc9fd3551e71cea02b90
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1
LABEL org.opencontainers.image.source="https://github.com/manibordev/formloop" \
      org.opencontainers.image.revision="78520e96daac2d0a088fdc4e33e3c567f2d604f5"
# MCP dependencies are not traced into the Next.js standalone output.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund && npm cache clean --force
COPY --from=build /source/apps/server/.next/standalone ./
COPY --from=build /source/apps/server/.next/static ./.next/static
COPY --from=build /source/apps/server/public ./public
COPY --from=build /source/apps/server/bin ./bin
COPY mcp-entry.mjs ./mcp-entry.mjs
COPY --chmod=755 browser-notice /usr/local/bin/xdg-open
USER node
EXPOSE 3847
CMD ["node", "/app/server.js"]

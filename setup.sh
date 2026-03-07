#!/bin/bash
set -euo pipefail

WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_IMAGE="claude-code-base"
FINAL_IMAGE="claude-code"
TEMP_CONTAINER="claude-code-setup"

# -------------------------------------------------------
# Nettoyage en cas d'erreur ou d'interruption
# -------------------------------------------------------
cleanup() {
    local exit_code=$?
    echo ""
    echo "Nettoyage..."
    docker rm -f "$TEMP_CONTAINER" > /dev/null 2>&1 || true
    if [ -d "$WORK_DIR/auth" ]; then
        rm -f "$WORK_DIR/auth/.credentials.json" "$WORK_DIR/auth/.claude.json"
        rmdir "$WORK_DIR/auth" 2>/dev/null || true
    fi
    rm -f "$WORK_DIR/Dockerfile.base"
    exit "$exit_code"
}
trap cleanup ERR INT TERM

# -------------------------------------------------------
# Vérification des pré-requis
# -------------------------------------------------------
for cmd in docker python3; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "Erreur : $cmd n'est pas installé." >&2
        exit 1
    fi
done

if ! docker compose version > /dev/null 2>&1; then
    echo "Erreur : docker compose n'est pas disponible." >&2
    exit 1
fi

# Vérifier que BuildKit est disponible
if ! DOCKER_BUILDKIT=1 docker build --help 2>&1 | grep -q "secret"; then
    echo "Erreur : Docker BuildKit est requis (Docker >= 18.09)." >&2
    exit 1
fi

echo "=== Claude Code - Installation conteneurisée ==="
echo ""

# -------------------------------------------------------
# Étape 1 : Créer les fichiers du projet
# -------------------------------------------------------
echo "[1/6] Création des fichiers..."

cat > "$WORK_DIR/entrypoint.sh" << 'ENTRYPOINT'
#!/bin/sh
chown node:node /workspace
# Rendre les tokens accessibles à root et node (volume partagé)
chmod 666 /root/.claude/.credentials.json 2>/dev/null || true
exec gosu node "$@"
ENTRYPOINT
chmod +x "$WORK_DIR/entrypoint.sh"

cat > "$WORK_DIR/Dockerfile.base" << 'DOCKERFILE'
FROM node:22-slim
RUN apt-get update && apt-get install -y git curl ripgrep gosu locales \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/fr_FR.UTF-8/s/^# //' /etc/locale.gen && locale-gen
ENV LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8
RUN npm install -g @anthropic-ai/claude-code
WORKDIR /workspace
DOCKERFILE

cat > "$WORK_DIR/docker-compose.yml" << 'COMPOSE'
services:
  claude-code:
    build: .
    image: claude-code
    container_name: claude-code
    stdin_open: true
    tty: true
    environment:
      - TZ=Europe/Paris
    volumes:
      - ${PROJECT_DIR:-./claude-data}:/workspace
      - claude-auth:/root/.claude
      - claude-auth:/home/node/.claude
    working_dir: /workspace
    command: ["sleep", "infinity"]

volumes:
  claude-auth:
COMPOSE

cat > "$WORK_DIR/.dockerignore" << 'DOCKERIGNORE'
setup.sh
run.sh
*.md
.git
.env
.dockerignore
Dockerfile.base
DOCKERIGNORE

# -------------------------------------------------------
# Étape 2 : Build de l'image de base (sans auth)
# -------------------------------------------------------
echo "[2/6] Build de l'image de base..."
docker build -t "$BASE_IMAGE" -f "$WORK_DIR/Dockerfile.base" "$WORK_DIR" -q

# -------------------------------------------------------
# Étape 3 : Login interactif
# -------------------------------------------------------
echo "[3/6] Lancement du conteneur pour l'authentification..."
echo "    -> Connectez-vous avec 'claude login' puis tapez 'exit' quand c'est fait."
echo ""

docker run -it --name "$TEMP_CONTAINER" "$BASE_IMAGE" /bin/bash

# -------------------------------------------------------
# Étape 4 : Extraction des fichiers d'auth
# -------------------------------------------------------
echo ""
echo "[4/6] Extraction des fichiers d'authentification..."

mkdir -p "$WORK_DIR/auth"

if ! docker cp "$TEMP_CONTAINER:/root/.claude/.credentials.json" "$WORK_DIR/auth/.credentials.json" 2>/dev/null; then
    echo "Erreur : fichier .credentials.json introuvable dans le conteneur." >&2
    echo "Avez-vous bien exécuté 'claude login' avant de taper 'exit' ?" >&2
    docker rm -f "$TEMP_CONTAINER" > /dev/null 2>&1 || true
    exit 1
fi

if ! docker cp "$TEMP_CONTAINER:/root/.claude.json" "$WORK_DIR/auth/.claude.json" 2>/dev/null; then
    echo "Erreur : fichier .claude.json introuvable dans le conteneur." >&2
    echo "Avez-vous bien exécuté 'claude login' avant de taper 'exit' ?" >&2
    docker rm -f "$TEMP_CONTAINER" > /dev/null 2>&1 || true
    exit 1
fi

docker rm -f "$TEMP_CONTAINER" > /dev/null

# Nettoyer le .claude.json : garder uniquement oauthAccount, hasCompletedOnboarding, mcpServers
echo ""
read -rp "Clef API Context7 (laisser vide pour ne pas configurer context7) : " context7_key
CONF="$WORK_DIR/auth/.claude.json" CONTEXT7_KEY="$context7_key" python3 << 'PYCLEAN'
import json, os, sys, tempfile

conf = os.environ['CONF']
try:
    with open(conf) as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError) as e:
    print(f"Erreur : impossible de lire {conf} : {e}", file=sys.stderr)
    sys.exit(1)

if 'oauthAccount' not in data:
    print("Erreur : oauthAccount absent. Le login a-t-il réussi ?", file=sys.stderr)
    sys.exit(1)

clean = {
    'oauthAccount': data['oauthAccount'],
    'hasCompletedOnboarding': True,
    'mcpServers': {
        'datagouv': {
            'type': 'http',
            'url': 'https://mcp.data.gouv.fr/mcp',
        },
    },
}
ctx7_key = os.environ.get('CONTEXT7_KEY', '')
if ctx7_key:
    clean['mcpServers']['context7'] = {
        'type': 'stdio',
        'command': 'npx',
        'args': ['-y', '@upstash/context7-mcp', '--api-key', ctx7_key],
        'env': {},
    }

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(conf))
try:
    with os.fdopen(fd, 'w') as f:
        json.dump(clean, f, indent=2)
    os.replace(tmp, conf)
except Exception:
    os.unlink(tmp)
    raise
PYCLEAN

echo "    -> Fichiers extraits et nettoyés."

# -------------------------------------------------------
# Étape 5 : Ajout de serveurs MCP supplémentaires (optionnel)
# -------------------------------------------------------
echo ""
read -rp "Voulez-vous ajouter d'autres serveurs MCP ? (o/N) " add_mcp

if [ "$add_mcp" = "o" ] || [ "$add_mcp" = "O" ]; then
    while true; do
        echo ""
        echo "Type de serveur :"
        echo "  1) HTTP  (ex: https://mcp.data.gouv.fr/mcp)"
        echo "  2) stdio (ex: npx -y @upstash/context7-mcp)"
        echo "  q) Terminer"
        read -rp "Choix : " mcp_type

        case "$mcp_type" in
            1)
                read -rp "Nom du serveur : " mcp_name
                read -rp "URL : " mcp_url
                MCP_NAME="$mcp_name" MCP_URL="$mcp_url" CONF="$WORK_DIR/auth/.claude.json" python3 << 'PYHTTP'
import json, os, sys, tempfile

conf = os.environ['CONF']
try:
    with open(conf) as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError) as e:
    print(f"Erreur : impossible de lire {conf} : {e}", file=sys.stderr)
    sys.exit(1)
data.setdefault('mcpServers', {})[os.environ['MCP_NAME']] = {
    'type': 'http',
    'url': os.environ['MCP_URL'],
}
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(conf))
try:
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, conf)
except Exception:
    os.unlink(tmp)
    raise
print(f"    -> {os.environ['MCP_NAME']} ajouté.")
PYHTTP
                ;;
            2)
                read -rp "Nom du serveur : " mcp_name
                read -rp "Commande complète (ex: npx -y @upstash/context7-mcp --api-key CLEF) : " mcp_cmd
                MCP_NAME="$mcp_name" MCP_CMD="$mcp_cmd" CONF="$WORK_DIR/auth/.claude.json" python3 << 'PYSTDIO'
import json, shlex, os, sys, tempfile

conf = os.environ['CONF']
try:
    with open(conf) as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError) as e:
    print(f"Erreur : impossible de lire {conf} : {e}", file=sys.stderr)
    sys.exit(1)
args = shlex.split(os.environ['MCP_CMD'])
data.setdefault('mcpServers', {})[os.environ['MCP_NAME']] = {
    'type': 'stdio',
    'command': args[0],
    'args': args[1:],
    'env': {},
}
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(conf))
try:
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, conf)
except Exception:
    os.unlink(tmp)
    raise
print(f"    -> {os.environ['MCP_NAME']} ajouté.")
PYSTDIO
                ;;
            q|Q|"") break ;;
            *) echo "Choix invalide." ;;
        esac
    done
fi

# -------------------------------------------------------
# Étape 6 : Build de l'image finale avec auth (BuildKit secrets)
# -------------------------------------------------------
echo ""
echo "[5/6] Build de l'image finale..."

cat > "$WORK_DIR/Dockerfile" << 'DOCKERFILE'
# syntax=docker/dockerfile:1
FROM node:22-slim

RUN apt-get update && apt-get install -y git curl ripgrep gosu locales \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/fr_FR.UTF-8/s/^# //' /etc/locale.gen && locale-gen
ENV LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8
ENV TZ=Europe/Paris

RUN npm install -g @anthropic-ai/claude-code

RUN mkdir -p /home/node/.claude /root/.claude

RUN --mount=type=secret,id=credentials \
    --mount=type=secret,id=claude_json \
    cp /run/secrets/credentials /home/node/.claude/.credentials.json && \
    cp /run/secrets/claude_json /home/node/.claude.json && \
    chown -R node:node /home/node/.claude /home/node/.claude.json && \
    chmod 600 /home/node/.claude/.credentials.json /home/node/.claude.json && \
    cp /run/secrets/credentials /root/.claude/.credentials.json && \
    cp /run/secrets/claude_json /root/.claude.json && \
    chmod 600 /root/.claude/.credentials.json /root/.claude.json

RUN printf '#!/bin/sh\nexec gosu node claude --dangerously-skip-permissions "$@"\n' > /usr/local/bin/claude-auto \
    && chmod +x /usr/local/bin/claude-auto

COPY entrypoint.sh /entrypoint.sh
WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

DOCKER_BUILDKIT=1 docker build \
    --no-cache \
    --secret "id=credentials,src=$WORK_DIR/auth/.credentials.json" \
    --secret "id=claude_json,src=$WORK_DIR/auth/.claude.json" \
    -t "$FINAL_IMAGE" \
    -f "$WORK_DIR/Dockerfile" \
    "$WORK_DIR" -q

# -------------------------------------------------------
# Suppression des fichiers d'auth temporaires
# -------------------------------------------------------
echo "[6/6] Nettoyage et initialisation du volume d'authentification..."

rm -f "$WORK_DIR/auth/.credentials.json" "$WORK_DIR/auth/.claude.json"
rmdir "$WORK_DIR/auth" 2>/dev/null || true
rm -f "$WORK_DIR/Dockerfile.base"
docker rmi "$BASE_IMAGE" > /dev/null 2>&1 || true

# Initialiser le volume claude-auth avec les tokens de l'image
docker run --rm \
    -v claude-auth:/root/.claude \
    -v claude-auth:/home/node/.claude \
    "$FINAL_IMAGE" true > /dev/null

echo ""
echo "=== Installation terminée ==="
echo ""
echo "Utilisation :"
echo "  docker compose up -d"
echo "  docker exec -ti claude-code claude          # mode normal"
echo "  docker exec -ti claude-code claude-auto     # mode autonome"
echo ""
echo "Ou avec run.sh pour lancer plusieurs instances :"
echo "  ./run.sh"
echo ""
echo "Les identifiants sont intégrés dans l'image."
echo "Les fichiers temporaires ont été supprimés."
echo "Les secrets ne sont pas visibles dans les layers Docker."

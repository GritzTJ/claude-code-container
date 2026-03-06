# claude-code-container

Exécuter Claude Code dans un conteneur Docker isolé, avec authentification intégrée via BuildKit.

*Run Claude Code in an isolated Docker container, with built-in authentication via BuildKit.*

---

## Pré-requis / Prerequisites

- Docker (avec BuildKit) et Docker Compose / Docker (with BuildKit) and Docker Compose
- Python 3
- Un compte Claude avec abonnement actif (Pro/Max) / A Claude account with an active subscription (Pro/Max)

## Installation

```bash
git clone https://github.com/GritzTJ/claude-code-container.git
cd claude-code-container
chmod +x setup.sh run.sh
./setup.sh
```

Le script `setup.sh` :

1. Crée les fichiers nécessaires (Dockerfile, docker-compose.yml, entrypoint.sh)
2. Build une image de base
3. Lance un conteneur temporaire pour se connecter (`claude login`)
4. Configure les serveurs MCP (datagouv, context7 optionnel, et serveurs personnalisés)
5. Build l'image finale avec les identifiants intégrés via BuildKit secret mounts
6. Supprime les fichiers d'authentification temporaires

Les identifiants ne sont ni sur le disque, ni dans les layers Docker.

---

*The `setup.sh` script:*

1. *Creates the necessary files (Dockerfile, docker-compose.yml, entrypoint.sh)*
2. *Builds a base image*
3. *Starts a temporary container to log in (`claude login`)*
4. *Configures MCP servers (datagouv, optional context7, and custom servers)*
5. *Builds the final image with credentials via BuildKit secret mounts*
6. *Removes temporary authentication files*

*Credentials are neither on disk nor in Docker layers.*

## Utilisation / Usage

### docker-compose (instance unique / single instance)

```bash
docker compose up -d
docker exec -ti claude-code claude          # mode interactif / interactive mode
docker exec -ti claude-code claude-auto     # mode autonome / autonomous mode
docker exec -ti claude-code claude-auto -p "Crée un fichier hello.py"
```

Pour changer le dossier de travail, créer un fichier `.env` :

*To change the working directory, create a `.env` file:*

```bash
echo 'PROJECT_DIR=/chemin/vers/projet' > .env
docker compose up -d
```

### run.sh (instances multiples / multiple instances)

```bash
./run.sh
```

Permet de lancer plusieurs conteneurs indépendants avec choix du nom et du type de stockage (bind mount ou volume Docker).

*Launches multiple independent containers with a choice of name and storage type (bind mount or Docker volume).*

## Déployer sur un autre serveur / Deploy to another server

**Option A** : Relancer le script / Re-run the script

```bash
scp setup.sh run.sh user@server:~/
ssh user@server "chmod +x setup.sh run.sh && ./setup.sh"
```

**Option B** : Exporter l'image / Export the image

```bash
# Serveur source / Source server
docker save claude-code | gzip > claude-code.tar.gz

# Serveur cible / Target server
scp claude-code.tar.gz run.sh user@server:~/
ssh user@server "gunzip -c ~/claude-code.tar.gz | docker load"
```

## Sécurité / Security

- Les identifiants sont intégrés via **BuildKit secret mounts** : invisibles dans les layers Docker, mais l'image reste sensible — **ne pas la pousser sur un registry public**
- `claude-auto` exécute sans confirmation : isolé dans le conteneur, mais `/workspace` affecte le système hôte
- Les tokens sont renouvelés automatiquement via le refresh token

---

- *Credentials are embedded via **BuildKit secret mounts**: invisible in Docker layers, but the image is sensitive — **do not push to a public registry***
- *`claude-auto` runs without confirmation: isolated in the container, but `/workspace` affects the host filesystem*
- *Tokens are automatically renewed via the refresh token*

## Structure

```
claude-code-container/
├── setup.sh             # Script d'installation / Installation script
├── run.sh               # Lancement d'instances / Instance launcher
├── Dockerfile           # (généré / generated)
├── docker-compose.yml   # (généré / generated)
├── entrypoint.sh        # (généré / generated)
├── .dockerignore        # (généré / generated)
├── .env                 # (optionnel / optional)
└── claude-data/         # Dossier de travail / Working directory
```

## Licence / License

MIT

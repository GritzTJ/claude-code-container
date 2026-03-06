**[🇫🇷 Français](#français) · [🇬🇧 English](#english)**

---

# Français

## claude-code-container — Claude Code dans Docker

Deux scripts pour exécuter Claude Code dans un conteneur Docker isolé, avec authentification intégrée via BuildKit secret mounts.

### Pourquoi ?

| | |
|---|---|
| **Isolation complète** | Claude Code tourne dans un conteneur — rien n'est installé sur l'hôte |
| **Authentification sécurisée** | Les identifiants sont intégrés via BuildKit secret mounts, invisibles dans les layers Docker |
| **Instances multiples** | Lancez autant de conteneurs que nécessaire, chacun sur un projet différent |
| **Mode autonome** | `claude-auto` exécute sans confirmation, en toute sécurité grâce à l'isolation |

### Installation

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

### Pré-requis

- Docker (avec BuildKit) et Docker Compose
- Python 3
- Un compte Claude avec abonnement actif (Pro/Max)

### Utilisation

#### docker-compose (instance unique)

```bash
docker compose up -d
docker exec -ti claude-code claude          # mode interactif
docker exec -ti claude-code claude-auto     # mode autonome
docker exec -ti claude-code claude-auto -p "Crée un fichier hello.py"
```

Pour changer le dossier de travail, créer un fichier `.env` :

```bash
echo 'PROJECT_DIR=/chemin/vers/projet' > .env
docker compose up -d
```

#### run.sh (instances multiples)

```bash
./run.sh
```

Permet de lancer plusieurs conteneurs indépendants avec choix du nom et du type de stockage (bind mount ou volume Docker).

### Déployer sur un autre serveur

**Option A** : Relancer le script

```bash
scp setup.sh run.sh user@serveur:~/
ssh user@serveur "chmod +x setup.sh run.sh && ./setup.sh"
```

**Option B** : Exporter l'image (pas besoin de se ré-authentifier)

```bash
# Serveur source
docker save claude-code | gzip > claude-code.tar.gz

# Serveur cible
scp claude-code.tar.gz run.sh user@serveur:~/
ssh user@serveur "gunzip -c ~/claude-code.tar.gz | docker load"
```

### Sécurité

- Les identifiants sont intégrés via **BuildKit secret mounts** : invisibles dans les layers Docker, mais l'image reste sensible — **ne pas la pousser sur un registry public**
- `claude-auto` exécute sans confirmation : isolé dans le conteneur, mais `/workspace` affecte le système hôte
- Les tokens sont renouvelés automatiquement via le refresh token
- Les fichiers d'authentification temporaires sont supprimés après le build

### Structure

```
claude-code-container/
├── setup.sh             # Script d'installation
├── run.sh               # Lancement d'instances
├── Dockerfile           # (généré par setup.sh)
├── docker-compose.yml   # (généré par setup.sh)
├── entrypoint.sh        # (généré par setup.sh)
├── .dockerignore        # (généré par setup.sh)
├── .env                 # (optionnel) Variable PROJECT_DIR
└── claude-data/         # Dossier de travail par défaut
```

---

### Licence

MIT

---

# English

## claude-code-container — Claude Code in Docker

Two scripts to run Claude Code in an isolated Docker container, with built-in authentication via BuildKit secret mounts.

### Why?

| | |
|---|---|
| **Full isolation** | Claude Code runs inside a container — nothing is installed on the host |
| **Secure authentication** | Credentials are embedded via BuildKit secret mounts, invisible in Docker layers |
| **Multiple instances** | Spin up as many containers as needed, each working on a different project |
| **Autonomous mode** | `claude-auto` runs without confirmation, safely thanks to isolation |

### Installation

```bash
git clone https://github.com/GritzTJ/claude-code-container.git
cd claude-code-container
chmod +x setup.sh run.sh
./setup.sh
```

The `setup.sh` script:

1. Creates the necessary files (Dockerfile, docker-compose.yml, entrypoint.sh)
2. Builds a base image
3. Starts a temporary container to log in (`claude login`)
4. Configures MCP servers (datagouv, optional context7, and custom servers)
5. Builds the final image with credentials via BuildKit secret mounts
6. Removes temporary authentication files

Credentials are neither on disk nor in Docker layers.

### Prerequisites

- Docker (with BuildKit) and Docker Compose
- Python 3
- A Claude account with an active subscription (Pro/Max)

### Usage

#### docker-compose (single instance)

```bash
docker compose up -d
docker exec -ti claude-code claude          # interactive mode
docker exec -ti claude-code claude-auto     # autonomous mode
docker exec -ti claude-code claude-auto -p "Create a hello.py file"
```

To change the working directory, create a `.env` file:

```bash
echo 'PROJECT_DIR=/path/to/project' > .env
docker compose up -d
```

#### run.sh (multiple instances)

```bash
./run.sh
```

Launches multiple independent containers with a choice of name and storage type (bind mount or Docker volume).

### Deploy to another server

**Option A**: Re-run the script

```bash
scp setup.sh run.sh user@server:~/
ssh user@server "chmod +x setup.sh run.sh && ./setup.sh"
```

**Option B**: Export the image (no need to re-authenticate)

```bash
# Source server
docker save claude-code | gzip > claude-code.tar.gz

# Target server
scp claude-code.tar.gz run.sh user@server:~/
ssh user@server "gunzip -c ~/claude-code.tar.gz | docker load"
```

### Security

- Credentials are embedded via **BuildKit secret mounts**: invisible in Docker layers, but the image is sensitive — **do not push to a public registry**
- `claude-auto` runs without confirmation: isolated in the container, but `/workspace` affects the host filesystem
- Tokens are automatically renewed via the refresh token
- Temporary authentication files are deleted after the build

### Structure

```
claude-code-container/
├── setup.sh             # Installation script
├── run.sh               # Instance launcher
├── Dockerfile           # (generated by setup.sh)
├── docker-compose.yml   # (generated by setup.sh)
├── entrypoint.sh        # (generated by setup.sh)
├── .dockerignore        # (generated by setup.sh)
├── .env                 # (optional) PROJECT_DIR variable
└── claude-data/         # Default working directory
```

---

### License

MIT

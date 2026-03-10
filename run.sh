#!/bin/bash
set -euo pipefail

IMAGE="claude-code"

# Vérification
if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
    echo "Erreur : l'image '$IMAGE' n'existe pas. Lancez d'abord setup.sh." >&2
    exit 1
fi

# Nom du conteneur
read -rp "Nom du conteneur (défaut: claude-code) : " container_name
container_name="${container_name:-claude-code}"

if [[ ! "$container_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
    echo "Erreur : nom de conteneur invalide (lettres, chiffres, _, . et - uniquement)." >&2
    exit 1
fi

# Persistance de /workspace
echo ""
echo "Persistance de /workspace :"
echo "  1) Bind mount  — dossier du serveur monté dans le conteneur (défaut)"
echo "  2) Volume Docker — volume géré par Docker"
echo "  3) Aucune — /workspace éphémère (perdu à la suppression du conteneur)"
read -rp "Choix (1/2/3) : " volume_type
volume_type="${volume_type:-1}"

volume_arg=""

case "$volume_type" in
    1)
        read -rp "Dossier à monter dans /workspace (défaut: ./$container_name) : " project_dir
        project_dir="${project_dir:-./$container_name}"

        mkdir -p "$project_dir"
        project_dir_abs="$(cd "$project_dir" && pwd)" || {
            echo "Erreur : impossible d'accéder à '$project_dir'." >&2
            exit 1
        }

        volume_arg="$project_dir_abs:/workspace"
        ;;
    2)
        volume_name="${container_name}-data"
        volume_arg="$volume_name:/workspace"
        ;;
    3)
        ;;
    *)
        echo "Erreur : choix invalide." >&2
        exit 1
        ;;
esac

# Lancement
if [ -n "$volume_arg" ]; then
    docker run -d \
        --name "$container_name" \
        --hostname "$container_name" \
        -e TZ=Europe/Paris \
        -v "$volume_arg" \
        -v claude-auth:/root/.claude \
        -v claude-auth:/home/node/.claude \
        -w /workspace \
        "$IMAGE" \
        sleep infinity
else
    docker run -d \
        --name "$container_name" \
        --hostname "$container_name" \
        -e TZ=Europe/Paris \
        -v claude-auth:/root/.claude \
        -v claude-auth:/home/node/.claude \
        -w /workspace \
        "$IMAGE" \
        sleep infinity
fi

echo ""
echo "Conteneur '$container_name' démarré."
echo ""
echo "Utilisation :"
echo "  docker exec -ti $container_name claude          # mode normal"
echo "  docker exec -ti $container_name claude-auto     # mode autonome"

if [ "$volume_type" = "2" ]; then
    echo ""
    echo "Suppression (conteneur + volume) :"
    echo "  docker rm -f $container_name && docker volume rm $volume_name"
fi

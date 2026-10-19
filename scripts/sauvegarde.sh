#!/usr/bin/env bash
# fichier de sauvegarde de bankdb
# Usage : sudo ./scripts/sauvegarde.sh
set -euo pipefail

NORMAL="\033[0m"
CYAN="\033[1;36m"
JAUNE="\033[1;33m"
ROUGE="\033[1;31m"
VERT="\033[1;32m"

REUSSITE="oui"

DATE_DU_JOUR=$(date +%F)
FICHIER="/var/backups/postgresql/${DATE_DU_JOUR}_bankdb.dump"

# Dossier où se trouve ce script, quel que soit l'endroit d'où on le lance :
# realpath "$0" donne le chemin complet du script, dirname n'en garde que le dossier
DOSSIER_SCRIPT="$(dirname "$(realpath "$0")")"

# Requête de comptage, pour comparer la base et sa copie restaurée.
# .. remonte du dossier scripts/ au dossier du dépôt, puis on redescend dans SQL/outils/
FICHIER_COMPARE="$DOSSIER_SCRIPT/../SQL/outils/compare.sql"

# Fonction d'appel de log, avec un préfixe afin de différencier les logs
# mettre en deuxième arg le type de réponse: "s", "a" ou "e"
log() {
  #succes
  if [[ ${2:-} == "s" ]]; then
    echo -e "\n${VERT}===success> $1 ${NORMAL}\n"
  # Avertissement
  elif [[ ${2:-} == "a" ]]; then
    echo -e "\n${JAUNE}=====alert> $1 ${NORMAL}\n"
  # Erreur
  elif [[ ${2:-} == "e" ]]; then
    echo -e "\n${ROUGE}=====error> $1 ${NORMAL}\n" >&2
  # Information
  else
    echo -e "\n${CYAN}==========> $1 ${NORMAL}\n"
  fi
}

# Verification si l'user est bien en tant que root
if [[ $EUID -ne 0 ]]; then
  log "Ce script doit se lancer en tant que root" "e"
  log "Usage : sudo $0" "e"
  exit 1
fi

# Création du dossier de backup pour postgresql
log "Création du dossier de backup pour postgresql"
mkdir -p /var/backups/postgresql
log "Création du dossier de backup pour postgresql terminée" "s"
# On met postgres propriétaire du dossier et on donne les droits uniquement à lui
log "postgres propriétaire du dossier de backup"
chown postgres:postgres /var/backups/postgresql
log "postgres propriétaire du dossier de backup terminée" "s"
log "droit sur le dossier uniquement pour postgres"
chmod 700 /var/backups/postgresql
log "droit sur le dossier uniquement pour postgres terminé" "s"

# On créer un backup de la db active
log "Création de la sauvegarde de bankdb dans le dossier de backup"
sudo -u postgres pg_dump -Fc -f "${FICHIER}" bankdb
log "Création de la sauvegarde de bankdb dans le dossier de backup terminée" "s"

# Création de la db_restore vide
log "Création de la db_restore"
# Suppression de la base s'il elle existe
log "Suppression de la base s'il elle existe"
sudo -u postgres dropdb --if-exists bankdb_restore
log "Suppression de la base s'il elle existe terminée" "s"
# Création de la db_restore
sudo -u postgres createdb bankdb_restore
log "Création de la db_restore terminée" "s"
# On met les données en backup dans la db
log "Integration des données de la sauvegarde dans bankdb_restore"
sudo -u postgres pg_restore -d bankdb_restore < "$FICHIER"
log "Integration des données de la sauvegarde dans bankdb_restore terminée" "s"

# On fait le test SQL de compare.sql avec la db active
log "Test des différences de données entre bankdb et bankdb_restore"

# Option : -A retire l’alignement en colonnes, -t retire les titres et le nombre de lignes
log "Récupération des données à comparer sur bankdb"
AVANT=$(sudo -u postgres psql -d bankdb -At < "${FICHIER_COMPARE}")
log "Récupération des données à comparer sur bankdb terminée" "s"
# On fait le test SQL de compare.sql avec la db restore
log "Récupération des données à comparer sur bankdb_restore"
APRES=$(sudo -u postgres psql -d bankdb_restore -At < "${FICHIER_COMPARE}")
log "Récupération des données à comparer sur bankdb_restore terminée" "s"

# Test entre les deux données
log "Test en cours"
if [[ "${AVANT}" != "${APRES}" ]]; then
  log "Les données entre les deux bases ne sont pas équivalentes" "e"
  echo "bankdb :"          ; echo "$AVANT"
  echo "bankdb_restore :"  ; echo "$APRES"
  REUSSITE="non"
else
  log "Test des différences de données entre bankdb et bankdb_restore terminé" "s"
fi

# Suppression de la base temporaire bankdb_restore
log "Suppression de la base temporaire bankdb_restore"
sudo -u postgres dropdb bankdb_restore
log "Suppression de la base temporaire bankdb_restore terminée" "s"
if [[ "$REUSSITE" == "non" ]]; then
  log "Echec de la sauvegarde" "e"
  exit 1
else
  log "Sauvegarde réussie" "s"
fi
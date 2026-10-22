#!/usr/bin/env bash
# fichier de mise en place de la base de donnée dans un serveur postgresql prêt et configuré (voir installation.sh)
# Usage : sudo ./scripts/recreation_db.sh
set -euo pipefail

NORMAL="\033[0m"
CYAN="\033[1;36m"
JAUNE="\033[1;33m"
ROUGE="\033[1;31m"
VERT="\033[1;32m"
MAGENTA="\033[1;35m"


DOSSIER_SCRIPT="$(dirname "$(realpath "$0")")"
DOSSIER_SQL="$DOSSIER_SCRIPT/../SQL"

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
  # Demande
  elif [[ ${2:-} == "d" ]]; then
    echo -e "\n${MAGENTA}===demande> $1 ${NORMAL}\n" >&2
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

# # Avant d'effectuer quoi que ce soit, on demande à l'user s'il veux bien suppr la base et ses rôles
#  "Demande de suppression"
# -p affiche la question, la réponse tapée est rangée dans la variable REPONSE
# -r empêche Bash d’interpréter les \ dans la réponse
# read -r -p "Cette opération supprime TOUTE la base bankdb. Tapez OUI pour continuer : " REPONSE

## On vérifie i la réponse est bonne, si non on annule tout
#if [[ "$REPONSE" != "OUI" ]]; then
#  log "Opération annulée, rien n’a été modifié" "a"
#  exit 0
#fi

log "Début des suppression"
# Suppression de la db
log "Suppression de la db"
sudo -u postgres dropdb --if-exists --force bankdb
log "Suppression de la db terminé" "s"

# Suppression des rôles
log "Suppression des rôles"
sudo -u postgres psql -c "DROP ROLE IF EXISTS grp_analyste, grp_support, grp_appli, grp_auditeur, analyste_alice, support_bob, app_novabank, auditeur_chloe, bank_owner"
log "Suppression des rôles terminée" "s"

log "Reconstruction de bankdb"
# tous les fichiers SQL numérotés, dans l'ordre alphabétique : 00_, 01_, … 09_
log "Exécution des fichiers SQL"
for FICHIER in "$DOSSIER_SQL"/[0-9][0-9]_*.sql; do
  log "Exécution de $(basename "$FICHIER")"
  if [[ "$FICHIER" == "$DOSSIER_SQL"/00_*.sql || "$FICHIER" == "$DOSSIER_SQL"/04_*.sql ]]; then
    sudo -u postgres psql < "$FICHIER"
  else
    # on exécute le fichier en tant que bank_owner, sans mot de passe :
    # postgres se connecte (règle peer), puis SET ROLE fait agir la session en tant que bank_owner
    { echo "SET ROLE bank_owner;"; cat "$FICHIER"; } | sudo -u postgres psql -d bankdb
  fi
  log "Exécution de $(basename "$FICHIER") terminée" "s"
done
log "Exécution des fichiers SQL terminée" "s"

log "Definition des mots de passe des comptes"
# L'user définit maintenant les mot de passe de chaque compte
for COMPTE in bank_owner analyste_alice support_bob app_novabank auditeur_chloe; do
    log "Demande d'un mot de passe pour le compte $COMPTE" "d"
    log "Attention, si le mot de passe est vide, le compte ne pourra pas se connecter, il faudra donc le définir plus tard en tant que postgres" "a"
    # redemande le mot de passe tant que les deux saisies ne correspondent pas
    until sudo -u postgres psql -c "\password $COMPTE" ; do
        log "Les deux saisies ne correspondent pas, recommencez" "a"
        log "Attention, si le mot de passe est vide, le compte ne pourra pas se connecter, il faudra donc le définir plus tard en tant que postgres" "a"
    done
    log "Mot de passe de $COMPTE défini" "s"
done
log "Definition des mots de passe des comptes terminée" "s"

log "Reconstruction de bankdb terminée" "s"

#!/usr/bin/env bash
# fichier qui enchaîne serveur, base, tests et sauvegarde.
# Usage : sudo ./scripts/tout_refaire.sh
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

# Demande d'instalation:
# demander : pose une question, réussit (code 0) seulement si on répond oui
demander() {
    # -p affiche la question, la réponse tapée est rangée dans la variable REPONSE
    # -r empêche Bash d’interpréter les \ dans la réponse
    REPONSE=""
    until [[ "$REPONSE" == "oui" || "$REPONSE" == "non" || "$REPONSE" == "o" || "$REPONSE" == "n" ]]; do
      read -r -p "$1 (oui/non) : " REPONSE
      if [[ "$REPONSE" != "oui" && "$REPONSE" != "non" && "$REPONSE" != "o" && "$REPONSE" != "n" ]]; then
        log "Veuillez répondre par \"oui\", \"o\", \"non\" ou \"n\" ($REPONSE)" "a"
      fi
    done
    if [[ "$REPONSE" == "oui" || "$REPONSE" == "o" ]]; then
      return 0
    fi
    return 1
}

log "Demande d'installation du serveur postgresql" "d"
if demander "Installer le serveur ?"; then
    sudo "${DOSSIER_SCRIPT}"/installation.sh
else
    log "Opération passé, rien n’a été modifié" "a"
fi

log "Demande de création de la base de donnée (DB)" "d"
if demander "Créer la base de donnée \"bankdb\" ?. Cette opération supprime TOUTE la base bankdb si déjà existante."; then
    sudo "${DOSSIER_SCRIPT}"/recreation_db.sh
else
    log "Opération passé, rien n’a été modifié" "a"
fi

log "Demande de vérification de la DB" "d"
if demander "Faire une vérification de bonne installation de bankdb ?"; then
    sudo -u postgres psql -d bankdb < "${DOSSIER_SQL}"/tests/tests.sql > "${DOSSIER_SQL}"/tests/resultats_tests.txt 2>&1
    OK=$(grep -c 'RESULTAT: OK' "${DOSSIER_SQL}"/tests//resultats_tests.txt)
    log "Nombre de vérifications réussies :" "s"
    echo "${OK}"
    log "Nombre de vérifications échouées :" "e"
    if grep -q 'RESULTAT: KO' "${DOSSIER_SQL}"/tests//resultats_tests.txt; then
      exit 1
    else
      echo "0"
    fi
else
    log "Opération passé, rien n’a été modifié" "a"
fi

log "Demande de sauvegarde de la DB" "d"
if demander "Faire une sauvegarde de \"bankdb\" ?"; then
     sudo "${DOSSIER_SCRIPT}"/sauvegarde.sh
else
    log "Opération passé, rien n’a été modifié" "a"
fi

log "Fin des opérations" "s"
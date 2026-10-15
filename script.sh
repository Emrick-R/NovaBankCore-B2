#!/usr/bin/env bash
# fichier d'installation de postgresql
# Usage : sudo ./script.sh
set -euo pipefail

NORMAL="\033[0m"
CYAN="\033[1;36m"
JAUNE="\033[1;33m"
ROUGE="\033[1;31m"
VERT="\033[1;32m"

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

# Installation des paquets
log "Update des paquets d'APT"
apt-get update
log "Installation de postgresql"
apt-get install -y postgresql
log "Installation de postgresql-client"
apt-get install -y postgresql-client
log "Installation de ufw"
apt-get install -y ufw
log "Installations terminées" "s"

# Création du fichier de conf de postgresql
log "Création du fichier de conf postgresql"
cat > /etc/postgresql/18/main/conf.d/01-novabank.conf << 'EOF'
  # Fichier de configuration POSTGRESQL généré via script.sh
  # on definit les adresses d'écoute (localhost et private host)
  listen_addresses = '127.0.0.1, 192.168.56.10'
  # On impose scram-sha-256 pour chiffrer les mots de passe
  password_encryption = 'scram-sha-256'
  # Les logs lors des connections
  log_connections = 'on'
  # Les logs lors des changements de structure : CREATE, ALTER, DROP
  log_statement = 'ddl'
EOF
log "Création du fichier de conf postgresql terminée" "s"

# On relance le service postgre
log "Relancement du service postgresql"
systemctl restart postgresql
log "Relancement du service postgresql terminé" "s"
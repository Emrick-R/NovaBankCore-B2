#!/usr/bin/env bash
# fichier d'installation et de configuration de postgresql, de ufw
# Envoyer les fichiers du dossier /scripts :
# scp -r scripts  novab-db:~/
# Usage : sudo ./scripts/installation.sh
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
  # Fichier de configuration POSTGRESQL généré via installation.sh
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

# Relancement du service postgre
log "Relancement du service postgresql"
systemctl restart postgresql
log "Relancement du service postgresql terminé" "s"

# Configuration de l'ufw (Uncomplicated Firewall)
log "Configuration de l'ufw (Uncomplicated Firewall)"

# On autorise les connexions de OpenSSH
log "Configuration de l'ufw: SSH"
ufw allow OpenSSH
log "Configuration de l'ufw: SSH, terminée" "s"

# On autorise,
# des connexions venant de n’importe quelle machine du réseau host-only (.1 à .254),
# vers le port 5432 de cette VM (any = sur n’importe laquelle de ses adresses),
# en TCP (le protocole utilisé par PostgreSQL)
log "Configuration de l'ufw: PostgreSQL"
ufw allow from 192.168.56.0/24 to any port 5432 proto tcp
log "Configuration de l'ufw: PostgreSQL, terminée" "s"

# Activation de l'ufw
log "Activation de l'ufw"
ufw --force enable
log "Activation de l'ufw terminée" "s"

log "Configuration de l'ufw terminée" "s"

# Configuration des droit de connexion selon l'utilisateur, son adresse et vers quoi
log "Configuration des droit de connexion selon l'utilisateur, son adresse et vers quoi"

log "Copie du fichier original"
# On créer un copie du fichier original avec verification que cela n'est pas déjà fait (--update=none) et
# avec ses droits initiaux (-p)
cp -p --update=none /etc/postgresql/18/main/pg_hba.conf /etc/postgresql/18/main/pg_hba.conf.orig
log "Copie du fichier original terminé" "s"

# Création du fichier de config
log "Création du fichier de configuration"
cat > /etc/postgresql/18/main/pg_hba.conf << 'EOF'
  # Fichier de configuration des droit de connexion selon l'utilisateur, son adresse et vers quoi. Générer via installation.sh
  local	all	postgres		peer
  host	bankdb	bank_owner,+grp_appli	127.0.0.1/32	scram-sha-256
  host	bankdb	+grp_analyste,+grp_support,+grp_auditeur	192.168.56.0/24	scram-sha-256
	local	all	all 	reject
	host	all	all	all	reject
EOF
log "Création du fichier de configuration terminé" "s"

# Rechargement du service postgresql
log "Rechargement du service postgresql"
systemctl reload postgresql
log "Rechargement du service postgresql terminé" "s"

log "Configuration des droit de connexion selon l'utilisateur, son adresse et vers quoi terminée" "s"

-- Fichier de création des schémas et des types ENUM pour la DB
-- Lancé avec l'user bank_owner :
-- psql -h 127.0.0.1 -U bank_owner -d bankdb < ~/SQL/01_schemas_types.sql
-- Verification : \dT core.*

-- Création des schémas
CREATE SCHEMA core;

CREATE SCHEMA audit;

-- Création des types ENUM
-- Documents envoyés, vérification en cours, identité confirmée, documents refusés
CREATE TYPE core.kyc_status AS ENUM ('PENDING', 'VERIFIED', 'REJECTED');
-- Compte courant (paiements du quotidien), compte épargne
CREATE TYPE core.account_type AS ENUM ('CHECKING', 'SAVINGS');
-- Actif, gelé (bloqué temporairement, par exemple après une fraude), fermé
CREATE TYPE core.acc_status AS ENUM ('ACTIVE', 'FROZEN', 'CLOSED');
-- Dépôt, retrait, sortie de virement, entrée de virement
CREATE TYPE core.tx_type AS ENUM ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER_OUT', 'TRANSFER_IN');
-- Nouvelle, examinée par un analyste, traitée
CREATE TYPE core.alert_status AS ENUM ('OPEN', 'REVIEWED', 'CLOSED');
-- Les deux règles du sujet : retrait de 5 000 ou plus, 5 virements en 10 minutes
CREATE TYPE core.rule_code AS ENUM ('BIG_WITHDRAWAL', 'RAPID_TRANSFERS');
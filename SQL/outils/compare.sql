-- Fichier de vérification entre la db active et la bankdb_restore.
-- Il compte toutes les lignes de chaque table.
-- Utilisé par le script sauvegarde.sh

-- On compte toutes les tables en tant qu'une seule et même table
SELECT 'customers' AS table_name, count(*) FROM core.customers
UNION ALL
SELECT 'accounts' AS table_name, count(*) FROM core.accounts
UNION ALL
SELECT 'transfers' AS table_name, count(*) FROM core.transfers
UNION ALL
SELECT 'transactions' AS table_name, count(*) FROM core.transactions
UNION ALL
SELECT 'fraud_alerts' AS table_name, count(*) FROM core.fraud_alerts
UNION ALL
SELECT 'audit_log' AS table_name, count(*) FROM audit.audit_log
ORDER BY table_name;
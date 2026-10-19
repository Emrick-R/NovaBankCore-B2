-- Fichier de création des procédures de la db
-- Lancé avec l'user bank_owner :
-- psql -h 127.0.0.1 -U bank_owner -d bankdb < ~/SQL/09_procedures.sql

-- arrête le fichier à la première erreur, au lieu d'exécuter la suite sur des données incomplètes
\set ON_ERROR_STOP on

-- Compteur des IBAN des nouveaux comptes (les comptes générés utilisent 1 à 200 000)
CREATE SEQUENCE IF NOT EXISTS core.seq_iban START 200001;

-- Ouverture d'un compte : vérifie le client, crée le compte et enregistre le dépôt initial
-- sp = stored procedure
CREATE OR REPLACE PROCEDURE core.sp_ouvrir_compte(
    p_customer_id  bigint,
    p_type         core.account_type,
    p_depot        numeric(14,2),
    INOUT p_account_id bigint DEFAULT NULL    -- résultat : le numéro du nouveau compte
    )
    LANGUAGE plpgsql
    -- Avec SECURITY DEFINER, elle s’exécute avec les droits de son propriétaire, bank_owner
    SECURITY DEFINER SET search_path = pg_catalog, pg_temp
    AS $$
        DECLARE
            v_kyc core.kyc_status;
        BEGIN
            -- 1. vérifier les entrées
            IF p_depot <= 0 OR p_depot IS NULL THEN
                RAISE EXCEPTION 'Un dépôt doit être supérieur à 0';
            END IF;

            SELECT kyc_status INTO v_kyc
                FROM core.customers
                WHERE customer_id = p_customer_id;

            IF NOT FOUND THEN -- le SELECT n'a trouvé aucune ligne
                RAISE EXCEPTION 'Client % inconnu', p_customer_id;
            END IF;

            IF v_kyc <> 'VERIFIED' THEN
                RAISE EXCEPTION 'Client % : KYC non vérifié (%)', p_customer_id, v_kyc;
            END IF;

            -- 2. créer le compte, et récupérer son numéro
            INSERT INTO core.accounts (
               customer_id,
               iban,
               account_type
                )
                VALUES (
                    p_customer_id,
                    'FR72' || lpad(nextval('core.seq_iban')::text, 23, '0'),
                    p_type
                )
                RETURNING account_id INTO p_account_id;

            -- 3. enregistrer le dépôt initial : le trigger calcule le solde
            INSERT INTO core.transactions (account_id, tx_type, amount)
            VALUES (
                    p_account_id,
                    'DEPOSIT'::core.tx_type,
                    p_depot
                   );
        END;
    $$;

-- l'application peut ouvrir des comptes, uniquement à travers cette procédure
GRANT EXECUTE ON PROCEDURE core.sp_ouvrir_compte(bigint, core.account_type, numeric, bigint) TO grp_appli;

-- Vérifications en tant que postgres :
-- SET ROLE app_novabank;
-- -- cas qui passe : le client 1 a un KYC VERIFIED (vu dans la vue du support)
-- CALL core.sp_ouvrir_compte(1, 'SAVINGS', 500, NULL);
-- -- refusé : le client 2 a un KYC REJECTED
-- CALL core.sp_ouvrir_compte(2, 'SAVINGS', 500, NULL);
-- -- refusé : client inconnu
-- CALL core.sp_ouvrir_compte(999999, 'SAVINGS', 500, NULL);
-- -- refusé : dépôt nul
-- CALL core.sp_ouvrir_compte(1, 'SAVINGS', 0, NULL);
-- -- l'appli ne peut toujours pas lire les tables directement
-- SELECT * FROM core.accounts LIMIT 1;
-- RESET ROLE;

-- Virement sûr : tout ou rien, sans solde négatif ni interblocage
CREATE OR REPLACE PROCEDURE core.sp_virement(
    p_from   bigint,                          -- compte qui envoie
    p_to     bigint,                          -- compte qui reçoit
    p_amount numeric(14,2),
    p_label  text,
    INOUT p_transfer_id bigint DEFAULT NULL   -- résultat : le numéro du virement
)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $$
    DECLARE
        v_status_from core.acc_status;
        v_status_to   core.acc_status;
    BEGIN
        -- 1. vérifier les entrées
        IF p_amount <= 0 OR p_amount IS NULL THEN -- montant vide ou pas strictement positif
            RAISE EXCEPTION 'Le montant doit être supérieur à 0';
        END IF;
        IF p_from = p_to THEN -- même compte des deux côtés
            RAISE EXCEPTION 'Le compte qui reçoit et le compte qui envoie ne peuvent pas être identiques';
        END IF;

        -- 2. verrouiller les deux comptes, toujours dans l'ordre croissant des numéros
        -- Avec PERFORM, on fait comme un SELECT, mais le résultat est jeté dans le vide
        PERFORM 1 FROM core.accounts
            WHERE account_id IN (p_from, p_to)
            ORDER BY account_id
            FOR UPDATE;

        -- 3. vérifier que les deux comptes existent et sont actifs
        -- Compte qui envoie
        SELECT status INTO v_status_from FROM core.accounts WHERE account_id = p_from;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Compte d''envoi % inconnu', p_from;
            END IF;
            IF v_status_from <> 'ACTIVE' THEN
                RAISE EXCEPTION 'Compte d''envoi % non actif (%)', p_from, v_status_from;
            END IF;
        -- Compte qui reçoit
        SELECT status INTO v_status_to FROM core.accounts WHERE account_id = p_to;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Compte de réception % inconnu', p_to;
            END IF;
            IF v_status_to <> 'ACTIVE' THEN
                RAISE EXCEPTION 'Compte de réception % non actif (%)', p_to, v_status_to;
            END IF;

        -- 4. enregistrer la demande de virement, et récupérer son numéro
        INSERT INTO core.transfers (
            from_account_id,
            to_account_id,
            amount,
            label
            )
            VALUES (
                p_from,
                p_to,
                p_amount,
                p_label
            )
            RETURNING transfer_id INTO p_transfer_id;

        -- 5. les deux écritures du grand livre : le trigger vérifie le solde et le met à jour
        -- la sortie, sur le compte qui envoie
        INSERT INTO core.transactions (
           account_id,
           tx_type,
           amount,
           transfer_id
            )
            VALUES (
                p_from,
                'TRANSFER_OUT',
                -p_amount,
                p_transfer_id
            );
        -- l'entrée, sur le compte qui reçoit
        INSERT INTO core.transactions (
            account_id,
            tx_type,
            amount,
            transfer_id
            )
            VALUES (
               p_to,
               'TRANSFER_IN',
               p_amount,
               p_transfer_id
           );
    END;
$$;


-- l'application peut créer des transferts, uniquement à travers cette procédure
GRANT EXECUTE ON PROCEDURE core.sp_virement(bigint, bigint, numeric, text, bigint) TO grp_appli;

-- Vérification en tant que postgres :
-- D'abord :
-- SELECT account_id FROM core.accounts WHERE status = 'FROZEN' LIMIT 1;
-- Puis avec le résultat précedent:
-- SET ROLE app_novabank;
-- -- 1. cas qui passe : renvoie le numéro du virement
-- CALL core.sp_virement(42, 43, 50, 'Test de virement', NULL);
-- -- 2. refusé par le TRIGGER : solde insuffisant
-- CALL core.sp_virement(42, 43, 999999, 'Trop gros', NULL);
-- -- 3. refusé : même compte
-- CALL core.sp_virement(42, 42, 50, 'Moi-même', NULL);
-- -- 4. refusé : compte gelé (mets le numéro trouvé)
-- CALL core.sp_virement(<compte gelé>, 43, 50, 'Gelé', NULL);
-- RESET ROLE;
--
-- -- 5. la preuve du « tout ou rien » : le virement refusé n'a laissé AUCUNE trace
-- SELECT count(*) FROM core.transfers WHERE label = 'Trop gros';    -- doit valoir 0

-- Relevé d'un compte sur une période : une fonction, car elle renvoie des lignes
CREATE OR REPLACE FUNCTION core.fn_releve(
        p_account_id bigint,
        p_debut      date,
        p_fin        date
    )
    -- les colonnes renvoyées
    RETURNS TABLE (
        date_ecriture timestamptz,
        type_ecriture core.tx_type,
        montant       numeric(14,2),
        solde_apres   numeric(14,2),
        libelle       text
    )
    LANGUAGE plpgsql
    SECURITY DEFINER SET search_path = pg_catalog, pg_temp
    AS $$
        BEGIN
            -- 1. vérifier les entrées
            -- dates vides ou dans le désordre
            IF p_debut IS NULL OR p_fin IS NULL OR p_debut > p_fin THEN
                RAISE EXCEPTION 'Période invalide : du % au %', p_debut, p_fin;
            END IF;
            PERFORM 1 FROM core.accounts WHERE account_id = p_account_id;
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'Compte % inconnu', p_account_id;
                END IF;

            -- 2. renvoyer les écritures de la période, dans l'ordre
            RETURN QUERY
            SELECT t.created_at, t.tx_type, t.amount, t.balance_after, tr.label
                FROM core.transactions AS t
                     LEFT JOIN core.transfers AS tr ON tr.transfer_id = t.transfer_id
                WHERE t.account_id = p_account_id
                  AND t.created_at >= p_debut
                  AND t.created_at < p_fin + 1        -- la date de fin est incluse en entier
                ORDER BY t.created_at, t.tx_id;
        END;
    $$;

-- l'application peut créer des relevés, uniquement à travers cette procédure
GRANT EXECUTE ON FUNCTION core.fn_releve(bigint, date, date) TO grp_appli;

-- Vérification en tant que postgres:
-- SET ROLE app_novabank;
-- -- cas qui passe : le relevé du compte 42 sur deux ans
-- SELECT * FROM core.fn_releve(42, '2024-01-01', '2026-12-31');
-- -- refusé : dates dans le désordre
-- SELECT * FROM core.fn_releve(42, '2026-12-31', '2026-01-01');
-- -- refusé : compte inconnu
-- SELECT * FROM core.fn_releve(999999, '2026-01-01', '2026-12-31');
-- RESET ROLE;
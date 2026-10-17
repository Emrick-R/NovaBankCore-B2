-- Fichier de génération des données de la base pour la DB
-- Lancé avec l'user bank_owner :
-- psql -h 127.0.0.1 -U bank_owner -d bankdb < ~/SQL/03_donnees.sql

-- On met à vide toutes les tables remplies par ce fichier, et remet leurs compteurs à 1
TRUNCATE core.customers, core.accounts, core.transfers, core.transactions, core.fraud_alerts RESTART IDENTITY;

-- On utilise une seed pour avoir la même chose à chaque lancement du fichier
SELECT setseed(0.3);

-- Les clients : core.customers, 100k clients
-- Verification : ```SELECT count(*) FROM core.customers;```
INSERT INTO core.customers (
    first_name,--  text            NOT NULL,
    last_name,--   text            NOT NULL,
    email,--       text            NOT NULL UNIQUE,
    phone,--       text            NOT NULL,
    birth_date,--  date            NOT NULL,
    kyc_status,--  core.kyc_status NOT NULL DEFAULT 'PENDING',
    risk_level,--  smallint        NOT NULL,
    created_at--  TIMESTAMPTZ     NOT NULL DEFAULT now(),
)
SELECT
    -- 20 prénoms, au hasard parmi 20 (random(1,20), car les cases commencent à 1)
    (ARRAY['Emma', 'Lucas', 'Léa', 'Hugo', 'Chloé', 'Louis', 'Manon', 'Gabriel',
     'Camille', 'Arthur', 'Inès', 'Jules', 'Sarah', 'Nathan', 'Jade', 'Adam',
     'Louise', 'Raphaël', 'Alice', 'Mohamed'])[random(1,20)],
    -- 20 noms, au hasard parmi 20
    (ARRAY['Martin', 'Bernard', 'Dubois', 'Thomas', 'Robert', 'Richard', 'Petit',
    'Durand', 'Leroy', 'Moreau', 'Simon', 'Laurent', 'Lefebvre', 'Michel',
    'Garcia', 'David', 'Bertrand', 'Roux', 'Nguyen', 'Fontaine'])[random(1,20)],
    -- email unique, construit à partir du numéro de ligne g : client42@novabank.bk
    'client' || g || '@novabank.bk',
    -- téléphone : 06 si g pair, 07 sinon, suivi de g sur 8 chiffres (lpad complète avec des 0 à gauche)
    CASE WHEN g % 2 = 0 THEN '06' ELSE '07' END || lpad(g::text, 8, '0'),
    -- date de naissance au hasard entre 19 et 60 ans (date - entier = date, en jours)
    current_date - random(19 * 365, 60 * 365),
    -- statut KYC au hasard, converti du texte vers le type ENUM core.kyc_status
    (ARRAY['PENDING', 'VERIFIED', 'REJECTED'])[random(1, 3)]::core.kyc_status,
    -- niveau de risque au hasard entre 1 et 5 (respecte ck_customers_risk_level)
    random(1, 5),
    -- inscription au hasard entre il y a 3 ans et il y a 2 ans
    now() - interval '2 years' - random() * interval '1 year'
FROM generate_series(1, 100000) AS g;

-- Les comptes : core.accounts, 200k comptes dont 2 comptes par clients
-- Verification : ```SELECT status, count(*) FROM core.accounts GROUP BY status;```
INSERT INTO core.accounts (
    customer_id,--  bigint            NOT NULL REFERENCES core.customers (customer_id),
    iban,--         text              NOT NULL UNIQUE,
    account_type,-- core.account_type NOT NULL DEFAULT 'CHECKING',
    status,--       core.acc_status   NOT NULL DEFAULT 'ACTIVE',
    opened_at--    TIMESTAMPTZ       NOT NULL DEFAULT now(),
)
SELECT
    c.customer_id,
    -- IBAN fictif unique : FR + 2 chiffres de clé + g sur 23 chiffres (27 caractères au total)
    'FR72' || lpad(g::text, 23, '0'),
    -- 1 compte sur deux est un compte CHECKING
    (ARRAY['CHECKING', 'SAVINGS'])[random(1, 2)]::core.account_type,
    -- 2% des comptes sont FROZEN, le reste ACTIVE, les comptes fermés seront inscrit via un update ultérieur
    CASE WHEN random() < 0.02 THEN 'FROZEN'::core.acc_status ELSE 'ACTIVE'::core.acc_status END,
    -- On prend la date d'inscription, et on lui ajoute entre 1 et 7 jours pour la creation du compte
    c.created_at + random(1, 7) * interval '1 day'
FROM generate_series(1, 200000) AS g
    -- relie chaque compte g à son client : 2 comptes par client (voir la répartition par modulo)
    JOIN core.customers AS c ON c.customer_id = 1 + (g % 100000);

-- Les virements : core.transfers 300k virements entre deux comptes DIFFÉRENTS, tirés au hasard
-- Verification :
-- ```SELECT count(*) FROM core.transfers;``` <- doit donner 300 000
-- ```SELECT min(created_at), max(created_at) FROM core.transfers;``` <- entre il y a 1 an et aujourd'hui
INSERT INTO core.transfers (
    from_account_id,-- bigint         NOT NULL REFERENCES core.accounts (account_id),
    to_account_id,--   bigint         NOT NULL REFERENCES core.accounts (account_id),
    amount,--          numeric(14, 2) NOT NULL,
    label,--           text,
    created_at--      TIMESTAMPTZ    NOT NULL DEFAULT now()
)
SELECT
    -- compte qui envoie : celui tiré dans la sous-requête
    t.src,
    -- compte qui reçoit : on part de src et on avance de dec cases,
    -- en faisant le tour comme une horloge (après 200 000, on revient à 1).
    -- Comme dec n'est jamais 0 ni un tour complet, on ne retombe jamais sur src.
    --   -1 : passe de la numérotation 1..200000 à 0..199999 (le modulo commence à 0)
    --   % 200000 : fait le tour
    --   1 + : revient à la numérotation 1..200000
    1 + (t.src - 1 + t.dec) % 200000,
    -- On génère un nombre avec des centimes
    random(10.00, 300.00),
    -- 15 libellés de virement au hasard
    (ARRAY['Loyer', 'Remboursement', 'Courses', 'Cadeau', 'Restaurant',
      'Vacances', 'Facture électricité', 'Abonnement', 'Participation',
      'Anniversaire', 'Colocation', 'Prêt', 'Épargne', 'Frais de transport',
      'Virement personnel'])[random(1, 15)],
    -- date du virement : maintenant, moins une fraction d'année au hasard
    -- (random() donne 0.xxx entre 0 et 1 → entre 0 et 1 an, avec heures et minutes)
    now() - random() * interval '1 year'
FROM (
    -- sous-requête : on fait les tirages UNE SEULE FOIS par virement,
    -- pour pouvoir réutiliser src deux fois ci-dessus sans le retirer au hasard
    SELECT g,
    random(1, 200000) AS src,  -- le compte qui envoie
    random(1, 199999) AS dec   -- le décalage : de 1 à 199 999, jamais 0
    FROM generate_series(1, 300000) AS g
    ) AS t;
-- Fichier de création des tables de la base pour la DB
-- Lancé avec l'user bank_owner :
-- psql -h 127.0.0.1 -U bank_owner -d bankdb < ~/SQL/02_tables.sql
-- Verification : ```\dT core.*``` ```\dt audit.*```

-- Création des tables
-- Table customers
CREATE TABLE core.customers
(
    customer_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name  text            NOT NULL,
    last_name   text            NOT NULL,
    email       text            NOT NULL UNIQUE,
    phone       text            NOT NULL,
    birth_date  date            NOT NULL,
    kyc_status  core.kyc_status NOT NULL DEFAULT 'PENDING',
    risk_level  smallint        NOT NULL,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT now(),
    CONSTRAINT ck_customers_email CHECK (email LIKE '%@%.%'),
    CONSTRAINT ck_customers_majeur CHECK (AGE(birth_date) >= interval '18 years'),
    CONSTRAINT ck_customers_risk_level CHECK (risk_level BETWEEN 1 AND 5)
    );

-- Table accounts
CREATE TABLE core.accounts
(
    account_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  bigint            NOT NULL REFERENCES core.customers (customer_id),
    iban         text              NOT NULL UNIQUE,
    account_type core.account_type NOT NULL DEFAULT 'CHECKING',
    balance      numeric(14, 2)    NOT NULL DEFAULT 0,
    status       core.acc_status   NOT NULL DEFAULT 'ACTIVE',
    opened_at    TIMESTAMPTZ       NOT NULL DEFAULT now(),
    CONSTRAINT ck_accounts_balance CHECK (balance >= 0)
);

-- Table transferts
CREATE TABLE core.transfers
(
    transfer_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_account_id bigint         NOT NULL REFERENCES core.accounts (account_id),
    to_account_id   bigint         NOT NULL REFERENCES core.accounts (account_id),
    amount          numeric(14, 2) NOT NULL,
    label           text,
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT ck_transfers_comptes_differents CHECK (from_account_id <> to_account_id),
    CONSTRAINT ck_transfers_amount CHECK (amount > 0)
);

-- Table transactions
CREATE TABLE core.transactions
(
    tx_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id    bigint         NOT NULL REFERENCES core.accounts (account_id),
    tx_type       core.tx_type   NOT NULL,
    amount        numeric(14, 2) NOT NULL,
    balance_after numeric(14, 2) NOT NULL,
    transfer_id   bigint REFERENCES core.transfers (transfer_id),
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT ck_transactions_signe CHECK (
        (tx_type IN ('DEPOSIT', 'TRANSFER_IN') AND amount > 0)
            OR (tx_type IN ('WITHDRAWAL', 'TRANSFER_OUT') AND amount < 0)),
    CONSTRAINT ck_transactions_balance_after CHECK (balance_after >= 0)
);

-- Table alerts
CREATE TABLE core.fraud_alerts
(
    alert_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id bigint            NOT NULL REFERENCES core.accounts (account_id),
    tx_id      bigint            NOT NULL REFERENCES core.transactions (tx_id),
    rule_code  core.rule_code    NOT NULL,
    status     core.alert_status NOT NULL DEFAULT 'OPEN',
    created_at TIMESTAMPTZ       NOT NULL DEFAULT now()
);

-- Table audit log
CREATE TABLE audit.audit_log
(
    log_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name text        NOT NULL,
    operation  text        NOT NULL,
    old_data   jsonb,
    new_data   jsonb,
    db_user    text        NOT NULL DEFAULT current_user,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_audit_log_operation CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE') )
);
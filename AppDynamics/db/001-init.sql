CREATE TABLE customers (
    id integer PRIMARY KEY,
    name text NOT NULL,
    credit_score integer NOT NULL CHECK (credit_score BETWEEN 300 AND 850)
);
INSERT INTO customers(id, name, credit_score)
SELECT i, 'Synthetic Customer ' || lpad(i::text, 3, '0'), 580 + (i * 17 % 241)
FROM generate_series(1, 100) AS i;

CREATE TABLE loans (
    request_id uuid PRIMARY KEY,
    customer_id integer NOT NULL REFERENCES customers(id),
    amount numeric(12, 2) NOT NULL CHECK (amount BETWEEN 100 AND 100000),
    term_months integer NOT NULL CHECK (term_months BETWEEN 12 AND 84),
    status text NOT NULL CHECK (status IN ('APPROVED', 'DECLINED')),
    credit_score integer NOT NULL,
    reason text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX loans_created_at ON loans(created_at DESC);

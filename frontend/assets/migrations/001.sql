CREATE TABLE accounts (
  id              TEXT PRIMARY KEY,
  user_id         TEXT NOT NULL,
  name            TEXT NOT NULL,
  type            TEXT NOT NULL,
  initial_balance INTEGER NOT NULL DEFAULT 0,
  currency_code   TEXT NOT NULL DEFAULT 'MXN',
  created_at      TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  deleted_at      TEXT
);

CREATE TABLE categories (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  name       TEXT NOT NULL,
  type       TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE transactions (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL,
  account_id    TEXT NOT NULL,
  category_id   TEXT NOT NULL,
  amount        INTEGER NOT NULL,
  currency_code TEXT NOT NULL DEFAULT 'MXN',
  description   TEXT NOT NULL DEFAULT '',
  date          TEXT NOT NULL,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);

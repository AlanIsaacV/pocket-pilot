-- Adds 'investment' to nature_type so transactions derived from investment_lots
-- can be persisted (the frontend generator sets nature='investment' for buy/sell).

ALTER TYPE nature_type ADD VALUE IF NOT EXISTS 'investment';

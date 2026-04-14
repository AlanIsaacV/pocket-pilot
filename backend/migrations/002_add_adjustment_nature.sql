-- Add 'adjustment' to the nature_type enum for balance adjustment transactions.
ALTER TYPE nature_type ADD VALUE IF NOT EXISTS 'adjustment';

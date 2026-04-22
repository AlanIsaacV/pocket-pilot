/// App-wide UUID namespace used for deterministic template occurrence IDs.
const kDeterministicTemplateNamespace = 'f3b6f4d2-5c8b-4f87-9f03-2ec2f7d32651';

/// App-wide UUID namespace used for deterministic yield occurrence IDs.
const kDeterministicYieldNamespace = '9b7dc9b8-9e4f-4e0b-a178-6f6b1b39b4f1';

/// App-wide UUID namespace used for deterministic default category IDs.
/// Combined with the user ID in the name: v5(namespace, "$userId/$canonicalId").
const kDeterministicCategoryDefaultsNamespace =
    'a2f1c3e5-7b4d-4a6f-8e2c-1d9f5b3a7e0c';

/// App-wide UUID namespace used for deterministic investment lot transaction IDs.
/// Combined with the lot ID in the name: v5(namespace, "lot:$lotId").
const kDeterministicInvestmentNamespace =
    '5e7b2f8c-3a4d-4e9b-8c1f-6a2d7e3b4c8f';

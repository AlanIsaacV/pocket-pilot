package sync

// EntityType is the canonical identifier shared by backend cursor storage
// and the frontend sync handler's entityType string. Keep the values in
// sync with the frontend SyncHandler.entityType getters.
type EntityType string

const (
	EntityAccount             EntityType = "account"
	EntityTransaction         EntityType = "transaction"
	EntityCategory            EntityType = "category"
	EntityGoal                EntityType = "goal"
	EntityTag                 EntityType = "tag"
	EntityBudget              EntityType = "budget"
	EntityTransactionTemplate EntityType = "transaction_template"
	EntityUserPreference      EntityType = "user_preference"
	EntityYieldConfig         EntityType = "yield_config"
	EntityInvestmentHolding   EntityType = "investment_holding"
	EntityInvestmentLot       EntityType = "investment_lot"
	EntityInvestmentSplit     EntityType = "investment_split"
	EntityMarketPrice         EntityType = "market_price"
)

// AllEntityTypes returns every entity type a client may ask about.
// GetSyncStatus uses this to fill missing cursors with the epoch.
// Adding a new sync-participating entity REQUIRES appending it here.
func AllEntityTypes() []EntityType {
	return []EntityType{
		EntityAccount,
		EntityTransaction,
		EntityCategory,
		EntityGoal,
		EntityTag,
		EntityBudget,
		EntityTransactionTemplate,
		EntityUserPreference,
		EntityYieldConfig,
		EntityInvestmentHolding,
		EntityInvestmentLot,
		EntityInvestmentSplit,
		EntityMarketPrice,
	}
}

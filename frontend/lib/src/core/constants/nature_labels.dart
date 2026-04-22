/// Returns the user-facing display label for a financial nature string.
String natureDisplayLabel(String nature) {
  return switch (nature) {
    'required' => 'Necesario',
    'obligation' => 'Obligacion',
    'lifestyle' => 'Estilo de vida',
    'active' => 'Activo',
    'passive' => 'Pasivo',
    'windfall' => 'Extraordinario',
    'adjustment' => 'Ajuste',
    'investment' => 'Inversion',
    _ => 'Sin definir',
  };
}

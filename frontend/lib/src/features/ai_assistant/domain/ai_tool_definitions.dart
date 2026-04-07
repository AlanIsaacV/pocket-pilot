import 'dart:convert';

import 'package:pocket_pilot/src/generated/pocket_pilot/v1/ai_assistant_service.pb.dart';

List<AIToolDefinition> get aiToolDefinitions => [
  _gestionarTransaccion,
  _editarTransaccion,
  _ejecutarPlantilla,
  _consultarResumenFinanciero,
  _gestionarMeta,
  _reportarFuncionNoSoportada,
];

final _gestionarTransaccion = AIToolDefinition(
  name: 'gestionar_transaccion',
  description:
      'Crea una nueva transaccion financiera (ingreso, gasto o transferencia entre cuentas).',
  parametersSchema: jsonEncode({
    'type': 'object',
    'properties': {
      'type': {
        'type': 'string',
        'enum': ['income', 'expense', 'transfer_out'],
      },
      'account_id': {
        'type': 'string',
        'description':
            'UUID exacto de la cuenta origen (del listado de cuentas del usuario)',
      },
      'to_account_id': {
        'type': 'string',
        'description': 'ID de la cuenta destino (solo para transferencias)',
      },
      'amount_cents': {
        'type': 'integer',
        'description':
            'Monto en centavos (debe ser mayor a 0, ej: 10000 para \$100)',
      },
      'currency_code': {
        'type': 'string',
        'description': 'Codigo de moneda (ej: MXN)',
      },
      'category_id': {
        'type': 'string',
        'description': 'ID de la categoria (no aplica para transferencias)',
      },
      'description': {'type': 'string'},
      'date': {
        'type': 'string',
        'format': 'date',
        'description': 'Fecha en formato YYYY-MM-DD',
      },
    },
    'required': ['type', 'account_id', 'amount_cents', 'currency_code', 'date'],
  }),
);

final _editarTransaccion = AIToolDefinition(
  name: 'editar_transaccion',
  description:
      'Edita una transaccion existente. Solo envia los campos que cambian, los demas se mantienen.',
  parametersSchema: jsonEncode({
    'type': 'object',
    'properties': {
      'transaction_id': {
        'type': 'string',
        'description': 'UUID de la transaccion a editar (obtenido al crearla)',
      },
      'account_id': {
        'type': 'string',
        'description':
            'UUID exacto de la nueva cuenta (del listado de cuentas del usuario)',
      },
      'amount_cents': {
        'type': 'integer',
        'description': 'Nuevo monto en centavos (debe ser mayor a 0)',
      },
      'currency_code': {
        'type': 'string',
        'description': 'Nuevo codigo de moneda',
      },
      'category_id': {
        'type': 'string',
        'description': 'UUID de la nueva categoria',
      },
      'description': {'type': 'string', 'description': 'Nueva descripcion'},
      'date': {
        'type': 'string',
        'format': 'date',
        'description': 'Nueva fecha en formato YYYY-MM-DD',
      },
      'type': {
        'type': 'string',
        'enum': ['income', 'expense'],
        'description': 'Nuevo tipo de transaccion',
      },
      'tags': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Lista de nombres de etiquetas',
      },
    },
    'required': ['transaction_id'],
  }),
);

final _ejecutarPlantilla = AIToolDefinition(
  name: 'ejecutar_plantilla',
  description:
      'Busca una plantilla de transaccion por nombre y crea la transaccion con los valores predefinidos.',
  parametersSchema: jsonEncode({
    'type': 'object',
    'properties': {
      'template_name': {
        'type': 'string',
        'description': 'Nombre de la plantilla a ejecutar',
      },
    },
    'required': ['template_name'],
  }),
);

final _consultarResumenFinanciero = AIToolDefinition(
  name: 'consultar_resumen_financiero',
  description:
      'Consulta datos financieros del usuario: saldos, gastos, ingresos, metricas del dashboard.',
  parametersSchema: jsonEncode({
    'type': 'object',
    'properties': {
      'query_type': {
        'type': 'string',
        'enum': [
          'account_balance',
          'monthly_expenses',
          'monthly_income',
          'category_expenses',
          'buying_power',
          'liquidity',
        ],
        'description': 'Tipo de consulta financiera',
      },
      'account_id': {
        'type': 'string',
        'description': 'ID de cuenta (opcional, para filtrar)',
      },
      'category_id': {
        'type': 'string',
        'description': 'ID de categoria (opcional, para filtrar)',
      },
      'period': {
        'type': 'string',
        'pattern': r'^\d{4}-\d{2}$',
        'description': 'Mes en formato YYYY-MM (default: mes actual)',
      },
    },
    'required': ['query_type'],
  }),
);

final _gestionarMeta = AIToolDefinition(
  name: 'gestionar_meta',
  description:
      'Consulta el estado de una meta de ahorro: progreso, monto faltante, fecha limite. Debes proporcionar goal_id o goal_name.',
  parametersSchema: jsonEncode({
    'type': 'object',
    'properties': {
      'goal_id': {'type': 'string', 'description': 'ID de la meta'},
      'goal_name': {
        'type': 'string',
        'description': 'Nombre de la meta (alternativa al ID)',
      },
    },
  }),
);

final _reportarFuncionNoSoportada = AIToolDefinition(
  name: 'reportar_funcion_no_soportada',
  description:
      'Usa esta herramienta cuando el usuario pida algo que no puedes hacer con las herramientas disponibles. Registra la intencion para analisis futuro.',
  parametersSchema: jsonEncode({
    'type': 'object',
    'properties': {
      'user_intent': {
        'type': 'string',
        'description': 'Descripcion de lo que el usuario intento hacer',
      },
      'reason': {
        'type': 'string',
        'description': 'Por que no se puede cumplir la solicitud',
      },
    },
    'required': ['user_intent', 'reason'],
  }),
);

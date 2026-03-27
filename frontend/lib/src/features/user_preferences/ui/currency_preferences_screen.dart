import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:pocket_pilot/src/core/theme/app_theme.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences.dart';
import 'package:pocket_pilot/src/features/user_preferences/domain/currency_preferences_constants.dart';
import 'package:pocket_pilot/src/features/user_preferences/ui/user_preferences_view_model.dart';
import 'package:pocket_pilot/src/ui/widgets/pp_screen_state.dart';

class CurrencyPreferencesScreen extends StatefulWidget {
  const CurrencyPreferencesScreen({super.key});

  @override
  State<CurrencyPreferencesScreen> createState() =>
      _CurrencyPreferencesScreenState();
}

class _CurrencyPreferencesScreenState extends State<CurrencyPreferencesScreen> {
  final TextEditingController _customCodeController = TextEditingController();

  List<String> _allowedDraft = List<String>.from(kInitialAllowedCurrencies);
  String _defaultDraft = kInitialDefaultCurrency;
  bool _didInitDraft = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _customCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserPreferencesViewModel>(
      builder: (context, vm, _) {
        _syncDraftFromVm(vm);

        return Scaffold(
          appBar: AppBar(title: const Text('Monedas')),
          body: Column(
            children: [
              if (vm.isSyncing && !vm.isLoading)
                LinearProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh,
                  minHeight: 2,
                ),
              Expanded(
                child: PpScreenState(
                  isLoading: vm.isLoading,
                  errorMessage: vm.errorMessage,
                  isEmpty: false,
                  emptyIcon: Icons.currency_exchange_rounded,
                  emptyLabel: 'Monedas',
                  onRefresh: vm.refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    children: [
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'Monedas sugeridas',
                        child: Column(
                          children: kSuggestedCurrencies.map((currency) {
                            final selected = _allowedDraft.contains(
                              currency.code,
                            );
                            return CheckboxListTile(
                              value: selected,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              title: Text(
                                '${currency.code} - ${currency.name}',
                                style: GoogleFonts.ibmPlexSans(fontSize: 14),
                              ),
                              onChanged: (checked) {
                                _toggleAllowed(currency.code, checked == true);
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'Agregar moneda personalizada',
                        subtitle: 'Formato: A-Z y 0-9, de 2 a 10 caracteres.',
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _customCodeController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: const InputDecoration(
                                  hintText: 'Ej. BTC, USDT, WBTC',
                                ),
                                onSubmitted: (_) => _addCustomCode(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _addCustomCode,
                              child: const Text('Agregar'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SectionCard(
                        title: 'Monedas permitidas',
                        subtitle:
                            'Estas monedas apareceran en el formulario de transacciones.',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _allowedDraft.map((code) {
                            final isDefault = code == _defaultDraft;
                            return InputChip(
                              label: Text(
                                isDefault ? '$code (default)' : code,
                                style: GoogleFonts.ibmPlexSans(
                                  fontWeight: isDefault
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                              selected: isDefault,
                              onSelected: (_) {
                                setState(() => _defaultDraft = code);
                              },
                              onDeleted: _allowedDraft.length > 1
                                  ? () => _removeCode(code)
                                  : null,
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : () => _save(vm),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar preferencias'),
              ),
            ),
          ),
        );
      },
    );
  }

  void _syncDraftFromVm(UserPreferencesViewModel vm) {
    if (_didInitDraft || vm.allowedCurrencies.isEmpty) return;
    _allowedDraft = List<String>.from(vm.allowedCurrencies);
    _defaultDraft = vm.defaultCurrency;
    _didInitDraft = true;
  }

  void _toggleAllowed(String code, bool shouldEnable) {
    setState(() {
      if (shouldEnable) {
        if (!_allowedDraft.contains(code)) {
          _allowedDraft.add(code);
        }
      } else {
        if (_allowedDraft.length == 1) {
          _showSnack('Debes mantener al menos una moneda permitida.');
          return;
        }
        _allowedDraft.remove(code);
        if (_defaultDraft == code) {
          _defaultDraft = _allowedDraft.first;
        }
      }
      _allowedDraft.sort(compareCurrencyCodes);
    });
  }

  void _removeCode(String code) {
    setState(() {
      if (_allowedDraft.length == 1) {
        _showSnack('Debes mantener al menos una moneda permitida.');
        return;
      }
      _allowedDraft.remove(code);
      if (_defaultDraft == code) {
        _defaultDraft = _allowedDraft.first;
      }
      _allowedDraft.sort(compareCurrencyCodes);
    });
  }

  void _addCustomCode() {
    final raw = _customCodeController.text;
    final code = normalizeCurrencyCode(raw);
    if (!isValidCurrencyCode(code)) {
      _showSnack('Codigo invalido. Usa A-Z y 0-9, de 2 a 10 caracteres.');
      return;
    }
    setState(() {
      if (!_allowedDraft.contains(code)) {
        _allowedDraft.add(code);
        _allowedDraft.sort(compareCurrencyCodes);
      }
      _customCodeController.clear();
    });
  }

  Future<void> _save(UserPreferencesViewModel vm) async {
    setState(() => _isSaving = true);
    try {
      await vm.saveCurrencies(
        allowed: _allowedDraft,
        defaultCode: _defaultDraft,
      );
      if (!mounted) return;
      _showSnack('Preferencias de moneda guardadas.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({required this.title, required this.child, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

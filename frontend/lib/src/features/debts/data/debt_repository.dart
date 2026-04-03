// ============================================================
// DebtRepository — orquestación de préstamos y deudas informales
// ============================================================
//
// Capa de servicio que delega a TransactionRepository y AccountRepository
// para los 4 escenarios de deudas, y a DebtLocalStore para consultas
// de saldos por contacto.

import 'package:pocket_pilot/src/features/accounts/data/account_repository.dart';
import 'package:pocket_pilot/src/features/debts/data/debt_local_store.dart';
import 'package:pocket_pilot/src/features/debts/domain/contact_balance.dart';
import 'package:pocket_pilot/src/features/transactions/data/transaction_repository.dart';
import 'package:pocket_pilot/src/features/transactions/domain/transaction.dart';

class DebtRepository {
  final TransactionRepository _txnRepo;
  final AccountRepository _accountRepo;
  final DebtLocalStore _debtLocal;

  DebtRepository({
    required TransactionRepository transactionRepo,
    required AccountRepository accountRepo,
    required DebtLocalStore debtLocal,
  }) : _txnRepo = transactionRepo,
       _accountRepo = accountRepo,
       _debtLocal = debtLocal;

  // ----------------------------------------------------------
  // READ
  // ----------------------------------------------------------

  Future<List<ContactBalance>> getContactsBalances() =>
      _debtLocal.getContactsBalances();

  Future<ContactBalance?> getContactBalanceByAccountId(String accountId) =>
      _debtLocal.getContactBalanceByAccountId(accountId);

  // ----------------------------------------------------------
  // Escenario 1: "Le presté dinero a alguien"
  // TRANSFER_OUT de mi cuenta real → TRANSFER_IN a cuenta del contacto.
  // Efecto: mi saldo baja, el saldo del contacto sube (me debe).
  // ----------------------------------------------------------

  Future<void> recordLoan({
    required String outId,
    required String inId,
    required String myAccountId,
    required String contactAccountId,
    required int amountCents,
    required String currencyCode,
    required String date,
    required String description,
    required List<String> tags,
  }) => _txnRepo.createTransfer(
    outId: outId,
    inId: inId,
    fromAccountId: myAccountId,
    toAccountId: contactAccountId,
    amountOutCents: amountCents,
    currencyOut: currencyCode,
    amountInCents: amountCents,
    currencyIn: currencyCode,
    date: date,
    descriptionOut: description,
    descriptionIn: description,
    tags: tags,
  );

  // ----------------------------------------------------------
  // Escenario 2: "Me pagaron lo que me debían"
  // TRANSFER_OUT de cuenta del contacto → TRANSFER_IN a mi cuenta real.
  // Efecto: saldo del contacto baja (hacia 0), mi saldo sube.
  // ----------------------------------------------------------

  Future<void> recordPaymentReceived({
    required String outId,
    required String inId,
    required String contactAccountId,
    required String myAccountId,
    required int amountCents,
    required String currencyCode,
    required String date,
    required String description,
    required List<String> tags,
  }) => _txnRepo.createTransfer(
    outId: outId,
    inId: inId,
    fromAccountId: contactAccountId,
    toAccountId: myAccountId,
    amountOutCents: amountCents,
    currencyOut: currencyCode,
    amountInCents: amountCents,
    currencyIn: currencyCode,
    date: date,
    descriptionOut: description,
    descriptionIn: description,
    tags: tags,
  );

  // ----------------------------------------------------------
  // Escenario 3: "Alguien pagó por mí" (asumo una deuda)
  // EXPENSE en la cuenta del contacto, con categoría del gasto.
  // Efecto: saldo del contacto se vuelve negativo (yo le debo).
  //         Mi liquidez real no se afecta, pero el presupuesto sí.
  // ----------------------------------------------------------

  Future<void> recordDebtExpense({
    required String id,
    required String contactAccountId,
    required String categoryId,
    required int amountCents,
    required String currencyCode,
    required String date,
    required String description,
    required List<String> tags,
  }) => _txnRepo.createTransaction(
    id: id,
    accountId: contactAccountId,
    categoryId: categoryId,
    amountMinor: amountCents,
    currencyCode: currencyCode,
    description: description,
    date: date,
    type: 'expense',
    status: 'cleared',
    tags: tags,
  );

  // ----------------------------------------------------------
  // Escenario 4: "Le pago lo que le debía"
  // TRANSFER_OUT de mi cuenta real → TRANSFER_IN a cuenta del contacto.
  // Efecto: mi saldo baja, saldo del contacto sube (hacia 0 desde negativo).
  // ----------------------------------------------------------

  Future<void> recordPaymentMade({
    required String outId,
    required String inId,
    required String myAccountId,
    required String contactAccountId,
    required int amountCents,
    required String currencyCode,
    required String date,
    required String description,
    required List<String> tags,
  }) => _txnRepo.createTransfer(
    outId: outId,
    inId: inId,
    fromAccountId: myAccountId,
    toAccountId: contactAccountId,
    amountOutCents: amountCents,
    currencyOut: currencyCode,
    amountInCents: amountCents,
    currencyIn: currencyCode,
    date: date,
    descriptionOut: description,
    descriptionIn: description,
    tags: tags,
  );

  // ----------------------------------------------------------
  // Gestión de contactos
  // ----------------------------------------------------------

  Future<void> createContact({
    required String id,
    required String name,
    required String currencyCode,
  }) => _accountRepo.createAccount(
    id: id,
    name: name,
    type: 'contact',
    currencyCode: currencyCode,
  );

  Future<List<TransactionModel>> getContactTransactions(String accountId) =>
      _debtLocal.getContactTransactions(accountId);

  Future<List<Map<String, dynamic>>> searchContacts(String query) =>
      _debtLocal.searchContacts(query);

  Future<void> forgiveDebt(String accountId) =>
      _accountRepo.deleteAccount(accountId);
}

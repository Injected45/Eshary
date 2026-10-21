import '../../clients/domain/client.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../transfers/domain/transfer.dart';

/// What a party report is searched by.
enum PartyField {
  company('الشركة'),
  name('الاسم'),
  code('الكود');

  const PartyField(this.label);
  final String label;
}

/// The three things an operation says about the other side, whichever way it
/// went: an exit names the beneficiary, an entry names the sender (the saved
/// party, or the account typed when there is none).
typedef PartyFacts = ({String company, String name, String code});

PartyFacts factsOfTransfer(Transfer t) => (
      company: (t.beneficiaryAccountCompany ?? '').trim(),
      name: t.beneficiaryName.trim(),
      code: (t.beneficiaryCode ?? '').trim(),
    );

PartyFacts factsOfBuy(CurrencyBuy b, Map<String, Client> clientById) {
  final client = b.clientId == null ? null : clientById[b.clientId!];
  return (
    company: (client?.company ?? '').trim(),
    name: (client?.name ?? b.clientFromAccount ?? '').trim(),
    code: (client?.code ?? '').trim(),
  );
}

String _of(PartyFacts f, PartyField field) {
  switch (field) {
    case PartyField.company:
      return f.company;
    case PartyField.name:
      return f.name;
    case PartyField.code:
      return f.code;
  }
}

/// The distinct values of [field] among the operations, for the picker.
List<String> partyValues(
  PartyField field, {
  required Iterable<CurrencyBuy> buys,
  required Iterable<Transfer> transfers,
  required Map<String, Client> clientById,
}) {
  final byKey = <String, String>{};
  void add(PartyFacts f) {
    final v = _of(f, field);
    if (v.isEmpty) return;
    byKey.putIfAbsent(_key(field, v), () => v);
  }

  for (final b in buys) {
    add(factsOfBuy(b, clientById));
  }
  for (final t in transfers) {
    add(factsOfTransfer(t));
  }
  return byKey.values.toList()..sort();
}

/// A code is compared without case, spaces or digit shape (٥٥٢١ = 5521); a
/// company or a name without case or extra spaces.
String _key(PartyField field, String s) => field == PartyField.code
    ? partyKey(s)
    : s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Whether [facts] belongs to what was asked for. A code must be the same
/// code; a company or a name matches when it contains what was typed.
bool partyMatches(PartyFacts facts, PartyField field, String query) {
  final q = _key(field, query);
  if (q.isEmpty) return false;
  final v = _key(field, _of(facts, field));
  if (v.isEmpty) return false;
  return field == PartyField.code ? v == q : v.contains(q);
}

/// The entries and exits that belong to [query] in [field].
({List<CurrencyBuy> buys, List<Transfer> transfers}) operationsOfParty({
  required PartyField field,
  required String query,
  required Iterable<CurrencyBuy> buys,
  required Iterable<Transfer> transfers,
  required Map<String, Client> clientById,
}) =>
    (
      buys: [
        for (final b in buys)
          if (partyMatches(factsOfBuy(b, clientById), field, query)) b,
      ],
      transfers: [
        for (final t in transfers)
          if (partyMatches(factsOfTransfer(t), field, query)) t,
      ],
    );

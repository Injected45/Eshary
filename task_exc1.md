Eshary Flutter + Supabase at D:\forward\rhalla\Eshary. Riverpod 2.x, Arabic/RTL, dark glassmorphism. Recent state:
  - TransfersScreen Section 1 has cascading ةفارصلا ةكرش (String) → باسحلا مسإ (Exchange) dropdowns, then full-width يراشإلا مقرلا + باسحلا ديصر. The body of each section is
  wrapped in a private `_CollapsibleSection` stateful widget defined at the bottom of transfers_screen.dart (internal `_expanded` flag, chevron toggles). The constructor       
  currently does NOT accept `key` — you must add `super.key`.
  - CurrencyBuyScreen "باسح ىلإ ءارشلا هيجوت" currently has Companies first, Exchange filtered second. Pending rows are shown in `_PendingTable` and daily rows in              
  `_DailyBuysTable`, both StatelessWidgets that read `b.clientFromAccount` (the client's free-text "company" field) for the client cell — that is NOT the client's name.      
  - Saved beneficiaries dialog (`_SavedBeneficiariesDialog` inside transfers_screen.dart) list-tile shows `item.name` (bold) on top + `item.account` underneath. User wants this
   inverted.
  - ArchiveScreen `_SoldTable` and `_BoughtTable` group rows by date and inline a DataTable per day under a date heading — too noisy.
  - Archive RPC `archive_daily_buys(p_owner)` (migration 0003) raises `'cannot archive: N pending currency buy(s) must be resolved first'` with errcode `check_violation` when
  pending rows exist; the current friendlyError default catches it but the user can't tell why.

  Available primitives:
  - `clientsListProvider` (List<Client>) — lib\features\clients\presentation\clients_providers.dart
  - `pendingBuysProvider` / `dailyBuysProvider` / `archivedBuysProvider` — lib\features\currency_buy\presentation\currency_buys_providers.dart
  - `companiesListProvider` (List<Company>) + `allExchangesProvider` (List<Exchange>) — lib\features\companies\presentation\companies_providers.dart
  - `exchangeCompaniesListProvider` (List<ExchangeCompany>) — lib\features\exchange_companies\presentation\exchange_companies_providers.dart
  - `_TransferArchiveDetailScreen` / `_BuyArchiveDetailScreen` / `_DetailKv` private widgets at the bottom of archive_screen.dart
  - `friendlyError(e)` helper — lib\shared\logger.dart
  - `parseMoney`, `formatMoney`, `dateOnly`, `dateTime` — lib\shared\formatters.dart
  - The Exchange and Company classes have id-based `==` overrides; equality comparisons work.
  - Each Company has exactly one Exchange row (1:1) in the current data model.

  ## Task 1 — CurrencyBuy tables: show actual client NAME
  Edit ONLY: lib\features\currency_buy\presentation\currency_buy_screen.dart

  Convert `_PendingTable` from StatelessWidget → ConsumerWidget. Inside `build`, watch `clientsListProvider` and build `final clientById = { for (final c in (clients.value ??
  const <Client>[])) c.id: c.name }`. Replace the "ليمعلا" cell value `b.clientFromAccount ?? '-'` with `clientById[b.clientId] ?? b.clientFromAccount ?? '—'`.

  Same conversion + same fix in `_DailyBuysTable`: replace the third column "باسحلا" cell value `b.clientFromAccount ?? '-'` with `clientById[b.clientId] ?? b.clientFromAccount
   ?? '—'`. The column header "باسحلا" STAYS unchanged.

  DO NOT change the repository writes — both columns keep being saved in the DB.

  ## Task 2 — CurrencyBuy "باسح ىلإ ءارشلا هيجوت": invert order — exchange-company FIRST, company filtered SECOND
  Edit ONLY: lib\features\currency_buy\presentation\currency_buy_screen.dart

  Add `String? _exchangeCompanyName;` to `_CurrencyBuyScreenState`. Add the import `'../../exchange_companies/presentation/exchange_companies_providers.dart';` if missing.

  REPLACE the existing `companiesAsync.when(data: (companies) => Row[CompaniesDropdown, ExchangesDropdown])` block with two CONSECUTIVE pickers (not in a Row — vertical stack
  with SizedBox(height: 14) between):

  DropdownButtonFormField<String> sourced from `exchangeCompaniesListProvider` (names). Apply the existing postFrame stale-value guard. onChanged — **ةملتسملا ةفارصلا ةكرش** .1
   calls a new private method `_onExchangeCompanyChanged(String? name)` which does `setState(() { _exchangeCompanyName = name; _myCompany = null; _exchange = null; })`.

   DropdownButtonFormField<Company> filtered to companies whose Exchange (looked up via `allExchangesProvider`) has `name == _exchangeCompanyName`. Build — **ةصاخلا كتكرش** .2
  the filtered list as: get allExchanges (from `ref.watch(allExchangesProvider).value ?? const []`), filter to those with `e.name == _exchangeCompanyName`, then map each to its
   Company via `companies.firstWhere((c) => c.id == e.companyId, orElse: () => null)` (cast appropriately) and dedupe. Empty-disabled when `_exchangeCompanyName == null` with
  hint `'اًلوأ ةفارصلا ةكرش رتخا'`. Apply the postFrame stale-value guard. onChanged: setState such that `_myCompany = c` AND `_exchange` is set to the matching Exchange row
  (the one with `e.companyId == c.id && e.name == _exchangeCompanyName`).

  DELETE the previously-existing inner `exchangesAsync.when(...)` Exchange dropdown — `_exchange` is now auto-bound when the user picks the company. The existing
  `exchangesAsync = _myCompany == null ? const AsyncValue.data([]) : ref.watch(exchangesByCompanyProvider(_myCompany!.id))` line at the top of build is no longer needed and CAN
   be removed; replace its usages.

  DO NOT touch the client dropdown, the USD/rate/LYD inputs, or the action buttons.

  ## Task 3 — Saved beneficiaries list-tile: invert label order
  Edit ONLY: lib\features\transfers\presentation\transfers_screen.dart

  In `_SavedBeneficiariesDialogState.build`'s ListView.separated.itemBuilder, the current inner Column is:
  ```dart
  Text(item.name, style: TextStyle(fontSize: 13, fontWeight: w600, textHigh)),
  SizedBox(height: 2),
  Text(item.account ?? '—', style: TextStyle(fontSize: 11, textLow)),
  Swap so the account string sits on top with the bold/textHigh style, and the name string sits below with the smaller/textLow style. Fallback "—" for null/empty account STAYS
  — substitute it BEFORE rendering. Keep both styles' fontSize/fontWeight values; only the position swaps. The trash IconButton, the InkWell tap → Navigator.pop(item), and the
  leading FaIcon are unchanged.

  Task 4 — Transfers: prevent send when amount > exchange balance

  Edit ONLY: lib\features\transfers\presentation\transfers_screen.dart

  In _generate(), AFTER the parseMoney(_amount.text) <= 0 guard and BEFORE the _beneficiaryName.text.trim().isEmpty guard, insert:
  final amount = parseMoney(_amount.text);
  final balance = _exchange?.balance ?? 0;
  if (amount > balance) {
    _snack('باسحلا ديصر زواجتي غلبملا (${formatMoney(balance)} \$).');
    return;
  }

  Also insert the SAME guard at the top of _saveToDaily() (right after the if (_company == null || _exchange == null || _reference == null) return; early-exit) — the
  messages-preview path can call _saveToDaily without re-running _generate. After the guard, proceed with the existing setState(() => _busy = true).

  Task 5 — Transfers: clear all fields + collapse all sections after save success

  Edit ONLY: lib\features\transfers\presentation\transfers_screen.dart

  Step A — make _CollapsibleSection programmatically collapsible:
  - Update its constructor signature to accept super.key: const _CollapsibleSection({super.key, required this.header, required this.child, this.initiallyExpanded = true});
  - Add a public method on _CollapsibleSectionState:
  void collapse() {
    if (_expanded) setState(() => _expanded = false);
  }

  Step B — file-scope GlobalKeys (add near transfersScreenKey):
  final _section1Key = GlobalKey<_CollapsibleSectionState>();
  final _section2Key = GlobalKey<_CollapsibleSectionState>();
  final _section3Key = GlobalKey<_CollapsibleSectionState>();
  final _logSectionKey = GlobalKey<_CollapsibleSectionState>();

  Step C — pass each key to its _CollapsibleSection:
  - Section 1 (ةذفنملا ةهجلا) → key: _section1Key
  - Section 2 (مالتسالا ةهج) → key: _section2Key
  - Section 3 (ليوحتلا ةميق) → key: _section3Key
  - Daily-log card (ةذفنملا تالاوحلا لجس) → key: _logSectionKey

  Step D — in _saveToDaily(), INSIDE the existing setState(() { _composedMessages = null; _amount.clear(); ... _reference = next; }) block, ALSO add:
  _exchangeCompanyName = null;
  _exchange = null;
  _company = null;

  Step E — AFTER playAlert() and BEFORE _snack('يمويلا لجسلا يف ظفحلا مت'), call:
  _section1Key.currentState?.collapse();
  _section2Key.currentState?.collapse();
  _section3Key.currentState?.collapse();
  _logSectionKey.currentState?.collapse();

  DO NOT change _archiveAll, the chevron animation, or the AnimatedSize duration.

  Task 6 — Archive: collapsed day-row → tap opens that day's transactions screen

  Edit ONLY: lib\features\archive\presentation\archive_screen.dart

  In _SoldTable.build, REPLACE the current for (final date in sortedDates) [Padding(date heading), SingleChildScrollView(DataTable per day)] block with a list of tappable
  day-summary tiles. The existing date grouping (grouped map + sortedDates list newest-first) STAYS. For each date compute final dayTotal = grouped[date]!.fold<double>(0, (s,
  t) => s + t.amount);.

  Render each date as:
  Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openSoldDay(context, date, grouped[date]!),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            border: Border.all(color: AppColors.glassBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const FaIcon(FontAwesomeIcons.calendar, size: 12, color: AppColors.textLow),
            const SizedBox(width: 8),
            Expanded(child: Text(date, style: const TextStyle(color: AppColors.textHigh, fontSize: 13, fontWeight: FontWeight.w600))),
            Text('-${formatMoney(dayTotal)}', style: const TextStyle(color: AppColors.negative, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            const FaIcon(FontAwesomeIcons.chevronLeft, size: 12, color: AppColors.textLow),
          ]),
        ),
      ),
    ),
  ),

  The grand-total row at the bottom of _SoldTable (the one with total parameter) STAYS unchanged.

  Add a top-level helper in the same file: void _openSoldDay(BuildContext context, String date, List<Transfer> dayRows) =>
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _SoldDayDetailScreen(date: date, rows: dayRows)));

  Define _SoldDayDetailScreen at the bottom of archive_screen.dart (next to the existing _TransferArchiveDetailScreen):
  - Constructor: const _SoldDayDetailScreen({required this.date, required this.rows}); with final String date; final List<Transfer> rows;
  - AppBar title 'ليصافت $date' with the same glass styling as other detail screens.
  - Body: ListView with one GlassCard containing a SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(...)) mirroring the existing per-day DataTable from
  _SoldTable (showCheckboxColumn: false, columns ةميقلا / يراشإلا / ةكرشلا مسا \$, rows reuse DataRow(onSelectChanged: (_) => _openSoldDetail(context, t), cells: [...])).
  - A footer "مويلا يلامجإ" row inside the same GlassCard: a Row with label and -${formatMoney(rows.fold<double>(0, (s, t) => s + t.amount))} in negative color and bold.

  Apply the SAME pattern to _BoughtTable:
  - Group rows by dateOnly.format(b.archivedAt ?? b.createdAt) if not already (mirror _SoldTable's grouping).
  - Compute dayTotal = dayRows.fold<double>(0, (s, b) => s + b.usdAmount).
  - Render tappable day tiles in positive-green: '+${formatMoney(dayTotal)}', color AppColors.positive.
  - Helper _openBoughtDay(context, date, dayRows) → push _BuyDayDetailScreen.
  - _BuyDayDetailScreen mirrors _SoldDayDetailScreen but with columns ةميقلا / خيراتلا \$ (or just ةميقلا / باسحلا per your preference) and rows reuse _openBoughtDetail for
  per-row tap. Add the day-total footer row in positive color.
  - Keep the existing grand-total DataRow at the bottom of _BoughtTable unchanged.

  DO NOT remove the per-row tap into _TransferArchiveDetailScreen / _BuyArchiveDetailScreen — that behavior moves into the new day-detail screens.

  Task 7 — CurrencyBuy archive button: pre-check pending + clearer Arabic message

  Edit ONLY: lib\features\currency_buy\presentation\currency_buy_screen.dart  AND  lib\shared\logger.dart

  In lib\shared\logger.dart friendlyError(e), ADD a new substring branch BEFORE the existing '23503' branch:
  if (s.contains('pending currency buy') ||
      (s.contains('check_violation') && s.contains('pending'))) {
    return 'الًوأ اهفذحا وأ اهلمكأ .ةقلّعم ءارش تايلمع دجوت :ليحرتلا نكمي ال.';
  }

  In currency_buy_screen.dart _archiveAll(), BEFORE the showDialog confirm prompt, ADD a client-side guard:
  final pendingCount =
      (ref.read(pendingBuysProvider).value ?? const <CurrencyBuy>[]).length;
  if (pendingCount > 0) {
    _snack('كيدل :ليحرتلا نكمي ال $pendingCount ةقلّعم ةيلمع.');
    return;
  }

  DO NOT change the RPC, the migration, or the archive-action provider.

  Hard rules — NEVER violate

  - NEVER edit any file outside the four named above (currency_buy_screen.dart, transfers_screen.dart, archive_screen.dart, logger.dart).
  - NEVER add a pubspec dependency.
  - NEVER touch supabase migrations or RPCs.
  - NEVER auto-pick a باسح after the user picks a ةفارصلا ةكرش on either screen — leave the second dropdown blank for the user.
  - NEVER change the AnimatedSize duration / curve of _CollapsibleSection.
  - NEVER make _CollapsibleSection or its State public.
  - STOP and ASK before deleting any file.

  Verification

  flutter analyze lib\features\currency_buy\presentation\currency_buy_screen.dart lib\features\transfers\presentation\transfers_screen.dart
  lib\features\archive\presentation\archive_screen.dart lib\shared\logger.dart
  Report only errors (not info/style).

  Done when

  1. CurrencyBuy pending + daily tables show the actual client name (looked up via clientsListProvider) — falling back to clientFromAccount only when client_id is null.
  2. CurrencyBuy "هيجوت" section: ةملتسملا ةفارصلا ةكرش dropdown is the FIRST picker; ةصاخلا كتكرش appears below it as a dropdown filtered to companies whose Exchange.name
  matches the picked exchange-company; selecting a company auto-binds _exchange to that company's exchange row; the previous Companies+Exchanges Row layout is gone.
  3. Saved beneficiaries list-tile shows the account text on top (bold/textHigh) and the name string underneath (small/textLow).
  4. Trying to save/generate a transfer with amount > balance shows snackbar "باسحلا ديصر زواجتي غلبملا (X.XX $)" and aborts; the SAME guard fires from both _generate and
  _saveToDaily paths.
  5. After a transfer save succeeds: all 4 input controllers are cleared, _exchangeCompanyName / _company / _exchange are nulled, and all 4 _CollapsibleSections collapse.
  6. Archive sold + bought cards show one tappable date row per day (icon + date + day total + chevron); tapping opens a per-day detail screen with the full transactions table;
   row taps inside that screen open _TransferArchiveDetailScreen / _BuyArchiveDetailScreen as before. The grand-total rows at the bottom of _SoldTable and _BoughtTable STAY.
  7. Pressing "ةلمعلا تايرتشمل يمويلا لافقإلا" with N pending rows: skips the confirm dialog, shows snackbar "كيدل :ليحرتلا نكمي ال N ةقلّعم ةيلمع." With no pending rows:
  archive proceeds normally; any RPC failure now shows "الًوأ اهفذحا وأ اهلمكأ .ةقلّعم ءارش تايلمع دجوت :ليحرتلا نكمي ال." instead of the generic default.

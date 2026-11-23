import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../core/app_variant.dart';
import '../../core/l10n_ext.dart';
import '../../core/platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/games.dart';
import '../../data/models/plan.dart';
import '../../l10n/app_localizations.dart';
import '../../services/billing/subscription_service.dart';
import '../../services/referral/referral_service.dart';
import '../../shared/art/zad_art.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../parent/devices_card.dart' show JoinFamilyCard;
import '../parent/parent_gate.dart';

final _billingProvider = StateProvider<BillingPeriod>((_) => BillingPeriod.yearly);

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final period = ref.watch(_billingProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.subTitle), backgroundColor: AppColors.navy, foregroundColor: Colors.white),
      body: ZadSceneBackground(
        scene: ZadScene.parent,
        // Prices and purchase are for parents only: a child who reaches this
        // screen (home banner, upgrade sheet, deep link) sees the PIN prompt.
        child: ParentGate(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(l10n.subIntro, style: const TextStyle(fontSize: 17, color: AppColors.muted)),
            const SizedBox(height: 12),
            SegmentedButton<BillingPeriod>(
              segments: [
                ButtonSegment(value: BillingPeriod.monthly, label: Text(l10n.monthly, style: const TextStyle(fontSize: 16))),
                ButtonSegment(value: BillingPeriod.yearly, label: Text('${l10n.yearly} · ${l10n.saveUpTo}', style: const TextStyle(fontSize: 15))),
              ],
              selected: {period},
              onSelectionChanged: (s) => ref.read(_billingProvider.notifier).state = s.first,
            ),
            const SizedBox(height: 14),
            _PlanCards(period: period),
            const SizedBox(height: 14),
            ZadCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l10n.launchOffers, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Banner2(text: l10n.offer1, bg: AppColors.mintSoft, fg: AppColors.mintText),
                const SizedBox(height: 6),
                Banner2(text: l10n.offer2, bg: AppColors.purpleSoft, fg: AppColors.purpleDark),
                // Ramadan offer: Zad X Play only.
                if (!kIsKids) ...[
                  const SizedBox(height: 6),
                  Banner2(text: l10n.offer3, bg: const Color(0xFFFFF4D6), fg: AppColors.pendingText),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            const _ReferralCard(),
            const SizedBox(height: 10),
            Text(l10n.pricesNote, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            TextButton(onPressed: () => ref.read(subscriptionServiceProvider).restore(), child: Text(l10n.restorePurchases)),
            // The store subscription belongs to another Zad X family (e.g. a new phone): it is
            // never joined automatically; the parent links this phone with a parent code.
            if (ref.watch(purchaseInOtherFamilyProvider).valueOrNull ?? false) ...[
              const SizedBox(height: 6),
              Banner2(text: l10n.purchaseOtherFamily, bg: const Color(0xFFFFF4D6), fg: AppColors.pendingText),
              const SizedBox(height: 8),
              const JoinFamilyCard(),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Free / Basic / Plus. Three columns on wide screens (in reading order, so
/// RTL puts Free on the right), stacked cards on phones.
class _PlanCards extends StatelessWidget {
  const _PlanCards({required this.period});
  final BillingPeriod period;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final cards = [
          for (final plan in allPlans) _PlanCard(plan: plan, period: period, highlighted: plan.tier == PlanTier.plus),
        ];
        if (constraints.maxWidth >= 720) {
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: cards[i]),
              ],
            ]),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            cards[i],
          ],
        ]);
      });
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan, required this.period, this.highlighted = false});
  final PlanPricing plan;
  final BillingPeriod period;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final service = ref.watch(subscriptionServiceProvider);
    final ent = ref.watch(entitlementProvider).valueOrNull ?? const Entitlement();
    final yearly = period == BillingPeriod.yearly;
    final tier = plan.tier;
    final has = plan.features.contains;
    final isCurrent = !ent.inTrial && ent.effectiveTier == tier;

    final name = switch (tier) {
      null => l10n.freeName,
      PlanTier.basic => l10n.basicName,
      PlanTier.plus => l10n.plusName,
    };

    // One checklist for all three cards, driven by the feature matrix in plan.dart.
    final features = <(String, Object)>[
      (l10n.featLock, has(AppFeature.appLock)),
      // Islamic features: Zad X Play only (not part of any Zad X Kids plan).
      if (!kIsKids) (l10n.featPrayer, has(AppFeature.prayerTimes) && has(AppFeature.adhan)),
      if (!kIsKids) (l10n.featQuran, has(AppFeature.quran)),
      (l10n.featTasks, has(AppFeature.tasksRewards)),
      // No "N games" here: with the device-wide lock every non-allowed app is locked
      // (maxGames only limits the Games screen picker).
      (l10n.featGames, has(AppFeature.tasksRewards)),
      // Zad X Kids has no built-in learning game yet: do not advertise one.
      if (activeZadGames.isNotEmpty) (l10n.featEduGames, has(AppFeature.eduGames)),
      (l10n.featExercises, has(AppFeature.exercises)),
      if (!kIsKids) (l10n.featAdhkar, has(AppFeature.adhkar)),
      (l10n.featCustomTasks, has(AppFeature.customUnlockTasks)),
      (l10n.featKids, Fmt.digits(plan.maxChildren, lang)),
      (
        l10n.featAi,
        has(AppFeature.unlimitedAssistant)
            ? l10n.unlimited
            : has(AppFeature.assistant)
                ? l10n.limited
                : false
      ),
      (l10n.featPs, has(AppFeature.consoleLinks)),
      (l10n.featReport, has(AppFeature.weeklyReport)),
    ];

    return ZadCard(
      border: Border.all(color: highlighted ? AppColors.purple : Colors.transparent, width: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (highlighted || isCurrent)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isCurrent ? AppColors.mintSoft : AppColors.yellow,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(isCurrent ? l10n.yourPlan : l10n.mostPopular,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ),
        const SizedBox(height: 6),
        Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        if (tier == null) ...[
          Text(l10n.freeNoSubscription, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.mintText)),
          Text(l10n.freeNote, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
        ] else ...[
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, children: [
            Text(
              // Prefer the localized store price; fall back to the suggested USD price.
              service.storePrice(tier, period) ?? Fmt.usd(yearly ? plan.yearly : plan.monthly),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
            ),
            Text(yearly ? l10n.perYear : l10n.perMonth, style: const TextStyle(fontSize: 16, color: AppColors.muted)),
            if (yearly)
              Text(Fmt.usd(plan.monthly * 12),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 16, color: AppColors.muted, decoration: TextDecoration.lineThrough)),
          ]),
          if (yearly)
            Text(l10n.yearEq(Fmt.usd(plan.yearlyPerMonth)),
                style: const TextStyle(fontSize: 15, color: AppColors.mintText, fontWeight: FontWeight.w800)),
        ],
        const SizedBox(height: 8),
        for (final (label, value) in features) _FeatureRow(label: label, value: value),
        const SizedBox(height: 10),
        if (tier == null)
          const SizedBox.shrink()
        else if (!AppPlatform.canPurchase)
          Banner2(text: l10n.subscribeOnPhone, bg: AppColors.purpleSoft, fg: AppColors.purpleDark)
        else
          FilledButton(
            style: highlighted ? null : FilledButton.styleFrom(backgroundColor: AppColors.purpleSoft, foregroundColor: AppColors.purpleDark),
            onPressed: () async {
              final code = ref.read(_appliedReferralProvider);
              final ok = await service.buy(tier, period, referralCode: code);
              if (!ok && context.mounted) showToast(context, l10n.purchaseError);
            },
            child: Text(l10n.subscribeNow),
          ),
      ]),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.label, required this.value});
  final String label;
  final Object value;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (text, color, spoken) = switch (value) {
      true => ('✓', AppColors.mintText, l10n.featIncluded),
      false => ('—', const Color(0xFF6E6A87), l10n.featNotIncluded),
      _ => (value.toString(), AppColors.mintText, value.toString()),
    };
    return Semantics(
      label: '$label: $spoken',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.purpleSoft))),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        ]),
      ),
    );
  }
}

/// Code a new user typed from a friend's invite (applied at purchase).
final _appliedReferralProvider = StateProvider<String?>((_) => null);

class _ReferralCard extends ConsumerWidget {
  const _ReferralCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final status = ref.watch(referralStatusProvider).valueOrNull ?? const ReferralStatus(code: '…');
    final friends = status.paidFriends.clamp(0, AppConfig.referralMaxFriendsPerYear);
    final ladder = [l10n.invite1, l10n.invite2, l10n.invite3];

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.inviteTitle, style: Theme.of(context).textTheme.titleMedium),
        Text(l10n.inviteRule, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
        const SizedBox(height: 8),
        for (var i = 0; i < ladder.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: friends > i ? AppColors.purple : AppColors.cream,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Expanded(
                child: Text(ladder[i],
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: friends > i ? Colors.white : AppColors.ink)),
              ),
              if (friends > i) const Icon(Icons.check_rounded, color: Colors.white),
            ]),
          ),
        const SizedBox(height: 6),
        Text(l10n.yourCode, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.muted)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF8FF),
                border: Border.all(color: const Color(0xFFB9A6F5), width: 2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(status.code,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: 2, color: AppColors.purpleDark)),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: status.code));
              showToast(context, l10n.copied);
            },
            child: Text(l10n.copy),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text(l10n.invitedOf(Fmt.digits(friends, lang)), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          Text(
            status.rewardMonths > 0 ? l10n.rewardMonths(status.rewardMonths, Fmt.digits(status.rewardMonths, lang)) : l10n.noRewardYet,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.mintText),
          ),
        ]),
        const SizedBox(height: 6),
        ProgressBar(value: friends / 3, color: AppColors.yellow),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => Share.share(l10n.inviteShareText(status.code)),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text(l10n.inviteFriend),
        ),
        const SizedBox(height: 8),
        _RedeemField(l10n: l10n),
      ]),
    );
  }
}

/// A new family enters a friend's code before subscribing.
class _RedeemField extends ConsumerWidget {
  const _RedeemField({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextField(
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(fontSize: 17),
        decoration: InputDecoration(
          labelText: l10n.inviteCodeField,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onChanged: (v) => ref.read(_appliedReferralProvider.notifier).state = v.trim().isEmpty ? null : v.trim().toUpperCase(),
      );
}

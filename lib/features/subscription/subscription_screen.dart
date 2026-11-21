import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../core/l10n_ext.dart';
import '../../core/platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/plan.dart';
import '../../l10n/app_localizations.dart';
import '../../services/billing/subscription_service.dart';
import '../../services/referral/referral_service.dart';
import '../../shared/art/zad_art.dart';
import '../../shared/widgets/zad_widgets.dart';

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
          _PlanCard(plan: planPlus, period: period, highlighted: true),
          const SizedBox(height: 12),
          _PlanCard(plan: planBasic, period: period),
          const SizedBox(height: 14),
          ZadCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l10n.launchOffers, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Banner2(text: l10n.offer1, bg: AppColors.mintSoft, fg: AppColors.mintText),
              const SizedBox(height: 6),
              Banner2(text: l10n.offer2, bg: AppColors.purpleSoft, fg: AppColors.purpleDark),
              const SizedBox(height: 6),
              Banner2(text: l10n.offer3, bg: const Color(0xFFFFF4D6), fg: AppColors.pendingText),
            ]),
          ),
          const SizedBox(height: 14),
          const _ReferralCard(),
          const SizedBox(height: 10),
          Text(l10n.pricesNote, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          TextButton(onPressed: () => ref.read(subscriptionServiceProvider).restore(), child: Text(l10n.restorePurchases)),
        ]),
      ),
    );
  }
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
    final yearly = period == BillingPeriod.yearly;
    // Prefer the localized store price; fall back to the suggested USD price.
    final price = service.storePrice(plan.tier, period) ?? Fmt.usd(yearly ? plan.yearly : plan.monthly);
    final isPlus = plan.tier == PlanTier.plus;

    final features = <(String, Object)>[
      (l10n.featTasks, true),
      (l10n.featPrayer, true),
      (l10n.featQuran, true),
      (l10n.featGames, l10n.gamesN(Fmt.digits(plan.maxGames, lang))),
      (l10n.featPs, plan.playStation),
      (l10n.featAi, plan.unlimitedAssistant ? l10n.unlimited : l10n.limited),
      (l10n.featKids, Fmt.digits(plan.maxChildren, lang)),
      (l10n.featReport, plan.weeklyReport),
    ];

    return ZadCard(
      border: Border.all(color: highlighted ? AppColors.purple : Colors.transparent, width: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (highlighted)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(999)),
              child: Text(l10n.mostPopular, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ),
        const SizedBox(height: 6),
        Text(isPlus ? l10n.plusName : l10n.basicName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, children: [
          Text(price, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          Text(yearly ? l10n.perYear : l10n.perMonth, style: const TextStyle(fontSize: 16, color: AppColors.muted)),
          if (yearly)
            Text(Fmt.usd(plan.monthly * 12),
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 16, color: AppColors.muted, decoration: TextDecoration.lineThrough)),
        ]),
        if (yearly)
          Text(l10n.yearEq(Fmt.usd(plan.yearlyPerMonth)),
              style: const TextStyle(fontSize: 15, color: AppColors.mintText, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final (label, value) in features) _FeatureRow(label: label, value: value),
        const SizedBox(height: 10),
        if (!AppPlatform.canPurchase)
          Banner2(text: l10n.subscribeOnPhone, bg: AppColors.purpleSoft, fg: AppColors.purpleDark)
        else
        FilledButton(
          style: highlighted ? null : FilledButton.styleFrom(backgroundColor: AppColors.purpleSoft, foregroundColor: AppColors.purpleDark),
          onPressed: () async {
            final code = ref.read(_appliedReferralProvider);
            final ok = await service.buy(plan.tier, period, referralCode: code);
            if (!ok && context.mounted) showToast(context, l10n.purchaseError);
          },
          child: Text(l10n.startTrial),
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
    final (text, color) = switch (value) {
      true => ('✓', AppColors.mintText),
      false => ('—', const Color(0xFF8A86A3)),
      _ => (value.toString(), AppColors.mintText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.purpleSoft))),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
        Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      ]),
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
            status.rewardMonths > 0 ? l10n.rewardMonths(Fmt.digits(status.rewardMonths, lang)) : l10n.noRewardYet,
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

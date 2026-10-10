/// A refusal from the trial / subscription functions. [code] is the machine
/// word the database or the Edge Function returned (`friendlyError` turns it
/// into Arabic).
class TrialRefused implements Exception {
  const TrialRefused(this.code, {this.wait, this.left});

  final String code;

  /// Seconds before another code may be requested (`too_soon`).
  final int? wait;

  /// Wrong-code attempts left on this code (`invalid_code`).
  final int? left;

  @override
  String toString() => code;
}

/// What an applicant sees about their own request (`trial_follow`).
class TrialFollow {
  const TrialFollow({
    required this.status,
    required this.managerName,
    required this.businessName,
    required this.phoneMasked,
    required this.trialHours,
    required this.phoneVerified,
    required this.reviewNote,
    required this.messageStatus,
    required this.resendWait,
    required this.canRequestCode,
    required this.approvalExpiresAt,
  });

  /// pending_review / needs_info / approved / approval_expired / rejected /
  /// activated.
  final String status;
  final String managerName;
  final String businessName;
  final String phoneMasked;
  final int? trialHours;
  final bool phoneVerified;
  final String? reviewNote;

  /// queued / sent / failed, or null when no code was ever sent.
  final String? messageStatus;
  final int resendWait;
  final bool canRequestCode;
  final DateTime? approvalExpiresAt;

  factory TrialFollow.fromJson(Map<String, dynamic> j) => TrialFollow(
        status: j['status'] as String? ?? 'pending_review',
        managerName: j['managerName'] as String? ?? '',
        businessName: j['businessName'] as String? ?? '',
        phoneMasked: j['phone'] as String? ?? '',
        trialHours: (j['trialHours'] as num?)?.toInt(),
        phoneVerified: j['phoneVerified'] == true,
        reviewNote: j['reviewNote'] as String?,
        messageStatus: j['messageStatus'] as String?,
        resendWait: (j['resendWait'] as num?)?.toInt() ?? 0,
        canRequestCode: j['canRequestCode'] == true,
        approvalExpiresAt: j['approvalExpiresAt'] == null
            ? null
            : DateTime.parse(j['approvalExpiresAt'] as String),
      );
}

/// The subscriber's own state, answered by the database clock
/// (`subscription_state`). Nothing here comes from the phone's clock.
class SubscriptionState {
  const SubscriptionState({
    required this.status,
    required this.serverNow,
    required this.trialEndsAt,
    required this.remainingSeconds,
    required this.allowedActions,
    required this.receivedAtTicks,
  });

  /// pending / trial / paid / expired / suspended / time_untrusted.
  final String status;
  final DateTime serverNow;
  final DateTime? trialEndsAt;
  final int? remainingSeconds;
  final List<String> allowedActions;

  /// Monotonic reading ([Stopwatch]) at the moment the answer arrived, so the
  /// countdown moves with elapsed time, not with the (changeable) phone clock.
  final int receivedAtTicks;

  bool get canWrite => allowedActions.contains('write');

  factory SubscriptionState.fromJson(
    Map<String, dynamic> j,
    int ticksMs,
  ) =>
      SubscriptionState(
        status: j['status'] as String? ?? 'pending',
        serverNow: DateTime.parse(j['serverNow'] as String),
        trialEndsAt: j['trialEndsAt'] == null
            ? null
            : DateTime.parse(j['trialEndsAt'] as String),
        remainingSeconds: (j['remainingSeconds'] as num?)?.toInt(),
        allowedActions:
            ((j['allowedActions'] as List?) ?? const []).cast<String>(),
        receivedAtTicks: ticksMs,
      );
}

/// One row of the administrator's trial-request list.
class TrialRequestRow {
  const TrialRequestRow({
    required this.id,
    required this.managerName,
    required this.businessName,
    required this.phone,
    required this.status,
    required this.bucket,
    required this.reviewNote,
    required this.requestedAt,
    required this.approvalExpiresAt,
    required this.trialHours,
    required this.phoneVerified,
    required this.trialEndsAt,
    required this.remainingSeconds,
    required this.userId,
    required this.messageStatus,
    required this.repeatHint,
  });

  final String id;
  final String managerName;
  final String businessName;
  final String phone;
  final String status;

  /// pending_review / needs_info / approved_waiting / message_failed /
  /// approval_expired / active_trial / ending_soon / expired_trial / paid /
  /// rejected_or_suspended.
  final String bucket;
  final String? reviewNote;
  final DateTime requestedAt;
  final DateTime? approvalExpiresAt;
  final int? trialHours;
  final bool phoneVerified;
  final DateTime? trialEndsAt;
  final int? remainingSeconds;
  final String? userId;
  final String? messageStatus;
  final int repeatHint;

  factory TrialRequestRow.fromJson(Map<String, dynamic> j) => TrialRequestRow(
        id: j['id'] as String,
        managerName: j['manager_name'] as String? ?? '',
        businessName: j['business_name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        status: j['status'] as String? ?? '',
        bucket: j['bucket'] as String? ?? '',
        reviewNote: j['review_note'] as String?,
        requestedAt: DateTime.parse(j['requested_at'] as String),
        approvalExpiresAt: j['approval_expires_at'] == null
            ? null
            : DateTime.parse(j['approval_expires_at'] as String),
        trialHours: (j['trial_hours'] as num?)?.toInt(),
        phoneVerified: j['phone_verified'] == true,
        trialEndsAt: j['trial_ends_at'] == null
            ? null
            : DateTime.parse(j['trial_ends_at'] as String),
        remainingSeconds: (j['remaining_seconds'] as num?)?.toInt(),
        userId: j['user_id'] as String?,
        messageStatus: j['message_status'] as String?,
        repeatHint: (j['repeat_hint'] as num?)?.toInt() ?? 0,
      );
}

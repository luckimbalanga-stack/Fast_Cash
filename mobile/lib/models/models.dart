class PhoneNumber {
  PhoneNumber({
    required this.id,
    required this.phone,
    required this.network,
    required this.networkLabel,
    required this.isPrimary,
    required this.verified,
  });

  final int id;
  final String phone;
  final String network;
  final String networkLabel;
  final bool isPrimary;
  final bool verified;

  factory PhoneNumber.fromJson(Map<String, dynamic> json) => PhoneNumber(
        id: json['id'] as int,
        phone: json['phone'] as String,
        network: json['network'] as String,
        networkLabel: json['network_label'] as String? ?? '',
        isPrimary: json['is_primary'] == true,
        verified: json['verified'] == true,
      );
}

class UserAccount {
  UserAccount({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    required this.createdAt,
    required this.numbers,
    this.transactionCount,
  });

  final int id;
  final String name;
  final String phone;
  final String status;
  final String createdAt;
  final List<PhoneNumber> numbers;
  final int? transactionCount;

  PhoneNumber? get primary {
    for (final number in numbers) {
      if (number.isPrimary && number.verified) return number;
    }
    if (numbers.isEmpty) return null;
    return numbers.first;
  }

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        id: json['id'] as int,
        name: json['name'] as String,
        phone: json['phone'] as String,
        status: json['status'] as String? ?? 'active',
        createdAt: json['created_at'] as String? ?? '',
        transactionCount: json['transaction_count'] as int?,
        numbers: ((json['numbers'] as List?) ?? []).map((item) => PhoneNumber.fromJson(item as Map<String, dynamic>)).toList(),
      );
}

class PdrPoint {
  PdrPoint({
    required this.id,
    required this.code,
    required this.name,
    required this.managerName,
    required this.phone,
    required this.address,
    required this.commune,
    required this.city,
    required this.lat,
    required this.lng,
    required this.usdDeclared,
    required this.cdfDeclared,
    required this.usdReserved,
    required this.cdfReserved,
    required this.usdAvailable,
    required this.cdfAvailable,
    required this.acceptsDeposits,
    required this.networks,
    required this.networkLabels,
    required this.status,
    required this.isOpen,
    required this.ratingAvg,
    required this.ratingCount,
    required this.openingHours,
    this.distanceM,
    this.etaMin,
    this.availableForRequest,
  });

  final int id;
  final String code;
  final String name;
  final String managerName;
  final String phone;
  final String address;
  final String commune;
  final String city;
  final double lat;
  final double lng;
  final double usdDeclared;
  final double cdfDeclared;
  final double usdReserved;
  final double cdfReserved;
  final double usdAvailable;
  final double cdfAvailable;
  final bool acceptsDeposits;
  final List<String> networks;
  final List<String> networkLabels;
  final String status;
  final bool isOpen;
  final double ratingAvg;
  final int ratingCount;
  final String openingHours;
  final double? distanceM;
  final int? etaMin;
  final bool? availableForRequest;

  factory PdrPoint.fromJson(Map<String, dynamic> json) => PdrPoint(
        id: json['id'] as int,
        code: json['code'] as String,
        name: json['name'] as String,
        managerName: json['manager_name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        address: json['address'] as String? ?? '',
        commune: json['commune'] as String? ?? '',
        city: json['city'] as String? ?? 'Kinshasa',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        usdDeclared: (json['usd_declared'] as num?)?.toDouble() ?? 0,
        cdfDeclared: (json['cdf_declared'] as num?)?.toDouble() ?? 0,
        usdReserved: (json['usd_reserved'] as num?)?.toDouble() ?? 0,
        cdfReserved: (json['cdf_reserved'] as num?)?.toDouble() ?? 0,
        usdAvailable: (json['usd_available'] as num?)?.toDouble() ?? 0,
        cdfAvailable: (json['cdf_available'] as num?)?.toDouble() ?? 0,
        acceptsDeposits: json['accepts_deposits'] == true,
        networks: ((json['networks'] as List?) ?? []).map((item) => item.toString()).toList(),
        networkLabels: ((json['network_labels'] as List?) ?? []).map((item) => item.toString()).toList(),
        status: json['status'] as String? ?? 'active',
        isOpen: json['is_open'] == true,
        ratingAvg: (json['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: json['rating_count'] as int? ?? 0,
        openingHours: json['opening_hours'] as String? ?? '',
        distanceM: (json['distance_m'] as num?)?.toDouble(),
        etaMin: json['eta_min'] as int?,
        availableForRequest: json['available_for_request'] as bool?,
      );
}

class TimelineEvent {
  TimelineEvent({required this.status, required this.label, required this.createdAt});
  final String status;
  final String label;
  final String createdAt;

  factory TimelineEvent.fromJson(Map<String, dynamic> json) => TimelineEvent(
        status: json['status'] as String? ?? '',
        label: json['label'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

class CashOperation {
  CashOperation({
    required this.id,
    required this.reference,
    required this.type,
    required this.userId,
    required this.userName,
    required this.pdrId,
    required this.pdrName,
    required this.pdrAddress,
    required this.pdrCommune,
    required this.pdrLat,
    required this.pdrLng,
    required this.pdrHours,
    required this.pdrPhone,
    required this.phone,
    required this.network,
    required this.networkLabel,
    required this.amount,
    required this.currency,
    required this.fees,
    required this.total,
    required this.status,
    required this.tokenCode,
    required this.tokenStatus,
    required this.tokenExpiresAt,
    required this.ratingStars,
    required this.ratingComment,
    required this.createdAt,
    required this.timeline,
  });

  final int id;
  final String reference;
  final String type;
  final int userId;
  final String userName;
  final int pdrId;
  final String pdrName;
  final String pdrAddress;
  final String pdrCommune;
  final double pdrLat;
  final double pdrLng;
  final String pdrHours;
  final String pdrPhone;
  final String phone;
  final String network;
  final String networkLabel;
  final double amount;
  final String currency;
  final double fees;
  final double total;
  final String status;
  final String? tokenCode;
  final String? tokenStatus;
  final String? tokenExpiresAt;
  final int? ratingStars;
  final String? ratingComment;
  final String createdAt;
  final List<TimelineEvent> timeline;

  bool get isWithdrawal => type == 'withdrawal';

  factory CashOperation.fromJson(Map<String, dynamic> json) => CashOperation(
        id: json['id'] as int,
        reference: json['reference'] as String,
        type: json['type'] as String,
        userId: json['user_id'] as int,
        userName: json['user_name'] as String? ?? '',
        pdrId: json['pdr_id'] as int,
        pdrName: json['pdr_name'] as String? ?? '',
        pdrAddress: json['pdr_address'] as String? ?? '',
        pdrCommune: json['pdr_commune'] as String? ?? '',
        pdrLat: (json['pdr_lat'] as num?)?.toDouble() ?? 0,
        pdrLng: (json['pdr_lng'] as num?)?.toDouble() ?? 0,
        pdrHours: json['pdr_hours'] as String? ?? '',
        pdrPhone: json['pdr_phone'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        network: json['network'] as String? ?? '',
        networkLabel: json['network_label'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'USD',
        fees: (json['fees'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? '',
        tokenCode: json['token_code'] as String?,
        tokenStatus: json['token_status'] as String?,
        tokenExpiresAt: json['token_expires_at'] as String?,
        ratingStars: json['rating_stars'] as int?,
        ratingComment: json['rating_comment'] as String?,
        createdAt: json['created_at'] as String? ?? '',
        timeline: ((json['timeline'] as List?) ?? []).map((item) => TimelineEvent.fromJson(item as Map<String, dynamic>)).toList(),
      );
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.operationId,
  });

  final int id;
  final String title;
  final String body;
  final bool isRead;
  final String createdAt;
  final int? operationId;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        isRead: json['is_read'] == true,
        createdAt: json['created_at'] as String? ?? '',
        operationId: json['operation_id'] as int?,
      );
}

class RatingItem {
  RatingItem({
    required this.id,
    required this.userName,
    required this.stars,
    required this.comment,
    required this.createdAt,
    this.pdrName,
  });

  final int id;
  final String userName;
  final int stars;
  final String comment;
  final String createdAt;
  final String? pdrName;

  factory RatingItem.fromJson(Map<String, dynamic> json) => RatingItem(
        id: json['id'] as int,
        userName: json['user_name'] as String? ?? '',
        stars: json['stars'] as int? ?? 0,
        comment: json['comment'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        pdrName: json['pdr_name'] as String?,
      );
}

class AppSettings {
  AppSettings({
    required this.feePercent,
    required this.tokenMinutes,
    required this.usdCdfRate,
    required this.banner,
    required this.appVersion,
    required this.appMinVersion,
    required this.appDownloadUrl,
    required this.appUpdateMessage,
  });

  final double feePercent;
  final int tokenMinutes;
  final double usdCdfRate;
  final String banner;
  final String appVersion;
  final String appMinVersion;
  final String appDownloadUrl;
  final String appUpdateMessage;

  static final fallback = AppSettings(
    feePercent: 1,
    tokenMinutes: 30,
    usdCdfRate: 2880,
    banner: '',
    appVersion: '1.0.0',
    appMinVersion: '1.0.0',
    appDownloadUrl: '',
    appUpdateMessage: 'Une nouvelle version de Fast-Cash est disponible. Téléchargez-la pour continuer.',
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        feePercent: (json['fee_percent'] as num?)?.toDouble() ?? 1,
        tokenMinutes: json['token_minutes'] as int? ?? 30,
        usdCdfRate: (json['usd_cdf_rate'] as num?)?.toDouble() ?? 2880,
        banner: json['banner'] as String? ?? '',
        appVersion: json['app_version'] as String? ?? '1.0.0',
        appMinVersion: json['app_min_version'] as String? ?? '1.0.0',
        appDownloadUrl: json['app_download_url'] as String? ?? '',
        appUpdateMessage: json['app_update_message'] as String? ??
            'Une nouvelle version de Fast-Cash est disponible. Téléchargez-la pour continuer.',
      );
}

class SearchResult {
  SearchResult({required this.radiusM, required this.simulated, required this.lat, required this.lng, required this.results});
  final int radiusM;
  final bool simulated;
  final double lat;
  final double lng;
  final List<PdrPoint> results;

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    final origin = json['origin'] as Map<String, dynamic>? ?? {};
    return SearchResult(
      radiusM: json['radius_m'] as int? ?? 0,
      simulated: origin['simulated'] == true,
      lat: (origin['lat'] as num?)?.toDouble() ?? -4.3038,
      lng: (origin['lng'] as num?)?.toDouble() ?? 15.3005,
      results: ((json['results'] as List?) ?? []).map((item) => PdrPoint.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }
}

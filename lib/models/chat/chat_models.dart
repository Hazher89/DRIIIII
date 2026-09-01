import 'package:flutter/material.dart';

enum ChatRoomType {
  maviInternal('mavi_internal'),
  maviGroup('mavi_group'),
  partnerBroadcast('partner_broadcast'),
  partnerPrivate('partner_private'),
  partnerGroup('partner_group'),
  maviPartnerDirect('mavi_partner_direct');

  const ChatRoomType(this.dbValue);
  final String dbValue;

  static ChatRoomType? fromDb(String? value) {
    if (value == null) return null;
    for (final t in values) {
      if (t.dbValue == value) return t;
    }
    return null;
  }

  bool get isPartnerOnly =>
      this == partnerPrivate || this == partnerGroup;

  bool get isGroup =>
      this == maviGroup || this == partnerGroup || this == maviInternal;

  String get labelNorwegian => switch (this) {
        ChatRoomType.maviInternal => 'MAVI internt',
        ChatRoomType.maviGroup => 'MAVI-gruppe',
        ChatRoomType.partnerBroadcast => 'Meldinger fra MAVI',
        ChatRoomType.partnerPrivate => 'Privat chat',
        ChatRoomType.partnerGroup => 'Partner-gruppe',
        ChatRoomType.maviPartnerDirect => 'Direkte til partner',
      };

  String get subtitleNorwegian => switch (this) {
        ChatRoomType.maviInternal => 'Kun MAVI-ansatte',
        ChatRoomType.maviGroup => 'Gruppe — kun MAVI-ansatte',
        ChatRoomType.partnerBroadcast => 'Alle partnere ser meldingene',
        ChatRoomType.partnerPrivate => 'Kun dere — MAVI kan ikke lese',
        ChatRoomType.partnerGroup => 'Gruppe — MAVI kan ikke lese',
        ChatRoomType.maviPartnerDirect => 'MAVI ↔ partner',
      };

  IconData get icon => switch (this) {
        ChatRoomType.maviInternal => Icons.groups_outlined,
        ChatRoomType.maviGroup => Icons.groups,
        ChatRoomType.partnerBroadcast => Icons.campaign_outlined,
        ChatRoomType.partnerPrivate => Icons.lock_outline,
        ChatRoomType.partnerGroup => Icons.group_outlined,
        ChatRoomType.maviPartnerDirect => Icons.support_agent,
      };
}

class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.companyId,
    required this.roomType,
    this.title,
    this.partnerId,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.unreadCount = 0,
    this.isArchived = false,
    this.isPinned = false,
    this.isMuted = false,
  });

  final String id;
  final String companyId;
  final ChatRoomType roomType;
  final String? title;
  final String? partnerId;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final int unreadCount;
  final bool isArchived;
  final bool isPinned;
  final bool isMuted;

  String displayTitle([String? partnerName]) {
    if (title?.trim().isNotEmpty == true) return title!.trim();
    if (partnerName?.trim().isNotEmpty == true) return partnerName!.trim();
    return roomType.labelNorwegian;
  }

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    final prefs = json['chat_user_room_prefs'];
    Map<String, dynamic>? prefMap;
    if (prefs is List && prefs.isNotEmpty) {
      prefMap = Map<String, dynamic>.from(prefs.first as Map);
    } else if (prefs is Map) {
      prefMap = Map<String, dynamic>.from(prefs);
    }

    return ChatRoom(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      roomType: ChatRoomType.fromDb(json['room_type'] as String?) ?? ChatRoomType.maviInternal,
      title: json['title'] as String?,
      partnerId: json['partner_id'] as String?,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.tryParse(json['last_message_at'] as String)?.toLocal()
          : null,
      lastMessagePreview: json['last_message_preview'] as String?,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      isArchived: prefMap?['archived_at'] != null,
      isPinned: prefMap?['pinned_at'] != null,
      isMuted: _isMuted(prefMap?['muted_until']),
    );
  }

  static bool _isMuted(Object? mutedUntil) {
    if (mutedUntil == null) return false;
    final parsed = DateTime.tryParse(mutedUntil.toString());
    if (parsed == null) return false;
    return parsed.isAfter(DateTime.now().toUtc());
  }
}

enum ChatMessageType {
  text('text'),
  image('image'),
  video('video'),
  file('file'),
  system('system');

  const ChatMessageType(this.dbValue);
  final String dbValue;

  static ChatMessageType fromDb(String? v) {
    for (final t in values) {
      if (t.dbValue == v) return t;
    }
    return ChatMessageType.text;
  }
}

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.storagePath,
    required this.mimeType,
    this.fileName,
    this.byteSize,
    this.width,
    this.height,
    this.durationMs,
    this.signedUrl,
  });

  final String id;
  final String storagePath;
  final String mimeType;
  final String? fileName;
  final int? byteSize;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? signedUrl;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as String,
      storagePath: json['storage_path'] as String,
      mimeType: json['mime_type'] as String,
      fileName: json['file_name'] as String?,
      byteSize: (json['byte_size'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      durationMs: (json['duration_ms'] as num?)?.toInt(),
    );
  }

  ChatAttachment copyWith({String? signedUrl}) => ChatAttachment(
        id: id,
        storagePath: storagePath,
        mimeType: mimeType,
        fileName: fileName,
        byteSize: byteSize,
        width: width,
        height: height,
        durationMs: durationMs,
        signedUrl: signedUrl ?? this.signedUrl,
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.messageType = ChatMessageType.text,
    this.senderName,
    this.isEdited = false,
    this.deletedAt,
    this.moderationState = 'active',
    this.replyToId,
    this.replyTo,
    this.attachments = const [],
  });

  final String id;
  final String roomId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final ChatMessageType messageType;
  final String? senderName;
  final bool isEdited;
  final DateTime? deletedAt;
  final String moderationState;
  final String? replyToId;
  final ChatMessage? replyTo;
  final List<ChatAttachment> attachments;

  bool get isDeleted => deletedAt != null;
  bool get isBlocked => moderationState == 'blocked';
  bool get hasMedia => attachments.isNotEmpty;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final attsRaw = json['chat_message_attachments'];
    final attachments = <ChatAttachment>[];
    if (attsRaw is List) {
      for (final a in attsRaw) {
        attachments.add(ChatAttachment.fromJson(Map<String, dynamic>.from(a as Map)));
      }
    }

    return ChatMessage(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      messageType: ChatMessageType.fromDb(json['message_type'] as String?),
      senderName: json['sender_name'] as String?,
      isEdited: json['is_edited'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? DateTime.tryParse(json['deleted_at'] as String)?.toLocal()
          : null,
      moderationState: json['moderation_state'] as String? ?? 'active',
      replyToId: json['reply_to_id'] as String?,
      attachments: attachments,
    );
  }

  ChatMessage copyWith({
    String? senderName,
    ChatMessage? replyTo,
    List<ChatAttachment>? attachments,
  }) =>
      ChatMessage(
        id: id,
        roomId: roomId,
        senderId: senderId,
        body: body,
        createdAt: createdAt,
        messageType: messageType,
        senderName: senderName ?? this.senderName,
        isEdited: isEdited,
        deletedAt: deletedAt,
        moderationState: moderationState,
        replyToId: replyToId,
        replyTo: replyTo ?? this.replyTo,
        attachments: attachments ?? this.attachments,
      );
}

class ChatPartnerDirectoryEntry {
  const ChatPartnerDirectoryEntry({
    required this.userId,
    required this.fullName,
    required this.partnerId,
    required this.partnerName,
    this.accountKind = 'owner',
  });

  final String userId;
  final String fullName;
  final String partnerId;
  final String partnerName;
  final String accountKind;

  String get roleLabel => switch (accountKind) {
        'driver' => 'Sjåfør',
        'staff' => 'Ansatt',
        _ => 'Bil-eier',
      };

  factory ChatPartnerDirectoryEntry.fromJson(Map<String, dynamic> json) =>
      ChatPartnerDirectoryEntry(
        userId: json['user_id'] as String,
        fullName: (json['full_name'] as String?)?.trim() ?? 'Partner',
        partnerId: json['partner_id'] as String,
        partnerName: (json['partner_name'] as String?)?.trim() ?? 'Partner',
        accountKind: (json['account_kind'] as String?) ?? 'owner',
      );
}

class ChatMaviDirectoryEntry {
  const ChatMaviDirectoryEntry({
    required this.userId,
    required this.fullName,
  });

  final String userId;
  final String fullName;

  factory ChatMaviDirectoryEntry.fromJson(Map<String, dynamic> json) =>
      ChatMaviDirectoryEntry(
        userId: json['user_id'] as String,
        fullName: (json['full_name'] as String?)?.trim() ?? 'Ansatt',
      );
}

class ChatPartnerCompanyEntry {
  const ChatPartnerCompanyEntry({
    required this.partnerId,
    required this.partnerName,
    this.ownerName,
  });

  final String partnerId;
  final String partnerName;
  final String? ownerName;

  factory ChatPartnerCompanyEntry.fromJson(Map<String, dynamic> json) =>
      ChatPartnerCompanyEntry(
        partnerId: json['partner_id'] as String,
        partnerName: (json['partner_name'] as String?)?.trim() ?? 'Partner',
        ownerName: json['owner_name'] as String?,
      );
}

class ChatSuperadminDirectory {
  const ChatSuperadminDirectory({
    required this.mavi,
    required this.partners,
    required this.companies,
  });

  final List<ChatMaviDirectoryEntry> mavi;
  final List<ChatPartnerDirectoryEntry> partners;
  final List<ChatPartnerCompanyEntry> companies;

  factory ChatSuperadminDirectory.fromJson(Map<String, dynamic> json) {
    List<T> mapList<T>(dynamic raw, T Function(Map<String, dynamic>) fn) {
      if (raw is! List) return const [];
      return raw.map((e) => fn(Map<String, dynamic>.from(e as Map))).toList();
    }

    return ChatSuperadminDirectory(
      mavi: mapList(json['mavi'], ChatMaviDirectoryEntry.fromJson),
      partners: mapList(json['partners'], ChatPartnerDirectoryEntry.fromJson),
      companies: mapList(json['companies'], ChatPartnerCompanyEntry.fromJson),
    );
  }
}

class ChatPendingMedia {
  const ChatPendingMedia({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    this.isVideo = false,
  });

  final List<int> bytes;
  final String mimeType;
  final String fileName;
  final bool isVideo;
}

class ChatBlockedUser {
  const ChatBlockedUser({
    required this.userId,
    required this.fullName,
    this.blockedAt,
    this.reason,
  });

  final String userId;
  final String fullName;
  final DateTime? blockedAt;
  final String? reason;

  factory ChatBlockedUser.fromJson(Map<String, dynamic> json) => ChatBlockedUser(
        userId: json['user_id'] as String,
        fullName: (json['full_name'] as String?)?.trim() ?? 'Bruker',
        blockedAt: json['blocked_at'] != null
            ? DateTime.tryParse(json['blocked_at'] as String)?.toLocal()
            : null,
        reason: json['reason'] as String?,
      );
}

class ChatAuditEntry {
  const ChatAuditEntry({
    required this.id,
    required this.action,
    this.roomId,
    this.messageId,
    this.targetUserId,
    this.actorId,
    this.createdAt,
  });

  final String id;
  final String action;
  final String? roomId;
  final String? messageId;
  final String? targetUserId;
  final String? actorId;
  final DateTime? createdAt;

  factory ChatAuditEntry.fromJson(Map<String, dynamic> json) => ChatAuditEntry(
        id: json['id'] as String,
        action: json['action'] as String? ?? '',
        roomId: json['room_id'] as String?,
        messageId: json['message_id'] as String?,
        targetUserId: json['target_user_id'] as String?,
        actorId: json['actor_id'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
            : null,
      );

  String get actionLabel => switch (action) {
        'block_user' => 'Blokkerte bruker',
        'unblock_user' => 'Avblokkerte bruker',
        'hide_message' => 'Skjulte melding',
        'remove_member' => 'Fjernet medlem',
        'delete_room' => 'Slettet chat',
        _ => action,
      };
}

class ChatRoomMember {
  const ChatRoomMember({
    required this.userId,
    required this.fullName,
    required this.memberRole,
    this.partnerName,
    this.accountKind = 'owner',
    this.joinedAt,
  });

  final String userId;
  final String fullName;
  final String memberRole;
  final String? partnerName;
  final String accountKind;
  final DateTime? joinedAt;

  String get roleLabel => switch (accountKind) {
        'mavi' => 'MAVI-ansatt',
        'driver' => 'Sjåfør',
        'staff' => 'Ansatt',
        _ => 'Bil-eier',
      };

  String get subtitle {
    final parts = <String>[roleLabel];
    if (partnerName != null && partnerName!.trim().isNotEmpty) {
      parts.add(partnerName!.trim());
    }
    if (memberRole == 'owner') parts.add('Admin');
    return parts.join(' · ');
  }

  factory ChatRoomMember.fromJson(Map<String, dynamic> json) => ChatRoomMember(
        userId: json['user_id'] as String,
        fullName: (json['full_name'] as String?)?.trim() ?? 'Bruker',
        memberRole: json['member_role'] as String? ?? 'member',
        partnerName: json['partner_name'] as String?,
        accountKind: json['account_kind'] as String? ?? 'owner',
        joinedAt: json['joined_at'] != null
            ? DateTime.tryParse(json['joined_at'] as String)?.toLocal()
            : null,
      );
}

class ChatReadReceipt {
  const ChatReadReceipt({
    required this.userId,
    required this.fullName,
    required this.readAt,
  });

  final String userId;
  final String fullName;
  final DateTime readAt;

  factory ChatReadReceipt.fromJson(Map<String, dynamic> json) => ChatReadReceipt(
        userId: json['user_id'] as String,
        fullName: (json['full_name'] as String?)?.trim() ?? 'Bruker',
        readAt: DateTime.parse(json['read_at'] as String).toLocal(),
      );
}

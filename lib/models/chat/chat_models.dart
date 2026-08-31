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
    );
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
  });

  final String userId;
  final String fullName;
  final String partnerId;
  final String partnerName;
}

class ChatMaviDirectoryEntry {
  const ChatMaviDirectoryEntry({
    required this.userId,
    required this.fullName,
  });

  final String userId;
  final String fullName;
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

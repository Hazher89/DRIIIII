/// Handlinger per tilgangsområde (CRUD + godkjenn).
enum AccessAction {
  view,
  create,
  edit,
  delete,
  approve;

  String get dbKey => name;

  String get label => switch (this) {
        AccessAction.view => 'Les',
        AccessAction.create => 'Opprett',
        AccessAction.edit => 'Endre',
        AccessAction.delete => 'Slett',
        AccessAction.approve => 'Godkjenn',
      };

  String get shortLabel => switch (this) {
        AccessAction.view => 'L',
        AccessAction.create => 'O',
        AccessAction.edit => 'E',
        AccessAction.delete => 'S',
        AccessAction.approve => 'G',
      };

  static AccessAction? tryParse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'view':
      case 'read':
      case 'les':
        return AccessAction.view;
      case 'create':
      case 'opprett':
        return AccessAction.create;
      case 'edit':
      case 'update':
      case 'endre':
        return AccessAction.edit;
      case 'delete':
      case 'slett':
        return AccessAction.delete;
      case 'approve':
      case 'godkjenn':
        return AccessAction.approve;
      default:
        return null;
    }
  }

  static const all = [
    AccessAction.view,
    AccessAction.create,
    AccessAction.edit,
    AccessAction.delete,
    AccessAction.approve,
  ];
}

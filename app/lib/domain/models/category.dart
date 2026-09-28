import 'enums.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.icon = 'category',
    this.color = '#64748B',
    this.isDefault = false,
    this.archived = false,
  });

  final String id;
  final String name;
  final CategoryKind kind;
  final String icon;
  final String color;
  final bool isDefault;
  final bool archived;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: CategoryKind.parse(j['kind'] as String?),
    icon: j['icon'] as String? ?? 'category',
    color: j['color'] as String? ?? '#64748B',
    isDefault: j['is_default'] as bool? ?? false,
    archived: j['archived'] as bool? ?? false,
  );
}

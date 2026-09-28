import 'package:flutter/material.dart';

/// Ícones disponíveis para categorias (nome salvo no banco → ícone).
const categoryIcons = <String, IconData>{
  'restaurant': Icons.restaurant_rounded,
  'home': Icons.home_rounded,
  'directions_car': Icons.directions_car_rounded,
  'favorite': Icons.favorite_rounded,
  'celebration': Icons.celebration_rounded,
  'shopping_bag': Icons.shopping_bag_rounded,
  'school': Icons.school_rounded,
  'receipt_long': Icons.receipt_long_rounded,
  'category': Icons.category_rounded,
  'work': Icons.work_rounded,
  'laptop': Icons.laptop_rounded,
  'trending_up': Icons.trending_up_rounded,
  'payments': Icons.payments_rounded,
  'pets': Icons.pets_rounded,
  'fitness_center': Icons.fitness_center_rounded,
  'flight': Icons.flight_rounded,
  'child_care': Icons.child_care_rounded,
  'local_cafe': Icons.local_cafe_rounded,
  'checkroom': Icons.checkroom_rounded,
  'savings': Icons.savings_rounded,
  'account_balance_wallet': Icons.account_balance_wallet_rounded,
  'swap_horiz': Icons.swap_horiz_rounded,
};

const categoryColors = <String>[
  '#F97316',
  '#8B5CF6',
  '#0EA5E9',
  '#EF4444',
  '#EC4899',
  '#F59E0B',
  '#6366F1',
  '#14B8A6',
  '#64748B',
  '#16A34A',
  '#22C55E',
  '#10B981',
  '#84CC16',
  '#A855F7',
];

IconData iconFor(String? name) => categoryIcons[name] ?? Icons.category_rounded;

Color colorFromHex(String? hex, {Color fallback = const Color(0xFF64748B)}) {
  if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return fallback;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, this.icon, this.color, this.size = 42, this.iconData});
  final String? icon;
  final String? color;
  final double size;
  final IconData? iconData;

  @override
  Widget build(BuildContext context) {
    final c = colorFromHex(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(iconData ?? iconFor(icon), color: c, size: size * 0.52),
    );
  }
}

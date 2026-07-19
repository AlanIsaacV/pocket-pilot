// ============================================================
// CategoryIconData — presets de iconos Material 3 para categorías
// ============================================================
//
// Se almacena el codePoint del icono como string hexadecimal en
// CategoryModel.icon (ej. "ef52"). Para renderizar:
//   Icon(CategoryIconData.iconFromHex(model.icon))

import 'package:flutter/material.dart';

abstract final class CategoryIconData {
  /// Convierte un hex codePoint almacenado a IconData.
  /// Devuelve [Icons.category_outlined] si el string es inválido o vacío.
  static IconData iconFromHex(String hex) {
    if (hex.isEmpty) return Icons.category_outlined;
    final code = int.tryParse(hex, radix: 16);
    if (code == null) return Icons.category_outlined;
    return IconData(code, fontFamily: 'MaterialIcons');
  }

  /// Convierte un IconData a string hex para almacenar.
  static String iconToHex(IconData icon) =>
      icon.codePoint.toRadixString(16);

  /// Resuelve un nombre de icono Material a su hex codePoint.
  /// Si [nameOrHex] ya es un hex válido o está vacío, lo devuelve tal cual.
  static String resolveIcon(String nameOrHex) {
    if (nameOrHex.isEmpty) return nameOrHex;
    final icon = _nameToIcon[nameOrHex];
    if (icon != null) return iconToHex(icon);
    return nameOrHex;
  }

  static final Map<String, IconData> _nameToIcon = {
    'shopping_cart': Icons.shopping_cart_outlined,
    'restaurant': Icons.restaurant_outlined,
    'directions_car': Icons.directions_car_outlined,
    'home': Icons.home_outlined,
    'work': Icons.work_outline,
    'school': Icons.school_outlined,
    'fitness_center': Icons.fitness_center_outlined,
    'local_hospital': Icons.local_hospital_outlined,
    'flight': Icons.flight_outlined,
    'movie': Icons.movie_outlined,
    'phone_android': Icons.phone_android_outlined,
    'pets': Icons.pets_outlined,
    'sports_soccer': Icons.sports_soccer_outlined,
    'attach_money': Icons.attach_money_outlined,
    'savings': Icons.savings_outlined,
    'card_giftcard': Icons.card_giftcard_outlined,
    'local_cafe': Icons.local_cafe_outlined,
    'local_gas_station': Icons.local_gas_station_outlined,
    'train': Icons.train_outlined,
    'park': Icons.park_outlined,
    'child_care': Icons.child_care_outlined,
    'local_pharmacy': Icons.local_pharmacy_outlined,
    'music_note': Icons.music_note_outlined,
    'brush': Icons.brush_outlined,
    'camera_alt': Icons.camera_alt_outlined,
    'wifi': Icons.wifi_outlined,
    'electric_bolt': Icons.electric_bolt_outlined,
    'water_drop': Icons.water_drop_outlined,
    'local_laundry_service': Icons.local_laundry_service_outlined,
    'checkroom': Icons.checkroom_outlined,
    'spa': Icons.spa_outlined,
    'sports_esports': Icons.sports_esports_outlined,
    'menu_book': Icons.menu_book_outlined,
    'storefront': Icons.storefront_outlined,
    'local_bar': Icons.local_bar_outlined,
    'bike_scooter': Icons.bike_scooter_outlined,
    'laptop': Icons.laptop_outlined,
    'headphones': Icons.headphones_outlined,
    'volunteer_activism': Icons.volunteer_activism_outlined,
    'receipt_long': Icons.receipt_long_outlined,
    'local_taxi': Icons.local_taxi_outlined,
    'local_parking': Icons.local_parking_outlined,
    'build': Icons.build_outlined,
    'chair': Icons.chair_outlined,
    'yard': Icons.yard_outlined,
    'handyman': Icons.handyman_outlined,
    'weekend': Icons.weekend_outlined,
    'theaters': Icons.theaters_outlined,
    'event': Icons.event_outlined,
    'book': Icons.book_outlined,
    'inventory': Icons.inventory_outlined,
    'category': Icons.category_outlined,
  };

  /// Iconos comunes (~16) — subset inicial visible en el picker.
  static const List<IconData> commonIcons = [
    Icons.shopping_cart_outlined,
    Icons.restaurant_outlined,
    Icons.directions_car_outlined,
    Icons.home_outlined,
    Icons.work_outline,
    Icons.school_outlined,
    Icons.fitness_center_outlined,
    Icons.local_hospital_outlined,
    Icons.flight_outlined,
    Icons.movie_outlined,
    Icons.phone_android_outlined,
    Icons.pets_outlined,
    Icons.sports_soccer_outlined,
    Icons.attach_money_outlined,
    Icons.savings_outlined,
    Icons.card_giftcard_outlined,
  ];

  /// Iconos extendidos (~24 adicionales) — visibles con "Ver más".
  static const List<IconData> extendedIcons = [
    Icons.local_cafe_outlined,
    Icons.local_gas_station_outlined,
    Icons.train_outlined,
    Icons.park_outlined,
    Icons.child_care_outlined,
    Icons.local_pharmacy_outlined,
    Icons.music_note_outlined,
    Icons.brush_outlined,
    Icons.camera_alt_outlined,
    Icons.wifi_outlined,
    Icons.electric_bolt_outlined,
    Icons.water_drop_outlined,
    Icons.local_laundry_service_outlined,
    Icons.checkroom_outlined,
    Icons.spa_outlined,
    Icons.sports_esports_outlined,
    Icons.menu_book_outlined,
    Icons.storefront_outlined,
    Icons.local_bar_outlined,
    Icons.bike_scooter_outlined,
    Icons.laptop_outlined,
    Icons.headphones_outlined,
    Icons.volunteer_activism_outlined,
    Icons.receipt_long_outlined,
  ];
}

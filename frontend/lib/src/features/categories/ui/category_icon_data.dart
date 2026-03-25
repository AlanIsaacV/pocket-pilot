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

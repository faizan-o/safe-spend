import 'package:flutter/material.dart';

/// Maps the icon names stored on categories to Material icons.
IconData iconForKey(String key) {
  switch (key) {
    case 'restaurant':
      return Icons.restaurant;
    case 'shopping_basket':
      return Icons.shopping_basket;
    case 'directions_bus':
      return Icons.directions_bus;
    case 'shopping_bag':
      return Icons.shopping_bag;
    case 'movie':
      return Icons.movie;
    case 'favorite':
      return Icons.favorite;
    case 'school':
      return Icons.school;
    case 'home':
      return Icons.home;
    case 'receipt_long':
      return Icons.receipt_long;
    case 'groups':
      return Icons.groups;
    case 'savings':
      return Icons.savings;
    default:
      return Icons.category;
  }
}

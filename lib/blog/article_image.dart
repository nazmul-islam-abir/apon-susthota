/// Image registry for the blog feature. Kept under `lib/blog/` so the
/// `BlogRepository` can compose articles with their images without a
/// cross-folder import.
///
/// Convention:
///   * Use a public URL (https://...) for a network-loaded image.
///   * Leave the string empty ('') to fall back to the built-in
///     gradient placeholder so the screen never looks broken.
///
/// Edit this file to swap any article's hero / thumb URLs — no other
/// file in the app needs to change.
library;

import 'package:flutter/material.dart';

class ArticleImage {
  final String hero;
  final String thumb;
  final List<Color> gradient;

  const ArticleImage({
    required this.hero,
    required this.thumb,
    this.gradient = const [Color(0xCC0F0F1A), Color(0x6600F0FF)],
  });
}

const Map<String, ArticleImage> kArticleImages = {
  'home_dashboard': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1490645935967-10de6ba17061?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1490645935967-10de6ba17061?w=600&q=80',
  ),
  'role_select': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1576091160550-2173dba999ef?w=600&q=80',
  ),
  'onboarding': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=600&q=80',
  ),
  'meal_plan': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1498837167922-ddd27525d352?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1498837167922-ddd27525d352?w=600&q=80',
  ),
  'meal_details': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=600&q=80',
  ),
  'plan_editor': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=600&q=80',
  ),
  'restricted_foods': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1551024601-bec78aea704b?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1551024601-bec78aea704b?w=600&q=80',
  ),
  'medicine': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1587854692152-cbe660dbde88?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1587854692152-cbe660dbde88?w=600&q=80',
  ),
  'medicine_editor': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1471864190281-a93a3070b6de?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1471864190281-a93a3070b6de?w=600&q=80',
  ),
  'doctor_report': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?w=600&q=80',
  ),
  'water': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1523362628745-0c100150b504?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1523362628745-0c100150b504?w=600&q=80',
  ),
  'water_analytics': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1502740479091-635887520276?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1502740479091-635887520276?w=600&q=80',
  ),
  'workout': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=600&q=80',
  ),
  'workout_details': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=600&q=80',
  ),
  'ai_chat': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1531746790731-6c087fecd65a?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1531746790731-6c087fecd65a?w=600&q=80',
  ),
  'analytics': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=600&q=80',
  ),
  'profile': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=600&q=80',
  ),
  'caretaker_shell': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1581579438747-104c53e7e7a5?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1581579438747-104c53e7e7a5?w=600&q=80',
  ),
  'caretaker_today': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1573497019940-1c28c88b4f3e?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1573497019940-1c28c88b4f3e?w=600&q=80',
  ),
  'patient_inbox': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=600&q=80',
  ),
  'explore': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=600&q=80',
  ),
  'splash': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1505751172876-fa1923c5c528?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1505751172876-fa1923c5c528?w=600&q=80',
  ),
  'auth': ArticleImage(
    hero: 'https://images.unsplash.com/photo-1499951360447-b19be8fe80f5?w=1600&q=80',
    thumb: 'https://images.unsplash.com/photo-1499951360447-b19be8fe80f5?w=600&q=80',
  ),
};

ArticleImage fallbackImage(String id) {
  final entry = kArticleImages[id];
  return entry ?? const ArticleImage(hero: '', thumb: '');
}
// Client for Wikipedia's public REST API (content under CC BY-SA).
import 'dart:convert';

import 'package:http/http.dart' as http;

const _api = 'https://en.wikipedia.org/api/rest_v1';
const _headers = {'Accept': 'application/json', 'Api-User-Agent': 'CurioApp/1.0 (educational fact app)'};

class WikiEvent {
  final int year;
  final String text;
  final String? thumb, pageTitle, pageUrl;
  WikiEvent(this.year, this.text, this.thumb, this.pageTitle, this.pageUrl);
}

class WikiArticle {
  final String title, description, extract, url;
  final String? thumb;
  WikiArticle(this.title, this.description, this.extract, this.url, this.thumb);
}

final Map<String, List<WikiEvent>> _cache = {};

Future<Map<String, dynamic>> _get(String url) async {
  final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 12));
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
}

String _title(Map<String, dynamic> p) {
  final t = p['titles'];
  if (t is Map && t['normalized'] is String) return t['normalized'] as String;
  return (p['normalizedtitle'] as String?) ?? (p['title'] as String).replaceAll('_', ' ');
}

String? _url(Map<String, dynamic> p) {
  final u = p['content_urls'];
  if (u is Map && u['desktop'] is Map) return u['desktop']['page'] as String?;
  return null;
}

Future<List<WikiEvent>> onThisDay(int month, int day) async {
  final key = '$month-$day';
  if (_cache.containsKey(key)) return _cache[key]!;
  final mm = month.toString().padLeft(2, '0'), dd = day.toString().padLeft(2, '0');
  final data = await _get('$_api/feed/onthisday/events/$mm/$dd');
  final out = <WikiEvent>[];
  for (final e in (data['events'] as List? ?? [])) {
    final m = e as Map<String, dynamic>;
    if (m['year'] is! int || m['text'] is! String) continue;
    final pages = (m['pages'] as List?) ?? [];
    final p = pages.isNotEmpty ? pages.first as Map<String, dynamic> : null;
    out.add(WikiEvent(
      m['year'] as int,
      m['text'] as String,
      p?['thumbnail'] is Map ? p!['thumbnail']['source'] as String? : null,
      p != null ? _title(p) : null,
      p != null ? _url(p) : null,
    ));
  }
  _cache[key] = out;
  return out;
}

/// A random article, skipping stubs, lists and disambiguation pages.
Future<WikiArticle?> randomArticle({int tries = 4}) async {
  for (var i = 0; i < tries; i++) {
    final a = await _get('$_api/page/random/summary');
    final extract = a['extract'] as String? ?? '';
    final title = _title(a);
    if (a['type'] != 'standard' || extract.length < 160 || title.startsWith('List of')) continue;
    return WikiArticle(
      title,
      a['description'] as String? ?? '',
      extract,
      _url(a) ?? 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title)}',
      a['thumbnail'] is Map ? a['thumbnail']['source'] as String? : null,
    );
  }
  return null;
}

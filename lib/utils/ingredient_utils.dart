String coreIngredient(String name) {
  name = name.toLowerCase().trim();

  // Remove parentheses
  name = name.replaceAll(RegExp(r'\(.*?\)'), '');

  // Remove non-letter chars
  name = name.replaceAll(RegExp(r'[^a-z\s]'), '');

  // Remove filler words (adjectives, properties)
  const removeWords = [
    "large", "small", "fresh", "raw", "peeled", "chopped", "diced",
    "sliced", "grated", "ground", "whole", "extra", "virgin",
    "boneless", "skinless", "shredded", "washed", "cooked",
    "remove", "skin", "cloves", "leaf", "leaves",

    // Colors
    "red", "green", "yellow", "black", "white", "brown",

    // Useless grocery words
    "pack", "package", "tablespoon", "teaspoon", "cup",
  ];

  for (final w in removeWords) {
    name = name.replaceAll(RegExp("\\b$w\\b"), '');
  }

  name = name.trim();

  if (name.isEmpty) return "";

  // Split into words
  final parts = name.split(RegExp(r'\s+'));

  // If single word → singularize
  if (parts.length == 1) {
    return _singularize(parts[0]);
  }

  // List of generic or useless ending words
  const genericWords = [
    "crumbs", "crumb", "spread", "powder", "paste",
    "juice", "sauce", "mix", "extract"
  ];

  // If first word is good and last is generic → use first
  if (genericWords.contains(parts.last)) {
    return _singularize(parts.first);
  }

  // If last becomes too short (ex: "cap") → return first
  if (parts.last.length <= 3) {
    return _singularize(parts.first);
  }

  // Default: return FIRST meaningful word
  return _singularize(parts.first);
}

String _singularize(String base) {
  if (base.endsWith("ies")) return base.replaceAll(RegExp(r'ies$'), 'y');
  if (base.endsWith("oes")) return base.replaceAll(RegExp(r'oes$'), 'o');
  if (base.endsWith("s")) return base.replaceAll(RegExp(r's$'), '');
  return base;
}

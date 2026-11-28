/// Ordem das categorias da TV ao vivo escolhida pelo usuário (segurar e
/// arrastar na gaveta).
library;

/// Os ids de [provider] na ordem de [saved]. Os que não estão em [saved]
/// (categorias novas do provedor) ficam logo depois da vizinha de antes na
/// lista dele.
List<String> orderCategoryIds(List<String> provider, List<String> saved) {
  if (saved.isEmpty) return provider;
  final present = provider.toSet();
  final order = [
    for (final id in saved)
      if (present.remove(id)) id,
  ];
  for (var i = 0; i < provider.length; i++) {
    if (!present.contains(provider[i])) continue;
    final after = i == 0 ? -1 : order.indexOf(provider[i - 1]);
    order.insert(after + 1, provider[i]);
  }
  return order;
}

/// [id] vai para o lugar de [target]; quem estava no caminho anda uma posição.
List<String> moveCategoryId(List<String> order, String id, String target) {
  final from = order.indexOf(id);
  final to = order.indexOf(target);
  if (from < 0 || to < 0 || from == to) return order;
  return [...order]
    ..removeAt(from)
    ..insert(to, id);
}

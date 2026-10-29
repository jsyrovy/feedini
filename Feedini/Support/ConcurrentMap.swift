extension Collection where Element: Sendable {
    /// Transforms the elements with at most `limit` transforms running at once; the results keep the order of the
    /// elements.
    func concurrentMap<Result: Sendable>(
        limit: Int, _ transform: @escaping @Sendable (Element) async -> Result
    ) async -> [Result] {
        let items = Array(self)
        return await withTaskGroup(of: (Int, Result).self) { group in
            var results = [Result?](repeating: nil, count: items.count)
            var next = 0
            while next < Swift.min(limit, items.count) {
                let index = next
                group.addTask { (index, await transform(items[index])) }
                next += 1
            }
            while let (index, result) = await group.next() {
                results[index] = result
                if next < items.count {
                    let index = next
                    group.addTask { (index, await transform(items[index])) }
                    next += 1
                }
            }
            return results.compactMap { $0 }
        }
    }
}

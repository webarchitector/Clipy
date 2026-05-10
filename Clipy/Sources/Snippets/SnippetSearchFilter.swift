//
//  SnippetSearchFilter.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import RealmSwift

/// Computes the set of node identifiers (snippets + ancestor folders) that
/// should remain visible when the snippets editor outline is filtered by a
/// search query. Empty / whitespace-only query returns nil (no filter
/// active). Matching rule: locale-aware case- and diacritic-insensitive
/// substring against snippet `title` or `content`. Folder titles are not
/// matched directly; folders appear in the result only as ancestors of
/// matched snippets.
enum SnippetSearchFilter {
    static func visibleIdentifiers(query: String, in realm: Realm) -> Set<String>? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let matches = realm.objects(CPYSnippet.self)
            .filter("title CONTAINS[cd] %@ OR content CONTAINS[cd] %@", trimmed, trimmed)
        var result = Set<String>()
        for snippet in matches {
            result.insert(snippet.identifier)
            var pid = snippet.parentIdentifier
            while !pid.isEmpty, !result.contains(pid) {
                result.insert(pid)
                guard let parent = realm.object(ofType: CPYFolder.self, forPrimaryKey: pid) else { break }
                pid = parent.parentIdentifier
            }
        }
        return result
    }
}

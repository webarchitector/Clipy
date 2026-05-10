//
//  SnippetXml.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import RealmSwift
import AEXML

/// Recursive snippet/folder tree import & export. The XML format is the same
/// flat schema Clipy has always shipped, with one addition: a `<folder>` may
/// contain a `<folders>` element listing nested child folders. Old flat XML
/// (without `<folders>`) imports unchanged.
enum SnippetXml {
    /// Returns the number of root folders imported.
    @discardableResult
    static func importDocument(data: Data, into realm: Realm, startingRootIndex: Int) throws -> Int {
        var options = AEXMLOptions()
        options.parserSettings.shouldTrimWhitespace = false
        let xml = try AEXMLDocument(xml: data, options: options)
        var rootIndex = startingRootIndex
        var imported = 0
        try realm.write {
            xml[Constants.Xml.rootElement][Constants.Xml.folderElement].all?.forEach { folderElement in
                importFolder(folderElement, parentId: "", index: rootIndex, in: realm)
                rootIndex += 1
                imported += 1
            }
        }
        return imported
    }

    static func exportDocument(from realm: Realm) -> AEXMLDocument {
        let doc = AEXMLDocument()
        let root = doc.addChild(name: Constants.Xml.rootElement)
        let roots = realm.objects(CPYFolder.self)
            .filter("parentIdentifier == ''")
            .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        for folder in roots {
            exportFolder(folder, into: root, realm: realm)
        }
        return doc
    }

    private static func importFolder(_ element: AEXMLElement, parentId: String, index: Int, in realm: Realm) {
        let folder = CPYFolder()
        folder.title = element[Constants.Xml.titleElement].value ?? "untitled folder"
        folder.parentIdentifier = parentId
        folder.index = index
        realm.add(folder)
        var snippetIndex = 0
        element[Constants.Xml.snippetsElement][Constants.Xml.snippetElement].all?.forEach { sEl in
            let snippet = CPYSnippet()
            snippet.title = sEl[Constants.Xml.titleElement].value ?? "untitled snippet"
            snippet.content = sEl[Constants.Xml.contentElement].value ?? ""
            snippet.parentIdentifier = folder.identifier
            snippet.index = snippetIndex
            realm.add(snippet)
            snippetIndex += 1
        }
        var childIndex = 0
        element[Constants.Xml.foldersElement][Constants.Xml.folderElement].all?.forEach { childEl in
            importFolder(childEl, parentId: folder.identifier, index: childIndex, in: realm)
            childIndex += 1
        }
    }

    private static func exportFolder(_ folder: CPYFolder, into parent: AEXMLElement, realm: Realm) {
        let folderElement = parent.addChild(name: Constants.Xml.folderElement)
        folderElement.addChild(name: Constants.Xml.titleElement, value: folder.title)

        let snippetsElement = folderElement.addChild(name: Constants.Xml.snippetsElement)
        let snippets = realm.objects(CPYSnippet.self)
            .filter("parentIdentifier == %@", folder.identifier)
            .sorted(byKeyPath: #keyPath(CPYSnippet.index), ascending: true)
        for snippet in snippets {
            let sEl = snippetsElement.addChild(name: Constants.Xml.snippetElement)
            sEl.addChild(name: Constants.Xml.titleElement, value: snippet.title)
            sEl.addChild(name: Constants.Xml.contentElement, value: snippet.content)
        }

        let subfolders = realm.objects(CPYFolder.self)
            .filter("parentIdentifier == %@", folder.identifier)
            .sorted(byKeyPath: #keyPath(CPYFolder.index), ascending: true)
        if !subfolders.isEmpty {
            let foldersElement = folderElement.addChild(name: Constants.Xml.foldersElement)
            for sub in subfolders {
                exportFolder(sub, into: foldersElement, realm: realm)
            }
        }
    }
}

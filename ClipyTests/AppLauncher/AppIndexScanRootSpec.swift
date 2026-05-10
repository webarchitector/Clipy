// swiftlint:disable identifier_name

import Quick
import Nimble
import Foundation
@testable import Clipy

class AppIndexScanRootSpec: QuickSpec {
    override class func spec() {
        describe("AppIndex.collectAppNames") {

            // Regression: on recent macOS, /Applications/Safari.app is a
            // symlink into /System/Cryptexes/. The URL-based
            // FileManager.enumerator silently drops it when fetching
            // resource values fails on the cryptex target, so the scan
            // must supplement the enumerator with a top-level
            // contentsOfDirectory pass that picks up plain symlinks.
            it("includes /Applications/Safari.app when the cryptex symlink is present") {
                let fm = FileManager.default
                let safariPath = "/Applications/Safari.app"
                guard fm.fileExists(atPath: safariPath) else { return }
                let attrs = try? fm.attributesOfItem(atPath: safariPath)
                guard (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink else { return }

                let names = AppIndex.collectAppNames(at: "/Applications", maxDepth: 3)
                expect(names).to(contain("Safari"))
            }

            it("returns nested .app bundles up to the requested depth") {
                let fm = FileManager.default
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                    .appendingPathComponent("AppIndexScanRootSpec-\(UUID().uuidString)", isDirectory: true)
                try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: tmp) }

                let topLevel = tmp.appendingPathComponent("Top.app", isDirectory: true)
                try? fm.createDirectory(at: topLevel, withIntermediateDirectories: true)
                let nested = tmp.appendingPathComponent("Sub/Nested.app", isDirectory: true)
                try? fm.createDirectory(at: nested, withIntermediateDirectories: true)

                let names = AppIndex.collectAppNames(at: tmp.path, maxDepth: 3)
                expect(names).to(contain("Top"))
                expect(names).to(contain("Nested"))
            }

            it("respects maxDepth and ignores .app bundles below it") {
                let fm = FileManager.default
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                    .appendingPathComponent("AppIndexScanRootSpec-\(UUID().uuidString)", isDirectory: true)
                try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: tmp) }

                let deep = tmp.appendingPathComponent("a/b/c/Deep.app", isDirectory: true)
                try? fm.createDirectory(at: deep, withIntermediateDirectories: true)

                let names = AppIndex.collectAppNames(at: tmp.path, maxDepth: 1)
                expect(names.contains("Deep")) == false
            }
        }
    }
}

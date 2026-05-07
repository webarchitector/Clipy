import Quick
import Nimble
import Cocoa
@testable import Clipy

class ExcludeAppServiceSpec: QuickSpec {
    override class func spec() {

        // CPYAppInfo's only init is failable from a Cocoa info dict, so wrap.
        func makeAppInfo(identifier: String, name: String = "X") -> CPYAppInfo {
            return CPYAppInfo(info: [
                kCFBundleIdentifierKey as String: identifier as AnyObject,
                kCFBundleNameKey as String: name as AnyObject
            ])!
        }

        describe("ExcludeAppService.applicationCount / application(at:)") {

            it("returns the seeded applications in order") {
                let app1 = makeAppInfo(identifier: "com.example.one", name: "One")
                let app2 = makeAppInfo(identifier: "com.example.two", name: "Two")
                let service = ExcludeAppService(applications: [app1, app2])
                expect(service.applicationCount) == 2
                expect(service.application(at: 0)?.identifier) == "com.example.one"
                expect(service.application(at: 1)?.identifier) == "com.example.two"
            }

            it("returns nil for out-of-range indexes instead of crashing") {
                let service = ExcludeAppService(applications: [])
                expect(service.application(at: 0)).to(beNil())
                expect(service.application(at: -1)).to(beNil())
                expect(service.application(at: 999)).to(beNil())
            }
        }

        describe("ExcludeAppService.copiedProcessIsExcludedApplications(pasteboard:)") {

            // 1Password's macOS bundle identifiers (registered for browser extension hand-off).
            let onePasswordIdentifiers = ["com.agilebits.onepassword-osx", "com.agilebits.onepassword7"]

            // Helper: build an isolated NSPasteboard carrying just the marker types.
            func makePasteboard(types: [String]) -> NSPasteboard {
                let pb = NSPasteboard(name: NSPasteboard.Name(rawValue: "ExcludeAppServiceSpec-\(UUID().uuidString)"))
                pb.declareTypes(types.map { NSPasteboard.PasteboardType($0) }, owner: nil)
                return pb
            }

            it("returns true when 1Password browser extension marks the pasteboard AND the user has the macOS app excluded") {
                let app = makeAppInfo(identifier: "com.agilebits.onepassword-osx", name: "1Password 6")
                let service = ExcludeAppService(applications: [app])
                let pb = makePasteboard(types: ["com.agilebits.onepassword"])
                expect(service.copiedProcessIsExcludedApplications(pasteboard: pb)) == true
            }

            it("returns true for 1Password 7 bundle id too") {
                let app = makeAppInfo(identifier: "com.agilebits.onepassword7", name: "1Password 7")
                let service = ExcludeAppService(applications: [app])
                let pb = makePasteboard(types: ["com.agilebits.onepassword"])
                expect(service.copiedProcessIsExcludedApplications(pasteboard: pb)) == true
            }

            it("returns false when 1Password marker is present but no matching app is in the exclusion list") {
                let unrelated = makeAppInfo(identifier: "com.example.other", name: "Other")
                let service = ExcludeAppService(applications: [unrelated])
                let pb = makePasteboard(types: ["com.agilebits.onepassword"])
                expect(service.copiedProcessIsExcludedApplications(pasteboard: pb)) == false
            }

            it("returns false when the pasteboard has no special markers") {
                _ = onePasswordIdentifiers // touch — keeps the constant referenced if test set shrinks
                let app = makeAppInfo(identifier: "com.agilebits.onepassword-osx")
                let service = ExcludeAppService(applications: [app])
                let pb = makePasteboard(types: [NSPasteboard.PasteboardType.string.rawValue])
                expect(service.copiedProcessIsExcludedApplications(pasteboard: pb)) == false
            }

            it("returns false when the pasteboard is empty") {
                let service = ExcludeAppService(applications: [makeAppInfo(identifier: "com.agilebits.onepassword-osx")])
                let pb = NSPasteboard(name: NSPasteboard.Name(rawValue: "ExcludeAppServiceSpec-empty-\(UUID().uuidString)"))
                expect(service.copiedProcessIsExcludedApplications(pasteboard: pb)) == false
            }
        }

        describe("ExcludeAppService.add / delete") {

            it("appends a new application") {
                let service = ExcludeAppService(applications: [])
                let app = makeAppInfo(identifier: "com.example.foo")
                service.add(with: app)
                expect(service.applicationCount) == 1
                expect(service.application(at: 0)?.identifier) == "com.example.foo"
            }

            it("ignores duplicates (same identifier+name)") {
                let app = makeAppInfo(identifier: "com.example.foo", name: "Foo")
                let service = ExcludeAppService(applications: [app])
                service.add(with: app)
                expect(service.applicationCount) == 1
            }

            it("removes by app info") {
                let app1 = makeAppInfo(identifier: "com.example.one")
                let app2 = makeAppInfo(identifier: "com.example.two")
                let service = ExcludeAppService(applications: [app1, app2])
                service.delete(with: app1)
                expect(service.applicationCount) == 1
                expect(service.application(at: 0)?.identifier) == "com.example.two"
            }

            it("removes by index") {
                let app1 = makeAppInfo(identifier: "com.example.one")
                let app2 = makeAppInfo(identifier: "com.example.two")
                let service = ExcludeAppService(applications: [app1, app2])
                service.delete(with: 0)
                expect(service.applicationCount) == 1
                expect(service.application(at: 0)?.identifier) == "com.example.two"
            }

            it("delete(with: index) is a no-op for out-of-range") {
                let service = ExcludeAppService(applications: [makeAppInfo(identifier: "com.example.foo")])
                service.delete(with: 99)
                expect(service.applicationCount) == 1
            }
        }
    }
}

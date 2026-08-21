import XCTest

/// The uninstall path list exists twice — once in `Uninstaller.tracePaths` for the
/// in-app removal, once in `Scripts/uninstall.sh` for anyone with the repository.
/// Two copies of the same list is the shape of problem this project has already
/// been bitten by: the contrast audit kept its own copy of the palette maths and
/// quietly disagreed with the app for weeks. So the copies are compared by machine
/// rather than by promise, and adding a path to one side alone fails the build.
@MainActor
final class UninstallerTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)          // …/Tests/UninstallerTests.swift
            .deletingLastPathComponent()          // …/Tests
            .deletingLastPathComponent()          // …/
    }

    /// The paths listed between the markers in the shell script, in order.
    private func pathsDeclaredByTheShellScript() throws -> [String] {
        let script = repoRoot.appendingPathComponent("Scripts/uninstall.sh")
        let source = try String(contentsOf: script, encoding: .utf8)

        guard let start = source.range(of: "# BEGIN library-paths"),
              let end = source.range(of: "# END library-paths"),
              start.upperBound < end.lowerBound else {
            XCTFail("the marker comments are gone from Scripts/uninstall.sh — the two lists are no longer comparable")
            return []
        }
        return source[start.upperBound ..< end.lowerBound]
            .split(separator: "\n")
            .compactMap { line in
                guard let open = line.firstIndex(of: "\""),
                      let close = line.lastIndex(of: "\""), open < close else { return nil }
                return String(line[line.index(after: open) ..< close])
            }
    }

    /// The paths the app would remove, as `~/Library`-relative strings.
    private func pathsDeclaredByTheApp() -> [String] {
        let home = URL(fileURLWithPath: "/Users/nobody")
        let prefix = home.appendingPathComponent("Library").path + "/"
        return Uninstaller.tracePaths(home: home).map {
            String($0.path.dropFirst(prefix.count))
        }
    }

    func testTheShellScriptRemovesExactlyTheSamePaths() throws {
        let shell = try pathsDeclaredByTheShellScript()
        let app = pathsDeclaredByTheApp()

        XCTAssertFalse(shell.isEmpty, "no paths were parsed out of the shell script")
        XCTAssertEqual(app, shell,
                       "Uninstaller.tracePaths and Scripts/uninstall.sh disagree about what " +
                       "removing PomoLight means. Whichever you changed, change the other.")
    }

    /// A list that removes things is worth being paranoid about. Nothing in it may
    /// reach outside `~/Library`, and no entry may be the Library folder itself.
    func testEveryPathStaysInsideTheUsersLibrary() {
        let home = URL(fileURLWithPath: "/Users/nobody")
        let library = home.appendingPathComponent("Library").path

        for url in Uninstaller.tracePaths(home: home) {
            let path = url.standardizedFileURL.path
            XCTAssertTrue(path.hasPrefix(library + "/"), "\(path) is not under ~/Library")
            XCTAssertGreaterThan(path.count, library.count + 1, "\(path) is far too broad")
            XCTAssertFalse(path.contains(".."), "\(path) walks upwards")
            XCTAssertFalse(url.lastPathComponent.contains("*"), "\(path) is a wildcard")
        }
    }

    func testNoPathIsListedTwice() {
        let paths = pathsDeclaredByTheApp()
        XCTAssertEqual(Set(paths).count, paths.count, "a path appears more than once: \(paths)")
    }

    /// The settings file is the one thing a current install actually leaves, and
    /// `--keep-settings` in the script relies on it being first in the list.
    func testTheSettingsFileIsTheFirstEntry() {
        XCTAssertEqual(pathsDeclaredByTheApp().first, "Preferences/com.vismo.pomolight.plist")
    }
}

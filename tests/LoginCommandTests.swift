import Foundation

@main
@MainActor
struct LoginCommandTests {
    final class Fixture {
        var state: AppCommandMode.LoginStatus
        var reads = 0, registrations = 0, removals = 0
        var registrationResult: AppCommandMode.LoginStatus = .enabled
        var removalResult: AppCommandMode.LoginStatus = .notRegistered
        var registrationError: Error?
        var removalError: Error?

        init(_ state: AppCommandMode.LoginStatus) { self.state = state }
        var service: AppCommandMode.LoginService {
            .init(status: { self.reads += 1; return self.state }, register: {
                self.registrations += 1
                self.state = self.registrationResult
                if let error = self.registrationError { throw error }
            }, unregister: {
                self.removals += 1
                self.state = self.removalResult
                if let error = self.removalError { throw error }
            })
        }
    }

    static var checked = 0
    static func expect(_ value: Bool, _ name: String) {
        guard value else { fatalError("FAIL: \(name)") }
        checked += 1
    }
    static func invoke(_ fixture: Fixture, _ args: [String]) -> (Int32?, [String: Any]) {
        var lines: [String] = []
        let code = AppCommandMode.run(arguments: args, service: fixture.service, output: { lines.append($0) })
        if code == nil { expect(lines.isEmpty, "unhandled invocation has no output"); return (nil, [:]) }
        expect(lines.count == 1, "one structured result per command")
        let value = try! JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as! [String: Any]
        expect(value["ok"] as? Bool == (code == 0), "JSON success agrees with exit code")
        return (code, value)
    }

    static func main() {
        for args in [[], ["--ui-self-test"], ["--background-measure"], ["--other", "--login", "on"]] {
            let f = Fixture(.notRegistered)
            expect(invoke(f, args).0 == nil && f.reads == 0, "non-login launch leaves app flow untouched")
        }
        for args in [["--login", "--json"], ["--login", "invalid", "--json"],
                     ["--login", "on", "--json", "--force"], ["--login", "on", "--json", "--json"],
                     ["--login", "on", "off", "--json"]] {
            let f = Fixture(.notRegistered)
            let result = invoke(f, args)
            expect(result.0 == 2 && result.1["error"] as? String == "invalid_arguments" && f.reads == 0,
                   "invalid syntax never reads or mutates service")
        }
        for state in [AppCommandMode.LoginStatus.enabled, .notRegistered] {
            let f = Fixture(state)
            let result = invoke(f, ["--login", "status", "--json"])
            expect(result.0 == 0 && result.1["status"] as? String == state.rawValue && f.reads == 1,
                   "status reports registered state")
            expect(f.registrations == 0 && f.removals == 0, "status is read-only")
        }
        for action in ["on", "off"] {
            let f = Fixture(action == "on" ? .notRegistered : .enabled)
            let refused = invoke(f, ["--login", action, "--json"])
            expect(refused.0 == 3 && refused.1["confirmation_required"] as? Bool == true,
                   "write requires explicit confirmation")
            let preview = invoke(f, ["--login", action, "--json", "--dry-run", "--yes"])
            expect(preview.0 == 0 && preview.1["would_change"] as? Bool == true
                   && preview.1["changed"] as? Bool == false && f.registrations == 0 && f.removals == 0,
                   "dry-run never registers even with yes")
            let applied = invoke(f, ["--login", action, "--json", "--yes"])
            expect(applied.0 == 0 && applied.1["changed"] as? Bool == true
                   && f.state == (action == "on" ? .enabled : .notRegistered), "confirmed operation reads back requested state")
            let noop = invoke(f, ["--login", action, "--json", "--yes"])
            expect(noop.0 == 0 && noop.1["changed"] as? Bool == false
                   && f.registrations + f.removals == 1, "repeat request is idempotent")
        }
        for action in ["status", "on"] {
            let f = Fixture(.requiresApproval)
            let result = invoke(f, ["--login", action, "--json", "--yes"])
            expect(result.0 == 4 && result.1["requires_approval"] as? Bool == true
                   && result.1["next_step"] as? String != nil && f.registrations == 0,
                   "pending approval is explicit and cannot be bypassed")
        }
        let pending = Fixture(.notRegistered)
        pending.registrationResult = .requiresApproval
        let approval = invoke(pending, ["--login", "on", "--json", "--yes"])
        expect(approval.0 == 4 && pending.reads == 2 && approval.1["changed"] as? Bool == true,
               "registration returning success still checks pending approval")
        expect(invoke(pending, ["--login", "off", "--json", "--yes"]).0 == 0 && pending.removals == 1,
               "off withdraws a pending registration")
        for state in [AppCommandMode.LoginStatus.notFound, .unknown] {
            let f = Fixture(state)
            let result = invoke(f, ["--login", "on", "--json", "--yes"])
            expect(result.0 == 1 && result.1["error"] as? String == "service_unavailable"
                   && f.registrations == 0, "unavailable service fails closed")
        }
        let failure = Fixture(.notRegistered)
        failure.registrationError = NSError(domain: "LoginFixture", code: 42)
        let failed = invoke(failure, ["--login", "on", "--json", "--yes"])
        expect(failed.0 == 1 && failure.reads == 2 && failed.1["status"] as? String == "enabled"
               && failed.1["changed"] as? Bool == true && failed.1["service_error"] is [String: Any],
               "throwing write preserves error and actual partially changed state")
        let removal = Fixture(.enabled)
        removal.removalResult = .enabled
        removal.removalError = NSError(domain: "LoginFixture", code: 43)
        let removalFailure = invoke(removal, ["--login", "off", "--json", "--yes"])
        expect(removalFailure.0 == 1 && removal.reads == 2 && removalFailure.1["changed"] as? Bool == false,
               "failed removal is read back without claiming success")
        let mismatch = Fixture(.notRegistered)
        mismatch.registrationResult = .notRegistered
        let mismatchResult = invoke(mismatch, ["--login", "on", "--json", "--yes"])
        expect(mismatchResult.0 == 1 && mismatchResult.1["error"] as? String == "state_mismatch",
               "API success alone cannot claim enabled")
        var text = ""
        let human = Fixture(.enabled)
        expect(AppCommandMode.run(arguments: ["--login", "status"], service: human.service,
                                  output: { text = $0 }) == 0 && !text.isEmpty && !text.hasPrefix("{"),
               "plain status is readable without JSON")
        print("Login command: \(checked) fixture assertions passed; no real login-item registration")
    }
}

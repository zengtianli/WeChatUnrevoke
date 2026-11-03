import Foundation

@main
enum ProcessControlTests {
    static func main() {
        var requests: [String] = []
        var polls = 0
        let fixture = WeChatProcessControl(requestQuit: { requests.append($0); return true },
                                          reopen: { _ in fatalError("quit must not reopen by itself") }, pause: {})
        precondition(fixture.quitAndWait(target: "/fixture/WeChat.app") {
            polls += 1; return polls < 3
        })
        precondition(requests == ["/fixture/WeChat.app"] && polls == 3)
        polls = 0
        precondition(!fixture.quitAndWait(target: "/fixture/WeChat.app") { polls += 1; return true })
        precondition(polls == 20)
        precondition(!fixture.quitAndWait(target: "/fixture/WeChat.app") { nil })
        let refused = WeChatProcessControl(requestQuit: { _ in false }, reopen: { _ in false }, pause: {})
        precondition(!refused.quitAndWait(target: "/fixture/WeChat.app") { fatalError("a refusal must not poll") })
        print("PASS: selected target, cooperative refusal, helper drain, timeout and failed readback")
    }
}

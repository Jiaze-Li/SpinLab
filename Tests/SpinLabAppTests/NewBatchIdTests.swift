import Testing
@testable import SpinLabApp

@Suite("New batch id: prefix and number")
struct NewBatchIdTests {
    @Test("A prefix and digits make the batch id; anything unfinished or not digits makes none")
    func composes() {
        #expect(NewBatchId.compose(prefix: "PN", number: "117") == "PN117")
        #expect(NewBatchId.compose(prefix: "PN", number: " 117 ") == "PN117")
        #expect(NewBatchId.compose(prefix: "PN", number: "") == "")
        #expect(NewBatchId.compose(prefix: "PN", number: "117/SRO1") == "")
        #expect(NewBatchId.compose(prefix: "PN", number: "1a") == "")
    }

    @Test("An existing id splits into the longest known prefix and its digits")
    func splits() {
        let prefixes = ["S", "SL", "PN"]
        #expect(NewBatchId.split("SL105", prefixes: prefixes)?.prefix == "SL")
        #expect(NewBatchId.split("SL105", prefixes: prefixes)?.number == "105")
        #expect(NewBatchId.split("PN106/SRO1", prefixes: prefixes) == nil)
        #expect(NewBatchId.split("XX1", prefixes: prefixes) == nil)
    }
}

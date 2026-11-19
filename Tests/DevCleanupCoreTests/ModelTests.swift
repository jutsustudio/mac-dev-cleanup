import Foundation
import Testing
@testable import DevCleanupCore

@Test func ruleIDsAreUnique() {
    let ids = Catalog.all.map(\.id)
    #expect(Set(ids).count == ids.count)
}

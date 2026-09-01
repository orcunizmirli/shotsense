import ShotCore
import ShotCoreTestSupport
import Testing
@testable import LibraryKit

@MainActor
@Suite("LibraryViewModel")
struct LibraryViewModelTests {
    @Test("İzin yoksa izin ekranı gösterilir, boş ekran değil")
    func permissionStateIsDistinctFromEmpty() async {
        // 02 §3: bu ikisi karışırsa kullanıcı ne yapacağını bilemez.
        let source = FakeShotSource(authorization: .denied)
        let model = LibraryViewModel(
            dependencies: TestDependencies.make(index: FakeIndex(), source: source)
        )

        await model.load()

        #expect(model.state == .permissionRequired)
    }

    @Test("İzin var ama kayıt yoksa boş durum")
    func emptyStateWhenNoShots() async {
        let model = LibraryViewModel(dependencies: TestDependencies.make(index: FakeIndex()))
        await model.load()
        #expect(model.state == .empty)
    }

    @Test("Kayıtlar yeniden eskiye sıralanır")
    func contentIsSortedNewestFirst() async throws {
        let index = FakeIndex(shots: [
            TestDependencies.shot(identifier: "eski", createdAt: TestDependencies.epoch.addingTimeInterval(-86400)),
            TestDependencies.shot(identifier: "yeni", createdAt: TestDependencies.epoch),
        ])
        let model = LibraryViewModel(dependencies: TestDependencies.make(index: index))

        await model.load()

        guard case let .content(shots) = model.state else {
            Issue.record("içerik bekleniyordu, \(model.state) geldi")
            return
        }
        #expect(shots.map(\.assetIdentifier) == ["yeni", "eski"])
    }

    @Test("Kategori seçimi listeyi süzer")
    func categorySelectionFilters() async {
        let index = FakeIndex(shots: [
            TestDependencies.shot(identifier: "fis", category: .receipt),
            TestDependencies.shot(identifier: "bilet", category: .ticket),
        ])
        let model = LibraryViewModel(dependencies: TestDependencies.make(index: index))
        await model.load()

        await model.select(category: .ticket)

        guard case let .content(shots) = model.state else {
            Issue.record("içerik bekleniyordu")
            return
        }
        #expect(shots.map(\.assetIdentifier) == ["bilet"])
    }

    @Test("Yalnız kitaplıkta bulunan kategoriler çip olarak gösterilir")
    func onlyPresentCategoriesAreOffered() async {
        // Boş kategoriye tıklayıp boş ekranla karşılaşmak kötü bir deneyimdir.
        let index = FakeIndex(shots: [TestDependencies.shot(category: .receipt)])
        let model = LibraryViewModel(dependencies: TestDependencies.make(index: index))

        await model.load()

        #expect(model.availableCategories == [.receipt])
    }

    @Test("İndeks hatası hata durumuna düşürür")
    func indexFailureShowsError() async {
        let index = FakeIndex()
        await index.setShouldFail(true)
        let model = LibraryViewModel(dependencies: TestDependencies.make(index: index))

        await model.load()

        guard case .failed = model.state else {
            Issue.record("hata durumu bekleniyordu, \(model.state) geldi")
            return
        }
    }

    @Test("Sınırlı erişimde kitaplık yine yüklenir")
    func limitedAccessStillLoads() async {
        let source = FakeShotSource(authorization: .limited)
        let index = FakeIndex(shots: [TestDependencies.shot()])
        let model = LibraryViewModel(
            dependencies: TestDependencies.make(index: index, source: source)
        )

        await model.load()

        #expect(model.state != .permissionRequired)
    }
}

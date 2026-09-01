import EventKit
import Testing
@testable import ActionKit

@Suite("EventKitAccessPolicy")
struct EventKitAccessPolicyTests {
    @Test("Sorulmamışsa izin istenir")
    func notDeterminedRequests() {
        #expect(EventKitAccessPolicy.remindersDecision(for: .notDetermined) == .request)
        #expect(EventKitAccessPolicy.calendarDecision(for: .notDetermined) == .request)
    }

    @Test("Reddedilmişse tekrar sorulmaz")
    func deniedDoesNotRequestAgain() {
        // Reddedilmiş izni tekrar istemek sistem diyaloğunu göstermez; kullanıcıya
        // Ayarlar'a gitmesi söylenmelidir.
        #expect(EventKitAccessPolicy.remindersDecision(for: .denied) == .denied)
        #expect(EventKitAccessPolicy.calendarDecision(for: .restricted) == .denied)
    }

    @Test("Takvimde yazma-yalnız erişim yeterlidir")
    func calendarAcceptsWriteOnly() {
        // Uygulama kullanıcının etkinliklerini okumaz; daha geniş izin istemek yanlış olur.
        #expect(EventKitAccessPolicy.calendarDecision(for: .writeOnly) == .proceed)
    }

    @Test("Hatırlatıcılarda yazma-yalnız yetmez")
    func remindersRequireFullAccess() {
        // EventKit hatırlatıcılar için yazma-yalnız erişim sunmaz; bunu kabul etmek
        // çalışmayan bir düğme yaratırdı.
        #expect(EventKitAccessPolicy.remindersDecision(for: .writeOnly) == .denied)
    }

    @Test("Tam erişimde ikisi de devam eder")
    func fullAccessProceeds() {
        #expect(EventKitAccessPolicy.remindersDecision(for: .fullAccess) == .proceed)
        #expect(EventKitAccessPolicy.calendarDecision(for: .fullAccess) == .proceed)
    }
}

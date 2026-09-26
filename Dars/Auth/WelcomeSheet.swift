import SwiftUI

struct WelcomePage: View {
    let role: Role
    let onDone: () -> Void
    @State private var leaving = false

    private struct Row: Identifiable {
        let icon: String
        let title: String
        let body: String
        var id: String { title }
    }

    private var rows: [Row] {
        func r(_ icon: String, _ key: String) -> Row { Row(icon: icon, title: L("\(key)_title"), body: L("\(key)_body")) }
        switch role {
        case .student: return [r("Filled.WbSunny", "welcome_student_1"), r("Filled.Backpack", "welcome_student_2"), r("Filled.NotificationsActive", "welcome_student_3")]
        case .parent: return [r("Filled.FamilyRestroom", "welcome_parent_1"), r("Filled.CalendarMonth", "welcome_parent_2"), r("Filled.Summarize", "welcome_parent_3")]
        case .teacher: return [r("Filled.Today", "welcome_teacher_1"), r("Filled.HowToReg", "welcome_teacher_2"), r("Filled.PostAdd", "welcome_teacher_3")]
        case .admin: return [r("Filled.Insights", "welcome_admin_1"), r("Filled.Groups", "welcome_admin_2"), r("Filled.Campaign", "welcome_admin_3")]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 48)
                    HeroMark().darsEnterHero()
                    Spacer().frame(height: 28)
                    Text(verbatim: L("welcome_title"))
                        .font(.system(size: 24, weight: .bold))
                        .darsTracking(-0.2)
                        .foregroundStyle(Tokens.text)
                        .multilineTextAlignment(.center)
                        .darsEnter(delay: 0.09)
                        .accessibilityAddTraits(.isHeader)
                    Spacer().frame(height: 36)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .top, spacing: 18) {
                            MaterialIcon(row.icon, size: 32).foregroundStyle(Tokens.accentText).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: row.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Tokens.text)
                                Text(verbatim: row.body).font(.system(size: 15)).foregroundStyle(Tokens.textMuted)
                            }
                            Spacer(minLength: 0)
                        }
                        .darsStagger(index, step: 0.09, delay: 0.2)
                        if index < 2 { Spacer().frame(height: 26) }
                    }
                    Spacer().frame(height: 24)
                }
            }
            .scrollIndicators(.hidden)
            MotionPrimaryButton(title: LocalizedStringKey(L("welcome_start")), enabled: !leaving) {
                guard !leaving else { return }
                leaving = true
                onDone()
            }
            .padding(.bottom, 20)
            .darsEnter(delay: 0.42)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.bg.ignoresSafeArea())
    }
}

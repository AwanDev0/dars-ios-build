import SwiftUI

struct ShellView: View {
    let profile: Profile
    @Environment(\.horizontalSizeClass) private var width
    @State private var selected = "home"
    @State private var teacher = TeacherStore()
    @Environment(PushRegistrar.self) private var push

    var body: some View {
        Group {
            if width == .regular {
                NavigationSplitView {
                    SidebarTabs(tabs: tabs, selected: $selected)
                } detail: {
                    page
                        .background(DarsColor.backgroundBase.ignoresSafeArea())
                }
            } else {
                ZStack(alignment: .bottom) {
                    page
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    CapsuleTabBar(tabs: tabs, selected: $selected)
                }
                .background(DarsColor.backgroundBase.ignoresSafeArea())
            }
        }
        .environment(teacher)
        .task {
            if profile.role == .teacher { await teacher.load(me: profile) }
        }
        .onChange(of: push.pendingTab) { _, wanted in
            guard let wanted, tabs.contains(where: { $0.id == wanted }) else { return }
            withAnimation(Motion.arrive) { selected = wanted }
            push.pendingTab = nil
        }
    }

    @ViewBuilder
    private var page: some View {
        switch profile.role {
        case .student: student
        case .parent:  parent
        case .teacher: teacherPages
        case .admin:   admin
        }
    }

    @ViewBuilder private var student: some View {
        switch selected {
        case "home":     TodayView(profile: profile)
        case "schedule": NavigationStack { ScheduleView(profile: profile) }
        case "work":     NavigationStack { WorkView(profile: profile) }
        case "marks":    NavigationStack { MarksView(profile: profile) }
        default:         shared
        }
    }

    @ViewBuilder private var parent: some View {
        switch selected {
        case "home": ParentHomeView(profile: profile)
        default:     shared
        }
    }

    @ViewBuilder private var teacherPages: some View {
        switch selected {
        case "home":    TeacherHomeView(profile: profile)
        case "classes": TeacherClassesView(profile: profile)
        case "post":    PostComposerView(profile: profile)
        default:        shared
        }
    }

    @ViewBuilder private var admin: some View {
        switch selected {
        case "home": AdminOverviewView(profile: profile)
        case "people":
            NavigationStack {
                AdminPeopleView(me: profile)
                    .navigationDestination(for: AdminRoute.self) { AdminRouter(route: $0, me: profile) }
            }
        case "classes":
            NavigationStack {
                AdminClassesView(me: profile)
                    .navigationDestination(for: AdminRoute.self) { AdminRouter(route: $0, me: profile) }
            }
        default: shared
        }
    }

    @ViewBuilder private var shared: some View {
        switch selected {
        case "messages": ConversationsView(profile: profile)
        case "profile":  ProfileView(profile: profile)
        default:         TabPlaceholder(title: tabs.first { $0.id == selected }?.title ?? "")
        }
    }

    private var tabs: [DarsTab] {
        switch profile.role {
        case .student:
            return [
                DarsTab(id: "home", title: "Home", symbol: "house", selectedSymbol: "house.fill"),
                DarsTab(id: "schedule", title: "Schedule", symbol: "calendar", selectedSymbol: "calendar"),
                DarsTab(id: "work", title: "Work", symbol: "text.book.closed", selectedSymbol: "text.book.closed.fill"),
                DarsTab(id: "marks", title: "Marks", symbol: "chart.bar", selectedSymbol: "chart.bar.fill"),
                DarsTab(id: "messages", title: "Chat", symbol: "bubble.left", selectedSymbol: "bubble.left.fill"),
                DarsTab(id: "profile", title: "Profile", symbol: "person.circle", selectedSymbol: "person.circle.fill"),
            ]
        case .parent:
            return [
                DarsTab(id: "home", title: "Children", symbol: "figure.2.and.child.holdinghands", selectedSymbol: "figure.2.and.child.holdinghands"),
                DarsTab(id: "messages", title: "Chat", symbol: "bubble.left", selectedSymbol: "bubble.left.fill"),
                DarsTab(id: "profile", title: "Profile", symbol: "person.circle", selectedSymbol: "person.circle.fill"),
            ]
        case .teacher:
            return [
                DarsTab(id: "home", title: "Home", symbol: "house", selectedSymbol: "house.fill"),
                DarsTab(id: "classes", title: "Classes", symbol: "books.vertical", selectedSymbol: "books.vertical.fill"),
                DarsTab(id: "post", title: "Post", symbol: "plus.circle", selectedSymbol: "plus.circle.fill"),
                DarsTab(id: "messages", title: "Chat", symbol: "bubble.left", selectedSymbol: "bubble.left.fill"),
                DarsTab(id: "profile", title: "Profile", symbol: "person.circle", selectedSymbol: "person.circle.fill"),
            ]
        case .admin:
            return [
                DarsTab(id: "home", title: "Overview", symbol: "chart.bar", selectedSymbol: "chart.bar.fill"),
                DarsTab(id: "people", title: "People", symbol: "person.2", selectedSymbol: "person.2.fill"),
                DarsTab(id: "classes", title: "Classes", symbol: "books.vertical", selectedSymbol: "books.vertical.fill"),
                DarsTab(id: "messages", title: "Chat", symbol: "bubble.left", selectedSymbol: "bubble.left.fill"),
                DarsTab(id: "profile", title: "Profile", symbol: "person.circle", selectedSymbol: "person.circle.fill"),
            ]
        }
    }
}

struct TabPlaceholder: View {
    let title: LocalizedStringKey
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "hammer")
        } description: {
            Text("Next milestone.")
        }
    }
}

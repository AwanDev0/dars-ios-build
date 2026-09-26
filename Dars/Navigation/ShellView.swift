import SwiftUI

struct ShellView: View {
    let profile: Profile
    @Environment(\.horizontalSizeClass) private var width
    @State private var selected = "home"
    @State private var visited: Set<String> = ["home"]
    @State private var barHidden = false
    @State private var teacher = TeacherStore()
    @Environment(PushRegistrar.self) private var push

    var body: some View {
        Group {
            if width == .regular {
                NavigationSplitView {
                    SidebarTabs(tabs: tabs, selected: $selected)
                } detail: {
                    pages
                        .background(DarsColor.backgroundBase.ignoresSafeArea())
                }
            } else {
                ZStack(alignment: .bottom) {
                    pages
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            Color.clear.frame(height: barHidden ? 0 : 66)
                        }
                    if !barHidden {
                        CapsuleTabBar(tabs: tabs, selected: $selected)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .background(DarsColor.backgroundBase.ignoresSafeArea())
                .onPreferenceChange(HidesTabBarKey.self) { hidden in
                    Task { @MainActor in
                        withAnimation(Motion.decelerate) { barHidden = hidden }
                    }
                }
            }
        }
        .environment(teacher)
        .task {
            if profile.role == .teacher { await teacher.load(me: profile) }
        }
        .onChange(of: selected) { _, now in visited.insert(now) }
        .onChange(of: push.pendingTab) { _, wanted in
            guard let wanted, tabs.contains(where: { $0.id == wanted }) else { return }
            withAnimation(Motion.arrive) { selected = wanted }
            push.pendingTab = nil
        }
    }

    private var pages: some View {
        ZStack {
            ForEach(tabs) { tab in
                if visited.contains(tab.id) {
                    let on = tab.id == selected
                    page(tab.id)
                        .transformPreference(HidesTabBarKey.self) { if !on { $0 = false } }
                        .opacity(on ? 1 : 0)
                        .allowsHitTesting(on)
                        .accessibilityHidden(!on)
                        .zIndex(on ? 1 : 0)
                }
            }
        }
    }

    @ViewBuilder
    private func page(_ id: String) -> some View {
        switch profile.role {
        case .student: student(id)
        case .parent:  parent(id)
        case .teacher: teacherPages(id)
        case .admin:   admin(id)
        }
    }

    @ViewBuilder private func student(_ id: String) -> some View {
        switch id {
        case "home":     TodayView(profile: profile)
        case "schedule": NavigationStack { ScheduleView(profile: profile) }
        case "work":     NavigationStack { WorkView(profile: profile) }
        case "marks":    NavigationStack { MarksView(profile: profile) }
        default:         shared(id)
        }
    }

    @ViewBuilder private func parent(_ id: String) -> some View {
        switch id {
        case "home": ParentHomeView(profile: profile)
        default:     shared(id)
        }
    }

    @ViewBuilder private func teacherPages(_ id: String) -> some View {
        switch id {
        case "home":    TeacherHomeView(profile: profile)
        case "classes": TeacherClassesView(profile: profile)
        case "post":    PostComposerView(profile: profile)
        default:        shared(id)
        }
    }

    @ViewBuilder private func admin(_ id: String) -> some View {
        switch id {
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
        default: shared(id)
        }
    }

    @ViewBuilder private func shared(_ id: String) -> some View {
        switch id {
        case "messages": ConversationsView(profile: profile)
        case "profile":  ProfileView(profile: profile)
        default:         TabPlaceholder(title: tabs.first { $0.id == id }?.title ?? "")
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
